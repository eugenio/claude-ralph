#!/usr/bin/env bats
# =============================================================================
# ralph-cleanup.bats - Tests for ralph-cleanup.sh
# =============================================================================
#
# DESCRIPTION:
#   Comprehensive test suite for ralph-cleanup.sh covering all commands:
#   - summary: Show instance summary (default)
#   - --dead: Clean up dead instances
#   - --old: Clean up old instances
#   - --all: Clean up both dead and old
#   - --dry-run: Preview mode without changes
#
# USAGE:
#   bats ralph-cleanup.bats
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

    # ralph-cleanup.sh is at project root level (2 directories up from scripts/ralph/)
    # RALPH_SCRIPT_DIR_ORIG points to scripts/ralph/
    local project_root="$RALPH_SCRIPT_DIR_ORIG/../.."

    # Copy ralph-cleanup.sh to test directory
    cp "$project_root/ralph-cleanup.sh" "$TEST_TEMP_DIR/scripts/ralph/"
    chmod +x "$TEST_TEMP_DIR/scripts/ralph/ralph-cleanup.sh"

    # Create prd.json for tests
    create_prd_fixture "partial"
}

teardown() {
    teardown_test_environment
}

# Helper to run ralph-cleanup.sh in test environment
run_ralph_cleanup() {
    cd "$TEST_TEMP_DIR/scripts/ralph" || return 1
    run bash "$TEST_TEMP_DIR/scripts/ralph/ralph-cleanup.sh" "$@"
}

# Custom lock fixture for ralph-cleanup.sh format
# ralph-cleanup.sh expects 'owner' file (not 'owner.txt')
create_cleanup_lock_fixture() {
    local story_id="$1"
    local owner="${2:-test-instance-1234-5678}"
    local lock_age="${3:-0}"

    local lock_dir="$TEST_TEMP_DIR/scripts/ralph/locks/${story_id}.lock"
    mkdir -p "$lock_dir"

    local now lock_timestamp
    now=$(date +%s)
    lock_timestamp=$((now - lock_age))

    # ralph-cleanup.sh expects 'owner' file without .txt extension
    echo "$owner" > "$lock_dir/owner"
    echo "$lock_timestamp" > "$lock_dir/timestamp"
}

# =============================================================================
# SCRIPT STRUCTURE TESTS
# =============================================================================

@test "ralph-cleanup.sh exists and is executable" {
    assert_file_exists "$TEST_TEMP_DIR/scripts/ralph/ralph-cleanup.sh"
    [[ -x "$TEST_TEMP_DIR/scripts/ralph/ralph-cleanup.sh" ]]
}

@test "ralph-cleanup.sh has valid bash syntax" {
    run bash -n "$TEST_TEMP_DIR/scripts/ralph/ralph-cleanup.sh"
    assert_success
}

# =============================================================================
# HELP COMMAND TESTS
# =============================================================================

@test "--help flag shows usage information" {
    run_ralph_cleanup --help
    assert_success
    assert_output_contains "Usage:"
    assert_output_contains "--dead"
    assert_output_contains "--old"
    assert_output_contains "--all"
    assert_output_contains "--dry-run"
}

@test "-h flag shows usage information" {
    run_ralph_cleanup -h
    assert_success
    assert_output_contains "Usage:"
}

@test "help shows RALPH_CLEANUP_TTL environment variable" {
    run_ralph_cleanup --help
    assert_success
    assert_output_contains "RALPH_CLEANUP_TTL"
}

# =============================================================================
# SUMMARY DISPLAY TESTS - NO INSTANCES
# =============================================================================

@test "default command shows summary when no cleanup flags provided" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "INSTANCE SUMMARY"
}

@test "summary shows total instances count" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Total instances:"
}

@test "summary shows running count" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Running:"
}

@test "summary shows completed count" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Completed:"
}

@test "summary shows terminated count" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Terminated:"
}

@test "summary shows dead count" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Dead:"
}

@test "summary shows active locks count" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Active locks:"
}

@test "summary with no instances shows zeros" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Total instances: 0"
}

