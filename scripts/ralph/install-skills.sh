#!/usr/bin/env bash
#
# install-skills.sh - Installs ralph skills globally to ~/.claude/skills/
#
# SYNOPSIS
#   ./install-skills.sh
#
# DESCRIPTION
#   Copies all skills from the ralph skills directory to the global Claude Code
#   skills directory (~/.claude/skills/). This makes the skills available for
#   interactive Claude Code sessions in any project.
#
#   Existing skills are updated (overwritten) when this script runs.
#
#   Optionally installs shell functions for ralph, ralph-once, and ralph-status
#   to your shell profile (.bashrc and/or .zshrc).
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared utilities
if [[ -f "$SCRIPT_DIR/ralph-utils.sh" ]]; then
    source "$SCRIPT_DIR/ralph-utils.sh"
fi

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
# Shell Alias Installation
# ─────────────────────────────────────────────────────────────────────────────

check_functions_exist() {
    local profile_path="$1"
    if [[ -f "$profile_path" ]] && grep -q "# Ralph functions" "$profile_path" 2>/dev/null; then
        return 0
    fi
    return 1
}

install_shell_functions() {
    local profile_path="$1"
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

    # Check if Ralph functions already exist
    if check_functions_exist "$profile_path"; then
        print_colored "$GRAY" "  Ralph functions already exist in $(basename "$profile_path"), skipping"
        return 0
    fi

    # Build the function block
    local function_block
    function_block=$(cat <<EOF

# Ralph functions
ralph() { "$ralph_dir/ralph.sh" "\$@"; }
ralph-once() { "$ralph_dir/ralph-once.sh" "\$@"; }
ralph-status() { "$ralph_dir/ralph-status.sh" "\$@"; }
EOF
)

    # Append to profile
    if echo "$function_block" >> "$profile_path" 2>/dev/null; then
        print_colored "$GREEN" "  Added Ralph functions to $(basename "$profile_path")"
        return 0
    else
        print_colored "$RED" "  Failed to write to: $profile_path"
        return 1
    fi
}

install_bash_aliases() {
    local installed=false
    local ralph_dir
    ralph_dir="$(get_ralph_scripts_path)"

    echo ""
    print_colored "$CYAN" "Installing shell functions..."
    echo ""

    # Install to .bashrc if it exists or bash is the shell
    local bashrc="$HOME/.bashrc"
    if [[ -f "$bashrc" ]] || [[ "$SHELL" == *"bash"* ]]; then
        install_shell_functions "$bashrc" && installed=true
    fi

    # Install to .zshrc if it exists or zsh is the shell
    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        install_shell_functions "$zshrc" && installed=true
    fi

    # Install to .profile as fallback if neither exists
    if [[ "$installed" == false ]]; then
        local profile="$HOME/.profile"
        install_shell_functions "$profile"
    fi

    echo ""
    print_colored "$YELLOW" "To activate the functions, run one of:"
    print_colored "$CYAN" "  source ~/.bashrc"
    print_colored "$CYAN" "  source ~/.zshrc"
    print_colored "$GRAY" "  Or restart your terminal"
    echo ""
    print_colored "$YELLOW" "Available commands (work from any directory):"
    print_colored "$CYAN" "  ralph        - Run the ralph loop"
    print_colored "$CYAN" "  ralph-once   - Run a single ralph iteration"
    print_colored "$CYAN" "  ralph-status - Check ralph progress"
    echo ""
    print_colored "$GRAY" "Note: Functions use absolute paths and will always run scripts from:"
    print_colored "$GRAY" "  $ralph_dir"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    show_banner
    echo ""

    local source_path
    local dest_path
    source_path="$(get_source_skills_path)"
    dest_path="$(get_destination_skills_path)"

    print_colored "$CYAN" "Source: $source_path"
    print_colored "$CYAN" "Destination: $dest_path"
    echo ""

    # Install skills
    if ! install_skills; then
        exit 1
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Optional alias installation
    # ─────────────────────────────────────────────────────────────────────────
    echo ""
    print_colored "$BLUE" "───────────────────────────────────────────────────────"
    echo -n "Would you like to install shell aliases for ralph tools? (y/N) "
    read -r response

    if [[ "$response" =~ ^[yY] ]]; then
        install_bash_aliases
    else
        print_colored "$GRAY" "Skipping alias installation."
    fi

    echo ""
    exit 0
}

# Run main
main "$@"
