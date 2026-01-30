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
MIN_FRAME_WIDTH=60
MIN_FRAME_HEIGHT=20

# Reserved lines for fixed UI elements
# Header: top border(1) + title(1) + separator(1) + separator after projects(1) = 4
# Instances: header row(1) + divider(1) = 2
# Locks: separator(1) + header(1) = 2
# Footer: separator(1) + help(1) + time(1) + bottom border(1) = 4
# Total fixed overhead = 12 lines
RESERVED_LINES=12

# get_frame_width()
# Returns the current terminal width minus 2 for borders
get_frame_width() {
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)
    local width=$((term_width - 2))
    [[ "$width" -lt "$MIN_FRAME_WIDTH" ]] && width="$MIN_FRAME_WIDTH"
    echo "$width"
}

# get_frame_height()
# Returns the current terminal height
get_frame_height() {
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)
    [[ "$term_height" -lt "$MIN_FRAME_HEIGHT" ]] && term_height="$MIN_FRAME_HEIGHT"
    echo "$term_height"
}

# calculate_section_limits()
# Calculates max rows for each section based on terminal height
# Sets global variables: MAX_PROJECTS, MAX_INSTANCES, MAX_LOCKS
calculate_section_limits() {
    local term_height
    term_height=$(get_frame_height)
    local available=$((term_height - RESERVED_LINES))

    # Minimum 1 row per section
    [[ "$available" -lt 3 ]] && available=3

    # Distribution ratio: PROJECTS:INSTANCES:LOCKS = 2:5:2
    MAX_PROJECTS=$((available * 2 / 9))
    MAX_INSTANCES=$((available * 5 / 9))
    MAX_LOCKS=$((available - MAX_PROJECTS - MAX_INSTANCES))

    # Enforce minimums
    [[ "$MAX_PROJECTS" -lt 1 ]] && MAX_PROJECTS=1
    [[ "$MAX_INSTANCES" -lt 1 ]] && MAX_INSTANCES=1
    [[ "$MAX_LOCKS" -lt 1 ]] && MAX_LOCKS=1
}

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
    echo "  c - Run cleanup for dead and terminated instances"
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
# MULTI-PROJECT HELPERS
# =============================================================================

# get_project_prd_status()
# Gets PRD status for a specific project root
get_project_prd_status() {
    local project_root="$1"
    local prd_file=""
    if [[ -f "$project_root/scripts/ralph/prd.json" ]]; then
        prd_file="$project_root/scripts/ralph/prd.json"
    elif [[ -f "$project_root/.claude/ralph/prd.json" ]]; then
        prd_file="$project_root/.claude/ralph/prd.json"
    elif [[ -f "$project_root/prd.json" ]]; then
        prd_file="$project_root/prd.json"
    fi
    if [[ -z "$prd_file" || ! -f "$prd_file" ]]; then
        echo '{"total":0,"complete":0}'
        return 0
    fi
    local prd_json total complete
    prd_json=$(cat "$prd_file" 2>/dev/null) || { echo '{"total":0,"complete":0}'; return 0; }
    total=$(echo "$prd_json" | jq '.userStories | length' 2>/dev/null || echo 0)
    complete=$(echo "$prd_json" | jq '[.userStories[] | select(.passes == true)] | length' 2>/dev/null || echo 0)
    jq -n --argjson t "$total" --argjson c "$complete" '{total:$t,complete:$c}'
}

# get_all_projects_prd_status()
# Gets PRD status for all unique projects from global instances
get_all_projects_prd_status() {
    local instances_json project_roots local_root all_roots result
    instances_json=$(get_ralph_global_instances "all" 2>/dev/null || echo "[]")
    project_roots=$(echo "$instances_json" | jq -r '.[].projectRoot // empty' | sort -u)
    local_root=$(get_project_root 2>/dev/null || echo "")
    if [[ -n "$local_root" ]]; then
        all_roots=$(printf "%s\n%s" "$project_roots" "$local_root" | sort -u | grep -v '^$')
    else
        all_roots="$project_roots"
    fi
    result="[]"
    while IFS= read -r pr; do
        [[ -z "$pr" || ! -d "$pr" ]] && continue
        local name status total complete
        name=$(basename "$pr")
        status=$(get_project_prd_status "$pr")
        total=$(echo "$status" | jq -r '.total')
        complete=$(echo "$status" | jq -r '.complete')
        result=$(echo "$result" | jq --arg n "$name" --argjson t "$total" --argjson c "$complete" --arg r "$pr" \
            '. + [{name:$n,total:$t,complete:$c,root:$r}]')
    done <<< "$all_roots"
    echo "$result"
}

