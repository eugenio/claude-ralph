#!/usr/bin/env bash
# =============================================================================
# ralph-parallel.sh - Launch and manage multiple Ralph instances in parallel
# =============================================================================
#
# DESCRIPTION:
#   Provides commands to start, stop, and monitor multiple concurrent Ralph
#   instances using bash background processes.
#
# USAGE:
#   ./ralph-parallel.sh <command> [options]
#
# COMMANDS:
#   start     Launch Ralph instances (default: CPU cores / 2)
#   stop      Stop all running instances gracefully (SIGTERM)
#   kill      Force kill all instances (SIGKILL)
#   status    Show running instance status
#   dashboard Open monitoring dashboard
#   help      Show this help
#
# OPTIONS:
#   -c, --count N         Number of instances to launch (default: CPU cores / 2)
#   -m, --max-iterations  Max iterations per instance (default: 10)
#
# ENVIRONMENT:
#   RALPH_MAX_INSTANCES   Maximum instances allowed (default: 8)
#   RALPH_ITERATIONS      Default max iterations (default: 10)
#
# EXAMPLES:
#   ./ralph-parallel.sh start -c 3           # Launch 3 instances
#   ./ralph-parallel.sh start --count 2 -m 5 # 2 instances, 5 iterations each
#   ./ralph-parallel.sh stop                  # Stop all instances
#   ./ralph-parallel.sh status                # Show running status
#
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
if [[ ! -f "$SCRIPT_DIR/ralph-utils.sh" ]]; then
    echo "Error: ralph-utils.sh not found in script directory" >&2
    exit 1
fi
# shellcheck source=ralph-utils.sh
source "$SCRIPT_DIR/ralph-utils.sh"

# Load paths
eval "$(get_ralph_paths)"

# =============================================================================
# CONFIGURATION
# =============================================================================

JOBS_FILE="$INSTANCES_DIR/running-jobs.json"
MAX_INSTANCES="${RALPH_MAX_INSTANCES:-8}"
DEFAULT_ITERATIONS="${RALPH_ITERATIONS:-10}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

get_default_count() {
    local cpu_count
    cpu_count=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
    local default=$((cpu_count / 2))
    [[ "$default" -lt 1 ]] && default=1
    echo "$default"
}

ensure_instances_dir() {
    mkdir -p "$INSTANCES_DIR"
}

save_jobs() {
    local jobs_json="$1"
    ensure_instances_dir
    echo "$jobs_json" > "$JOBS_FILE"
}

get_saved_jobs() {
    if [[ ! -f "$JOBS_FILE" ]]; then
        echo "[]"
        return 0
    fi

    local content
    content=$(cat "$JOBS_FILE" 2>/dev/null)
    if [[ -z "$content" ]]; then
        echo "[]"
        return 0
    fi

    # Validate JSON
    if ! echo "$content" | jq '.' &>/dev/null; then
        echo "[]"
        return 0
    fi

    echo "$content"
}

is_process_running() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

# =============================================================================
# COMMAND FUNCTIONS
# =============================================================================

show_help() {
    echo ""
    write_colored cyan "Usage: ./ralph-parallel.sh <Command> [Options]"
    echo ""
    write_colored yellow "Commands:"
    echo "  start [-c N] [-m M]  Launch N instances with M max iterations"
    echo "  stop                 Stop all instances gracefully (SIGTERM)"
    echo "  kill                 Force kill all instances (SIGKILL)"
    echo "  status               Show running instances"
    echo "  dashboard            Open monitoring dashboard"
    echo "  queue <subcommand>   Queue management (add, list, status, clear)"
    echo "  help                 Show this help"
    echo ""
    write_colored yellow "Options:"
    echo "  -c, --count N        Number of instances (default: CPU cores / 2)"
    echo "  -m, --max-iterations Max iterations per instance (default: 10)"
    echo ""
    write_colored yellow "Examples:"
    echo "  ./ralph-parallel.sh start -c 3"
    echo "  ./ralph-parallel.sh stop"
    echo "  ./ralph-parallel.sh status"
    echo "  ./ralph-parallel.sh queue add -p /project/prd.json -r /project"
    echo "  ./ralph-parallel.sh queue list"
    echo ""
    write_colored yellow "Environment Variables:"
    echo "  RALPH_MAX_INSTANCES  Maximum instances allowed (default: 8)"
    echo "  RALPH_ITERATIONS     Default max iterations (default: 10)"
    echo ""
}

