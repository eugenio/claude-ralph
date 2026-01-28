#!/usr/bin/env bats
# =============================================================================
# ralph-locks.bats - Tests for ralph-locks.sh
# =============================================================================
#
# DESCRIPTION:
#   Comprehensive test suite for ralph-locks.sh covering all commands:
#   - status: Show all current locks
#   - release: Release a specific lock
#   - release-all: Release all locks
#   - cleanup: Remove stale locks
#
# USAGE:
#   bats ralph-locks.bats
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

    # Copy ralph-utils.sh and ralph-locks.sh to test directory
    cp "$RALPH_SCRIPT_DIR_ORIG/ralph-utils.sh" "$TEST_TEMP_DIR/scripts/ralph/"
    cp "$RALPH_SCRIPT_DIR_ORIG/ralph-locks.sh" "$TEST_TEMP_DIR/scripts/ralph/"
    chmod +x "$TEST_TEMP_DIR/scripts/ralph/ralph-locks.sh"
    chmod +x "$TEST_TEMP_DIR/scripts/ralph/ralph-utils.sh"

    # Create prd.json for tests
    create_prd_fixture "partial"
}

teardown() {
    teardown_test_environment
}

# Helper to run ralph-locks.sh in test environment
# Runs the script in a subshell to avoid readonly variable conflicts
run_ralph_locks() {
    cd "$TEST_TEMP_DIR" || return 1
    run bash "$TEST_TEMP_DIR/scripts/ralph/ralph-locks.sh" "$@"
}

# =============================================================================
# SCRIPT STRUCTURE TESTS
# =============================================================================

@test "ralph-locks.sh exists and is executable" {
    assert_file_exists "$TEST_TEMP_DIR/scripts/ralph/ralph-locks.sh"
    [[ -x "$TEST_TEMP_DIR/scripts/ralph/ralph-locks.sh" ]]
}

@test "ralph-locks.sh has valid bash syntax" {
    run bash -n "$TEST_TEMP_DIR/scripts/ralph/ralph-locks.sh"
    assert_success
}

@test "ralph-locks.sh sources ralph-utils.sh" {
    run grep -q "source.*ralph-utils.sh" "$TEST_TEMP_DIR/scripts/ralph/ralph-locks.sh"
    assert_success
}

# =============================================================================
# HELP COMMAND TESTS
# =============================================================================

@test "help command shows usage information" {
    run_ralph_locks help
    assert_success
    assert_output_contains "Usage:"
    assert_output_contains "Commands:"
}

@test "--help flag shows usage information" {
    run_ralph_locks --help
    assert_success
    assert_output_contains "Usage:"
}

@test "-h flag shows usage information" {
    run_ralph_locks -h
    assert_success
    assert_output_contains "Usage:"
}

# =============================================================================
# STATUS COMMAND TESTS - NO LOCKS
# =============================================================================

@test "status command with no locks shows 'No active locks'" {
    run_ralph_locks status
    assert_success
    assert_output_contains "No active locks"
}

@test "status command is default (no arguments)" {
    run_ralph_locks
    assert_success
    assert_output_contains "RALPH LOCK STATUS"
}

@test "status command shows header banner" {
    run_ralph_locks status
    assert_success
    assert_output_contains "RALPH LOCK STATUS"
}

# =============================================================================
# STATUS COMMAND TESTS - WITH LOCKS
# =============================================================================

@test "status command shows existing lock" {
    create_lock_fixture "US-001" "test-owner-123"

    run_ralph_locks status
    assert_success
    assert_output_contains "US-001"
    assert_output_contains "test-owner-123"
}

@test "status command shows multiple locks" {
    create_lock_fixture "US-001" "owner-1"
    create_lock_fixture "US-002" "owner-2"
    create_lock_fixture "US-003" "owner-3"

    run_ralph_locks status
    assert_success
    assert_output_contains "US-001"
    assert_output_contains "US-002"
    assert_output_contains "US-003"
}

@test "status command shows lock age" {
    # Create a lock that's 5 seconds old
    create_lock_fixture "US-001" "test-owner" 5

    run_ralph_locks status
    assert_success
    # Should show age in seconds format
    assert_output_contains "s"
}

