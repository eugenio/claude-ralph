#!/usr/bin/env bash
# =============================================================================
# ralph-locks.sh - Manage story locks for multi-instance Ralph
# =============================================================================
#
# SYNOPSIS:
#   ralph-locks.sh <command> [options]
#
# DESCRIPTION:
#   Provides commands to view, release, and clean up story locks
#   used by concurrent Ralph instances.
#
# COMMANDS:
#   status              Show all current locks
#   release -s STORY_ID Force release a specific lock
#   release-all         Force release all locks
#   cleanup             Remove stale locks (>2 hours or dead owner)
#   help                Show this help
#
# EXAMPLES:
#   ./ralph-locks.sh status
#   ./ralph-locks.sh release -s US-001
#   ./ralph-locks.sh cleanup
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
# DISPLAY FUNCTIONS
# =============================================================================

show_help() {
    echo ""
    echo -e "${COLOR_CYAN}Usage: ./ralph-locks.sh <Command> [Options]${COLOR_RESET}"
    echo ""
    echo -e "${COLOR_YELLOW}Commands:${COLOR_RESET}"
    echo "  status              Show all current locks"
    echo "  release -s STORY_ID Force release a specific lock"
    echo "  release-all         Force release all locks"
    echo "  cleanup             Remove stale locks (>2 hours or dead owner)"
    echo "  help                Show this help"
    echo ""
    echo -e "${COLOR_YELLOW}Examples:${COLOR_RESET}"
    echo "  ./ralph-locks.sh status"
    echo "  ./ralph-locks.sh release -s US-001"
    echo "  ./ralph-locks.sh cleanup"
    echo ""
}

show_lock_status() {
    local separator
    separator=$(printf '═%.0s' {1..60})

    echo ""
    echo -e "${COLOR_BLUE}${separator}${COLOR_RESET}"
    echo -e "${COLOR_CYAN}                    RALPH LOCK STATUS${COLOR_RESET}"
    echo -e "${COLOR_BLUE}${separator}${COLOR_RESET}"
    echo ""

    local locks_json
    locks_json=$(get_ralph_story_locks)

    local lock_count
    lock_count=$(echo "$locks_json" | jq 'length')

    if [[ "$lock_count" -eq 0 ]]; then
        echo -e "  ${COLOR_GREEN}No active locks${COLOR_RESET}"
        echo ""
        return
    fi

    # Header
    printf "${COLOR_WHITE}%-12s %-30s %-10s %-10s${COLOR_RESET}\n" "STORY" "OWNER" "AGE" "STATUS"
    printf "%-12s %-30s %-10s %-10s\n" "-----" "-----" "---" "------"

    # Iterate over locks
    echo "$locks_json" | jq -c '.[]' | while read -r lock; do
        local story_id owner age is_dead is_stale

        story_id=$(echo "$lock" | jq -r '.storyId')
        owner=$(echo "$lock" | jq -r '.owner')
        age=$(echo "$lock" | jq -r '.age')
        is_dead=$(echo "$lock" | jq -r '.isDead')
        is_stale=$(echo "$lock" | jq -r '.isStale')

        # Format age
        local age_str
        if [[ "$age" -lt 60 ]]; then
            age_str="${age}s"
        elif [[ "$age" -lt 3600 ]]; then
            age_str="$((age / 60))m"
        else
            age_str="$((age / 3600))h"
        fi

        # Determine status and color
        local status color
        if [[ "$is_dead" == "true" ]]; then
            status="dead owner"
            color="$COLOR_RED"
        elif [[ "$is_stale" == "true" ]]; then
            status="stale"
            color="$COLOR_YELLOW"
        else
            status="valid"
            color="$COLOR_GREEN"
        fi

        # Truncate owner if too long
        local owner_short
        if [[ "${#owner}" -gt 30 ]]; then
            owner_short="${owner:0:27}..."
        else
            owner_short="$owner"
        fi

        printf "%-12s %-30s %-10s " "$story_id" "$owner_short" "$age_str"
        echo -e "${color}${status}${COLOR_RESET}"
    done

    echo ""
}

