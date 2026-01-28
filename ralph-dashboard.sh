#!/bin/bash
# ralph-dashboard.sh - TUI dashboard for monitoring Ralph instances
# Usage: ./ralph-dashboard.sh [--all|--repo PATH]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="$SCRIPT_DIR/instances"
LOCKS_DIR="$SCRIPT_DIR/locks"
PRD_FILE="$SCRIPT_DIR/prd.json"

REFRESH_INTERVAL=2
SHOW_ALL_REPOS=false
FILTER_REPO=""

# Colors (using tput for better compatibility)
init_colors() {
    if command -v tput &>/dev/null && tput colors &>/dev/null; then
        RED=$(tput setaf 1)
        GREEN=$(tput setaf 2)
        YELLOW=$(tput setaf 3)
        BLUE=$(tput setaf 4)
        MAGENTA=$(tput setaf 5)
        CYAN=$(tput setaf 6)
        WHITE=$(tput setaf 7)
        BOLD=$(tput bold)
        DIM=$(tput dim)
        NC=$(tput sgr0)
    else
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        CYAN='\033[0;36m'
        WHITE='\033[0;37m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
    fi
}

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --all           Show instances from all repos (uses ~/.ralph/global)"
    echo "  --repo PATH     Filter to specific repo path"
    echo "  --refresh N     Refresh interval in seconds (default: 2)"
    echo "  -h, --help      Show this help"
    echo ""
    echo "Navigation:"
    echo "  q, Ctrl+C       Quit"
    echo "  r               Force refresh"
    echo "  l               Show locks"
    echo "  c               Cleanup dead instances"
}

get_prd_status() {
    if [ ! -f "$PRD_FILE" ]; then
        echo "0/0"
        return
    fi

    local total=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo "0")
    local complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
    echo "$complete/$total"
}

get_progress_bar() {
    local complete="$1"
    local total="$2"
    local width=30

    if [ "$total" -eq 0 ]; then
        printf "[%-${width}s]" ""
        return
    fi

    local filled=$((complete * width / total))
    local empty=$((width - filled))

    printf "["
    printf "${GREEN}%${filled}s${NC}" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]"
}

format_duration() {
    local seconds="$1"

    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

get_state_color() {
    local state="$1"
    case "$state" in
        working|merging)
            echo "$GREEN"
            ;;
        claiming|starting)
            echo "$CYAN"
            ;;
        idle)
            echo "$YELLOW"
            ;;
        completed)
            echo "$BLUE"
            ;;
        terminated|max_iterations)
            echo "$DIM"
            ;;
        dead)
            echo "$RED"
            ;;
        *)
            echo "$WHITE"
            ;;
    esac
}