# get_all_projects_locks()
# Gets locks from all projects in global registry
get_all_projects_locks() {
    local instances_json project_roots local_root all_roots result
    instances_json=$(get_ralph_global_instances "all" 2>/dev/null || echo "[]")
    project_roots=$(echo "$instances_json" | jq -r '.[].projectRoot // empty' | sort -u)
    local_root=$(get_project_root 2>/dev/null || echo "")
    if [[ -n "$local_root" ]]; then
        all_roots=$(printf "%s\n%s" "$project_roots" "$local_root" | sort -u | grep -v '^$')
    else
        all_roots="$project_roots"
    fi
    result="[]"
    while IFS= read -r pr; do
        [[ -z "$pr" || ! -d "$pr" ]] && continue
        local locks_dir=""
        if [[ -d "$pr/scripts/ralph/locks" ]]; then
            locks_dir="$pr/scripts/ralph/locks"
        elif [[ -d "$pr/.claude/ralph/locks" ]]; then
            locks_dir="$pr/.claude/ralph/locks"
        fi
        [[ -z "$locks_dir" ]] && continue
        local pname now
        pname=$(basename "$pr")
        now=$(date +%s)
        for lock_dir in "$locks_dir"/*.lock/; do
            [[ -d "$lock_dir" ]] || continue
            local sid owner ts age
            sid=$(basename "$lock_dir" .lock)
            owner="unknown"; ts=0
            if [[ -f "$lock_dir/owner.txt" ]]; then
                owner=$(cat "$lock_dir/owner.txt" | tr -d '\n')
            elif [[ -f "$lock_dir/owner" ]]; then
                owner=$(cat "$lock_dir/owner" | tr -d '\n')
            fi
            if [[ -f "$lock_dir/timestamp.txt" ]]; then
                ts=$(cat "$lock_dir/timestamp.txt" | tr -d '\n')
            elif [[ -f "$lock_dir/timestamp" ]]; then
                ts=$(cat "$lock_dir/timestamp" | tr -d '\n')
            fi
            age=$((now - ts))
            local is_stale="false"
            [[ "$age" -gt 7200 ]] && is_stale="true"
            result=$(echo "$result" | jq --arg s "$sid" --arg o "$owner" --argjson a "$age" \
                --argjson stale "$is_stale" --arg p "$pname" \
                '. + [{storyId:$s,owner:$o,age:$a,isStale:$stale,project:$p,isDead:false}]')
        done
    done <<< "$all_roots"
    echo "$result"
}

# =============================================================================
# RENDER FUNCTIONS
# =============================================================================

# render_header()
# Renders the dashboard header with per-project PRD progress
#
render_header() {
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

    # Get all projects PRD status
    local projects_status project_count
    projects_status=$(get_all_projects_prd_status)
    project_count=$(echo "$projects_status" | jq 'length')

    if [[ "$project_count" -eq 0 ]]; then
        local empty_text="  No PRD files found"
        local empty_padding=$((FRAME_WIDTH - ${#empty_text}))
        write_colored blue "${BOX_V}" "-n"
        write_colored gray "$empty_text" "-n"
        printf "%*s" "$empty_padding" ""
        write_colored blue "${BOX_V}"
    else
        # Show each project's progress (limited by MAX_PROJECTS)
        echo "$projects_status" | jq -c '.[]' | head -"$MAX_PROJECTS" | while IFS= read -r project; do
            [[ -z "$project" ]] && continue
            local name total complete progress_bar progress_text progress_padding
            name=$(echo "$project" | jq -r '.name')
            total=$(echo "$project" | jq -r '.total')
            complete=$(echo "$project" | jq -r '.complete')
            # Truncate name if needed
            [[ ${#name} -gt 12 ]] && name="${name:0:9}..."
            progress_bar=$(get_progress_bar "$complete" "$total" 20)
            progress_text="  $(printf '%-12s' "$name") $progress_bar ${complete}/${total}"
            progress_padding=$((FRAME_WIDTH - ${#progress_text}))
            write_colored blue "${BOX_V}" "-n"
            printf "%s%*s" "$progress_text" "$progress_padding" ""
            write_colored blue "${BOX_V}"
        done
        if [[ "$project_count" -gt "$MAX_PROJECTS" ]]; then
            local more_count=$((project_count - MAX_PROJECTS))
            local more_text="  ... and $more_count more projects"
            local more_padding=$((FRAME_WIDTH - ${#more_text}))
            write_colored blue "${BOX_V}" "-n"
            write_colored gray "$more_text" "-n"
            printf "%*s" "$more_padding" ""
            write_colored blue "${BOX_V}"
        fi
    fi

    # Separator
    write_colored blue "${BOX_VR}$(repeat_char "$BOX_H" $FRAME_WIDTH)${BOX_VL}"
}

# render_instances()
# Renders the instance table with dynamic column widths
#
render_instances() {
    local now
    now=$(date +%s)

    # Calculate dynamic column widths based on frame width
    # Fixed columns: STATE(12), ITER(7), RUNTIME(12) = 31 + 5 spaces = 36
    local fixed_width=36
    local available=$((FRAME_WIDTH - fixed_width))
    # Distribute to: PROJECT, STORY, BRANCH (ratio 3:2:4)
    local col_project=$((available * 3 / 9))
    local col_story=$((available * 2 / 9))
    local col_branch=$((available - col_project - col_story))
    # Minimums
    [[ "$col_project" -lt 10 ]] && col_project=10
    [[ "$col_story" -lt 8 ]] && col_story=8
    [[ "$col_branch" -lt 10 ]] && col_branch=10

    # Header row
    local header_line
    header_line=$(printf " %-${col_project}s %-${col_story}s %-12s %-7s %-12s %-${col_branch}s" \
        "PROJECT" "STORY" "STATE" "ITER" "RUNTIME" "BRANCH")
    local header_padding=$((FRAME_WIDTH - ${#header_line}))
    write_colored blue "${BOX_V}" "-n"
    write_colored white "$header_line" "-n"
    [[ "$header_padding" -gt 0 ]] && printf "%*s" "$header_padding" ""
    write_colored blue "${BOX_V}"

    # Divider row
    local div_project div_story div_branch
    div_project=$(repeat_char "-" "$col_project")
    div_story=$(repeat_char "-" "$col_story")
    div_branch=$(repeat_char "-" "$col_branch")
    local divider_line
    divider_line=$(printf " %-${col_project}s %-${col_story}s %-12s %-7s %-12s %-${col_branch}s" \
        "$div_project" "$div_story" "------------" "-------" "------------" "$div_branch")
    local div_padding=$((FRAME_WIDTH - ${#divider_line}))
    write_colored blue "${BOX_V}" "-n"
    write_colored gray "$divider_line" "-n"
    [[ "$div_padding" -gt 0 ]] && printf "%*s" "$div_padding" ""
    write_colored blue "${BOX_V}"

    # Get instances from global registry (shows all projects)
    local instances_json
    instances_json=$(get_ralph_global_instances "all" 2>/dev/null || echo "[]")

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
        # Limit instances to MAX_INSTANCES
        echo "$instances_json" | jq -c '.[]' | head -"$MAX_INSTANCES" | while IFS= read -r instance; do
            [[ -z "$instance" ]] && continue

            local is_dead state instance_id current_story iteration max_iterations
            local branch runtime_str project_name

            is_dead=$(echo "$instance" | jq -r '.isDead // false')
            state=$(echo "$instance" | jq -r '.state // "unknown"')

            if [[ "$is_dead" == "true" ]]; then
                state="dead"
            fi

            local color
            color=$(get_state_color "$state")

            instance_id=$(echo "$instance" | jq -r '.instanceId // ""')
            project_name=$(echo "$instance" | jq -r '.projectName // "local"')
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

            # Truncate to column widths
            project_name=$(truncate_string "${project_name:-"local"}" "$col_project")
            branch=$(truncate_string "${branch:-"-"}" "$col_branch")
            current_story=$(truncate_string "${current_story:-"-"}" "$col_story")
            [[ -z "$current_story" || "$current_story" == "null" ]] && current_story="-"

            # Iteration display
            local iter_str="${iteration}/${max_iterations}"

            # Build line with dynamic widths
            local line_part1
            line_part1=$(printf " %-${col_project}s %-${col_story}s " "$project_name" "$current_story")

            local state_part
            state_part=$(printf "%-12s " "$state")

            local line_part2
            line_part2=$(printf "%-7s %-12s %-${col_branch}s" "$iter_str" "$runtime_str" "$branch")

            local full_line="${line_part1}${state_part}${line_part2}"
            local line_padding=$((FRAME_WIDTH - ${#full_line}))

            write_colored blue "${BOX_V}" "-n"
            printf "%s" "$line_part1"
            write_colored "$color" "$state_part" "-n"
            printf "%s" "$line_part2"
            [[ "$line_padding" -gt 0 ]] && printf "%*s" "$line_padding" ""
            write_colored blue "${BOX_V}"
        done

        # Show "... and N more" if there are more instances
        if [[ "$instance_count" -gt "$MAX_INSTANCES" ]]; then
            local more_count=$((instance_count - MAX_INSTANCES))
            local more_line="  ... and $more_count more instances"
            local more_padding=$((FRAME_WIDTH - ${#more_line}))
            write_colored blue "${BOX_V}" "-n"
            write_colored gray "$more_line" "-n"
            printf "%*s" "$more_padding" ""
            write_colored blue "${BOX_V}"
        fi
    fi
}

# render_locks()
# Renders the active locks section from all projects
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

    # Get locks from all projects
    local locks_json lock_count
    locks_json=$(get_all_projects_locks 2>/dev/null || echo "[]")
    lock_count=$(echo "$locks_json" | jq 'length')

    if [[ "$lock_count" -eq 0 ]]; then
        local no_locks="    No active locks"
        local no_locks_padding=$((FRAME_WIDTH - ${#no_locks}))
        write_colored blue "${BOX_V}" "-n"
        write_colored gray "$no_locks" "-n"
        printf "%*s" "$no_locks_padding" ""
        write_colored blue "${BOX_V}"
    else
        # Calculate dynamic column widths for locks
        # Fixed: "    " prefix (4) + " by " (4) + " for " (5) + padding = ~15
        local lock_fixed=15
        local lock_available=$((FRAME_WIDTH - lock_fixed))
        # Distribute to: PROJECT, STORY, OWNER, DURATION (ratio 2:2:3:2)
        local lk_project=$((lock_available * 2 / 9))
        local lk_story=$((lock_available * 2 / 9))
        local lk_owner=$((lock_available * 3 / 9))
        local lk_duration=$((lock_available - lk_project - lk_story - lk_owner))
        [[ "$lk_project" -lt 8 ]] && lk_project=8
        [[ "$lk_story" -lt 8 ]] && lk_story=8
        [[ "$lk_owner" -lt 10 ]] && lk_owner=10
        [[ "$lk_duration" -lt 10 ]] && lk_duration=10

        echo "$locks_json" | jq -c '.[]' | head -"$MAX_LOCKS" | while IFS= read -r lock; do
            [[ -z "$lock" ]] && continue
            local story_id owner age is_stale project age_str color lock_line lock_line_padding
            story_id=$(echo "$lock" | jq -r '.storyId // ""')
            owner=$(echo "$lock" | jq -r '.owner // ""')
            age=$(echo "$lock" | jq -r '.age // 0')
            is_stale=$(echo "$lock" | jq -r '.isStale // false')
            project=$(echo "$lock" | jq -r '.project // ""')
            age_str=$(format_duration "$age")
            owner=$(truncate_string "$owner" "$lk_owner")
            project=$(truncate_string "$project" "$lk_project")
            story_id=$(truncate_string "$story_id" "$lk_story")
            color="green"
            [[ "$is_stale" == "true" ]] && color="yellow"
            lock_line=$(printf "    %-${lk_project}s %-${lk_story}s by %-${lk_owner}s for %-${lk_duration}s" "$project" "$story_id" "$owner" "$age_str")
            lock_line_padding=$((FRAME_WIDTH - ${#lock_line}))
            write_colored blue "${BOX_V}" "-n"
            write_colored "$color" "$lock_line" "-n"
            [[ "$lock_line_padding" -gt 0 ]] && printf "%*s" "$lock_line_padding" ""
            write_colored blue "${BOX_V}"
        done

        if [[ "$lock_count" -gt "$MAX_LOCKS" ]]; then
            local more_count=$((lock_count - MAX_LOCKS))
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
    # Update frame dimensions dynamically based on terminal size
    FRAME_WIDTH=$(get_frame_width)
    calculate_section_limits
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
    "$SCRIPT_DIR/ralph-cleanup.sh" --dead --terminated
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
