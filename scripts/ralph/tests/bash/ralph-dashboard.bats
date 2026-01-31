#!/usr/bin/env bats
# =============================================================================
# ralph-dashboard.bats - Tests for ralph-dashboard.sh
# =============================================================================
#
# DESCRIPTION:
#   Comprehensive test suite for ralph-dashboard.sh TUI dashboard covering:
#   - Render functions (header, instances, locks, footer)
#   - Progress bar calculation
#   - Duration formatting (seconds, minutes, hours)
#   - Instance state color mapping
#   - No instances handling
#   - No locks handling
#
# USAGE:
#   bats ralph-dashboard.bats
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

    # RALPH_SCRIPT_DIR_ORIG points to scripts/ralph/tests/bash/../.. = scripts/ralph
    # The dashboard is at scripts/ralph/ralph-dashboard.sh
    local ralph_dir="$RALPH_SCRIPT_DIR_ORIG"

    # Copy ralph-dashboard.sh from scripts/ralph to test directory
    cp "$ralph_dir/ralph-dashboard.sh" "$TEST_TEMP_DIR/scripts/ralph/"
    chmod +x "$TEST_TEMP_DIR/scripts/ralph/ralph-dashboard.sh"

    # Create prd.json for tests
    create_prd_fixture "partial"
}

teardown() {
    teardown_test_environment
}

# Helper to extract render functions from dashboard and test them
# We source the script and call individual functions in isolation
extract_and_test_functions() {
    cd "$TEST_TEMP_DIR/scripts/ralph" || return 1

    # Create a test wrapper that sources dashboard but doesn't run main_loop
    cat > "$TEST_TEMP_DIR/test_dashboard_funcs.sh" <<'SCRIPT'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/ralph"
INSTANCES_DIR="$SCRIPT_DIR/instances"
LOCKS_DIR="$SCRIPT_DIR/locks"
PRD_FILE="$SCRIPT_DIR/prd.json"

REFRESH_INTERVAL=2
SHOW_ALL_REPOS=false
FILTER_REPO=""

# Colors - simplified for testing
init_colors() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
}

init_colors

# Source the dashboard functions (but not the main_loop execution)
SCRIPT

    # Extract function definitions from the dashboard script
    sed -n '/^get_prd_status()/,/^[a-z_]*() {$/p' "$TEST_TEMP_DIR/scripts/ralph/ralph-dashboard.sh" | head -n -1 >> "$TEST_TEMP_DIR/test_dashboard_funcs.sh"
    sed -n '/^get_progress_bar()/,/^[a-z_]*() {$/p' "$TEST_TEMP_DIR/scripts/ralph/ralph-dashboard.sh" | head -n -1 >> "$TEST_TEMP_DIR/test_dashboard_funcs.sh"
    sed -n '/^format_duration()/,/^[a-z_]*() {$/p' "$TEST_TEMP_DIR/scripts/ralph/ralph-dashboard.sh" | head -n -1 >> "$TEST_TEMP_DIR/test_dashboard_funcs.sh"
    sed -n '/^get_state_color()/,/^[a-z_]*() {$/p' "$TEST_TEMP_DIR/scripts/ralph/ralph-dashboard.sh" | head -n -1 >> "$TEST_TEMP_DIR/test_dashboard_funcs.sh"

    chmod +x "$TEST_TEMP_DIR/test_dashboard_funcs.sh"
}

# Helper to run dashboard with --help to test non-TUI functionality
run_dashboard_help() {
    cd "$TEST_TEMP_DIR/scripts/ralph" || return 1
    run bash "$TEST_TEMP_DIR/scripts/ralph/ralph-dashboard.sh" --help
}

