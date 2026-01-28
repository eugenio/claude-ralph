#!/bin/bash
# ralph-parallel.sh - Launch multiple Ralph instances in parallel
# Usage: ./ralph-parallel.sh [count|stop|status]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="$SCRIPT_DIR/instances"
PIDS_FILE="$INSTANCES_DIR/running.pids"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  <N>             Launch N instances (default: CPU cores / 2)"
    echo "  stop            Stop all running instances gracefully"
    echo "  kill            Force kill all running instances"
    echo "  status          Show running instances"
    echo "  dashboard       Launch dashboard to monitor instances"
    echo ""
    echo "Examples:"
    echo "  $0 3            # Launch 3 instances"
    echo "  $0 stop         # Stop all instances"
    echo "  $0 status       # Show status"
    echo ""
    echo "Environment Variables:"
    echo "  RALPH_MAX_INSTANCES  Maximum instances to launch (default: 8)"
    echo "  RALPH_ITERATIONS     Max iterations per instance (default: 10)"
}

get_cpu_count() {
    if command -v nproc &>/dev/null; then
        nproc
    elif [ -f /proc/cpuinfo ]; then
        grep -c ^processor /proc/cpuinfo
    elif command -v sysctl &>/dev/null; then
        sysctl -n hw.ncpu 2>/dev/null || echo "4"
    else
        echo "4"
    fi
}

get_default_count() {
    local cpus=$(get_cpu_count)
    local default=$((cpus / 2))
    [ "$default" -lt 1 ] && default=1
    echo "$default"
}

save_pid() {
    local pid="$1"
    mkdir -p "$INSTANCES_DIR"
    echo "$pid" >> "$PIDS_FILE"
}

load_pids() {
    if [ -f "$PIDS_FILE" ]; then
        cat "$PIDS_FILE" | sort -u
    fi
}

clean_pids() {
    local active_pids=""
    for pid in $(load_pids); do
        if kill -0 "$pid" 2>/dev/null; then
            active_pids="$active_pids$pid\n"
        fi
    done

    mkdir -p "$INSTANCES_DIR"
    echo -e "$active_pids" | grep -v '^$' > "$PIDS_FILE" 2>/dev/null || true
}

cmd_launch() {
    local count="${1:-$(get_default_count)}"
    local max_instances="${RALPH_MAX_INSTANCES:-8}"
    local iterations="${RALPH_ITERATIONS:-10}"

    # Validate count
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid count '$count'${NC}"
        exit 1
    fi

    if [ "$count" -gt "$max_instances" ]; then
        echo -e "${YELLOW}Warning: Limiting to $max_instances instances (RALPH_MAX_INSTANCES)${NC}"
        count="$max_instances"
    fi

    if [ "$count" -lt 1 ]; then
        echo -e "${RED}Error: Count must be at least 1${NC}"
        exit 1
    fi

    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}         ${CYAN}RALPH PARALLEL LAUNCHER${NC}                       ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Launching ${GREEN}$count${NC} instances with ${GREEN}$iterations${NC} iterations each..."
    echo ""

    mkdir -p "$INSTANCES_DIR"

    for i in $(seq 1 "$count"); do
        # Small delay between launches to avoid race conditions
        [ "$i" -gt 1 ] && sleep 1

        echo -e "  ${CYAN}Starting instance $i/$count...${NC}"

        # Launch in background with nohup
        nohup "$SCRIPT_DIR/ralph.sh" "$iterations" \
            > /dev/null 2>&1 &

        local pid=$!
        save_pid "$pid"

        echo -e "    ${GREEN}✓${NC} PID: $pid"
    done

    echo ""
    echo -e "${GREEN}Launched $count instances${NC}"
    echo ""
    echo "Monitor with:"
    echo "  $0 status"
    echo "  $SCRIPT_DIR/ralph-dashboard.sh"
    echo ""
    echo "Stop with:"
    echo "  $0 stop"
}

