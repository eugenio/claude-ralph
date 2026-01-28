#!/usr/bin/env bash
# =============================================================================
# ralph-dashboard.sh - TUI dashboard for monitoring Ralph instances
# =============================================================================
#
# SYNOPSIS:
#   ralph-dashboard.sh [-r SECONDS]
#
# DESCRIPTION:
#   Provides a real-time terminal dashboard showing all running Ralph
#   instances, their status, PRD progress, and active locks.
#
# OPTIONS:
#   -r, --refresh SECONDS   Refresh interval (default: 2)
#   -h, --help              Show this help message
#
# KEYBOARD SHORTCUTS:
#   q - Quit the dashboard
#   r - Force refresh
#   l - Show detailed locks view
#   c - Run cleanup for dead instances
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - jq (for JSON parsing)
#   - tput (for terminal control)
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

REFRESH_INTERVAL=2
FRAME_WIDTH=75

# Unicode box drawing characters
readonly BOX_TL=$'\u2554'  # ╔
readonly BOX_TR=$'\u2557'  # ╗
readonly BOX_BL=$'\u255A'  # ╚
readonly BOX_BR=$'\u255D'  # ╝
readonly BOX_H=$'\u2550'   # ═
readonly BOX_V=$'\u2551'   # ║
readonly BOX_VR=$'\u2560'  # ╠
readonly BOX_VL=$'\u2563'  # ╣

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

show_help() {
    echo ""
    write_colored cyan "Usage: ./ralph-dashboard.sh [options]"
    echo ""
    write_colored yellow "Options:"
    echo "  -r, --refresh SECONDS   Refresh interval (default: 2)"
    echo "  -h, --help              Show this help message"
    echo ""
    write_colored yellow "Keyboard Shortcuts:"
    echo "  q - Quit the dashboard"
    echo "  r - Force refresh"
    echo "  l - Show detailed locks view"
    echo "  c - Run cleanup for dead instances"
    echo ""
}

# repeat_char()
# Repeats a character n times
# Arguments:
#   $1 - Character to repeat
#   $2 - Number of times to repeat
#
repeat_char() {
    local char="$1"
    local count="$2"
    local i
    for ((i = 0; i < count; i++)); do
        printf "%s" "$char"
    done
}

# get_progress_bar()
# Creates a progress bar
# Arguments:
#   $1 - Complete count
#   $2 - Total count
#   $3 - Width (default 30)
#
get_progress_bar() {
    local complete="$1"
    local total="$2"
    local width="${3:-30}"

    if [[ "$total" -eq 0 ]]; then
        printf "[%*s]" "$width" ""
        return
    fi

    local filled=$((complete * width / total))
    [[ "$filled" -gt "$width" ]] && filled="$width"
    local empty=$((width - filled))

    local bar="["
    local i
    for ((i = 0; i < filled; i++)); do bar+=$'\u2588'; done  # █
    for ((i = 0; i < empty; i++)); do bar+=$'\u2591'; done   # ░
    bar+="]"
    printf "%s" "$bar"
}

# format_duration()
# Formats seconds into human-readable duration
# Arguments:
#   $1 - Duration in seconds
#
format_duration() {
    local seconds="$1"

    if [[ "$seconds" -lt 60 ]]; then
        printf "%ds" "$seconds"
    elif [[ "$seconds" -lt 3600 ]]; then
        local m=$((seconds / 60))
        local s=$((seconds % 60))
        printf "%dm %ds" "$m" "$s"
    else
        local h=$((seconds / 3600))
        local m=$(((seconds % 3600) / 60))
        printf "%dh %dm" "$h" "$m"
    fi
}

# get_state_color()
# Returns color code for a state
# Arguments:
#   $1 - State name
#
get_state_color() {
    local state="$1"

    case "$state" in
        working|merging)
            echo "green"
            ;;
        claiming|starting)
            echo "cyan"
            ;;
        idle)
            echo "yellow"
            ;;
        completed)
            echo "blue"
            ;;
        terminated|max_iterations)
            echo "gray"
            ;;
        dead)
            echo "red"
            ;;
        *)
            echo "white"
            ;;
    esac
}

# pad_right()
# Pads a string on the right
# Arguments:
#   $1 - String
#   $2 - Width
#
pad_right() {
    printf "%-${2}s" "$1"
}

