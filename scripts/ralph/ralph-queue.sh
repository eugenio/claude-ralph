#!/usr/bin/env bash
# =============================================================================
# ralph-queue.sh - CLI for managing the global PRD queue
# =============================================================================
#
# DESCRIPTION:
#   Command-line interface for managing the global PRD queue that enables
#   cross-project automation. Workers can pick up queued PRDs when their
#   current work completes.
#
# USAGE:
#   ralph-queue.sh <command> [options]
#
# COMMANDS:
#   add      Add a PRD to the queue
#   list     Show queue status
#   remove   Remove an entry from the queue
#   clear    Clear completed entries
#   status   Show queue summary
#   help     Show this help message
#
# EXAMPLES:
#   ralph-queue.sh add -p /path/to/prd.json -r /path/to/project
#   ralph-queue.sh list
#   ralph-queue.sh remove -i entry-id
#   ralph-queue.sh clear
#
# =============================================================================

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ralph-utils.sh
source "$SCRIPT_DIR/ralph-utils.sh"

# =============================================================================
# DISPLAY FUNCTIONS
# =============================================================================

show_help() {
    cat <<'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                         RALPH QUEUE MANAGEMENT                             ║
╚════════════════════════════════════════════════════════════════════════════╝

Usage: ralph-queue.sh <command> [options]

Commands:
  add      Add a PRD to the queue
  list     Show queue entries
  remove   Remove an entry from the queue
  clear    Clear completed entries
  status   Show queue summary
  check    Check if a PRD is complete before adding
  help     Show this help message

Add Command:
  -p, --prd PATH        Path to prd.json file (required)
  -r, --project PATH    Project root directory (required)
  --priority N          Priority (1-99, lower = higher priority, default: 10)

List Command:
  -s, --status STATUS   Filter by status: pending, active, completed, failed, all
                        (default: all)

Remove Command:
  -i, --id ID           Entry ID to remove (required)

Check Command:
  -p, --prd PATH        Path to prd.json file (required)
  -q, --quiet           Quiet mode (exit code only: 0=complete, 1=incomplete)

Examples:
  # Add a PRD to the queue
  ralph-queue.sh add -p /home/user/project/prd.json -r /home/user/project

  # Add with high priority
  ralph-queue.sh add -p /path/prd.json -r /path/project --priority 1

  # List all queue entries
  ralph-queue.sh list

  # List only pending entries
  ralph-queue.sh list -s pending

  # Remove an entry
  ralph-queue.sh remove -i q-1234567890-abcd1234

  # Clear completed entries
  ralph-queue.sh clear

  # Show queue summary
  ralph-queue.sh status
EOF
}

