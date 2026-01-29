#!/usr/bin/env bash
# Test script for global registry functions (GM-001)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$SCRIPT_DIR/../.."

# Source ralph-utils.sh
source "$RALPH_DIR/ralph-utils.sh" || { echo "FAIL: Cannot source ralph-utils.sh"; exit 1; }

# Test counter
PASSED=0
FAILED=0

test_pass() {
    echo "PASS: $1"
    ((PASSED++)) || true
}

test_fail() {
    echo "FAIL: $1"
    ((FAILED++)) || true
}

# Clean test directory
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "=== Testing Global Registry Functions (GM-001) ==="
echo ""

# Test 1: get_ralph_global_dir returns default path
echo "Test 1: get_ralph_global_dir default path"
unset RALPH_GLOBAL_DIR
result=$(get_ralph_global_dir)
if [[ "$result" == *"/.ralph/global" ]]; then
    test_pass "Default path ends with /.ralph/global"
else
    test_fail "Expected path to end with /.ralph/global, got: $result"
fi

# Test 2: get_ralph_global_dir respects override
echo "Test 2: get_ralph_global_dir with override"
export RALPH_GLOBAL_DIR="$TEST_DIR/custom"
result=$(get_ralph_global_dir)
if [[ "$result" == "$TEST_DIR/custom" ]]; then
    test_pass "Override path is respected"
else
    test_fail "Expected $TEST_DIR/custom, got: $result"
fi

# Test 3: init_ralph_global_registry creates directories
echo "Test 3: init_ralph_global_registry creates directories"
export RALPH_GLOBAL_DIR="$TEST_DIR/global"
rm -rf "$TEST_DIR/global"
init_ralph_global_registry
if [[ -d "$TEST_DIR/global/instances" ]] && [[ -d "$TEST_DIR/global/locks" ]]; then
    test_pass "Both instances and locks directories created"
else
    test_fail "Directories not created properly"
fi

# Test 4: init_ralph_global_registry is idempotent
echo "Test 4: init_ralph_global_registry is idempotent"
init_ralph_global_registry
if [[ -d "$TEST_DIR/global/instances" ]] && [[ -d "$TEST_DIR/global/locks" ]]; then
    test_pass "Idempotent - directories still exist"
else
    test_fail "Directories missing after second call"
fi

# Test 5: RALPH_GLOBAL_DISABLE skips creation
echo "Test 5: RALPH_GLOBAL_DISABLE skips creation"
export RALPH_GLOBAL_DIR="$TEST_DIR/disabled"
export RALPH_GLOBAL_DISABLE=1
rm -rf "$TEST_DIR/disabled"
init_ralph_global_registry
if [[ ! -d "$TEST_DIR/disabled" ]]; then
    test_pass "Disable flag prevents directory creation"
else
    test_fail "Directory created despite disable flag"
fi
unset RALPH_GLOBAL_DISABLE

# Test 6: Directory permissions (Unix only)
echo "Test 6: Directory permissions"
export RALPH_GLOBAL_DIR="$TEST_DIR/perms"
rm -rf "$TEST_DIR/perms"
init_ralph_global_registry
perms=$(stat -c %a "$TEST_DIR/perms" 2>/dev/null || stat -f %Lp "$TEST_DIR/perms" 2>/dev/null || echo "unknown")
if [[ "$perms" == "700" ]] || [[ "$perms" == "unknown" ]]; then
    test_pass "Directory permissions are 700 (or stat not available)"
else
    test_fail "Expected 700, got: $perms"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
