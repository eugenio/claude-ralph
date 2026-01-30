#!/bin/bash

# Ralph Loop - Comprehensive Test Suite
# Tests all scripts: supervisor, status, stop, setup, and aliases
# Run with: bash test-supervisor.sh

# ============================================================================
# Test Framework
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")/scripts"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

setup_test_env() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.claude"
    cd "$TEST_DIR" || exit 1
}

teardown_test_env() {
    cd "$SCRIPT_DIR" || exit 1
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
    TEST_DIR=""
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

    # Run test in subshell to isolate failures
    if ( set -e; $test_func ); then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}PASS${NC}"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

# ============================================================================
# Unit Tests: setup-ralph-loop.sh
# ============================================================================
test_setup_help() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/setup-ralph-loop.sh" --help 2>&1)
    teardown_test_env
    [[ "$output" == *"USAGE:"* ]] && [[ "$output" == *"--max-iterations"* ]] && [[ "$output" == *"--completion-promise"* ]]
}

test_setup_requires_prompt() {
    setup_test_env
    local exit_code=0
    "$SCRIPTS_DIR/setup-ralph-loop.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -ne 0 ]]
}

test_setup_creates_state_file() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "Test prompt" > /dev/null 2>&1
    local result=$([[ -f ".claude/ralph-loop.local.md" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_setup_state_file_contains_prompt() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "Build a REST API" > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"Build a REST API"* ]]
}

test_setup_state_file_has_frontmatter() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "Test" > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"---"* ]] && [[ "$content" == *"iteration: 1"* ]] && [[ "$content" == *"active: true"* ]]
}

test_setup_max_iterations() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" --max-iterations 50 "Test" > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"max_iterations: 50"* ]]
}

test_setup_completion_promise() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" --completion-promise "DONE" "Test" > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"completion_promise:"* ]] && [[ "$content" == *"DONE"* ]]
}

test_setup_multiword_prompt() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" Build a REST API for todos > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"Build a REST API for todos"* ]]
}

test_setup_invalid_max_iterations() {
    setup_test_env
    local exit_code=0
    "$SCRIPTS_DIR/setup-ralph-loop.sh" --max-iterations abc "Test" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -ne 0 ]]
}

test_setup_missing_max_iterations_value() {
    setup_test_env
    local exit_code=0
    "$SCRIPTS_DIR/setup-ralph-loop.sh" --max-iterations > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -ne 0 ]]
}

test_setup_missing_promise_value() {
    setup_test_env
    local exit_code=0
    "$SCRIPTS_DIR/setup-ralph-loop.sh" --completion-promise > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -ne 0 ]]
}

test_setup_output_message() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/setup-ralph-loop.sh" "Test" 2>&1)
    teardown_test_env
    [[ "$output" == *"Ralph loop activated"* ]]
}

test_setup_unit() {
    describe "Unit Tests: setup-ralph-loop.sh"
    run_test "should display help with --help" test_setup_help
    run_test "should require prompt argument" test_setup_requires_prompt
    run_test "should create state file" test_setup_creates_state_file
    run_test "should include prompt in state file" test_setup_state_file_contains_prompt
    run_test "should create YAML frontmatter" test_setup_state_file_has_frontmatter
    run_test "should accept --max-iterations" test_setup_max_iterations
    run_test "should accept --completion-promise" test_setup_completion_promise
    run_test "should handle multi-word prompts" test_setup_multiword_prompt
    run_test "should reject invalid --max-iterations" test_setup_invalid_max_iterations
    run_test "should require value for --max-iterations" test_setup_missing_max_iterations_value
    run_test "should require value for --completion-promise" test_setup_missing_promise_value
    run_test "should output activation message" test_setup_output_message
}

# ============================================================================
# Unit Tests: ralph-status.sh
# ============================================================================
test_status_help() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" --help 2>&1)
    teardown_test_env
    [[ "$output" == *"Usage:"* ]] && [[ "$output" == *"--clean"* ]]
}

test_status_no_supervisor() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"No Ralph supervisor or loop is currently running"* ]]
}

