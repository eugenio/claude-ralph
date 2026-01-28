#!/usr/bin/env bash
# =============================================================================
# test_helper.bash - Common test utilities for bats tests
# =============================================================================
#
# DESCRIPTION:
#   Provides shared test utilities, mock functions, and fixtures for all
#   ralph bash script tests. Uses bats-support and bats-assert for enhanced
#   assertions.
#
# USAGE:
#   In your .bats file:
#   load 'test_helper'
#
# REQUIREMENTS:
#   - bats-core
#   - bats-support (optional but recommended)
#   - bats-assert (optional but recommended)
#
# =============================================================================

# =============================================================================
# BATS LIBRARY LOADING
# =============================================================================

# Attempt to load bats-support and bats-assert if available
# These provide enhanced assertion functions like assert_success, assert_output, etc.

_load_bats_libs() {
    # Common installation paths for bats libraries
    local lib_paths=(
        # System-wide installations (Linux)
        "/usr/lib/bats"
        "/usr/local/lib/bats"
        "/usr/share/bats"
        # Homebrew (macOS)
        "/opt/homebrew/lib"
        "/usr/local/lib"
        # npm global installations
        "${HOME}/.npm-global/lib/node_modules"
        "/usr/local/lib/node_modules"
        # Local project installations
        "${BATS_TEST_DIRNAME}/../../node_modules"
        "${BATS_TEST_DIRNAME}/../../../node_modules"
        # Submodule installations
        "${BATS_TEST_DIRNAME}/bats-support"
        "${BATS_TEST_DIRNAME}/bats-assert"
    )

    # Try to load bats-support
    for path in "${lib_paths[@]}"; do
        if [[ -f "$path/bats-support/load.bash" ]]; then
            # shellcheck source=/dev/null
            source "$path/bats-support/load.bash"
            break
        elif [[ -f "$path/load.bash" && "$path" == *"bats-support"* ]]; then
            # shellcheck source=/dev/null
            source "$path/load.bash"
            break
        fi
    done

    # Try to load bats-assert
    for path in "${lib_paths[@]}"; do
        if [[ -f "$path/bats-assert/load.bash" ]]; then
            # shellcheck source=/dev/null
            source "$path/bats-assert/load.bash"
            break
        elif [[ -f "$path/load.bash" && "$path" == *"bats-assert"* ]]; then
            # shellcheck source=/dev/null
            source "$path/load.bash"
            break
        fi
    done
}

# Attempt to load libraries (non-fatal if not available)
_load_bats_libs 2>/dev/null || true

# =============================================================================
# FALLBACK ASSERTIONS (if bats-assert not available)
# =============================================================================

# Provide basic assertion functions if bats-assert is not installed
# Note: $status and $output are provided by bats framework

if ! command -v assert_success &>/dev/null; then
    # shellcheck disable=SC2154
    assert_success() {
        if [[ "$status" -ne 0 ]]; then
            echo "Expected success (exit code 0), but got exit code $status" >&2
            echo "Output was: $output" >&2
            return 1
        fi
    }
fi

if ! command -v assert_failure &>/dev/null; then
    # shellcheck disable=SC2154
    assert_failure() {
        if [[ "$status" -eq 0 ]]; then
            echo "Expected failure (non-zero exit code), but got exit code 0" >&2
            echo "Output was: $output" >&2
            return 1
        fi
    }
fi

if ! command -v assert_output &>/dev/null; then
    # shellcheck disable=SC2154
    assert_output() {
        local expected="$1"
        if [[ "$output" != "$expected" ]]; then
            echo "Expected output: $expected" >&2
            echo "Actual output: $output" >&2
            return 1
        fi
    }
fi

if ! command -v assert_line &>/dev/null; then
    # shellcheck disable=SC2154
    assert_line() {
        local expected="$1"
        if [[ ! "$output" == *"$expected"* ]]; then
            echo "Expected line not found: $expected" >&2
            echo "Output was: $output" >&2
            return 1
        fi
    }
fi