# truncate_string()
# Truncates string with ellipsis
# Arguments:
#   $1 - String
#   $2 - Max length
#
truncate_string() {
    local str="$1"
    local max_len="$2"

    if [[ ${#str} -gt $max_len ]]; then
        echo "${str:0:$((max_len - 3))}..."
    else
        echo "$str"
    fi
}

# =============================================================================
# RENDER FUNCTIONS
# =============================================================================

# render_header()
# Renders the dashboard header with PRD progress
#
render_header() {
    local prd_json

    # shellcheck disable=SC2119
    if prd_json=$(read_prd_json 2>/dev/null); then
        eval "$(get_prd_status "$prd_json")"
    else
        PRD_TOTAL=0
        PRD_COMPLETE=0
    fi

    # Top border
    write_colored blue "${BOX_TL}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_TR}"

    # Title
    local title="              RALPH DASHBOARD"
    local title_padding=$((FRAME_WIDTH - ${#title}))
    write_colored blue "${BOX_V}" "-n"
    printf "%s%*s" "$title" "$title_padding" ""
    write_colored blue "${BOX_V}"

    # Separator
    write_colored blue "${BOX_VR}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_VL}"

    # Progress bar
    local progress_bar
    progress_bar=$(get_progress_bar "$PRD_COMPLETE" "$PRD_TOTAL")
    local progress_text="  PRD Progress: $progress_bar ${PRD_COMPLETE}/${PRD_TOTAL}"
    local progress_padding=$((FRAME_WIDTH - ${#progress_text}))

    write_colored blue "${BOX_V}" "-n"
    printf "%s%*s" "$progress_text" "$progress_padding" ""
    write_colored blue "${BOX_V}"

    # Separator
    write_colored blue "${BOX_VR}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_VL}"
}

# render_instances()
# Renders the instance table
#
render_instances() {
    local now
    now=$(date +%s)

    # Header row
    local header_line
    header_line=$(printf " %-10s %-12s %-12s %-6s %-12s %-14s" \
        "INSTANCE" "STORY" "STATE" "ITER" "RUNTIME" "BRANCH")
    write_colored blue "${BOX_V}" "-n"
    write_colored white "$header_line" "-n"
    write_colored blue "${BOX_V}"

    # Divider row
    local divider_line
    divider_line=$(printf " %-10s %-12s %-12s %-6s %-12s %-14s" \
        "--------" "-----" "-----" "----" "-------" "------")
    write_colored blue "${BOX_V}" "-n"
    write_colored gray "$divider_line" "-n"
    write_colored blue "${BOX_V}"

    # Get instances
    local instances_json
    instances_json=$(get_ralph_instances "all" 2>/dev/null || echo "[]")

    local instance_count
    instance_count=$(echo "$instances_json" | jq 'length')

    if [[ "$instance_count" -eq 0 ]]; then
        local empty_line="  No instances running"
        local empty_padding=$((FRAME_WIDTH - ${#empty_line}))
        write_colored blue "${BOX_V}" "-n"
        write_colored gray "$empty_line" "-n"
        printf "%*s" "$empty_padding" ""
        write_colored blue "${BOX_V}"
    else
        echo "$instances_json" | jq -c '.[]' | while IFS= read -r instance; do
            [[ -z "$instance" ]] && continue

            local is_dead state instance_id short_id current_story iteration max_iterations
            local branch runtime_str

            is_dead=$(echo "$instance" | jq -r '.isDead // false')
            state=$(echo "$instance" | jq -r '.state // "unknown"')

            if [[ "$is_dead" == "true" ]]; then
                state="dead"
            fi

            local color
            color=$(get_state_color "$state")

            instance_id=$(echo "$instance" | jq -r '.instanceId // ""')
            short_id=$(echo "$instance" | jq -r '.shortId // ""')
            current_story=$(echo "$instance" | jq -r '.currentStory // ""')
            iteration=$(echo "$instance" | jq -r '.iteration // 0')
            max_iterations=$(echo "$instance" | jq -r '.maxIterations // 0')
            branch=$(echo "$instance" | jq -r '.branch // ""')

            # Calculate runtime from instance ID timestamp
            local start_epoch
            start_epoch="${instance_id##*-}"
            if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
                local runtime=$((now - start_epoch))
                runtime_str=$(format_duration "$runtime")
            else
                runtime_str="-"
            fi

            # Truncate branch if needed
            branch=$(truncate_string "${branch:-"-"}" 14)

            # Story display
            [[ -z "$current_story" || "$current_story" == "null" ]] && current_story="-"

            # Iteration display
            local iter_str="${iteration}/${max_iterations}"

            # Build line
            local line_part1
            line_part1=$(printf " %-10s %-12s " "$short_id" "$current_story")

            local state_part
            state_part=$(printf "%-12s " "$state")

            local line_part2
            line_part2=$(printf "%-6s %-12s %-14s" "$iter_str" "$runtime_str" "$branch")

            write_colored blue "${BOX_V}" "-n"
            printf "%s" "$line_part1"
            write_colored "$color" "$state_part" "-n"
            printf "%s" "$line_part2"
            write_colored blue "${BOX_V}"
        done
    fi
}

# render_locks()
# Renders the active locks section
#
render_locks() {
    # Separator
    write_colored blue "${BOX_VR}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_VL}"

    # Header
    local locks_header="  ACTIVE LOCKS"
    local locks_header_padding=$((FRAME_WIDTH - ${#locks_header}))
    write_colored blue "${BOX_V}" "-n"
    write_colored white "$locks_header" "-n"
    printf "%*s" "$locks_header_padding" ""
    write_colored blue "${BOX_V}"

    # Get locks
    local locks_json
    locks_json=$(get_ralph_story_locks 2>/dev/null || echo "[]")

    local lock_count
    lock_count=$(echo "$locks_json" | jq 'length')

    if [[ "$lock_count" -eq 0 ]]; then
        local no_locks="    No active locks"
        local no_locks_padding=$((FRAME_WIDTH - ${#no_locks}))
        write_colored blue "${BOX_V}" "-n"
        write_colored gray "$no_locks" "-n"
        printf "%*s" "$no_locks_padding" ""
        write_colored blue "${BOX_V}"
    else
        echo "$locks_json" | jq -c '.[]' | head -5 | while IFS= read -r lock; do
            [[ -z "$lock" ]] && continue

            local story_id owner age is_dead is_stale

            story_id=$(echo "$lock" | jq -r '.storyId // ""')
            owner=$(echo "$lock" | jq -r '.owner // ""')
            age=$(echo "$lock" | jq -r '.age // 0')
            is_dead=$(echo "$lock" | jq -r '.isDead // false')
            is_stale=$(echo "$lock" | jq -r '.isStale // false')

            local age_str
            age_str=$(format_duration "$age")

            # Truncate owner
            local owner_short
            owner_short=$(truncate_string "$owner" 10)

            # Determine color
            local color
            if [[ "$is_dead" == "true" ]]; then
                color="red"
            elif [[ "$is_stale" == "true" ]]; then
                color="yellow"
            else
                color="green"
            fi

            local lock_line
            lock_line=$(printf "    %-10s held by %-10s for %-10s" "$story_id" "$owner_short" "$age_str")
            local lock_line_padding=$((FRAME_WIDTH - ${#lock_line}))

            write_colored blue "${BOX_V}" "-n"
            write_colored "$color" "$lock_line" "-n"
            printf "%*s" "$lock_line_padding" ""
            write_colored blue "${BOX_V}"
        done

        if [[ "$lock_count" -gt 5 ]]; then
            local more_count=$((lock_count - 5))
            local more_line="    ... and $more_count more"
            local more_padding=$((FRAME_WIDTH - ${#more_line}))

            write_colored blue "${BOX_V}" "-n"
            write_colored gray "$more_line" "-n"
            printf "%*s" "$more_padding" ""
            write_colored blue "${BOX_V}"
        fi
    fi
}

# render_footer()
# Renders the footer with help and timestamp
#
render_footer() {
    # Separator
    write_colored blue "${BOX_VR}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_VL}"

    # Help line
    local help_line="  Press: q=quit  r=refresh  l=locks  c=cleanup"
    local help_padding=$((FRAME_WIDTH - ${#help_line}))
    write_colored blue "${BOX_V}" "-n"
    write_colored gray "$help_line" "-n"
    printf "%*s" "$help_padding" ""
    write_colored blue "${BOX_V}"

    # Time line
    local time_line
    time_line="  Last update: $(date '+%H:%M:%S')"
    local time_padding=$((FRAME_WIDTH - ${#time_line}))
    write_colored blue "${BOX_V}" "-n"
    write_colored gray "$time_line" "-n"
    printf "%*s" "$time_padding" ""
    write_colored blue "${BOX_V}"

    # Bottom border
    write_colored blue "${BOX_BL}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_BR}"
}

# render_dashboard()
# Renders the complete dashboard
#
render_dashboard() {
    clear
    render_header
    render_instances
    render_locks
    render_footer
}

# =============================================================================
# INTERACTIVE FUNCTIONS
# =============================================================================

# show_locks_detail()
# Shows detailed lock view by running ralph-locks.sh
#
show_locks_detail() {
    clear
    "$SCRIPT_DIR/ralph-locks.sh" status
    echo ""
    write_colored gray "Press any key to return to dashboard..."
    read -rsn1
}

# invoke_cleanup()
# Runs cleanup for dead instances
#
invoke_cleanup() {
    clear
    "$SCRIPT_DIR/ralph-cleanup.sh" --dead
    echo ""
    write_colored gray "Press any key to return to dashboard..."
    read -rsn1
}

# =============================================================================
# MAIN LOOP
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--refresh)
                REFRESH_INTERVAL="${2:-2}"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                write_colored red "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check dependencies
    if ! command -v tput &>/dev/null; then
        write_colored red "Error: tput not found. Install ncurses."
        exit 1
    fi

    # Setup terminal
    local cursor_visible=true

    cleanup() {
        # Restore cursor
        if [[ "$cursor_visible" == "false" ]]; then
            tput cnorm 2>/dev/null || true
        fi
        clear
    }

    trap cleanup EXIT

    # Hide cursor
    tput civis 2>/dev/null || true
    cursor_visible=false

    # Main loop
    while true; do
        render_dashboard

        # Wait for input or timeout
        local timeout_end=$((SECONDS + REFRESH_INTERVAL))

        while [[ $SECONDS -lt $timeout_end ]]; do
            # Non-blocking read with timeout
            if read -rsn1 -t 0.1 key 2>/dev/null; then
                case "$key" in
                    q|Q)
                        exit 0
                        ;;
                    r|R)
                        break  # Force refresh
                        ;;
                    l|L)
                        show_locks_detail
                        break
                        ;;
                    c|C)
                        invoke_cleanup
                        break
                        ;;
                esac
            fi
        done
    done
}

main "$@"