test_status_detects_loop_state() {
    setup_test_env
    cat > .claude/ralph-loop.local.md << 'EOF'
---
active: true
iteration: 99
max_iterations: 0
completion_promise: null
started_at: "2026-01-30T12:00:00Z"
---
Test loop prompt
EOF
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"In-Session Loop State"* ]] && [[ "$output" == *"99"* ]]
}

test_status_shows_stale_loop_warning() {
    setup_test_env
    cat > .claude/ralph-loop.local.md << 'EOF'
---
active: true
iteration: 5
max_iterations: 0
completion_promise: null
started_at: "2026-01-30T12:00:00Z"
---
Test prompt
EOF
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"stale"* ]]
}

test_status_detects_stale() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"NOT RUNNING"* ]] && [[ "$output" == *"stale"* ]]
}

test_status_shows_cleanup_tip() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"--clean"* ]]
}

test_status_displays_iteration() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 42, "max_iterations": 100}
EOF
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"42"* ]]
}

test_status_unit() {
    describe "Unit Tests: ralph-status.sh"
    run_test "should display help with --help" test_status_help
    run_test "should show 'no supervisor or loop' when no state file" test_status_no_supervisor
    run_test "should detect stale state file" test_status_detects_stale
    run_test "should show cleanup tip for stale files" test_status_shows_cleanup_tip
    run_test "should display iteration count" test_status_displays_iteration
    run_test "should detect in-session loop state file" test_status_detects_loop_state
    run_test "should show stale warning for loop state" test_status_shows_stale_loop_warning
}