render_header() {
    local prd_status=$(get_prd_status)
    local complete=${prd_status%/*}
    local total=${prd_status#*/}

    echo "${BLUE}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BLUE}║${NC}              ${BOLD}${CYAN}RALPH DASHBOARD${NC}                                          ${BLUE}║${NC}"
    echo "${BLUE}╠═══════════════════════════════════════════════════════════════════════╣${NC}"

    # Progress bar
    printf "${BLUE}║${NC}  PRD Progress: "
    get_progress_bar "$complete" "$total"
    printf " %s" "$prd_status"

    # Pad to fill line
    local progress_len=$((17 + 32 + ${#prd_status}))
    local padding=$((71 - progress_len))
    printf "%${padding}s${BLUE}║${NC}\n" ""

    echo "${BLUE}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
}

render_instances() {
    local now=$(date +%s)

    # Header row
    printf "${BLUE}║${NC} ${BOLD}%-10s %-12s %-10s %-6s %-10s %-12s${NC} ${BLUE}║${NC}\n" \
        "INSTANCE" "STORY" "STATE" "ITER" "RUNTIME" "BRANCH"
    printf "${BLUE}║${NC} %-10s %-12s %-10s %-6s %-10s %-12s ${BLUE}║${NC}\n" \
        "--------" "-----" "-----" "----" "-------" "------"

    local found=0

    if [ -d "$INSTANCES_DIR" ]; then
        for dir in "$INSTANCES_DIR"/*; do
            [ -d "$dir" ] || continue

            local instance_id=$(basename "$dir")
            local short_id="${instance_id:0:8}"
            local status_file="$dir/status.json"

            if [ ! -f "$status_file" ]; then
                continue
            fi

            local state=$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
            local story=$(jq -r '.currentStory // "-"' "$status_file" 2>/dev/null || echo "-")
            local iteration=$(jq -r '.iteration // 0' "$status_file" 2>/dev/null || echo "0")
            local max_iter=$(jq -r '.maxIterations // 0' "$status_file" 2>/dev/null || echo "0")
            local heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
            local start_time=$(jq -r '.startTime // ""' "$status_file" 2>/dev/null || echo "")
            local branch=$(jq -r '.branch // "-"' "$status_file" 2>/dev/null || echo "-")

            # Calculate runtime
            local heartbeat_age=$((now - heartbeat))

            # Mark as dead if no heartbeat
            if [ "$heartbeat_age" -gt 300 ] && [ "$state" != "terminated" ] && [ "$state" != "completed" ]; then
                state="dead"
            fi

            # Calculate total runtime from instance ID timestamp
            local start_epoch="${instance_id##*-}"
            local runtime=$((now - start_epoch))
            local runtime_str=$(format_duration "$runtime")

            # Get color for state
            local color=$(get_state_color "$state")

            # Truncate branch name
            local branch_short="${branch:0:12}"
            if [ ${#branch} -gt 12 ]; then
                branch_short="${branch_short:0:11}…"
            fi

            printf "${BLUE}║${NC} ${color}%-10s${NC} %-12s ${color}%-10s${NC} %2s/%-2s %-10s %-12s ${BLUE}║${NC}\n" \
                "$short_id" "${story:-"-"}" "$state" "$iteration" "$max_iter" "$runtime_str" "$branch_short"

            found=$((found + 1))
        done
    fi

    if [ "$found" -eq 0 ]; then
        printf "${BLUE}║${NC}  ${DIM}No instances running${NC}%50s${BLUE}║${NC}\n" ""
    fi
}

render_locks() {
    echo "${BLUE}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BLUE}║${NC}  ${BOLD}ACTIVE LOCKS${NC}%58s${BLUE}║${NC}\n" ""

    local now=$(date +%s)
    local found=0

    if [ -d "$LOCKS_DIR" ]; then
        for lock_dir in "$LOCKS_DIR"/*.lock; do
            [ -d "$lock_dir" ] || continue

            local story_id=$(basename "$lock_dir" .lock)
            local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "unknown")
            local owner_short="${owner:0:8}"
            local timestamp=$(cat "$lock_dir/timestamp" 2>/dev/null || echo "0")
            local age=$((now - timestamp))
            local age_str=$(format_duration "$age")

            printf "${BLUE}║${NC}    ${YELLOW}%-10s${NC} held by ${CYAN}%-10s${NC} for %-10s%20s${BLUE}║${NC}\n" \
                "$story_id" "$owner_short" "$age_str" ""

            found=$((found + 1))
        done
    fi

    if [ "$found" -eq 0 ]; then
        printf "${BLUE}║${NC}    ${DIM}No active locks${NC}%54s${BLUE}║${NC}\n" ""
    fi
}

render_footer() {
    echo "${BLUE}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BLUE}║${NC}  ${DIM}Press: q=quit  r=refresh  l=locks  c=cleanup${NC}%25s${BLUE}║${NC}\n" ""
    printf "${BLUE}║${NC}  ${DIM}Last update: $(date '+%H:%M:%S')${NC}%47s${BLUE}║${NC}\n" ""
    echo "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
}

render_dashboard() {
    clear
    render_header
    render_instances
    render_locks
    render_footer
}

main_loop() {
    # Hide cursor
    tput civis 2>/dev/null || true

    # Restore cursor on exit
    trap 'tput cnorm 2>/dev/null || true; exit 0' EXIT INT TERM

    while true; do
        render_dashboard

        # Read with timeout for refresh
        if read -t "$REFRESH_INTERVAL" -n 1 key 2>/dev/null; then
            case "$key" in
                q|Q)
                    break
                    ;;
                r|R)
                    # Force refresh
                    continue
                    ;;
                l|L)
                    # Show detailed locks
                    "$SCRIPT_DIR/ralph-locks.sh" status
                    echo ""
                    echo "Press any key to continue..."
                    read -n 1
                    ;;
                c|C)
                    # Cleanup
                    "$SCRIPT_DIR/ralph-cleanup.sh" --dead
                    echo ""
                    echo "Press any key to continue..."
                    read -n 1
                    ;;
            esac
        fi
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            SHOW_ALL_REPOS=true
            shift
            ;;
        --repo)
            FILTER_REPO="$2"
            shift 2
            ;;
        --refresh)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

init_colors
main_loop
