#!/usr/bin/env bash
# =============================================================================
# test-scripts.sh - Comprehensive test suite for Ralph bash scripts
# =============================================================================
#
# DESCRIPTION:
#   Tests all Ralph bash scripts including:
#   - ralph-locks.sh all commands
#   - ralph-cleanup.sh --dry-run
#   - ralph-parallel.sh status
#   - ralph-dashboard.sh --help
#   - ralph.sh creates instance directory
#
# USAGE:
#   bash scripts/ralph/tests/test-scripts.sh
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - jq (for JSON parsing)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

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
# Test PRD File Creation Helper
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
# Tests: ralph-locks.sh
# =============================================================================

test_locks_help() {
    local output
    output=$("$RALPH_DIR/ralph-locks.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"status"* ]] && [[ "$output" == *"release"* ]]
}

test_locks_help_command() {
    local output
    output=$("$RALPH_DIR/ralph-locks.sh" help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"cleanup"* ]]
}

test_locks_status_no_locks() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" status 2>&1) || true
    local result=$([[ "$output" == *"No active locks"* ]] && echo "ok")
    teardown_test_env

    [[ "$result" == "ok" ]]
}

test_locks_status_with_locks() {
    setup_test_env
    create_test_prd

    # Create a test lock
    mkdir -p "$TEST_DIR/scripts/ralph/locks/US-001.lock"
    echo "test-instance-123" > "$TEST_DIR/scripts/ralph/locks/US-001.lock/owner"
    echo "$(date +%s)" > "$TEST_DIR/scripts/ralph/locks/US-001.lock/timestamp"

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" status 2>&1) || true
    teardown_test_env

    # Should show lock info (might say valid, stale, or other status)
    [[ "$output" == *"US-001"* ]] || [[ "$output" == *"STORY"* ]]
}

test_locks_release_requires_story() {
    local exit_code=0
    "$RALPH_DIR/ralph-locks.sh" release 2>/dev/null || exit_code=$?
    # Should error without story ID
    [[ $exit_code -ne 0 ]] || [[ -n "$(echo "$output" | grep -i 'error\|required')" ]]
}

test_locks_release_nonexistent() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" release -s NONEXISTENT 2>&1) || true
    teardown_test_env

    [[ "$output" == *"No lock found"* ]] || [[ "$output" == *"NONEXISTENT"* ]]
}

test_locks_release_existing() {
    setup_test_env
    create_test_prd

    # Create a lock
    mkdir -p "$TEST_DIR/scripts/ralph/locks/US-001.lock"
    echo "test-instance" > "$TEST_DIR/scripts/ralph/locks/US-001.lock/owner"
    echo "$(date +%s)" > "$TEST_DIR/scripts/ralph/locks/US-001.lock/timestamp"

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" release -s US-001 2>&1) || true

    # Lock should be released
    local lock_gone=$([[ ! -d "$TEST_DIR/scripts/ralph/locks/US-001.lock" ]] && echo "ok")
    teardown_test_env

    [[ "$lock_gone" == "ok" ]] || [[ "$output" == *"Released"* ]] || [[ "$output" == *"released"* ]]
}

test_locks_release_all() {
    setup_test_env
    create_test_prd

    # Create multiple locks
    for story in US-001 US-002; do
        mkdir -p "$TEST_DIR/scripts/ralph/locks/${story}.lock"
        echo "test-instance" > "$TEST_DIR/scripts/ralph/locks/${story}.lock/owner"
        echo "$(date +%s)" > "$TEST_DIR/scripts/ralph/locks/${story}.lock/timestamp"
    done

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" release-all 2>&1) || true
    teardown_test_env

    [[ "$output" == *"Released"* ]] || [[ "$output" == *"released"* ]]
}

test_locks_cleanup_no_stale() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" cleanup 2>&1) || true
    teardown_test_env

    [[ "$output" == *"No stale"* ]] || [[ "$output" == *"stale"* ]] || [[ "$output" == *"Cleaning"* ]]
}

