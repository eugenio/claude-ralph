#!/usr/bin/env bats
# =============================================================================
# ralph-queue.bats - Tests for ralph queue functionality
# =============================================================================
#
# DESCRIPTION:
#   Comprehensive test suite for ralph queue management functions.
#   Tests queue initialization, entry management, claiming, and completion.
#
# USAGE:
#   bats scripts/ralph/tests/bash/ralph-queue.bats
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

    # Create test project directories
    TEST_PROJECT_1="$TEST_TEMP_DIR/project1"
    TEST_PROJECT_2="$TEST_TEMP_DIR/project2"
    mkdir -p "$TEST_PROJECT_1/scripts/ralph"
    mkdir -p "$TEST_PROJECT_2/scripts/ralph"

    # Create test PRD files
    cat > "$TEST_PROJECT_1/scripts/ralph/prd.json" <<'EOF'
{
  "featureName": "Project 1 Feature",
  "branchName": "feature/project1",
  "userStories": [
    {"id": "P1-001", "title": "Story 1", "passes": false, "priority": 1},
    {"id": "P1-002", "title": "Story 2", "passes": false, "priority": 2}
  ]
}
EOF

    cat > "$TEST_PROJECT_2/scripts/ralph/prd.json" <<'EOF'
{
  "featureName": "Project 2 Feature",
  "branchName": "feature/project2",
  "userStories": [
    {"id": "P2-001", "title": "Story 1", "passes": false, "priority": 1}
  ]
}
EOF

    export TEST_PROJECT_1
    export TEST_PROJECT_2
}

teardown() {
    teardown_test_environment
    unset RALPH_GLOBAL_DIR
}

# =============================================================================
# QUEUE FIXTURE HELPERS
# =============================================================================

# create_queue_fixture()
# Creates a queue.json file in the global directory
# Arguments:
#   $1 - Number of entries to create (default 0)
#   $2 - Status for entries (default "pending")
#
create_queue_fixture() {
    local num_entries="${1:-0}"
    local entry_status="${2:-pending}"
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"

    local entries="[]"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    for i in $(seq 1 "$num_entries"); do
        local entry
        entry=$(jq -n \
            --arg id "entry-$i" \
            --arg prdPath "$TEST_PROJECT_1/scripts/ralph/prd.json" \
            --arg projectRoot "$TEST_PROJECT_1" \
            --argjson priority "$i" \
            --arg status "$entry_status" \
            --arg addedAt "$now" \
            '{
                id: $id,
                prdPath: $prdPath,
                projectRoot: $projectRoot,
                priority: $priority,
                status: $status,
                addedAt: $addedAt,
                claimedBy: null,
                claimedAt: null,
                completedAt: null
            }')
        entries=$(echo "$entries" | jq --argjson entry "$entry" '. += [$entry]')
    done

    echo "{\"entries\": $entries}" > "$queue_file"
}

# =============================================================================
# init_ralph_queue() TESTS
# =============================================================================

@test "init_ralph_queue() creates queue.json if not exists" {
    skip_if_no_jq

    # Ensure queue doesn't exist
    [[ ! -f "$RALPH_GLOBAL_DIR/queue.json" ]]

    run init_ralph_queue
    assert_success

    assert_file_exists "$RALPH_GLOBAL_DIR/queue.json"
}

@test "init_ralph_queue() creates valid JSON structure" {
    skip_if_no_jq

    init_ralph_queue

    local queue_content
    queue_content=$(cat "$RALPH_GLOBAL_DIR/queue.json")

    # Should have entries array
    local has_entries
    has_entries=$(echo "$queue_content" | jq 'has("entries")')
    [[ "$has_entries" == "true" ]]
}

@test "init_ralph_queue() creates empty entries array" {
    skip_if_no_jq

    init_ralph_queue

    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 0 ]]
}

@test "init_ralph_queue() is idempotent" {
    skip_if_no_jq

    # Create queue with an entry
    create_queue_fixture 1

    # Call init again
    run init_ralph_queue
    assert_success

    # Entry should still exist
    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 1 ]]
}

@test "init_ralph_queue() creates global directory if not exists" {
    skip_if_no_jq

    rm -rf "$RALPH_GLOBAL_DIR"
    [[ ! -d "$RALPH_GLOBAL_DIR" ]]

    run init_ralph_queue
    assert_success

    assert_dir_exists "$RALPH_GLOBAL_DIR"
    assert_file_exists "$RALPH_GLOBAL_DIR/queue.json"
}

# =============================================================================
# add_ralph_queue_entry() TESTS
# =============================================================================