if ! command -v refute_output &>/dev/null; then
    # shellcheck disable=SC2154
    refute_output() {
        local unexpected="$1"
        if [[ "$output" == "$unexpected" ]]; then
            echo "Output should not match: $unexpected" >&2
            return 1
        fi
    }
fi

if ! command -v refute_line &>/dev/null; then
    # shellcheck disable=SC2154
    refute_line() {
        local unexpected="$1"
        if [[ "$output" == *"$unexpected"* ]]; then
            echo "Unexpected line found: $unexpected" >&2
            echo "Output was: $output" >&2
            return 1
        fi
    }
fi

# =============================================================================
# TEST DIRECTORY MANAGEMENT
# =============================================================================

# Global variable to track the test temp directory
TEST_TEMP_DIR=""
# Track the original ralph script directory
RALPH_SCRIPT_DIR_ORIG=""

# setup_test_environment()
# Creates a clean temporary directory structure for testing
# Call this in your setup() function
#
setup_test_environment() {
    # Create unique temp directory for this test
    TEST_TEMP_DIR=$(mktemp -d -t ralph-test-XXXXXX)

    # Save original script directory
    RALPH_SCRIPT_DIR_ORIG="${BATS_TEST_DIRNAME}/../.."

    # Create ralph directory structure in temp
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph"
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/instances"
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks"
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/archive"

    # Create minimal progress.txt
    cat > "$TEST_TEMP_DIR/scripts/ralph/progress.txt" <<'EOF'
## Codebase Patterns
(Test patterns)
---
EOF

    # Export for tests
    export TEST_TEMP_DIR
    export RALPH_SCRIPT_DIR_ORIG
}

# teardown_test_environment()
# Cleans up the temporary test directory
# Call this in your teardown() function
#
teardown_test_environment() {
    if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    TEST_TEMP_DIR=""
}

# get_test_ralph_dir()
# Returns the path to the ralph scripts in the test temp directory
#
get_test_ralph_dir() {
    echo "$TEST_TEMP_DIR/scripts/ralph"
}

# =============================================================================
# FIXTURE MANAGEMENT
# =============================================================================

# Fixtures directory relative to test_helper.bash
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# load_fixture()
# Loads a fixture file into the test environment
# Arguments:
#   $1 - Fixture filename (relative to fixtures/)
#   $2 - Destination path in test temp dir
#
load_fixture() {
    local fixture_name="$1"
    local dest_path="$2"

    local fixture_path="$FIXTURES_DIR/$fixture_name"

    if [[ ! -f "$fixture_path" ]]; then
        echo "Fixture not found: $fixture_path" >&2
        return 1
    fi

    cp "$fixture_path" "$dest_path"
}

# create_prd_fixture()
# Creates a prd.json file in the test environment
# Arguments:
#   $1 - Fixture type: "empty", "partial", "complete", or a JSON string
#
create_prd_fixture() {
    local fixture_type="${1:-partial}"
    local prd_file="$TEST_TEMP_DIR/scripts/ralph/prd.json"

    case "$fixture_type" in
        empty)
            cat > "$prd_file" <<'EOF'
{
  "featureName": "Test Feature",
  "branchName": "test/feature-branch",
  "description": "Test description",
  "userStories": []
}
EOF
            ;;
        partial)
            cat > "$prd_file" <<'EOF'
{
  "featureName": "Test Feature",
  "branchName": "test/feature-branch",
  "description": "Test description",
  "userStories": [
    {
      "id": "US-001",
      "title": "First story",
      "priority": 1,
      "acceptanceCriteria": ["Criterion 1"],
      "passes": true,
      "notes": "Test notes"
    },
    {
      "id": "US-002",
      "title": "Second story",
      "priority": 2,
      "acceptanceCriteria": ["Criterion 2"],
      "passes": false,
      "notes": "Test notes"
    },
    {
      "id": "US-003",
      "title": "Third story",
      "priority": 3,
      "acceptanceCriteria": ["Criterion 3"],
      "passes": false,
      "notes": "Test notes"
    }
  ]
}
EOF
            ;;
        complete)
            cat > "$prd_file" <<'EOF'
{
  "featureName": "Test Feature",
  "branchName": "test/feature-branch",
  "description": "Test description",
  "userStories": [
    {
      "id": "US-001",
      "title": "First story",
      "priority": 1,
      "acceptanceCriteria": ["Criterion 1"],
      "passes": true,
      "notes": "Test notes"
    },
    {
      "id": "US-002",
      "title": "Second story",
      "priority": 2,
      "acceptanceCriteria": ["Criterion 2"],
      "passes": true,
      "notes": "Test notes"
    }
  ]
}
EOF
            ;;
        *)
            # Assume it's raw JSON
            echo "$fixture_type" > "$prd_file"
            ;;
    esac
}

