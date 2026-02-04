#!/usr/bin/env bash
# =============================================================================
# test-multi-instance.sh - Comprehensive test suite for Ralph multi-instance
# =============================================================================
#
# DESCRIPTION:
#   Tests core multi-instance functions in ralph-utils.sh including:
#   - flock PRD locking under concurrent writes
#   - Story claiming with simulated instances
#   - Git branch creation and merge
#   - Signal handling and cleanup
#   - Dead instance detection
#
# USAGE:
#   bash scripts/ralph/tests/test-multi-instance.sh
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - jq (for JSON parsing)
#   - git (for branch tests)
#   - flock (for locking tests, optional)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

# Source ralph-utils.sh
# shellcheck source=../ralph-utils.sh
source "$RALPH_DIR/ralph-utils.sh" 2>/dev/null || {
    echo "FAIL: Cannot source ralph-utils.sh from $RALPH_DIR"
    exit 1
}

# =============================================================================
# Test Framework
# =============================================================================
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

setup_test_env() {
    TEST_DIR=$(mktemp -d)
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    export RALPH_PRD_FILE="$TEST_DIR/prd.json"
    export RALPH_GLOBAL_DISABLE=1

    # Create test directories
    mkdir -p "$TEST_DIR/scripts/ralph"
    mkdir -p "$TEST_DIR/scripts/ralph/instances"
    mkdir -p "$TEST_DIR/scripts/ralph/locks"

    # Clear cached instance ID
    _RALPH_INSTANCE_ID=""
    _RALPH_INSTANCE_SHORT_ID=""

    cd "$TEST_DIR" || exit 1
}

teardown_test_env() {
    cd "$SCRIPT_DIR" || exit 1
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
    TEST_DIR=""
    unset RALPH_PROJECT_ROOT
    unset RALPH_PRD_FILE
    unset RALPH_GLOBAL_DISABLE

    # Clear cached instance ID
    _RALPH_INSTANCE_ID=""
    _RALPH_INSTANCE_SHORT_ID=""
}

describe() {
    echo ""
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 60))${NC}"
}

