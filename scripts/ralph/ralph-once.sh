#!/usr/bin/env bash
# =============================================================================
# ralph-once.sh - Single iteration runner for ralph
# =============================================================================
#
# DESCRIPTION:
#   Runs a single iteration of Claude Code for the current PRD.
#   Useful for testing or manual control over the execution flow.
#   Unlike ralph.sh, this script does not loop or archive previous runs.
#
# USAGE:
#   ./ralph-once.sh
#
# REQUIREMENTS:
#   - Bash 4.0+
#   - Claude Code CLI (claude)
#   - jq (for JSON parsing)
#   - git
#
# =============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
if [[ ! -f "$SCRIPT_DIR/ralph-utils.sh" ]]; then
    echo "Error: ralph-utils.sh not found in script directory" >&2
    exit 1
fi
# shellcheck source=ralph-utils.sh
source "$SCRIPT_DIR/ralph-utils.sh"

# Load paths
eval "$(get_ralph_paths)"

# =============================================================================
# DISPLAY FUNCTIONS
# =============================================================================

show_banner() {
    echo ""
    write_colored blue "$(printf '═%.0s' {1..55})"
    write_colored yellow "           RALPH SINGLE ITERATION"
    write_colored blue "$(printf '═%.0s' {1..55})"
}

show_status() {
    local total="$1"
    local complete="$2"
    local remaining="$3"

    if [[ "$total" -eq 0 ]]; then
        write_colored yellow "No PRD file found or empty"
        return
    fi

    write_colored cyan "Stories: " -n
    write_colored green "$complete" -n
    printf "/%s complete, " "$total"
    write_colored yellow "$remaining" -n
    printf " remaining\n"
}

# =============================================================================
# CLAUDE CODE EXECUTION
# =============================================================================

invoke_claude_code() {
    local prompt_path="$1"
    local project_root="$2"

    write_colored yellow "Running Claude Code..."
    echo ""

    # Read the prompt content
    if [[ ! -f "$prompt_path" ]]; then
        write_colored red "Error: Prompt file not found: $prompt_path"
        return 1
    fi

    local prompt_content
    prompt_content=$(cat "$prompt_path")

    # Save current directory
    local original_dir
    original_dir=$(pwd)

    # Change to project root
    cd "$project_root" || {
        write_colored red "Error: Failed to change to project root: $project_root"
        return 1
    }

    # Run Claude Code with piped input
    # Using -p for non-interactive (print) mode
    # Using --dangerously-skip-permissions for full autonomy
    # Using --verbose for detailed output
    local output exit_code

    # Capture output and display it (tee-like behavior)
    # Check if stderr is a TTY for proper output handling
    if [[ -t 2 ]]; then
        # stderr is a TTY, tee to stderr for live display
        output=$(echo "$prompt_content" | claude -p --dangerously-skip-permissions --verbose 2>&1 | tee /dev/stderr)
        exit_code=$?
    else
        # No TTY (non-interactive mode), just capture output
        output=$(echo "$prompt_content" | claude -p --dangerously-skip-permissions --verbose 2>&1)
        exit_code=$?
        # Print output after capture
        if [[ -n "$output" ]]; then
            echo "$output"
        fi
    fi

    # Return to original directory
    cd "$original_dir" || true

    # Set global variables for result
    CLAUDE_OUTPUT="$output"
    CLAUDE_EXIT_CODE="$exit_code"

    return $exit_code
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Check dependencies
    if ! test_dependencies; then
        exit 1
    fi

    # Check for PRD file
    if [[ ! -f "$PRD_FILE" ]]; then
        write_colored red "Error: prd.json not found in $RALPH_DIR"
        echo "Create a prd.json file with your user stories first."
        echo "See prd.json.example for the expected format."
        exit 1
    fi

    # Read PRD
    local prd_json
    if ! prd_json=$(read_prd_json); then
        write_colored red "Error: Failed to read prd.json"
        exit 1
    fi

    # Show banner
    show_banner

    # Get and show current status
    eval "$(get_prd_status "$prd_json")"
    show_status "$PRD_TOTAL" "$PRD_COMPLETE" "$PRD_REMAINING"
    echo ""

    # Save initial completion count for comparison
    local initial_complete="$PRD_COMPLETE"

    # Check if already complete
    if [[ "$PRD_REMAINING" -eq 0 ]]; then
        write_colored green "All stories already complete!"
        exit 0
    fi

    # Run Claude Code
    CLAUDE_OUTPUT=""
    CLAUDE_EXIT_CODE=0

    if ! invoke_claude_code "$PROMPT_FILE" "$PROJECT_ROOT"; then
        write_colored red "Claude Code exited with code $CLAUDE_EXIT_CODE"
    fi

    # Check for completion signal
    local has_signal=false
    if [[ -n "$CLAUDE_OUTPUT" ]]; then
        if echo "$CLAUDE_OUTPUT" | grep -q '<promise>COMPLETE</promise>'; then
            has_signal=true
        fi
    fi

    if [[ "$has_signal" == "true" ]]; then
        echo ""
        write_colored green "All stories complete!"
    else
        # Show updated status
        echo ""
        write_colored blue "$(printf '═%.0s' {1..55})"

        # Re-read PRD to get latest status (Claude may have updated it)
        prd_json=$(read_prd_json 2>/dev/null) || prd_json=""
        eval "$(get_prd_status "$prd_json")"

        write_colored cyan "Completed: " -n
        write_colored green "$PRD_COMPLETE" -n
        printf "/%s stories\n" "$PRD_TOTAL"

        if [[ "$PRD_COMPLETE" -gt "$initial_complete" ]]; then
            write_colored green "Progress made! Run again to continue."
        else
            write_colored yellow "No new stories completed. Check progress.txt for details."
        fi
    fi
}

# Run main
main "$@"