@test "status command shows lock with minute age" {
    # Create a lock that's 120 seconds (2 minutes) old
    create_lock_fixture "US-001" "test-owner" 120

    run_ralph_locks status
    assert_success
    # Should show age in minutes format
    assert_output_contains "m"
}

@test "status command shows lock with hour age" {
    # Create a lock that's 7200 seconds (2 hours) old
    create_lock_fixture "US-001" "test-owner" 7200

    run_ralph_locks status
    assert_success
    # Should show age in hours format
    assert_output_contains "h"
}

@test "status command shows valid lock status" {
    create_lock_fixture "US-001" "test-owner" 10

    run_ralph_locks status
    assert_success
    assert_output_contains "valid"
}

@test "status command shows stale lock status" {
    # Create a lock that's >2 hours old (7201 seconds)
    create_lock_fixture "US-001" "test-owner" 7201

    run_ralph_locks status
    assert_success
    assert_output_contains "stale"
}

@test "status command shows table headers" {
    create_lock_fixture "US-001" "test-owner"

    run_ralph_locks status
    assert_success
    assert_output_contains "STORY"
    assert_output_contains "OWNER"
    assert_output_contains "AGE"
    assert_output_contains "STATUS"
}

@test "status command truncates long owner names" {
    # Create lock with very long owner name
    create_lock_fixture "US-001" "this-is-a-very-long-owner-name-that-should-be-truncated"

    run_ralph_locks status
    assert_success
    # Should be truncated with ...
    assert_output_contains "..."
}

# =============================================================================
# RELEASE COMMAND TESTS
# =============================================================================

@test "release command removes specific lock" {
    create_lock_fixture "US-001" "test-owner"

    # Verify lock exists
    local lock_dir="$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock"
    assert_dir_exists "$lock_dir"

    run_ralph_locks release -s US-001
    assert_success
    assert_output_contains "Released"

    # Verify lock is removed
    [[ ! -d "$lock_dir" ]]
}

@test "release command with --story flag works" {
    create_lock_fixture "US-002" "test-owner"

    run_ralph_locks release --story US-002
    assert_success
    assert_output_contains "Released"

    local lock_dir="$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock"
    [[ ! -d "$lock_dir" ]]
}

@test "release command shows owner when releasing" {
    create_lock_fixture "US-001" "owner-to-show"

    run_ralph_locks release -s US-001
    assert_success
    assert_output_contains "owner-to-show"
}

@test "release command handles non-existent lock" {
    run_ralph_locks release -s US-999
    # Should succeed but indicate no lock found
    assert_success
    assert_output_contains "No lock found"
}

@test "release command requires story ID" {
    run_ralph_locks release
    assert_failure
    assert_output_contains "Error"
    assert_output_contains "StoryId required"
}

@test "release command does not affect other locks" {
    create_lock_fixture "US-001" "owner-1"
    create_lock_fixture "US-002" "owner-2"

    run_ralph_locks release -s US-001
    assert_success

    # US-001 should be gone
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
    # US-002 should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock"
}

# =============================================================================
# RELEASE-ALL COMMAND TESTS
# =============================================================================

@test "release-all command removes all locks" {
    create_lock_fixture "US-001" "owner-1"
    create_lock_fixture "US-002" "owner-2"
    create_lock_fixture "US-003" "owner-3"

    run_ralph_locks release-all
    assert_success

    # All locks should be gone
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-003.lock" ]]
}

@test "release-all command shows progress" {
    create_lock_fixture "US-001" "owner-1"
    create_lock_fixture "US-002" "owner-2"

    run_ralph_locks release-all
    assert_success
    assert_output_contains "Released"
}

@test "release-all command with no locks succeeds" {
    run_ralph_locks release-all
    assert_success
    assert_output_contains "Released"
}

@test "release-all command shows release count" {
    create_lock_fixture "US-001" "owner-1"
    create_lock_fixture "US-002" "owner-2"

    run_ralph_locks release-all
    assert_success
    # Should show count of released locks
    assert_output_contains "2"
}

# =============================================================================
# CLEANUP COMMAND TESTS
# =============================================================================