# create_instance_fixture()
# Creates an instance directory with status.json
# Arguments:
#   $1 - Instance ID
#   $2 - State: starting, idle, claiming, working, merging, completed, terminated
#   $3 - Optional: Heartbeat age in seconds (0 = now, 600 = 10 min ago)
#
create_instance_fixture() {
    local instance_id="$1"
    local state="${2:-working}"
    local heartbeat_age="${3:-0}"

    local instance_dir="$TEST_TEMP_DIR/scripts/ralph/instances/$instance_id"
    mkdir -p "$instance_dir"

    local now epoch_now heartbeat_epoch
    now=$(date '+%Y-%m-%d %H:%M:%S')
    epoch_now=$(date +%s)
    heartbeat_epoch=$((epoch_now - heartbeat_age))
    local heartbeat_time
    heartbeat_time=$(date -d "@$heartbeat_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$heartbeat_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$now")

    cat > "$instance_dir/status.json" <<EOF
{
    "instanceId": "$instance_id",
    "shortId": "${instance_id:0:8}",
    "state": "$state",
    "currentStory": "US-001",
    "iteration": 1,
    "maxIterations": 10,
    "startTime": "$now",
    "lastHeartbeat": "$heartbeat_time",
    "lastHeartbeatEpoch": $heartbeat_epoch,
    "projectRoot": "$TEST_TEMP_DIR",
    "branch": "test/branch",
    "pid": $$
}
EOF

    # Create log file
    cat > "$instance_dir/ralph.log" <<EOF
# Ralph Instance Log
# Instance ID: $instance_id
# Started: $now
---
EOF
}

# create_lock_fixture()
# Creates a lock directory for a story
# Arguments:
#   $1 - Story ID
#   $2 - Owner instance ID
#   $3 - Optional: Lock age in seconds (0 = now)
#
create_lock_fixture() {
    local story_id="$1"
    local owner="${2:-test-instance-1234-5678}"
    local lock_age="${3:-0}"

    local lock_dir="$TEST_TEMP_DIR/scripts/ralph/locks/${story_id}.lock"
    mkdir -p "$lock_dir"

    local now lock_timestamp
    now=$(date +%s)
    lock_timestamp=$((now - lock_age))

    echo "$owner" > "$lock_dir/owner.txt"
    echo "$lock_timestamp" > "$lock_dir/timestamp.txt"
    echo "$$" > "$lock_dir/pid.txt"
}

# =============================================================================
# MOCK FUNCTIONS
# =============================================================================

# Mock registry to track mock calls
declare -A MOCK_CALLS
declare -A MOCK_RETURN_VALUES
declare -A MOCK_OUTPUTS