# =============================================================================
# COMMAND FUNCTIONS
# =============================================================================

cmd_release() {
    local story_id="$1"

    if [[ -z "$story_id" ]]; then
        echo -e "${COLOR_RED}Error: StoryId required for release command${COLOR_RESET}"
        echo "Usage: ./ralph-locks.sh release -s US-001"
        exit 1
    fi

    local lock_info
    if ! lock_info=$(get_ralph_story_lock "$story_id" 2>/dev/null); then
        echo -e "${COLOR_YELLOW}No lock found for $story_id${COLOR_RESET}"
        return
    fi

    local owner
    owner=$(echo "$lock_info" | jq -r '.owner')

    echo -e "${COLOR_YELLOW}Releasing lock for $story_id (owner: $owner)...${COLOR_RESET}"

    if unlock_ralph_story "$story_id" "force"; then
        echo -e "${COLOR_GREEN}Lock released${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}Failed to release lock${COLOR_RESET}"
    fi
}

cmd_release_all() {
    echo -e "${COLOR_YELLOW}Releasing all locks...${COLOR_RESET}"

    local locks_json
    locks_json=$(get_ralph_story_locks)

    local lock_count
    lock_count=$(echo "$locks_json" | jq 'length')

    echo "$locks_json" | jq -r '.[].storyId' | while read -r story_id; do
        if unlock_ralph_story "$story_id" "force"; then
            echo -e "  ${COLOR_GRAY}Released: $story_id${COLOR_RESET}"
        fi
    done

    echo -e "${COLOR_GREEN}Released $lock_count locks${COLOR_RESET}"
}

cmd_cleanup() {
    echo -e "${COLOR_BLUE}Cleaning up stale locks...${COLOR_RESET}"

    local locks_json
    locks_json=$(get_ralph_story_locks)

    local cleaned=0

    echo "$locks_json" | jq -c '.[]' | while read -r lock; do
        local story_id is_dead is_stale age

        story_id=$(echo "$lock" | jq -r '.storyId')
        is_dead=$(echo "$lock" | jq -r '.isDead')
        is_stale=$(echo "$lock" | jq -r '.isStale')
        age=$(echo "$lock" | jq -r '.age')

        if [[ "$is_dead" == "true" || "$is_stale" == "true" ]]; then
            local reason
            if [[ "$is_dead" == "true" ]]; then
                reason="dead owner"
            else
                reason="stale (${age}s)"
            fi

            echo -e "  ${COLOR_YELLOW}Removing: $story_id - $reason${COLOR_RESET}"

            if unlock_ralph_story "$story_id" "force"; then
                ((cleaned++)) || true
            fi
        fi
    done

    # Count stale locks that were cleaned
    local stale_count
    stale_count=$(echo "$locks_json" | jq '[.[] | select(.isDead == true or .isStale == true)] | length')

    if [[ "$stale_count" -eq 0 ]]; then
        echo -e "${COLOR_GREEN}No stale locks found${COLOR_RESET}"
    else
        echo -e "${COLOR_GREEN}Cleaned up $stale_count stale locks${COLOR_RESET}"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-status}"
    shift || true

    # Parse remaining arguments
    local story_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--story-id)
                story_id="${2:-}"
                shift 2 || { echo "Error: -s requires an argument"; exit 1; }
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                # Unknown option, might be story_id directly for backwards compatibility
                if [[ -z "$story_id" && "$1" != -* ]]; then
                    story_id="$1"
                    shift
                else
                    echo "Unknown option: $1"
                    show_help
                    exit 1
                fi
                ;;
        esac
    done

    case "$command" in
        status)
            show_lock_status
            ;;
        release)
            cmd_release "$story_id"
            ;;
        release-all|releaseall)
            cmd_release_all
            ;;
        cleanup)
            cmd_cleanup
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
