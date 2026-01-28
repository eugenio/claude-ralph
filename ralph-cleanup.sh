#!/bin/bash
# ralph-cleanup.sh - Clean up old instances and stale data
# Usage: ./ralph-cleanup.sh [--dead|--old|--all|--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="$SCRIPT_DIR/instances"
LOCKS_DIR="$SCRIPT_DIR/locks"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
CLEANUP_DEAD=false
CLEANUP_OLD=false

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dead      Clean up dead instances (no heartbeat >5 min)"
    echo "  --old       Clean up old instances (>7 days, configurable via RALPH_CLEANUP_TTL)"
    echo "  --all       Clean up both dead and old instances"
    echo "  --dry-run   Show what would be cleaned without deleting"
    echo "  -h, --help  Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  RALPH_CLEANUP_TTL  Days to keep old instances (default: 7)"
}

cleanup_dead_instances() {
    echo -e "${BLUE}Checking for dead instances...${NC}"

    local now=$(date +%s)
    local count=0

    for dir in "$INSTANCES_DIR"/*; do
        [ -d "$dir" ] || continue

        local instance_id=$(basename "$dir")
        local status_file="$dir/status.json"

        if [ -f "$status_file" ]; then
            local heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
            local state=$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
            local age=$((now - heartbeat))

            # Dead if no heartbeat for 5 minutes and not already terminated
            if [ "$age" -gt 300 ] && [ "$state" != "terminated" ] && [ "$state" != "completed" ]; then
                echo -e "  ${YELLOW}Dead instance: $instance_id (no heartbeat for ${age}s)${NC}"

                if [ "$DRY_RUN" = "false" ]; then
                    # Update status to terminated
                    jq '.state = "terminated"' "$status_file" > "$status_file.tmp" && \
                        mv "$status_file.tmp" "$status_file"

                    # Release any locks held by this instance
                    for lock_dir in "$LOCKS_DIR"/*.lock; do
                        [ -d "$lock_dir" ] || continue
                        local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "")
                        if [ "$owner" = "$instance_id" ]; then
                            local story_id=$(basename "$lock_dir" .lock)
                            echo -e "    ${YELLOW}Releasing lock: $story_id${NC}"
                            rm -rf "$lock_dir"
                        fi
                    done
                fi

                count=$((count + 1))
            fi
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No dead instances found${NC}"
    else
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}Would clean up $count dead instances (dry run)${NC}"
        else
            echo -e "${GREEN}Cleaned up $count dead instances${NC}"
        fi
    fi
}

cleanup_old_instances() {
    echo -e "${BLUE}Checking for old instances...${NC}"

    local ttl_days="${RALPH_CLEANUP_TTL:-7}"

    # Try GNU date first, fall back to calculating manually
    local cutoff
    if date -d "$ttl_days days ago" +%s &>/dev/null; then
        cutoff=$(date -d "$ttl_days days ago" +%s)
    else
        # macOS/BSD fallback
        cutoff=$(date -v-${ttl_days}d +%s 2>/dev/null || echo "0")
    fi

    if [ "$cutoff" = "0" ]; then
        echo -e "${YELLOW}Warning: Could not calculate cutoff date. Skipping old instance cleanup.${NC}"
        return
    fi

    local count=0

    for dir in "$INSTANCES_DIR"/*; do
        [ -d "$dir" ] || continue

        local instance_id=$(basename "$dir")
        local status_file="$dir/status.json"

        if [ -f "$status_file" ]; then
            local heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
            local state=$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null || echo "unknown")

            # Remove if older than TTL and not actively running
            if [ "$heartbeat" -lt "$cutoff" ]; then
                local age_days=$(( ($(date +%s) - heartbeat) / 86400 ))
                echo -e "  ${YELLOW}Old instance: $instance_id (${age_days} days old, state: $state)${NC}"

                if [ "$DRY_RUN" = "false" ]; then
                    rm -rf "$dir"
                fi

                count=$((count + 1))
            fi
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No old instances found (TTL: $ttl_days days)${NC}"
    else
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}Would remove $count old instances (dry run)${NC}"
        else
            echo -e "${GREEN}Removed $count old instances${NC}"
        fi
    fi
}

show_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}              INSTANCE SUMMARY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

    if [ ! -d "$INSTANCES_DIR" ]; then
        echo "No instances directory"
        return
    fi

    local total=0
    local running=0
    local dead=0
    local completed=0
    local terminated=0

    local now=$(date +%s)

    for dir in "$INSTANCES_DIR"/*; do
        [ -d "$dir" ] || continue
        total=$((total + 1))

        local status_file="$dir/status.json"
        if [ -f "$status_file" ]; then
            local state=$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
            local heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
            local age=$((now - heartbeat))

            case "$state" in
                completed)
                    completed=$((completed + 1))
                    ;;
                terminated)
                    terminated=$((terminated + 1))
                    ;;
                *)
                    if [ "$age" -gt 300 ]; then
                        dead=$((dead + 1))
                    else
                        running=$((running + 1))
                    fi
                    ;;
            esac
        fi
    done

    echo "Total instances: $total"
    echo -e "  ${GREEN}Running:    $running${NC}"
    echo -e "  ${BLUE}Completed:  $completed${NC}"
    echo -e "  ${YELLOW}Terminated: $terminated${NC}"
    echo -e "  ${RED}Dead:       $dead${NC}"

    # Show locks
    echo ""
    local lock_count=0
    if [ -d "$LOCKS_DIR" ]; then
        lock_count=$(ls -d "$LOCKS_DIR"/*.lock 2>/dev/null | wc -l || echo "0")
    fi
    echo "Active locks: $lock_count"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dead)
            CLEANUP_DEAD=true
            shift
            ;;
        --old)
            CLEANUP_OLD=true
            shift
            ;;
        --all)
            CLEANUP_DEAD=true
            CLEANUP_OLD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Default to showing summary if no cleanup requested
if [ "$CLEANUP_DEAD" = "false" ] && [ "$CLEANUP_OLD" = "false" ]; then
    show_summary
    echo ""
    echo "Run with --dead, --old, or --all to clean up instances"
    exit 0
fi

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

if [ "$CLEANUP_DEAD" = "true" ]; then
    cleanup_dead_instances
    echo ""
fi

if [ "$CLEANUP_OLD" = "true" ]; then
    cleanup_old_instances
    echo ""
fi

show_summary
