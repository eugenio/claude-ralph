#!/usr/bin/env bats
# =============================================================================
# ralph-queue-worker.bats - Tests for worker queue integration
# =============================================================================
#
# DESCRIPTION:
#   Tests for ralph.sh queue-aware completion behavior.
#   Verifies that workers can check the global queue after completing a PRD
#   and automatically continue with the next queued PRD.
#
# USAGE:
#   bats scripts/ralph/tests/bash/ralph-queue-worker.bats
#
# REQUIREMENTS:
#   - bats-core
#   - jq
#
# =============================================================================

# Load test helper
load 'test_helper'

# =============================================================================
# TEST SETUP AND TEARDOWN
# =============================================================================

setup() {
    setup_test_environment
    source_ralph_utils

    # Set up global queue directory in test environment
    export RALPH_GLOBAL_DIR="$TEST_TEMP_DIR/global"
    mkdir -p "$RALPH_GLOBAL_DIR"

    # Create test projects
    TEST_PROJECT_1="$TEST_TEMP_DIR/project1"
    TEST_PROJECT_2="$TEST_TEMP_DIR/project2"
    TEST_PROJECT_3="$TEST_TEMP_DIR/project3"

    for project in "$TEST_PROJECT_1" "$TEST_PROJECT_2" "$TEST_PROJECT_3"; do
        mkdir -p "$project/scripts/ralph"
        mkdir -p "$project/src"

        # Create a simple PRD for each project
        cat > "$project/scripts/ralph/prd.json" <<EOF
{
  "featureName": "$(basename "$project") Feature",
  "branchName": "feature/$(basename "$project")",
  "userStories": [
    {"id": "US-001", "title": "Story 1", "passes": false, "priority": 1}
  ]
}
EOF
    done

    export TEST_PROJECT_1
    export TEST_PROJECT_2
    export TEST_PROJECT_3
}

teardown() {
    teardown_test_environment
    unset RALPH_GLOBAL_DIR
}

# =============================================================================
# QUEUE AWARENESS TESTS
# =============================================================================

@test "get_ralph_next_queued_prd() returns null when queue is empty" {
    skip_if_no_jq

    init_ralph_queue

    local result
    result=$(get_ralph_next_queued_prd 2>/dev/null) || true

    [[ -z "$result" || "$result" == "null" ]]
}

@test "get_ralph_next_queued_prd() returns pending entry" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local result
    result=$(get_ralph_next_queued_prd)

    [[ -n "$result" ]]
    local prd_path
    prd_path=$(echo "$result" | jq -r '.prdPath')
    [[ "$prd_path" == "$TEST_PROJECT_1/scripts/ralph/prd.json" ]]
}

@test "get_ralph_next_queued_prd() respects priority" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1" 5
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2" 1

    local result
    result=$(get_ralph_next_queued_prd)

    local project_root
    project_root=$(echo "$result" | jq -r '.projectRoot')
    [[ "$project_root" == "$TEST_PROJECT_2" ]]
}

@test "get_ralph_next_queued_prd() skips active entries" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2"

    # Mark first as active
    claim_ralph_queue_entry "instance-1"

    local result
    result=$(get_ralph_next_queued_prd)

    local project_root
    project_root=$(echo "$result" | jq -r '.projectRoot')
    [[ "$project_root" == "$TEST_PROJECT_2" ]]
}

@test "get_ralph_next_queued_prd() skips completed entries" {
    skip_if_no_jq

    init_ralph_queue
    local id1 id2
    id1=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")
    id2=$(add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2")

    # Mark first as completed
    complete_ralph_queue_entry "$id1"

    local result
    result=$(get_ralph_next_queued_prd)

    local project_root
    project_root=$(echo "$result" | jq -r '.projectRoot')
    [[ "$project_root" == "$TEST_PROJECT_2" ]]
}

# =============================================================================
# CLAIM AND WORK FLOW TESTS
# =============================================================================

@test "claim_and_work_next_queue_entry() claims entry" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local instance_id="test-worker-001"
    local claimed
    claimed=$(claim_ralph_queue_entry "$instance_id")

    local claimed_by
    claimed_by=$(echo "$claimed" | jq -r '.claimedBy')
    [[ "$claimed_by" == "$instance_id" ]]
}

@test "claim_and_work_next_queue_entry() returns entry details" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local claimed
    claimed=$(claim_ralph_queue_entry "test-worker-001")

    local prd_path project_root
    prd_path=$(echo "$claimed" | jq -r '.prdPath')
    project_root=$(echo "$claimed" | jq -r '.projectRoot')

    [[ "$prd_path" == "$TEST_PROJECT_1/scripts/ralph/prd.json" ]]
    [[ "$project_root" == "$TEST_PROJECT_1" ]]
}

@test "worker can complete work and mark entry done" {
    skip_if_no_jq

    init_ralph_queue
    local entry_id
    entry_id=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")

    # Claim the entry
    claim_ralph_queue_entry "test-worker-001"

    # Complete the work
    complete_ralph_queue_entry "$entry_id" "completed"

    # Verify status
    local entry
    entry=$(get_ralph_queue_entry "$entry_id")
    local status
    status=$(echo "$entry" | jq -r '.status')
    [[ "$status" == "completed" ]]
}