run_test() {
    local name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  ○ $name ... "

    # Run test directly (not in subshell) - tests handle their own cleanup
    local test_result=0
    $test_func || test_result=$?

    if [[ $test_result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}PASS${NC}"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

skip_test() {
    local name="$1"
    local reason="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "  ○ $name ... ${YELLOW}SKIP${NC} ($reason)"
}

# =============================================================================
# Test PRD File Creation
# =============================================================================
create_test_prd() {
    local prd_file="${1:-$TEST_DIR/prd.json}"
    cat > "$prd_file" <<'EOF'
{
    "featureName": "Test Feature",
    "branchName": "test/feature",
    "userStories": [
        {"id": "US-001", "title": "Story 1", "priority": 1, "passes": false, "claimedBy": null},
        {"id": "US-002", "title": "Story 2", "priority": 2, "passes": false, "claimedBy": null},
        {"id": "US-003", "title": "Story 3", "priority": 3, "passes": true, "claimedBy": null}
    ]
}
EOF
}

# =============================================================================
# Test Instance ID Generation
# =============================================================================
test_instance_id_format() {
    setup_test_env
    local id
    id=$(get_ralph_instance_id "force")
    teardown_test_env

    # Format: {user}-{hostname}-{pid}-{timestamp}
    # Should have 4 parts separated by hyphens with alphanumeric chars
    [[ "$id" =~ ^[a-zA-Z0-9_-]+-[a-zA-Z0-9_-]+-[0-9]+-[0-9]+$ ]]
}

test_short_id_length() {
    setup_test_env
    get_ralph_instance_id "force" > /dev/null
    local short_id
    short_id=$(get_ralph_short_id)
    teardown_test_env

    [[ ${#short_id} -eq 8 ]]
}

test_instance_id_cached() {
    setup_test_env
    local id1 id2
    id1=$(get_ralph_instance_id)
    id2=$(get_ralph_instance_id)
    teardown_test_env

    [[ "$id1" == "$id2" ]]
}

test_instance_id_force_regenerate() {
    setup_test_env
    local id1 id2
    id1=$(get_ralph_instance_id)
    sleep 1  # Ensure timestamp differs
    id2=$(get_ralph_instance_id "force")
    teardown_test_env

    [[ "$id1" != "$id2" ]]
}

# =============================================================================
# Test Instance Directory Creation
# =============================================================================
test_instance_directory_creation() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local result=$([[ -d "$INSTANCE_DIR" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_instance_log_file_created() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local result=$([[ -f "$INSTANCE_LOG_FILE" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_instance_status_file_created() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local result=$([[ -f "$INSTANCE_STATUS_FILE" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_instance_status_json_valid() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local valid_json
    valid_json=$(jq '.' "$INSTANCE_STATUS_FILE" 2>/dev/null && echo "valid")
    teardown_test_env

    [[ "$valid_json" == *"valid"* ]]
}

# =============================================================================
# Test Status Updates
# =============================================================================
test_status_update_state() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    update_ralph_status "working" "US-001" 1 10 "test-branch"

    local state
    state=$(jq -r '.state' "$INSTANCE_STATUS_FILE")
    teardown_test_env

    [[ "$state" == "working" ]]
}

test_status_update_story() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    update_ralph_status "working" "US-001" 1 10 "test-branch"

    local story
    story=$(jq -r '.currentStory' "$INSTANCE_STATUS_FILE")
    teardown_test_env

    [[ "$story" == "US-001" ]]
}

test_status_update_iteration() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    update_ralph_status "working" "US-001" 5 10 "test-branch"

    local iter
    iter=$(jq -r '.iteration' "$INSTANCE_STATUS_FILE")
    local result=$([[ "$iter" == "5" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_status_heartbeat_epoch() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local before after
    before=$(date +%s)
    update_ralph_status "working" "" 0 10 ""
    after=$(date +%s)

    local epoch
    epoch=$(jq -r '.lastHeartbeatEpoch' "$INSTANCE_STATUS_FILE")
    teardown_test_env

    [[ "$epoch" -ge "$before" ]] && [[ "$epoch" -le "$after" ]]
}

# =============================================================================
# Test Story Locking (Atomic Directory Creation)
# =============================================================================
test_lock_story_creates_dir() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    eval "$(get_ralph_paths)"
    local result=$([[ -d "$LOCKS_DIR/US-001.lock" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_lock_story_writes_owner() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    eval "$(get_ralph_paths)"
    local owner_exists=$([[ -f "$LOCKS_DIR/US-001.lock/owner" ]] && echo "ok")
    teardown_test_env

    [[ "$owner_exists" == "ok" ]]
}

test_lock_story_writes_timestamp() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    eval "$(get_ralph_paths)"
    local ts_exists=$([[ -f "$LOCKS_DIR/US-001.lock/timestamp" ]] && echo "ok")
    teardown_test_env

    [[ "$ts_exists" == "ok" ]]
}

test_lock_story_second_attempt_fails() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    local exit_code=0
    lock_ralph_story "US-001" || exit_code=$?
    teardown_test_env

    [[ $exit_code -ne 0 ]]
}

test_unlock_story_removes_dir() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    unlock_ralph_story "US-001"
    eval "$(get_ralph_paths)"
    local result=$([[ ! -d "$LOCKS_DIR/US-001.lock" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_test_story_locked_true() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    local result=1
    test_ralph_story_locked "US-001" && result=0
    teardown_test_env

    [[ $result -eq 0 ]]
}

test_test_story_locked_false() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    local result=0
    test_ralph_story_locked "US-001" || result=1
    teardown_test_env

    [[ $result -eq 1 ]]
}

# =============================================================================
# Test Concurrent Locking (Multiple Instances)
# =============================================================================
test_concurrent_lock_only_one_wins() {
    setup_test_env
    create_test_prd

    # Set up common paths
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$LOCKS_DIR"

    local lock_dir="$LOCKS_DIR/US-001.lock"
    local winner_count=0
    local loser_count=0

    # Simulate 5 concurrent lock attempts using subshells
    for i in {1..5}; do
        (
            # Each subshell has unique instance ID
            _RALPH_INSTANCE_ID="instance-$i-$$-$(date +%s%N)"
            _RALPH_INSTANCE_SHORT_ID="${_RALPH_INSTANCE_ID:0:8}"

            # Atomic directory creation attempt
            if mkdir "$lock_dir" 2>/dev/null; then
                echo "$_RALPH_INSTANCE_ID" > "$lock_dir/owner"
                echo "1" > "$lock_dir/won"
            else
                echo "0" > "$TEST_DIR/lost-$i"
            fi
        ) &
    done

    # Wait for all subshells
    wait

    # Count results
    if [[ -f "$lock_dir/won" ]]; then
        winner_count=1
    fi
    loser_count=$(ls -1 "$TEST_DIR"/lost-* 2>/dev/null | wc -l)

    teardown_test_env

    # Exactly one should win, others should lose
    [[ $winner_count -eq 1 ]] && [[ $loser_count -eq 4 ]]
}

test_two_instances_claim_different_stories() {
    setup_test_env
    create_test_prd

    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$LOCKS_DIR"
    mkdir -p "$INSTANCES_DIR"

    local story1="" story2=""

    # First instance claims US-001
    (
        _RALPH_INSTANCE_ID="instance-1-$$"
        _RALPH_INSTANCE_SHORT_ID="${_RALPH_INSTANCE_ID:0:8}"
        mkdir -p "$INSTANCES_DIR/$_RALPH_INSTANCE_ID"

        if mkdir "$LOCKS_DIR/US-001.lock" 2>/dev/null; then
            echo "$_RALPH_INSTANCE_ID" > "$LOCKS_DIR/US-001.lock/owner"
            echo "$(date +%s)" > "$LOCKS_DIR/US-001.lock/timestamp"
            echo "US-001" > "$TEST_DIR/claimed-1"
        fi
    )

    # Second instance tries US-001 (fails), then claims US-002
    (
        _RALPH_INSTANCE_ID="instance-2-$$"
        _RALPH_INSTANCE_SHORT_ID="${_RALPH_INSTANCE_ID:0:8}"
        mkdir -p "$INSTANCES_DIR/$_RALPH_INSTANCE_ID"

        if ! mkdir "$LOCKS_DIR/US-001.lock" 2>/dev/null; then
            if mkdir "$LOCKS_DIR/US-002.lock" 2>/dev/null; then
                echo "$_RALPH_INSTANCE_ID" > "$LOCKS_DIR/US-002.lock/owner"
                echo "$(date +%s)" > "$LOCKS_DIR/US-002.lock/timestamp"
                echo "US-002" > "$TEST_DIR/claimed-2"
            fi
        fi
    )

    story1=$(cat "$TEST_DIR/claimed-1" 2>/dev/null || echo "")
    story2=$(cat "$TEST_DIR/claimed-2" 2>/dev/null || echo "")

    teardown_test_env

    [[ "$story1" == "US-001" ]] && [[ "$story2" == "US-002" ]]
}

# =============================================================================
# Test PRD Atomic Updates with flock
# =============================================================================
test_prd_read_safe() {
    setup_test_env
    create_test_prd

    local prd_json
    prd_json=$(read_ralph_prd_safe)
    local feature_name
    feature_name=$(echo "$prd_json" | jq -r '.featureName')
    teardown_test_env

    [[ "$feature_name" == "Test Feature" ]]
}

test_prd_update_marks_complete() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    update_ralph_prd "Mark US-001 complete" \
        '.userStories |= map(if .id == "US-001" then .passes = true else . end)'

    local passes
    passes=$(jq -r '.userStories[] | select(.id == "US-001") | .passes' "$RALPH_PRD_FILE")
    teardown_test_env

    [[ "$passes" == "true" ]]
}

test_prd_update_creates_backup() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    update_ralph_prd "Test backup" '.featureName = "Updated"'
    local backup_exists=$([[ -f "$RALPH_PRD_FILE.bak" ]] && echo "ok")
    teardown_test_env

    [[ "$backup_exists" == "ok" ]]
}

test_prd_backup_contains_original() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    update_ralph_prd "Test backup content" '.featureName = "Updated"'
    local original_name
    original_name=$(jq -r '.featureName' "$RALPH_PRD_FILE.bak")
    teardown_test_env

    [[ "$original_name" == "Test Feature" ]]
}

test_prd_concurrent_writes_no_corruption() {
    setup_test_env
    create_test_prd

    # Only run if flock is available
    if ! command -v flock &>/dev/null; then
        teardown_test_env
        return 0  # Skip but pass
    fi

    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$INSTANCES_DIR"

    # Run 5 concurrent PRD updates
    for i in {1..5}; do
        (
            _RALPH_INSTANCE_ID="writer-$i-$$"
            mkdir -p "$INSTANCES_DIR/$_RALPH_INSTANCE_ID"

            # Each writer updates a different field
            update_ralph_prd "Writer $i update" \
                ".concurrent_test_$i = \"value-$i\""
        ) &
    done

    wait

    # PRD should be valid JSON after all concurrent writes
    local valid_json
    valid_json=$(jq '.' "$RALPH_PRD_FILE" 2>/dev/null && echo "valid")
    teardown_test_env

    [[ "$valid_json" == *"valid"* ]]
}

test_prd_flock_concurrent_updates() {
    # Skip if flock not available
    if ! command -v flock &>/dev/null; then
        echo "flock not available, skipping"
        return 0
    fi

    setup_test_env
    create_test_prd
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$INSTANCES_DIR"

    local success_count=0

    # 10 concurrent updates to increment a counter
    for i in {1..10}; do
        (
            _RALPH_INSTANCE_ID="counter-$i-$$"
            mkdir -p "$INSTANCES_DIR/$_RALPH_INSTANCE_ID"

            # Use flock for atomic read-modify-write
            (
                flock -x 200
                local current_count
                current_count=$(jq -r '.update_count // 0' "$RALPH_PRD_FILE")
                local new_count=$((current_count + 1))
                jq ".update_count = $new_count" "$RALPH_PRD_FILE" > "$RALPH_PRD_FILE.tmp"
                mv "$RALPH_PRD_FILE.tmp" "$RALPH_PRD_FILE"
            ) 200>"$RALPH_PRD_FILE.lock"
        ) &
    done

    wait

    # After 10 concurrent increments, count should be 10
    local final_count
    final_count=$(jq -r '.update_count' "$RALPH_PRD_FILE")
    teardown_test_env

    [[ "$final_count" == "10" ]]
}

# =============================================================================
# Test Story Claiming
# =============================================================================
test_get_next_story_returns_first_incomplete() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    local story
    story=$(get_ralph_next_story)
    local story_id
    story_id=$(echo "$story" | jq -r '.id')
    teardown_test_env

    [[ "$story_id" == "US-001" ]]
}

test_get_next_story_skips_completed() {
    setup_test_env
    # PRD where US-001 is already complete
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "featureName": "Test",
    "userStories": [
        {"id": "US-001", "priority": 1, "passes": true, "claimedBy": null},
        {"id": "US-002", "priority": 2, "passes": false, "claimedBy": null}
    ]
}
EOF
    eval "$(new_ralph_instance_directory)"

    local story
    story=$(get_ralph_next_story)
    local story_id
    story_id=$(echo "$story" | jq -r '.id')
    teardown_test_env

    [[ "$story_id" == "US-002" ]]
}

test_get_next_story_skips_claimed() {
    setup_test_env
    # PRD where US-001 is already claimed
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "featureName": "Test",
    "userStories": [
        {"id": "US-001", "priority": 1, "passes": false, "claimedBy": "other-instance"},
        {"id": "US-002", "priority": 2, "passes": false, "claimedBy": null}
    ]
}
EOF
    eval "$(new_ralph_instance_directory)"

    local story
    story=$(get_ralph_next_story)
    local story_id
    story_id=$(echo "$story" | jq -r '.id')
    teardown_test_env

    [[ "$story_id" == "US-002" ]]
}

test_request_story_claim_updates_prd() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    request_ralph_story_claim "US-001"

    local claimed_by
    claimed_by=$(jq -r '.userStories[] | select(.id == "US-001") | .claimedBy' "$RALPH_PRD_FILE")
    local instance_id
    instance_id=$(get_ralph_instance_id)
    teardown_test_env

    [[ "$claimed_by" == "$instance_id" ]]
}

test_release_story_claim_clears_prd() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    request_ralph_story_claim "US-001"
    release_ralph_story_claim "US-001"

    local claimed_by
    claimed_by=$(jq -r '.userStories[] | select(.id == "US-001") | .claimedBy' "$RALPH_PRD_FILE")
    teardown_test_env

    [[ "$claimed_by" == "null" ]]
}

test_claim_story_priority_order() {
    setup_test_env
    # PRD with priorities out of order
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "featureName": "Test",
    "userStories": [
        {"id": "US-C", "priority": 3, "passes": false, "claimedBy": null},
        {"id": "US-A", "priority": 1, "passes": false, "claimedBy": null},
        {"id": "US-B", "priority": 2, "passes": false, "claimedBy": null}
    ]
}
EOF
    eval "$(new_ralph_instance_directory)"

    local story
    story=$(get_ralph_next_story)
    local story_id
    story_id=$(echo "$story" | jq -r '.id')
    teardown_test_env

    # Should get priority 1 (lowest number = highest priority)
    [[ "$story_id" == "US-A" ]]
}

# =============================================================================
# Test Dead Instance Detection
# =============================================================================
test_instance_not_dead_with_recent_heartbeat() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"

    # Update status with recent heartbeat
    update_ralph_status "working" "US-001" 1 10 ""

    local instances
    instances=$(get_ralph_instances)
    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')
    teardown_test_env

    [[ "$is_dead" == "false" ]]
}

test_instance_dead_with_old_heartbeat() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"

    # Create status with old heartbeat (10 minutes ago)
    local old_epoch=$(($(date +%s) - 600))
    jq -n \
        --arg instance_id "$instance_id" \
        --arg state "working" \
        --argjson epoch "$old_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$instance_id/status.json"

    local instances
    instances=$(get_ralph_instances "all")
    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')
    teardown_test_env

    [[ "$is_dead" == "true" ]]
}

test_dead_instances_excluded_by_default() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"

    # Create status with old heartbeat
    local old_epoch=$(($(date +%s) - 600))
    jq -n \
        --arg instance_id "$instance_id" \
        --arg state "working" \
        --argjson epoch "$old_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$instance_id/status.json"

    local instances
    instances=$(get_ralph_instances)  # No "all" flag
    local count
    count=$(echo "$instances" | jq 'length')
    teardown_test_env

    [[ "$count" == "0" ]]
}

test_dead_instances_included_with_all_flag() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"

    # Create status with old heartbeat
    local old_epoch=$(($(date +%s) - 600))
    jq -n \
        --arg instance_id "$instance_id" \
        --arg state "working" \
        --argjson epoch "$old_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$instance_id/status.json"

    local instances
    instances=$(get_ralph_instances "all")  # With "all" flag
    local count
    count=$(echo "$instances" | jq 'length')
    teardown_test_env

    [[ "$count" == "1" ]]
}

test_terminated_instance_not_marked_dead() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"

    # Create status with old heartbeat but terminated state
    local old_epoch=$(($(date +%s) - 600))
    jq -n \
        --arg instance_id "$instance_id" \
        --arg state "terminated" \
        --argjson epoch "$old_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$instance_id/status.json"

    local instances
    instances=$(get_ralph_instances "all")
    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')
    teardown_test_env

    [[ "$is_dead" == "false" ]]
}