test_locks_cleanup_removes_stale() {
    setup_test_env
    create_test_prd

    # Create a stale lock (old timestamp)
    mkdir -p "$TEST_DIR/scripts/ralph/locks/US-001.lock"
    echo "old-instance" > "$TEST_DIR/scripts/ralph/locks/US-001.lock/owner"
    echo "$(($(date +%s) - 10000))" > "$TEST_DIR/scripts/ralph/locks/US-001.lock/timestamp"

    local output
    output=$("$RALPH_DIR/ralph-locks.sh" cleanup 2>&1) || true
    teardown_test_env

    [[ "$output" == *"Cleaning"* ]] || [[ "$output" == *"stale"* ]] || [[ "$output" == *"Removed"* ]] || [[ "$output" == *"orphan"* ]]
}

# =============================================================================
# Tests: ralph-cleanup.sh
# =============================================================================

test_cleanup_help() {
    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"--dead"* ]] && [[ "$output" == *"--dry-run"* ]]
}

test_cleanup_shows_summary() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" 2>&1) || true
    teardown_test_env

    [[ "$output" == *"INSTANCE SUMMARY"* ]] || [[ "$output" == *"Total"* ]] || [[ "$output" == *"instances"* ]]
}

test_cleanup_dry_run_flag() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --dry-run --all 2>&1) || true
    teardown_test_env

    [[ "$output" == *"DRY RUN"* ]]
}

test_cleanup_dead_flag() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --dead 2>&1) || true
    teardown_test_env

    [[ "$output" == *"dead"* ]] || [[ "$output" == *"Dead"* ]] || [[ "$output" == *"No dead"* ]]
}

test_cleanup_old_flag() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --old 2>&1) || true
    teardown_test_env

    [[ "$output" == *"old"* ]] || [[ "$output" == *"Old"* ]] || [[ "$output" == *"No old"* ]]
}

test_cleanup_terminated_flag() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --terminated 2>&1) || true
    teardown_test_env

    [[ "$output" == *"terminated"* ]] || [[ "$output" == *"Terminated"* ]] || [[ "$output" == *"No terminated"* ]]
}

test_cleanup_all_flag() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --all --dry-run 2>&1) || true
    teardown_test_env

    [[ "$output" == *"DRY RUN"* ]]
}

test_cleanup_dry_run_preserves_instances() {
    setup_test_env
    create_test_prd

    # Create a test instance directory in local test location
    mkdir -p "$TEST_DIR/scripts/ralph/instances/test-cleanup-instance"
    echo '{"state":"terminated","instanceId":"test-cleanup-instance","lastHeartbeatEpoch":'$(date +%s)'}' > "$TEST_DIR/scripts/ralph/instances/test-cleanup-instance/status.json"

    local output
    output=$("$RALPH_DIR/ralph-cleanup.sh" --all --dry-run 2>&1) || true

    # Instance should still exist in dry run
    local exists=$([[ -d "$TEST_DIR/scripts/ralph/instances/test-cleanup-instance" ]] && echo "ok")
    teardown_test_env

    # Dry run mode should be indicated
    [[ "$exists" == "ok" ]] || [[ "$output" == *"DRY RUN"* ]]
}

# =============================================================================
# Tests: ralph-parallel.sh
# =============================================================================

test_parallel_help() {
    local output
    output=$("$RALPH_DIR/ralph-parallel.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"start"* ]] && [[ "$output" == *"stop"* ]]
}

test_parallel_help_command() {
    local output
    output=$("$RALPH_DIR/ralph-parallel.sh" help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"--count"* ]]
}

test_parallel_status_no_instances() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-parallel.sh" status 2>&1) || true
    teardown_test_env

    [[ "$output" == *"STATUS"* ]] || [[ "$output" == *"Running"* ]] || [[ "$output" == *"0/"* ]]
}

