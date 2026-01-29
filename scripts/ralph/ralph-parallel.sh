#!/usr/bin/env bash
# =============================================================================
# ralph-parallel.sh - Launch multiple Ralph instances in parallel
# =============================================================================
#
# DESCRIPTION:
#   Launches multiple Ralph instances for parallel story processing.
#   Manages instance lifecycle with start, stop, and status commands.
#
# USAGE:
#   ./ralph-parallel.sh [command] [args]
#
# COMMANDS:
#   <N>             Launch N instances (default: CPU cores / 2)
#   stop            Stop all running instances gracefully
#   kill            Force kill all running instances
#   status          Show running instances
#   dashboard       Launch dashboard to monitor instances
#   help            Show this help
#
# EXAMPLES:
#   ./ralph-parallel.sh 3       # Launch 3 instances
#   ./ralph-parallel.sh stop    # Stop all instances
#   ./ralph-parallel.sh status  # Show status
#
# ENVIRONMENT:
#   RALPH_MAX_INSTANCES  Maximum instances to launch (default: 8)
#   RALPH_ITERATIONS     Max iterations per instance (default: 10)
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - jq (for JSON parsing)
#
# =============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
# shellcheck source=ralph-utils.sh
source "$SCRIPT_DIR/ralph-utils.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Load paths
eval "$(get_ralph_paths)"

PIDS_FILE="$INSTANCES_DIR/running.pids"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

show_help() {
    echo ""
    write_colored cyan "Usage: ./ralph-parallel.sh <command> [args]"
    echo ""
    write_colored yellow "Commands:"
    echo "  <N>             Launch N instances (default: CPU cores / 2)"
    echo "  stop            Stop all running instances gracefully"
    echo "  kill            Force kill all running instances"
    echo "  status          Show running instances"
    echo "  dashboard       Launch dashboard to monitor instances"
    echo "  help            Show this help"
    echo ""
    write_colored yellow "Examples:"
    echo "  ./ralph-parallel.sh 3       # Launch 3 instances"
    echo "  ./ralph-parallel.sh stop    # Stop all instances"
    echo "  ./ralph-parallel.sh status  # Show status"
    echo ""
    write_colored yellow "Environment Variables:"
    echo "  RALPH_MAX_INSTANCES  Maximum instances to launch (default: 8)"
    echo "  RALPH_ITERATIONS     Max iterations per instance (default: 10)"
    echo ""
}

get_cpu_count() {
    if command -v nproc &>/dev/null; then
        nproc
    elif [[ -f /proc/cpuinfo ]]; then
        grep -c ^processor /proc/cpuinfo
    elif command -v sysctl &>/dev/null; then
        sysctl -n hw.ncpu 2>/dev/null || echo "4"
    else
        echo "4"
    fi
}

get_default_count() {
    local cpus
    cpus=$(get_cpu_count)
    local default=$((cpus / 2))
    [[ "$default" -lt 1 ]] && default=1
    echo "$default"
}

save_pid() {
    local pid="$1"
    mkdir -p "$INSTANCES_DIR"
    echo "$pid" >> "$PIDS_FILE"
}

load_pids() {
    if [[ -f "$PIDS_FILE" ]]; then
        sort -u "$PIDS_FILE"
    fi
}

clean_pids() {
    local active_pids=""
    local pid
    for pid in $(load_pids); do
        if kill -0 "$pid" 2>/dev/null; then
            active_pids="${active_pids}${pid}"$'\n'
        fi
    done

    mkdir -p "$INSTANCES_DIR"
    echo "$active_pids" | grep -v '^$' > "$PIDS_FILE" 2>/dev/null || true
}

# =============================================================================
# COMMAND FUNCTIONS
# =============================================================================

cmd_launch() {
    local count="${1:-$(get_default_count)}"
    local max_instances="${RALPH_MAX_INSTANCES:-8}"
    local iterations="${RALPH_ITERATIONS:-10}"

    # Validate count
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        write_colored red "Error: Invalid count '$count'"
        exit 1
    fi

    if [[ "$count" -gt "$max_instances" ]]; then
        write_colored yellow "Warning: Limiting to $max_instances instances (RALPH_MAX_INSTANCES)"
        count="$max_instances"
    fi

    if [[ "$count" -lt 1 ]]; then
        write_colored red "Error: Count must be at least 1"
        exit 1
    fi

    write_colored blue "╔═══════════════════════════════════════════════════════╗"
    echo -e "${COLOR_BLUE}║${COLOR_RESET}         ${COLOR_CYAN}RALPH PARALLEL LAUNCHER${COLOR_RESET}                       ${COLOR_BLUE}║${COLOR_RESET}"
    write_colored blue "╚═══════════════════════════════════════════════════════╝"
    echo ""
    echo -e "Launching ${COLOR_GREEN}$count${COLOR_RESET} instances with ${COLOR_GREEN}$iterations${COLOR_RESET} iterations each..."
    echo ""

    mkdir -p "$INSTANCES_DIR"

    local i
    for i in $(seq 1 "$count"); do
        # Small delay between launches to avoid race conditions
        [[ "$i" -gt 1 ]] && sleep 1

        write_colored cyan "  Starting instance $i/$count..."

        # Launch in background with nohup
        nohup "$SCRIPT_DIR/ralph.sh" "$iterations" \
            > /dev/null 2>&1 &

        local pid=$!
        save_pid "$pid"

        echo -e "    ${COLOR_GREEN}✓${COLOR_RESET} PID: $pid"
    done

    echo ""
    write_colored green "Launched $count instances"
    echo ""
    echo "Monitor with:"
    echo "  $0 status"
    echo "  $SCRIPT_DIR/ralph-dashboard.sh"
    echo ""
    echo "Stop with:"
    echo "  $0 stop"
}