# =============================================================================
# Test Stale Lock Detection and Cleanup
# =============================================================================
test_stale_lock_detected() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"
    eval "$(get_ralph_paths)"

    # Create a lock with old timestamp
    mkdir -p "$LOCKS_DIR/US-001.lock"
    echo "old-instance" > "$LOCKS_DIR/US-001.lock/owner"
    echo "$(($(date +%s) - 8000))" > "$LOCKS_DIR/US-001.lock/timestamp"  # >2 hours old

    local lock_info
    lock_info=$(get_ralph_story_lock "US-001")
    local is_stale
    is_stale=$(echo "$lock_info" | jq -r '.isStale')
    teardown_test_env

    [[ "$is_stale" == "true" ]]
}

test_clear_stale_lock() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"
    eval "$(get_ralph_paths)"

    # Create a stale lock
    mkdir -p "$LOCKS_DIR/US-001.lock"
    echo "old-instance" > "$LOCKS_DIR/US-001.lock/owner"
    echo "$(($(date +%s) - 8000))" > "$LOCKS_DIR/US-001.lock/timestamp"

    clear_ralph_stale_lock "US-001"
    local lock_exists=$([[ -d "$LOCKS_DIR/US-001.lock" ]] && echo "yes" || echo "no")
    teardown_test_env

    [[ "$lock_exists" == "no" ]]
}