@test "cleanup command removes stale locks only" {
    # Create a valid lock (10 seconds old)
    create_lock_fixture "US-001" "owner-1" 10

    # Create a stale lock (>2 hours old)
    create_lock_fixture "US-002" "owner-2" 7500

    run_ralph_locks cleanup
    assert_success

    # Valid lock should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock"
    # Stale lock should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock" ]]
}

@test "cleanup command shows 'No stale locks' when none to clean" {
    # Create only valid locks
    create_lock_fixture "US-001" "owner-1" 10

    run_ralph_locks cleanup
    assert_success
    assert_output_contains "No stale locks"
}

@test "cleanup command shows removed lock info" {
    create_lock_fixture "US-001" "owner-1" 8000

    run_ralph_locks cleanup
    assert_success
    assert_output_contains "US-001"
    assert_output_contains "stale"
}

@test "cleanup command handles multiple stale locks" {
    # All stale
    create_lock_fixture "US-001" "owner-1" 8000
    create_lock_fixture "US-002" "owner-2" 9000
    create_lock_fixture "US-003" "owner-3" 10000

    run_ralph_locks cleanup
    assert_success

    # All should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-003.lock" ]]
}

@test "cleanup command with empty locks directory" {
    run_ralph_locks cleanup
    assert_success
    assert_output_contains "No stale locks"
}

# =============================================================================
# DEAD OWNER DETECTION TESTS
# =============================================================================

@test "status command identifies dead owner lock" {
    # Create an instance that looks dead (no recent heartbeat)
    create_instance_fixture "dead-instance-1234" "working" 600

    # Create lock owned by dead instance
    create_lock_fixture "US-001" "dead-instance-1234" 100

    run_ralph_locks status
    assert_success
    # Should identify as dead owner
    assert_output_contains "dead"
}

@test "cleanup command removes dead owner locks" {
    # Create an instance that looks dead
    create_instance_fixture "dead-instance-5678" "working" 600

    # Create lock owned by dead instance
    create_lock_fixture "US-001" "dead-instance-5678" 100

    run_ralph_locks cleanup
    assert_success
    assert_output_contains "dead"

    # Lock should be removed
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
}

@test "cleanup keeps valid lock from active instance" {
    # Create an instance that is active (recent heartbeat)
    create_instance_fixture "active-instance-1234" "working" 10

    # Create lock owned by active instance
    create_lock_fixture "US-001" "active-instance-1234" 100

    run_ralph_locks cleanup
    assert_success
    # Should indicate no stale locks
    assert_output_contains "No stale locks"

    # Lock should still exist
    assert_dir_exists "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock"
}

@test "dead owner lock is removed even if not stale by age" {
    # Create a very dead instance (10 minutes without heartbeat)
    create_instance_fixture "very-dead-instance" "working" 600

    # Create a recent lock (only 60 seconds old) but owned by dead instance
    create_lock_fixture "US-001" "very-dead-instance" 60

    run_ralph_locks cleanup
    assert_success

    # Should be removed because owner is dead
    [[ ! -d "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock" ]]
}

# =============================================================================
# UNKNOWN COMMAND TESTS
# =============================================================================

@test "unknown command shows error and help" {
    run_ralph_locks invalid-command
    assert_failure
    assert_output_contains "Unknown command"
    assert_output_contains "Usage:"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles lock directory not existing" {
    # Remove locks directory
    rm -rf "$TEST_TEMP_DIR/scripts/ralph/locks"

    run_ralph_locks status
    assert_success
    assert_output_contains "No active locks"
}

@test "release command with story ID as positional argument" {
    create_lock_fixture "US-005" "test-owner"

    # Some scripts accept positional story ID
    run_ralph_locks release US-005
    # This should work or fail gracefully
    # Implementation may vary
}

@test "handles special characters in owner name" {
    create_lock_fixture "US-001" "owner-with-special#chars_test"

    run_ralph_locks status
    assert_success
    assert_output_contains "US-001"
}

@test "handles unicode in status display" {
    create_lock_fixture "US-001" "test-owner"

    run_ralph_locks status
    assert_success
    # Should contain unicode box characters
    assert_output_contains "═"
}