# ============================================================================
# Unit Tests: Cleanup Functionality
# ============================================================================
test_cleanup_removes_state() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local result=$([[ ! -f ".claude/ralph-supervisor.local.json" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_cleanup_removes_pid() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    echo "999999" > .claude/ralph-supervisor.pid
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local result=$([[ ! -f ".claude/ralph-supervisor.pid" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_cleanup_removes_claude_pid() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    echo "999998" > .claude/ralph-supervisor-claude.pid
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local result=$([[ ! -f ".claude/ralph-supervisor-claude.pid" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_cleanup_preserves_log() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    echo "test log" > .claude/ralph-supervisor.log
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local result=$([[ -f ".claude/ralph-supervisor.log" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_cleanup_exit_code() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    local exit_code=1
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1 && exit_code=0
    teardown_test_env
    [[ $exit_code -eq 0 ]]
}

test_cleanup_removes_loop_state() {
    setup_test_env
    cat > .claude/ralph-loop.local.md << 'EOF'
---
active: true
iteration: 5
max_iterations: 0
completion_promise: null
started_at: "2026-01-30T12:00:00Z"
---
Test prompt
EOF
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local result=$([[ ! -f ".claude/ralph-loop.local.md" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_cleanup_removes_both_state_types() {
    setup_test_env
    # Create supervisor state
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    # Create in-session loop state
    cat > .claude/ralph-loop.local.md << 'EOF'
---
active: true
iteration: 5
max_iterations: 0
completion_promise: null
started_at: "2026-01-30T12:00:00Z"
---
Test prompt
EOF
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local result=$([[ ! -f ".claude/ralph-supervisor.local.json" ]] && [[ ! -f ".claude/ralph-loop.local.md" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_cleanup_unit() {
    describe "Unit Tests: Cleanup Functionality"
    run_test "should remove state file with --clean" test_cleanup_removes_state
    run_test "should remove PID file with --clean" test_cleanup_removes_pid
    run_test "should remove Claude PID file with --clean" test_cleanup_removes_claude_pid
    run_test "should preserve log file with --clean" test_cleanup_preserves_log
    run_test "should exit with code 0 after cleanup" test_cleanup_exit_code
    run_test "should remove in-session loop state with --clean" test_cleanup_removes_loop_state
    run_test "should remove both state file types with --clean" test_cleanup_removes_both_state_types
}

# ============================================================================
# Unit Tests: ralph-stop.sh
# ============================================================================
test_stop_help() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/ralph-stop.sh" --help 2>&1)
    teardown_test_env
    [[ "$output" == *"USAGE:"* ]] && [[ "$output" == *"--force"* ]]
}

test_stop_no_supervisor() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/ralph-stop.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"No Ralph supervisor"* ]]
}

test_stop_cleans_files() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "claude_pid": 999998, "status": "running"}
EOF
    echo "999999" > .claude/ralph-supervisor.pid
    "$SCRIPTS_DIR/ralph-stop.sh" > /dev/null 2>&1
    local result=$([[ ! -f ".claude/ralph-supervisor.local.json" ]] && [[ ! -f ".claude/ralph-supervisor.pid" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_stop_unit() {
    describe "Unit Tests: ralph-stop.sh"
    run_test "should display help with --help" test_stop_help
    run_test "should handle no supervisor gracefully" test_stop_no_supervisor
    run_test "should clean up state files on stop" test_stop_cleans_files
}

# ============================================================================
# Unit Tests: ralph-supervisor.sh
# ============================================================================
test_supervisor_help() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/ralph-supervisor.sh" --help 2>&1)
    teardown_test_env
    [[ "$output" == *"USAGE:"* ]] && [[ "$output" == *"--max-iterations"* ]] && [[ "$output" == *"--background"* ]]
}

test_supervisor_requires_prompt() {
    setup_test_env
    local exit_code=0
    "$SCRIPTS_DIR/ralph-supervisor.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -ne 0 ]]
}

test_supervisor_detects_running() {
    setup_test_env
    echo $$ > .claude/ralph-supervisor.pid
    local output
    output=$("$SCRIPTS_DIR/ralph-supervisor.sh" --background "test" 2>&1) || true
    teardown_test_env
    [[ "$output" == *"already running"* ]]
}

test_supervisor_unit() {
    describe "Unit Tests: ralph-supervisor.sh"
    run_test "should display help with --help" test_supervisor_help
    run_test "should require prompt argument" test_supervisor_requires_prompt
    run_test "should detect already running supervisor" test_supervisor_detects_running
}

# ============================================================================
# Unit Tests: install-aliases.sh
# ============================================================================
test_aliases_help() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/install-aliases.sh" --help 2>&1)
    teardown_test_env
    [[ "$output" == *"USAGE:"* ]] && [[ "$output" == *"install"* ]] && [[ "$output" == *"uninstall"* ]]
}

test_aliases_show() {
    setup_test_env
    local output
    output=$("$SCRIPTS_DIR/install-aliases.sh" show 2>&1)
    teardown_test_env
    [[ "$output" == *"ralph-supervisor"* ]] && [[ "$output" == *"ralph-status"* ]] && [[ "$output" == *"ralph-cleanup"* ]]
}

test_aliases_check_not_installed() {
    setup_test_env
    # Create a fake rc file without aliases
    local rc_file="$TEST_DIR/.bashrc"
    echo "# empty rc" > "$rc_file"
    HOME="$TEST_DIR"
    local exit_code=0
    "$SCRIPTS_DIR/install-aliases.sh" check --shell bash > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -ne 0 ]]
}

test_aliases_dry_run_install() {
    setup_test_env
    local rc_file="$TEST_DIR/.bashrc"
    echo "# empty rc" > "$rc_file"
    HOME="$TEST_DIR"
    local output
    output=$("$SCRIPTS_DIR/install-aliases.sh" install --shell bash --dry-run 2>&1)
    # File should NOT be modified
    local content
    content=$(cat "$rc_file")
    teardown_test_env
    [[ "$output" == *"DRY RUN"* ]] && [[ "$content" == "# empty rc" ]]
}

test_aliases_install() {
    setup_test_env
    local rc_file="$TEST_DIR/.bashrc"
    echo "# empty rc" > "$rc_file"
    HOME="$TEST_DIR"
    "$SCRIPTS_DIR/install-aliases.sh" install --shell bash > /dev/null 2>&1
    local content
    content=$(cat "$rc_file")
    teardown_test_env
    [[ "$content" == *"ralph-cleanup"* ]] && [[ "$content" == *"ralph-supervisor"* ]]
}

test_aliases_check_installed() {
    setup_test_env
    local rc_file="$TEST_DIR/.bashrc"
    echo "# empty rc" > "$rc_file"
    HOME="$TEST_DIR"
    "$SCRIPTS_DIR/install-aliases.sh" install --shell bash > /dev/null 2>&1
    local exit_code=0
    "$SCRIPTS_DIR/install-aliases.sh" check --shell bash > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]]
}

test_aliases_uninstall() {
    setup_test_env
    local rc_file="$TEST_DIR/.bashrc"
    echo "# empty rc" > "$rc_file"
    HOME="$TEST_DIR"
    "$SCRIPTS_DIR/install-aliases.sh" install --shell bash > /dev/null 2>&1
    "$SCRIPTS_DIR/install-aliases.sh" uninstall --shell bash > /dev/null 2>&1
    local content
    content=$(cat "$rc_file")
    teardown_test_env
    [[ "$content" != *"ralph-cleanup"* ]]
}

test_aliases_reinstall() {
    setup_test_env
    local rc_file="$TEST_DIR/.bashrc"
    echo "# empty rc" > "$rc_file"
    HOME="$TEST_DIR"
    "$SCRIPTS_DIR/install-aliases.sh" install --shell bash > /dev/null 2>&1
    "$SCRIPTS_DIR/install-aliases.sh" install --shell bash > /dev/null 2>&1
    # Should not have duplicate alias blocks
    local count
    count=$(grep -c "Ralph Loop Aliases - BEGIN" "$rc_file" || echo "0")
    teardown_test_env
    [[ "$count" == "1" ]]
}

test_aliases_unit() {
    describe "Unit Tests: install-aliases.sh"
    run_test "should display help with --help" test_aliases_help
    run_test "should show aliases with 'show' command" test_aliases_show
    run_test "should detect aliases not installed" test_aliases_check_not_installed
    run_test "should not modify file in dry-run mode" test_aliases_dry_run_install
    run_test "should install aliases to rc file" test_aliases_install
    run_test "should detect aliases after install" test_aliases_check_installed
    run_test "should remove aliases on uninstall" test_aliases_uninstall
    run_test "should not duplicate on reinstall" test_aliases_reinstall
}

# ============================================================================
# Integration Tests
# ============================================================================
test_status_after_cleanup() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 5}
EOF
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"No Ralph supervisor or loop is currently running"* ]]
}

test_status_after_stop() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "claude_pid": 999998, "status": "running"}
EOF
    "$SCRIPTS_DIR/ralph-stop.sh" > /dev/null 2>&1
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1)
    teardown_test_env
    [[ "$output" == *"No Ralph supervisor or loop is currently running"* ]]
}

test_all_clean_flags() {
    setup_test_env
    local exit_code=0
    "$SCRIPTS_DIR/ralph-status.sh" --all --clean > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]]
}

test_setup_then_cleanup() {
    setup_test_env
    # Setup creates ralph-loop.local.md, cleanup targets ralph-supervisor.local.json
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "Test" > /dev/null 2>&1
    [[ -f ".claude/ralph-loop.local.md" ]]
    # These are different files - setup creates loop state, supervisor creates supervisor state
    local result=$([[ -f ".claude/ralph-loop.local.md" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_integration() {
    describe "Integration Tests"
    run_test "should show no supervisor after cleanup" test_status_after_cleanup
    run_test "should show no supervisor after stop" test_status_after_stop
    run_test "should accept --all --clean flags together" test_all_clean_flags
    run_test "setup should create loop state file" test_setup_then_cleanup
}

# ============================================================================
# Edge Case Tests
# ============================================================================
test_malformed_json() {
    setup_test_env
    echo "not valid json {{{" > .claude/ralph-supervisor.local.json
    local exit_code=0
    "$SCRIPTS_DIR/ralph-status.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    # Should not crash (exit 0 or 1 is ok)
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]
}

test_empty_state_file() {
    setup_test_env
    touch .claude/ralph-supervisor.local.json
    local exit_code=0
    "$SCRIPTS_DIR/ralph-status.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]
}

test_missing_claude_dir() {
    setup_test_env
    rmdir .claude 2>/dev/null || true
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1) || true
    teardown_test_env
    [[ "$output" == *"No Ralph supervisor"* ]]
}

test_orphan_pid_file() {
    setup_test_env
    echo "999999" > .claude/ralph-supervisor.pid
    local exit_code=0
    "$SCRIPTS_DIR/ralph-stop.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]]
}

test_null_values() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": null, "claude_pid": null, "status": null, "iteration": null}
EOF
    local exit_code=0
    "$SCRIPTS_DIR/ralph-status.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]
}

test_large_iteration() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 999999999, "max_iterations": 0}
EOF
    local output
    output=$("$SCRIPTS_DIR/ralph-status.sh" 2>&1) || true
    teardown_test_env
    [[ "$output" == *"999999999"* ]]
}

test_special_characters() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "prompt": "Test with \"quotes\" and $dollars", "iteration": 1}
EOF
    local exit_code=0
    "$SCRIPTS_DIR/ralph-status.sh" > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]]
}