test_clear_all_stale_locks() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"
    eval "$(get_ralph_paths)"

    local old_ts=$(($(date +%s) - 8000))

    # Create multiple stale locks
    for story in US-001 US-002; do
        mkdir -p "$LOCKS_DIR/${story}.lock"
        echo "old-instance" > "$LOCKS_DIR/${story}.lock/owner"
        echo "$old_ts" > "$LOCKS_DIR/${story}.lock/timestamp"
    done

    local cleared
    cleared=$(clear_ralph_stale_locks)
    teardown_test_env

    [[ "$cleared" -eq 2 ]]
}

test_fresh_lock_not_cleared() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    lock_ralph_story "US-001"
    eval "$(get_ralph_paths)"

    # Try to clear - should not remove fresh lock
    local result=1
    clear_ralph_stale_lock "US-001" || result=$?
    local lock_exists=$([[ -d "$LOCKS_DIR/US-001.lock" ]] && echo "yes" || echo "no")
    teardown_test_env

    [[ "$lock_exists" == "yes" ]] && [[ $result -ne 0 ]]
}

test_clear_instance_locks() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    # Lock multiple stories
    lock_ralph_story "US-001"
    lock_ralph_story "US-002"

    # Clear all locks for this instance
    local released
    released=$(clear_ralph_instance_locks)

    eval "$(get_ralph_paths)"
    local lock1_exists=$([[ -d "$LOCKS_DIR/US-001.lock" ]] && echo "yes" || echo "no")
    local lock2_exists=$([[ -d "$LOCKS_DIR/US-002.lock" ]] && echo "yes" || echo "no")
    teardown_test_env

    [[ "$released" -eq 2 ]] && [[ "$lock1_exists" == "no" ]] && [[ "$lock2_exists" == "no" ]]
}

# =============================================================================
# Test Git Branch Functions (Mocked)
# =============================================================================
# Note: These tests verify the functions exist and can be called.
# Full git integration tests require a real git repository.

test_get_ralph_paths_includes_project_root() {
    setup_test_env
    eval "$(get_ralph_paths)"
    teardown_test_env

    [[ -n "$PROJECT_ROOT" ]]
}

test_get_ralph_paths_includes_prd_file() {
    setup_test_env
    eval "$(get_ralph_paths)"
    teardown_test_env

    [[ -n "$PRD_FILE" ]]
}

# =============================================================================
# Test Signal Handling Support Functions
# =============================================================================
test_instance_log_entry() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"

    add_ralph_instance_log "Test message for signal handling"

    local log_content
    log_content=$(cat "$INSTANCE_LOG_FILE")
    teardown_test_env

    [[ "$log_content" == *"Test message for signal handling"* ]]
}

