#!/usr/bin/env bash
# =============================================================================
# ralph-utils.sh - Shared utility functions for claude-ralph bash scripts
# =============================================================================
#
# DESCRIPTION:
#   Common utility functions for all ralph bash scripts including:
#   - Path resolution for ralph directories
#   - PRD file reading/writing and status tracking
#   - Colored terminal output
#   - Multi-instance support with locking
#   - Logging utilities
#
# USAGE:
#   Source this file in other ralph scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/ralph-utils.sh"
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - jq (for JSON parsing)
#   - git (for version control operations)
#
# =============================================================================

# Prevent multiple sourcing
if [[ -n "${_RALPH_UTILS_LOADED:-}" ]]; then
    return 0
fi
readonly _RALPH_UTILS_LOADED=1

# Strict mode for better error handling
set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Script directory (where ralph-utils.sh is located)
RALPH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RALPH_SCRIPT_DIR

# Instance-level variables (set once per session)
_RALPH_INSTANCE_ID=""
_RALPH_INSTANCE_SHORT_ID=""

# =============================================================================
# GLOBAL REGISTRY FUNCTIONS (GM-001)
# =============================================================================

get_ralph_global_dir() {
    if [[ -n "${RALPH_GLOBAL_DIR:-}" ]]; then
        echo "$RALPH_GLOBAL_DIR"
        return 0
    fi
    echo "${HOME}/.ralph/global"
}

init_ralph_global_registry() {
    if [[ "${RALPH_GLOBAL_DISABLE:-}" == "1" ]]; then
        return 0
    fi
    local global_dir
    global_dir=$(get_ralph_global_dir)
    local instances_dir="$global_dir/instances"
    local locks_dir="$global_dir/locks"
    if [[ ! -d "$instances_dir" ]]; then
        mkdir -p "$instances_dir" 2>/dev/null || return 1
        chmod 700 "$global_dir" 2>/dev/null || true
        chmod 700 "$instances_dir" 2>/dev/null || true
    fi
    if [[ ! -d "$locks_dir" ]]; then
        mkdir -p "$locks_dir" 2>/dev/null || return 1
        chmod 700 "$locks_dir" 2>/dev/null || true
    fi
    return 0
}

# get_ralph_global_link_name()
# Returns the link name for global registry registration
# Format: {project-name}-{instance-id}
# Output: Link name string
#
get_ralph_global_link_name() {
    local project_root
    project_root=$(get_project_root)
    local project_name
    project_name=$(basename "$project_root")
    local instance_id
    instance_id=$(get_ralph_instance_id)
    echo "${project_name}-${instance_id}"
}

# register_ralph_global_instance()
# Creates a symlink in the global registry pointing to the local instance directory
# This allows the global dashboard to discover instances across projects
# Returns: 0 on success, 1 on failure or if disabled
#
register_ralph_global_instance() {
    # Skip if disabled
    if [[ "${RALPH_GLOBAL_DISABLE:-}" == "1" ]]; then
        return 0
    fi

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local instances_dir="$global_dir/instances"
    local link_name
    link_name=$(get_ralph_global_link_name)
    local link_path="$instances_dir/$link_name"

    # Ensure global registry is initialized
    init_ralph_global_registry || return 1

    # Get the local instance directory
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"
    local instance_dir="$INSTANCES_DIR/$instance_id"

    # Create instance directory if it doesn't exist
    if [[ ! -d "$instance_dir" ]]; then
        mkdir -p "$instance_dir" 2>/dev/null || return 1
    fi

    # Remove existing link if present (in case of stale symlink)
    if [[ -L "$link_path" || -e "$link_path" ]]; then
        rm -f "$link_path" 2>/dev/null || true
    fi

    # Create symlink
    if ln -s "$instance_dir" "$link_path" 2>/dev/null; then
        add_ralph_instance_log "Registered in global registry: $link_name"
        return 0
    else
        # Log but don't fail - global registry is optional
        add_ralph_instance_log "Warning: Failed to register in global registry"
        return 1
    fi
}

# unregister_ralph_global_instance()
# Removes the symlink from the global registry
# Note: On Windows/MSYS where symlinks may become directories, we use rm -rf
# Returns: 0 on success or if already unregistered
#
unregister_ralph_global_instance() {
    # Skip if disabled
    if [[ "${RALPH_GLOBAL_DISABLE:-}" == "1" ]]; then
        return 0
    fi

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local link_name
    link_name=$(get_ralph_global_link_name)
    local link_path="$global_dir/instances/$link_name"

    if [[ -L "$link_path" || -e "$link_path" ]]; then
        # Use rm -rf for Windows compatibility (ln -s may create directories)
        if rm -rf "$link_path" 2>/dev/null; then
            add_ralph_instance_log "Unregistered from global registry"
            return 0
        fi
    fi

    return 0
}

# ensure_global_registration()
# Re-creates global symlink if it was removed (by cleanup or manually)
# Called during heartbeat to maintain global registry consistency
# Returns: 0 on success, 1 on failure
#
ensure_global_registration() {
    # Skip if disabled
    if [[ "${RALPH_GLOBAL_DISABLE:-}" == "1" ]]; then
        return 0
    fi

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local link_name
    link_name=$(get_ralph_global_link_name)
    local link_path="$global_dir/instances/$link_name"

    # Get the local instance directory
    eval "$(get_ralph_paths)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    local instance_dir="$INSTANCES_DIR/$instance_id"

    # Only recreate if symlink is missing but instance directory exists
    if [[ ! -L "$link_path" && ! -e "$link_path" ]] && [[ -d "$instance_dir" ]]; then
        local instances_dir="$global_dir/instances"

        # Ensure directory exists
        if [[ ! -d "$instances_dir" ]]; then
            mkdir -p "$instances_dir" 2>/dev/null || return 1
        fi

        # Create symlink (silently, don't spam logs)
        ln -s "$instance_dir" "$link_path" 2>/dev/null || return 1
    fi

    return 0
}

# get_ralph_global_instances()
# Returns JSON array of all instances from the global registry
# This allows dashboards to see instances across all projects
# Arguments:
#   $1 - "all" to include dead instances, otherwise only active
# Output: JSON array of instance status objects with project info
#
get_ralph_global_instances() {
    local include_dead="${1:-}"

    local global_dir
    global_dir=$(get_ralph_global_dir)
    local instances_dir="$global_dir/instances"

    if [[ ! -d "$instances_dir" ]]; then
        echo "[]"
        return 0
    fi

    local now dead_threshold instances_json
    now=$(date +%s)
    dead_threshold=300  # 5 minutes

    instances_json="[]"

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

        local status heartbeat_age is_dead state last_heartbeat_epoch

        if ! status=$(cat "$status_file" 2>/dev/null); then
            continue
        fi

        last_heartbeat_epoch=$(echo "$status" | jq -r '.lastHeartbeatEpoch // 0')
        state=$(echo "$status" | jq -r '.state // "unknown"')
        heartbeat_age=$((now - last_heartbeat_epoch))

        # Check if dead (no heartbeat > 5 min and not in terminal state)
        if [[ "$heartbeat_age" -gt "$dead_threshold" && "$state" != "terminated" && "$state" != "completed" ]]; then
            is_dead="true"
        else
            is_dead="false"
        fi

        # Skip dead instances unless requested
        if [[ "$is_dead" == "true" && "$include_dead" != "all" ]]; then
            continue
        fi

        # Extract project name from link name (format: project-name-instance-id)
        local link_name project_name
        link_name=$(basename "$link")
        # Project name is everything before the first "-uge-" pattern
        project_name=$(echo "$link_name" | sed 's/-uge-.*$//')

        # Add isDead, heartbeatAge, and projectName to status
        status=$(echo "$status" | jq \
            --argjson isDead "$is_dead" \
            --argjson heartbeatAge "$heartbeat_age" \
            --arg projectName "$project_name" \
            '. + {isDead: $isDead, heartbeatAge: $heartbeatAge, projectName: $projectName}')

        instances_json=$(echo "$instances_json" | jq --argjson inst "$status" '. + [$inst]')
    done

    # Sort by lastHeartbeatEpoch descending (most recent first)
    echo "$instances_json" | jq 'sort_by(-.lastHeartbeatEpoch)'
}

# =============================================================================
# COLOR CODES
# =============================================================================

# Check if terminal supports colors
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    readonly COLOR_RED=$'\033[0;31m'
    readonly COLOR_GREEN=$'\033[0;32m'
    readonly COLOR_YELLOW=$'\033[0;33m'
    readonly COLOR_BLUE=$'\033[0;34m'
    readonly COLOR_CYAN=$'\033[0;36m'
    readonly COLOR_WHITE=$'\033[0;37m'
    readonly COLOR_GRAY=$'\033[0;90m'
    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_BOLD=$'\033[1m'  # Used for emphasis in other scripts
else
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_CYAN=""
    readonly COLOR_WHITE=""
    readonly COLOR_GRAY=""
    readonly COLOR_RESET=""
    # shellcheck disable=SC2034
    readonly COLOR_BOLD=""
fi

# =============================================================================
# PATH FUNCTIONS
# =============================================================================

