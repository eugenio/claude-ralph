#!/usr/bin/env bash
# =============================================================================
# ralph-status.sh - Display the current status of ralph PRD stories
# =============================================================================
#
# DESCRIPTION:
#   Reads the PRD file and displays a formatted summary of all user stories,
#   including completion status, progress bar, and current git branch.
#
# USAGE:
#   ./ralph-status.sh
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - jq (for JSON parsing)
#   - git (for branch display)
#
# =============================================================================

# Source the shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ralph-utils.sh
source "$SCRIPT_DIR/ralph-utils.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Column widths for the story table
readonly ID_WIDTH=8
readonly PRIORITY_WIDTH=8
readonly STATUS_WIDTH=10
readonly TITLE_WIDTH=40
readonly TOTAL_WIDTH=$((ID_WIDTH + PRIORITY_WIDTH + STATUS_WIDTH + TITLE_WIDTH + 6))

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# get_git_branch()
# Gets the current git branch name
# Output: Branch name string, or empty if not in a git repo
#
get_git_branch() {
    local branch
    if branch=$(git branch --show-current 2>/dev/null); then
        echo "$branch"
    fi
}

# repeat_char()
# Repeats a character n times
# Arguments:
#   $1 - Character to repeat
#   $2 - Number of times to repeat
# Output: String of repeated characters
#
repeat_char() {
    local char="$1"
    local count="$2"
    local result=""
    local i
    for ((i = 0; i < count; i++)); do
        result+="$char"
    done
    printf "%s" "$result"
}

# pad_right()
# Pads a string to the right with spaces
# Arguments:
#   $1 - String to pad
#   $2 - Total width
# Output: Padded string
#
pad_right() {
    local str="$1"
    local width="$2"
    printf "%-${width}s" "$str"
}

# truncate_string()
# Truncates a string and adds ellipsis if too long
# Arguments:
#   $1 - String to truncate
#   $2 - Maximum length
# Output: Truncated string
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
# DISPLAY FUNCTIONS
# =============================================================================

# show_banner()
# Displays the status banner with branch info
# Arguments:
#   $1 - Current git branch (optional)
#
show_banner() {
    local branch="$1"

    echo ""
    write_colored blue "$(repeat_char '═' 55)"
    write_colored yellow "              RALPH STATUS"
    write_colored blue "$(repeat_char '═' 55)"

    if [[ -n "$branch" ]]; then
        write_colored cyan "Branch: " "-n"
        write_colored white "$branch"
    fi
    echo ""
}

# show_progress_summary()
# Displays the progress summary with visual progress bar
# Uses global PRD_* variables from get_prd_status
#
show_progress_summary() {
    local complete="$1"
    local remaining="$2"
    local total="$3"
    local percentage="$4"

    # Progress bar
    local progress_bar
    progress_bar=$(render_progress_bar "$complete" "$total" 30)

    write_colored cyan "Progress: " "-n"

    if [[ "$percentage" -eq 100 ]]; then
        write_colored green "$progress_bar" "-n"
    elif [[ "$percentage" -ge 50 ]]; then
        write_colored yellow "$progress_bar" "-n"
    else
        write_colored red "$progress_bar" "-n"
    fi

    printf " "
    echo "${percentage}%"

    # Story counts
    write_colored cyan "Stories:  " "-n"
    write_colored green "$complete" "-n"
    printf " complete, "
    write_colored yellow "$remaining" "-n"
    echo " remaining (total: $total)"
    echo ""
}