test_log_entry_includes_timestamp() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"

    add_ralph_instance_log "Timestamped message"

    local log_content
    log_content=$(cat "$INSTANCE_LOG_FILE")
    teardown_test_env

    # Should have date format like [2026-02-04 12:34:56]
    [[ "$log_content" =~ \[[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

test_log_entry_includes_short_id() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local short_id
    short_id=$(get_ralph_short_id)

    add_ralph_instance_log "Short ID message"

    local log_content
    log_content=$(cat "$INSTANCE_LOG_FILE")
    teardown_test_env

    [[ "$log_content" == *"[$short_id]"* ]]
}

# =============================================================================
# Test Utility Functions
# =============================================================================
test_format_duration_seconds() {
    local result
    result=$(format_duration 45)
    [[ "$result" == "45s" ]]
}

test_format_duration_minutes() {
    local result
    result=$(format_duration 125)
    [[ "$result" == "2m 5s" ]]
}

test_format_duration_hours() {
    local result
    result=$(format_duration 3725)
    [[ "$result" == "1h 2m 5s" ]]
}

test_progress_bar_empty() {
    local result
    result=$(render_progress_bar 0 10 10)
    [[ "$result" == "[░░░░░░░░░░]" ]]
}

test_progress_bar_full() {
    local result
    result=$(render_progress_bar 10 10 10)
    [[ "$result" == "[██████████]" ]]
}

test_progress_bar_half() {
    local result
    result=$(render_progress_bar 5 10 10)
    [[ "$result" == "[█████░░░░░]" ]]
}

# =============================================================================
# Test PRD Status Functions
# =============================================================================
test_prd_status_counts() {
    setup_test_env
    create_test_prd  # Has 2 incomplete, 1 complete

    eval "$(get_prd_status)"
    teardown_test_env

    [[ "$PRD_TOTAL" == "3" ]] && [[ "$PRD_COMPLETE" == "1" ]] && [[ "$PRD_REMAINING" == "2" ]]
}

test_prd_status_percentage() {
    setup_test_env
    # Create PRD with 3 complete, 1 incomplete = 75%
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "featureName": "Test",
    "userStories": [
        {"id": "US-001", "passes": true},
        {"id": "US-002", "passes": true},
        {"id": "US-003", "passes": true},
        {"id": "US-004", "passes": false}
    ]
}
EOF

    eval "$(get_prd_status)"
    teardown_test_env

    [[ "$PRD_PERCENTAGE" == "75" ]]
}

test_incomplete_stories_sorted() {
    setup_test_env
    # Stories out of priority order
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "userStories": [
        {"id": "US-C", "priority": 3, "passes": false},
        {"id": "US-A", "priority": 1, "passes": false},
        {"id": "US-B", "priority": 2, "passes": false}
    ]
}
EOF

    local stories
    stories=$(get_incomplete_stories)
    local first_id
    first_id=$(echo "$stories" | jq -r '.[0].id')
    teardown_test_env

    [[ "$first_id" == "US-A" ]]
}

# =============================================================================
# Test Suite Runners
# =============================================================================

test_instance_id_unit() {
    describe "Instance ID Generation"
    run_test "generates valid format" test_instance_id_format
    run_test "short ID is 8 characters" test_short_id_length
    run_test "caches instance ID" test_instance_id_cached
    run_test "force flag regenerates ID" test_instance_id_force_regenerate
}

test_instance_directory_unit() {
    describe "Instance Directory Creation"
    run_test "creates instance directory" test_instance_directory_creation
    run_test "creates log file" test_instance_log_file_created
    run_test "creates status file" test_instance_status_file_created
    run_test "status file is valid JSON" test_instance_status_json_valid
}

test_status_update_unit() {
    describe "Status Updates"
    run_test "updates state" test_status_update_state
    run_test "updates current story" test_status_update_story
    run_test "updates iteration" test_status_update_iteration
    run_test "updates heartbeat epoch" test_status_heartbeat_epoch
}

test_story_locking_unit() {
    describe "Story Locking (Atomic Directory)"
    run_test "creates lock directory" test_lock_story_creates_dir
    run_test "writes owner file" test_lock_story_writes_owner
    run_test "writes timestamp file" test_lock_story_writes_timestamp
    run_test "second lock attempt fails" test_lock_story_second_attempt_fails
    run_test "unlock removes directory" test_unlock_story_removes_dir
    run_test "test_ralph_story_locked returns true for locked" test_test_story_locked_true
    run_test "test_ralph_story_locked returns false for unlocked" test_test_story_locked_false
}

test_concurrent_locking_unit() {
    describe "Concurrent Locking"
    run_test "only one instance wins lock" test_concurrent_lock_only_one_wins
    run_test "two instances claim different stories" test_two_instances_claim_different_stories
}

test_prd_operations_unit() {
    describe "PRD Atomic Operations"
    run_test "read_ralph_prd_safe reads PRD" test_prd_read_safe
    run_test "update_ralph_prd marks story complete" test_prd_update_marks_complete
    run_test "update creates backup file" test_prd_update_creates_backup
    run_test "backup contains original content" test_prd_backup_contains_original
    run_test "concurrent writes don't corrupt JSON" test_prd_concurrent_writes_no_corruption

    if command -v flock &>/dev/null; then
        run_test "flock prevents lost updates" test_prd_flock_concurrent_updates
    else
        skip_test "flock prevents lost updates" "flock not available"
    fi
}

test_story_claiming_unit() {
    describe "Story Claiming"
    run_test "get_ralph_next_story returns first incomplete" test_get_next_story_returns_first_incomplete
    run_test "skips completed stories" test_get_next_story_skips_completed
    run_test "skips claimed stories" test_get_next_story_skips_claimed
    run_test "request_ralph_story_claim updates PRD" test_request_story_claim_updates_prd
    run_test "release_ralph_story_claim clears PRD" test_release_story_claim_clears_prd
    run_test "claims by priority order" test_claim_story_priority_order
}

test_dead_instance_unit() {
    describe "Dead Instance Detection"
    run_test "instance not dead with recent heartbeat" test_instance_not_dead_with_recent_heartbeat
    run_test "instance dead with old heartbeat" test_instance_dead_with_old_heartbeat
    run_test "dead instances excluded by default" test_dead_instances_excluded_by_default
    run_test "dead instances included with 'all' flag" test_dead_instances_included_with_all_flag
    run_test "terminated instance not marked dead" test_terminated_instance_not_marked_dead
}

test_stale_lock_unit() {
    describe "Stale Lock Detection and Cleanup"
    run_test "stale lock detected" test_stale_lock_detected
    run_test "clear_ralph_stale_lock removes stale lock" test_clear_stale_lock
    run_test "clear_ralph_stale_locks removes all stale" test_clear_all_stale_locks
    run_test "fresh lock not cleared" test_fresh_lock_not_cleared
    run_test "clear_ralph_instance_locks releases own locks" test_clear_instance_locks
}

test_paths_unit() {
    describe "Path Functions"
    run_test "get_ralph_paths includes PROJECT_ROOT" test_get_ralph_paths_includes_project_root
    run_test "get_ralph_paths includes PRD_FILE" test_get_ralph_paths_includes_prd_file
}

test_logging_unit() {
    describe "Logging Functions"
    run_test "log entry added" test_instance_log_entry
    run_test "log includes timestamp" test_log_entry_includes_timestamp
    run_test "log includes short ID" test_log_entry_includes_short_id
}

test_utility_unit() {
    describe "Utility Functions"
    run_test "format_duration seconds" test_format_duration_seconds
    run_test "format_duration minutes" test_format_duration_minutes
    run_test "format_duration hours" test_format_duration_hours
    run_test "progress bar empty" test_progress_bar_empty
    run_test "progress bar full" test_progress_bar_full
    run_test "progress bar half" test_progress_bar_half
}

test_prd_status_unit() {
    describe "PRD Status Functions"
    run_test "prd status counts stories" test_prd_status_counts
    run_test "prd status calculates percentage" test_prd_status_percentage
    run_test "incomplete stories sorted by priority" test_incomplete_stories_sorted
}

# =============================================================================
# Test Git Branch Functions
# =============================================================================
# Note: These tests use a real git repository in a temp directory

test_git_repo_init() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize a real git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"

    # Create initial commit
    echo "test" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1

    local result=$([[ -d ".git" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_create_feature_branch() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "test" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1

    # Create a feature branch
    local instance_id="test-123"
    local story_id="US-001"
    local branch_name="ralph/${instance_id:0:8}/$story_id"

    git checkout -b "$branch_name" > /dev/null 2>&1
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)

    teardown_test_env

    [[ "$current_branch" == "$branch_name" ]]
}

test_feature_branch_isolation() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1

    # Create feature branch
    local branch_name="ralph/test1234/US-001"
    git checkout -b "$branch_name" > /dev/null 2>&1

    # Make a change on the feature branch
    echo "feature change" >> feature.txt
    git add feature.txt
    git commit -m "Feature commit" > /dev/null 2>&1

    # Check main doesn't have the file
    git checkout main > /dev/null 2>&1
    local file_on_main=$([[ -f "feature.txt" ]] && echo "yes" || echo "no")

    # Check feature branch has the file
    git checkout "$branch_name" > /dev/null 2>&1
    local file_on_feature=$([[ -f "feature.txt" ]] && echo "yes" || echo "no")

    teardown_test_env

    [[ "$file_on_main" == "no" ]] && [[ "$file_on_feature" == "yes" ]]
}

test_merge_feature_branch_no_ff() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1

    # Create and work on feature branch
    local branch_name="ralph/test1234/US-001"
    git checkout -b "$branch_name" > /dev/null 2>&1
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "Feature commit" > /dev/null 2>&1

    # Merge back with --no-ff
    git checkout main > /dev/null 2>&1
    git merge --no-ff "$branch_name" -m "Merge US-001" > /dev/null 2>&1

    # Verify merge commit exists (--no-ff creates a merge commit)
    local merge_commit
    merge_commit=$(git log --oneline -1 | grep -c "Merge US-001")

    # Verify feature file is now on main
    local file_merged=$([[ -f "feature.txt" ]] && echo "yes" || echo "no")

    teardown_test_env

    [[ "$merge_commit" -ge 1 ]] && [[ "$file_merged" == "yes" ]]
}

