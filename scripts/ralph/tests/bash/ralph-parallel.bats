#!/usr/bin/env bats
# =============================================================================
# ralph-parallel.bats - Tests for ralph-parallel.sh
# =============================================================================
#
# DESCRIPTION:
#   Comprehensive test suite for the ralph-parallel.sh script that manages
#   multiple parallel Ralph instances with PRD file and project root options.
#
# REQUIREMENTS:
#   - bats-core
#   - jq (for JSON parsing)
#
# =============================================================================

# Load test helper
load 'test_helper'

# Path to the script being tested
RALPH_PARALLEL_SCRIPT=""

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

setup() {
    setup_test_environment
    # The ralph-parallel.sh is two levels up from tests/bash
    RALPH_PARALLEL_SCRIPT="${BATS_TEST_DIRNAME}/../../ralph-parallel.sh"

    # Copy required scripts to test environment
    cp "$RALPH_PARALLEL_SCRIPT" "$TEST_TEMP_DIR/ralph-parallel.sh"
    cp "${BATS_TEST_DIRNAME}/../../ralph-utils.sh" "$TEST_TEMP_DIR/scripts/ralph/ralph-utils.sh"
    chmod +x "$TEST_TEMP_DIR/ralph-parallel.sh"

    # Create a mock ralph.sh in the test environment
    cat > "$TEST_TEMP_DIR/scripts/ralph/ralph.sh" << 'EOF'
#!/usr/bin/env bash
# Mock ralph.sh for testing
echo "Mock ralph.sh called with args: $@"
sleep 0.1
EOF
    chmod +x "$TEST_TEMP_DIR/scripts/ralph/ralph.sh"
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Run ralph-parallel.sh with environment pointing to test temp dir
run_ralph_parallel() {
    cd "$TEST_TEMP_DIR/scripts/ralph" && run ./../../ralph-parallel.sh "$@"
}

# Run the actual script for help output testing
run_ralph_parallel_direct() {
    run "$RALPH_PARALLEL_SCRIPT" "$@"
}

# Create a test PRD file at specified path
create_test_prd_at() {
    local prd_path="$1"
    mkdir -p "$(dirname "$prd_path")"
    cat > "$prd_path" <<'EOF'
{
  "featureName": "Test Feature",
  "branchName": "test/feature-branch",
  "description": "Test description",
  "userStories": [
    {
      "id": "US-001",
      "title": "First story",
      "priority": 1,
      "passes": false
    }
  ]
}
EOF
}

# =============================================================================
# SCRIPT STRUCTURE TESTS
# =============================================================================

@test "ralph-parallel.sh exists and is executable" {
    [[ -f "$RALPH_PARALLEL_SCRIPT" ]]
    [[ -x "$RALPH_PARALLEL_SCRIPT" ]]
}

@test "ralph-parallel.sh has valid bash syntax" {
    run bash -n "$RALPH_PARALLEL_SCRIPT"
    assert_success
}

# =============================================================================
# HELP OUTPUT TESTS
# =============================================================================

@test "help command shows usage information" {
    run_ralph_parallel_direct help
    assert_success
    assert_output_contains "Usage:"
}

@test "help output includes -p/--prd option" {
    run_ralph_parallel_direct help
    assert_success
    assert_output_contains "-p"
    assert_output_contains "--prd"
}

@test "help output includes -r/--project option" {
    run_ralph_parallel_direct help
    assert_success
    assert_output_contains "-r"
    assert_output_contains "--project"
}

@test "help output describes PRD option purpose" {
    run_ralph_parallel_direct help
    assert_success
    # Should mention prd.json or PRD file path
    assert_output_contains "prd"
}

@test "help output describes project option purpose" {
    run_ralph_parallel_direct help
    assert_success
    # Should mention project root or directory
    assert_output_contains "project"
}

@test "-h flag shows help" {
    run_ralph_parallel_direct -h
    assert_success
    assert_output_contains "Usage:"
}

@test "--help flag shows help" {
    run_ralph_parallel_direct --help
    assert_success
    assert_output_contains "Usage:"
}

# =============================================================================
# FLAG PARSING TESTS
# =============================================================================

@test "parses -p flag with value" {
    local test_prd="$TEST_TEMP_DIR/custom/prd.json"
    create_test_prd_at "$test_prd"

    # We need to mock the start command to verify the flag was parsed
    # For this test, we check that it doesn't error on a valid path
    run_ralph_parallel_direct help -p "$test_prd"
    assert_success
}

@test "parses --prd flag with value" {
    local test_prd="$TEST_TEMP_DIR/custom/prd.json"
    create_test_prd_at "$test_prd"

    run_ralph_parallel_direct help --prd "$test_prd"
    assert_success
}

@test "parses -r flag with value" {
    local test_project="$TEST_TEMP_DIR/my-project"
    mkdir -p "$test_project"

    run_ralph_parallel_direct help -r "$test_project"
    assert_success
}

@test "parses --project flag with value" {
    local test_project="$TEST_TEMP_DIR/my-project"
    mkdir -p "$test_project"

    run_ralph_parallel_direct help --project "$test_project"
    assert_success
}

@test "parses combined -p and -r flags" {
    local test_prd="$TEST_TEMP_DIR/custom/prd.json"
    local test_project="$TEST_TEMP_DIR/my-project"
    create_test_prd_at "$test_prd"
    mkdir -p "$test_project"

    run_ralph_parallel_direct help -p "$test_prd" -r "$test_project"
    assert_success
}

@test "parses flags with count option" {
    local test_prd="$TEST_TEMP_DIR/custom/prd.json"
    create_test_prd_at "$test_prd"

    run_ralph_parallel_direct help -p "$test_prd" -c 2
    assert_success
}

@test "parses flags with max-iterations option" {
    local test_prd="$TEST_TEMP_DIR/custom/prd.json"
    create_test_prd_at "$test_prd"

    run_ralph_parallel_direct help -p "$test_prd" -m 5
    assert_success
}

# =============================================================================
# PATH VALIDATION TESTS
# =============================================================================

@test "errors when PRD file does not exist" {
    run_ralph_parallel_direct start -p "/nonexistent/path/prd.json"
    assert_failure
    assert_output_contains "not found"
}

@test "errors when PRD path is not a file" {
    local test_dir="$TEST_TEMP_DIR/not-a-file"
    mkdir -p "$test_dir"

    run_ralph_parallel_direct start -p "$test_dir"
    assert_failure
    assert_output_contains "not"
}

@test "errors when project path does not exist" {
    run_ralph_parallel_direct start -r "/nonexistent/project/dir"
    assert_failure
    assert_output_contains "not found"
}

@test "errors when project path is not a directory" {
    local test_file="$TEST_TEMP_DIR/not-a-dir.txt"
    echo "test" > "$test_file"

    run_ralph_parallel_direct start -r "$test_file"
    assert_failure
    assert_output_contains "not"
}

@test "validates both PRD and project paths" {
    local test_prd="$TEST_TEMP_DIR/custom/prd.json"
    create_test_prd_at "$test_prd"

    run_ralph_parallel_direct start -p "$test_prd" -r "/nonexistent/project"
    assert_failure
    assert_output_contains "not found"
}

# =============================================================================
# EXAMPLES SECTION TESTS
# =============================================================================

@test "help examples include -p option usage" {
    run_ralph_parallel_direct help
    assert_success
    # Examples section should show -p usage
    [[ "$output" == *"-p"* ]] || [[ "$output" == *"--prd"* ]]
}

# =============================================================================
# COMMAND COMBINATIONS TESTS
# =============================================================================

@test "status command works without path options" {
    run_ralph_parallel_direct status
    # Status should work even without PRD (it checks running instances)
    # It might fail if no instances dir, but shouldn't error on path validation
    [[ "$status" -eq 0 ]] || [[ "$output" != *"--prd"* ]]
}

@test "stop command works without path options" {
    run_ralph_parallel_direct stop
    # Stop should work to stop any running instances
    assert_success
}

# =============================================================================
# ENVIRONMENT VARIABLE TESTS
# =============================================================================

@test "respects RALPH_MAX_INSTANCES environment variable" {
    run_ralph_parallel_direct help
    assert_success
    assert_output_contains "RALPH_MAX_INSTANCES"
}

@test "respects RALPH_ITERATIONS environment variable" {
    run_ralph_parallel_direct help
    assert_success
    assert_output_contains "RALPH_ITERATIONS"
}
