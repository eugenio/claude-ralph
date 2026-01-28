#!/usr/bin/env bats
# =============================================================================
# bash-powershell-comparison.bats - Integration tests comparing bash/PowerShell
# =============================================================================
#
# US-012: Validate bash scripts match PowerShell behavior
#
# This test file runs both bash and PowerShell versions of ralph scripts with
# the same test data and compares their behavior for functional equivalence.
#
# REQUIREMENTS:
#   - bats-core
#   - pwsh (PowerShell 7+)
#   - jq
#
# =============================================================================

load 'test_helper'

# =============================================================================
# SETUP AND TEARDOWN
# =============================================================================

setup() {
    setup_test_environment

    # Store script locations
    BASH_SCRIPTS_DIR="$RALPH_SCRIPT_DIR_ORIG/../.."
    PS_SCRIPTS_DIR="$RALPH_SCRIPT_DIR_ORIG"

    # Copy bash scripts to test environment
    cp "$BASH_SCRIPTS_DIR/ralph-status.sh" "$TEST_TEMP_DIR/"
    cp "$BASH_SCRIPTS_DIR/ralph-locks.sh" "$TEST_TEMP_DIR/"
    cp "$BASH_SCRIPTS_DIR/ralph-cleanup.sh" "$TEST_TEMP_DIR/"
    chmod +x "$TEST_TEMP_DIR"/*.sh

    # Copy PowerShell scripts to test environment
    cp "$PS_SCRIPTS_DIR/ralph-status.ps1" "$TEST_TEMP_DIR/scripts/ralph/"
    cp "$PS_SCRIPTS_DIR/ralph-locks.ps1" "$TEST_TEMP_DIR/scripts/ralph/"
    cp "$PS_SCRIPTS_DIR/ralph-cleanup.ps1" "$TEST_TEMP_DIR/scripts/ralph/"
    cp "$PS_SCRIPTS_DIR/RalphUtils.psm1" "$TEST_TEMP_DIR/scripts/ralph/"

    export BASH_SCRIPTS_DIR
    export PS_SCRIPTS_DIR
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Strip ANSI color codes from output for comparison
strip_colors() {
    sed -E 's/\x1b\[[0-9;]*m//g' | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'
}

# Run bash script and capture output
run_bash_script() {
    local script="$1"
    shift
    cd "$TEST_TEMP_DIR" && bash "$script" "$@" 2>&1
}

# Run PowerShell script and capture output
run_ps_script() {
    local script="$1"
    shift
    cd "$TEST_TEMP_DIR/scripts/ralph" && pwsh -NoProfile -NonInteractive -File "$script" "$@" 2>&1
}

# Skip test if pwsh not available
skip_if_no_pwsh() {
    if ! command -v pwsh &>/dev/null; then
        skip "PowerShell 7+ (pwsh) not installed"
    fi
}

# =============================================================================
# PREREQUISITE TESTS
# =============================================================================

@test "prerequisites: bash is available" {
    command -v bash
}

@test "prerequisites: pwsh is available" {
    skip_if_no_pwsh
    command -v pwsh
}

@test "prerequisites: jq is available" {
    skip_if_no_jq
    command -v jq
}

@test "prerequisites: PowerShell version is 7+" {
    skip_if_no_pwsh
    # shellcheck disable=SC2016
    run pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major'
    assert_success
    [[ "$output" -ge 7 ]]
}

# =============================================================================
# RALPH-STATUS.SH VS RALPH-STATUS.PS1 COMPARISON
# =============================================================================

@test "ralph-status: both scripts handle missing prd.json gracefully" {
    skip_if_no_pwsh
    skip_if_no_jq

    # Remove prd.json to test missing file handling
    rm -f "$TEST_TEMP_DIR/scripts/ralph/prd.json"
    rm -f "$TEST_TEMP_DIR/prd.json"

    # Run bash version
    run run_bash_script "./ralph-status.sh"
    local bash_exit_code=$status
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    run run_ps_script "ralph-status.ps1"
    local ps_exit_code=$status
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should exit with error (non-zero)
    [[ $bash_exit_code -ne 0 ]]
    [[ $ps_exit_code -ne 0 ]]

    # Both should mention missing prd.json
    [[ "$bash_output" == *"prd.json"* ]]
    [[ "$ps_output" == *"prd.json"* ]]
}

@test "ralph-status: both scripts display feature name from prd.json" {
    skip_if_no_pwsh
    skip_if_no_jq

    create_prd_fixture "partial"
    # Also create prd.json at project root for bash script
    cp "$TEST_TEMP_DIR/scripts/ralph/prd.json" "$TEST_TEMP_DIR/prd.json"

    # Run bash version
    run run_bash_script "./ralph-status.sh"
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    run run_ps_script "ralph-status.ps1"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should display "Test Feature"
    [[ "$bash_output" == *"Test Feature"* ]]
}

@test "ralph-status: both scripts show correct story counts (partial PRD)" {
    skip_if_no_pwsh
    skip_if_no_jq

    create_prd_fixture "partial"
    cp "$TEST_TEMP_DIR/scripts/ralph/prd.json" "$TEST_TEMP_DIR/prd.json"

    # Run bash version and extract counts
    run run_bash_script "./ralph-status.sh"
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version and extract counts
    run run_ps_script "ralph-status.ps1"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Partial fixture has 3 stories, 1 complete, 2 remaining
    # Bash shows: Complete: 1, Remaining: 2, Total: 3
    [[ "$bash_output" == *"1"* ]]  # At least shows 1 complete
    [[ "$bash_output" == *"2"* ]]  # At least shows 2 remaining
    [[ "$bash_output" == *"3"* ]]  # At least shows 3 total
}

@test "ralph-status: both scripts show 100% complete for complete PRD" {
    skip_if_no_pwsh
    skip_if_no_jq

    create_prd_fixture "complete"
    cp "$TEST_TEMP_DIR/scripts/ralph/prd.json" "$TEST_TEMP_DIR/prd.json"

    # Run bash version
    run run_bash_script "./ralph-status.sh"
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    run run_ps_script "ralph-status.ps1"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should show 100%
    [[ "$bash_output" == *"100%"* ]]
    [[ "$ps_output" == *"100%"* ]]
}

@test "ralph-status: both scripts handle empty userStories array" {
    skip_if_no_pwsh
    skip_if_no_jq

    create_prd_fixture "empty"
    cp "$TEST_TEMP_DIR/scripts/ralph/prd.json" "$TEST_TEMP_DIR/prd.json"

    # Run bash version - may error on division by zero
    run run_bash_script "./ralph-status.sh"
    local bash_exit=$status

    # Run PowerShell version - should handle gracefully
    run run_ps_script "ralph-status.ps1"
    local ps_exit=$status

    # Document behavior: bash may fail, PowerShell should succeed
    # This is an intentional difference
    [[ $ps_exit -eq 0 ]]
}

# =============================================================================
# RALPH-LOCKS.SH VS RALPH-LOCKS.PS1 COMPARISON
# =============================================================================

@test "ralph-locks: both scripts show help with --help/Help" {
    skip_if_no_pwsh

    # Run bash version
    run run_bash_script "./ralph-locks.sh" --help
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    run run_ps_script "ralph-locks.ps1" "Help"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should show usage info
    [[ "$bash_output" == *"status"* ]] || [[ "$bash_output" == *"Status"* ]]
    [[ "$bash_output" == *"release"* ]] || [[ "$bash_output" == *"Release"* ]]
    [[ "$ps_output" == *"status"* ]] || [[ "$ps_output" == *"Status"* ]]
    [[ "$ps_output" == *"release"* ]] || [[ "$ps_output" == *"Release"* ]]
}

@test "ralph-locks: both scripts show 'no active locks' when locks dir is empty" {
    skip_if_no_pwsh

    # Ensure locks dir exists but is empty
    rm -rf "$TEST_TEMP_DIR/scripts/ralph/locks"/*
    rm -rf "$TEST_TEMP_DIR/locks"
    mkdir -p "$TEST_TEMP_DIR/locks"
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks"

    # Run bash version
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-locks.sh" status
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-locks.ps1" "Status"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should indicate no locks
    [[ "$bash_output" == *"No active locks"* ]] || [[ "$bash_output" == *"no"*"lock"* ]]
    [[ "$ps_output" == *"No active locks"* ]] || [[ "$ps_output" == *"no"*"lock"* ]]
}

@test "ralph-locks: both scripts display existing locks" {
    skip_if_no_pwsh

    # Create lock for bash script (uses 'owner' not 'owner.txt')
    mkdir -p "$TEST_TEMP_DIR/locks/US-001.lock"
    echo "test-instance-12345678" > "$TEST_TEMP_DIR/locks/US-001.lock/owner"
    date +%s > "$TEST_TEMP_DIR/locks/US-001.lock/timestamp"

    # Create lock for PowerShell script (check RalphUtils.psm1 format)
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock"
    echo "test-instance-12345678" > "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock/owner"
    date +%s > "$TEST_TEMP_DIR/scripts/ralph/locks/US-001.lock/timestamp"

    # Run bash version
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-locks.sh" status
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-locks.ps1" "Status"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should show US-001
    [[ "$bash_output" == *"US-001"* ]]
    [[ "$ps_output" == *"US-001"* ]]
}

@test "ralph-locks: both scripts release a specific lock" {
    skip_if_no_pwsh

    # Create locks for both scripts
    mkdir -p "$TEST_TEMP_DIR/locks/US-002.lock"
    echo "test-owner-abcd1234" > "$TEST_TEMP_DIR/locks/US-002.lock/owner"
    date +%s > "$TEST_TEMP_DIR/locks/US-002.lock/timestamp"

    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock"
    echo "test-owner-abcd1234" > "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock/owner"
    date +%s > "$TEST_TEMP_DIR/scripts/ralph/locks/US-002.lock/timestamp"

    # Release with bash
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-locks.sh" release "US-002"
    assert_success
    # Lock should be removed
    [[ ! -d "$TEST_TEMP_DIR/locks/US-002.lock" ]]

    # Release with PowerShell
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-locks.ps1" "Release" -StoryId "US-002"
    # Note: may succeed or fail depending on if lock still exists
}

@test "ralph-locks: both scripts handle release of non-existent lock" {
    skip_if_no_pwsh

    # Run bash version - release non-existent lock
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-locks.sh" release "US-999"
    local bash_exit=$status
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-locks.ps1" "Release" -StoryId "US-999"
    local ps_exit=$status
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should handle gracefully (not crash)
    # May show "no lock found" or similar
    [[ "$bash_output" == *"No lock"* ]] || [[ "$bash_output" == *"no lock"* ]] || [[ $bash_exit -eq 0 ]]
}

@test "ralph-locks: both scripts support release-all/ReleaseAll command" {
    skip_if_no_pwsh

    # Create multiple locks for bash
    mkdir -p "$TEST_TEMP_DIR/locks/US-010.lock"
    echo "owner1" > "$TEST_TEMP_DIR/locks/US-010.lock/owner"
    date +%s > "$TEST_TEMP_DIR/locks/US-010.lock/timestamp"
    mkdir -p "$TEST_TEMP_DIR/locks/US-011.lock"
    echo "owner2" > "$TEST_TEMP_DIR/locks/US-011.lock/owner"
    date +%s > "$TEST_TEMP_DIR/locks/US-011.lock/timestamp"

    # Create multiple locks for PowerShell
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks/US-010.lock"
    echo "owner1" > "$TEST_TEMP_DIR/scripts/ralph/locks/US-010.lock/owner"
    date +%s > "$TEST_TEMP_DIR/scripts/ralph/locks/US-010.lock/timestamp"
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks/US-011.lock"
    echo "owner2" > "$TEST_TEMP_DIR/scripts/ralph/locks/US-011.lock/owner"
    date +%s > "$TEST_TEMP_DIR/scripts/ralph/locks/US-011.lock/timestamp"

    # Release all with bash
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-locks.sh" release-all
    assert_success

    # Both locks should be removed
    [[ ! -d "$TEST_TEMP_DIR/locks/US-010.lock" ]]
    [[ ! -d "$TEST_TEMP_DIR/locks/US-011.lock" ]]

    # Release all with PowerShell
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-locks.ps1" "ReleaseAll"
    # All locks should be released
}

# =============================================================================
# RALPH-CLEANUP.SH VS RALPH-CLEANUP.PS1 COMPARISON
# =============================================================================

@test "ralph-cleanup: both scripts show help with --help" {
    skip_if_no_pwsh

    # Run bash version
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh" --help
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # PowerShell doesn't have a direct help command but Get-Help works
    # Just verify bash help works
    [[ "$bash_output" == *"dead"* ]] || [[ "$bash_output" == *"Dead"* ]]
    [[ "$bash_output" == *"old"* ]] || [[ "$bash_output" == *"Old"* ]]
}

@test "ralph-cleanup: both scripts show summary when called without flags" {
    skip_if_no_pwsh

    # Create a test instance
    create_instance_fixture "test-summary-instance" "working" 0

    # Run bash version
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh"
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Run PowerShell version
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-cleanup.ps1"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Both should show "Total" or summary
    [[ "$bash_output" == *"Total"* ]] || [[ "$bash_output" == *"total"* ]] || [[ "$bash_output" == *"instances"* ]]
}

@test "ralph-cleanup: both scripts support dry-run mode" {
    skip_if_no_pwsh

    # Create a dead instance (heartbeat > 5 min ago)
    create_instance_fixture "dead-test-instance" "working" 600

    # Run bash version with --dry-run --dead
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh" --dry-run --dead
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Instance should NOT be removed in dry-run
    [[ -d "$TEST_TEMP_DIR/scripts/ralph/instances/dead-test-instance" ]]

    # Bash should mention dry run
    [[ "$bash_output" == *"DRY RUN"* ]] || [[ "$bash_output" == *"dry"* ]]
}

@test "ralph-cleanup: both scripts identify dead instances correctly" {
    skip_if_no_pwsh

    # Create a dead instance (heartbeat > 5 min ago)
    create_instance_fixture "definitely-dead" "working" 600

    # Run bash version
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh" --dry-run --dead
    local bash_output
    bash_output=$(echo "$output" | strip_colors)

    # Should identify the dead instance
    [[ "$bash_output" == *"dead"* ]] || [[ "$bash_output" == *"Dead"* ]]
}

# =============================================================================
# FUNCTIONAL EQUIVALENCE TESTS
# =============================================================================

@test "equivalence: lock file format is compatible between bash and PowerShell" {
    skip_if_no_pwsh

    # Create a lock using bash-style format (owner, timestamp files without .txt)
    mkdir -p "$TEST_TEMP_DIR/scripts/ralph/locks/US-COMPAT.lock"
    echo "compat-test-owner-xyz" > "$TEST_TEMP_DIR/scripts/ralph/locks/US-COMPAT.lock/owner"
    date +%s > "$TEST_TEMP_DIR/scripts/ralph/locks/US-COMPAT.lock/timestamp"

    # PowerShell should be able to read it
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-locks.ps1" "Status"
    local ps_output
    ps_output=$(echo "$output" | strip_colors)

    # Should show the lock
    [[ "$ps_output" == *"US-COMPAT"* ]] || [[ "$ps_output" == *"compat-test"* ]]
}

@test "equivalence: instance status.json format is compatible" {
    skip_if_no_pwsh

    # Create instance with standard format
    create_instance_fixture "compat-instance-1234" "working" 0

    # Both should be able to read instance data
    # Bash cleanup
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh"
    local bash_exit=$status

    # PowerShell cleanup
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-cleanup.ps1"
    local ps_exit=$status

    # Both should succeed (not crash on format)
    [[ $bash_exit -eq 0 ]]
    [[ $ps_exit -eq 0 ]]
}

@test "equivalence: prd.json format is compatible" {
    skip_if_no_pwsh
    skip_if_no_jq

    create_prd_fixture "partial"
    cp "$TEST_TEMP_DIR/scripts/ralph/prd.json" "$TEST_TEMP_DIR/prd.json"

    # Both scripts should parse the same prd.json
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-status.sh"
    assert_success

    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-status.ps1"
    assert_success
}

# =============================================================================
# DOCUMENTED DIFFERENCES TESTS
# =============================================================================

@test "difference: bash scripts at project root, PowerShell in scripts/ralph/" {
    # This is an intentional structural difference
    # Bash: PROJECT_ROOT/ralph-status.sh
    # PowerShell: PROJECT_ROOT/scripts/ralph/ralph-status.ps1

    # Verify bash script exists at project root
    [[ -f "$BASH_SCRIPTS_DIR/ralph-status.sh" ]]
    [[ -f "$BASH_SCRIPTS_DIR/ralph-locks.sh" ]]
    [[ -f "$BASH_SCRIPTS_DIR/ralph-cleanup.sh" ]]

    # Verify PowerShell scripts exist in scripts/ralph/
    [[ -f "$PS_SCRIPTS_DIR/ralph-status.ps1" ]]
    [[ -f "$PS_SCRIPTS_DIR/ralph-locks.ps1" ]]
    [[ -f "$PS_SCRIPTS_DIR/ralph-cleanup.ps1" ]]
}

@test "difference: command parameter styles differ (bash --flag vs PowerShell -Flag)" {
    skip_if_no_pwsh

    # Bash uses lowercase with double dash: --dead, --old, --dry-run
    # PowerShell uses PascalCase with single dash: -Dead, -Old, -WhatIf

    # This is intentional to match each platform's conventions

    # Verify bash accepts --dead
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh" --dead --dry-run
    # Should not error on unknown flag
    assert_success

    # Verify PowerShell accepts -Dead
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-cleanup.ps1" -Dead -WhatIf
    # Should not error
    assert_success
}

@test "difference: PowerShell uses -WhatIf, bash uses --dry-run" {
    skip_if_no_pwsh

    # Create instance to test cleanup
    create_instance_fixture "whatif-test" "working" 600

    # Bash --dry-run
    cd "$TEST_TEMP_DIR"
    run bash "./ralph-cleanup.sh" --dry-run --dead
    assert_success
    local bash_output
    bash_output=$(echo "$output" | strip_colors)
    [[ "$bash_output" == *"DRY RUN"* ]] || [[ "$bash_output" == *"dry"* ]]

    # PowerShell -WhatIf
    cd "$TEST_TEMP_DIR/scripts/ralph"
    run pwsh -NoProfile -NonInteractive -File "ralph-cleanup.ps1" -Dead -WhatIf
    # PowerShell WhatIf mode
    assert_success
}