# =============================================================================
# SUMMARY DISPLAY TESTS - WITH VARIOUS INSTANCE STATES
# =============================================================================

@test "summary counts running instances correctly" {
    # Create 2 running instances (recent heartbeat)
    create_instance_fixture "running-instance-1" "working" 10
    create_instance_fixture "running-instance-2" "claiming" 20

    run_ralph_cleanup
    assert_success
    assert_output_contains "Running:    2"
}

@test "summary counts completed instances correctly" {
    create_instance_fixture "completed-instance-1" "completed" 100
    create_instance_fixture "completed-instance-2" "completed" 200

    run_ralph_cleanup
    assert_success
    assert_output_contains "Completed:  2"
}

@test "summary counts terminated instances correctly" {
    create_instance_fixture "terminated-instance-1" "terminated" 100

    run_ralph_cleanup
    assert_success
    assert_output_contains "Terminated: 1"
}

@test "summary counts dead instances correctly" {
    # Dead = working/claiming state but no heartbeat for >5 min (300s)
    create_instance_fixture "dead-instance-1" "working" 400
    create_instance_fixture "dead-instance-2" "claiming" 500

    run_ralph_cleanup
    assert_success
    assert_output_contains "Dead:       2"
}

@test "summary with mixed instance states" {
    create_instance_fixture "running-1" "working" 10
    create_instance_fixture "completed-1" "completed" 100
    create_instance_fixture "terminated-1" "terminated" 200
    create_instance_fixture "dead-1" "working" 400

    run_ralph_cleanup
    assert_success
    assert_output_contains "Total instances: 4"
    assert_output_contains "Running:    1"
    assert_output_contains "Completed:  1"
    assert_output_contains "Terminated: 1"
    assert_output_contains "Dead:       1"
}

@test "summary counts locks correctly" {
    create_lock_fixture "US-001" "owner-1"
    create_lock_fixture "US-002" "owner-2"

    run_ralph_cleanup
    assert_success
    assert_output_contains "Active locks: 2"
}

# =============================================================================
# --DEAD FLAG TESTS
# =============================================================================

@test "--dead flag cleans only dead instances" {
    # Create a running instance (should NOT be cleaned)
    create_instance_fixture "running-instance" "working" 10

    # Create a dead instance (should be cleaned)
    create_instance_fixture "dead-instance" "working" 400

    run_ralph_cleanup --dead
    assert_success
    assert_output_contains "Checking for dead instances"
    assert_output_contains "dead-instance"

    # Check dead instance was marked as terminated
    local status_file="$TEST_TEMP_DIR/scripts/ralph/instances/dead-instance/status.json"
    local state
    state=$(jq -r '.state' "$status_file")
    [[ "$state" == "terminated" ]]

    # Running instance should be unchanged
    status_file="$TEST_TEMP_DIR/scripts/ralph/instances/running-instance/status.json"
    state=$(jq -r '.state' "$status_file")
    [[ "$state" == "working" ]]
}

@test "--dead flag shows cleaned count" {
    create_instance_fixture "dead-1" "working" 400
    create_instance_fixture "dead-2" "claiming" 500

    run_ralph_cleanup --dead
    assert_success
    assert_output_contains "Cleaned up 2 dead instances"
}

@test "--dead flag with no dead instances shows no dead instances" {
    create_instance_fixture "running-instance" "working" 10

    run_ralph_cleanup --dead
    assert_success
    assert_output_contains "No dead instances found"
}

@test "--dead flag releases locks held by dead instances" {
    # Create a dead instance
    create_instance_fixture "dead-instance-1234" "working" 400

    # Create a lock owned by the dead instance (using cleanup format with 'owner' not 'owner.txt')
    create_cleanup_lock_fixture "US-001" "dead-instance-1234"

    run_ralph_cleanup --dead
    assert_success
    assert_output_contains "Releasing lock"
    assert_output_contains "US-001"

    # Lock should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
}