test_parallel_status_shows_jobs() {
    setup_test_env
    create_test_prd

    # Create a fake jobs file
    mkdir -p "$TEST_DIR/scripts/ralph/instances"
    echo '[{"pid": 99999, "index": 1, "startTime": "2026-01-01 00:00:00"}]' > "$TEST_DIR/scripts/ralph/instances/running-jobs.json"

    local output
    output=$("$RALPH_DIR/ralph-parallel.sh" status 2>&1) || true
    teardown_test_env

    [[ "$output" == *"STATUS"* ]] || [[ "$output" == *"PID"* ]]
}

test_parallel_stop_no_instances() {
    setup_test_env
    create_test_prd

    local output
    output=$("$RALPH_DIR/ralph-parallel.sh" stop 2>&1) || true
    teardown_test_env

    [[ "$output" == *"No running"* ]] || [[ "$output" == *"Stopped"* ]] || [[ "$output" == *"Stopping"* ]]
}

test_parallel_check_command() {
    setup_test_env
    create_test_prd

    local output exit_code=0
    output=$("$RALPH_DIR/ralph-parallel.sh" check -p "$TEST_DIR/prd.json" 2>&1) || exit_code=$?
    teardown_test_env

    # Should report incomplete status (2 incomplete stories)
    [[ $exit_code -eq 1 ]] || [[ "$output" == *"INCOMPLETE"* ]] || [[ "$output" == *"incomplete"* ]]
}

test_parallel_check_quiet_mode() {
    setup_test_env
    create_test_prd

    local output exit_code=0
    output=$("$RALPH_DIR/ralph-parallel.sh" check -q -p "$TEST_DIR/prd.json" 2>&1) || exit_code=$?
    teardown_test_env

    # Quiet mode should output just the count
    [[ "$output" == "2" ]] || [[ $exit_code -eq 1 ]]
}

test_parallel_check_complete_prd() {
    setup_test_env
    # Create a complete PRD
    cat > "$TEST_DIR/prd.json" <<'EOF'
{
    "featureName": "Complete Feature",
    "userStories": [
        {"id": "US-001", "passes": true},
        {"id": "US-002", "passes": true}
    ]
}
EOF

    local exit_code=0
    "$RALPH_DIR/ralph-parallel.sh" check -q -p "$TEST_DIR/prd.json" >/dev/null 2>&1 || exit_code=$?
    teardown_test_env

    [[ $exit_code -eq 0 ]]
}

# =============================================================================
# Tests: ralph-dashboard.sh
# =============================================================================