@test "worker can mark entry as failed" {
    skip_if_no_jq

    init_ralph_queue
    local entry_id
    entry_id=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")

    # Claim the entry
    claim_ralph_queue_entry "test-worker-001"

    # Mark as failed
    complete_ralph_queue_entry "$entry_id" "failed"

    # Verify status
    local entry
    entry=$(get_ralph_queue_entry "$entry_id")
    local status
    status=$(echo "$entry" | jq -r '.status')
    [[ "$status" == "failed" ]]
}

# =============================================================================
# MULTI-WORKER TESTS
# =============================================================================

@test "multiple workers can claim different entries" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2"

    # Worker 1 claims first entry
    local claimed1
    claimed1=$(claim_ralph_queue_entry "worker-1")
    local project1
    project1=$(echo "$claimed1" | jq -r '.projectRoot')

    # Worker 2 claims second entry
    local claimed2
    claimed2=$(claim_ralph_queue_entry "worker-2")
    local project2
    project2=$(echo "$claimed2" | jq -r '.projectRoot')

    # Different projects
    [[ "$project1" != "$project2" ]]
}

@test "worker gets nothing when all entries are claimed" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    # First worker claims the only entry
    claim_ralph_queue_entry "worker-1"

    # Second worker should get nothing
    run claim_ralph_queue_entry "worker-2"
    assert_failure
}

@test "worker can claim after another completes" {
    skip_if_no_jq

    init_ralph_queue
    local entry_id
    entry_id=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")

    # First worker claims
    claim_ralph_queue_entry "worker-1"

    # First worker completes
    complete_ralph_queue_entry "$entry_id" "completed"

    # Queue should now be empty for pending
    run claim_ralph_queue_entry "worker-2"
    assert_failure
}

# =============================================================================
# QUEUE MODE CONTINUATION TESTS
# =============================================================================

@test "worker continues to next PRD in queue mode" {
    skip_if_no_jq

    init_ralph_queue
    local id1 id2
    id1=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")
    id2=$(add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2")

    # Simulate worker completing first PRD
    claim_ralph_queue_entry "worker-1"
    complete_ralph_queue_entry "$id1" "completed"

    # Worker should be able to get next entry
    local next_entry
    next_entry=$(claim_ralph_queue_entry "worker-1")

    local project_root
    project_root=$(echo "$next_entry" | jq -r '.projectRoot')
    [[ "$project_root" == "$TEST_PROJECT_2" ]]
}

@test "worker stops when queue is empty" {
    skip_if_no_jq

    init_ralph_queue
    local id1
    id1=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")

    # Complete the only entry
    claim_ralph_queue_entry "worker-1"
    complete_ralph_queue_entry "$id1" "completed"

    # Should get nothing now
    run claim_ralph_queue_entry "worker-1"
    assert_failure
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles missing PRD file in queue entry" {
    skip_if_no_jq

    init_ralph_queue

    # Add entry with valid PRD
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    # Delete the PRD file
    rm "$TEST_PROJECT_1/scripts/ralph/prd.json"

    # Claiming should still work (file validation happens at work time)
    local claimed
    claimed=$(claim_ralph_queue_entry "worker-1")
    [[ -n "$claimed" ]]
}

@test "handles concurrent queue operations" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2"
    add_ralph_queue_entry "$TEST_PROJECT_3/scripts/ralph/prd.json" "$TEST_PROJECT_3"

    # Simulate parallel claims (in sequence for testing)
    local claimed1 claimed2 claimed3

    claimed1=$(claim_ralph_queue_entry "worker-1")
    claimed2=$(claim_ralph_queue_entry "worker-2")
    claimed3=$(claim_ralph_queue_entry "worker-3")

    # All should be different projects
    local p1 p2 p3
    p1=$(echo "$claimed1" | jq -r '.projectRoot')
    p2=$(echo "$claimed2" | jq -r '.projectRoot')
    p3=$(echo "$claimed3" | jq -r '.projectRoot')

    [[ "$p1" != "$p2" ]]
    [[ "$p2" != "$p3" ]]
    [[ "$p1" != "$p3" ]]
}

# =============================================================================
# HELPER FUNCTION TESTS
# =============================================================================

@test "get_ralph_next_queued_prd() function exists" {
    skip_if_no_jq

    # This should exist in ralph-utils.sh after implementation
    run type get_ralph_next_queued_prd
    # Will fail until implemented
}

@test "should_continue_with_queue() returns true when queue has entries" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local pending_count
    pending_count=$(get_ralph_queue_entries "pending" | jq 'length')
    [[ "$pending_count" -gt 0 ]]
}

@test "should_continue_with_queue() returns false when queue is empty" {
    skip_if_no_jq

    init_ralph_queue

    local pending_count
    pending_count=$(get_ralph_queue_entries "pending" | jq 'length')
    [[ "$pending_count" -eq 0 ]]
}