show_banner() {
    local title="$1"
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    printf "║ %-74s ║\n" "$title"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

# =============================================================================
# COMMAND: ADD
# =============================================================================

cmd_add() {
    local prd_path=""
    local project_root=""
    local priority=10

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prd)
                prd_path="$2"
                shift 2
                ;;
            -r|--project)
                project_root="$2"
                shift 2
                ;;
            --priority)
                priority="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                echo "Use 'ralph-queue.sh help' for usage information." >&2
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$prd_path" ]]; then
        echo "Error: PRD path required. Use -p or --prd" >&2
        return 1
    fi

    if [[ -z "$project_root" ]]; then
        echo "Error: Project root required. Use -r or --project" >&2
        return 1
    fi

    # Convert to absolute paths if needed
    if [[ ! "$prd_path" = /* ]]; then
        prd_path="$(cd "$(dirname "$prd_path")" && pwd)/$(basename "$prd_path")"
    fi

    if [[ ! "$project_root" = /* ]]; then
        project_root="$(cd "$project_root" && pwd)"
    fi

    # Validate paths exist
    if [[ ! -f "$prd_path" ]]; then
        echo "Error: PRD file not found: $prd_path" >&2
        return 1
    fi

    if [[ ! -d "$project_root" ]]; then
        echo "Error: Project root not found: $project_root" >&2
        return 1
    fi

    # Add to queue
    local entry_id
    if entry_id=$(add_ralph_queue_entry "$prd_path" "$project_root" "$priority"); then
        echo ""
        write_colored green "✓ Added to queue successfully"
        echo ""
        echo "  Entry ID:    $entry_id"
        echo "  PRD:         $prd_path"
        echo "  Project:     $project_root"
        echo "  Priority:    $priority"
        echo ""
    else
        echo "Error: Failed to add entry to queue" >&2
        return 1
    fi
}

# =============================================================================
# COMMAND: LIST
# =============================================================================

cmd_list() {
    local status_filter="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--status)
                status_filter="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    show_banner "RALPH QUEUE - $(echo "$status_filter" | tr '[:lower:]' '[:upper:]') ENTRIES"

    local entries
    entries=$(get_ralph_queue_entries "$status_filter")

    local count
    count=$(echo "$entries" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "  No entries found."
        echo ""
        return 0
    fi

    # Table header
    printf "  %-24s %-10s %-8s %-30s %-4s\n" "ID" "STATUS" "PRIORITY" "PROJECT" "STORIES"
    printf "  %-24s %-10s %-8s %-30s %-4s\n" "------------------------" "----------" "--------" "------------------------------" "----"

    # Table rows
    echo "$entries" | jq -r '.[] | [.id, .status, .priority, .projectRoot, .prdPath] | @tsv' | while IFS=$'\t' read -r id status priority project_root prd_path; do
        # Truncate long values
        local short_id="${id:0:24}"
        local short_project
        short_project=$(basename "$project_root")
        [[ ${#short_project} -gt 30 ]] && short_project="${short_project:0:27}..."

        # Get story count from PRD if accessible
        local stories="?"
        if [[ -f "$prd_path" ]]; then
            local total complete
            total=$(jq '.userStories | length' "$prd_path" 2>/dev/null || echo "0")
            complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_path" 2>/dev/null || echo "0")
            stories="$complete/$total"
        fi

        # Color based on status
        local status_color="white"
        case "$status" in
            pending)   status_color="yellow" ;;
            active)    status_color="cyan" ;;
            completed) status_color="green" ;;
            failed)    status_color="red" ;;
        esac

        printf "  %-24s " "$short_id"
        write_colored "$status_color" "$(printf "%-10s" "$status")" "-n"
        printf " %-8s %-30s %-4s\n" "$priority" "$short_project" "$stories"
    done

    echo ""
    echo "  Total: $count entries"
    echo ""
}

# =============================================================================
# COMMAND: REMOVE
# =============================================================================

cmd_remove() {
    local entry_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--id)
                entry_id="$2"
                shift 2
                ;;
            *)
                # Assume positional argument is ID
                entry_id="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$entry_id" ]]; then
        echo "Error: Entry ID required. Use -i or --id" >&2
        return 1
    fi

    # Get entry info before removing
    local entry
    if entry=$(get_ralph_queue_entry "$entry_id" 2>/dev/null); then
        local project_root
        project_root=$(echo "$entry" | jq -r '.projectRoot')

        if remove_ralph_queue_entry "$entry_id"; then
            echo ""
            write_colored green "✓ Removed entry from queue"
            echo ""
            echo "  Entry ID: $entry_id"
            echo "  Project:  $project_root"
            echo ""
        else
            echo "Error: Failed to remove entry" >&2
            return 1
        fi
    else
        echo ""
        write_colored yellow "Entry not found: $entry_id"
        echo ""
        return 1
    fi
}

# =============================================================================
# COMMAND: CLEAR
# =============================================================================

cmd_clear() {
    show_banner "CLEARING COMPLETED ENTRIES"

    local cleared_count
    cleared_count=$(clear_ralph_queue_completed)

    if [[ "$cleared_count" -eq 0 ]]; then
        echo "  No completed entries to clear."
    else
        write_colored green "  ✓ Cleared $cleared_count completed entries"
    fi
    echo ""
}

# =============================================================================
# COMMAND: STATUS
# =============================================================================

cmd_status() {
    show_banner "RALPH QUEUE STATUS"

    local summary
    summary=$(get_ralph_queue_summary)

    local total pending active completed failed
    total=$(echo "$summary" | jq '.total')
    pending=$(echo "$summary" | jq '.pending')
    active=$(echo "$summary" | jq '.active')
    completed=$(echo "$summary" | jq '.completed')
    failed=$(echo "$summary" | jq '.failed')

    echo "  Queue Summary:"
    echo ""
    printf "    %-12s %d\n" "Total:" "$total"
    printf "    "
    write_colored yellow "$(printf "%-12s" "Pending:")" "-n"
    echo " $pending"
    printf "    "
    write_colored cyan "$(printf "%-12s" "Active:")" "-n"
    echo " $active"
    printf "    "
    write_colored green "$(printf "%-12s" "Completed:")" "-n"
    echo " $completed"
    printf "    "
    write_colored red "$(printf "%-12s" "Failed:")" "-n"
    echo " $failed"
    echo ""

    # Show queue file location
    local queue_file
    queue_file=$(get_ralph_queue_file)
    echo "  Queue file: $queue_file"
    echo ""
}

# =============================================================================
# COMMAND: CHECK
# =============================================================================

cmd_check() {
    local prd_path=""
    local quiet=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prd)
                prd_path="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet=1
                shift
                ;;
            *)
                # Assume positional argument is prd path
                if [[ -z "$prd_path" ]]; then
                    prd_path="$1"
                else
                    echo "Error: Unknown option: $1" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$prd_path" ]]; then
        echo "Error: PRD path required. Use -p or --prd" >&2
        return 1
    fi

    # Convert to absolute path if needed
    if [[ ! "$prd_path" = /* ]]; then
        prd_path="$(cd "$(dirname "$prd_path")" && pwd)/$(basename "$prd_path")"
    fi

    if [[ ! -f "$prd_path" ]]; then
        echo "Error: PRD file not found: $prd_path" >&2
        return 1
    fi

    # Get story counts
    local total complete incomplete
    total=$(jq '.userStories | length' "$prd_path" 2>/dev/null || echo "0")
    complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_path" 2>/dev/null || echo "0")
    incomplete=$((total - complete))

    if [[ "$quiet" -eq 1 ]]; then
        # Quiet mode: output count and return exit code
        echo "$incomplete"
        if [[ "$incomplete" -eq 0 && "$total" -gt 0 ]]; then
            return 0  # Complete
        else
            return 1  # Incomplete or empty
        fi
    fi

    # Verbose output
    echo ""
    if [[ "$total" -eq 0 ]]; then
        write_colored red "PRD has no stories: $prd_path"
        echo ""
        echo "Incomplete: 0"
        return 1
    elif [[ "$incomplete" -eq 0 ]]; then
        write_colored green "PRD COMPLETE: $complete/$total stories done"
        echo ""
        echo "  PRD: $prd_path"
        echo ""
        echo "Incomplete: 0"
        return 0
    else
        write_colored yellow "PRD INCOMPLETE: $complete/$total stories done, $incomplete remaining"
        echo ""
        echo "  PRD: $prd_path"
        echo ""
        echo "  Incomplete stories:"
        jq -r '.userStories[] | select(.passes != true) | "    - \(.id): \(.title)"' "$prd_path" 2>/dev/null
        echo ""
        echo "Incomplete: $incomplete"
        return 1
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-status}"
    shift || true

    case "$command" in
        add)
            cmd_add "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        remove|rm)
            cmd_remove "$@"
            ;;
        clear)
            cmd_clear "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        check)
            cmd_check "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown command: $command" >&2
            echo "Use 'ralph-queue.sh help' for usage information." >&2
            exit 1
            ;;
    esac
}

main "$@"
