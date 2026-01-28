#!/bin/bash
# ralph-locks.sh - Manage story locks for multi-instance Ralph
# Usage: ./ralph-locks.sh [status|release <story-id>|release-all|cleanup]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCKS_DIR="$SCRIPT_DIR/locks"
INSTANCES_DIR="$SCRIPT_DIR/instances"

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
    echo "  status              Show all current locks"
    echo "  release <story-id>  Force release a specific lock"
    echo "  release-all         Force release all locks"
    echo "  cleanup             Remove stale locks (>2 hours old or dead owner)"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 release US-001"
    echo "  $0 cleanup"
}

get_instance_status() {
    local instance_id="$1"
    local status_file="$INSTANCES_DIR/$instance_id/status.json"

    if [ -f "$status_file" ]; then
        local state=$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null)
        local heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null)
        local now=$(date +%s)
        local age=$((now - heartbeat))

        if [ "$age" -gt 300 ]; then
            echo "dead (no heartbeat for ${age}s)"
        else
            echo "$state"
        fi
    else
        echo "unknown"
    fi
}

cmd_status() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}              RALPH LOCK STATUS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    if [ ! -d "$LOCKS_DIR" ] || [ -z "$(ls -A "$LOCKS_DIR" 2>/dev/null)" ]; then
        echo -e "${GREEN}No active locks${NC}"
        return 0
    fi

    printf "%-12s %-40s %-10s %-15s\n" "STORY" "OWNER" "AGE" "STATUS"
    printf "%-12s %-40s %-10s %-15s\n" "-----" "-----" "---" "------"

    for lock_dir in "$LOCKS_DIR"/*.lock; do
        [ -d "$lock_dir" ] || continue

        local story_id=$(basename "$lock_dir" .lock)
        local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "unknown")
        local timestamp=$(cat "$lock_dir/timestamp" 2>/dev/null || echo "0")
        local now=$(date +%s)
        local age=$((now - timestamp))

        # Format age
        local age_str
        if [ "$age" -lt 60 ]; then
            age_str="${age}s"
        elif [ "$age" -lt 3600 ]; then
            age_str="$((age / 60))m"
        else
            age_str="$((age / 3600))h"
        fi

        # Get owner status
        local owner_status=$(get_instance_status "$owner")

        # Color based on status
        local color="$GREEN"
        if [ "$owner_status" = "dead" ] || [[ "$owner_status" == dead* ]]; then
            color="$RED"
        elif [ "$age" -gt 7200 ]; then
            color="$YELLOW"
        fi

        printf "${color}%-12s %-40s %-10s %-15s${NC}\n" \
            "$story_id" "${owner:0:40}" "$age_str" "$owner_status"
    done

    echo ""
}

cmd_release() {
    local story_id="$1"

    if [ -z "$story_id" ]; then
        echo -e "${RED}Error: Story ID required${NC}"
        echo "Usage: $0 release <story-id>"
        exit 1
    fi

    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    if [ ! -d "$lock_dir" ]; then
        echo -e "${YELLOW}No lock found for $story_id${NC}"
        return 0
    fi

    local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}Releasing lock for $story_id (owner: $owner)${NC}"

    rm -rf "$lock_dir"
    echo -e "${GREEN}Lock released${NC}"
}

cmd_release_all() {
    echo -e "${YELLOW}Releasing all locks...${NC}"

    if [ ! -d "$LOCKS_DIR" ]; then
        echo -e "${GREEN}No locks directory${NC}"
        return 0
    fi

    local count=0
    for lock_dir in "$LOCKS_DIR"/*.lock; do
        [ -d "$lock_dir" ] || continue
        local story_id=$(basename "$lock_dir" .lock)
        rm -rf "$lock_dir"
        echo "  Released: $story_id"
        count=$((count + 1))
    done

    echo -e "${GREEN}Released $count locks${NC}"
}

cmd_cleanup() {
    echo -e "${BLUE}Cleaning up stale locks...${NC}"

    if [ ! -d "$LOCKS_DIR" ]; then
        echo -e "${GREEN}No locks directory${NC}"
        return 0
    fi

    local stale_seconds="${RALPH_LOCK_TIMEOUT:-7200}"
    local now=$(date +%s)
    local count=0

    for lock_dir in "$LOCKS_DIR"/*.lock; do
        [ -d "$lock_dir" ] || continue

        local story_id=$(basename "$lock_dir" .lock)
        local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "")
        local timestamp=$(cat "$lock_dir/timestamp" 2>/dev/null || echo "0")
        local age=$((now - timestamp))
        local should_remove=false
        local reason=""

        # Check age
        if [ "$age" -gt "$stale_seconds" ]; then
            should_remove=true
            reason="stale (age: ${age}s)"
        fi

        # Check owner heartbeat
        if [ -n "$owner" ] && [ "$should_remove" = "false" ]; then
            local status_file="$INSTANCES_DIR/$owner/status.json"
            if [ -f "$status_file" ]; then
                local heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
                local heartbeat_age=$((now - heartbeat))
                if [ "$heartbeat_age" -gt 300 ]; then
                    should_remove=true
                    reason="dead owner (no heartbeat for ${heartbeat_age}s)"
                fi
            fi
        fi

        if [ "$should_remove" = "true" ]; then
            echo -e "  ${YELLOW}Removing: $story_id - $reason${NC}"
            rm -rf "$lock_dir"
            count=$((count + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No stale locks found${NC}"
    else
        echo -e "${GREEN}Cleaned up $count stale locks${NC}"
    fi
}

# Main
case "${1:-status}" in
    status)
        cmd_status
        ;;
    release)
        cmd_release "$2"
        ;;
    release-all)
        cmd_release_all
        ;;
    cleanup)
        cmd_cleanup
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