# mock_command()
# Creates a mock for a command
# Arguments:
#   $1 - Command name to mock
#   $2 - Return value (default 0)
#   $3 - Output to return (optional)
#
mock_command() {
    local cmd="$1"
    local return_val="${2:-0}"
    local output="${3:-}"

    MOCK_RETURN_VALUES["$cmd"]="$return_val"
    MOCK_OUTPUTS["$cmd"]="$output"
    MOCK_CALLS["$cmd"]=0

    # Create function that shadows the command
    eval "$cmd() {
        MOCK_CALLS['$cmd']=\$((MOCK_CALLS['$cmd'] + 1))
        [[ -n \"\${MOCK_OUTPUTS['$cmd']:-}\" ]] && echo \"\${MOCK_OUTPUTS['$cmd']}\"
        return \${MOCK_RETURN_VALUES['$cmd']}
    }"
}

# mock_git()
# Creates a comprehensive git mock
# Arguments:
#   $1 - Subcommand to mock (status, branch, log, etc.)
#   $2 - Output to return
#   $3 - Return value (default 0)
#
mock_git() {
    local subcommand="$1"
    local output="${2:-}"
    local return_val="${3:-0}"

    MOCK_RETURN_VALUES["git_$subcommand"]="$return_val"
    MOCK_OUTPUTS["git_$subcommand"]="$output"
    MOCK_CALLS["git_$subcommand"]=0

    # Override git function if not already done
    if ! declare -f _original_git &>/dev/null; then
        # Save original git path
        _ORIGINAL_GIT_PATH=$(command -v git)

        # shellcheck disable=SC2317
        git() {
            local subcmd="${1:-}"
            local mock_key="git_$subcmd"

            if [[ -n "${MOCK_OUTPUTS[$mock_key]:-}" || -n "${MOCK_RETURN_VALUES[$mock_key]:-}" ]]; then
                MOCK_CALLS["$mock_key"]=$((MOCK_CALLS["$mock_key"] + 1))
                [[ -n "${MOCK_OUTPUTS[$mock_key]:-}" ]] && echo "${MOCK_OUTPUTS[$mock_key]}"
                return "${MOCK_RETURN_VALUES[$mock_key]:-0}"
            fi

            # Fall through to real git if not mocked
            "$_ORIGINAL_GIT_PATH" "$@"
        }
    fi
}

# mock_jq()
# Creates a jq mock for testing
# Arguments:
#   $1 - Expected query pattern (for identification)
#   $2 - Output to return
#   $3 - Return value (default 0)
#
mock_jq() {
    local query_pattern="$1"
    local output="${2:-}"
    local return_val="${3:-0}"

    # Store mock data
    MOCK_RETURN_VALUES["jq_${query_pattern}"]="$return_val"
    MOCK_OUTPUTS["jq_${query_pattern}"]="$output"
    MOCK_CALLS["jq"]=0

    # Note: Full jq mocking is complex; for most tests, use real jq with fixture files
}

# get_mock_call_count()
# Returns the number of times a mock was called
# Arguments:
#   $1 - Mock name
#
get_mock_call_count() {
    local mock_name="$1"
    echo "${MOCK_CALLS[$mock_name]:-0}"
}

# reset_mocks()
# Resets all mock registries
#
reset_mocks() {
    MOCK_CALLS=()
    MOCK_RETURN_VALUES=()
    MOCK_OUTPUTS=()
}

# =============================================================================
# ASSERTION HELPERS
# =============================================================================

# assert_file_exists()
# Asserts that a file exists
# Arguments:
#   $1 - File path
#
assert_file_exists() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        echo "Expected file to exist: $file_path" >&2
        return 1
    fi
}

# assert_dir_exists()
# Asserts that a directory exists
# Arguments:
#   $1 - Directory path
#
assert_dir_exists() {
    local dir_path="$1"
    if [[ ! -d "$dir_path" ]]; then
        echo "Expected directory to exist: $dir_path" >&2
        return 1
    fi
}

# assert_file_contains()
# Asserts that a file contains a string
# Arguments:
#   $1 - File path
#   $2 - Expected content
#
assert_file_contains() {
    local file_path="$1"
    local expected="$2"

    if [[ ! -f "$file_path" ]]; then
        echo "File does not exist: $file_path" >&2
        return 1
    fi

    if ! grep -q "$expected" "$file_path"; then
        echo "Expected file to contain: $expected" >&2
        echo "File contents:" >&2
        cat "$file_path" >&2
        return 1
    fi
}