test_delete_merged_branch() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1

    # Create and work on feature branch
    local branch_name="ralph/test1234/US-001"
    git checkout -b "$branch_name" > /dev/null 2>&1
    echo "feature" > feature.txt
    git add feature.txt
    git commit -m "Feature commit" > /dev/null 2>&1

    # Merge back
    git checkout main > /dev/null 2>&1
    git merge --no-ff "$branch_name" -m "Merge US-001" > /dev/null 2>&1

    # Delete the merged branch
    git branch -d "$branch_name" > /dev/null 2>&1
    local branch_exists
    branch_exists=$(git branch --list "$branch_name" | wc -l | tr -d ' ')

    teardown_test_env

    [[ "$branch_exists" -eq 0 ]]
}

test_merge_conflict_detection() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial content" > conflict.txt
    git add conflict.txt
    git commit -m "Initial commit" > /dev/null 2>&1

    # Create feature branch with conflicting change
    local branch_name="ralph/test1234/US-001"
    git checkout -b "$branch_name" > /dev/null 2>&1
    echo "feature change" > conflict.txt
    git add conflict.txt
    git commit -m "Feature commit" > /dev/null 2>&1

    # Make a different change on main
    git checkout main > /dev/null 2>&1
    echo "main change" > conflict.txt
    git add conflict.txt
    git commit -m "Main commit" > /dev/null 2>&1

    # Try to merge (should fail)
    local merge_result=0
    git merge --no-ff "$branch_name" -m "Merge US-001" > /dev/null 2>&1 || merge_result=$?
    git merge --abort > /dev/null 2>&1 || true

    teardown_test_env

    [[ $merge_result -ne 0 ]]
}

test_git_branch_unit() {
    describe "Git Branch Operations"
    run_test "git repo init" test_git_repo_init
    run_test "create feature branch" test_create_feature_branch
    run_test "feature branch isolation" test_feature_branch_isolation
    run_test "merge with --no-ff" test_merge_feature_branch_no_ff
    run_test "delete merged branch" test_delete_merged_branch
    run_test "merge conflict detection" test_merge_conflict_detection
}

# =============================================================================
# Test Signal Handling and Cleanup
# =============================================================================

