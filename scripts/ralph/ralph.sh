#!/bin/bash
# claude-ralph - Autonomous AI agent loop for Claude Code
# Multi-instance version with isolation, locking, and feature branches
# Usage: ./ralph.sh [max_iterations]

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT can be overridden via environment, defaults to SCRIPT_DIR for self-contained repos
PROJECT_ROOT="${RALPH_PROJECT_ROOT:-$SCRIPT_DIR}"

# Shared files (with locking)
PRD_FILE="$SCRIPT_DIR/prd.json"
PRD_LOCK="$SCRIPT_DIR/.prd.lock"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Multi-instance directories
INSTANCES_DIR="$SCRIPT_DIR/instances"
LOCKS_DIR="$SCRIPT_DIR/locks"

# Global registry directory (GM-001)
# Override with RALPH_GLOBAL_DIR environment variable
GLOBAL_DIR="${RALPH_GLOBAL_DIR:-$HOME/.ralph/global}"
GLOBAL_INSTANCES_DIR="$GLOBAL_DIR/instances"
GLOBAL_LOCKS_DIR="$GLOBAL_DIR/locks"

# Generate unique instance ID: user-hostname-pid-timestamp
INSTANCE_ID="${USER:-unknown}-$(hostname -s 2>/dev/null || echo 'local')-$$-$(date +%s)"
INSTANCE_SHORT_ID="${INSTANCE_ID:0:8}"

# Instance-specific files
INSTANCE_DIR="$INSTANCES_DIR/$INSTANCE_ID"
LOG_FILE="$INSTANCE_DIR/ralph.log"
PROGRESS_FILE="$INSTANCE_DIR/progress.txt"
STATUS_FILE="$INSTANCE_DIR/status.json"

# Current story being worked on
CURRENT_STORY_ID=""
CURRENT_STORY_BRANCH=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING
# =============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$INSTANCE_SHORT_ID] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_debug() {
    if [ "${RALPH_DEBUG:-0}" = "1" ]; then
        log "DEBUG: $1"
    fi
}

# =============================================================================
# GLOBAL REGISTRY (GM-001)
# =============================================================================

init_global_registry() {
    # Skip if disabled
    if [ "${RALPH_GLOBAL_DISABLE:-}" = "1" ]; then
        log_debug "Global registry disabled"
        return 0
    fi

    # Create global registry directories
    if [ ! -d "$GLOBAL_INSTANCES_DIR" ]; then
        if mkdir -p "$GLOBAL_INSTANCES_DIR" 2>/dev/null; then
            chmod 700 "$GLOBAL_DIR" 2>/dev/null || true
            chmod 700 "$GLOBAL_INSTANCES_DIR" 2>/dev/null || true
            log "Created global instances directory: $GLOBAL_INSTANCES_DIR"
        else
            log "Warning: Failed to create global instances directory"
        fi
    fi

    if [ ! -d "$GLOBAL_LOCKS_DIR" ]; then
        if mkdir -p "$GLOBAL_LOCKS_DIR" 2>/dev/null; then
            chmod 700 "$GLOBAL_LOCKS_DIR" 2>/dev/null || true
            log "Created global locks directory: $GLOBAL_LOCKS_DIR"
        else
            log "Warning: Failed to create global locks directory"
        fi
    fi

    return 0
}

# =============================================================================
# INSTANCE MANAGEMENT (US-001, US-002)
# =============================================================================

init_instance() {
    # Create instance directory structure
    mkdir -p "$INSTANCE_DIR"
    mkdir -p "$INSTANCES_DIR"
    mkdir -p "$LOCKS_DIR"

    # Initialize global registry (GM-001)
    init_global_registry

    # Initialize log file
    echo "# Ralph Instance Log" > "$LOG_FILE"
    echo "# Instance ID: $INSTANCE_ID" >> "$LOG_FILE"
    echo "# Short ID: $INSTANCE_SHORT_ID" >> "$LOG_FILE"
    echo "# Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "# Project: $PROJECT_ROOT" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"

    # Initialize progress file
    cat > "$PROGRESS_FILE" << EOF
# Ralph Progress Log
Instance: $INSTANCE_ID
Started: $(date '+%Y-%m-%d %H:%M:%S')

## Codebase Patterns
(Patterns discovered during implementation will be added here)

---
EOF

    # Initialize status file
    update_status "starting" ""

    # Register in global registry (GM-004)
    register_ralph_global_instance

    log "Instance initialized: $INSTANCE_ID"
    log "Instance directory: $INSTANCE_DIR"
}

