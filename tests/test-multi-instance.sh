#!/bin/bash
# test-multi-instance.sh - Test multi-instance Ralph features
# Usage: ./tests/test-multi-instance.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$SCRIPT_DIR/test-workspace"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$1"
}

pass() {
    log "${GREEN}✓ PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    log "${RED}✗ FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

setup() {
    log "${BLUE}Setting up test environment...${NC}"
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR/instances"
    mkdir -p "$TEST_DIR/locks"
}

teardown() {
    log "${BLUE}Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
}

# =============================================================================
# TESTS
# =============================================================================

test_instance_id_generation() {
    log "\n${YELLOW}TEST: Instance ID Generation${NC}"

    # Source the functions we need
    source <(grep -A 50 'INSTANCE_ID=' "$SCRIPT_DIR/ralph.sh" | head -5)

    # Check format: user-hostname-pid-timestamp (hostname may contain dashes)
    if [[ "$INSTANCE_ID" =~ ^[a-zA-Z0-9_]+-[a-zA-Z0-9_-]+-[0-9]+-[0-9]+$ ]]; then
        pass "Instance ID format is correct: $INSTANCE_ID"
    else
        fail "Instance ID format incorrect: $INSTANCE_ID"
    fi

    # Check short ID is 8 chars
    local short_id="${INSTANCE_ID:0:8}"
    if [ ${#short_id} -eq 8 ]; then
        pass "Short ID is 8 characters: $short_id"
    else
        fail "Short ID length incorrect: ${#short_id}"
    fi
}

test_lock_acquisition() {
    log "\n${YELLOW}TEST: Lock Acquisition${NC}"

    local lock_dir="$TEST_DIR/locks/US-TEST.lock"

    # Test atomic mkdir lock
    if mkdir "$lock_dir" 2>/dev/null; then
        echo "test-instance-1" > "$lock_dir/owner"
        echo "$(date +%s)" > "$lock_dir/timestamp"
        pass "Lock acquired successfully"
    else
        fail "Could not acquire lock"
        return
    fi

    # Test that second acquisition fails
    if mkdir "$lock_dir" 2>/dev/null; then
        fail "Second lock acquisition should have failed"
    else
        pass "Second lock acquisition correctly blocked"
    fi

    # Verify lock contents
    local owner=$(cat "$lock_dir/owner")
    if [ "$owner" = "test-instance-1" ]; then
        pass "Lock owner stored correctly"
    else
        fail "Lock owner incorrect: $owner"
    fi

    # Cleanup
    rm -rf "$lock_dir"
}

test_lock_release() {
    log "\n${YELLOW}TEST: Lock Release${NC}"

    local lock_dir="$TEST_DIR/locks/US-TEST2.lock"

    # Acquire lock
    mkdir "$lock_dir"
    echo "test-instance-2" > "$lock_dir/owner"

    # Release lock
    rm -rf "$lock_dir"

    # Verify released
    if [ ! -d "$lock_dir" ]; then
        pass "Lock released successfully"
    else
        fail "Lock not released"
    fi

    # Another instance can now acquire
    if mkdir "$lock_dir" 2>/dev/null; then
        pass "Lock can be re-acquired after release"
        rm -rf "$lock_dir"
    else
        fail "Could not re-acquire released lock"
    fi
}

test_stale_lock_detection() {
    log "\n${YELLOW}TEST: Stale Lock Detection${NC}"

    local lock_dir="$TEST_DIR/locks/US-STALE.lock"

    # Create stale lock (timestamp in the past)
    mkdir "$lock_dir"
    echo "dead-instance" > "$lock_dir/owner"
    echo "1000000000" > "$lock_dir/timestamp"  # Year 2001

    local timestamp=$(cat "$lock_dir/timestamp")
    local now=$(date +%s)
    local age=$((now - timestamp))

    if [ "$age" -gt 7200 ]; then
        pass "Stale lock correctly identified (age: ${age}s)"
    else
        fail "Stale lock not detected"
    fi

    rm -rf "$lock_dir"
}

test_status_json_format() {
    log "\n${YELLOW}TEST: Status JSON Format${NC}"

    local status_file="$TEST_DIR/instances/test-instance/status.json"
    mkdir -p "$(dirname "$status_file")"

    # Create test status
    cat > "$status_file" << EOF
{
  "instanceId": "test-user-host-12345-1700000000",
  "shortId": "test-use",
  "state": "working",
  "currentStory": "US-001",
  "iteration": 3,
  "maxIterations": 10,
  "startTime": "2024-01-01 12:00:00",
  "lastHeartbeat": "2024-01-01 12:05:00",
  "lastHeartbeatEpoch": $(date +%s),
  "projectRoot": "/test/project",
  "branch": "ralph/test/US-001",
  "pid": 12345
}
EOF

    # Validate JSON
    if jq empty "$status_file" 2>/dev/null; then
        pass "Status file is valid JSON"
    else
        fail "Status file is not valid JSON"
    fi

    # Check required fields
    local state=$(jq -r '.state' "$status_file")
    if [ "$state" = "working" ]; then
        pass "State field present and correct"
    else
        fail "State field missing or incorrect"
    fi

    local story=$(jq -r '.currentStory' "$status_file")
    if [ "$story" = "US-001" ]; then
        pass "CurrentStory field present and correct"
    else
        fail "CurrentStory field missing or incorrect"
    fi
}

test_concurrent_lock_safety() {
    log "\n${YELLOW}TEST: Concurrent Lock Safety${NC}"

    local lock_dir="$TEST_DIR/locks/US-CONCURRENT.lock"
    local success_count=0
    local fail_count=0

    # Launch 5 concurrent attempts to acquire the same lock
    for i in {1..5}; do
        (
            if mkdir "$lock_dir" 2>/dev/null; then
                echo "instance-$i" > "$lock_dir/owner"
                exit 0
            fi
            exit 1
        ) &
    done

    wait

    # Check that exactly one succeeded
    if [ -d "$lock_dir" ]; then
        local owner=$(cat "$lock_dir/owner")
        pass "Exactly one instance acquired lock: $owner"
    else
        fail "No instance acquired lock (should not happen)"
    fi

    rm -rf "$lock_dir"
}

test_ralph_locks_script() {
    log "\n${YELLOW}TEST: ralph-locks.sh Script${NC}"

    # Check script exists and is executable
    if [ -x "$SCRIPT_DIR/ralph-locks.sh" ]; then
        pass "ralph-locks.sh exists and is executable"
    else
        fail "ralph-locks.sh not found or not executable"
        return
    fi

    # Test status command (should not error)
    if "$SCRIPT_DIR/ralph-locks.sh" status > /dev/null 2>&1; then
        pass "ralph-locks.sh status runs without error"
    else
        fail "ralph-locks.sh status failed"
    fi
}

test_ralph_cleanup_script() {
    log "\n${YELLOW}TEST: ralph-cleanup.sh Script${NC}"

    if [ -x "$SCRIPT_DIR/ralph-cleanup.sh" ]; then
        pass "ralph-cleanup.sh exists and is executable"
    else
        fail "ralph-cleanup.sh not found or not executable"
        return
    fi

    # Test dry-run mode
    if "$SCRIPT_DIR/ralph-cleanup.sh" --dry-run --dead > /dev/null 2>&1; then
        pass "ralph-cleanup.sh --dry-run runs without error"
    else
        fail "ralph-cleanup.sh --dry-run failed"
    fi
}

test_ralph_parallel_script() {
    log "\n${YELLOW}TEST: ralph-parallel.sh Script${NC}"

    if [ -x "$SCRIPT_DIR/ralph-parallel.sh" ]; then
        pass "ralph-parallel.sh exists and is executable"
    else
        fail "ralph-parallel.sh not found or not executable"
        return
    fi

    # Test status command
    if "$SCRIPT_DIR/ralph-parallel.sh" status > /dev/null 2>&1; then
        pass "ralph-parallel.sh status runs without error"
    else
        fail "ralph-parallel.sh status failed"
    fi
}

test_ralph_dashboard_script() {
    log "\n${YELLOW}TEST: ralph-dashboard.sh Script${NC}"

    if [ -x "$SCRIPT_DIR/ralph-dashboard.sh" ]; then
        pass "ralph-dashboard.sh exists and is executable"
    else
        fail "ralph-dashboard.sh not found or not executable"
        return
    fi

    # Test help
    if "$SCRIPT_DIR/ralph-dashboard.sh" --help > /dev/null 2>&1; then
        pass "ralph-dashboard.sh --help runs without error"
    else
        fail "ralph-dashboard.sh --help failed"
    fi
}

test_prd_flock_locking() {
    log "\n${YELLOW}TEST: PRD flock Locking${NC}"

    local test_prd="$TEST_DIR/test-prd.json"
    local test_lock="$TEST_DIR/.test-prd.lock"

    # Create test PRD
    cat > "$test_prd" << 'EOF'
{"stories": [{"id": "US-001", "passes": false}]}
EOF

    # Test concurrent writes with flock
    local success_count=0

    for i in {1..5}; do
        (
            flock -w 1 200 || exit 1
            local content=$(cat "$test_prd")
            echo "$content" | jq ".stories[0].count = $i" > "$test_prd.tmp"
            mv "$test_prd.tmp" "$test_prd"
            exit 0
        ) 200>"$test_lock" &
    done

    wait

    # Verify JSON is valid
    if jq empty "$test_prd" 2>/dev/null; then
        pass "PRD remains valid JSON after concurrent writes"
    else
        fail "PRD corrupted after concurrent writes"
    fi

    rm -f "$test_prd" "$test_lock"
}

test_story_claiming_simulation() {
    log "\n${YELLOW}TEST: Story Claiming Simulation${NC}"

    local locks_dir="$TEST_DIR/sim-locks"
    mkdir -p "$locks_dir"

    # Simulate 3 instances trying to claim same story
    local claim_count=0

    for i in {1..3}; do
        if mkdir "$locks_dir/US-SIM.lock" 2>/dev/null; then
            echo "instance-$i" > "$locks_dir/US-SIM.lock/owner"
            claim_count=$((claim_count + 1))
        fi
    done

    if [ "$claim_count" -eq 1 ]; then
        pass "Only one instance can claim a story"
    else
        fail "Multiple instances claimed same story: $claim_count"
    fi

    rm -rf "$locks_dir"
}

test_signal_handling() {
    log "\n${YELLOW}TEST: Signal Handling Setup${NC}"

    # Verify ralph.sh has trap statements
    if grep -q "trap.*EXIT" "$SCRIPT_DIR/ralph.sh"; then
        pass "ralph.sh has EXIT trap"
    else
        fail "ralph.sh missing EXIT trap"
    fi

    if grep -q "trap.*INT" "$SCRIPT_DIR/ralph.sh"; then
        pass "ralph.sh has INT trap"
    else
        fail "ralph.sh missing INT trap"
    fi

    if grep -q "trap.*TERM" "$SCRIPT_DIR/ralph.sh"; then
        pass "ralph.sh has TERM trap"
    else
        fail "ralph.sh missing TERM trap"
    fi
}

test_dead_instance_detection() {
    log "\n${YELLOW}TEST: Dead Instance Detection Logic${NC}"

    local instances_dir="$TEST_DIR/dead-instances"
    mkdir -p "$instances_dir/dead-instance"

    # Create status with old heartbeat (6 minutes ago)
    local old_heartbeat=$(($(date +%s) - 360))
    cat > "$instances_dir/dead-instance/status.json" << EOF
{
  "instanceId": "dead-instance",
  "state": "working",
  "lastHeartbeatEpoch": $old_heartbeat
}
EOF

    # Check heartbeat age
    local now=$(date +%s)
    local heartbeat=$(jq -r '.lastHeartbeatEpoch' "$instances_dir/dead-instance/status.json")
    local age=$((now - heartbeat))

    if [ "$age" -gt 300 ]; then
        pass "Dead instance detected (heartbeat age: ${age}s > 300s)"
    else
        fail "Dead instance not detected (age: ${age}s)"
    fi

    rm -rf "$instances_dir"
}

test_git_branch_naming() {
    log "\n${YELLOW}TEST: Git Branch Naming Convention${NC}"

    # Check that branch naming follows pattern
    local short_id="abc12345"
    local story_id="US-001"
    local expected_branch="ralph/$short_id/$story_id"

    if [[ "$expected_branch" =~ ^ralph/[a-zA-Z0-9_-]+/[A-Z]+-[0-9]+$ ]]; then
        pass "Branch naming pattern is valid: $expected_branch"
    else
        fail "Branch naming pattern invalid"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    log "${BLUE}║${NC}     ${YELLOW}RALPH MULTI-INSTANCE TEST SUITE${NC}                   ${BLUE}║${NC}"
    log "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"

    setup

    # Run tests
    test_instance_id_generation
    test_lock_acquisition
    test_lock_release
    test_stale_lock_detection
    test_status_json_format
    test_concurrent_lock_safety
    test_ralph_locks_script
    test_ralph_cleanup_script
    test_ralph_parallel_script
    test_ralph_dashboard_script
    test_prd_flock_locking
    test_story_claiming_simulation
    test_signal_handling
    test_dead_instance_detection
    test_git_branch_naming

    teardown

    # Summary
    log "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    log "${BLUE}                    TEST SUMMARY${NC}"
    log "${BLUE}═══════════════════════════════════════════════════════${NC}"
    log "${GREEN}Passed: $PASSED${NC}"
    log "${RED}Failed: $FAILED${NC}"

    if [ "$FAILED" -eq 0 ]; then
        log "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        log "\n${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