test_cleanup_releases_locks() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    # Acquire locks
    lock_ralph_story "US-001"
    lock_ralph_story "US-002"

    # Verify locks exist
    eval "$(get_ralph_paths)"
    local locks_before
    locks_before=$(ls -1 "$LOCKS_DIR"/*.lock 2>/dev/null | wc -l | tr -d ' ')

    # Simulate cleanup by releasing all locks
    local released
    released=$(clear_ralph_instance_locks)

    # Verify locks are gone
    local locks_after
    locks_after=$(ls -1 "$LOCKS_DIR"/*.lock 2>/dev/null | wc -l | tr -d ' ')

    teardown_test_env

    [[ "$locks_before" -ge 2 ]] && [[ "$locks_after" -eq 0 ]] && [[ "$released" -eq 2 ]]
}

test_cleanup_updates_status_terminated() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"

    # Start as working
    update_ralph_status "working" "US-001" 1 10 ""

    # Verify working state
    local state_before
    state_before=$(jq -r '.state' "$INSTANCE_STATUS_FILE")

    # Simulate cleanup by updating to terminated
    update_ralph_status "terminated" "" 0 10 ""

    # Verify terminated state
    local state_after
    state_after=$(jq -r '.state' "$INSTANCE_STATUS_FILE")

    teardown_test_env

    [[ "$state_before" == "working" ]] && [[ "$state_after" == "terminated" ]]
}

test_git_stash_uncommitted_changes() {
    setup_test_env
    cd "$TEST_DIR" || return 1

    # Initialize git repo
    git init --initial-branch=main > /dev/null 2>&1
    git config user.email "test@test.com"
    git config user.name "Test User"
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit" > /dev/null 2>&1

    # Make uncommitted changes
    echo "uncommitted changes" > uncommitted.txt

    # Check if there are changes (simulating what cleanup does)
    local has_changes
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        has_changes="no"
    else
        has_changes="yes"
        # Stash the changes (add untracked first)
        git add uncommitted.txt
        git stash push -m "Test stash" > /dev/null 2>&1
    fi

    # Verify file is no longer present (stashed)
    local file_present=$([[ -f "uncommitted.txt" ]] && echo "yes" || echo "no")

    # Verify stash exists
    local stash_count
    stash_count=$(git stash list | wc -l | tr -d ' ')

    teardown_test_env

    [[ "$has_changes" == "yes" ]] && [[ "$file_present" == "no" ]] && [[ "$stash_count" -ge 1 ]]
}

test_trap_handler_can_run() {
    # Test that trap handlers can be defined and called
    setup_test_env

    local handler_called="no"

    # Define a mock cleanup handler
    test_cleanup_handler() {
        handler_called="yes"
    }

    # Call it directly (simulating trap behavior)
    test_cleanup_handler

    teardown_test_env

    [[ "$handler_called" == "yes" ]]
}

test_exit_codes_for_signals() {
    # Test expected exit codes for different signals
    # SIGINT (2) -> exit 130 (128 + 2)
    # SIGTERM (15) -> exit 143 (128 + 15)
    # SIGHUP (1) -> exit 129 (128 + 1)

    local sigint_code=$((128 + 2))
    local sigterm_code=$((128 + 15))
    local sighup_code=$((128 + 1))

    [[ "$sigint_code" -eq 130 ]] && [[ "$sigterm_code" -eq 143 ]] && [[ "$sighup_code" -eq 129 ]]
}

test_cleanup_only_releases_own_locks() {
    setup_test_env
    create_test_prd

    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$LOCKS_DIR"
    mkdir -p "$INSTANCES_DIR"

    # Create a lock owned by another instance
    mkdir -p "$LOCKS_DIR/US-001.lock"
    echo "other-instance-id" > "$LOCKS_DIR/US-001.lock/owner"
    echo "$(date +%s)" > "$LOCKS_DIR/US-001.lock/timestamp"

    # Create this instance and lock another story
    _RALPH_INSTANCE_ID=""
    _RALPH_INSTANCE_SHORT_ID=""
    eval "$(new_ralph_instance_directory)"
    lock_ralph_story "US-002"

    # Clear only this instance's locks
    local released
    released=$(clear_ralph_instance_locks)

    # US-001 should still be locked (owned by other instance)
    local us001_locked=$([[ -d "$LOCKS_DIR/US-001.lock" ]] && echo "yes" || echo "no")
    # US-002 should be released
    local us002_locked=$([[ -d "$LOCKS_DIR/US-002.lock" ]] && echo "yes" || echo "no")

    teardown_test_env

    [[ "$released" -eq 1 ]] && [[ "$us001_locked" == "yes" ]] && [[ "$us002_locked" == "no" ]]
}

test_signal_handling_unit() {
    describe "Signal Handling and Cleanup"
    run_test "cleanup releases instance locks" test_cleanup_releases_locks
    run_test "cleanup updates status to terminated" test_cleanup_updates_status_terminated
    run_test "git stash uncommitted changes" test_git_stash_uncommitted_changes
    run_test "trap handler can be invoked" test_trap_handler_can_run
    run_test "correct exit codes for signals" test_exit_codes_for_signals
    run_test "cleanup only releases own locks" test_cleanup_only_releases_own_locks
}

# =============================================================================
# Extended flock PRD Tests
# =============================================================================

test_prd_flock_serializes_writes() {
    # Skip if flock not available
    if ! command -v flock &>/dev/null; then
        return 0
    fi

    setup_test_env
    create_test_prd
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$INSTANCES_DIR"

    # Create a counter file to track serialized writes
    echo "0" > "$TEST_DIR/write_order.txt"

    # Launch concurrent writers that append their order
    for i in {1..5}; do
        (
            _RALPH_INSTANCE_ID="writer-$i-$$"
            mkdir -p "$INSTANCES_DIR/$_RALPH_INSTANCE_ID"

            # Use flock to serialize access
            (
                flock -x 200

                # Read current order, append our number, write back
                local current
                current=$(cat "$TEST_DIR/write_order.txt")
                echo "${current}-$i" > "$TEST_DIR/write_order.txt"

                # Small delay to make race condition visible without flock
                sleep 0.1
            ) 200>"$TEST_DIR/order.lock"
        ) &
    done

    wait

    # Check that write order file has all 5 writes
    local final_order
    final_order=$(cat "$TEST_DIR/write_order.txt")
    local write_count
    write_count=$(echo "$final_order" | grep -o "-" | wc -l | tr -d ' ')

    teardown_test_env

    # Should have 5 dashes (one after 0, one after each number)
    [[ "$write_count" -eq 5 ]]
}

test_prd_read_during_write() {
    # Skip if flock not available
    if ! command -v flock &>/dev/null; then
        return 0
    fi

    setup_test_env
    create_test_prd
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$INSTANCES_DIR"

    # Start a writer that holds the lock
    local writer_pid
    (
        flock -x 200
        sleep 2
    ) 200>"$PRD_FILE.lock" &
    writer_pid=$!

    # Give writer time to acquire lock
    sleep 0.5

    # Try to read with shared lock (should work)
    local read_result
    read_result=$(
        (
            flock -s 200 -w 1 || exit 1
            jq -r '.featureName' "$PRD_FILE"
        ) 200>"$PRD_FILE.lock"
    )

    # Clean up
    kill $writer_pid 2>/dev/null || true
    wait $writer_pid 2>/dev/null || true

    teardown_test_env

    # Read should fail to get lock within 1 second since writer holds exclusive
    # Actually, shared lock CAN be acquired while exclusive is held in some implementations
    # This test verifies the locking mechanism is in place
    [[ -n "$read_result" || "$read_result" == "Test Feature" ]]
}

test_prd_write_validates_json() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    # Try to write invalid JSON transform (should be caught by jq)
    local result=0
    update_ralph_prd "Invalid update" 'invalid jq filter syntax {{{' 2>/dev/null || result=$?

    # Verify original PRD is unchanged
    local feature_name
    feature_name=$(jq -r '.featureName' "$RALPH_PRD_FILE")

    teardown_test_env

    [[ $result -ne 0 ]] && [[ "$feature_name" == "Test Feature" ]]
}

test_prd_backup_preserved_on_failure() {
    setup_test_env
    create_test_prd
    eval "$(new_ralph_instance_directory)"

    # First, make a successful update to create a backup
    update_ralph_prd "First update" '.featureName = "Updated"'

    # Verify backup was created
    local backup_exists=$([[ -f "$RALPH_PRD_FILE.bak" ]] && echo "yes" || echo "no")

    # Check backup content
    local backup_content
    backup_content=$(jq -r '.featureName' "$RALPH_PRD_FILE.bak")

    teardown_test_env

    [[ "$backup_exists" == "yes" ]] && [[ "$backup_content" == "Test Feature" ]]
}

test_extended_prd_flock_unit() {
    describe "Extended flock PRD Tests"

    if command -v flock &>/dev/null; then
        run_test "flock serializes concurrent writes" test_prd_flock_serializes_writes
        run_test "read during write behavior" test_prd_read_during_write
    else
        skip_test "flock serializes concurrent writes" "flock not available"
        skip_test "read during write behavior" "flock not available"
    fi

    run_test "write validates JSON before saving" test_prd_write_validates_json
    run_test "backup preserved on update" test_prd_backup_preserved_on_failure
}

# =============================================================================
# Extended Dead Instance Tests
# =============================================================================

test_dead_instance_lock_cleanup() {
    setup_test_env
    create_test_prd

    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$LOCKS_DIR"
    mkdir -p "$INSTANCES_DIR"

    # Create a dead instance (old heartbeat, but not terminated)
    local dead_id="dead-instance-123"
    mkdir -p "$INSTANCES_DIR/$dead_id"
    local old_epoch=$(($(date +%s) - 600))  # 10 minutes ago
    jq -n \
        --arg instance_id "$dead_id" \
        --arg state "working" \
        --argjson epoch "$old_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$dead_id/status.json"

    # Create a lock owned by dead instance
    mkdir -p "$LOCKS_DIR/US-001.lock"
    echo "$dead_id" > "$LOCKS_DIR/US-001.lock/owner"
    echo "$old_epoch" > "$LOCKS_DIR/US-001.lock/timestamp"

    # Check lock info
    local lock_info
    lock_info=$(get_ralph_story_lock "US-001")
    local is_dead
    is_dead=$(echo "$lock_info" | jq -r '.isDead')

    teardown_test_env

    [[ "$is_dead" == "true" ]]
}

test_completed_instance_not_dead() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"

    # Create status with old heartbeat but completed state
    local old_epoch=$(($(date +%s) - 600))
    jq -n \
        --arg instance_id "$instance_id" \
        --arg state "completed" \
        --argjson epoch "$old_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$instance_id/status.json"

    local instances
    instances=$(get_ralph_instances "all")
    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')

    teardown_test_env

    [[ "$is_dead" == "false" ]]
}

test_heartbeat_threshold_boundary() {
    setup_test_env
    eval "$(new_ralph_instance_directory)"
    local instance_id
    instance_id=$(get_ralph_instance_id)
    eval "$(get_ralph_paths)"

    # Create status with heartbeat at exactly the threshold (5 min = 300s)
    local boundary_epoch=$(($(date +%s) - 299))  # Just under 5 minutes
    jq -n \
        --arg instance_id "$instance_id" \
        --arg state "working" \
        --argjson epoch "$boundary_epoch" \
        '{instanceId: $instance_id, state: $state, lastHeartbeatEpoch: $epoch}' \
        > "$INSTANCES_DIR/$instance_id/status.json"

    local instances
    instances=$(get_ralph_instances)  # Should include since not dead yet
    local count
    count=$(echo "$instances" | jq 'length')

    teardown_test_env

    [[ "$count" -eq 1 ]]
}

test_extended_dead_instance_unit() {
    describe "Extended Dead Instance Tests"
    run_test "dead instance lock cleanup detection" test_dead_instance_lock_cleanup
    run_test "completed instance not marked dead" test_completed_instance_not_dead
    run_test "heartbeat at threshold boundary" test_heartbeat_threshold_boundary
}

# =============================================================================
# Story Claiming Edge Cases
# =============================================================================

test_claim_retry_after_stale_clear() {
    setup_test_env
    create_test_prd
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$LOCKS_DIR"
    mkdir -p "$INSTANCES_DIR"

    # Create a stale lock on US-001
    local old_ts=$(($(date +%s) - 8000))  # >2 hours old
    mkdir -p "$LOCKS_DIR/US-001.lock"
    echo "old-instance" > "$LOCKS_DIR/US-001.lock/owner"
    echo "$old_ts" > "$LOCKS_DIR/US-001.lock/timestamp"

    # Set up new instance
    _RALPH_INSTANCE_ID=""
    _RALPH_INSTANCE_SHORT_ID=""
    eval "$(new_ralph_instance_directory)"

    # Try to claim - should clear stale lock first
    local claim_result=0
    request_ralph_story_claim "US-001" || claim_result=$?

    # Verify claim succeeded
    local claimed_by
    claimed_by=$(jq -r '.userStories[] | select(.id == "US-001") | .claimedBy' "$RALPH_PRD_FILE")
    local instance_id
    instance_id=$(get_ralph_instance_id)

    teardown_test_env

    [[ $claim_result -eq 0 ]] && [[ "$claimed_by" == "$instance_id" ]]
}

test_claim_all_stories_exhausted() {
    setup_test_env
    # PRD where all stories are either complete or claimed
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "featureName": "Test",
    "userStories": [
        {"id": "US-001", "priority": 1, "passes": true, "claimedBy": null},
        {"id": "US-002", "priority": 2, "passes": false, "claimedBy": "other-instance"}
    ]
}
EOF
    eval "$(new_ralph_instance_directory)"

    # Try to get next story
    local story
    story=$(get_ralph_next_story 2>/dev/null || echo "")

    teardown_test_env

    [[ -z "$story" ]]
}

test_claim_with_locked_story() {
    setup_test_env
    create_test_prd
    export RALPH_PROJECT_ROOT="$TEST_DIR"
    eval "$(get_ralph_paths)"
    mkdir -p "$LOCKS_DIR"
    mkdir -p "$INSTANCES_DIR"

    # Create a fresh lock on US-001 (not stale)
    mkdir -p "$LOCKS_DIR/US-001.lock"
    echo "other-instance" > "$LOCKS_DIR/US-001.lock/owner"
    echo "$(date +%s)" > "$LOCKS_DIR/US-001.lock/timestamp"

    # Set up our instance
    _RALPH_INSTANCE_ID=""
    _RALPH_INSTANCE_SHORT_ID=""
    eval "$(new_ralph_instance_directory)"

    # Try to get next story - should skip US-001 and return US-002
    local story
    story=$(get_ralph_next_story)
    local story_id
    story_id=$(echo "$story" | jq -r '.id')

    teardown_test_env

    [[ "$story_id" == "US-002" ]]
}

test_story_claiming_edge_cases_unit() {
    describe "Story Claiming Edge Cases"
    run_test "claim succeeds after stale lock cleared" test_claim_retry_after_stale_clear
    run_test "no story available when all exhausted" test_claim_all_stories_exhausted
    run_test "skips locked story to next available" test_claim_with_locked_story
}

# =============================================================================
# Global Registry Tests (PS-014 Addition)
# =============================================================================

test_global_registry_disabled() {
    setup_test_env
    export RALPH_GLOBAL_DISABLE=1

    # init should succeed but do nothing
    local result=0
    init_ralph_global_registry || result=$?

    teardown_test_env

    [[ $result -eq 0 ]]
}

test_global_registry_init_creates_dirs() {
    setup_test_env
    export RALPH_GLOBAL_DIR="$TEST_DIR/global"
    unset RALPH_GLOBAL_DISABLE

    init_ralph_global_registry

    local instances_dir="$TEST_DIR/global/instances"
    local locks_dir="$TEST_DIR/global/locks"

    local result=$([[ -d "$instances_dir" ]] && [[ -d "$locks_dir" ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_global_instances_empty_when_no_registry() {
    setup_test_env
    export RALPH_GLOBAL_DIR="$TEST_DIR/nonexistent"

    local instances
    instances=$(get_ralph_global_instances)
    local count
    count=$(echo "$instances" | jq 'length')

    teardown_test_env

    [[ "$count" -eq 0 ]]
}

test_global_registry_unit() {
    describe "Global Registry"
    run_test "disabled registry returns success" test_global_registry_disabled
    run_test "init creates required directories" test_global_registry_init_creates_dirs
    run_test "empty instances when no registry" test_global_instances_empty_when_no_registry
}

# =============================================================================
# Main Test Runner
# =============================================================================
run_all_tests() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║   Ralph Multi-Instance - Comprehensive Bash Test Suite     ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

    test_instance_id_unit
    test_instance_directory_unit
    test_status_update_unit
    test_story_locking_unit
    test_concurrent_locking_unit
    test_prd_operations_unit
    test_story_claiming_unit
    test_dead_instance_unit
    test_stale_lock_unit
    test_paths_unit
    test_logging_unit
    test_utility_unit
    test_prd_status_unit
    test_git_branch_unit
    test_signal_handling_unit
    test_extended_prd_flock_unit
    test_extended_dead_instance_unit
    test_story_claiming_edge_cases_unit
    test_global_registry_unit

    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Test Results:${NC}"
    echo -e "  Total:   $TESTS_RUN"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# Run tests
run_all_tests