@test "--dead flag does not clean completed instances" {
    create_instance_fixture "completed-instance" "completed" 400

    run_ralph_cleanup --dead
    assert_success
    assert_output_contains "No dead instances found"

    # Completed instance should still have completed state
    local status_file="$TEST_TEMP_DIR/scripts/ralph/instances/completed-instance/status.json"
    local state
    state=$(jq -r '.state' "$status_file")
    [[ "$state" == "completed" ]]
}

@test "--dead flag does not clean terminated instances" {
    create_instance_fixture "terminated-instance" "terminated" 400

    run_ralph_cleanup --dead
    assert_success
    assert_output_contains "No dead instances found"
}

# =============================================================================
# --OLD FLAG TESTS
# =============================================================================

@test "--old flag cleans only old instances" {
    # Create a recent instance (should NOT be cleaned)
    create_instance_fixture "recent-instance" "completed" 100

    # Create an old instance (>7 days = 604800 seconds)
    create_instance_fixture "old-instance" "completed" 700000

    run_ralph_cleanup --old
    assert_success
    assert_output_contains "Checking for old instances"
    assert_output_contains "old-instance"

    # Old instance directory should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/instances/old-instance" ]]

    # Recent instance should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/instances/recent-instance"
}

@test "--old flag shows removed count" {
    create_instance_fixture "old-1" "completed" 700000
    create_instance_fixture "old-2" "terminated" 800000

    run_ralph_cleanup --old
    assert_success
    assert_output_contains "Removed 2 old instances"
}

@test "--old flag with no old instances shows none found" {
    create_instance_fixture "recent-instance" "completed" 100

    run_ralph_cleanup --old
    assert_success
    assert_output_contains "No old instances found"
}

@test "--old flag respects RALPH_CLEANUP_TTL environment variable" {
    # Create instance that's 3 days old (259200 seconds)
    create_instance_fixture "three-day-old" "completed" 259200

    # With default 7-day TTL, should not be cleaned
    run_ralph_cleanup --old
    assert_success
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/instances/three-day-old"
}

@test "--old flag shows TTL in output" {
    run_ralph_cleanup --old
    assert_success
    # Should show TTL days in output (default 7)
    assert_output_contains "7 days"
}

@test "--old flag removes instance directory completely" {
    create_instance_fixture "old-instance" "completed" 700000

    run_ralph_cleanup --old
    assert_success

    # Entire directory should be gone, not just status.json
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/instances/old-instance" ]]
}

# =============================================================================
# --ALL FLAG TESTS
# =============================================================================

@test "--all flag cleans both dead and old instances" {
    # Create a dead instance
    create_instance_fixture "dead-instance" "working" 400

    # Create an old instance
    create_instance_fixture "old-instance" "completed" 700000

    run_ralph_cleanup --all
    assert_success
    assert_output_contains "Checking for dead instances"
    assert_output_contains "Checking for old instances"

    # Dead instance should be marked terminated
    local status_file="$TEST_TEMP_DIR/scripts/ralph/instances/dead-instance/status.json"
    local state
    state=$(jq -r '.state' "$status_file")
    [[ "$state" == "terminated" ]]

    # Old instance should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/instances/old-instance" ]]
}

@test "--all flag processes dead before old" {
    run_ralph_cleanup --all
    assert_success
    # Verify order in output - dead comes before old
    local dead_pos old_pos
    dead_pos=$(echo "$output" | grep -n "dead instances" | head -1 | cut -d: -f1)
    old_pos=$(echo "$output" | grep -n "old instances" | head -1 | cut -d: -f1)
    [[ "$dead_pos" -lt "$old_pos" ]]
}

# =============================================================================
# --DRY-RUN FLAG TESTS
# =============================================================================

@test "--dry-run shows actions without executing" {
    create_instance_fixture "dead-instance" "working" 400

    run_ralph_cleanup --dead --dry-run
    assert_success
    assert_output_contains "DRY RUN MODE"
    assert_output_contains "Would clean up"
}

@test "--dry-run does not modify dead instances" {
    create_instance_fixture "dead-instance" "working" 400

    run_ralph_cleanup --dead --dry-run
    assert_success

    # Instance should still have original state
    local status_file="$TEST_TEMP_DIR/scripts/ralph/instances/dead-instance/status.json"
    local state
    state=$(jq -r '.state' "$status_file")
    [[ "$state" == "working" ]]
}