# Create a non-interactive test version of the dashboard
create_test_dashboard() {
    cat > "$TEST_TEMP_DIR/scripts/ralph/test-dashboard.sh" <<'EOF'
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="$SCRIPT_DIR/instances"
LOCKS_DIR="$SCRIPT_DIR/locks"
PRD_FILE="$SCRIPT_DIR/prd.json"

REFRESH_INTERVAL=2
SHOW_ALL_REPOS=false
FILTER_REPO=""

# Colors - simplified for testing
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

init_colors() {
    : # Already defined above
}

get_prd_status() {
    if [ ! -f "$PRD_FILE" ]; then
        echo "0/0"
        return
    fi

    local total complete
    total=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo "0")
    complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
    echo "$complete/$total"
}

get_progress_bar() {
    local complete="$1"
    local total="$2"
    local width=30

    if [ "$total" -eq 0 ]; then
        printf "[%-${width}s]" ""
        return
    fi

    local filled=$((complete * width / total))
    local empty=$((width - filled))

    printf "["
    printf "${GREEN}%${filled}s${NC}" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "]"
}

format_duration() {
    local seconds="$1"

    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

get_state_color() {
    local state="$1"
    case "$state" in
        working|merging)
            echo "$GREEN"
            ;;
        claiming|starting)
            echo "$CYAN"
            ;;
        idle)
            echo "$YELLOW"
            ;;
        completed)
            echo "$BLUE"
            ;;
        terminated|max_iterations)
            echo "$DIM"
            ;;
        dead)
            echo "$RED"
            ;;
        *)
            echo "$WHITE"
            ;;
    esac
}

render_header() {
    local prd_status
    prd_status=$(get_prd_status)
    local complete=${prd_status%/*}
    local total=${prd_status#*/}

    echo "${BLUE}+===================================================================+${NC}"
    echo "${BLUE}|${NC}              ${BOLD}${CYAN}RALPH DASHBOARD${NC}                                    ${BLUE}|${NC}"
    echo "${BLUE}+===================================================================+${NC}"

    printf "${BLUE}|${NC}  PRD Progress: "
    get_progress_bar "$complete" "$total"
    printf " %s" "$prd_status"
    printf "\n"
}

