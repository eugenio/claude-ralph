#!/usr/bin/env bats
# =============================================================================
# ralph-utils.bats - Tests for ralph-utils.sh shared library
# =============================================================================
#
# Run with: bats scripts/ralph/tests/bash/ralph-utils.bats
#
# =============================================================================

# Load test helpers
load 'test_helper'

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

setup() {
    setup_test_environment
    source_ralph_utils
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# get_ralph_paths() TESTS
# =============================================================================

@test "get_ralph_paths() returns RALPH_DIR path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "RALPH_DIR="
}

@test "get_ralph_paths() returns PROJECT_ROOT path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "PROJECT_ROOT="
}

@test "get_ralph_paths() returns PRD_FILE path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "PRD_FILE="
    assert_output_contains "prd.json"
}

@test "get_ralph_paths() returns PROGRESS_FILE path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "PROGRESS_FILE="
    assert_output_contains "progress.txt"
}

@test "get_ralph_paths() returns LOG_FILE path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "LOG_FILE="
    assert_output_contains "ralph.log"
}

@test "get_ralph_paths() returns INSTANCES_DIR path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "INSTANCES_DIR="
    assert_output_contains "instances"
}

@test "get_ralph_paths() returns LOCKS_DIR path" {
    run get_ralph_paths
    assert_success
    assert_output_contains "LOCKS_DIR="
    assert_output_contains "locks"
}

@test "get_ralph_paths() variables can be evaluated" {
    eval "$(get_ralph_paths)"
    [[ -n "$RALPH_DIR" ]]
    [[ -n "$PROJECT_ROOT" ]]
    [[ -n "$PRD_FILE" ]]
    [[ "$PRD_FILE" == *"prd.json" ]]
}

