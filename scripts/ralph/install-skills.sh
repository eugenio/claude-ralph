#!/usr/bin/env bash
#
# install-skills.sh - Installs ralph skills globally to ~/.claude/skills/
#
# SYNOPSIS
#   ./install-skills.sh [OPTIONS]
#
# DESCRIPTION
#   Copies all skills from the ralph skills directory to the global Claude Code
#   skills directory (~/.claude/skills/). This makes the skills available for
#   interactive Claude Code sessions in any project.
#
#   Existing skills are updated (overwritten) when this script runs.
#
#   Optionally installs shell functions for ralph, ralph-once, ralph-status,
#   ralph-parallel, and ralph-dashboard to your shell profile (.bashrc and/or .zshrc).
#
# OPTIONS
#   --force         Updates profile without prompting for confirmation.
#                   For outdated functions, automatically updates in-place.
#   --check         Only reports status without making changes.
#   --skip-aliases  Skips alias installation entirely.
#   -h, --help      Shows this help message.
#
# EXAMPLES
#   ./install-skills.sh                    # Interactive installation
#   ./install-skills.sh --force            # Force update without prompts
#   ./install-skills.sh --check            # Check status only
#   ./install-skills.sh --skip-aliases     # Install skills only
#   ./install-skills.sh --force --skip-aliases  # Force install skills only
#

set -euo pipefail

# Command-line flags
FORCE=false
CHECK=false
SKIP_ALIASES=false

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared utilities
if [[ -f "$SCRIPT_DIR/ralph-utils.sh" ]]; then
    source "$SCRIPT_DIR/ralph-utils.sh"
fi

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE=true
                shift
                ;;
            --check)
                CHECK=true
                shift
                ;;
            --skip-aliases)
                SKIP_ALIASES=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_colored "$RED" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Install ralph skills globally and optionally add shell functions."
    echo ""
    echo "Options:"
    echo "  --force         Update profile without prompting"
    echo "  --check         Only report status, make no changes"
    echo "  --skip-aliases  Skip alias installation"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                        # Interactive installation"
    echo "  $0 --force                # Force update without prompts"
    echo "  $0 --check                # Check status only"
    echo "  $0 --skip-aliases         # Install skills only"
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

print_colored() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

show_banner() {
    echo ""
    print_colored "$BLUE" "═══════════════════════════════════════════════════════"
    print_colored "$YELLOW" "         RALPH SKILL INSTALLER"
    print_colored "$BLUE" "═══════════════════════════════════════════════════════"
}

get_source_skills_path() {
    # Skills are at repo root (../../skills from scripts/ralph/)
    echo "$SCRIPT_DIR/../../skills"
}

get_destination_skills_path() {
    echo "$HOME/.claude/skills"
}