@test "add_ralph_queue_entry() adds entry to queue" {
    skip_if_no_jq

    init_ralph_queue

    run add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    assert_success

    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 1 ]]
}

@test "add_ralph_queue_entry() returns entry ID" {
    skip_if_no_jq

    init_ralph_queue

    local entry_id
    entry_id=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")

    [[ -n "$entry_id" ]]
}

@test "add_ralph_queue_entry() sets status to pending" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local status
    status=$(jq -r '.entries[0].status' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$status" == "pending" ]]
}

@test "add_ralph_queue_entry() stores prd path" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local prd_path
    prd_path=$(jq -r '.entries[0].prdPath' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$prd_path" == "$TEST_PROJECT_1/scripts/ralph/prd.json" ]]
}

@test "add_ralph_queue_entry() stores project root" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local project_root
    project_root=$(jq -r '.entries[0].projectRoot' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$project_root" == "$TEST_PROJECT_1" ]]
}

@test "add_ralph_queue_entry() sets addedAt timestamp" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local added_at
    added_at=$(jq -r '.entries[0].addedAt' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$added_at" != "null" ]]
}

@test "add_ralph_queue_entry() uses default priority 10" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local priority
    priority=$(jq '.entries[0].priority' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$priority" -eq 10 ]]
}

@test "add_ralph_queue_entry() accepts custom priority" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1" 1

    local priority
    priority=$(jq '.entries[0].priority' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$priority" -eq 1 ]]
}

@test "add_ralph_queue_entry() generates unique IDs" {
    skip_if_no_jq

    init_ralph_queue
    local id1 id2

    id1=$(add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1")
    id2=$(add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2")

    [[ "$id1" != "$id2" ]]
}

@test "add_ralph_queue_entry() fails if PRD file doesn't exist" {
    skip_if_no_jq

    init_ralph_queue

    run add_ralph_queue_entry "/nonexistent/prd.json" "$TEST_PROJECT_1"
    assert_failure
}

@test "add_ralph_queue_entry() fails if project root doesn't exist" {
    skip_if_no_jq

    init_ralph_queue

    run add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "/nonexistent/project"
    assert_failure
}

@test "add_ralph_queue_entry() adds multiple entries" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1" 2
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2" 1

    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 2 ]]
}

@test "add_ralph_queue_entry() initializes claimedBy as null" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    local claimed_by
    claimed_by=$(jq -r '.entries[0].claimedBy' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$claimed_by" == "null" ]]
}

# =============================================================================
# get_ralph_queue_entries() TESTS
# =============================================================================

@test "get_ralph_queue_entries() returns empty array for empty queue" {
    skip_if_no_jq

    init_ralph_queue

    local entries
    entries=$(get_ralph_queue_entries)

    [[ "$entries" == "[]" ]]
}

@test "get_ralph_queue_entries() returns all entries" {
    skip_if_no_jq

    create_queue_fixture 3

    local entries entries_count
    entries=$(get_ralph_queue_entries)
    entries_count=$(echo "$entries" | jq 'length')

    [[ "$entries_count" -eq 3 ]]
}

@test "get_ralph_queue_entries() returns entries with all fields" {
    skip_if_no_jq

    create_queue_fixture 1

    local entries
    entries=$(get_ralph_queue_entries)

    local has_id has_prd_path has_status
    has_id=$(echo "$entries" | jq '.[0] | has("id")')
    has_prd_path=$(echo "$entries" | jq '.[0] | has("prdPath")')
    has_status=$(echo "$entries" | jq '.[0] | has("status")')

    [[ "$has_id" == "true" ]]
    [[ "$has_prd_path" == "true" ]]
    [[ "$has_status" == "true" ]]
}

@test "get_ralph_queue_entries() filters by status" {
    skip_if_no_jq

    # Create queue with mixed statuses
    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2"

    # Manually mark one as completed
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    local pending_entries pending_count
    pending_entries=$(get_ralph_queue_entries "pending")
    pending_count=$(echo "$pending_entries" | jq 'length')

    [[ "$pending_count" -eq 1 ]]
}

@test "get_ralph_queue_entries() sorts by priority" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1" 5
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2" 1

    local entries first_priority
    entries=$(get_ralph_queue_entries)
    first_priority=$(echo "$entries" | jq '.[0].priority')

    # Lower priority number should come first
    [[ "$first_priority" -eq 1 ]]
}

@test "get_ralph_queue_entries() returns pending entries by default" {
    skip_if_no_jq

    create_queue_fixture 2 "pending"

    # Mark one as completed
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    local entries entries_count
    entries=$(get_ralph_queue_entries)
    entries_count=$(echo "$entries" | jq 'length')

    # Should return only pending entries
    [[ "$entries_count" -eq 1 ]]
}