update_status() {
    local state="$1"
    local story="$2"
    local tmp_file="$STATUS_FILE.tmp"

    cat > "$tmp_file" << EOF
{
  "instanceId": "$INSTANCE_ID",
  "shortId": "$INSTANCE_SHORT_ID",
  "state": "$state",
  "currentStory": "$story",
  "iteration": ${CURRENT_ITERATION:-0},
  "maxIterations": $MAX_ITERATIONS,
  "startTime": "$(date -d "@${INSTANCE_ID##*-}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')",
  "lastHeartbeat": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lastHeartbeatEpoch": $(date +%s),
  "projectRoot": "$PROJECT_ROOT",
  "branch": "$CURRENT_STORY_BRANCH",
  "pid": $$
}
EOF
    mv "$tmp_file" "$STATUS_FILE"
}

cleanup_old_instances() {
    local ttl_days="${RALPH_CLEANUP_TTL:-7}"
    local cutoff=$(date -d "$ttl_days days ago" +%s 2>/dev/null || echo "0")

    if [ "$cutoff" = "0" ]; then
        return  # date -d not supported (macOS)
    fi

    for dir in "$INSTANCES_DIR"/*; do
        [ -d "$dir" ] || continue
        local status_file="$dir/status.json"
        if [ -f "$status_file" ]; then
            local last_heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
            if [ "$last_heartbeat" -lt "$cutoff" ]; then
                log "Cleaning up old instance: $(basename "$dir")"
                rm -rf "$dir"
            fi
        fi
    done
}

# =============================================================================
# PRD ATOMIC OPERATIONS (US-005)
# =============================================================================

# Read PRD with shared lock
read_prd() {
    flock -s 200
    cat "$PRD_FILE"
    flock -u 200
} 200>"$PRD_LOCK"

# Update PRD with exclusive lock
update_prd() {
    local jq_filter="$1"
    local description="$2"
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        if flock -w 5 200; then
            # Backup before modification
            cp "$PRD_FILE" "$PRD_FILE.bak"

            # Apply update
            local tmp_file="$PRD_FILE.tmp"
            if jq "$jq_filter" "$PRD_FILE" > "$tmp_file" 2>/dev/null; then
                # Validate JSON
                if jq empty "$tmp_file" 2>/dev/null; then
                    mv "$tmp_file" "$PRD_FILE"
                    log_debug "PRD updated: $description"
                    flock -u 200
                    return 0
                else
                    log "ERROR: PRD update produced invalid JSON"
                    rm -f "$tmp_file"
                fi
            else
                log "ERROR: jq filter failed: $jq_filter"
                rm -f "$tmp_file"
            fi
            flock -u 200
            return 1
        else
            retry=$((retry + 1))
            log "PRD lock timeout, retry $retry/$max_retries"
            sleep 1
        fi
    done 200>"$PRD_LOCK"

    log "ERROR: Failed to acquire PRD lock after $max_retries retries"
    return 1
}

# =============================================================================
# STORY LOCKING (US-003)
# =============================================================================

# Acquire lock for a story (atomic mkdir)
acquire_story_lock() {
    local story_id="$1"
    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    # Clean stale locks first
    cleanup_stale_lock "$story_id"

    # Attempt atomic lock acquisition
    if mkdir "$lock_dir" 2>/dev/null; then
        echo "$INSTANCE_ID" > "$lock_dir/owner"
        echo "$(date +%s)" > "$lock_dir/timestamp"
        echo "$$" > "$lock_dir/pid"
        log "Acquired lock for $story_id"
        return 0
    fi

    log_debug "Lock for $story_id held by another instance"
    return 1
}

# Release lock for a story
release_story_lock() {
    local story_id="$1"
    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    if [ -d "$lock_dir" ]; then
        local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "")
        if [ "$owner" = "$INSTANCE_ID" ]; then
            rm -rf "$lock_dir"
            log "Released lock for $story_id"
            return 0
        else
            log "WARNING: Cannot release lock for $story_id - owned by $owner"
            return 1
        fi
    fi
    return 0
}

# Check if lock is stale (older than 2 hours or owner dead)
cleanup_stale_lock() {
    local story_id="$1"
    local lock_dir="$LOCKS_DIR/${story_id}.lock"
    local stale_seconds="${RALPH_LOCK_TIMEOUT:-7200}"  # 2 hours default

    if [ ! -d "$lock_dir" ]; then
        return 0
    fi

    local timestamp=$(cat "$lock_dir/timestamp" 2>/dev/null || echo "0")
    local now=$(date +%s)
    local age=$((now - timestamp))

    # Check if lock is stale by time
    if [ "$age" -gt "$stale_seconds" ]; then
        local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "unknown")
        log "Releasing stale lock for $story_id (age: ${age}s, owner: $owner)"
        rm -rf "$lock_dir"
        return 0
    fi

    # Check if owner instance is dead (no heartbeat in 5 minutes)
    local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "")
    if [ -n "$owner" ]; then
        local owner_status="$INSTANCES_DIR/$owner/status.json"
        if [ -f "$owner_status" ]; then
            local last_heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$owner_status" 2>/dev/null || echo "0")
            local heartbeat_age=$((now - last_heartbeat))
            if [ "$heartbeat_age" -gt 300 ]; then  # 5 minutes
                log "Releasing lock for $story_id - owner instance dead (no heartbeat for ${heartbeat_age}s)"
                rm -rf "$lock_dir"

                # Clear claimedBy in PRD
                update_prd \
                    "(.userStories[] | select(.id == \"$story_id\")).claimedBy = null" \
                    "Cleared claimedBy for dead instance"
                return 0
            fi
        fi
    fi

    return 1  # Lock is valid
}

# Release all locks held by this instance
release_all_locks() {
    for lock_dir in "$LOCKS_DIR"/*.lock; do
        [ -d "$lock_dir" ] || continue
        local owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "")
        if [ "$owner" = "$INSTANCE_ID" ]; then
            local story_id=$(basename "$lock_dir" .lock)
            release_story_lock "$story_id"
        fi
    done
}

# =============================================================================
# STORY CLAIMING (US-004)
# =============================================================================

# Find and claim next available story
claim_next_story() {
    local max_retries=5
    local retry=0

    while [ $retry -lt $max_retries ]; do
        # Get list of incomplete, unclaimed stories ordered by priority
        local stories=$(read_prd | jq -r '
            .userStories
            | sort_by(.priority)
            | .[]
            | select(.passes == false)
            | select(.claimedBy == null or .claimedBy == "")
            | .id
        ' 2>/dev/null)

        for story_id in $stories; do
            # Try to acquire lock
            if acquire_story_lock "$story_id"; then
                # Update PRD with claim
                if update_prd \
                    "(.userStories[] | select(.id == \"$story_id\")).claimedBy = \"$INSTANCE_ID\"" \
                    "Claimed $story_id"; then
                    CURRENT_STORY_ID="$story_id"
                    log "Claimed story: $story_id"
                    return 0
                else
                    # Failed to update PRD, release lock
                    release_story_lock "$story_id"
                fi
            fi
        done

        # No stories available, wait and retry
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            log "No available stories, waiting 30s (retry $retry/$max_retries)"
            sleep 30
        fi
    done

    log "No stories available after $max_retries retries"
    return 1
}

# Release current story claim
release_story_claim() {
    if [ -n "$CURRENT_STORY_ID" ]; then
        release_story_lock "$CURRENT_STORY_ID"
        update_prd \
            "(.userStories[] | select(.id == \"$CURRENT_STORY_ID\")).claimedBy = null" \
            "Released claim on $CURRENT_STORY_ID"
        CURRENT_STORY_ID=""
    fi
}

# =============================================================================
# GIT BRANCH ISOLATION (US-006)
# =============================================================================

# Create feature branch for story
create_story_branch() {
    local story_id="$1"
    local base_branch=$(read_prd | jq -r '.branchName // "main"')
    CURRENT_STORY_BRANCH="ralph/$INSTANCE_SHORT_ID/$story_id"

    cd "$PROJECT_ROOT"

    # Fetch latest
    git fetch origin 2>/dev/null || true

    # Check if base branch exists
    if git show-ref --verify --quiet "refs/heads/$base_branch" 2>/dev/null; then
        git checkout "$base_branch" 2>/dev/null || true
        git pull origin "$base_branch" 2>/dev/null || true
    elif git show-ref --verify --quiet "refs/remotes/origin/$base_branch" 2>/dev/null; then
        git checkout -b "$base_branch" "origin/$base_branch" 2>/dev/null || true
    fi

    # Create or checkout story branch
    if git show-ref --verify --quiet "refs/heads/$CURRENT_STORY_BRANCH" 2>/dev/null; then
        git checkout "$CURRENT_STORY_BRANCH"
        log "Checked out existing branch: $CURRENT_STORY_BRANCH"
    else
        git checkout -b "$CURRENT_STORY_BRANCH"
        log "Created new branch: $CURRENT_STORY_BRANCH"
    fi

    cd "$SCRIPT_DIR"
}

# Merge story branch back to main ralph branch
merge_story_branch() {
    local story_id="$1"
    local base_branch=$(read_prd | jq -r '.branchName // "main"')

    if [ -z "$CURRENT_STORY_BRANCH" ]; then
        return 0
    fi

    cd "$PROJECT_ROOT"

    # Checkout base branch
    git checkout "$base_branch" 2>/dev/null || {
        log "WARNING: Could not checkout $base_branch for merge"
        cd "$SCRIPT_DIR"
        return 1
    }

    # Pull latest
    git pull origin "$base_branch" 2>/dev/null || true

    # Merge with --no-ff to preserve history
    if git merge --no-ff "$CURRENT_STORY_BRANCH" -m "Merge $story_id from instance $INSTANCE_SHORT_ID"; then
        log "Merged $CURRENT_STORY_BRANCH into $base_branch"

        # Delete the feature branch
        git branch -d "$CURRENT_STORY_BRANCH" 2>/dev/null || true
        log "Deleted branch: $CURRENT_STORY_BRANCH"
    else
        log "ERROR: Merge conflict! Manual resolution required."
        git merge --abort 2>/dev/null || true
        cd "$SCRIPT_DIR"
        return 1
    fi

    cd "$SCRIPT_DIR"
    CURRENT_STORY_BRANCH=""
    return 0
}

# =============================================================================
# GLOBAL INSTANCE FUNCTIONS (GM-004)
# =============================================================================

get_ralph_global_dir() {
    echo "${RALPH_GLOBAL_DIR:-$HOME/.ralph/global}"
}

get_ralph_global_link_name() {
    local project_name
    project_name=$(basename "$PROJECT_ROOT")
    echo "${project_name}-${INSTANCE_ID}"
}

register_ralph_global_instance() {
    # Skip if disabled
    [[ "${RALPH_GLOBAL_DISABLE:-0}" == "1" ]] && return 0

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local instances_dir="$global_dir/instances"
    local link_name
    link_name=$(get_ralph_global_link_name)
    local link_path="$instances_dir/$link_name"

    # Ensure global instances directory exists
    if [[ ! -d "$instances_dir" ]]; then
        mkdir -p "$instances_dir" 2>/dev/null || return 1
        chmod 700 "$global_dir" 2>/dev/null || true
        chmod 700 "$instances_dir" 2>/dev/null || true
    fi

    # Remove existing link if present (in case of stale symlink)
    if [[ -L "$link_path" || -e "$link_path" ]]; then
        rm -f "$link_path" 2>/dev/null || true
    fi

    # Create symlink pointing to instance directory
    if ln -s "$INSTANCE_DIR" "$link_path" 2>/dev/null; then
        log "Registered in global registry: $link_name"
        return 0
    else
        log "Warning: Failed to register in global registry"
        return 1
    fi
}

unregister_ralph_global_instance() {
    [[ "${RALPH_GLOBAL_DISABLE:-0}" == "1" ]] && return 0
    local link_path="$(get_ralph_global_dir)/instances/$(get_ralph_global_link_name)"
    if [[ -L "$link_path" || -e "$link_path" ]]; then
        # Use rm -rf for Windows compatibility (ln -s may create directories)
        rm -rf "$link_path" 2>/dev/null && log "Unregistered from global registry" || true
    fi
}

# =============================================================================
# SIGNAL HANDLING (US-011)
# =============================================================================

cleanup_on_exit() {
    log "Shutting down instance..."
    update_status "terminated" "$CURRENT_STORY_ID"

    # Release all locks
    release_all_locks

    # Unregister from global registry (GM-004)
    unregister_ralph_global_instance

    # Stash any uncommitted changes
    cd "$PROJECT_ROOT"
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        log "No uncommitted changes"
    else
        git stash push -m "Ralph instance $INSTANCE_SHORT_ID shutdown stash" 2>/dev/null || true
        log "Stashed uncommitted changes"
    fi
    cd "$SCRIPT_DIR"

    log "Cleanup complete. Goodbye!"
}

trap cleanup_on_exit EXIT
trap 'log "Received SIGINT"; exit 130' INT
trap 'log "Received SIGTERM"; exit 143' TERM
trap 'log "Received SIGHUP"; exit 129' HUP

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

check_dependencies() {
    if ! command -v claude &> /dev/null; then
        echo -e "${RED}Error: Claude Code CLI not found${NC}"
        echo "Install with: npm install -g @anthropic-ai/claude-code"
        echo "Then authenticate with: claude"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq not found${NC}"
        echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi

    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error: git not found${NC}"
        exit 1
    fi

    if ! command -v flock &> /dev/null; then
        echo -e "${RED}Error: flock not found${NC}"
        echo "Install with: apt install util-linux (Linux) or brew install flock (macOS)"
        exit 1
    fi
}

# =============================================================================
# STATUS HELPERS
# =============================================================================

all_stories_complete() {
    if [ ! -f "$PRD_FILE" ]; then
        return 1
    fi

    local incomplete=$(read_prd | jq '[.userStories[] | select(.passes == false)] | length' 2>/dev/null || echo "1")
    [ "$incomplete" -eq 0 ]
}

get_status() {
    if [ ! -f "$PRD_FILE" ]; then
        echo "No PRD file found"
        return
    fi

    local total=$(read_prd | jq '.userStories | length' 2>/dev/null || echo "0")
    local complete=$(read_prd | jq '[.userStories[] | select(.passes == true)] | length' 2>/dev/null || echo "0")
    local remaining=$((total - complete))

    echo -e "${CYAN}Stories: ${GREEN}$complete${NC}/${total} complete, ${YELLOW}$remaining${NC} remaining"
}

get_story_title() {
    local story_id="$1"
    read_prd | jq -r ".userStories[] | select(.id == \"$story_id\") | .title" 2>/dev/null || echo "$story_id"
}

# =============================================================================
# ARCHIVE
# =============================================================================

archive_previous_run() {
    if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
        local current_branch=$(read_prd | jq -r '.branchName // empty' 2>/dev/null || echo "")
        local last_branch=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

        if [ -n "$current_branch" ] && [ -n "$last_branch" ] && [ "$current_branch" != "$last_branch" ]; then
            local date_str=$(date +%Y-%m-%d)
            local folder_name=$(echo "$last_branch" | sed 's|^ralph/||')
            local archive_folder="$ARCHIVE_DIR/$date_str-$folder_name"

            mkdir -p "$archive_folder"

            [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$archive_folder/"
            [ -d "$INSTANCES_DIR" ] && cp -r "$INSTANCES_DIR" "$archive_folder/" 2>/dev/null || true

            log "${YELLOW}Archived previous run to $archive_folder${NC}"
        fi
    fi
}

save_current_branch() {
    if [ -f "$PRD_FILE" ]; then
        local branch=$(read_prd | jq -r '.branchName // empty' 2>/dev/null || echo "")
        if [ -n "$branch" ]; then
            echo "$branch" > "$LAST_BRANCH_FILE"
        fi
    fi
}

# =============================================================================
# MAIN LOOP
# =============================================================================

main() {
    check_dependencies

    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║           claude-ralph (multi-instance)               ║"
    echo "║  Autonomous AI Agent Loop (Claude Subscription)       ║"
    echo "╠═══════════════════════════════════════════════════════╣"
    echo -e "║  Instance: ${MAGENTA}$INSTANCE_SHORT_ID${BLUE}                                 ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ ! -f "$PRD_FILE" ]; then
        echo -e "${RED}Error: prd.json not found in $SCRIPT_DIR${NC}"
        echo "Create a prd.json file with your user stories first."
        echo "See prd.json.example for the expected format."
        exit 1
    fi

    # Initialize instance
    init_instance
    cleanup_old_instances

    archive_previous_run
    save_current_branch

    log "Starting Ralph with max $MAX_ITERATIONS iterations"
    get_status
    echo ""

    CURRENT_ITERATION=0
    for ((i=1; i<=MAX_ITERATIONS; i++)); do
        CURRENT_ITERATION=$i
        update_status "idle" ""

        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  [$INSTANCE_SHORT_ID] ITERATION $i / $MAX_ITERATIONS${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

        get_status

        # Check if already complete BEFORE starting work
        if all_stories_complete; then
            echo -e "${GREEN}✅ All stories complete! Exiting successfully.${NC}"
            log "All stories complete at iteration $i"
            update_status "completed" ""
            exit 0
        fi

        # Claim a story to work on
        update_status "claiming" ""
        if ! claim_next_story; then
            log "No stories to claim. Checking if all complete..."
            if all_stories_complete; then
                echo -e "${GREEN}✅ All stories complete! Exiting successfully.${NC}"
                update_status "completed" ""
                exit 0
            else
                log "Stories remain but none available. Another instance may be working. Exiting."
                update_status "idle" ""
                exit 0
            fi
        fi

        local story_title=$(get_story_title "$CURRENT_STORY_ID")
        log "Working on: $CURRENT_STORY_ID - $story_title"
        update_status "working" "$CURRENT_STORY_ID"

        # Create feature branch
        create_story_branch "$CURRENT_STORY_ID"

        log "Starting iteration $i for $CURRENT_STORY_ID"

        # Run Claude Code with the prompt
        echo -e "${YELLOW}Running Claude Code for $CURRENT_STORY_ID...${NC}"

        cd "$PROJECT_ROOT"
        # Use tee to log file; only copy to stderr if it's available (not in background mode)
        local tee_target="$INSTANCE_DIR/claude-output.log"
        local claude_exit_code=0
        if [[ -t 2 ]]; then
            # stderr is a TTY, tee to both file and stderr
            OUTPUT=$(cat "$PROMPT_FILE" | claude -p \
                --dangerously-skip-permissions \
                --verbose \
                2>&1 | tee "$tee_target" | tee /dev/stderr) || claude_exit_code=$?
        else
            # No TTY (background mode), just log to file
            OUTPUT=$(cat "$PROMPT_FILE" | claude -p \
                --dangerously-skip-permissions \
                --verbose \
                2>&1 | tee "$tee_target") || claude_exit_code=$?
        fi
        if [ $claude_exit_code -ne 0 ]; then
            log "⚠️  Claude Code exited with code $claude_exit_code"
            cd "$SCRIPT_DIR"
            echo -e "${RED}Claude Code failed with exit code $claude_exit_code${NC}"
            echo -e "${YELLOW}Releasing story and continuing...${NC}"
            release_story_claim
        fi
        cd "$SCRIPT_DIR"

        # Update heartbeat
        update_status "working" "$CURRENT_STORY_ID"

        echo ""
        echo -e "${BLUE}Iteration $i completed. Checking status...${NC}"

        # Check if story was completed
        local story_passes=$(read_prd | jq -r ".userStories[] | select(.id == \"$CURRENT_STORY_ID\") | .passes" 2>/dev/null)
        if [ "$story_passes" = "true" ]; then
            log "Story $CURRENT_STORY_ID completed!"

            # Merge back to main branch
            update_status "merging" "$CURRENT_STORY_ID"
            merge_story_branch "$CURRENT_STORY_ID"

            # Release claim
            release_story_claim
        fi

        # Check for completion signal
        local complete_count=$(echo "$OUTPUT" | grep -o "<promise>COMPLETE</promise>" | wc -l || echo "0")

        if [ "$complete_count" -gt 0 ] && all_stories_complete; then
            echo -e "${GREEN}"
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║              ✅ RALPH COMPLETE!                       ║"
            echo "║         All user stories have been implemented        ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo -e "${NC}"
            log "✅ Done! All stories complete at iteration $i"
            update_status "completed" ""
            exit 0
        fi

        if all_stories_complete; then
            echo -e "${GREEN}"
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║              ✅ RALPH COMPLETE!                       ║"
            echo "║         All user stories have been implemented        ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo -e "${NC}"
            log "✅ Done! All stories verified complete at iteration $i"
            update_status "completed" ""
            exit 0
        fi

        # Show what's remaining
        local remaining_new=$(read_prd | jq '[.userStories[] | select(.passes == false)] | length' 2>/dev/null || echo "?")
        if [ "$remaining_new" != "?" ] && [ "$remaining_new" -gt 0 ]; then
            echo -e "${YELLOW}${remaining_new} stories still remaining. Continuing...${NC}"
        fi

        # Brief pause between iterations
        if [ $i -lt $MAX_ITERATIONS ]; then
            echo -e "${YELLOW}Waiting 2 seconds before next iteration...${NC}"
            sleep 2
        fi
    done

    echo -e "${YELLOW}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║     ⚠️  Max iterations ($MAX_ITERATIONS) reached                     ║"
    echo "║     Some stories may still be incomplete              ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    get_status
    log "Max iterations reached. Check prd.json for remaining stories."
    update_status "max_iterations" "$CURRENT_STORY_ID"

    # Release any held story
    release_story_claim
}

main "$@"