cmd_start() {
    local count="$1"
    local max_iterations="$2"

    # Default count to CPU cores / 2
    if [[ -z "$count" || "$count" -le 0 ]]; then
        count=$(get_default_count)
    fi

    # Default max iterations
    if [[ -z "$max_iterations" || "$max_iterations" -le 0 ]]; then
        max_iterations="$DEFAULT_ITERATIONS"
    fi

    # Enforce max instances
    if [[ "$count" -gt "$MAX_INSTANCES" ]]; then
        write_colored yellow "Warning: Limiting to $MAX_INSTANCES instances (RALPH_MAX_INSTANCES)"
        count="$MAX_INSTANCES"
    fi

    echo ""
    write_colored blue "$(printf '═%.0s' {1..55})"
    write_colored cyan "         RALPH PARALLEL LAUNCHER"
    write_colored blue "$(printf '═%.0s' {1..55})"
    echo ""
    echo "Launching $count instances with $max_iterations iterations each..."
    echo ""

    local ralph_script="$SCRIPT_DIR/ralph.sh"
    if [[ ! -f "$ralph_script" ]]; then
        write_colored red "Error: ralph.sh not found"
        exit 1
    fi

    ensure_instances_dir
    local jobs_json="[]"

    for ((i = 1; i <= count; i++)); do
        write_colored cyan "  Starting instance $i/$count..."

        # Small delay between launches to avoid lock contention
        if [[ "$i" -gt 1 ]]; then
            sleep 1
        fi

        # Launch in background
        local log_file="$INSTANCES_DIR/parallel-$i-$$.log"
        "$ralph_script" "$max_iterations" > "$log_file" 2>&1 &
        local pid=$!

        # Record job info
        local start_time
        start_time=$(date '+%Y-%m-%d %H:%M:%S')

        jobs_json=$(echo "$jobs_json" | jq \
            --argjson pid "$pid" \
            --arg start_time "$start_time" \
            --argjson iterations "$max_iterations" \
            --arg log_file "$log_file" \
            --argjson index "$i" \
            '. += [{
                pid: $pid,
                index: $index,
                startTime: $start_time,
                iterations: $iterations,
                logFile: $log_file
            }]')

        write_colored green "    PID: $pid"
    done

    save_jobs "$jobs_json"

    echo ""
    write_colored green "Launched $count instances"
    echo ""
    write_colored yellow "Monitor with:"
    echo "  ./ralph-parallel.sh status"
    echo "  ./ralph-parallel.sh dashboard"
    echo ""
    write_colored yellow "Stop with:"
    echo "  ./ralph-parallel.sh stop"
    echo ""
}

cmd_stop() {
    write_colored yellow "Stopping all Ralph instances..."

    local saved_jobs stopped=0
    saved_jobs=$(get_saved_jobs)

    # Stop jobs from our tracking file
    local pids
    pids=$(echo "$saved_jobs" | jq -r '.[].pid')

    for pid in $pids; do
        if is_process_running "$pid"; then
            write_colored gray "  Stopping PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
            ((stopped++)) || true
        fi
    done

    # Also try to find any ralph.sh processes we might have missed
    # Using pgrep to find ralph.sh processes (excluding ourselves)
    local ralph_pids
    ralph_pids=$(pgrep -f "ralph\.sh" 2>/dev/null || true)

    for pid in $ralph_pids; do
        # Skip our own PID
        [[ "$pid" == "$$" ]] && continue

        if is_process_running "$pid"; then
            write_colored gray "  Stopping PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
            ((stopped++)) || true
        fi
    done

    if [[ "$stopped" -eq 0 ]]; then
        write_colored green "No running instances found"
    else
        write_colored green "Stopped $stopped instances"
    fi

    # Clear jobs file
    save_jobs "[]"
}