test_double_cleanup() {
    setup_test_env
    cat > .claude/ralph-supervisor.local.json << 'EOF'
{"pid": 999999, "status": "running", "iteration": 1}
EOF
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1
    local exit_code=0
    "$SCRIPTS_DIR/ralph-status.sh" --clean > /dev/null 2>&1 || exit_code=$?
    teardown_test_env
    [[ $exit_code -eq 0 ]]
}

test_special_prompt_characters() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "Build an API with 'quotes' and \"double quotes\"" > /dev/null 2>&1
    local result=$([[ -f ".claude/ralph-loop.local.md" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_unicode_prompt() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "Build emoji support 🚀 with unicode λ" > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"🚀"* ]] || [[ "$content" == *"emoji"* ]]
}

test_zero_max_iterations() {
    setup_test_env
    "$SCRIPTS_DIR/setup-ralph-loop.sh" --max-iterations 0 "Test" > /dev/null 2>&1
    local content
    content=$(cat .claude/ralph-loop.local.md 2>/dev/null)
    teardown_test_env
    [[ "$content" == *"max_iterations: 0"* ]]
}

test_very_long_prompt() {
    setup_test_env
    local long_prompt
    long_prompt=$(printf 'x%.0s' {1..1000})
    "$SCRIPTS_DIR/setup-ralph-loop.sh" "$long_prompt" > /dev/null 2>&1
    local result=$([[ -f ".claude/ralph-loop.local.md" ]] && echo "ok")
    teardown_test_env
    [[ "$result" == "ok" ]]
}

test_edge_cases() {
    describe "Edge Case Tests"
    run_test "should handle malformed JSON gracefully" test_malformed_json
    run_test "should handle empty state file" test_empty_state_file
    run_test "should handle missing .claude directory" test_missing_claude_dir
    run_test "should handle orphan PID file" test_orphan_pid_file
    run_test "should handle state file with null values" test_null_values
    run_test "should handle large iteration numbers" test_large_iteration
    run_test "should handle special characters in state file" test_special_characters
    run_test "should handle double cleanup idempotently" test_double_cleanup
    run_test "should handle special characters in prompt" test_special_prompt_characters
    run_test "should handle unicode in prompt" test_unicode_prompt
    run_test "should handle zero max iterations" test_zero_max_iterations
    run_test "should handle very long prompts" test_very_long_prompt
}

# ============================================================================
# Test Runner
# ============================================================================
run_all_tests() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     Ralph Loop - Comprehensive Bash Test Suite             ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

    test_setup_unit
    test_status_unit
    test_cleanup_unit
    test_stop_unit
    test_supervisor_unit
    test_aliases_unit
    test_integration
    test_edge_cases

    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Test Results:${NC}"
    echo -e "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# Run tests
run_all_tests