cmd_stop() {
    write_colored yellow "Stopping all Ralph instances..."

    clean_pids
    local pids
    pids=$(load_pids)
    local count=0

    local pid
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Sending SIGTERM to PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
            ((count++)) || true
        fi
    done

    if [[ "$count" -eq 0 ]]; then
        write_colored green "No running instances found"
    else
        echo ""
        write_colored yellow "Sent SIGTERM to $count instances"
        echo "Waiting for graceful shutdown (10s timeout)..."

        # Wait for processes to exit
        local timeout=10
        local waited=0
        while [[ "$waited" -lt "$timeout" ]]; do
            sleep 1
            ((waited++)) || true

            local still_running=0
            for pid in $pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    ((still_running++)) || true
                fi
            done

            if [[ "$still_running" -eq 0 ]]; then
                break
            fi

            echo "  Still running: $still_running"
        done

        # Check if any still running
        local remaining=0
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                ((remaining++)) || true
            fi
        done

        if [[ "$remaining" -gt 0 ]]; then
            write_colored yellow "$remaining instances still running. Use '$0 kill' to force kill."
        else
            write_colored green "All instances stopped"
        fi
    fi

    # Clean up PID file
    clean_pids
}

cmd_kill() {
    write_colored red "Force killing all Ralph instances..."

    clean_pids
    local pids
    pids=$(load_pids)
    local count=0

    local pid
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "  Sending SIGKILL to PID $pid..."
            kill -KILL "$pid" 2>/dev/null || true
            ((count++)) || true
        fi
    done

    # Also kill any claude processes started by ralph
    pkill -f "claude -p --dangerously-skip-permissions" 2>/dev/null || true

    if [[ "$count" -eq 0 ]]; then
        write_colored green "No running instances found"
    else
        write_colored red "Killed $count instances"
    fi

    # Clear PID file
    : > "$PIDS_FILE"
}

cmd_status() {
    write_colored blue "╔═══════════════════════════════════════════════════════╗"
    echo -e "${COLOR_BLUE}║${COLOR_RESET}         ${COLOR_CYAN}RALPH PARALLEL STATUS${COLOR_RESET}                         ${COLOR_BLUE}║${COLOR_RESET}"
    write_colored blue "╚═══════════════════════════════════════════════════════╝"
    echo ""

    clean_pids
    local pids
    pids=$(load_pids)
    local running=0
    local total=0

    printf "%-10s %-10s %-12s %-10s\n" "PID" "STATUS" "INSTANCE" "STATE"
    printf "%-10s %-10s %-12s %-10s\n" "---" "------" "--------" "-----"

    local pid
    for pid in $pids; do
        ((total++)) || true
        local status="stopped"
        local instance="-"
        local state="-"

        if kill -0 "$pid" 2>/dev/null; then
            status="${COLOR_GREEN}running${COLOR_RESET}"
            ((running++)) || true

            # Try to find instance info
            local dir
            for dir in "$INSTANCES_DIR"/*; do
                [[ -d "$dir" ]] || continue
                local status_file="$dir/status.json"
                if [[ -f "$status_file" ]]; then
                    local file_pid
                    file_pid=$(jq -r '.pid // 0' "$status_file" 2>/dev/null || echo "0")
                    if [[ "$file_pid" == "$pid" ]]; then
                        instance=$(basename "$dir")
                        instance="${instance:0:10}"
                        state=$(jq -r '.state // "-"' "$status_file" 2>/dev/null || echo "-")
                        break
                    fi
                fi
            done
        else
            status="${COLOR_GRAY}stopped${COLOR_RESET}"
        fi

        printf "%-10s %b  %-12s %-10s\n" "$pid" "$status" "$instance" "$state"
    done

    echo ""
    echo -e "Running: ${COLOR_GREEN}$running${COLOR_RESET}/$total"

    # Show active locks
    local locks_json lock_count
    locks_json=$(get_ralph_story_locks)
    lock_count=$(echo "$locks_json" | jq 'length')
    echo "Active locks: $lock_count"

    # Show PRD status
    if [[ -f "$PRD_FILE" ]]; then
        eval "$(get_prd_status)"
        echo "PRD progress: $PRD_COMPLETE/$PRD_TOTAL stories"
    fi
}

cmd_dashboard() {
    exec "$SCRIPT_DIR/ralph-dashboard.sh"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-}"

    case "$command" in
        ""|[0-9]*)
            cmd_launch "$command"
            ;;
        stop)
            cmd_stop
            ;;
        kill)
            cmd_kill
            ;;
        status)
            cmd_status
            ;;
        dashboard)
            cmd_dashboard
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            write_colored red "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