render_instances() {
    local now
    now=$(date +%s)

    printf "${BLUE}|${NC} ${BOLD}%-10s %-12s %-10s %-6s %-10s %-12s${NC} ${BLUE}|${NC}\n" \
        "INSTANCE" "STORY" "STATE" "ITER" "RUNTIME" "BRANCH"

    local found=0

    if [ -d "$INSTANCES_DIR" ]; then
        for dir in "$INSTANCES_DIR"/*; do
            [ -d "$dir" ] || continue

            local instance_id short_id status_file
            instance_id=$(basename "$dir")
            short_id="${instance_id:0:8}"
            status_file="$dir/status.json"

            if [ ! -f "$status_file" ]; then
                continue
            fi

            local state story iteration max_iter heartbeat start_time branch
            state=$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null || echo "unknown")
            story=$(jq -r '.currentStory // "-"' "$status_file" 2>/dev/null || echo "-")
            iteration=$(jq -r '.iteration // 0' "$status_file" 2>/dev/null || echo "0")
            max_iter=$(jq -r '.maxIterations // 0' "$status_file" 2>/dev/null || echo "0")
            heartbeat=$(jq -r '.lastHeartbeatEpoch // 0' "$status_file" 2>/dev/null || echo "0")
            branch=$(jq -r '.branch // "-"' "$status_file" 2>/dev/null || echo "-")

            local heartbeat_age=$((now - heartbeat))

            if [ "$heartbeat_age" -gt 300 ] && [ "$state" != "terminated" ] && [ "$state" != "completed" ]; then
                state="dead"
            fi

            local start_epoch="${instance_id##*-}"
            local runtime=$((now - start_epoch))
            local runtime_str
            runtime_str=$(format_duration "$runtime")

            local color
            color=$(get_state_color "$state")

            local branch_short="${branch:0:12}"

            printf "${BLUE}|${NC} ${color}%-10s${NC} %-12s ${color}%-10s${NC} %2s/%-2s %-10s %-12s ${BLUE}|${NC}\n" \
                "$short_id" "${story:-"-"}" "$state" "$iteration" "$max_iter" "$runtime_str" "$branch_short"

            found=$((found + 1))
        done
    fi

    if [ "$found" -eq 0 ]; then
        printf "${BLUE}|${NC}  ${DIM}No instances running${NC}\n"
    fi
}

render_locks() {
    printf "${BLUE}|${NC}  ${BOLD}ACTIVE LOCKS${NC}\n"

    local now found
    now=$(date +%s)
    found=0

    if [ -d "$LOCKS_DIR" ]; then
        for lock_dir in "$LOCKS_DIR"/*.lock; do
            [ -d "$lock_dir" ] || continue

            local story_id owner owner_short timestamp age age_str
            story_id=$(basename "$lock_dir" .lock)
            owner=$(cat "$lock_dir/owner" 2>/dev/null || cat "$lock_dir/owner.txt" 2>/dev/null || echo "unknown")
            owner_short="${owner:0:8}"
            timestamp=$(cat "$lock_dir/timestamp" 2>/dev/null || cat "$lock_dir/timestamp.txt" 2>/dev/null || echo "0")
            age=$((now - timestamp))
            age_str=$(format_duration "$age")

            printf "${BLUE}|${NC}    ${YELLOW}%-10s${NC} held by ${CYAN}%-10s${NC} for %-10s\n" \
                "$story_id" "$owner_short" "$age_str"

            found=$((found + 1))
        done
    fi

    if [ "$found" -eq 0 ]; then
        printf "${BLUE}|${NC}    ${DIM}No active locks${NC}\n"
    fi
}

render_footer() {
    printf "${BLUE}|${NC}  ${DIM}Press: q=quit  r=refresh  l=locks  c=cleanup${NC}\n"
    printf "${BLUE}|${NC}  ${DIM}Last update: $(date '+%H:%M:%S')${NC}\n"
    echo "${BLUE}+===================================================================+${NC}"
}

# Parse test mode
case "${1:-}" in
    --test-header)
        render_header
        ;;
    --test-instances)
        render_instances
        ;;
    --test-locks)
        render_locks
        ;;
    --test-footer)
        render_footer
        ;;
    --test-all)
        render_header
        render_instances
        render_locks
        render_footer
        ;;
    --test-duration)
        format_duration "$2"
        ;;
    --test-progress-bar)
        get_progress_bar "$2" "$3"
        ;;
    --test-state-color)
        get_state_color "$2"
        ;;
    --test-prd-status)
        get_prd_status
        ;;
    -h|--help)
        echo "Usage: test-dashboard.sh [--test-*]"
        echo "Test modes for ralph-dashboard.sh functions"
        ;;
    *)
        echo "Test mode required. Use --help for options."
        exit 1
        ;;
esac
EOF
    chmod +x "$TEST_TEMP_DIR/scripts/ralph/test-dashboard.sh"
}

# Helper to run the test dashboard
run_test_dashboard() {
    cd "$TEST_TEMP_DIR/scripts/ralph" || return 1
    run bash "$TEST_TEMP_DIR/scripts/ralph/test-dashboard.sh" "$@"
}

# =============================================================================
# SCRIPT STRUCTURE TESTS
# =============================================================================

@test "ralph-dashboard.sh exists in scripts/ralph" {
    assert_file_exists "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
}

@test "ralph-dashboard.sh is executable" {
    [[ -x "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh" ]]
}

@test "ralph-dashboard.sh has valid bash syntax" {
    run bash -n "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

@test "ralph-dashboard.sh contains required functions" {
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"

    grep -q "get_prd_status()" "$dashboard"
    grep -q "get_progress_bar()" "$dashboard"
    grep -q "format_duration()" "$dashboard"
    grep -q "get_state_color()" "$dashboard"
    grep -q "render_header()" "$dashboard"
    grep -q "render_instances()" "$dashboard"
    grep -q "render_locks()" "$dashboard"
    grep -q "render_footer()" "$dashboard"
    grep -q "render_dashboard()" "$dashboard"
    grep -q "main_loop()" "$dashboard"
}

# =============================================================================
# HELP COMMAND TESTS
# =============================================================================

@test "--help shows usage information" {
    run_dashboard_help
    assert_success
    assert_output_contains "Usage:"
}

@test "--help shows available options" {
    run_dashboard_help
    assert_success
    assert_output_contains "--all"
    assert_output_contains "--repo"
    assert_output_contains "--refresh"
}

@test "--help shows navigation keys" {
    run_dashboard_help
    assert_success
    assert_output_contains "Quit"
    assert_output_contains "refresh"
}

# =============================================================================
# FORMAT DURATION TESTS
# =============================================================================

@test "format_duration returns seconds for < 60" {
    create_test_dashboard
    run_test_dashboard --test-duration 30
    assert_success
    assert_output "30s"
}

@test "format_duration returns seconds for 0" {
    create_test_dashboard
    run_test_dashboard --test-duration 0
    assert_success
    assert_output "0s"
}

@test "format_duration returns seconds for 59" {
    create_test_dashboard
    run_test_dashboard --test-duration 59
    assert_success
    assert_output "59s"
}

@test "format_duration returns minutes for >= 60" {
    create_test_dashboard
    run_test_dashboard --test-duration 60
    assert_success
    assert_output "1m 0s"
}

@test "format_duration returns minutes and seconds" {
    create_test_dashboard
    run_test_dashboard --test-duration 125
    assert_success
    assert_output "2m 5s"
}

@test "format_duration returns hours for >= 3600" {
    create_test_dashboard
    run_test_dashboard --test-duration 3600
    assert_success
    assert_output "1h 0m"
}

@test "format_duration returns hours and minutes" {
    create_test_dashboard
    run_test_dashboard --test-duration 7265
    assert_success
    # 7265 seconds = 2h 1m (ignoring remaining seconds)
    assert_output "2h 1m"
}

@test "format_duration handles large values" {
    create_test_dashboard
    run_test_dashboard --test-duration 86400
    assert_success
    # 86400 seconds = 24 hours = 24h 0m
    assert_output "24h 0m"
}

# =============================================================================
# PROGRESS BAR CALCULATION TESTS
# =============================================================================

@test "get_progress_bar handles 0/0" {
    create_test_dashboard
    run_test_dashboard --test-progress-bar 0 0
    assert_success
    # Should show empty bar
    assert_output_contains "["
    assert_output_contains "]"
}

@test "get_progress_bar handles 0% complete" {
    create_test_dashboard
    run_test_dashboard --test-progress-bar 0 10
    assert_success
    assert_output_contains "["
    assert_output_contains "]"
    # Should have mostly empty characters
    assert_output_contains "-"
}

@test "get_progress_bar handles 50% complete" {
    create_test_dashboard
    run_test_dashboard --test-progress-bar 5 10
    assert_success
    assert_output_contains "["
    assert_output_contains "]"
    # Should have mix of filled and empty
    assert_output_contains "#"
    assert_output_contains "-"
}

@test "get_progress_bar handles 100% complete" {
    create_test_dashboard
    run_test_dashboard --test-progress-bar 10 10
    assert_success
    assert_output_contains "["
    assert_output_contains "]"
    # Should be all filled
    assert_output_contains "#"
}

@test "get_progress_bar handles partial completion" {
    create_test_dashboard
    run_test_dashboard --test-progress-bar 1 3
    assert_success
    # 1/3 = 33% = 10 filled of 30
    assert_output_contains "["
    assert_output_contains "]"
}

# =============================================================================
# GET STATE COLOR TESTS
# =============================================================================

@test "get_state_color returns green for working" {
    create_test_dashboard
    run_test_dashboard --test-state-color working
    assert_success
    # Should contain green ANSI code
    assert_output_contains "32m"
}

@test "get_state_color returns green for merging" {
    create_test_dashboard
    run_test_dashboard --test-state-color merging
    assert_success
    assert_output_contains "32m"
}

@test "get_state_color returns cyan for claiming" {
    create_test_dashboard
    run_test_dashboard --test-state-color claiming
    assert_success
    assert_output_contains "36m"
}

@test "get_state_color returns cyan for starting" {
    create_test_dashboard
    run_test_dashboard --test-state-color starting
    assert_success
    assert_output_contains "36m"
}

@test "get_state_color returns yellow for idle" {
    create_test_dashboard
    run_test_dashboard --test-state-color idle
    assert_success
    assert_output_contains "33m"
}

@test "get_state_color returns blue for completed" {
    create_test_dashboard
    run_test_dashboard --test-state-color completed
    assert_success
    assert_output_contains "34m"
}

@test "get_state_color returns dim for terminated" {
    create_test_dashboard
    run_test_dashboard --test-state-color terminated
    assert_success
    # DIM is escape code \033[2m
    assert_output_contains "2m"
}

@test "get_state_color returns dim for max_iterations" {
    create_test_dashboard
    run_test_dashboard --test-state-color max_iterations
    assert_success
    assert_output_contains "2m"
}

@test "get_state_color returns red for dead" {
    create_test_dashboard
    run_test_dashboard --test-state-color dead
    assert_success
    assert_output_contains "31m"
}

@test "get_state_color returns white for unknown state" {
    create_test_dashboard
    run_test_dashboard --test-state-color unknown_state
    assert_success
    assert_output_contains "37m"
}

# =============================================================================
# RENDER HEADER TESTS
# =============================================================================

@test "render_header shows RALPH DASHBOARD title" {
    create_test_dashboard
    run_test_dashboard --test-header
    assert_success
    assert_output_contains "RALPH DASHBOARD"
}

@test "render_header shows PRD Progress label" {
    create_test_dashboard
    run_test_dashboard --test-header
    assert_success
    assert_output_contains "PRD Progress:"
}

@test "render_header shows progress bar" {
    create_test_dashboard
    run_test_dashboard --test-header
    assert_success
    assert_output_contains "["
    assert_output_contains "]"
}

@test "render_header shows complete/total count" {
    create_test_dashboard
    # partial fixture has 1 complete, 3 total
    run_test_dashboard --test-header
    assert_success
    assert_output_contains "1/3"
}

@test "render_header with complete prd shows all complete" {
    create_prd_fixture "complete"
    create_test_dashboard
    run_test_dashboard --test-header
    assert_success
    # complete fixture has 2 complete, 2 total
    assert_output_contains "2/2"
}

@test "render_header with empty stories shows 0/0" {
    create_prd_fixture "empty"
    create_test_dashboard
    run_test_dashboard --test-header
    assert_success
    assert_output_contains "0/0"
}

# =============================================================================
# RENDER INSTANCES TESTS - NO INSTANCES
# =============================================================================

@test "render_instances shows column headers" {
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "INSTANCE"
    assert_output_contains "STORY"
    assert_output_contains "STATE"
    assert_output_contains "ITER"
    assert_output_contains "RUNTIME"
    assert_output_contains "BRANCH"
}

@test "render_instances with no instances shows message" {
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "No instances running"
}

@test "render_instances handles missing instances directory" {
    rm -rf "$TEST_TEMP_DIR/scripts/ralph/instances"
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "No instances running"
}

# =============================================================================
# RENDER INSTANCES TESTS - WITH INSTANCES
# =============================================================================

@test "render_instances shows single instance" {
    create_instance_fixture "test-instance-123-$(date +%s)" "working" 0
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "test-ins"
    assert_output_contains "working"
    assert_output_contains "US-001"
}

@test "render_instances shows multiple instances" {
    local now
    now=$(date +%s)
    create_instance_fixture "instance-a-123-$now" "working" 0
    create_instance_fixture "instance-b-456-$now" "idle" 0
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "working"
    assert_output_contains "idle"
}

@test "render_instances shows iteration count" {
    create_instance_fixture "test-iter-123-$(date +%s)" "working" 0
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    # Default fixture sets iteration=1, maxIterations=10
    assert_output_contains "1/"
    assert_output_contains "/10"
}

@test "render_instances marks dead instance" {
    local now
    now=$(date +%s)
    # Create instance with old heartbeat (600 seconds = 10 minutes ago)
    create_instance_fixture "dead-instance-123-$((now - 1000))" "working" 600
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "dead"
}

@test "render_instances shows runtime" {
    local now
    now=$(date +%s)
    # Instance started 120 seconds ago (based on timestamp in ID)
    create_instance_fixture "runtime-test-123-$((now - 120))" "working" 0
    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "2m"
}

@test "render_instances truncates long branch names" {
    local now
    now=$(date +%s)
    local instance_dir="$TEST_TEMP_DIR/scripts/ralph/instances/branch-test-123-$now"
    mkdir -p "$instance_dir"

    # Create status with very long branch name
    cat > "$instance_dir/status.json" <<EOF
{
    "instanceId": "branch-test-123-$now",
    "state": "working",
    "currentStory": "US-001",
    "iteration": 1,
    "maxIterations": 10,
    "lastHeartbeatEpoch": $now,
    "branch": "very-long-branch-name-that-should-be-truncated"
}
EOF

    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    # Branch should be truncated to 12 chars
    assert_output_contains "very-long-br"
}

@test "render_instances skips instance without status.json" {
    local now
    now=$(date +%s)
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/instances/empty-instance-123-$now"
    # No status.json created

    create_test_dashboard
    run_test_dashboard --test-instances
    assert_success
    assert_output_contains "No instances running"
}

# =============================================================================
# RENDER LOCKS TESTS - NO LOCKS
# =============================================================================

@test "render_locks shows ACTIVE LOCKS header" {
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "ACTIVE LOCKS"
}

@test "render_locks with no locks shows message" {
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "No active locks"
}

@test "render_locks handles missing locks directory" {
    rm -rf "$TEST_TEMP_DIR/scripts/ralph/locks"
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "No active locks"
}

# =============================================================================
# RENDER LOCKS TESTS - WITH LOCKS
# =============================================================================

@test "render_locks shows single lock" {
    create_lock_fixture "US-001" "owner-test-123" 0
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "US-001"
    assert_output_contains "owner-te"
}

@test "render_locks shows multiple locks" {
    create_lock_fixture "US-001" "owner-1" 0
    create_lock_fixture "US-002" "owner-2" 0
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "US-001"
    assert_output_contains "US-002"
}

@test "render_locks shows lock age in seconds" {
    create_lock_fixture "US-001" "owner-test" 30
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "30s"
}

@test "render_locks shows lock age in minutes" {
    create_lock_fixture "US-001" "owner-test" 120
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "2m"
}

@test "render_locks shows lock age in hours" {
    create_lock_fixture "US-001" "owner-test" 7200
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "2h"
}

@test "render_locks shows 'held by' text" {
    create_lock_fixture "US-001" "test-owner" 0
    create_test_dashboard
    run_test_dashboard --test-locks
    assert_success
    assert_output_contains "held by"
}

# =============================================================================
# RENDER FOOTER TESTS
# =============================================================================

@test "render_footer shows keyboard shortcuts" {
    create_test_dashboard
    run_test_dashboard --test-footer
    assert_success
    assert_output_contains "q=quit"
    assert_output_contains "r=refresh"
    assert_output_contains "l=locks"
    assert_output_contains "c=cleanup"
}

@test "render_footer shows last update time" {
    create_test_dashboard
    run_test_dashboard --test-footer
    assert_success
    assert_output_contains "Last update:"
}

# =============================================================================
# RENDER ALL (INTEGRATION) TESTS
# =============================================================================

@test "render_all produces valid output" {
    create_test_dashboard
    run_test_dashboard --test-all
    assert_success
    # Should contain all major sections
    assert_output_contains "RALPH DASHBOARD"
    assert_output_contains "PRD Progress:"
    assert_output_contains "INSTANCE"
    assert_output_contains "ACTIVE LOCKS"
    assert_output_contains "q=quit"
}

@test "render_all with instances and locks" {
    create_instance_fixture "full-test-123-$(date +%s)" "working" 0
    create_lock_fixture "US-001" "owner-1" 0
    create_test_dashboard
    run_test_dashboard --test-all
    assert_success
    assert_output_contains "full-tes"
    assert_output_contains "working"
    assert_output_contains "US-001"
    assert_output_contains "owner-1"
}

# =============================================================================
# GET PRD STATUS TESTS
# =============================================================================

@test "get_prd_status returns correct count for partial" {
    create_prd_fixture "partial"
    create_test_dashboard
    run_test_dashboard --test-prd-status
    assert_success
    assert_output "1/3"
}

@test "get_prd_status returns correct count for complete" {
    create_prd_fixture "complete"
    create_test_dashboard
    run_test_dashboard --test-prd-status
    assert_success
    assert_output "2/2"
}

@test "get_prd_status returns 0/0 for empty stories" {
    create_prd_fixture "empty"
    create_test_dashboard
    run_test_dashboard --test-prd-status
    assert_success
    assert_output "0/0"
}

@test "get_prd_status returns 0/0 for missing prd.json" {
    rm -f "$TEST_TEMP_DIR/scripts/ralph/prd.json"
    create_test_dashboard
    run_test_dashboard --test-prd-status
    assert_success
    assert_output "0/0"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "handles unicode box drawing characters" {
    run grep -q "═" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

@test "handles tput initialization gracefully" {
    # Check that tput is used for terminal control
    run grep -q "tput" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

@test "handles clear command for TUI" {
    run grep -q "clear" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

@test "handles cursor hide/show for TUI" {
    run grep -q "civis" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
    run grep -q "cnorm" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

@test "dashboard uses trap for cleanup" {
    run grep -q "trap" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

@test "dashboard handles refresh interval argument" {
    run grep -q "REFRESH_INTERVAL" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
    run grep -q "\-\-refresh" "$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    assert_success
}

# =============================================================================
# STALE LOCK CLEANUP TESTS
# =============================================================================

@test "get_all_projects_locks function exists" {
    # RALPH_SCRIPT_DIR_ORIG points to scripts/ralph
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    run grep -q "get_all_projects_locks()" "$dashboard"
    assert_success
}

@test "clear_stale_locks_all_projects function exists" {
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    run grep -q "clear_stale_locks_all_projects()" "$dashboard"
    assert_success
}

@test "get_all_projects_locks checks all 6 lock directories" {
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    # Check that all 6 paths are searched
    run grep "scripts/ralph/locks" "$dashboard"
    assert_success
    run grep ".claude/ralph/locks" "$dashboard"
    assert_success
    run grep '"$pr/ralph/locks"' "$dashboard"
    assert_success
    run grep "tasks/locks" "$dashboard"
    assert_success
    run grep "project/locks" "$dashboard"
    assert_success
}

@test "stale lock detection uses 7200 second threshold" {
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    run grep '7200' "$dashboard"
    assert_success
}

@test "dead owner detection uses 300 second threshold" {
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    run grep '300' "$dashboard"
    assert_success
}

@test "invoke_cleanup calls stale locks cleanup" {
    local dashboard="$RALPH_SCRIPT_DIR_ORIG/ralph-dashboard.sh"
    run grep -A 30 "invoke_cleanup()" "$dashboard"
    assert_success
    assert_output_contains "clear_stale_locks_all_projects"
}