# assert_json_value()
# Asserts that a JSON file contains a specific value at a path
# Arguments:
#   $1 - File path
#   $2 - jq path (e.g., '.userStories[0].id')
#   $3 - Expected value
#
assert_json_value() {
    local file_path="$1"
    local jq_path="$2"
    local expected="$3"

    if [[ ! -f "$file_path" ]]; then
        echo "JSON file does not exist: $file_path" >&2
        return 1
    fi

    local actual
    actual=$(jq -r "$jq_path" "$file_path")

    if [[ "$actual" != "$expected" ]]; then
        echo "Expected JSON value at $jq_path: $expected" >&2
        echo "Actual value: $actual" >&2
        return 1
    fi
}

# assert_output_contains()
# Asserts that output contains a substring (works with bats $output)
# Arguments:
#   $1 - Expected substring
#
assert_output_contains() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: $expected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# assert_output_not_contains()
# Asserts that output does not contain a substring
# Arguments:
#   $1 - Unexpected substring
#
assert_output_not_contains() {
    local unexpected="$1"
    if [[ "$output" == *"$unexpected"* ]]; then
        echo "Expected output NOT to contain: $unexpected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# wait_for_file()
# Waits for a file to exist (with timeout)
# Arguments:
#   $1 - File path
#   $2 - Timeout in seconds (default 5)
#
wait_for_file() {
    local file_path="$1"
    local timeout="${2:-5}"
    local elapsed=0

    while [[ ! -f "$file_path" && "$elapsed" -lt "$timeout" ]]; do
        sleep 0.1
        elapsed=$((elapsed + 1))
    done

    [[ -f "$file_path" ]]
}

# capture_stderr()
# Captures stderr from a command
# Arguments:
#   All arguments are passed to the command
# Sets:
#   $stderr - The captured stderr output (exported for caller use)
#
capture_stderr() {
    local tmpfile
    tmpfile=$(mktemp)
    "$@" 2>"$tmpfile"
    local ret=$?
    # shellcheck disable=SC2034
    stderr=$(cat "$tmpfile")
    export stderr
    rm -f "$tmpfile"
    return $ret
}

# skip_if_no_jq()
# Skips the test if jq is not available
#
skip_if_no_jq() {
    if ! command -v jq &>/dev/null; then
        skip "jq is not installed"
    fi
}

# skip_if_no_git()
# Skips the test if git is not available
#
skip_if_no_git() {
    if ! command -v git &>/dev/null; then
        skip "git is not installed"
    fi
}

# =============================================================================
# TEST SCRIPT SOURCING HELPERS
# =============================================================================

# source_ralph_utils()
# Sources ralph-utils.sh with test environment overrides
#
source_ralph_utils() {
    # Set RALPH_SCRIPT_DIR to test directory
    export RALPH_SCRIPT_DIR="$TEST_TEMP_DIR/scripts/ralph"

    # Copy ralph-utils.sh to test directory if not present
    if [[ ! -f "$RALPH_SCRIPT_DIR/ralph-utils.sh" ]]; then
        cp "$RALPH_SCRIPT_DIR_ORIG/ralph-utils.sh" "$RALPH_SCRIPT_DIR/"
    fi

    # Unset the loaded flag to allow re-sourcing
    unset _RALPH_UTILS_LOADED

    # Source the utils
    # shellcheck source=/dev/null
    source "$RALPH_SCRIPT_DIR/ralph-utils.sh"
}

# Export all helper functions
export -f setup_test_environment
export -f teardown_test_environment
export -f get_test_ralph_dir
export -f load_fixture
export -f create_prd_fixture
export -f create_instance_fixture
export -f create_lock_fixture
export -f mock_command
export -f mock_git
export -f mock_jq
export -f get_mock_call_count
export -f reset_mocks
export -f assert_file_exists
export -f assert_dir_exists
export -f assert_file_contains
export -f assert_json_value
export -f assert_output_contains
export -f assert_output_not_contains
export -f wait_for_file
export -f capture_stderr
export -f skip_if_no_jq
export -f skip_if_no_git
export -f source_ralph_utils