get_ralph_scripts_path() {
    # Check if we're in scripts/ralph or repo root
    if [[ -f "$SCRIPT_DIR/ralph.sh" ]]; then
        echo "$SCRIPT_DIR"
    elif [[ -f "$SCRIPT_DIR/scripts/ralph/ralph.sh" ]]; then
        echo "$SCRIPT_DIR/scripts/ralph"
    else
        echo "$SCRIPT_DIR"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Skill Installation
# ─────────────────────────────────────────────────────────────────────────────

install_skills() {
    local source_path
    local dest_path
    local skills_installed=()
    local errors=()

    source_path="$(get_source_skills_path)"
    dest_path="$(get_destination_skills_path)"

    # Check if source skills directory exists
    if [[ ! -d "$source_path" ]]; then
        print_colored "$RED" "Error: Source skills directory not found: $source_path"
        return 1
    fi

    # Get all skill directories
    local skill_dirs=()
    while IFS= read -r -d '' dir; do
        skill_dirs+=("$dir")
    done < <(find "$source_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    if [[ ${#skill_dirs[@]} -eq 0 ]]; then
        print_colored "$RED" "Error: No skills found in: $source_path"
        return 1
    fi

    # Create destination directory if it doesn't exist
    if [[ ! -d "$dest_path" ]]; then
        if mkdir -p "$dest_path" 2>/dev/null; then
            print_colored "$GRAY" "Created directory: $dest_path"
        else
            print_colored "$RED" "Error: Failed to create destination directory: $dest_path"
            return 1
        fi
    fi

    # Copy each skill
    for skill_dir in "${skill_dirs[@]}"; do
        local skill_name
        skill_name="$(basename "$skill_dir")"
        local skill_dest="$dest_path/$skill_name"

        # Remove existing skill directory if it exists (for clean overwrite)
        if [[ -d "$skill_dest" ]]; then
            rm -rf "$skill_dest" 2>/dev/null || true
        fi

        # Copy the skill directory
        if cp -r "$skill_dir" "$skill_dest" 2>/dev/null; then
            skills_installed+=("$skill_name")
        else
            errors+=("Failed to install skill '$skill_name'")
        fi
    done

    # Report results
    if [[ ${#skills_installed[@]} -gt 0 ]]; then
        print_colored "$GREEN" "Skills installed successfully!"
        echo ""
        print_colored "$CYAN" "Installed skills:"
        for skill in "${skills_installed[@]}"; do
            print_colored "$GREEN" "  - $skill"
        done
        echo ""
        print_colored "$GRAY" "Skills are now available globally in Claude Code."
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        print_colored "$RED" "Errors:"
        for err in "${errors[@]}"; do
            print_colored "$RED" "  - $err"
        done
        return 1
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Ralph Functions Detection and Comparison
# ─────────────────────────────────────────────────────────────────────────────

# Expected Ralph function names (scripts that should exist)
declare -a EXPECTED_FUNCTION_NAMES=()

populate_expected_ralph_functions() {
    # Populates EXPECTED_FUNCTION_NAMES array with expected function names
    # Must be called directly (not in a subshell) to preserve array values
    local ralph_dir
    ralph_dir="$(get_ralph_scripts_path)"

    EXPECTED_FUNCTION_NAMES=()
    EXPECTED_RALPH_DIR="$ralph_dir"

    # Define all expected Ralph functions
    local scripts=("ralph.sh" "ralph-once.sh" "ralph-status.sh" "ralph-parallel.sh" "ralph-dashboard.sh")
    local names=("ralph" "ralph-once" "ralph-status" "ralph-parallel" "ralph-dashboard")

    for i in "${!scripts[@]}"; do
        local script="${scripts[$i]}"
        local name="${names[$i]}"
        if [[ -f "$ralph_dir/$script" ]]; then
            EXPECTED_FUNCTION_NAMES+=("$name")
        fi
    done
}

get_expected_ralph_functions() {
    # Returns the expected Ralph function definitions for the profile
    # Note: Call populate_expected_ralph_functions first if you need the array values
    local ralph_dir
    ralph_dir="$(get_ralph_scripts_path)"

    local function_lines=()

    # Define all expected Ralph functions
    local scripts=("ralph.sh" "ralph-once.sh" "ralph-status.sh" "ralph-parallel.sh" "ralph-dashboard.sh")
    local names=("ralph" "ralph-once" "ralph-status" "ralph-parallel" "ralph-dashboard")

    for i in "${!scripts[@]}"; do
        local script="${scripts[$i]}"
        local name="${names[$i]}"
        if [[ -f "$ralph_dir/$script" ]]; then
            function_lines+=("$name() { \"$ralph_dir/$script\" \"\$@\"; }")
        fi
    done

    # Output the function block
    echo ""
    echo "# Ralph functions"
    printf '%s\n' "${function_lines[@]}"
}

get_profile_ralph_functions() {
    # Parses a profile file to extract existing Ralph functions block
    # Args: profile_path
    # Outputs: start_line|end_line|function_names|ralph_dir (pipe-separated)
    # Returns 0 if found, 1 if not found
    local profile_path="$1"

    if [[ ! -f "$profile_path" ]]; then
        echo "-1|-1||"
        return 1
    fi

    local content
    content="$(cat "$profile_path" 2>/dev/null)" || {
        echo "-1|-1||"
        return 1
    }

    # Find the Ralph functions marker
    local start_line=-1
    local line_num=0
    local found_names=()
    local ralph_dir=""
    local end_line=-1

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*Ralph\ functions[[:space:]]*$ ]]; then
            start_line=$line_num
        elif [[ $start_line -ge 0 ]]; then
            # Check if this is a Ralph function line
            if [[ "$line" =~ ^[[:space:]]*(ralph[-a-z]*)\(\)[[:space:]]*\{ ]]; then
                found_names+=("${BASH_REMATCH[1]}")
                end_line=$line_num
                # Extract the ralph directory from the function definition
                if [[ "$line" =~ \"([^\"]+)/ralph ]]; then
                    ralph_dir="${BASH_REMATCH[1]}"
                fi
            # Stop at a different comment section
            elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*[A-Za-z] && $line_num -gt $((start_line + 1)) ]]; then
                break
            # Stop at empty line after functions
            elif [[ "$line" =~ ^[[:space:]]*$ && ${#found_names[@]} -gt 0 ]]; then
                break
            # Non-Ralph content found after Ralph section
            elif [[ ! "$line" =~ ^[[:space:]]*$ && ! "$line" =~ ^[[:space:]]*(ralph[-a-z]*)\(\) ]]; then
                break
            fi
        fi
        ((line_num++)) || true
    done <<< "$content"

    if [[ $start_line -lt 0 ]]; then
        echo "-1|-1||"
        return 1
    fi

    # Use pipe as delimiter to avoid space parsing issues
    echo "$start_line|$end_line|${found_names[*]}|$ralph_dir"
    return 0
}

compare_ralph_functions() {
    # Compares expected Ralph functions against those installed in the profile
    # Args: profile_path
    # Sets global variables: COMPARE_STATUS, COMPARE_INSTALLED_COUNT, COMPARE_EXPECTED_COUNT
    #                       COMPARE_MISSING_FUNCTIONS, COMPARE_PATH_OUTDATED
    #                       COMPARE_INSTALLED_PATH, COMPARE_EXPECTED_PATH
    local profile_path="$1"

    # Populate expected functions array (must be called directly, not in subshell)
    populate_expected_ralph_functions
    local expected_path="$EXPECTED_RALPH_DIR"

    COMPARE_EXPECTED_COUNT=${#EXPECTED_FUNCTION_NAMES[@]}
    COMPARE_EXPECTED_PATH="$expected_path"
    COMPARE_INSTALLED_COUNT=0
    COMPARE_INSTALLED_PATH=""
    COMPARE_STATUS="missing"
    COMPARE_MISSING_FUNCTIONS=()
    COMPARE_PATH_OUTDATED=false

    # Parse installed functions
    local parse_result
    parse_result="$(get_profile_ralph_functions "$profile_path")" || {
        COMPARE_MISSING_FUNCTIONS=("${EXPECTED_FUNCTION_NAMES[@]}")
        return
    }

    # Parse pipe-delimited result
    local start_line end_line installed_names_str installed_path
    IFS='|' read -r start_line end_line installed_names_str installed_path <<< "$parse_result"

    if [[ $start_line -lt 0 ]]; then
        COMPARE_MISSING_FUNCTIONS=("${EXPECTED_FUNCTION_NAMES[@]}")
        return
    fi

    # Convert installed names string to array
    local installed_names=()
    if [[ -n "$installed_names_str" ]]; then
        read -ra installed_names <<< "$installed_names_str"
    fi

    COMPARE_INSTALLED_COUNT=${#installed_names[@]}
    COMPARE_INSTALLED_PATH="$installed_path"

    # Check for missing functions
    for expected in "${EXPECTED_FUNCTION_NAMES[@]}"; do
        local found=false
        for installed in "${installed_names[@]}"; do
            if [[ "$expected" == "$installed" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            COMPARE_MISSING_FUNCTIONS+=("$expected")
        fi
    done

    # Check if path is outdated
    if [[ -n "$installed_path" && "$installed_path" != "$expected_path" ]]; then
        COMPARE_PATH_OUTDATED=true
    fi

    # Determine overall status
    if [[ ${#COMPARE_MISSING_FUNCTIONS[@]} -eq 0 && "$COMPARE_PATH_OUTDATED" == false ]]; then
        COMPARE_STATUS="up-to-date"
    else
        COMPARE_STATUS="outdated"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Shell Alias Installation
# ─────────────────────────────────────────────────────────────────────────────

check_functions_exist() {
    local profile_path="$1"
    if [[ -f "$profile_path" ]] && grep -q "# Ralph functions" "$profile_path" 2>/dev/null; then
        return 0
    fi
    return 1
}

backup_profile_file() {
    # Creates a backup of the profile file before modification
    # Args: profile_path
    # Outputs: backup_path (or empty string on failure)
    local profile_path="$1"

    if [[ ! -f "$profile_path" ]]; then
        return 0
    fi

    local backup_path="${profile_path}.bak"
    if cp "$profile_path" "$backup_path" 2>/dev/null; then
        echo "$backup_path"
        return 0
    else
        return 1
    fi
}

update_ralph_functions_in_profile() {
    # Updates Ralph functions block in-place in the profile
    # Args: profile_path
    local profile_path="$1"

    # Create backup
    local backup_path
    backup_path="$(backup_profile_file "$profile_path")" || {
        print_colored "$RED" "  Failed to create backup"
        return 1
    }
    if [[ -n "$backup_path" ]]; then
        print_colored "$GRAY" "  Backup created: $backup_path"
    fi

    # Get expected function block
    local expected_block
    expected_block="$(get_expected_ralph_functions)"

    # Parse current profile to get line positions (pipe-delimited)
    local parse_result
    parse_result="$(get_profile_ralph_functions "$profile_path")"
    local start_line end_line
    IFS='|' read -r start_line end_line _ _ <<< "$parse_result"

    if [[ $start_line -lt 0 ]]; then
        # Shouldn't happen, but install fresh if no block found
        echo "$expected_block" >> "$profile_path"
        return 0
    fi

    # Read the profile into an array
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$profile_path"

    # Build new content
    {
        # Lines before Ralph block
        for ((i=0; i<start_line; i++)); do
            printf '%s\n' "${lines[$i]}"
        done

        # New Ralph block (skip leading newline if at start of file)
        if [[ $start_line -eq 0 ]]; then
            echo "$expected_block" | tail -n +2
        else
            echo "$expected_block"
        fi

        # Lines after Ralph block
        for ((i=end_line+1; i<${#lines[@]}; i++)); do
            printf '%s\n' "${lines[$i]}"
        done
    } > "${profile_path}.tmp"

    # Replace original with updated content
    mv "${profile_path}.tmp" "$profile_path"

    print_colored "$GREEN" "  Ralph functions updated in-place"
    return 0
}

reinstall_ralph_functions_in_profile() {
    # Removes old Ralph functions block and appends fresh one
    # Args: profile_path
    local profile_path="$1"

    # Create backup
    local backup_path
    backup_path="$(backup_profile_file "$profile_path")" || {
        print_colored "$RED" "  Failed to create backup"
        return 1
    }
    if [[ -n "$backup_path" ]]; then
        print_colored "$GRAY" "  Backup created: $backup_path"
    fi

    # Get expected function block
    local expected_block
    expected_block="$(get_expected_ralph_functions)"

    # Parse current profile to get line positions (pipe-delimited)
    local parse_result
    parse_result="$(get_profile_ralph_functions "$profile_path")"
    local start_line end_line
    IFS='|' read -r start_line end_line _ _ <<< "$parse_result"

    if [[ $start_line -lt 0 ]]; then
        # No existing block, just append
        echo "$expected_block" >> "$profile_path"
        return 0
    fi

    # Read the profile into an array
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$profile_path"

    # Build new content without old Ralph block, then append fresh
    {
        # Lines before Ralph block
        for ((i=0; i<start_line; i++)); do
            printf '%s\n' "${lines[$i]}"
        done

        # Lines after Ralph block
        for ((i=end_line+1; i<${#lines[@]}; i++)); do
            printf '%s\n' "${lines[$i]}"
        done

        # Append fresh Ralph block
        echo "$expected_block"
    } > "${profile_path}.tmp"

    # Replace original with updated content
    mv "${profile_path}.tmp" "$profile_path"

    print_colored "$GREEN" "  Ralph functions reinstalled (removed old, added fresh)"
    return 0
}

install_shell_functions() {
    # Installs Ralph functions to a profile, handling update/reinstall if needed
    # Args: profile_path [force]
    local profile_path="$1"
    local force="${2:-false}"
    local ralph_dir
    ralph_dir="$(get_ralph_scripts_path)"

    # Create profile file if it doesn't exist
    if [[ ! -f "$profile_path" ]]; then
        touch "$profile_path" 2>/dev/null || {
            print_colored "$RED" "  Failed to create: $profile_path"
            return 1
        }
        print_colored "$GRAY" "  Created: $profile_path"
    fi

    # Compare expected vs installed functions
    compare_ralph_functions "$profile_path"

    # If no Ralph functions exist, install fresh
    if [[ "$COMPARE_STATUS" == "missing" ]]; then
        local expected_block
        expected_block="$(get_expected_ralph_functions)"
        if echo "$expected_block" >> "$profile_path" 2>/dev/null; then
            print_colored "$GREEN" "  Added Ralph functions to $(basename "$profile_path")"
            return 0
        else
            print_colored "$RED" "  Failed to write to: $profile_path"
            return 1
        fi
    fi

    # If up-to-date, report and skip
    if [[ "$COMPARE_STATUS" == "up-to-date" ]]; then
        print_colored "$GRAY" "  Ralph functions are up-to-date in $(basename "$profile_path")"
        return 0
    fi

    # Functions exist but are outdated
    # If force flag is set, automatically update
    if [[ "$force" == true ]]; then
        print_colored "$YELLOW" "  Updating Ralph functions in $(basename "$profile_path") (force mode)..."
        update_ralph_functions_in_profile "$profile_path"
        return $?
    fi

    # Interactive mode - prompt user
    echo ""
    print_colored "$YELLOW" "  Existing Ralph functions detected in $(basename "$profile_path"):"
    print_colored "$CYAN" "    Installed: $COMPARE_INSTALLED_COUNT functions"
    print_colored "$CYAN" "    Expected:  $COMPARE_EXPECTED_COUNT functions"

    if [[ ${#COMPARE_MISSING_FUNCTIONS[@]} -gt 0 ]]; then
        echo ""
        print_colored "$YELLOW" "  Missing functions:"
        for func in "${COMPARE_MISSING_FUNCTIONS[@]}"; do
            print_colored "$RED" "    - $func"
        done
    fi

    if [[ "$COMPARE_PATH_OUTDATED" == true ]]; then
        echo ""
        print_colored "$YELLOW" "  Path is outdated:"
        print_colored "$RED" "    Current:  $COMPARE_INSTALLED_PATH"
        print_colored "$GREEN" "    Expected: $COMPARE_EXPECTED_PATH"
    fi

    echo ""
    print_colored "$YELLOW" "  Options:"
    print_colored "$CYAN" "    (S)kip     - Leave profile unchanged"
    print_colored "$CYAN" "    (U)pdate   - Update Ralph functions block in-place"
    print_colored "$CYAN" "    (R)einstall - Remove old block and append fresh one"
    echo ""

    echo -n "  Choose action for $(basename "$profile_path") [S/U/R]: "
    read -r response

    case "$response" in
        [sS])
            print_colored "$GRAY" "  Skipped - profile unchanged"
            return 0
            ;;
        [uU])
            update_ralph_functions_in_profile "$profile_path"
            return $?
            ;;
        [rR])
            reinstall_ralph_functions_in_profile "$profile_path"
            return $?
            ;;
        *)
            print_colored "$GRAY" "  Invalid choice, skipping."
            return 0
            ;;
    esac
}

install_bash_aliases() {
    # Args: [force]
    local force="${1:-false}"
    local installed=false
    local ralph_dir
    ralph_dir="$(get_ralph_scripts_path)"

    echo ""
    print_colored "$CYAN" "Installing shell functions..."
    echo ""

    # Install to .bashrc if it exists or bash is the shell
    local bashrc="$HOME/.bashrc"
    if [[ -f "$bashrc" ]] || [[ "$SHELL" == *"bash"* ]]; then
        install_shell_functions "$bashrc" "$force" && installed=true
    fi

    # Install to .zshrc if it exists or zsh is the shell
    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        install_shell_functions "$zshrc" "$force" && installed=true
    fi

    # Install to .profile as fallback if neither exists
    if [[ "$installed" == false ]]; then
        local profile="$HOME/.profile"
        install_shell_functions "$profile" "$force"
    fi

    echo ""
    print_colored "$YELLOW" "To activate the functions, run one of:"
    print_colored "$CYAN" "  source ~/.bashrc"
    print_colored "$CYAN" "  source ~/.zshrc"
    print_colored "$GRAY" "  Or restart your terminal"
    echo ""
    print_colored "$YELLOW" "Available commands (work from any directory):"
    print_colored "$CYAN" "  ralph           - Run the ralph loop"
    print_colored "$CYAN" "  ralph-once      - Run a single ralph iteration"
    print_colored "$CYAN" "  ralph-status    - Check ralph progress"
    print_colored "$CYAN" "  ralph-parallel  - Run multiple ralph instances in parallel"
    print_colored "$CYAN" "  ralph-dashboard - Monitor ralph instances in a TUI dashboard"
    echo ""
    print_colored "$GRAY" "Note: Functions use absolute paths and will always run scripts from:"
    print_colored "$GRAY" "  $ralph_dir"
}

show_check_status() {
    # Shows status for --check mode
    local source_path
    local dest_path
    source_path="$(get_source_skills_path)"
    dest_path="$(get_destination_skills_path)"

    print_colored "$YELLOW" "Check mode - no changes will be made"
    echo ""

    # Check skills status
    if [[ -d "$source_path" ]]; then
        local skill_dirs=()
        while IFS= read -r -d '' dir; do
            skill_dirs+=("$dir")
        done < <(find "$source_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

        if [[ ${#skill_dirs[@]} -gt 0 ]]; then
            print_colored "$CYAN" "Skills to install:"
            for skill_dir in "${skill_dirs[@]}"; do
                local skill_name
                skill_name="$(basename "$skill_dir")"
                local skill_dest="$dest_path/$skill_name"
                local status
                if [[ -d "$skill_dest" ]]; then
                    status="(update)"
                else
                    status="(new)"
                fi
                print_colored "$GREEN" "  - $skill_name $status"
            done
        else
            print_colored "$YELLOW" "No skills found in source directory."
        fi
    else
        print_colored "$RED" "Source skills directory not found: $source_path"
    fi

    echo ""

    # Check aliases status for each profile
    print_colored "$CYAN" "Profile aliases status:"

    local profiles=()
    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"

    if [[ -f "$bashrc" ]] || [[ "$SHELL" == *"bash"* ]]; then
        profiles+=("$bashrc")
    fi
    if [[ -f "$zshrc" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        profiles+=("$zshrc")
    fi

    if [[ ${#profiles[@]} -eq 0 ]]; then
        profiles+=("$HOME/.profile")
    fi

    for profile in "${profiles[@]}"; do
        echo ""
        print_colored "$CYAN" "  $(basename "$profile"):"
        compare_ralph_functions "$profile"

        case "$COMPARE_STATUS" in
            "missing")
                print_colored "$YELLOW" "    Status: Not installed"
                print_colored "$GRAY" "    Expected functions: $COMPARE_EXPECTED_COUNT"
                ;;
            "up-to-date")
                print_colored "$GREEN" "    Status: Up-to-date"
                print_colored "$GRAY" "    Installed functions: $COMPARE_INSTALLED_COUNT"
                ;;
            "outdated")
                print_colored "$YELLOW" "    Status: Needs update"
                print_colored "$GRAY" "    Installed: $COMPARE_INSTALLED_COUNT | Expected: $COMPARE_EXPECTED_COUNT"
                if [[ ${#COMPARE_MISSING_FUNCTIONS[@]} -gt 0 ]]; then
                    print_colored "$YELLOW" "    Missing:"
                    for func in "${COMPARE_MISSING_FUNCTIONS[@]}"; do
                        print_colored "$RED" "      - $func"
                    done
                fi
                if [[ "$COMPARE_PATH_OUTDATED" == true ]]; then
                    print_colored "$YELLOW" "    Path outdated: $COMPARE_INSTALLED_PATH -> $COMPARE_EXPECTED_PATH"
                fi
                ;;
        esac
    done
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Parse command-line arguments
    parse_args "$@"

    show_banner
    echo ""

    local source_path
    local dest_path
    source_path="$(get_source_skills_path)"
    dest_path="$(get_destination_skills_path)"

    print_colored "$CYAN" "Source: $source_path"
    print_colored "$CYAN" "Destination: $dest_path"
    echo ""

    # ─────────────────────────────────────────────────────────────────────────
    # Check mode - report status only
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$CHECK" == true ]]; then
        show_check_status
        exit 0
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Install skills
    # ─────────────────────────────────────────────────────────────────────────
    if ! install_skills; then
        exit 1
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Skip aliases if requested
    # ─────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_ALIASES" == true ]]; then
        echo ""
        print_colored "$GRAY" "Skipping alias installation (--skip-aliases specified)."
        echo ""
        exit 0
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Alias installation (force or interactive)
    # ─────────────────────────────────────────────────────────────────────────
    echo ""
    print_colored "$BLUE" "───────────────────────────────────────────────────────"

    if [[ "$FORCE" == true ]]; then
        # Force mode - install/update without prompting
        print_colored "$YELLOW" "Installing shell aliases (force mode)..."
        install_bash_aliases true
    else
        # Interactive mode - prompt user
        echo -n "Would you like to install shell aliases for ralph tools? (y/N) "
        read -r response

        if [[ "$response" =~ ^[yY] ]]; then
            install_bash_aliases false
        else
            print_colored "$GRAY" "Skipping alias installation."
        fi
    fi

    echo ""
    exit 0
}

# Run main
main "$@"