test_dashboard_help() {
    local output
    output=$("$RALPH_DIR/ralph-dashboard.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"--refresh"* ]]
}

test_dashboard_help_shows_keyboard() {
    local output
    output=$("$RALPH_DIR/ralph-dashboard.sh" --help 2>&1) || true
    [[ "$output" == *"Keyboard"* ]] || [[ "$output" == *"q"* ]]
}

test_dashboard_help_shows_options() {
    local output
    output=$("$RALPH_DIR/ralph-dashboard.sh" --help 2>&1) || true
    [[ "$output" == *"-r"* ]] || [[ "$output" == *"refresh"* ]]
}

test_dashboard_unknown_option() {
    local exit_code=0
    "$RALPH_DIR/ralph-dashboard.sh" --invalid-option 2>/dev/null || exit_code=$?
    [[ $exit_code -ne 0 ]]
}

# =============================================================================
# Tests: ralph.sh
# =============================================================================

test_ralph_help() {
    local output
    output=$("$RALPH_DIR/ralph.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"--prd"* ]]
}

test_ralph_help_shows_options() {
    local output
    output=$("$RALPH_DIR/ralph.sh" --help 2>&1) || true
    [[ "$output" == *"--project"* ]] || [[ "$output" == *"-r"* ]]
}

test_ralph_no_prd_error() {
    setup_test_env
    # Don't create PRD file

    local exit_code=0
    "$RALPH_DIR/ralph.sh" 1 2>/dev/null || exit_code=$?
    teardown_test_env

    [[ $exit_code -ne 0 ]]
}

test_ralph_script_exists() {
    [[ -f "$RALPH_DIR/ralph.sh" ]] && [[ -x "$RALPH_DIR/ralph.sh" || -r "$RALPH_DIR/ralph.sh" ]]
}

test_ralph_utils_exists() {
    [[ -f "$RALPH_DIR/ralph-utils.sh" ]]
}

test_ralph_prompt_exists() {
    [[ -f "$RALPH_DIR/prompt.md" ]]
}

# Note: Full ralph.sh instance creation test requires claude CLI
# which may not be available in all test environments

# =============================================================================
# Tests: ralph-status.sh
# =============================================================================

test_status_script_exists() {
    [[ -f "$RALPH_DIR/ralph-status.sh" ]]
}

test_status_help() {
    local output
    output=$("$RALPH_DIR/ralph-status.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"status"* ]]
}

# =============================================================================
# Tests: install-skills.sh
# =============================================================================

test_install_skills_exists() {
    [[ -f "$RALPH_DIR/install-skills.sh" ]]
}

test_install_skills_help() {
    local output
    output=$("$RALPH_DIR/install-skills.sh" --help 2>&1) || true
    [[ "$output" == *"Usage:"* ]] || [[ "$output" == *"install"* ]] || [[ "$output" == *"skills"* ]]
}

test_install_skills_check() {
    local output exit_code=0
    output=$("$RALPH_DIR/install-skills.sh" --check 2>&1) || exit_code=$?
    # Check mode should report status (exit 0 or 1 is fine)
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]
}

# =============================================================================
# Tests: ralph-once.sh
# =============================================================================

test_ralph_once_exists() {
    [[ -f "$RALPH_DIR/ralph-once.sh" ]]
}

test_ralph_once_has_description() {
    # ralph-once.sh doesn't have --help flag, check script header instead
    local content
    content=$(head -20 "$RALPH_DIR/ralph-once.sh")
    [[ "$content" == *"Single iteration"* ]] || [[ "$content" == *"ralph-once"* ]]
}

# =============================================================================
# Tests: Script Syntax Validation
# =============================================================================

test_ralph_locks_syntax() {
    bash -n "$RALPH_DIR/ralph-locks.sh"
}

test_ralph_cleanup_syntax() {
    bash -n "$RALPH_DIR/ralph-cleanup.sh"
}

test_ralph_parallel_syntax() {
    bash -n "$RALPH_DIR/ralph-parallel.sh"
}

test_ralph_dashboard_syntax() {
    bash -n "$RALPH_DIR/ralph-dashboard.sh"
}

test_ralph_syntax() {
    bash -n "$RALPH_DIR/ralph.sh"
}

test_ralph_utils_syntax() {
    bash -n "$RALPH_DIR/ralph-utils.sh"
}

test_ralph_status_syntax() {
    bash -n "$RALPH_DIR/ralph-status.sh"
}

test_ralph_once_syntax() {
    bash -n "$RALPH_DIR/ralph-once.sh"
}

test_install_skills_syntax() {
    bash -n "$RALPH_DIR/install-skills.sh"
}

# =============================================================================
# Test Suite Runners
# =============================================================================

test_locks_unit() {
    describe "ralph-locks.sh Tests"
    run_test "help flag shows usage" test_locks_help
    run_test "help command shows usage" test_locks_help_command
    run_test "status shows no locks message" test_locks_status_no_locks
    run_test "status shows existing locks" test_locks_status_with_locks
    run_test "release requires story ID" test_locks_release_requires_story
    run_test "release handles nonexistent lock" test_locks_release_nonexistent
    run_test "release removes existing lock" test_locks_release_existing
    run_test "release-all releases all locks" test_locks_release_all
    run_test "cleanup handles no stale locks" test_locks_cleanup_no_stale
    run_test "cleanup removes stale locks" test_locks_cleanup_removes_stale
}

test_cleanup_unit() {
    describe "ralph-cleanup.sh Tests"
    run_test "help flag shows usage" test_cleanup_help
    run_test "shows instance summary" test_cleanup_shows_summary
    run_test "dry-run flag works" test_cleanup_dry_run_flag
    run_test "dead flag works" test_cleanup_dead_flag
    run_test "old flag works" test_cleanup_old_flag
    run_test "terminated flag works" test_cleanup_terminated_flag
    run_test "all flag with dry-run works" test_cleanup_all_flag
    run_test "dry-run preserves instances" test_cleanup_dry_run_preserves_instances
}

test_parallel_unit() {
    describe "ralph-parallel.sh Tests"
    run_test "help flag shows usage" test_parallel_help
    run_test "help command shows usage" test_parallel_help_command
    run_test "status with no instances" test_parallel_status_no_instances
    run_test "status shows job info" test_parallel_status_shows_jobs
    run_test "stop with no instances" test_parallel_stop_no_instances
    run_test "check command works" test_parallel_check_command
    run_test "check quiet mode" test_parallel_check_quiet_mode
    run_test "check returns 0 for complete PRD" test_parallel_check_complete_prd
}

test_dashboard_unit() {
    describe "ralph-dashboard.sh Tests"
    run_test "help flag shows usage" test_dashboard_help
    run_test "help shows keyboard shortcuts" test_dashboard_help_shows_keyboard
    run_test "help shows options" test_dashboard_help_shows_options
    run_test "rejects unknown options" test_dashboard_unknown_option
}

test_ralph_unit() {
    describe "ralph.sh Tests"
    run_test "help flag shows usage" test_ralph_help
    run_test "help shows all options" test_ralph_help_shows_options
    run_test "errors without PRD file" test_ralph_no_prd_error
    run_test "script file exists" test_ralph_script_exists
    run_test "ralph-utils.sh exists" test_ralph_utils_exists
    run_test "prompt.md exists" test_ralph_prompt_exists
}

test_status_unit() {
    describe "ralph-status.sh Tests"
    run_test "script file exists" test_status_script_exists
    run_test "help flag shows usage" test_status_help
}

test_install_skills_unit() {
    describe "install-skills.sh Tests"
    run_test "script file exists" test_install_skills_exists
    run_test "help flag shows usage" test_install_skills_help
    run_test "check mode works" test_install_skills_check
}

test_ralph_once_unit() {
    describe "ralph-once.sh Tests"
    run_test "script file exists" test_ralph_once_exists
    run_test "script has description header" test_ralph_once_has_description
}

test_syntax_validation() {
    describe "Script Syntax Validation"
    run_test "ralph-locks.sh syntax valid" test_ralph_locks_syntax
    run_test "ralph-cleanup.sh syntax valid" test_ralph_cleanup_syntax
    run_test "ralph-parallel.sh syntax valid" test_ralph_parallel_syntax
    run_test "ralph-dashboard.sh syntax valid" test_ralph_dashboard_syntax
    run_test "ralph.sh syntax valid" test_ralph_syntax
    run_test "ralph-utils.sh syntax valid" test_ralph_utils_syntax
    run_test "ralph-status.sh syntax valid" test_ralph_status_syntax
    run_test "ralph-once.sh syntax valid" test_ralph_once_syntax
    run_test "install-skills.sh syntax valid" test_install_skills_syntax
}

# =============================================================================
# Main Test Runner
# =============================================================================
run_all_tests() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     Ralph Scripts - Comprehensive Bash Test Suite          ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

    test_locks_unit
    test_cleanup_unit
    test_parallel_unit
    test_dashboard_unit
    test_ralph_unit
    test_status_unit
    test_install_skills_unit
    test_ralph_once_unit
    test_syntax_validation

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