# show_story_table()
# Displays all stories in a formatted table
# Arguments:
#   $1 - JSON array of stories
#
show_story_table() {
    local stories_json="$1"

    # Header separator
    write_colored gray "$(repeat_char '─' "$TOTAL_WIDTH")"

    # Header
    write_colored white "$(pad_right "ID" "$ID_WIDTH")  $(pad_right "Priority" "$PRIORITY_WIDTH")  $(pad_right "Status" "$STATUS_WIDTH")  Title"

    # Header separator
    write_colored gray "$(repeat_char '─' "$TOTAL_WIDTH")"

    # Sort stories by priority and iterate
    local sorted_stories
    sorted_stories=$(echo "$stories_json" | jq -c 'sort_by(.priority) | .[]')

    while IFS= read -r story; do
        [[ -z "$story" ]] && continue

        local story_id priority passes title status status_color

        story_id=$(echo "$story" | jq -r '.id')
        priority=$(echo "$story" | jq -r '.priority')
        passes=$(echo "$story" | jq -r '.passes')
        title=$(echo "$story" | jq -r '.title')

        if [[ "$passes" == "true" ]]; then
            status="COMPLETE"
            status_color="green"
        else
            status="PENDING"
            status_color="yellow"
        fi

        # Truncate title if too long
        title=$(truncate_string "$title" "$TITLE_WIDTH")

        # Print the row
        printf "%s  %s  " \
            "$(pad_right "$story_id" "$ID_WIDTH")" \
            "$(pad_right "$priority" "$PRIORITY_WIDTH")"

        write_colored "$status_color" "$(pad_right "$status" "$STATUS_WIDTH")" "-n"
        printf "  %s\n" "$title"

    done <<< "$sorted_stories"

    # Footer separator
    write_colored gray "$(repeat_char '─' "$TOTAL_WIDTH")"
    echo ""
}

# show_incomplete_stories()
# Lists incomplete stories with priorities
# Arguments:
#   $1 - JSON array of incomplete stories (sorted by priority)
#
show_incomplete_stories() {
    local incomplete_json="$1"

    local count
    count=$(echo "$incomplete_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        return
    fi

    write_colored yellow "Incomplete Stories (by priority):"
    echo ""

    echo "$incomplete_json" | jq -c '.[]' | while IFS= read -r story; do
        [[ -z "$story" ]] && continue

        local story_id priority title
        story_id=$(echo "$story" | jq -r '.id')
        priority=$(echo "$story" | jq -r '.priority')
        title=$(echo "$story" | jq -r '.title')

        printf "  "
        write_colored cyan "[$priority]" "-n"
        printf " "
        write_colored white "$story_id: " "-n"
        write_colored gray "$title"
    done

    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Load paths
    eval "$(get_ralph_paths)"

    # Check for PRD file
    if [[ ! -f "$PRD_FILE" ]]; then
        write_colored red "Error: prd.json not found"
        echo ""
        write_colored gray "Expected location: $PRD_FILE"
        echo ""
        write_colored yellow "To get started:"
        echo "  1. Copy prd.json.example to prd.json"
        echo "  2. Edit prd.json with your user stories"
        echo "  3. Run this script again"
        exit 1
    fi

    # Read PRD
    local prd_json
    if ! prd_json=$(read_prd_json "$PRD_FILE"); then
        write_colored red "Error: Failed to parse prd.json"
        echo "Please check the file contains valid JSON."
        exit 1
    fi

    # Get branch
    local branch
    branch=$(get_git_branch)

    # Show banner
    show_banner "$branch"

    # Get status
    eval "$(get_prd_status "$prd_json")"

    if [[ "$PRD_TOTAL" -eq 0 ]]; then
        write_colored yellow "No user stories found in prd.json"
        echo "Add user stories to the \"userStories\" array to get started."
        exit 0
    fi

    # Show progress summary
    show_progress_summary "$PRD_COMPLETE" "$PRD_REMAINING" "$PRD_TOTAL" "$PRD_PERCENTAGE"

    # Get stories array
    local stories_json
    stories_json=$(echo "$prd_json" | jq '.userStories')

    # Show story table
    show_story_table "$stories_json"

    # Get incomplete stories
    local incomplete_json
    incomplete_json=$(get_incomplete_stories "$prd_json")

    local incomplete_count
    incomplete_count=$(echo "$incomplete_json" | jq 'length')

    if [[ "$incomplete_count" -gt 0 ]]; then
        show_incomplete_stories "$incomplete_json"
    else
        write_colored green "All stories complete!"
        echo ""
    fi
}

# Run main
main "$@"