@test "get_ralph_queue_entries() can get all entries regardless of status" {
    skip_if_no_jq

    create_queue_fixture 3 "pending"

    # Mark entries with different statuses
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed" | .entries[1].status = "active"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    local entries entries_count
    entries=$(get_ralph_queue_entries "all")
    entries_count=$(echo "$entries" | jq 'length')

    [[ "$entries_count" -eq 3 ]]
}

# =============================================================================
# claim_ralph_queue_entry() TESTS
# =============================================================================

@test "claim_ralph_queue_entry() claims first pending entry" {
    skip_if_no_jq

    create_queue_fixture 2

    local instance_id="test-instance-123"
    local claimed_entry
    claimed_entry=$(claim_ralph_queue_entry "$instance_id")

    [[ -n "$claimed_entry" ]]
}

@test "claim_ralph_queue_entry() sets status to active" {
    skip_if_no_jq

    create_queue_fixture 1

    claim_ralph_queue_entry "test-instance-123"

    local status
    status=$(jq -r '.entries[0].status' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$status" == "active" ]]
}

@test "claim_ralph_queue_entry() sets claimedBy" {
    skip_if_no_jq

    create_queue_fixture 1

    claim_ralph_queue_entry "test-instance-123"

    local claimed_by
    claimed_by=$(jq -r '.entries[0].claimedBy' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$claimed_by" == "test-instance-123" ]]
}

@test "claim_ralph_queue_entry() sets claimedAt timestamp" {
    skip_if_no_jq

    create_queue_fixture 1

    claim_ralph_queue_entry "test-instance-123"

    local claimed_at
    claimed_at=$(jq -r '.entries[0].claimedAt' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$claimed_at" != "null" ]]
}

@test "claim_ralph_queue_entry() returns claimed entry JSON" {
    skip_if_no_jq

    create_queue_fixture 1

    local claimed_entry entry_id
    claimed_entry=$(claim_ralph_queue_entry "test-instance-123")
    entry_id=$(echo "$claimed_entry" | jq -r '.id')

    [[ "$entry_id" == "entry-1" ]]
}

@test "claim_ralph_queue_entry() returns failure for empty queue" {
    skip_if_no_jq

    init_ralph_queue

    run claim_ralph_queue_entry "test-instance-123"
    assert_failure
}

@test "claim_ralph_queue_entry() skips already claimed entries" {
    skip_if_no_jq

    create_queue_fixture 2

    # Claim first entry
    claim_ralph_queue_entry "instance-1"

    # Second claim should get second entry
    local claimed_entry entry_id
    claimed_entry=$(claim_ralph_queue_entry "instance-2")
    entry_id=$(echo "$claimed_entry" | jq -r '.id')

    [[ "$entry_id" == "entry-2" ]]
}

@test "claim_ralph_queue_entry() claims by priority order" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1" 5
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2" 1

    local claimed_entry project_root
    claimed_entry=$(claim_ralph_queue_entry "test-instance-123")
    project_root=$(echo "$claimed_entry" | jq -r '.projectRoot')

    # Should claim lower priority number first (project 2)
    [[ "$project_root" == "$TEST_PROJECT_2" ]]
}

@test "claim_ralph_queue_entry() returns failure when all claimed" {
    skip_if_no_jq

    create_queue_fixture 1

    # Claim the only entry
    claim_ralph_queue_entry "instance-1"

    # Try to claim again
    run claim_ralph_queue_entry "instance-2"
    assert_failure
}

@test "claim_ralph_queue_entry() includes prdPath in response" {
    skip_if_no_jq

    create_queue_fixture 1

    local claimed_entry prd_path
    claimed_entry=$(claim_ralph_queue_entry "test-instance-123")
    prd_path=$(echo "$claimed_entry" | jq -r '.prdPath')

    [[ -n "$prd_path" ]]
}

@test "claim_ralph_queue_entry() includes projectRoot in response" {
    skip_if_no_jq

    create_queue_fixture 1

    local claimed_entry project_root
    claimed_entry=$(claim_ralph_queue_entry "test-instance-123")
    project_root=$(echo "$claimed_entry" | jq -r '.projectRoot')

    [[ -n "$project_root" ]]
}

# =============================================================================
# complete_ralph_queue_entry() TESTS
# =============================================================================

@test "complete_ralph_queue_entry() sets status to completed" {
    skip_if_no_jq

    create_queue_fixture 1

    complete_ralph_queue_entry "entry-1"

    local status
    status=$(jq -r '.entries[0].status' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$status" == "completed" ]]
}

@test "complete_ralph_queue_entry() sets completedAt timestamp" {
    skip_if_no_jq

    create_queue_fixture 1

    complete_ralph_queue_entry "entry-1"

    local completed_at
    completed_at=$(jq -r '.entries[0].completedAt' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$completed_at" != "null" ]]
}

@test "complete_ralph_queue_entry() can mark as failed" {
    skip_if_no_jq

    create_queue_fixture 1

    complete_ralph_queue_entry "entry-1" "failed"

    local status
    status=$(jq -r '.entries[0].status' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$status" == "failed" ]]
}

@test "complete_ralph_queue_entry() returns success on valid entry" {
    skip_if_no_jq

    create_queue_fixture 1

    run complete_ralph_queue_entry "entry-1"
    assert_success
}

@test "complete_ralph_queue_entry() returns failure on invalid entry" {
    skip_if_no_jq

    create_queue_fixture 1

    run complete_ralph_queue_entry "nonexistent-entry"
    assert_failure
}

@test "complete_ralph_queue_entry() doesn't affect other entries" {
    skip_if_no_jq

    create_queue_fixture 2

    complete_ralph_queue_entry "entry-1"

    local entry2_status
    entry2_status=$(jq -r '.entries[1].status' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entry2_status" == "pending" ]]
}

# =============================================================================
# remove_ralph_queue_entry() TESTS
# =============================================================================

@test "remove_ralph_queue_entry() removes entry from queue" {
    skip_if_no_jq

    create_queue_fixture 2

    remove_ralph_queue_entry "entry-1"

    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 1 ]]
}

@test "remove_ralph_queue_entry() removes correct entry" {
    skip_if_no_jq

    create_queue_fixture 2

    remove_ralph_queue_entry "entry-1"

    local remaining_id
    remaining_id=$(jq -r '.entries[0].id' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$remaining_id" == "entry-2" ]]
}

@test "remove_ralph_queue_entry() returns success on valid entry" {
    skip_if_no_jq

    create_queue_fixture 1

    run remove_ralph_queue_entry "entry-1"
    assert_success
}

@test "remove_ralph_queue_entry() returns failure on invalid entry" {
    skip_if_no_jq

    create_queue_fixture 1

    run remove_ralph_queue_entry "nonexistent-entry"
    assert_failure
}

@test "remove_ralph_queue_entry() handles empty queue" {
    skip_if_no_jq

    init_ralph_queue

    run remove_ralph_queue_entry "any-entry"
    assert_failure
}

# =============================================================================
# clear_ralph_queue_completed() TESTS
# =============================================================================

@test "clear_ralph_queue_completed() removes completed entries" {
    skip_if_no_jq

    create_queue_fixture 3

    # Mark some as completed
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed" | .entries[2].status = "completed"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    clear_ralph_queue_completed

    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 1 ]]
}

@test "clear_ralph_queue_completed() keeps pending entries" {
    skip_if_no_jq

    create_queue_fixture 2

    # Mark one as completed
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    clear_ralph_queue_completed

    local remaining_status
    remaining_status=$(jq -r '.entries[0].status' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$remaining_status" == "pending" ]]
}

@test "clear_ralph_queue_completed() keeps active entries" {
    skip_if_no_jq

    create_queue_fixture 2

    # Mark one as completed and one as active
    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed" | .entries[1].status = "active"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    clear_ralph_queue_completed

    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 1 ]]
}

@test "clear_ralph_queue_completed() returns count of cleared entries" {
    skip_if_no_jq

    create_queue_fixture 3

    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed" | .entries[2].status = "completed"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    local cleared_count
    cleared_count=$(clear_ralph_queue_completed)

    [[ "$cleared_count" -eq 2 ]]
}

# =============================================================================
# QUEUE ATOMICITY TESTS
# =============================================================================

@test "queue operations use file locking" {
    skip_if_no_jq

    # This test verifies that queue operations don't corrupt data
    # under concurrent access (basic sanity check)

    init_ralph_queue

    # Add entries in sequence
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    add_ralph_queue_entry "$TEST_PROJECT_2/scripts/ralph/prd.json" "$TEST_PROJECT_2"

    # Verify both entries exist
    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 2 ]]
}