# get_ralph_paths()
# Returns ralph directory paths as colon-separated key=value pairs
# Output format: RALPH_DIR=/path:PROJECT_ROOT=/path:PRD_FILE=/path:...
#
# Usage:
#   eval "$(get_ralph_paths)"
#   echo "$RALPH_DIR"
#
get_ralph_paths() {
    local ralph_dir="$RALPH_SCRIPT_DIR"
    local project_root
    project_root="${RALPH_PROJECT_ROOT:-}"
    if [[ -z "$project_root" ]]; then
        project_root="$(cd "$ralph_dir/../.." && pwd)"
    fi

    # Use exported PRD_FILE if set, otherwise default to script dir
    local prd_file="${RALPH_PRD_FILE:-$ralph_dir/prd.json}"

    # Determine work directory for locks/instances/progress
    # If project root is explicitly set and has a ralph subdir, use it
    local work_dir="$ralph_dir"
    local proj_root="${RALPH_PROJECT_ROOT:-}"
    if [[ -n "$proj_root" ]]; then
        if [[ -d "$proj_root/ralph" ]]; then
            work_dir="$proj_root/ralph"
        elif [[ -d "$proj_root/scripts/ralph" ]]; then
            work_dir="$proj_root/scripts/ralph"
        fi
    fi

    cat <<EOF
RALPH_DIR="$ralph_dir"
PROJECT_ROOT="$project_root"
PRD_FILE="$prd_file"
PROGRESS_FILE="$work_dir/progress.txt"
PROMPT_FILE="$ralph_dir/prompt.md"
LOG_FILE="$work_dir/ralph.log"
ARCHIVE_DIR="$work_dir/archive"
LAST_BRANCH_FILE="$work_dir/.last-branch"
INSTANCES_DIR="$work_dir/instances"
LOCKS_DIR="$work_dir/locks"
EOF
}

# get_ralph_dir()
# Returns the ralph scripts directory
#
get_ralph_dir() {
    echo "$RALPH_SCRIPT_DIR"
}

# get_project_root()
# Returns the project root directory (two levels up from ralph)
#
get_project_root() {
    cd "$RALPH_SCRIPT_DIR/../.." && pwd
}

# =============================================================================
# DEPENDENCY CHECKING
# =============================================================================

# test_dependencies()
# Checks if required dependencies are available
# Returns: 0 if all dependencies present, 1 otherwise
# Output: Error messages for missing dependencies
#
test_dependencies() {
    local errors=()
    local exit_code=0

    # Check for jq
    if ! command -v jq &>/dev/null; then
        errors+=("jq not found. Install with: apt install jq (or brew install jq)")
        exit_code=1
    fi

    # Check for git
    if ! command -v git &>/dev/null; then
        errors+=("git not found. Please install git.")
        exit_code=1
    fi

    # Check for claude CLI (optional warning)
    if ! command -v claude &>/dev/null; then
        errors+=("Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code")
        exit_code=1
    fi

    # Check bash version (4.0+)
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        errors+=("Bash 4.0+ required. Current version: $BASH_VERSION")
        exit_code=1
    fi

    # Output errors
    for err in "${errors[@]}"; do
        echo "$err" >&2
    done

    return $exit_code
}

# =============================================================================
# PRD JSON FUNCTIONS
# =============================================================================

# read_prd_json()
# Reads and outputs the PRD JSON file contents
# Arguments:
#   $1 - Optional path to prd.json (defaults to standard location)
# Returns: 0 on success, 1 on error
# Output: JSON content to stdout
#
read_prd_json() {
    local prd_file="${1:-}"

    if [[ -z "$prd_file" ]]; then
        eval "$(get_ralph_paths)"
        # shellcheck disable=SC2153
        prd_file="$PRD_FILE"
    fi

    if [[ ! -f "$prd_file" ]]; then
        echo "Error: PRD file not found: $prd_file" >&2
        return 1
    fi

    if ! jq '.' "$prd_file" 2>/dev/null; then
        echo "Error: Failed to parse PRD JSON: $prd_file" >&2
        return 1
    fi
}

# write_prd_json()
# Writes JSON content to the PRD file
# Arguments:
#   $1 - JSON content to write
#   $2 - Optional path to prd.json
# Returns: 0 on success, 1 on error
#
write_prd_json() {
    local json_content="$1"
    local prd_file="${2:-}"

    if [[ -z "$prd_file" ]]; then
        eval "$(get_ralph_paths)"
        prd_file="$PRD_FILE"
    fi

    # Validate JSON before writing
    if ! echo "$json_content" | jq '.' &>/dev/null; then
        echo "Error: Invalid JSON content" >&2
        return 1
    fi

    echo "$json_content" > "$prd_file"
}

# get_prd_status()
# Returns PRD completion status
# Arguments:
#   $1 - Optional PRD JSON content (reads from file if not provided)
# Output: Exports variables: PRD_TOTAL, PRD_COMPLETE, PRD_REMAINING, PRD_PERCENTAGE
#
# Usage:
#   eval "$(get_prd_status)"
#   echo "Progress: $PRD_COMPLETE/$PRD_TOTAL ($PRD_PERCENTAGE%)"
#
get_prd_status() {
    local prd_json="${1:-}"

    if [[ -z "$prd_json" ]]; then
        eval "$(get_ralph_paths)"
        if [[ ! -f "$PRD_FILE" ]]; then
            cat <<EOF
PRD_TOTAL=0
PRD_COMPLETE=0
PRD_REMAINING=0
PRD_PERCENTAGE=0
EOF
            return 0
        fi
        prd_json=$(cat "$PRD_FILE")
    fi

    local total complete remaining percentage

    total=$(echo "$prd_json" | jq '.userStories | length')
    complete=$(echo "$prd_json" | jq '[.userStories[] | select(.passes == true)] | length')
    remaining=$((total - complete))

    if [[ "$total" -gt 0 ]]; then
        percentage=$((complete * 100 / total))
    else
        percentage=0
    fi

    cat <<EOF
PRD_TOTAL=$total
PRD_COMPLETE=$complete
PRD_REMAINING=$remaining
PRD_PERCENTAGE=$percentage
EOF
}

# get_incomplete_stories()
# Returns incomplete stories sorted by priority as JSON array
# Arguments:
#   $1 - Optional PRD JSON content
# Output: JSON array of incomplete stories
#
get_incomplete_stories() {
    local prd_json="${1:-}"

    if [[ -z "$prd_json" ]]; then
        eval "$(get_ralph_paths)"
        if [[ ! -f "$PRD_FILE" ]]; then
            echo "[]"
            return 0
        fi
        prd_json=$(cat "$PRD_FILE")
    fi

    echo "$prd_json" | jq '[.userStories[] | select(.passes == false)] | sort_by(.priority)'
}

# =============================================================================
# COLORED OUTPUT FUNCTIONS
# =============================================================================

# write_colored()
# Outputs colored text to stdout
# Arguments:
#   $1 - Color name (red, green, yellow, blue, cyan, white, gray)
#   $2 - Message to display
#   $3 - Optional: "-n" for no newline
#
write_colored() {
    local color_name="$1"
    local message="$2"
    local newline="${3:-}"
    local color_code

    case "$color_name" in
        red)    color_code="$COLOR_RED" ;;
        green)  color_code="$COLOR_GREEN" ;;
        yellow) color_code="$COLOR_YELLOW" ;;
        blue)   color_code="$COLOR_BLUE" ;;
        cyan)   color_code="$COLOR_CYAN" ;;
        white)  color_code="$COLOR_WHITE" ;;
        gray)   color_code="$COLOR_GRAY" ;;
        *)      color_code="" ;;
    esac

    if [[ "$newline" == "-n" ]]; then
        printf "%s%s%s" "$color_code" "$message" "$COLOR_RESET"
    else
        printf "%s%s%s\n" "$color_code" "$message" "$COLOR_RESET"
    fi
}

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# add_log_entry()
# Adds a timestamped entry to the ralph log file
# Arguments:
#   $1 - Message to log
#   $2 - Optional path to log file
#
add_log_entry() {
    local message="$1"
    local log_file="${2:-}"

    if [[ -z "$log_file" ]]; then
        eval "$(get_ralph_paths)"
        # shellcheck disable=SC2153
        log_file="$LOG_FILE"
    fi

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] $message" >> "$log_file"
}

# =============================================================================
# MULTI-INSTANCE FUNCTIONS
# =============================================================================

# get_ralph_instance_id()
# Generates or returns the unique instance ID for this session
# Format: {username}-{hostname}-{pid}-{timestamp}
# Arguments:
#   $1 - Optional: "force" to regenerate
# Output: Instance ID string
#
get_ralph_instance_id() {
    local force="${1:-}"

    if [[ -n "$_RALPH_INSTANCE_ID" && "$force" != "force" ]]; then
        echo "$_RALPH_INSTANCE_ID"
        return 0
    fi

    local user hostname pid_num timestamp

    user="${USER:-${USERNAME:-unknown}}"
    hostname="${HOSTNAME:-$(hostname 2>/dev/null || echo "local")}"
    # Clean hostname of special characters
    hostname="${hostname//[^a-zA-Z0-9_-]/}"
    pid_num="$$"
    timestamp=$(date +%s)

    _RALPH_INSTANCE_ID="${user}-${hostname}-${pid_num}-${timestamp}"
    _RALPH_INSTANCE_SHORT_ID="${_RALPH_INSTANCE_ID:0:8}"

    echo "$_RALPH_INSTANCE_ID"
}