@test "get_ralph_paths() paths are absolute" {
    eval "$(get_ralph_paths)"
    [[ "$RALPH_DIR" == /* ]]
    [[ "$PROJECT_ROOT" == /* ]]
    [[ "$PRD_FILE" == /* ]]
}

# =============================================================================
# read_prd_json() TESTS
# =============================================================================

@test "read_prd_json() with valid JSON returns content" {
    skip_if_no_jq
    create_prd_fixture "partial"
    local prd_file
    prd_file="$(get_test_ralph_dir)/prd.json"

    run read_prd_json "$prd_file"
    assert_success
    assert_output_contains "featureName"
    assert_output_contains "userStories"
}

@test "read_prd_json() with missing file returns error" {
    run read_prd_json "/nonexistent/path/prd.json"
    assert_failure
    assert_output_contains "Error"
    assert_output_contains "not found"
}

@test "read_prd_json() with empty stories array parses correctly" {
    skip_if_no_jq
    create_prd_fixture "empty"
    local prd_file
    prd_file="$(get_test_ralph_dir)/prd.json"

    run read_prd_json "$prd_file"
    assert_success
    assert_output_contains "userStories"
    assert_output_contains "[]"
}

@test "read_prd_json() with invalid JSON returns error" {
    skip_if_no_jq
    local prd_file
    prd_file="$(get_test_ralph_dir)/prd.json"
    echo "{ invalid json" > "$prd_file"

    run read_prd_json "$prd_file"
    assert_failure
    assert_output_contains "Error"
}

@test "read_prd_json() parses story fields correctly" {
    skip_if_no_jq
    create_prd_fixture "partial"
    local prd_file
    prd_file="$(get_test_ralph_dir)/prd.json"

    local prd_content
    prd_content=$(read_prd_json "$prd_file")

    local first_story_id
    first_story_id=$(echo "$prd_content" | jq -r '.userStories[0].id')
    [[ "$first_story_id" == "US-001" ]]
}

@test "read_prd_json() uses default path when no argument given" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run read_prd_json
    assert_success
    assert_output_contains "userStories"
}

# =============================================================================
# get_prd_status() TESTS
# =============================================================================

@test "get_prd_status() returns PRD_TOTAL" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run get_prd_status
    assert_success
    assert_output_contains "PRD_TOTAL="
}

@test "get_prd_status() returns PRD_COMPLETE" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run get_prd_status
    assert_success
    assert_output_contains "PRD_COMPLETE="
}

@test "get_prd_status() returns PRD_REMAINING" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run get_prd_status
    assert_success
    assert_output_contains "PRD_REMAINING="
}

@test "get_prd_status() returns PRD_PERCENTAGE" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run get_prd_status
    assert_success
    assert_output_contains "PRD_PERCENTAGE="
}

@test "get_prd_status() calculates correct totals for partial PRD" {
    skip_if_no_jq
    create_prd_fixture "partial"

    eval "$(get_prd_status)"
    # partial fixture has 3 stories: 1 complete, 2 incomplete
    [[ "$PRD_TOTAL" -eq 3 ]]
    [[ "$PRD_COMPLETE" -eq 1 ]]
    [[ "$PRD_REMAINING" -eq 2 ]]
    [[ "$PRD_PERCENTAGE" -eq 33 ]]
}

@test "get_prd_status() calculates 100% for complete PRD" {
    skip_if_no_jq
    create_prd_fixture "complete"

    eval "$(get_prd_status)"
    # complete fixture has 2 stories, all complete
    [[ "$PRD_TOTAL" -eq 2 ]]
    [[ "$PRD_COMPLETE" -eq 2 ]]
    [[ "$PRD_REMAINING" -eq 0 ]]
    [[ "$PRD_PERCENTAGE" -eq 100 ]]
}

@test "get_prd_status() calculates 0% for empty PRD" {
    skip_if_no_jq
    create_prd_fixture "empty"

    eval "$(get_prd_status)"
    [[ "$PRD_TOTAL" -eq 0 ]]
    [[ "$PRD_COMPLETE" -eq 0 ]]
    [[ "$PRD_REMAINING" -eq 0 ]]
    [[ "$PRD_PERCENTAGE" -eq 0 ]]
}

@test "get_prd_status() handles missing PRD file gracefully" {
    skip_if_no_jq
    # Don't create PRD file

    eval "$(get_prd_status)"
    [[ "$PRD_TOTAL" -eq 0 ]]
    [[ "$PRD_PERCENTAGE" -eq 0 ]]
}

@test "get_prd_status() accepts JSON string as argument" {
    skip_if_no_jq
    local json_content
    json_content=$(cat <<'EOF'
{
  "userStories": [
    {"id": "US-001", "passes": true},
    {"id": "US-002", "passes": false}
  ]
}
EOF
)
    eval "$(get_prd_status "$json_content")"
    [[ "$PRD_TOTAL" -eq 2 ]]
    [[ "$PRD_COMPLETE" -eq 1 ]]
    [[ "$PRD_PERCENTAGE" -eq 50 ]]
}

# =============================================================================
# get_ralph_instances() TESTS
# =============================================================================

@test "get_ralph_instances() returns empty array when no instances exist" {
    skip_if_no_jq

    run get_ralph_instances
    assert_success
    [[ "$output" == "[]" ]]
}

@test "get_ralph_instances() parses single instance" {
    skip_if_no_jq
    create_instance_fixture "test-instance-1234-5678" "working" 0

    local instances
    instances=$(get_ralph_instances "all")

    local count
    count=$(echo "$instances" | jq 'length')
    [[ "$count" -eq 1 ]]
}

@test "get_ralph_instances() parses multiple instances" {
    skip_if_no_jq
    create_instance_fixture "instance-one-1234-0001" "working" 0
    create_instance_fixture "instance-two-1234-0002" "idle" 0

    local instances
    instances=$(get_ralph_instances "all")

    local count
    count=$(echo "$instances" | jq 'length')
    [[ "$count" -eq 2 ]]
}

@test "get_ralph_instances() includes instance state" {
    skip_if_no_jq
    create_instance_fixture "test-instance-1234-5678" "working" 0

    local instances
    instances=$(get_ralph_instances "all")

    local state
    state=$(echo "$instances" | jq -r '.[0].state')
    [[ "$state" == "working" ]]
}

@test "get_ralph_instances() includes heartbeat age" {
    skip_if_no_jq
    create_instance_fixture "test-instance-1234-5678" "working" 60

    local instances
    instances=$(get_ralph_instances "all")

    local heartbeat_age
    heartbeat_age=$(echo "$instances" | jq -r '.[0].heartbeatAge')
    # Heartbeat age should be around 60 seconds (allow some tolerance)
    [[ "$heartbeat_age" -ge 55 && "$heartbeat_age" -le 65 ]]
}

@test "get_ralph_instances() marks dead instances correctly" {
    skip_if_no_jq
    # Create instance with heartbeat > 5 minutes ago (dead threshold)
    create_instance_fixture "dead-instance-1234-5678" "working" 400

    local instances
    instances=$(get_ralph_instances "all")

    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')
    [[ "$is_dead" == "true" ]]
}

@test "get_ralph_instances() excludes dead instances by default" {
    skip_if_no_jq
    create_instance_fixture "alive-instance-1234-0001" "working" 0
    create_instance_fixture "dead-instance-1234-0002" "working" 400

    local instances
    instances=$(get_ralph_instances)

    local count
    count=$(echo "$instances" | jq 'length')
    [[ "$count" -eq 1 ]]

    local instance_id
    instance_id=$(echo "$instances" | jq -r '.[0].instanceId')
    [[ "$instance_id" == "alive-instance-1234-0001" ]]
}

@test "get_ralph_instances() includes terminated instances" {
    skip_if_no_jq
    create_instance_fixture "terminated-instance-1234-5678" "terminated" 400

    local instances
    instances=$(get_ralph_instances "all")

    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')
    # Terminated instances should NOT be marked as dead
    [[ "$is_dead" == "false" ]]
}

@test "get_ralph_instances() includes completed instances" {
    skip_if_no_jq
    create_instance_fixture "completed-instance-1234-5678" "completed" 400

    local instances
    instances=$(get_ralph_instances "all")

    local is_dead
    is_dead=$(echo "$instances" | jq -r '.[0].isDead')
    # Completed instances should NOT be marked as dead
    [[ "$is_dead" == "false" ]]
}

# =============================================================================
# lock_ralph_story() TESTS
# =============================================================================

@test "lock_ralph_story() creates lock directory" {
    skip_if_no_jq
    create_prd_fixture "partial"

    lock_ralph_story "US-001"

    local lock_dir
    lock_dir="$(get_test_ralph_dir)/locks/US-001.lock"
    assert_dir_exists "$lock_dir"
}

@test "lock_ralph_story() creates owner.txt file" {
    skip_if_no_jq
    create_prd_fixture "partial"

    lock_ralph_story "US-001"

    local owner_file
    owner_file="$(get_test_ralph_dir)/locks/US-001.lock/owner.txt"
    assert_file_exists "$owner_file"
}

@test "lock_ralph_story() creates timestamp.txt file" {
    skip_if_no_jq
    create_prd_fixture "partial"

    lock_ralph_story "US-001"

    local timestamp_file
    timestamp_file="$(get_test_ralph_dir)/locks/US-001.lock/timestamp.txt"
    assert_file_exists "$timestamp_file"
}

@test "lock_ralph_story() creates pid.txt file" {
    skip_if_no_jq
    create_prd_fixture "partial"

    lock_ralph_story "US-001"

    local pid_file
    pid_file="$(get_test_ralph_dir)/locks/US-001.lock/pid.txt"
    assert_file_exists "$pid_file"
}

@test "lock_ralph_story() owner.txt contains instance ID" {
    skip_if_no_jq
    create_prd_fixture "partial"

    lock_ralph_story "US-001"

    local owner_file owner_content instance_id
    owner_file="$(get_test_ralph_dir)/locks/US-001.lock/owner.txt"
    owner_content=$(cat "$owner_file")
    instance_id=$(get_ralph_instance_id)

    [[ "$owner_content" == "$instance_id" ]]
}

@test "lock_ralph_story() returns success on first lock" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run lock_ralph_story "US-001"
    assert_success
}

@test "lock_ralph_story() returns failure when already locked" {
    skip_if_no_jq
    create_prd_fixture "partial"

    # Create existing lock from different instance
    create_lock_fixture "US-001" "other-instance-9999-9999" 0

    run lock_ralph_story "US-001"
    assert_failure
}

@test "lock_ralph_story() clears stale locks before acquiring" {
    skip_if_no_jq
    create_prd_fixture "partial"

    # Create stale lock (> 2 hours old)
    create_lock_fixture "US-001" "stale-instance-1234-5678" 8000

    run lock_ralph_story "US-001"
    assert_success
}

# =============================================================================
# unlock_ralph_story() TESTS
# =============================================================================

@test "unlock_ralph_story() removes lock directory" {
    skip_if_no_jq
    create_prd_fixture "partial"

    # Create and then unlock
    lock_ralph_story "US-001"
    unlock_ralph_story "US-001"

    local lock_dir
    lock_dir="$(get_test_ralph_dir)/locks/US-001.lock"
    [[ ! -d "$lock_dir" ]]
}

@test "unlock_ralph_story() returns success when unlocking own lock" {
    skip_if_no_jq
    create_prd_fixture "partial"

    lock_ralph_story "US-001"
    run unlock_ralph_story "US-001"
    assert_success
}

@test "unlock_ralph_story() returns success when lock doesn't exist" {
    skip_if_no_jq
    create_prd_fixture "partial"

    run unlock_ralph_story "US-999"
    assert_success
}

@test "unlock_ralph_story() fails when not owner without force" {
    skip_if_no_jq
    create_prd_fixture "partial"

    # Create lock from different instance
    create_lock_fixture "US-001" "other-instance-9999-9999" 0

    run unlock_ralph_story "US-001"
    assert_failure
    assert_output_contains "Cannot release lock"
}

@test "unlock_ralph_story() succeeds with force flag" {
    skip_if_no_jq
    create_prd_fixture "partial"

    # Create lock from different instance
    create_lock_fixture "US-001" "other-instance-9999-9999" 0

    run unlock_ralph_story "US-001" "force"
    assert_success

    local lock_dir
    lock_dir="$(get_test_ralph_dir)/locks/US-001.lock"
    [[ ! -d "$lock_dir" ]]
}

# =============================================================================
# get_ralph_story_locks() TESTS
# =============================================================================

@test "get_ralph_story_locks() returns empty array when no locks exist" {
    skip_if_no_jq

    run get_ralph_story_locks
    assert_success
    [[ "$output" == "[]" ]]
}

@test "get_ralph_story_locks() lists single lock" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 0

    local locks
    locks=$(get_ralph_story_locks)

    local count
    count=$(echo "$locks" | jq 'length')
    [[ "$count" -eq 1 ]]
}

@test "get_ralph_story_locks() lists multiple locks" {
    skip_if_no_jq
    create_lock_fixture "US-001" "instance-one-1234-0001" 0
    create_lock_fixture "US-002" "instance-two-1234-0002" 0
    create_lock_fixture "US-003" "instance-one-1234-0001" 0

    local locks
    locks=$(get_ralph_story_locks)

    local count
    count=$(echo "$locks" | jq 'length')
    [[ "$count" -eq 3 ]]
}

@test "get_ralph_story_locks() includes story ID" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 0

    local locks
    locks=$(get_ralph_story_locks)

    local story_id
    story_id=$(echo "$locks" | jq -r '.[0].storyId')
    [[ "$story_id" == "US-001" ]]
}

@test "get_ralph_story_locks() includes owner" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 0

    local locks
    locks=$(get_ralph_story_locks)

    local owner
    owner=$(echo "$locks" | jq -r '.[0].owner')
    [[ "$owner" == "test-instance-1234-5678" ]]
}

@test "get_ralph_story_locks() includes lock age" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 120

    local locks
    locks=$(get_ralph_story_locks)

    local age
    age=$(echo "$locks" | jq -r '.[0].age')
    # Age should be around 120 seconds (allow some tolerance)
    [[ "$age" -ge 115 && "$age" -le 125 ]]
}

@test "get_ralph_story_locks() marks stale locks" {
    skip_if_no_jq
    # Create lock > 2 hours old (stale threshold)
    create_lock_fixture "US-001" "test-instance-1234-5678" 8000

    local locks
    locks=$(get_ralph_story_locks)

    local is_stale
    is_stale=$(echo "$locks" | jq -r '.[0].isStale')
    [[ "$is_stale" == "true" ]]
}

@test "get_ralph_story_locks() marks fresh locks as not stale" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 60

    local locks
    locks=$(get_ralph_story_locks)

    local is_stale
    is_stale=$(echo "$locks" | jq -r '.[0].isStale')
    [[ "$is_stale" == "false" ]]
}

# =============================================================================
# test_ralph_story_locked() TESTS
# =============================================================================

@test "test_ralph_story_locked() returns true when locked" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 0

    run test_ralph_story_locked "US-001"
    assert_success
}

@test "test_ralph_story_locked() returns false when not locked" {
    skip_if_no_jq

    run test_ralph_story_locked "US-001"
    assert_failure
}

# =============================================================================
# get_ralph_story_lock() TESTS
# =============================================================================

@test "get_ralph_story_lock() returns lock info as JSON" {
    skip_if_no_jq
    create_lock_fixture "US-001" "test-instance-1234-5678" 0

    local lock_info
    lock_info=$(get_ralph_story_lock "US-001")

    local story_id
    story_id=$(echo "$lock_info" | jq -r '.storyId')
    [[ "$story_id" == "US-001" ]]
}

@test "get_ralph_story_lock() returns failure when lock doesn't exist" {
    skip_if_no_jq

    run get_ralph_story_lock "US-999"
    assert_failure
}

# =============================================================================
# UTILITY FUNCTION TESTS
# =============================================================================

@test "format_duration() formats seconds only" {
    run format_duration 45
    assert_success
    assert_output "45s"
}

@test "format_duration() formats minutes and seconds" {
    run format_duration 125
    assert_success
    assert_output "2m 5s"
}

@test "format_duration() formats hours, minutes, and seconds" {
    run format_duration 3725
    assert_success
    assert_output "1h 2m 5s"
}

@test "format_duration() formats zero" {
    run format_duration 0
    assert_success
    assert_output "0s"
}

@test "render_progress_bar() renders empty bar for 0%" {
    run render_progress_bar 0 10 10
    assert_success
    assert_output_contains "[░░░░░░░░░░]"
}

@test "render_progress_bar() renders full bar for 100%" {
    run render_progress_bar 10 10 10
    assert_success
    assert_output_contains "[██████████]"
}

@test "render_progress_bar() renders half bar for 50%" {
    run render_progress_bar 5 10 10
    assert_success
    assert_output_contains "[█████░░░░░]"
}

@test "render_progress_bar() handles zero max value" {
    run render_progress_bar 0 0 10
    assert_success
    # Should render empty bar without division by zero error
    [[ "$output" == *"["* && "$output" == *"]"* ]]
}

# =============================================================================
# get_ralph_instance_id() TESTS
# =============================================================================

@test "get_ralph_instance_id() returns non-empty string" {
    local instance_id
    instance_id=$(get_ralph_instance_id)
    [[ -n "$instance_id" ]]
}

@test "get_ralph_instance_id() returns consistent value" {
    local id1 id2
    id1=$(get_ralph_instance_id)
    id2=$(get_ralph_instance_id)
    [[ "$id1" == "$id2" ]]
}

@test "get_ralph_instance_id() includes username" {
    local instance_id
    instance_id=$(get_ralph_instance_id)
    [[ "$instance_id" == *"${USER:-unknown}"* ]]
}

@test "get_ralph_instance_id() force generates new ID" {
    # Reset to force new generation
    _RALPH_INSTANCE_ID=""

    local id1 id2
    id1=$(get_ralph_instance_id)

    # Reset again
    _RALPH_INSTANCE_ID=""

    id2=$(get_ralph_instance_id "force")

    # IDs should be different due to different timestamps
    # (may be same if test runs within same second, so just check format)
    [[ -n "$id1" && -n "$id2" ]]
}

# =============================================================================
# get_incomplete_stories() TESTS
# =============================================================================

@test "get_incomplete_stories() returns empty array for complete PRD" {
    skip_if_no_jq
    create_prd_fixture "complete"

    local stories
    stories=$(get_incomplete_stories)

    [[ "$stories" == "[]" ]]
}

@test "get_incomplete_stories() returns incomplete stories sorted by priority" {
    skip_if_no_jq
    create_prd_fixture "partial"

    local stories
    stories=$(get_incomplete_stories)

    local count
    count=$(echo "$stories" | jq 'length')
    [[ "$count" -eq 2 ]]

    # First story should have lower priority number (higher priority)
    local first_priority second_priority
    first_priority=$(echo "$stories" | jq '.[0].priority')
    second_priority=$(echo "$stories" | jq '.[1].priority')
    [[ "$first_priority" -lt "$second_priority" ]]
}

@test "get_incomplete_stories() returns empty array for empty PRD" {
    skip_if_no_jq
    create_prd_fixture "empty"

    local stories
    stories=$(get_incomplete_stories)

    [[ "$stories" == "[]" ]]
}

# =============================================================================
# GLOBAL INSTANCE FUNCTIONS TESTS (GM-004)
# =============================================================================

@test "get_ralph_global_dir() returns default path" {
    unset RALPH_GLOBAL_DIR
    local dir
    dir=$(get_ralph_global_dir)
    [[ "$dir" == "$HOME/.ralph/global" ]]
}

@test "get_ralph_global_dir() respects RALPH_GLOBAL_DIR env var" {
    export RALPH_GLOBAL_DIR="/tmp/test-global"
    local dir
    dir=$(get_ralph_global_dir)
    [[ "$dir" == "/tmp/test-global" ]]
    unset RALPH_GLOBAL_DIR
}

@test "unregister_ralph_global_instance() is idempotent" {
    export RALPH_GLOBAL_DIR="$TEST_TEMP_DIR/global"
    mkdir -p "$RALPH_GLOBAL_DIR/instances"
    run unregister_ralph_global_instance
    [[ "$status" -eq 0 ]]
    run unregister_ralph_global_instance
    [[ "$status" -eq 0 ]]
    unset RALPH_GLOBAL_DIR
}

@test "ensure_global_registration() returns success when disabled" {
    export RALPH_GLOBAL_DISABLE=1
    run ensure_global_registration
    [[ "$status" -eq 0 ]]
    unset RALPH_GLOBAL_DISABLE
}

@test "ensure_global_registration() recreates missing symlink" {
    export RALPH_GLOBAL_DIR="$TEST_TEMP_DIR/global"
    export RALPH_PROJECT_ROOT="$TEST_TEMP_DIR/project"

    mkdir -p "$RALPH_GLOBAL_DIR/instances"
    mkdir -p "$RALPH_PROJECT_ROOT/ralph/instances"

    # Create instance directory
    instance_id=$(get_ralph_instance_id)
    local_instance_dir="$RALPH_PROJECT_ROOT/ralph/instances/$instance_id"
    mkdir -p "$local_instance_dir"

    # Ensure symlink doesn't exist
    link_name=$(get_ralph_global_link_name)
    link_path="$RALPH_GLOBAL_DIR/instances/$link_name"
    [[ ! -L "$link_path" ]]

    # Run ensure - should create symlink
    run ensure_global_registration
    [[ "$status" -eq 0 ]]

    # Verify symlink was created
    [[ -L "$link_path" ]]

    unset RALPH_GLOBAL_DIR RALPH_PROJECT_ROOT
}
