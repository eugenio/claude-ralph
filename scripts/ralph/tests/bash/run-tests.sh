#!/usr/bin/env bash
# =============================================================================
# run-tests.sh - Test runner for Ralph bash tests
# =============================================================================
#
# DESCRIPTION:
#   Runs all BATS tests for Ralph bash scripts. Supports parallel execution
#   and CI-compatible output formats (TAP, JUnit XML).
#
# USAGE:
#   ./run-tests.sh              # Run all tests
#   ./run-tests.sh --tap        # TAP output (for CI)
#   ./run-tests.sh --junit      # JUnit XML output
#   ./run-tests.sh --parallel   # Run tests in parallel
#   ./run-tests.sh --filter "pattern"  # Run tests matching pattern
#   ./run-tests.sh <file.bats>  # Run specific test file
#
# REQUIREMENTS:
#   - bats-core
#   - jq (for JSON parsing in tests)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Default options
OUTPUT_FORMAT=""
PARALLEL=""
FILTER=""
VERBOSE=""
TEST_FILES=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tap)
            OUTPUT_FORMAT="--tap"
            shift
            ;;
        --junit)
            OUTPUT_FORMAT="--formatter junit"
            shift
            ;;
        --parallel|-j)
            # Use half of available CPU cores
            PARALLEL="--jobs $(( $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) / 2 ))"
            shift
            ;;
        --jobs)
            PARALLEL="--jobs $2"
            shift 2
            ;;
        --filter|-f)
            FILTER="--filter $2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE="--verbose-run"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [test-files...]"
            echo ""
            echo "Options:"
            echo "  --tap           Output in TAP format (for CI)"
            echo "  --junit         Output in JUnit XML format"
            echo "  --parallel, -j  Run tests in parallel"
            echo "  --jobs N        Run tests with N parallel jobs"
            echo "  --filter, -f    Run tests matching pattern"
            echo "  --verbose, -v   Verbose output"
            echo "  --help, -h      Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                          # Run all tests"
            echo "  $0 --tap                    # TAP output for CI"
            echo "  $0 --parallel               # Parallel execution"
            echo "  $0 ralph-utils.bats         # Run specific file"
            echo "  $0 --filter 'lock'          # Run tests matching 'lock'"
            exit 0
            ;;
        *.bats)
            TEST_FILES+=("$1")
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}" >&2
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if bats is installed
if ! command -v bats &>/dev/null; then
    echo -e "${RED}Error: bats is not installed${NC}"
    echo ""
    echo "Install bats using one of:"
    echo "  - Ubuntu/Debian: sudo apt install bats"
    echo "  - macOS: brew install bats-core"
    echo "  - npm: npm install -g bats"
    echo ""
    exit 1
fi

# Check for jq (required by most tests)
if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. Some tests may be skipped.${NC}"
fi

# If no test files specified, run all .bats files
if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
    TEST_FILES=("$SCRIPT_DIR"/*.bats)
fi

# Show banner unless using CI format
if [[ -z "$OUTPUT_FORMAT" ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}Ralph Bash Test Suite${NC}"
    echo -e "${CYAN}=====================${NC}"
    echo ""
    echo "Running tests from: $SCRIPT_DIR"
    echo "Test files: ${#TEST_FILES[@]}"
    echo ""
fi

# Build bats command
BATS_CMD="bats"
[[ -n "$OUTPUT_FORMAT" ]] && BATS_CMD="$BATS_CMD $OUTPUT_FORMAT"
[[ -n "$PARALLEL" ]] && BATS_CMD="$BATS_CMD $PARALLEL"
[[ -n "$FILTER" ]] && BATS_CMD="$BATS_CMD $FILTER"
[[ -n "$VERBOSE" ]] && BATS_CMD="$BATS_CMD $VERBOSE"

# Run tests
# shellcheck disable=SC2086
$BATS_CMD "${TEST_FILES[@]}"
EXIT_CODE=$?

# Show summary unless using CI format
if [[ -z "$OUTPUT_FORMAT" ]]; then
    echo ""
    if [[ $EXIT_CODE -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed (exit code: $EXIT_CODE)${NC}"
    fi
fi

exit $EXIT_CODE