@test "--dry-run does not remove old instances" {
    create_instance_fixture "old-instance" "completed" 700000

    run_ralph_cleanup --old --dry-run
    assert_success
    assert_output_contains "Would remove"

    # Instance directory should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/instances/old-instance"
}

@test "--dry-run does not release locks" {
    create_instance_fixture "dead-instance-1234" "working" 400
    create_cleanup_lock_fixture "US-001" "dead-instance-1234"

    run_ralph_cleanup --dead --dry-run
    assert_success

    # Lock should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock"
}

@test "--dry-run with --all shows both dead and old without changes" {
    create_instance_fixture "dead-instance" "working" 400
    create_instance_fixture "old-instance" "completed" 700000

    run_ralph_cleanup --all --dry-run
    assert_success
    assert_output_contains "DRY RUN MODE"
    assert_output_contains "Would clean up"
    assert_output_contains "Would remove"

    # Both instances should still exist/be unchanged
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/instances/dead-instance"
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/instances/old-instance"
}

# =============================================================================
# LOCK RELEASE FROM CLEANED INSTANCES TESTS
# =============================================================================

@test "releases all locks from cleaned dead instance" {
    create_instance_fixture "dead-instance-multi" "working" 400

    # Create multiple locks owned by the dead instance (using cleanup format)
    create_cleanup_lock_fixture "US-001" "dead-instance-multi"
    create_cleanup_lock_fixture "US-002" "dead-instance-multi"
    create_cleanup_lock_fixture "US-003" "dead-instance-multi"

    run_ralph_cleanup --dead
    assert_success

    # All locks should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-003.lock" ]]
}

@test "does not release locks from other instances" {
    create_instance_fixture "dead-instance" "working" 400
    create_instance_fixture "active-instance" "working" 10

    # Dead instance owns one lock (using cleanup format)
    create_cleanup_lock_fixture "US-001" "dead-instance"
    # Active instance owns another lock
    create_cleanup_lock_fixture "US-002" "active-instance"

    run_ralph_cleanup --dead
    assert_success

    # Dead instance's lock should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
    # Active instance's lock should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock"
}

# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================

@test "unknown option shows error and help" {
    run_ralph_cleanup --invalid-option
    assert_failure
    assert_output_contains "Unknown option"
}

@test "handles missing instances directory gracefully" {
    rm -rf "$TEST_TEMP_DIR/scripts/ralph/instances"

    run_ralph_cleanup
    assert_success
    assert_output_contains "No instances directory"
}

@test "handles empty instances directory" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Total instances: 0"
}

@test "handles instance without status.json" {
    # Create instance directory without status.json
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/instances/broken-instance"

    run_ralph_cleanup
    assert_success
    # Should not crash, should count as 1 instance
    assert_output_contains "Total instances: 1"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles instance with invalid JSON in status.json" {
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/instances/invalid-json"
    echo "not valid json" > "$TEST_TEMP_DIR/scripts/ralph/instances/invalid-json/status.json"

    run_ralph_cleanup
    assert_success
    # Should not crash
}

@test "summary shows after cleanup with --dead" {
    create_instance_fixture "dead-instance" "working" 400

    run_ralph_cleanup --dead
    assert_success
    # Should show summary at end
    assert_output_contains "INSTANCE SUMMARY"
}

@test "summary shows after cleanup with --old" {
    create_instance_fixture "old-instance" "completed" 700000

    run_ralph_cleanup --old
    assert_success
    # Should show summary at end
    assert_output_contains "INSTANCE SUMMARY"
}

@test "handles locks directory not existing" {
    rm -rf "$TEST_TEMP_DIR/scripts/ralph/locks"
    create_instance_fixture "dead-instance" "working" 400

    run_ralph_cleanup --dead
    assert_success
    # Should not crash when trying to release locks
}

@test "shows hint to run with flags when no cleanup requested" {
    run_ralph_cleanup
    assert_success
    assert_output_contains "Run with --dead, --old, or --all"
}
