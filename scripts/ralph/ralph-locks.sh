#!/usr/bin/env bash
# =============================================================================
# ralph-locks.sh - Manage story locks for multi-instance Ralph
# =============================================================================
#
# DESCRIPTION:
#   Provides commands to view, release, and clean up story locks used by
#   concurrent Ralph instances.
#
# USAGE:
#   ./ralph-locks.sh [command] [options]
#
# COMMANDS:
#   status              Show all current locks (default)
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

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
# shellcheck source=ralph-utils.sh
source "$SCRIPT_DIR/ralph-utils.sh"

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_help() {
    echo ""
    write_colored "cyan" "Usage: ./ralph-locks.sh <command> [options]"
    echo ""
    write_colored "yellow" "Commands:"
    echo "  status              Show all current locks"
    echo "  release -s STORY_ID Force release a specific lock"
    echo "  release-all         Force release all locks"
    echo "  cleanup             Remove stale locks (>2 hours or dead owner)"
    echo "  help                Show this help"
    echo ""
    write_colored "yellow" "Examples:"
    echo "  ./ralph-locks.sh status"
    echo "  ./ralph-locks.sh release -s US-001"
    echo "  ./ralph-locks.sh cleanup"
    echo ""
}

# =============================================================================
# FORMAT FUNCTIONS
# =============================================================================

# format_age()
# Formats age in seconds to human-readable format
# Arguments:
#   $1 - Age in seconds
# Output: Formatted string (e.g., "5m", "2h")
#
format_age() {
    local age="$1"

    if [[ "$age" -lt 60 ]]; then
        echo "${age}s"
    elif [[ "$age" -lt 3600 ]]; then
        echo "$((age / 60))m"
    else
        echo "$((age / 3600))h"
    fi
}

# =============================================================================
# COMMAND FUNCTIONS
# =============================================================================

# show_lock_status()
# Displays all current locks with their status
#
show_lock_status() {
    echo ""
    write_colored "blue" "$(printf '%0.s═' {1..60})"
    write_colored "cyan" "                    RALPH LOCK STATUS"
    write_colored "blue" "$(printf '%0.s═' {1..60})"
    echo ""

    local locks_json
    locks_json=$(get_ralph_story_locks)

    local lock_count
    lock_count=$(echo "$locks_json" | jq 'length')

    if [[ "$lock_count" -eq 0 ]]; then
        write_colored "green" "  No active locks"
        echo ""
        return 0
    fi

    # Header
    printf "${COLOR_WHITE}%-12s %-30s %-10s %-10s${COLOR_RESET}\n" "STORY" "OWNER" "AGE" "STATUS"
    printf "%-12s %-30s %-10s %-10s\n" "-----" "-----" "---" "------"

    # Process each lock
    echo "$locks_json" | jq -c '.[]' | while read -r lock; do
        local story_id owner age is_dead is_stale

        story_id=$(echo "$lock" | jq -r '.storyId')
        owner=$(echo "$lock" | jq -r '.owner')
        age=$(echo "$lock" | jq -r '.age')
        is_dead=$(echo "$lock" | jq -r '.isDead')
        is_stale=$(echo "$lock" | jq -r '.isStale')

        # Format age
        local age_str
        age_str=$(format_age "$age")

        # Determine status and color
        local status color
        if [[ "$is_dead" == "true" ]]; then
            status="dead owner"
            color="red"
        elif [[ "$is_stale" == "true" ]]; then
            status="stale"
            color="yellow"
        else
            status="valid"
            color="green"
        fi

        # Truncate owner if too long
        local owner_short
        if [[ ${#owner} -gt 30 ]]; then
            owner_short="${owner:0:27}..."
        else
            owner_short="$owner"
        fi

        printf "%-12s %-30s %-10s " "$story_id" "$owner_short" "$age_str"
        write_colored "$color" "$status"
    done

    echo ""
}

# invoke_release()
# Releases a specific lock
# Arguments:
#   $1 - Story ID to release
#
invoke_release() {
    local story_id="$1"

    if [[ -z "$story_id" ]]; then
        write_colored "red" "Error: StoryId required for release command"
        echo "Usage: ./ralph-locks.sh release -s US-001"
        exit 1
    fi

    local lock_info
    if ! lock_info=$(get_ralph_story_lock "$story_id" 2>/dev/null); then
        write_colored "yellow" "No lock found for $story_id"
        return 0
    fi

    local owner
    owner=$(echo "$lock_info" | jq -r '.owner')

    write_colored "yellow" "Releasing lock for $story_id (owner: $owner)..."

    if unlock_ralph_story "$story_id" "force"; then
        write_colored "green" "Lock released"
    else
        write_colored "red" "Failed to release lock"
    fi
}

# invoke_release_all()
# Releases all current locks
#
invoke_release_all() {
    write_colored "yellow" "Releasing all locks..."

    local locks_json
    locks_json=$(get_ralph_story_locks)
    local count=0

    # Use process substitution to avoid subshell counter issue
    while read -r story_id; do
        if [[ -n "$story_id" ]]; then
            if unlock_ralph_story "$story_id" "force"; then
                write_colored "gray" "  Released: $story_id"
                ((count++)) || true
            fi
        fi
    done < <(echo "$locks_json" | jq -r '.[].storyId')

    write_colored "green" "Released $count locks"
}

# invoke_cleanup()
# Removes stale and dead-owner locks
#
invoke_cleanup() {
    write_colored "blue" "Cleaning up stale locks..."

    local locks_json
    locks_json=$(get_ralph_story_locks)
    local cleaned=0

    # Use process substitution to avoid subshell counter issue
    while read -r lock; do
        [[ -z "$lock" ]] && continue

        local story_id is_dead age

        story_id=$(echo "$lock" | jq -r '.storyId')
        is_dead=$(echo "$lock" | jq -r '.isDead')
        age=$(echo "$lock" | jq -r '.age')

        local reason
        if [[ "$is_dead" == "true" ]]; then
            reason="dead owner"
        else
            reason="stale (${age}s)"
        fi

        write_colored "yellow" "  Removing: $story_id - $reason"

        if unlock_ralph_story "$story_id" "force"; then
            ((cleaned++)) || true
        fi
    done < <(echo "$locks_json" | jq -c '.[] | select(.isDead == true or .isStale == true)')

    if [[ "$cleaned" -eq 0 ]]; then
        write_colored "green" "No stale locks found"
    else
        write_colored "green" "Cleaned up $cleaned stale locks"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-status}"
    shift || true

    local story_id=""

    # Parse options for release command
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--story)
                story_id="${2:-}"
                shift 2 || { write_colored "red" "Error: -s requires a story ID"; exit 1; }
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                # Unknown option, might be story ID without flag
                if [[ -z "$story_id" ]]; then
                    story_id="$1"
                fi
                shift
                ;;
        esac
    done

    case "$command" in
        status)
            show_lock_status
            ;;
        release)
            invoke_release "$story_id"
            ;;
        release-all)
            invoke_release_all
            ;;
        cleanup)
            invoke_cleanup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            write_colored "red" "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main only if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