cmd_kill() {
    write_colored red "Force killing all Ralph instances..."

    local killed=0

    # Kill jobs from our tracking file
    local saved_jobs pids
    saved_jobs=$(get_saved_jobs)
    pids=$(echo "$saved_jobs" | jq -r '.[].pid')

    for pid in $pids; do
        if is_process_running "$pid"; then
            write_colored gray "  Killing PID $pid..."
            kill -KILL "$pid" 2>/dev/null || true
            ((killed++)) || true
        fi
    done

    # Kill any ralph.sh processes
    local ralph_pids
    ralph_pids=$(pgrep -f "ralph\.sh" 2>/dev/null || true)

    for pid in $ralph_pids; do
        [[ "$pid" == "$$" ]] && continue

        if is_process_running "$pid"; then
            write_colored gray "  Killing PID $pid..."
            kill -KILL "$pid" 2>/dev/null || true
            ((killed++)) || true
        fi
    done

    # Also try to kill any claude processes
    local claude_pids
    claude_pids=$(pgrep -f "claude" 2>/dev/null || true)

    for pid in $claude_pids; do
        kill -KILL "$pid" 2>/dev/null || true
    done

    write_colored red "All instances killed"

    # Clear jobs file
    save_jobs "[]"
}

cmd_status() {
    echo ""
    write_colored blue "$(printf '═%.0s' {1..55})"
    write_colored cyan "         RALPH PARALLEL STATUS"
    write_colored blue "$(printf '═%.0s' {1..55})"
    echo ""

    local saved_jobs running=0 total
    saved_jobs=$(get_saved_jobs)
    total=$(echo "$saved_jobs" | jq 'length')

    # Print header
    printf "${COLOR_WHITE}%-8s %-10s %-12s %-15s${COLOR_RESET}\n" "PID" "STATUS" "INSTANCE" "STATE"
    printf "%-8s %-10s %-12s %-15s\n" "------" "------" "--------" "-----"

    # Process each job
    echo "$saved_jobs" | jq -c '.[]' | while read -r job; do
        local pid status color instance_id state
        pid=$(echo "$job" | jq -r '.pid')

        if is_process_running "$pid"; then
            status="Running"
            color="$COLOR_GREEN"
        else
            status="Gone"
            color="$COLOR_GRAY"
        fi

        # Try to find instance info (placeholder for now)
        instance_id="-"
        state="-"

        printf "${color}%-8s${COLOR_RESET} " "$pid"
        printf "${color}%-10s${COLOR_RESET} " "$status"
        printf "%-12s %-15s\n" "$instance_id" "$state"
    done

    # Count running
    local pids
    pids=$(echo "$saved_jobs" | jq -r '.[].pid')
    for pid in $pids; do
        if is_process_running "$pid"; then
            ((running++)) || true
        fi
    done

    echo ""
    if [[ "$running" -gt 0 ]]; then
        write_colored green "Running: $running/$total"
    else
        write_colored gray "Running: $running/$total"
    fi

    # Show locks
    local locks_json lock_count
    locks_json=$(get_ralph_story_locks)
    lock_count=$(echo "$locks_json" | jq 'length')
    echo "Active locks: $lock_count"

    # Show PRD status
    if [[ -f "$PRD_FILE" ]]; then
        eval "$(get_prd_status)"
        echo "PRD progress: $PRD_COMPLETE/$PRD_TOTAL stories"
    fi

    echo ""
}

cmd_dashboard() {
    local dashboard_script="$SCRIPT_DIR/ralph-dashboard.sh"
    if [[ -f "$dashboard_script" ]]; then
        exec "$dashboard_script"
    else
        write_colored red "Dashboard script not found"
        exit 1
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
    local command=""
    local count=0
    local max_iterations=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            start|stop|kill|status|dashboard|help)
                command="$1"
                shift
                ;;
            queue)
                # Delegate immediately to ralph-queue.sh with remaining args
                shift
                exec "$SCRIPT_DIR/ralph-queue.sh" "$@"
                ;;
            -c|--count)
                count="$2"
                shift 2
                ;;
            -m|--max-iterations)
                max_iterations="$2"
                shift 2
                ;;
            -h|--help)
                command="help"
                shift
                ;;
            *)
                # Unknown option, might be count for backwards compatibility
                if [[ "$1" =~ ^[0-9]+$ && -z "$count" ]]; then
                    count="$1"
                else
                    write_colored red "Unknown option: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Default command is status
    [[ -z "$command" ]] && command="status"

    # Execute command
    case "$command" in
        start)
            cmd_start "$count" "$max_iterations"
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
        help)
            show_help
            ;;
        *)
            show_help
            ;;
    esac
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Check dependencies
    if ! command -v jq &>/dev/null; then
        write_colored red "Error: jq is required. Install with: apt install jq (or brew install jq)"
        exit 1
    fi

    parse_args "$@"
}

main "$@"
