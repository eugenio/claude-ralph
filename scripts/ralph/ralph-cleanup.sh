#!/usr/bin/env bash
# =============================================================================
# ralph-cleanup.sh - Clean up old and dead Ralph instances
# =============================================================================
#
# SYNOPSIS:
#   ralph-cleanup.sh [options]
#
# DESCRIPTION:
#   Removes dead instances (no heartbeat > 5 min) and old instances
#   (older than configured TTL). Shows instance summary when run without flags.
#
# OPTIONS:
#   -d, --dead      Clean up dead instances (no heartbeat > 5 min)
#   -t, --terminated  Clean up terminated instances (cleanly finished)
#   -o, --old       Clean up old instances (default TTL: 7 days)
#   -a, --all       Clean up dead, terminated, and old instances
#   --dry-run       Show what would be cleaned without actually deleting
#   -h, --help      Show this help message
#
# ENVIRONMENT:
#   RALPH_CLEANUP_TTL   Days before instance is considered old (default: 7)
#
# EXAMPLES:
#   ./ralph-cleanup.sh
#   ./ralph-cleanup.sh --dead
#   ./ralph-cleanup.sh --all --dry-run
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
# GLOBAL VARIABLES
# =============================================================================

DRY_RUN=false
CLEAN_DEAD=false
CLEAN_TERMINATED=false
CLEAN_OLD=false

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# show_help()
# Displays usage information
#
show_help() {
    echo ""
    write_colored cyan "Usage: ./ralph-cleanup.sh [options]"
    echo ""
    write_colored yellow "Options:"
    echo "  -d, --dead        Clean up dead instances (no heartbeat > 5 min)"
    echo "  -t, --terminated  Clean up terminated instances (cleanly finished)"
    echo "  -o, --old         Clean up old instances (default TTL: 7 days)"
    echo "  -a, --all         Clean up dead, terminated, and old instances"
    echo "  --dry-run       Preview mode - show actions without executing"
    echo "  -h, --help      Show this help message"
    echo ""
    write_colored yellow "Environment Variables:"
    echo "  RALPH_CLEANUP_TTL   Days before instance is considered old (default: 7)"
    echo ""
    write_colored yellow "Examples:"
    echo "  ./ralph-cleanup.sh                # Show instance summary"
    echo "  ./ralph-cleanup.sh --dead         # Clean up dead instances"
    echo "  ./ralph-cleanup.sh --all --dry-run  # Preview full cleanup"
    echo ""
}

# repeat_char()
# Repeats a character n times
# Arguments:
#   $1 - Character to repeat
#   $2 - Number of times to repeat
# Output: Repeated string
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

# =============================================================================
# DISPLAY FUNCTIONS
# =============================================================================