cmd_stop() {
    echo -e "${YELLOW}Stopping all Ralph instances...${NC}"

    clean_pids
    local pids=$(load_pids)
    local count=0

    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  Sending SIGTERM to PID $pid..."
            kill -TERM "$pid" 2>/dev/null || true
            count=$((count + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No running instances found${NC}"
    else
        echo ""
        echo -e "${YELLOW}Sent SIGTERM to $count instances${NC}"
        echo "Waiting for graceful shutdown (10s timeout)..."

        # Wait for processes to exit
        local timeout=10
        local waited=0
        while [ "$waited" -lt "$timeout" ]; do
            sleep 1
            waited=$((waited + 1))

            local still_running=0
            for pid in $pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    still_running=$((still_running + 1))
                fi
            done

            if [ "$still_running" -eq 0 ]; then
                break
            fi

            echo "  Still running: $still_running"
        done

        # Check if any still running
        local remaining=0
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                remaining=$((remaining + 1))
            fi
        done

        if [ "$remaining" -gt 0 ]; then
            echo -e "${YELLOW}$remaining instances still running. Use '$0 kill' to force kill.${NC}"
        else
            echo -e "${GREEN}All instances stopped${NC}"
        fi
    fi

    # Clean up PID file
    clean_pids
}

cmd_kill() {
    echo -e "${RED}Force killing all Ralph instances...${NC}"

    clean_pids
    local pids=$(load_pids)
    local count=0

    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  Sending SIGKILL to PID $pid..."
            kill -KILL "$pid" 2>/dev/null || true
            count=$((count + 1))
        fi
    done

    # Also kill any claude processes started by ralph
    pkill -f "claude -p --dangerously-skip-permissions" 2>/dev/null || true

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No running instances found${NC}"
    else
        echo -e "${RED}Killed $count instances${NC}"
    fi

    # Clear PID file
    > "$PIDS_FILE"
}

cmd_status() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}         ${CYAN}RALPH PARALLEL STATUS${NC}                         ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    clean_pids
    local pids=$(load_pids)
    local running=0
    local total=0

    printf "%-10s %-10s %-12s %-10s\n" "PID" "STATUS" "INSTANCE" "STATE"
    printf "%-10s %-10s %-12s %-10s\n" "---" "------" "--------" "-----"

    for pid in $pids; do
        total=$((total + 1))
        local status="stopped"
        local instance="-"
        local state="-"

        if kill -0 "$pid" 2>/dev/null; then
            status="${GREEN}running${NC}"
            running=$((running + 1))

            # Try to find instance info
            for dir in "$INSTANCES_DIR"/*; do
                [ -d "$dir" ] || continue
                local status_file="$dir/status.json"
                if [ -f "$status_file" ]; then
                    local file_pid=$(jq -r '.pid // 0' "$status_file" 2>/dev/null || echo "0")
                    if [ "$file_pid" = "$pid" ]; then
                        instance=$(basename "$dir")
                        instance="${instance:0:10}"
                        state=$(jq -r '.state // "-"' "$status_file" 2>/dev/null || echo "-")
                        break
                    fi
                fi
            done
        else
            status="${DIM}stopped${NC}"
        fi

        printf "%-10s ${status}  %-12s %-10s\n" "$pid" "" "$instance" "$state"
    done

    echo ""
    echo -e "Running: ${GREEN}$running${NC}/$total"

    # Show active locks
    local lock_count=0
    if [ -d "$LOCKS_DIR" ]; then
        lock_count=$(ls -d "$LOCKS_DIR"/*.lock 2>/dev/null | wc -l || echo "0")
    fi
    echo "Active locks: $lock_count"

    # Show PRD status
    if [ -f "$SCRIPT_DIR/prd.json" ]; then
        local prd_total=$(jq '.userStories | length' "$SCRIPT_DIR/prd.json" 2>/dev/null || echo "0")
        local prd_complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$SCRIPT_DIR/prd.json" 2>/dev/null || echo "0")
        echo "PRD progress: $prd_complete/$prd_total stories"
    fi
}

cmd_dashboard() {
    exec "$SCRIPT_DIR/ralph-dashboard.sh"
}

# Main
case "${1:-}" in
    ""|[0-9]*)
        cmd_launch "$1"
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
        show_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_usage
        exit 1
        ;;
esac