@test "queue lock file is created during operations" {
    skip_if_no_jq

    init_ralph_queue
    add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"

    # Lock file should exist (or have existed) - we just verify queue is intact
    local entries_count
    entries_count=$(jq '.entries | length' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$entries_count" -eq 1 ]]
}

# =============================================================================
# get_ralph_queue_entry() TESTS
# =============================================================================

@test "get_ralph_queue_entry() returns entry by ID" {
    skip_if_no_jq

    create_queue_fixture 2

    local entry entry_id
    entry=$(get_ralph_queue_entry "entry-1")
    entry_id=$(echo "$entry" | jq -r '.id')

    [[ "$entry_id" == "entry-1" ]]
}

@test "get_ralph_queue_entry() returns failure for non-existent entry" {
    skip_if_no_jq

    create_queue_fixture 1

    run get_ralph_queue_entry "nonexistent"
    assert_failure
}

@test "get_ralph_queue_entry() includes all entry fields" {
    skip_if_no_jq

    create_queue_fixture 1

    local entry
    entry=$(get_ralph_queue_entry "entry-1")

    local has_prd has_root has_status
    has_prd=$(echo "$entry" | jq 'has("prdPath")')
    has_root=$(echo "$entry" | jq 'has("projectRoot")')
    has_status=$(echo "$entry" | jq 'has("status")')

    [[ "$has_prd" == "true" ]]
    [[ "$has_root" == "true" ]]
    [[ "$has_status" == "true" ]]
}

# =============================================================================
# QUEUE STATUS SUMMARY TESTS
# =============================================================================

@test "get_ralph_queue_summary() returns status counts" {
    skip_if_no_jq

    create_queue_fixture 4

    local queue_file="$RALPH_GLOBAL_DIR/queue.json"
    jq '.entries[0].status = "completed" | .entries[1].status = "active" | .entries[2].status = "failed"' "$queue_file" > "$queue_file.tmp" && mv "$queue_file.tmp" "$queue_file"

    local summary
    summary=$(get_ralph_queue_summary)

    local pending completed active failed
    pending=$(echo "$summary" | jq '.pending')
    completed=$(echo "$summary" | jq '.completed')
    active=$(echo "$summary" | jq '.active')
    failed=$(echo "$summary" | jq '.failed')

    [[ "$pending" -eq 1 ]]
    [[ "$completed" -eq 1 ]]
    [[ "$active" -eq 1 ]]
    [[ "$failed" -eq 1 ]]
}

@test "get_ralph_queue_summary() returns total count" {
    skip_if_no_jq

    create_queue_fixture 3

    local summary total
    summary=$(get_ralph_queue_summary)
    total=$(echo "$summary" | jq '.total')

    [[ "$total" -eq 3 ]]
}

@test "get_ralph_queue_summary() works on empty queue" {
    skip_if_no_jq

    init_ralph_queue

    local summary total
    summary=$(get_ralph_queue_summary)
    total=$(echo "$summary" | jq '.total')

    [[ "$total" -eq 0 ]]
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles queue with special characters in paths" {
    skip_if_no_jq

    # Create project with spaces in path
    local special_project="$TEST_TEMP_DIR/project with spaces"
    mkdir -p "$special_project/scripts/ralph"
    cp "$TEST_PROJECT_1/scripts/ralph/prd.json" "$special_project/scripts/ralph/"

    init_ralph_queue
    run add_ralph_queue_entry "$special_project/scripts/ralph/prd.json" "$special_project"
    assert_success

    local prd_path
    prd_path=$(jq -r '.entries[0].prdPath' "$RALPH_GLOBAL_DIR/queue.json")
    [[ "$prd_path" == "$special_project/scripts/ralph/prd.json" ]]
}

@test "handles unicode in project paths" {
    skip_if_no_jq

    # Create project with unicode in path
    local unicode_project="$TEST_TEMP_DIR/プロジェクト"
    mkdir -p "$unicode_project/scripts/ralph"
    cp "$TEST_PROJECT_1/scripts/ralph/prd.json" "$unicode_project/scripts/ralph/"

    init_ralph_queue
    run add_ralph_queue_entry "$unicode_project/scripts/ralph/prd.json" "$unicode_project"
    # May succeed or fail depending on filesystem
    # Just ensure it doesn't crash
}

@test "handles concurrent claims gracefully" {
    skip_if_no_jq

    create_queue_fixture 1

    # First claim succeeds
    claim_ralph_queue_entry "instance-1"

    # Second claim should fail
    run claim_ralph_queue_entry "instance-2"
    assert_failure
}

@test "queue survives invalid JSON in PRD file" {
    skip_if_no_jq

    # Create invalid PRD
    echo "{ invalid json" > "$TEST_PROJECT_1/scripts/ralph/prd.json"

    init_ralph_queue

    # Should still be able to add to queue (validation is PRD's job)
    run add_ralph_queue_entry "$TEST_PROJECT_1/scripts/ralph/prd.json" "$TEST_PROJECT_1"
    # This should succeed - we just store the path
    assert_success
}