# get_ralph_short_id()
# Returns the short (8-character) instance ID
#
get_ralph_short_id() {
    if [[ -z "$_RALPH_INSTANCE_SHORT_ID" ]]; then
        get_ralph_instance_id > /dev/null
    fi
    echo "$_RALPH_INSTANCE_SHORT_ID"
}

# new_ralph_instance_directory()
# Creates the instance-specific directory structure
# Arguments:
#   $1 - Optional instance ID
# Output: Exports INSTANCE_DIR, INSTANCE_LOG_FILE, INSTANCE_PROGRESS_FILE, INSTANCE_STATUS_FILE
#
# shellcheck disable=SC2153
new_ralph_instance_directory() {
    local instance_id="${1:-$(get_ralph_instance_id)}"
    local short_id
    short_id=$(get_ralph_short_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"

    # Create directories
    mkdir -p "$instance_dir"
    mkdir -p "$LOCKS_DIR"

    local instance_log_file="$instance_dir/ralph.log"
    local instance_progress_file="$instance_dir/progress.txt"
    local instance_status_file="$instance_dir/status.json"

    # Initialize log file (PROJECT_ROOT is set by eval above)
    cat > "$instance_log_file" <<EOF
# Ralph Instance Log
# Instance ID: $instance_id
# Short ID: $short_id
# Started: $(date '+%Y-%m-%d %H:%M:%S')
# Project: $PROJECT_ROOT
---
EOF

    # Initialize progress file
    cat > "$instance_progress_file" <<EOF
# Ralph Progress Log
Instance: $instance_id
Started: $(date '+%Y-%m-%d %H:%M:%S')

## Codebase Patterns
(Patterns discovered during implementation will be added here)

---
EOF

    # Initialize status
    update_ralph_status "starting" "" 0 10 ""

    # Output variables including the cached instance ID so they persist in parent shell
    cat <<EOF
INSTANCE_DIR="$instance_dir"
INSTANCE_LOG_FILE="$instance_log_file"
INSTANCE_PROGRESS_FILE="$instance_progress_file"
INSTANCE_STATUS_FILE="$instance_status_file"
_RALPH_INSTANCE_ID="$instance_id"
_RALPH_INSTANCE_SHORT_ID="$short_id"
EOF
}

# update_ralph_status()
# Updates the instance status.json file atomically
# Arguments:
#   $1 - State: starting, idle, claiming, working, merging, completed, terminated, max_iterations
#   $2 - Current story ID (optional)
#   $3 - Iteration number (optional, default 0)
#   $4 - Max iterations (optional, default 10)
#   $5 - Branch name (optional)
#
update_ralph_status() {
    local state="$1"
    local current_story="${2:-}"
    local iteration="${3:-0}"
    local max_iterations="${4:-10}"
    local branch="${5:-}"

    local instance_id
    instance_id=$(get_ralph_instance_id)
    local short_id
    short_id=$(get_ralph_short_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"
    local status_file="$instance_dir/status.json"

    # Ensure directory exists
    mkdir -p "$instance_dir"

    local now epoch_now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    epoch_now=$(date +%s)

    local status_json
    status_json=$(jq -n \
        --arg instance_id "$instance_id" \
        --arg short_id "$short_id" \
        --arg state "$state" \
        --arg current_story "$current_story" \
        --argjson iteration "$iteration" \
        --argjson max_iterations "$max_iterations" \
        --arg start_time "$now" \
        --arg last_heartbeat "$now" \
        --argjson last_heartbeat_epoch "$epoch_now" \
        --arg project_root "$PROJECT_ROOT" \
        --arg branch "$branch" \
        --argjson pid "$$" \
        '{
            instanceId: $instance_id,
            shortId: $short_id,
            state: $state,
            currentStory: $current_story,
            iteration: $iteration,
            maxIterations: $max_iterations,
            startTime: $start_time,
            lastHeartbeat: $last_heartbeat,
            lastHeartbeatEpoch: $last_heartbeat_epoch,
            projectRoot: $project_root,
            branch: $branch,
            pid: $pid
        }')

    # Atomic write: write to temp file, then rename
    local temp_file="${status_file}.tmp"
    echo "$status_json" > "$temp_file"
    mv "$temp_file" "$status_file"
}

# get_ralph_instance_status()
# Gets the status of a Ralph instance
# Arguments:
#   $1 - Instance ID
# Output: JSON status object or empty if not found
#
get_ralph_instance_status() {
    local instance_id="$1"

    eval "$(get_ralph_paths)"

    local status_file="$INSTANCES_DIR/$instance_id/status.json"

    if [[ ! -f "$status_file" ]]; then
        return 1
    fi

    cat "$status_file"
}

# get_ralph_instances()
# Gets all Ralph instances
# Arguments:
#   $1 - Optional: "all" to include dead instances
# Output: JSON array of instance status objects
#
get_ralph_instances() {
    local include_dead="${1:-}"

    eval "$(get_ralph_paths)"

    if [[ ! -d "$INSTANCES_DIR" ]]; then
        echo "[]"
        return 0
    fi

    local now dead_threshold instances_json
    now=$(date +%s)
    dead_threshold=300  # 5 minutes

    instances_json="[]"

    for instance_dir in "$INSTANCES_DIR"/*/; do
        [[ -d "$instance_dir" ]] || continue

        local status_file="$instance_dir/status.json"
        [[ -f "$status_file" ]] || continue

        local status heartbeat_age is_dead state last_heartbeat_epoch

        if ! status=$(cat "$status_file" 2>/dev/null); then
            continue
        fi

        last_heartbeat_epoch=$(echo "$status" | jq -r '.lastHeartbeatEpoch // 0')
        state=$(echo "$status" | jq -r '.state // "unknown"')
        heartbeat_age=$((now - last_heartbeat_epoch))

        # Check if dead (no heartbeat > 5 min and not in terminal state)
        if [[ "$heartbeat_age" -gt "$dead_threshold" && "$state" != "terminated" && "$state" != "completed" ]]; then
            is_dead="true"
        else
            is_dead="false"
        fi

        # Add isDead and heartbeatAge to status
        status=$(echo "$status" | jq \
            --argjson is_dead "$is_dead" \
            --argjson heartbeat_age "$heartbeat_age" \
            '. + {isDead: $is_dead, heartbeatAge: $heartbeat_age}')

        # Include or exclude based on dead status
        if [[ "$include_dead" == "all" || "$is_dead" == "false" ]]; then
            instances_json=$(echo "$instances_json" | jq --argjson status "$status" '. += [$status]')
        fi
    done

    echo "$instances_json"
}

# add_ralph_instance_log()
# Adds a log entry to the instance-specific log file
# Arguments:
#   $1 - Message to log
#
add_ralph_instance_log() {
    local message="$1"

    local instance_id short_id timestamp
    instance_id=$(get_ralph_instance_id)
    short_id=$(get_ralph_short_id)
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    eval "$(get_ralph_paths)"

    local log_file="$INSTANCES_DIR/$instance_id/ralph.log"

    # Ensure directory exists
    mkdir -p "$INSTANCES_DIR/$instance_id"

    local entry="[$timestamp] [$short_id] $message"

    echo "$entry" >> "$log_file"
    echo "$entry" >&2  # Output to stderr so it doesn't interfere with function return values
}

# =============================================================================
# STORY LOCKING FUNCTIONS
# =============================================================================

# lock_ralph_story()
# Acquires a lock on a story for exclusive access
# Arguments:
#   $1 - Story ID to lock
# Returns: 0 if lock acquired, 1 if already locked
#
lock_ralph_story() {
    local story_id="$1"

    # First cleanup any stale locks
    clear_ralph_stale_lock "$story_id" > /dev/null 2>&1 || true

    eval "$(get_ralph_paths)"

    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    # Atomic directory creation - fails if exists
    if ! mkdir "$lock_dir" 2>/dev/null; then
        return 1
    fi

    local instance_id
    instance_id=$(get_ralph_instance_id)
    local timestamp
    timestamp=$(date +%s)

    # Write owner and timestamp
    echo "$instance_id" > "$lock_dir/owner"
    echo "$timestamp" > "$lock_dir/timestamp"
    echo "$$" > "$lock_dir/pid.txt"

    add_ralph_instance_log "Acquired lock for $story_id"
    return 0
}

# unlock_ralph_story()
# Releases a lock on a story
# Arguments:
#   $1 - Story ID to unlock
#   $2 - Optional: "force" to release even if not owner
# Returns: 0 if lock released, 1 otherwise
#
unlock_ralph_story() {
    local story_id="$1"
    local force="${2:-}"

    eval "$(get_ralph_paths)"

    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    if [[ ! -d "$lock_dir" ]]; then
        return 0  # Already unlocked
    fi

    local owner=""
    if [[ -f "$lock_dir/owner.txt" ]]; then
        owner=$(cat "$lock_dir/owner.txt" | tr -d '\n')
    elif [[ -f "$lock_dir/owner" ]]; then
        owner=$(cat "$lock_dir/owner" | tr -d '\n')
    fi

    local instance_id
    instance_id=$(get_ralph_instance_id)

    if [[ "$force" == "force" || "$owner" == "$instance_id" ]]; then
        rm -rf "$lock_dir"
        add_ralph_instance_log "Released lock for $story_id"
        return 0
    else
        echo "Cannot release lock for $story_id - owned by $owner" >&2
        return 1
    fi
}

# test_ralph_story_locked()
# Tests if a story is currently locked
# Arguments:
#   $1 - Story ID to check
# Returns: 0 if locked, 1 if available
#
test_ralph_story_locked() {
    local story_id="$1"

    eval "$(get_ralph_paths)"

    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    [[ -d "$lock_dir" ]]
}

# get_ralph_story_lock()
# Gets information about a story lock
# Arguments:
#   $1 - Story ID to check
# Output: JSON object with lock info, or empty if not locked
#
get_ralph_story_lock() {
    local story_id="$1"

    eval "$(get_ralph_paths)"

    local lock_dir="$LOCKS_DIR/${story_id}.lock"

    if [[ ! -d "$lock_dir" ]]; then
        return 1
    fi

    local owner="unknown"
    local timestamp=0
    local pid=0

    # Read with .txt extension (new format) or without (legacy format)
    if [[ -f "$lock_dir/owner.txt" ]]; then
        owner=$(cat "$lock_dir/owner.txt" | tr -d '\n')
    elif [[ -f "$lock_dir/owner" ]]; then
        owner=$(cat "$lock_dir/owner" | tr -d '\n')
    fi
    if [[ -f "$lock_dir/timestamp.txt" ]]; then
        timestamp=$(cat "$lock_dir/timestamp.txt" | tr -d '\n')
    elif [[ -f "$lock_dir/timestamp" ]]; then
        timestamp=$(cat "$lock_dir/timestamp" | tr -d '\n')
    fi
    if [[ -f "$lock_dir/pid.txt" ]]; then
        pid=$(cat "$lock_dir/pid.txt" | tr -d '\n')
    elif [[ -f "$lock_dir/pid" ]]; then
        pid=$(cat "$lock_dir/pid" | tr -d '\n')
    fi

    local now age is_dead is_stale
    now=$(date +%s)
    age=$((now - timestamp))

    # Check if owner is dead
    is_dead="false"
    if status=$(get_ralph_instance_status "$owner" 2>/dev/null); then
        local heartbeat_epoch state
        heartbeat_epoch=$(echo "$status" | jq -r '.lastHeartbeatEpoch // 0')
        state=$(echo "$status" | jq -r '.state // "unknown"')
        local heartbeat_age=$((now - heartbeat_epoch))

        if [[ "$heartbeat_age" -gt 300 && "$state" != "terminated" && "$state" != "completed" ]]; then
            is_dead="true"
        fi
    fi

    # Check if stale (>2 hours)
    if [[ "$age" -gt 7200 ]]; then
        is_stale="true"
    else
        is_stale="false"
    fi

    jq -n \
        --arg story_id "$story_id" \
        --arg owner "$owner" \
        --argjson timestamp "$timestamp" \
        --argjson age "$age" \
        --argjson pid "$pid" \
        --argjson is_dead "$is_dead" \
        --argjson is_stale "$is_stale" \
        '{
            storyId: $story_id,
            owner: $owner,
            timestamp: $timestamp,
            age: $age,
            pid: $pid,
            isDead: $is_dead,
            isStale: $is_stale
        }'
}

# get_ralph_story_locks()
# Gets all current story locks
# Output: JSON array of lock information objects
#
get_ralph_story_locks() {
    eval "$(get_ralph_paths)"

    if [[ ! -d "$LOCKS_DIR" ]]; then
        echo "[]"
        return 0
    fi

    local locks_json="[]"

    for lock_dir in "$LOCKS_DIR"/*.lock/; do
        [[ -d "$lock_dir" ]] || continue

        local story_id
        story_id=$(basename "$lock_dir" .lock)

        local lock_info
        if lock_info=$(get_ralph_story_lock "$story_id" 2>/dev/null); then
            locks_json=$(echo "$locks_json" | jq --argjson lock "$lock_info" '. += [$lock]')
        fi
    done

    echo "$locks_json"
}

# clear_ralph_stale_lock()
# Clears a stale lock for a specific story
# Arguments:
#   $1 - Story ID to check
# Returns: 0 if lock was cleared, 1 if lock is valid or doesn't exist
#
clear_ralph_stale_lock() {
    local story_id="$1"

    local lock_info=""
    lock_info=$(get_ralph_story_lock "$story_id" 2>/dev/null) || true

    if [[ -z "$lock_info" ]]; then
        return 1
    fi

    local age is_dead
    age=$(echo "$lock_info" | jq -r '.age' 2>/dev/null) || age=""
    is_dead=$(echo "$lock_info" | jq -r '.isDead' 2>/dev/null) || is_dead="false"

    # Validate age is a number
    if [[ -z "$age" || ! "$age" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local stale_timeout="${RALPH_LOCK_TIMEOUT:-7200}"  # 2 hours default

    if [[ "$age" -gt "$stale_timeout" || "$is_dead" == "true" ]]; then
        local reason owner
        owner=$(echo "$lock_info" | jq -r '.owner')

        if [[ "$is_dead" == "true" ]]; then
            reason="dead owner"
        else
            reason="stale (${age}s)"
        fi

        add_ralph_instance_log "Clearing $reason lock for $story_id (owner: $owner)"
        unlock_ralph_story "$story_id" "force"
        return 0
    fi

    return 1
}

# clear_ralph_stale_locks()
# Clears all stale locks
# Output: Number of locks cleared
#
clear_ralph_stale_locks() {
    local cleared=0

    local locks_json
    locks_json=$(get_ralph_story_locks)

    local story_ids
    # Strip carriage returns for Windows/Git Bash compatibility
    story_ids=$(echo "$locks_json" | jq -r '.[].storyId' | tr -d '\r')

    for story_id in $story_ids; do
        if clear_ralph_stale_lock "$story_id"; then
            cleared=$((cleared + 1))
        fi
    done

    echo "$cleared"
}

# clear_ralph_instance_locks()
# Releases all locks held by this instance
# Output: Number of locks released
#
clear_ralph_instance_locks() {
    local instance_id
    instance_id=$(get_ralph_instance_id)

    local released=0
    local locks_json
    locks_json=$(get_ralph_story_locks)

    local owned_stories
    # Strip carriage returns for Windows/Git Bash compatibility
    owned_stories=$(echo "$locks_json" | jq -r --arg owner "$instance_id" '.[] | select(.owner == $owner) | .storyId' | tr -d '\r')

    for story_id in $owned_stories; do
        if unlock_ralph_story "$story_id"; then
            released=$((released + 1))
        fi
    done

    echo "$released"
}

# =============================================================================
# PRD ATOMIC OPERATIONS
# =============================================================================

# read_ralph_prd_safe()
# Reads the PRD file with file locking for safety
# Output: PRD JSON content
#
read_ralph_prd_safe() {
    eval "$(get_ralph_paths)"

    # Use flock for file-level locking if available
    if command -v flock &>/dev/null; then
        (
            flock -s 200
            read_prd_json
        ) 200>"$PRD_FILE.lock"
    else
        read_prd_json
    fi
}

# update_ralph_prd()
# Updates the PRD file atomically with a transformation
# Arguments:
#   $1 - Description of the update
#   $2 - jq filter to apply to the PRD
# Returns: 0 on success, 1 on error
#
# Example:
#   update_ralph_prd "Mark US-001 complete" '.userStories |= map(if .id == "US-001" then .passes = true else . end)'
#
update_ralph_prd() {
    local description="$1"
    local jq_filter="$2"

    eval "$(get_ralph_paths)"

    local prd_file="$PRD_FILE"
    local backup_file="$prd_file.bak"
    local temp_file="$prd_file.tmp"

    # Use flock for atomic operations if available
    local lock_cmd=""
    if command -v flock &>/dev/null; then
        lock_cmd="flock -x 200"
    fi

    (
        # Acquire exclusive lock
        if [[ -n "$lock_cmd" ]]; then
            eval "$lock_cmd"
        fi

        # Read current PRD
        local prd_json
        if ! prd_json=$(cat "$prd_file" 2>/dev/null); then
            echo "Error: Failed to read PRD" >&2
            return 1
        fi

        # Apply transformation
        local updated_json
        if ! updated_json=$(echo "$prd_json" | jq "$jq_filter"); then
            echo "Error: Failed to apply update" >&2
            return 1
        fi

        # Backup before write
        if [[ -f "$prd_file" ]]; then
            cp "$prd_file" "$backup_file"
        fi

        # Write to temp file first
        echo "$updated_json" > "$temp_file"

        # Validate JSON
        if ! jq '.' "$temp_file" > /dev/null 2>&1; then
            echo "Error: PRD update produced invalid JSON" >&2
            rm -f "$temp_file"
            return 1
        fi

        # Atomic rename
        mv "$temp_file" "$prd_file"

        add_ralph_instance_log "PRD updated: $description"
        return 0
    ) 200>"$prd_file.lock"
}

# =============================================================================
# STORY CLAIMING FUNCTIONS
# =============================================================================

# get_ralph_next_story()
# Gets the next unclaimed story by priority
# Output: JSON object of the next available story, or empty if none
#
get_ralph_next_story() {
    local prd_json
    prd_json=$(read_ralph_prd_safe 2>/dev/null) || return 1

    if [[ -z "$prd_json" ]]; then
        return 1
    fi

    # Get incomplete, unclaimed stories sorted by priority
    local available
    available=$(echo "$prd_json" | jq '[.userStories[] | select(.passes == false) | select(.claimedBy == null or .claimedBy == "")] | sort_by(.priority)')

    local story_count
    story_count=$(echo "$available" | jq 'length')

    if [[ "$story_count" -eq 0 ]]; then
        return 1
    fi

    # Find first unlocked story
    for i in $(seq 0 $((story_count - 1))); do
        local story_id
        story_id=$(echo "$available" | jq -r ".[$i].id")

        if ! test_ralph_story_locked "$story_id"; then
            echo "$available" | jq ".[$i]"
            return 0
        fi
    done

    return 1
}

# request_ralph_story_claim()
# Claims a story for exclusive work
# Arguments:
#   $1 - Story ID to claim
# Returns: 0 if claim succeeded, 1 otherwise
#
request_ralph_story_claim() {
    local story_id="$1"

    # Try to acquire lock
    if ! lock_ralph_story "$story_id"; then
        return 1
    fi

    local instance_id
    instance_id=$(get_ralph_instance_id)

    # Update PRD with claim
    if ! update_ralph_prd "Claim $story_id" \
        ".userStories |= map(if .id == \"$story_id\" then .claimedBy = \"$instance_id\" else . end)"; then
        # Failed to update PRD, release lock
        unlock_ralph_story "$story_id"
        return 1
    fi

    add_ralph_instance_log "Claimed story: $story_id"
    return 0
}

# release_ralph_story_claim()
# Releases a story claim
# Arguments:
#   $1 - Story ID to release
# Returns: 0 if release succeeded
#
release_ralph_story_claim() {
    local story_id="$1"

    # Release lock
    unlock_ralph_story "$story_id" || true

    # Clear claimedBy in PRD
    update_ralph_prd "Release $story_id" \
        ".userStories |= map(if .id == \"$story_id\" then .claimedBy = null else . end)" || true

    add_ralph_instance_log "Released claim on $story_id"
    return 0
}

# request_ralph_next_story_claim()
# Claims the next available story with retry logic
# Arguments:
#   $1 - Max retries (default 5)
#   $2 - Retry delay in seconds (default 30)
# Output: JSON of claimed story, or empty if none available
#
request_ralph_next_story_claim() {
    local max_retries="${1:-5}"
    local retry_delay="${2:-30}"

    local retry=0
    while [[ "$retry" -lt "$max_retries" ]]; do
        # Clean up stale locks first
        clear_ralph_stale_locks > /dev/null

        local story
        if story=$(get_ralph_next_story 2>/dev/null); then
            local story_id
            story_id=$(echo "$story" | jq -r '.id')

            if request_ralph_story_claim "$story_id"; then
                echo "$story"
                return 0
            fi
            # Lock failed, try again
            continue
        fi

        # No stories available
        retry=$((retry + 1))
        if [[ "$retry" -lt "$max_retries" ]]; then
            add_ralph_instance_log "No available stories, waiting ${retry_delay}s (retry $retry/$max_retries)"
            sleep "$retry_delay"
        fi
    done

    add_ralph_instance_log "No stories available after $max_retries retries"
    return 1
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# format_duration()
# Formats seconds into human-readable duration
# Arguments:
#   $1 - Duration in seconds
# Output: Formatted string (e.g., "1h 23m 45s")
#
format_duration() {
    local seconds="$1"

    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ "$hours" -gt 0 ]]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif [[ "$minutes" -gt 0 ]]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

# render_progress_bar()
# Renders a progress bar using Unicode block characters
# Arguments:
#   $1 - Current value
#   $2 - Maximum value
#   $3 - Width in characters (default 20)
# Output: Progress bar string
#
render_progress_bar() {
    local current="$1"
    local max="$2"
    local width="${3:-20}"

    if [[ "$max" -eq 0 ]]; then
        printf "[%*s]" "$width" ""
        return
    fi

    local filled=$((current * width / max))
    # Clamp to width
    [[ "$filled" -gt "$width" ]] && filled="$width"
    local empty=$((width - filled))

    local bar="["
    local i
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    bar+="]"
    printf "%s" "$bar"
}

# =============================================================================
# GLOBAL QUEUE FUNCTIONS
# =============================================================================

# get_ralph_queue_file()
# Returns the path to the global queue file
# Output: Path to queue.json
#
get_ralph_queue_file() {
    local global_dir
    global_dir=$(get_ralph_global_dir)
    echo "$global_dir/queue.json"
}

# get_ralph_queue_lock()
# Returns the path to the queue lock file
# Output: Path to queue.lock
#
get_ralph_queue_lock() {
    local global_dir
    global_dir=$(get_ralph_global_dir)
    echo "$global_dir/queue.lock"
}

# init_ralph_queue()
# Creates the queue.json file if it doesn't exist
# Returns: 0 on success
#
init_ralph_queue() {
    local global_dir queue_file
    global_dir=$(get_ralph_global_dir)
    queue_file=$(get_ralph_queue_file)

    # Create global directory if needed
    if [[ ! -d "$global_dir" ]]; then
        mkdir -p "$global_dir" 2>/dev/null || return 1
        chmod 700 "$global_dir" 2>/dev/null || true
    fi

    # Create queue file if it doesn't exist
    if [[ ! -f "$queue_file" ]]; then
        echo '{"entries": []}' > "$queue_file"
        chmod 600 "$queue_file" 2>/dev/null || true
    fi

    return 0
}

# _generate_queue_entry_id()
# Generates a unique ID for a queue entry
# Output: Unique ID string
#
_generate_queue_entry_id() {
    local timestamp random_part
    timestamp=$(date +%s%N 2>/dev/null || date +%s)
    random_part=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "$$")
    echo "q-${timestamp:0:10}-${random_part:0:8}"
}

# add_ralph_queue_entry()
# Adds a PRD to the global queue
# Arguments:
#   $1 - Path to prd.json file (absolute)
#   $2 - Project root directory (absolute)
#   $3 - Priority (optional, default 10, lower = higher priority)
# Returns: 0 on success, 1 on error
# Output: Entry ID on success
#
add_ralph_queue_entry() {
    local prd_path="$1"
    local project_root="$2"
    local priority="${3:-10}"

    # Validate inputs
    if [[ ! -f "$prd_path" ]]; then
        echo "Error: PRD file not found: $prd_path" >&2
        return 1
    fi

    if [[ ! -d "$project_root" ]]; then
        echo "Error: Project root not found: $project_root" >&2
        return 1
    fi

    # Initialize queue if needed
    init_ralph_queue || return 1

    local queue_file queue_lock entry_id now
    queue_file=$(get_ralph_queue_file)
    queue_lock=$(get_ralph_queue_lock)
    entry_id=$(_generate_queue_entry_id)
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Create the new entry
    local new_entry
    new_entry=$(jq -n \
        --arg id "$entry_id" \
        --arg prdPath "$prd_path" \
        --arg projectRoot "$project_root" \
        --argjson priority "$priority" \
        --arg addedAt "$now" \
        '{
            id: $id,
            prdPath: $prdPath,
            projectRoot: $projectRoot,
            priority: $priority,
            status: "pending",
            addedAt: $addedAt,
            claimedBy: null,
            claimedAt: null,
            completedAt: null
        }')

    # Add entry with file locking
    (
        if command -v flock &>/dev/null; then
            flock -x 200
        fi

        local queue_json
        queue_json=$(cat "$queue_file")

        local updated_queue
        updated_queue=$(echo "$queue_json" | jq --argjson entry "$new_entry" '.entries += [$entry]')

        echo "$updated_queue" > "$queue_file.tmp"
        mv "$queue_file.tmp" "$queue_file"
    ) 200>"$queue_lock"

    echo "$entry_id"
    return 0
}

# get_ralph_queue_entries()
# Returns queue entries, optionally filtered by status
# Arguments:
#   $1 - Status filter: "pending", "active", "completed", "failed", or "all" (default: "pending")
# Output: JSON array of entries
#
get_ralph_queue_entries() {
    local status_filter="${1:-pending}"

    local queue_file
    queue_file=$(get_ralph_queue_file)

    if [[ ! -f "$queue_file" ]]; then
        echo "[]"
        return 0
    fi

    local entries
    if [[ "$status_filter" == "all" ]]; then
        entries=$(jq '.entries | sort_by(.priority)' "$queue_file")
    else
        entries=$(jq --arg status "$status_filter" \
            '[.entries[] | select(.status == $status)] | sort_by(.priority)' \
            "$queue_file")
    fi

    echo "$entries"
}

# get_ralph_queue_entry()
# Returns a specific queue entry by ID
# Arguments:
#   $1 - Entry ID
# Output: JSON object of entry
# Returns: 0 if found, 1 if not found
#
get_ralph_queue_entry() {
    local entry_id="$1"

    local queue_file
    queue_file=$(get_ralph_queue_file)

    if [[ ! -f "$queue_file" ]]; then
        return 1
    fi

    local entry
    entry=$(jq --arg id "$entry_id" '.entries[] | select(.id == $id)' "$queue_file")

    if [[ -z "$entry" || "$entry" == "null" ]]; then
        return 1
    fi

    echo "$entry"
    return 0
}

# claim_ralph_queue_entry()
# Claims the next pending queue entry for processing
# Arguments:
#   $1 - Instance ID claiming the entry
# Output: JSON of claimed entry
# Returns: 0 if claimed, 1 if no entries available
#
claim_ralph_queue_entry() {
    local instance_id="$1"

    local queue_file queue_lock
    queue_file=$(get_ralph_queue_file)
    queue_lock=$(get_ralph_queue_lock)

    if [[ ! -f "$queue_file" ]]; then
        return 1
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Claim with file locking
    (
        if command -v flock &>/dev/null; then
            flock -x 200
        fi

        local queue_json
        queue_json=$(cat "$queue_file")

        # Find first pending entry (sorted by priority)
        local pending_entry entry_id
        pending_entry=$(echo "$queue_json" | jq '[.entries[] | select(.status == "pending")] | sort_by(.priority) | .[0]')

        if [[ -z "$pending_entry" || "$pending_entry" == "null" ]]; then
            exit 1
        fi

        entry_id=$(echo "$pending_entry" | jq -r '.id')

        # Update the entry
        local updated_queue
        updated_queue=$(echo "$queue_json" | jq \
            --arg id "$entry_id" \
            --arg claimedBy "$instance_id" \
            --arg claimedAt "$now" \
            '.entries |= map(
                if .id == $id then
                    .status = "active" | .claimedBy = $claimedBy | .claimedAt = $claimedAt
                else .
                end
            )')

        echo "$updated_queue" > "$queue_file.tmp"
        mv "$queue_file.tmp" "$queue_file"

        # Output the claimed entry with updated status
        echo "$pending_entry" | jq \
            --arg claimedBy "$instance_id" \
            --arg claimedAt "$now" \
            '. + {status: "active", claimedBy: $claimedBy, claimedAt: $claimedAt}'

    ) 200>"$queue_lock"

    local exit_code=$?
    return $exit_code
}

# complete_ralph_queue_entry()
# Marks a queue entry as completed or failed
# Arguments:
#   $1 - Entry ID
#   $2 - Status: "completed" (default) or "failed"
# Returns: 0 on success, 1 if entry not found
#
complete_ralph_queue_entry() {
    local entry_id="$1"
    local status="${2:-completed}"

    local queue_file queue_lock
    queue_file=$(get_ralph_queue_file)
    queue_lock=$(get_ralph_queue_lock)

    if [[ ! -f "$queue_file" ]]; then
        return 1
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update with file locking
    (
        if command -v flock &>/dev/null; then
            flock -x 200
        fi

        local queue_json
        queue_json=$(cat "$queue_file")

        # Check if entry exists
        local entry_exists
        entry_exists=$(echo "$queue_json" | jq --arg id "$entry_id" '[.entries[] | select(.id == $id)] | length')

        if [[ "$entry_exists" -eq 0 ]]; then
            exit 1
        fi

        # Update the entry
        local updated_queue
        updated_queue=$(echo "$queue_json" | jq \
            --arg id "$entry_id" \
            --arg status "$status" \
            --arg completedAt "$now" \
            '.entries |= map(
                if .id == $id then
                    .status = $status | .completedAt = $completedAt
                else .
                end
            )')

        echo "$updated_queue" > "$queue_file.tmp"
        mv "$queue_file.tmp" "$queue_file"
    ) 200>"$queue_lock"

    return $?
}

# remove_ralph_queue_entry()
# Removes an entry from the queue
# Arguments:
#   $1 - Entry ID
# Returns: 0 on success, 1 if entry not found
#
remove_ralph_queue_entry() {
    local entry_id="$1"

    local queue_file queue_lock
    queue_file=$(get_ralph_queue_file)
    queue_lock=$(get_ralph_queue_lock)

    if [[ ! -f "$queue_file" ]]; then
        return 1
    fi

    # Remove with file locking
    (
        if command -v flock &>/dev/null; then
            flock -x 200
        fi

        local queue_json
        queue_json=$(cat "$queue_file")

        # Check if entry exists
        local entry_exists
        entry_exists=$(echo "$queue_json" | jq --arg id "$entry_id" '[.entries[] | select(.id == $id)] | length')

        if [[ "$entry_exists" -eq 0 ]]; then
            exit 1
        fi

        # Remove the entry
        local updated_queue
        updated_queue=$(echo "$queue_json" | jq \
            --arg id "$entry_id" \
            '.entries |= [.[] | select(.id != $id)]')

        echo "$updated_queue" > "$queue_file.tmp"
        mv "$queue_file.tmp" "$queue_file"
    ) 200>"$queue_lock"

    return $?
}

# clear_ralph_queue_completed()
# Removes all completed entries from the queue
# Output: Number of entries removed
# Returns: 0 on success
#
clear_ralph_queue_completed() {
    local queue_file queue_lock
    queue_file=$(get_ralph_queue_file)
    queue_lock=$(get_ralph_queue_lock)

    if [[ ! -f "$queue_file" ]]; then
        echo "0"
        return 0
    fi

    # Clear with file locking
    (
        if command -v flock &>/dev/null; then
            flock -x 200
        fi

        local queue_json
        queue_json=$(cat "$queue_file")

        # Count completed entries
        local completed_count
        completed_count=$(echo "$queue_json" | jq '[.entries[] | select(.status == "completed")] | length')

        # Remove completed entries
        local updated_queue
        updated_queue=$(echo "$queue_json" | jq \
            '.entries |= [.[] | select(.status != "completed")]')

        echo "$updated_queue" > "$queue_file.tmp"
        mv "$queue_file.tmp" "$queue_file"

        echo "$completed_count"
    ) 200>"$queue_lock"
}

# get_ralph_queue_summary()
# Returns a summary of queue status counts
# Output: JSON object with status counts
#
get_ralph_queue_summary() {
    local queue_file
    queue_file=$(get_ralph_queue_file)

    if [[ ! -f "$queue_file" ]]; then
        echo '{"total": 0, "pending": 0, "active": 0, "completed": 0, "failed": 0}'
        return 0
    fi

    jq '{
        total: (.entries | length),
        pending: ([.entries[] | select(.status == "pending")] | length),
        active: ([.entries[] | select(.status == "active")] | length),
        completed: ([.entries[] | select(.status == "completed")] | length),
        failed: ([.entries[] | select(.status == "failed")] | length)
    }' "$queue_file"
}

# get_ralph_next_queued_prd()
# Gets the next pending PRD from the global queue without claiming it
# Output: JSON object of next pending entry, or empty if none
# Returns: 0 if found, 1 if queue is empty
#
get_ralph_next_queued_prd() {
    local queue_file
    queue_file=$(get_ralph_queue_file)

    if [[ ! -f "$queue_file" ]]; then
        return 1
    fi

    local next_entry
    next_entry=$(jq '[.entries[] | select(.status == "pending")] | sort_by(.priority) | .[0]' "$queue_file")

    if [[ -z "$next_entry" || "$next_entry" == "null" ]]; then
        return 1
    fi

    echo "$next_entry"
    return 0
}

# =============================================================================
# NOTIFICATION FUNCTIONS
# =============================================================================

# get_notification_config_file()
# Returns the path to the notification config file
#
get_notification_config_file() {
    echo "$(get_ralph_global_dir)/mcp/notifications.json"
}

# ralph_notify()
# Sends a notification to configured channels
# Arguments:
#   $1 - Event type (rate_limit_detected, prd_completed, etc.)
#   $2 - Title
#   $3 - Message
#   $4 - Instance ID (optional)
#   $5 - Project root (optional)
#
ralph_notify() {
    local event="$1"
    local title="$2"
    local message="$3"
    local instance_id="${4:-}"
    local project_root="${5:-}"

    local config_file
    config_file=$(get_notification_config_file)

    # Check if notifications are configured
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Read config and check if event is enabled
    local event_config
    event_config=$(jq -r ".events.${event} // empty" "$config_file" 2>/dev/null)

    if [[ -z "$event_config" ]]; then
        return 0
    fi

    local enabled channels
    enabled=$(echo "$event_config" | jq -r '.enabled // false')
    channels=$(echo "$event_config" | jq -r '.channels // []')

    if [[ "$enabled" != "true" || "$channels" == "[]" ]]; then
        return 0
    fi

    # Get channel configs and send notifications
    echo "$channels" | jq -r '.[]' 2>/dev/null | while read -r channel_name; do
        local channel_config
        channel_config=$(jq -r ".channels.\"$channel_name\" // empty" "$config_file")

        if [[ -z "$channel_config" ]]; then
            continue
        fi

        local channel_type channel_url channel_enabled
        channel_type=$(echo "$channel_config" | jq -r '.type')
        channel_url=$(echo "$channel_config" | jq -r '.url')
        channel_enabled=$(echo "$channel_config" | jq -r '.enabled // true')

        if [[ "$channel_enabled" != "true" || -z "$channel_url" ]]; then
            continue
        fi

        # Format and send notification based on channel type
        local payload
        case "$channel_type" in
            slack)
                payload=$(format_slack_notification "$event" "$title" "$message" "$instance_id")
                ;;
            discord)
                payload=$(format_discord_notification "$event" "$title" "$message" "$instance_id")
                ;;
            *)
                payload=$(format_webhook_notification "$event" "$title" "$message" "$instance_id" "$project_root")
                ;;
        esac

        # Send notification (background, don't block)
        curl -s -X POST -H "Content-Type: application/json" \
            -d "$payload" "$channel_url" >/dev/null 2>&1 &
    done
}

# format_slack_notification()
# Formats a notification for Slack
#
format_slack_notification() {
    local event="$1"
    local title="$2"
    local message="$3"
    local instance_id="$4"

    local color emoji
    color=$(get_event_color "$event")
    emoji=$(get_event_emoji "$event")

    jq -n \
        --arg color "$color" \
        --arg title "$emoji $title" \
        --arg message "$message" \
        --arg instance_id "$instance_id" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            attachments: [{
                color: $color,
                blocks: [
                    {
                        type: "header",
                        text: { type: "plain_text", text: $title, emoji: true }
                    },
                    {
                        type: "section",
                        text: { type: "mrkdwn", text: $message }
                    },
                    {
                        type: "context",
                        elements: [
                            { type: "mrkdwn", text: ("Ralph MCP | " + $timestamp + (if $instance_id != "" then " | " + $instance_id else "" end)) }
                        ]
                    }
                ]
            }]
        }'
}

# format_discord_notification()
# Formats a notification for Discord
#
format_discord_notification() {
    local event="$1"
    local title="$2"
    local message="$3"
    local instance_id="$4"

    local color emoji
    color=$(get_event_color_decimal "$event")
    emoji=$(get_event_emoji "$event")

    jq -n \
        --argjson color "$color" \
        --arg title "$emoji $title" \
        --arg message "$message" \
        --arg instance_id "$instance_id" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            embeds: [{
                title: $title,
                description: $message,
                color: $color,
                footer: { text: ("Ralph MCP" + (if $instance_id != "" then " | " + $instance_id else "" end)) },
                timestamp: $timestamp
            }]
        }'
}

# format_webhook_notification()
# Formats a notification for generic webhook
#
format_webhook_notification() {
    local event="$1"
    local title="$2"
    local message="$3"
    local instance_id="$4"
    local project_root="$5"

    jq -n \
        --arg event "$event" \
        --arg title "$title" \
        --arg message "$message" \
        --arg instance_id "$instance_id" \
        --arg project_root "$project_root" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            event: $event,
            title: $title,
            message: $message,
            instanceId: $instance_id,
            projectRoot: $project_root,
            timestamp: $timestamp
        }'
}

# get_event_color()
# Returns hex color for event type
#
get_event_color() {
    local event="$1"
    case "$event" in
        rate_limit_detected) echo "#ff9800" ;;
        rate_limit_cleared) echo "#4caf50" ;;
        prd_completed) echo "#2196f3" ;;
        story_completed) echo "#8bc34a" ;;
        instance_error) echo "#f44336" ;;
        instance_started) echo "#9c27b0" ;;
        instance_stopped) echo "#607d8b" ;;
        queue_empty) echo "#00bcd4" ;;
        *) echo "#757575" ;;
    esac
}

# get_event_color_decimal()
# Returns decimal color for Discord
#
get_event_color_decimal() {
    local event="$1"
    local hex
    hex=$(get_event_color "$event")
    printf "%d" "0x${hex#\#}"
}

# get_event_emoji()
# Returns emoji for event type
#
get_event_emoji() {
    local event="$1"
    case "$event" in
        rate_limit_detected) echo "⚠️" ;;
        rate_limit_cleared) echo "✅" ;;
        prd_completed) echo "🎉" ;;
        story_completed) echo "📝" ;;
        instance_error) echo "❌" ;;
        instance_started) echo "🚀" ;;
        instance_stopped) echo "🛑" ;;
        queue_empty) echo "📭" ;;
        *) echo "📢" ;;
    esac
}

# =============================================================================
# RATE LIMIT DETECTION FUNCTIONS
# =============================================================================

# get_global_rate_limit_file()
# Returns the path to the global rate limit marker file
#
get_global_rate_limit_file() {
    echo "$(get_ralph_global_dir)/rate_limited"
}

# detect_rate_limit_in_output()
# Scans a log file for rate limit patterns
# Arguments:
#   $1 - Path to log file to scan
# Output: The matched pattern if found
# Returns: 0 if rate limit detected, 1 if not
#
detect_rate_limit_in_output() {
    local log_file="$1"

    if [[ ! -f "$log_file" ]]; then
        return 1
    fi

    # Rate limit patterns to check
    local patterns=(
        'rate.?limit'
        '429'
        'too.?many.?requests'
        'overloaded'
        'capacity'
        'try.?again.?later'
        'request.?limit'
        'throttl'
    )

    for pattern in "${patterns[@]}"; do
        if grep -iqE "$pattern" "$log_file" 2>/dev/null; then
            echo "$pattern"
            return 0
        fi
    done

    return 1
}

# detect_rate_limit_by_exit_code()
# Checks if exit code indicates rate limiting
# Arguments:
#   $1 - Exit code from Claude process
# Returns: 0 if rate limit indicated, 1 if not
#
detect_rate_limit_by_exit_code() {
    local exit_code="$1"

    # Exit code 2 = rate limited (proposed convention)
    if [[ "$exit_code" == "2" ]]; then
        return 0
    fi

    return 1
}

# set_global_rate_limit()
# Sets the global rate limit marker so all instances pause
# Arguments:
#   $1 - Instance ID that detected the limit
#   $2 - Detection method
#   $3 - Trigger info (optional)
#
set_global_rate_limit() {
    local detected_by="$1"
    local detection_method="$2"
    local trigger_info="${3:-}"

    local rate_limit_file
    rate_limit_file=$(get_global_rate_limit_file)

    mkdir -p "$(dirname "$rate_limit_file")"

    local now now_epoch
    now=$(date -Iseconds)
    now_epoch=$(date +%s)

    cat > "$rate_limit_file" <<EOF
{
    "detectedBy": "$detected_by",
    "detectedAt": "$now",
    "detectedAtEpoch": $now_epoch,
    "detectionMethod": "$detection_method",
    "triggerInfo": "$trigger_info",
    "backoffSeconds": ${RALPH_RATE_BACKOFF_INITIAL:-60},
    "retryCount": 0
}
EOF

    echo -e "${RED}[GLOBAL] Rate limit detected by $detected_by - all instances will pause${NC}"
}

# check_global_rate_limit()
# Checks if a global rate limit is active
# Returns: 0 if rate limited, 1 if not
#
check_global_rate_limit() {
    local rate_limit_file
    rate_limit_file=$(get_global_rate_limit_file)

    if [[ -f "$rate_limit_file" ]]; then
        return 0
    fi
    return 1
}

# clear_global_rate_limit()
# Clears the global rate limit marker (called after successful work)
#
clear_global_rate_limit() {
    local rate_limit_file
    rate_limit_file=$(get_global_rate_limit_file)

    if [[ -f "$rate_limit_file" ]]; then
        rm -f "$rate_limit_file"
        echo -e "${GREEN}[GLOBAL] Rate limit cleared - instances can resume${NC}"

        # Send notification
        local instance_id short_id
        instance_id=$(get_ralph_instance_id 2>/dev/null || echo "")
        short_id=$(get_ralph_short_id 2>/dev/null || echo "")
        ralph_notify "rate_limit_cleared" "Rate Limit Cleared" \
            "Instance $short_id completed work successfully. All instances can resume." \
            "$instance_id" "${PROJECT_ROOT:-}"
    fi
}

# get_global_rate_limit_info()
# Gets info about the current global rate limit
# Output: JSON with rate limit details, or empty if not rate limited
#
get_global_rate_limit_info() {
    local rate_limit_file
    rate_limit_file=$(get_global_rate_limit_file)

    if [[ -f "$rate_limit_file" ]]; then
        cat "$rate_limit_file"
    fi
}

# wait_for_global_rate_limit_clear()
# Waits for the global rate limit to clear with exponential backoff
# Returns: 0 when cleared
#
wait_for_global_rate_limit_clear() {
    local instance_id short_id
    instance_id=$(get_ralph_instance_id)
    short_id=$(get_ralph_short_id)

    local rate_limit_file
    rate_limit_file=$(get_global_rate_limit_file)

    local initial_backoff="${RALPH_RATE_BACKOFF_INITIAL:-60}"
    local max_backoff="${RALPH_RATE_BACKOFF_MAX:-960}"
    local backoff_seconds=$initial_backoff

    # Update our status
    update_ralph_status "rate_limited" "" 0 10 ""

    while [[ -f "$rate_limit_file" ]]; do
        # Read current backoff from file
        local current_info
        current_info=$(cat "$rate_limit_file" 2>/dev/null)
        if [[ -n "$current_info" ]]; then
            backoff_seconds=$(echo "$current_info" | jq -r '.backoffSeconds // 60')
        fi

        # Add jitter (10% random variation)
        local jitter=$((RANDOM % (backoff_seconds / 10 + 1)))
        local wait_time=$((backoff_seconds + jitter))

        echo -e "${YELLOW}[$short_id] Global rate limit active. Waiting ${wait_time}s...${NC}"
        add_ralph_instance_log "Waiting for global rate limit to clear (${wait_time}s)"

        # Check for manual resume during wait
        local elapsed=0
        while [[ $elapsed -lt $wait_time ]]; do
            # Check if rate limit was cleared
            if [[ ! -f "$rate_limit_file" ]]; then
                echo -e "${GREEN}[$short_id] Global rate limit cleared. Resuming...${NC}"
                add_ralph_instance_log "Global rate limit cleared, resuming"
                update_ralph_status "idle" "" 0 10 ""
                return 0
            fi

            # Check for manual resume request
            if check_ralph_resume_requested; then
                clear_ralph_resume_request
                # Also clear global rate limit on manual resume
                clear_global_rate_limit
                echo -e "${GREEN}[$short_id] Manual resume - clearing global rate limit${NC}"
                add_ralph_instance_log "Manual resume, cleared global rate limit"
                update_ralph_status "idle" "" 0 10 ""
                return 0
            fi

            sleep 5
            elapsed=$((elapsed + 5))
        done

        # Increase backoff for next iteration (exponential)
        backoff_seconds=$((backoff_seconds * 2))
        if [[ $backoff_seconds -gt $max_backoff ]]; then
            backoff_seconds=$max_backoff
        fi

        # Update backoff in global file (first instance to update wins)
        if [[ -f "$rate_limit_file" ]]; then
            local retry_count
            retry_count=$(jq -r '.retryCount // 0' "$rate_limit_file")
            retry_count=$((retry_count + 1))

            jq --argjson backoff "$backoff_seconds" --argjson retry "$retry_count" \
                '.backoffSeconds = $backoff | .retryCount = $retry' \
                "$rate_limit_file" > "${rate_limit_file}.tmp" 2>/dev/null && \
                mv "${rate_limit_file}.tmp" "$rate_limit_file"
        fi
    done

    update_ralph_status "idle" "" 0 10 ""
    return 0
}

# handle_rate_limit_detection()
# Handles rate limit detection and enters rate limited state
# Arguments:
#   $1 - Detection method ("output_pattern", "exit_code", "api_poll")
#   $2 - Pattern or code that triggered detection (optional)
# Returns: 0 when ready to continue, 1 if should terminate
#
handle_rate_limit_detection() {
    local detection_method="$1"
    local trigger_info="${2:-}"
    local instance_id short_id

    instance_id=$(get_ralph_instance_id)
    short_id=$(get_ralph_short_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"

    echo -e "${YELLOW}[$short_id] Rate limit detected via $detection_method${NC}"
    if [[ -n "$trigger_info" ]]; then
        echo -e "${YELLOW}[$short_id] Trigger: $trigger_info${NC}"
    fi

    add_ralph_instance_log "Rate limit detected: method=$detection_method trigger=$trigger_info"

    # Set global rate limit so all instances pause
    set_global_rate_limit "$instance_id" "$detection_method" "$trigger_info"

    # Send notification
    ralph_notify "rate_limit_detected" "Rate Limit Detected" \
        "Instance $short_id detected rate limiting via $detection_method" \
        "$instance_id" "$PROJECT_ROOT"

    # Wait for global rate limit to clear
    wait_for_global_rate_limit_clear

    return 0
}

# =============================================================================
# PAUSE/RESUME FUNCTIONS (MCP Integration)
# =============================================================================

# check_ralph_pause_requested()
# Checks if a pause has been requested for this instance
# Returns: 0 if pause requested, 1 if not
#
check_ralph_pause_requested() {
    local instance_id
    instance_id=$(get_ralph_instance_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"
    local pause_file="$instance_dir/.pause_requested"

    if [[ -f "$pause_file" ]]; then
        return 0
    fi

    return 1
}

# check_ralph_resume_requested()
# Checks if a resume has been requested for this instance
# Returns: 0 if resume requested, 1 if not
#
check_ralph_resume_requested() {
    local instance_id
    instance_id=$(get_ralph_instance_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"
    local resume_file="$instance_dir/.resume_requested"

    if [[ -f "$resume_file" ]]; then
        return 0
    fi

    return 1
}

# clear_ralph_pause_request()
# Clears the pause request file
#
clear_ralph_pause_request() {
    local instance_id
    instance_id=$(get_ralph_instance_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"
    local pause_file="$instance_dir/.pause_requested"

    rm -f "$pause_file"
}

# clear_ralph_resume_request()
# Clears the resume request file
#
clear_ralph_resume_request() {
    local instance_id
    instance_id=$(get_ralph_instance_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"
    local resume_file="$instance_dir/.resume_requested"

    rm -f "$resume_file"
}

# enter_ralph_paused_state()
# Enters paused state and waits for resume signal
# Arguments:
#   $1 - Reason for pause (optional, default "manual")
#
enter_ralph_paused_state() {
    local reason="${1:-manual}"
    local instance_id short_id

    instance_id=$(get_ralph_instance_id)
    short_id=$(get_ralph_short_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"

    # Clear the pause request since we're now handling it
    clear_ralph_pause_request

    # Update status to paused
    update_ralph_status "paused" "" 0 10 ""

    echo -e "${YELLOW}[$short_id] Instance paused ($reason). Waiting for resume signal...${NC}"
    add_ralph_instance_log "Instance paused: $reason"

    # Wait for resume signal
    while true; do
        if check_ralph_resume_requested; then
            clear_ralph_resume_request
            echo -e "${GREEN}[$short_id] Resume signal received. Continuing...${NC}"
            add_ralph_instance_log "Instance resumed"
            update_ralph_status "idle" "" 0 10 ""
            return 0
        fi

        # Also check if we should terminate
        if [[ -f "$instance_dir/.terminate_requested" ]]; then
            rm -f "$instance_dir/.terminate_requested"
            echo -e "${RED}[$short_id] Terminate signal received during pause.${NC}"
            add_ralph_instance_log "Instance terminated during pause"
            return 1
        fi

        sleep 5
    done
}

# enter_ralph_rate_limited_state()
# Enters rate-limited state with exponential backoff
# Arguments:
#   $1 - Initial backoff seconds (default 60)
#   $2 - Max retries (default 5)
#
enter_ralph_rate_limited_state() {
    local initial_backoff="${1:-60}"
    local max_retries="${2:-5}"
    local instance_id short_id

    instance_id=$(get_ralph_instance_id)
    short_id=$(get_ralph_short_id)

    eval "$(get_ralph_paths)"

    local instance_dir="$INSTANCES_DIR/$instance_id"
    local rate_limit_file="$instance_dir/.rate_limited"

    # Write rate limit state file
    local now now_epoch
    now=$(date '+%Y-%m-%dT%H:%M:%SZ')
    now_epoch=$(date +%s)

    cat > "$rate_limit_file" <<EOF
{
    "instanceId": "$instance_id",
    "pausedAt": "$now",
    "pausedAtEpoch": $now_epoch,
    "reason": "rate_limit_detected",
    "backoffSeconds": $initial_backoff,
    "retryCount": 0,
    "maxRetries": $max_retries
}
EOF

    # Update status
    update_ralph_status "rate_limited" "" 0 10 ""

    local backoff_seconds=$initial_backoff
    local retry_count=0

    while [[ $retry_count -lt $max_retries ]]; do
        # Add jitter (10% random variation)
        local jitter=$((RANDOM % (backoff_seconds / 10 + 1)))
        local wait_time=$((backoff_seconds + jitter))

        echo -e "${YELLOW}[$short_id] Rate limited. Waiting ${wait_time}s (retry $((retry_count + 1))/$max_retries)...${NC}"
        add_ralph_instance_log "Rate limited, waiting ${wait_time}s (retry $((retry_count + 1))/$max_retries)"

        # Check for manual resume during backoff
        local elapsed=0
        while [[ $elapsed -lt $wait_time ]]; do
            if check_ralph_resume_requested; then
                clear_ralph_resume_request
                rm -f "$rate_limit_file"
                echo -e "${GREEN}[$short_id] Manual resume during rate limit backoff.${NC}"
                add_ralph_instance_log "Manually resumed from rate limit"
                update_ralph_status "idle" "" 0 10 ""
                return 0
            fi

            sleep 5
            elapsed=$((elapsed + 5))
        done

        # Exponential backoff (double each time, max 960s = 16min)
        backoff_seconds=$((backoff_seconds * 2))
        if [[ $backoff_seconds -gt 960 ]]; then
            backoff_seconds=960
        fi

        retry_count=$((retry_count + 1))

        # Update retry count in file
        jq --argjson retry "$retry_count" --argjson backoff "$backoff_seconds" \
            '.retryCount = $retry | .backoffSeconds = $backoff' \
            "$rate_limit_file" > "$rate_limit_file.tmp"
        mv "$rate_limit_file.tmp" "$rate_limit_file"
    done

    # Max retries exceeded
    rm -f "$rate_limit_file"
    echo -e "${RED}[$short_id] Max rate limit retries exceeded.${NC}"
    add_ralph_instance_log "Rate limit max retries exceeded"
    update_ralph_status "idle" "" 0 10 ""
    return 0
}