# show_summary()
# Displays instance summary statistics
#
show_summary() {
    echo ""
    write_colored blue "$(repeat_char '═' 60)"
    write_colored cyan "                  INSTANCE SUMMARY (Global)"
    write_colored blue "$(repeat_char '═' 60)"
    echo ""

    # Get all instances from global registry including dead ones
    local instances_json
    instances_json=$(get_ralph_global_instances "all" 2>/dev/null || echo "[]")

    local total running completed terminated dead

    total=$(echo "$instances_json" | jq 'length')
    running=$(echo "$instances_json" | jq '[.[] | select(.isDead == false and .state != "terminated" and .state != "completed")] | length')
    completed=$(echo "$instances_json" | jq '[.[] | select(.state == "completed")] | length')
    terminated=$(echo "$instances_json" | jq '[.[] | select(.state == "terminated")] | length')
    dead=$(echo "$instances_json" | jq '[.[] | select(.isDead == true)] | length')

    echo "Total instances: $total"
    write_colored green "  Running:    $running"
    write_colored blue "  Completed:  $completed"
    write_colored yellow "  Terminated: $terminated"
    write_colored red "  Dead:       $dead"
    echo ""

    # Show locks
    local locks_json lock_count
    locks_json=$(get_ralph_story_locks)
    lock_count=$(echo "$locks_json" | jq 'length')
    echo "Active locks: $lock_count"
    echo ""
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# clear_dead_instances()
# Marks dead instances as terminated and releases their locks
#
clear_dead_instances() {
    write_colored blue "Checking for dead instances (global)..."

    local instances_json
    instances_json=$(get_ralph_global_instances "all" 2>/dev/null || echo "[]")

    local dead_instances
    dead_instances=$(echo "$instances_json" | jq '[.[] | select(.isDead == true)]')
    local dead_count
    dead_count=$(echo "$dead_instances" | jq 'length')

    if [[ "$dead_count" -eq 0 ]]; then
        write_colored green "No dead instances found"
        return
    fi

    local cleaned=0
    local i

    for ((i = 0; i < dead_count; i++)); do
        local instance
        instance=$(echo "$dead_instances" | jq ".[$i]")

        local instance_id project_name heartbeat_age project_root
        instance_id=$(echo "$instance" | jq -r '.instanceId')
        project_name=$(echo "$instance" | jq -r '.projectName // "unknown"')
        heartbeat_age=$(echo "$instance" | jq -r '.heartbeatAge')
        project_root=$(echo "$instance" | jq -r '.projectRoot // ""')

        write_colored yellow "  Dead: $project_name ($instance_id) - no heartbeat for ${heartbeat_age}s"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "    [DRY RUN] Would mark as terminated and release locks"
            continue
        fi

        # Find the instance directory via global registry
        local global_dir
        global_dir=$(get_ralph_global_dir)
        local link_path="$global_dir/instances/${project_name}-${instance_id}"
        local instance_dir=""

        if [[ -L "$link_path" ]]; then
            instance_dir=$(readlink -f "$link_path" 2>/dev/null) || true
        fi

        # Update status to terminated
        if [[ -n "$instance_dir" && -f "$instance_dir/status.json" ]]; then
            local status_json
            status_json=$(cat "$instance_dir/status.json")
            status_json=$(echo "$status_json" | jq '.state = "terminated"')
            echo "$status_json" > "$instance_dir/status.json"
        fi

        # Release any locks held by this instance in project-local locks directories
        if [[ -n "$project_root" && -d "$project_root" ]]; then
            # Check all possible lock directory locations
            for project_locks_dir in "$project_root/scripts/ralph/locks" "$project_root/.claude/ralph/locks" "$project_root/ralph/locks" "$project_root/tasks/locks" "$project_root/project/locks" "$project_root/locks"; do
                [[ -d "$project_locks_dir" ]] || continue
                for lock_dir in "$project_locks_dir"/*.lock/; do
                    [[ -d "$lock_dir" ]] || continue
                    local lock_owner=""
                    if [[ -f "$lock_dir/owner.txt" ]]; then
                        lock_owner=$(cat "$lock_dir/owner.txt" | tr -d '\n')
                    elif [[ -f "$lock_dir/owner" ]]; then
                        lock_owner=$(cat "$lock_dir/owner" | tr -d '\n')
                    fi
                    if [[ "$lock_owner" == "$instance_id" ]]; then
                        local story_id
                        story_id=$(basename "$lock_dir" .lock)
                        write_colored yellow "    Releasing lock: $story_id"
                        rm -rf "$lock_dir" 2>/dev/null || true
                    fi
                done
            done
        fi

        ((cleaned++)) || true
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        write_colored yellow "Would clean up $dead_count dead instances"
    else
        write_colored green "Cleaned up $cleaned dead instances"
    fi
}

# clear_terminated_instances()
# Removes terminated instances (cleanly finished) from global registry
#
clear_terminated_instances() {
    write_colored blue "Checking for terminated instances (global)..."

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local instances_dir="$global_dir/instances"

    if [[ ! -d "$instances_dir" ]]; then
        write_colored green "No global instances directory"
        return
    fi

    local cleaned=0

    for link in "$instances_dir"/*; do
        [[ -L "$link" || -d "$link" ]] || continue

        local instance_dir
        # Resolve symlink to actual directory
        if [[ -L "$link" ]]; then
            instance_dir=$(readlink -f "$link" 2>/dev/null) || continue
        else
            instance_dir="$link"
        fi

        [[ -d "$instance_dir" ]] || continue

        local status_file="$instance_dir/status.json"
        [[ -f "$status_file" ]] || continue

        local status_json
        if ! status_json=$(cat "$status_file" 2>/dev/null); then
            continue
        fi

        local state project_name instance_id
        state=$(echo "$status_json" | jq -r '.state // "unknown"')
        instance_id=$(echo "$status_json" | jq -r '.instanceId // ""')

        # Extract project name from link name
        local link_name
        link_name=$(basename "$link")
        project_name=$(echo "$link_name" | sed 's/-uge-.*$//')

        if [[ "$state" == "terminated" || "$state" == "completed" ]]; then
            write_colored yellow "  Terminated: $project_name ($state)"

            if [[ "$DRY_RUN" == "true" ]]; then
                echo "    [DRY RUN] Would remove instance directory and global link"
            else
                # Remove the actual instance directory
                rm -rf "$instance_dir" 2>/dev/null || true
                # Remove the global registry link
                rm -f "$link" 2>/dev/null || true
                ((cleaned++)) || true
            fi
        fi
    done

    if [[ "$cleaned" -eq 0 && "$DRY_RUN" != "true" ]]; then
        write_colored green "No terminated instances found"
    elif [[ "$DRY_RUN" == "true" ]]; then
        write_colored yellow "Would remove terminated instances"
    else
        write_colored green "Removed $cleaned terminated instances"
    fi
}

# clear_old_instances()
# Removes instances older than TTL from global registry
#
clear_old_instances() {
    write_colored blue "Checking for old instances (global)..."

    local ttl_days="${RALPH_CLEANUP_TTL:-7}"
    local now cutoff
    now=$(date +%s)
    cutoff=$((now - (ttl_days * 86400)))

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local instances_dir="$global_dir/instances"

    if [[ ! -d "$instances_dir" ]]; then
        write_colored green "No global instances directory"
        return
    fi

    local cleaned=0

    for link in "$instances_dir"/*; do
        [[ -L "$link" || -d "$link" ]] || continue

        local instance_dir
        # Resolve symlink to actual directory
        if [[ -L "$link" ]]; then
            instance_dir=$(readlink -f "$link" 2>/dev/null) || continue
        else
            instance_dir="$link"
        fi

        [[ -d "$instance_dir" ]] || continue

        local status_file="$instance_dir/status.json"
        [[ -f "$status_file" ]] || continue

        local status_json
        if ! status_json=$(cat "$status_file" 2>/dev/null); then
            continue
        fi

        local last_heartbeat_epoch project_name
        last_heartbeat_epoch=$(echo "$status_json" | jq -r '.lastHeartbeatEpoch // 0')

        # Extract project name from link name
        local link_name
        link_name=$(basename "$link")
        project_name=$(echo "$link_name" | sed 's/-uge-.*$//')

        if [[ "$last_heartbeat_epoch" -lt "$cutoff" ]]; then
            local age_days
            age_days=$(((now - last_heartbeat_epoch) / 86400))

            write_colored yellow "  Old: $project_name ($age_days days old)"

            if [[ "$DRY_RUN" == "true" ]]; then
                echo "    [DRY RUN] Would remove instance directory and global link"
            else
                # Remove the actual instance directory
                rm -rf "$instance_dir" 2>/dev/null || true
                # Remove the global registry link
                rm -f "$link" 2>/dev/null || true
                ((cleaned++)) || true
            fi
        fi
    done

    if [[ "$cleaned" -eq 0 && "$DRY_RUN" != "true" ]]; then
        write_colored green "No old instances found (TTL: $ttl_days days)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        write_colored yellow "Would remove old instances (TTL: $ttl_days days)"
    else
        write_colored green "Removed $cleaned old instances"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dead)
            CLEAN_DEAD=true
            shift
            ;;
        -t|--terminated)
            CLEAN_TERMINATED=true
            shift
            ;;
        -o|--old)
            CLEAN_OLD=true
            shift
            ;;
        -a|--all)
            CLEAN_DEAD=true
            CLEAN_TERMINATED=true
            CLEAN_OLD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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

# If no action specified, show summary and hint
if [[ "$CLEAN_DEAD" == "false" && "$CLEAN_TERMINATED" == "false" && "$CLEAN_OLD" == "false" ]]; then
    show_summary
    echo "Run with -d/--dead, -t/--terminated, -o/--old, or -a/--all to clean up instances"
    exit 0
fi

# Show dry-run warning
if [[ "$DRY_RUN" == "true" ]]; then
    write_colored yellow "DRY RUN MODE - No changes will be made"
    echo ""
fi

# Execute requested cleanups
if [[ "$CLEAN_DEAD" == "true" ]]; then
    clear_dead_instances
    echo ""
fi

if [[ "$CLEAN_TERMINATED" == "true" ]]; then
    clear_terminated_instances
    echo ""
fi

if [[ "$CLEAN_OLD" == "true" ]]; then
    clear_old_instances
    echo ""
fi

# Show final summary
show_summary
