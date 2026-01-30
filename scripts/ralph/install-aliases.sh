#!/bin/bash

# Ralph Loop Alias Installation Script
# Installs shell aliases for convenient access to Ralph commands
# Supports bash and zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================================================
# Configuration
# ============================================================================
ALIASES_MARKER="# Ralph Loop Aliases - BEGIN"
ALIASES_END_MARKER="# Ralph Loop Aliases - END"

# ============================================================================
# Usage
# ============================================================================
usage() {
    cat <<EOF
Ralph Loop Alias Installation

USAGE:
    install-aliases.sh [COMMAND] [OPTIONS]

COMMANDS:
    install     Install aliases to shell rc file (default)
    uninstall   Remove aliases from shell rc file
    show        Show aliases that would be installed
    check       Check if aliases are already installed

OPTIONS:
    --shell <bash|zsh>  Specify shell (auto-detected by default)
    --dry-run           Show what would be done without making changes
    --help, -h          Show this help

EXAMPLES:
    install-aliases.sh                    # Install to detected shell
    install-aliases.sh install --shell zsh
    install-aliases.sh uninstall
    install-aliases.sh show
    install-aliases.sh check

ALIASES INSTALLED:
    ralph-supervisor    Start supervised Ralph loop
    ralph-status        Show Ralph supervisor status
    ralph-stop          Stop Ralph supervisor
    ralph-cleanup       Clean stale state files (alias for ralph-status --clean)
    ralph-dashboard     Show all Ralph supervisors (alias for ralph-status --all)

EOF
    exit 0
}

# ============================================================================
# Shell Detection
# ============================================================================
detect_shell() {
    local shell_name
    shell_name=$(basename "$SHELL")

    case "$shell_name" in
        bash) echo "bash" ;;
        zsh)  echo "zsh" ;;
        *)
            # Fallback: check if rc files exist
            if [[ -f "$HOME/.zshrc" ]]; then
                echo "zsh"
            elif [[ -f "$HOME/.bashrc" ]]; then
                echo "bash"
            else
                echo "unknown"
            fi
            ;;
    esac
}

get_rc_file() {
    local shell="$1"
    case "$shell" in
        bash)
            if [[ -f "$HOME/.bash_profile" ]] && [[ "$(uname)" == "Darwin" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        zsh)  echo "$HOME/.zshrc" ;;
        *)    echo "" ;;
    esac
}

# ============================================================================
# Alias Generation
# ============================================================================
generate_aliases() {
    cat <<EOF
$ALIASES_MARKER
# Installed by: $SCRIPT_DIR/install-aliases.sh
# Date: $(date -Iseconds)

# Ralph Loop Process Supervisor aliases
alias ralph-supervisor='$SCRIPT_DIR/ralph-supervisor.sh'
alias ralph-status='$SCRIPT_DIR/ralph-status.sh'
alias ralph-stop='$SCRIPT_DIR/ralph-stop.sh'

# Convenience aliases
alias ralph-cleanup='$SCRIPT_DIR/ralph-status.sh --clean'
alias ralph-dashboard='$SCRIPT_DIR/ralph-status.sh --all'
alias ralph-setup='$SCRIPT_DIR/setup-ralph-loop.sh'

# PowerShell variants (for Git Bash on Windows)
alias ralph-supervisor-ps='powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_DIR/ralph-supervisor.ps1"'
alias ralph-status-ps='powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_DIR/ralph-status.ps1"'
alias ralph-stop-ps='powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_DIR/ralph-stop.ps1"'

$ALIASES_END_MARKER
EOF
}

# ============================================================================
# Commands
# ============================================================================
show_aliases() {
    echo -e "${BOLD}${CYAN}Ralph Loop Aliases:${NC}"
    echo ""
    generate_aliases | grep -E "^alias " | while read -r line; do
        local name value
        name=$(echo "$line" | sed "s/alias \([^=]*\)=.*/\1/")
        value=$(echo "$line" | sed "s/alias [^=]*='\(.*\)'/\1/")
        printf "  ${GREEN}%-20s${NC} → %s\n" "$name" "$value"
    done
    echo ""
}

check_installed() {
    local shell="${1:-$(detect_shell)}"
    local rc_file
    rc_file=$(get_rc_file "$shell")

    if [[ -z "$rc_file" ]]; then
        echo -e "${RED}Cannot determine rc file for shell: $shell${NC}"
        return 1
    fi

    if [[ ! -f "$rc_file" ]]; then
        echo -e "${YELLOW}RC file does not exist: $rc_file${NC}"
        return 1
    fi

    if grep -q "$ALIASES_MARKER" "$rc_file" 2>/dev/null; then
        echo -e "${GREEN}Ralph aliases are installed in: $rc_file${NC}"
        return 0
    else
        echo -e "${YELLOW}Ralph aliases are NOT installed in: $rc_file${NC}"
        return 1
    fi
}

install_aliases() {
    local shell="${1:-$(detect_shell)}"
    local dry_run="${2:-false}"

    local rc_file
    rc_file=$(get_rc_file "$shell")

    if [[ -z "$rc_file" ]]; then
        echo -e "${RED}Error: Cannot determine rc file for shell: $shell${NC}"
        echo "Supported shells: bash, zsh"
        exit 1
    fi

    echo -e "${BOLD}Installing Ralph aliases...${NC}"
    echo "  Shell: $shell"
    echo "  RC file: $rc_file"
    echo ""

    # Check if already installed
    if [[ -f "$rc_file" ]] && grep -q "$ALIASES_MARKER" "$rc_file" 2>/dev/null; then
        echo -e "${YELLOW}Aliases already installed. Updating...${NC}"
        # Remove old aliases first
        uninstall_aliases "$shell" "$dry_run" true
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}[DRY RUN] Would append to $rc_file:${NC}"
        echo ""
        generate_aliases
        echo ""
        return 0
    fi

    # Create rc file if it doesn't exist
    if [[ ! -f "$rc_file" ]]; then
        echo -e "${YELLOW}Creating $rc_file${NC}"
        touch "$rc_file"
    fi

    # Append aliases
    echo "" >> "$rc_file"
    generate_aliases >> "$rc_file"

    echo -e "${GREEN}Aliases installed successfully!${NC}"
    echo ""
    echo "To use immediately, run:"
    echo -e "  ${CYAN}source $rc_file${NC}"
    echo ""
    echo "Or restart your terminal."
    echo ""
    show_aliases
}

uninstall_aliases() {
    local shell="${1:-$(detect_shell)}"
    local dry_run="${2:-false}"
    local quiet="${3:-false}"

    local rc_file
    rc_file=$(get_rc_file "$shell")

    if [[ -z "$rc_file" ]] || [[ ! -f "$rc_file" ]]; then
        if [[ "$quiet" != "true" ]]; then
            echo -e "${YELLOW}RC file not found: $rc_file${NC}"
        fi
        return 0
    fi

    if ! grep -q "$ALIASES_MARKER" "$rc_file" 2>/dev/null; then
        if [[ "$quiet" != "true" ]]; then
            echo -e "${YELLOW}No Ralph aliases found in: $rc_file${NC}"
        fi
        return 0
    fi

    if [[ "$quiet" != "true" ]]; then
        echo -e "${BOLD}Removing Ralph aliases from $rc_file...${NC}"
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo -e "${CYAN}[DRY RUN] Would remove aliases block from $rc_file${NC}"
        return 0
    fi

    # Create temp file and remove alias block
    local temp_file
    temp_file=$(mktemp)

    # Use sed to remove the block between markers (including markers)
    sed "/$ALIASES_MARKER/,/$ALIASES_END_MARKER/d" "$rc_file" > "$temp_file"

    # Also remove any trailing empty lines that might be left
    # Keep file but remove consecutive blank lines at end
    cat "$temp_file" > "$rc_file"
    rm "$temp_file"

    if [[ "$quiet" != "true" ]]; then
        echo -e "${GREEN}Aliases removed successfully!${NC}"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    local command="install"
    local shell=""
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            install|uninstall|show|check)
                command="$1"
                shift
                ;;
            --shell)
                shell="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                ;;
        esac
    done

    # Auto-detect shell if not specified
    if [[ -z "$shell" ]]; then
        shell=$(detect_shell)
    fi

    # Execute command
    case "$command" in
        install)
            install_aliases "$shell" "$dry_run"
            ;;
        uninstall)
            uninstall_aliases "$shell" "$dry_run"
            ;;
        show)
            show_aliases
            ;;
        check)
            check_installed "$shell"
            ;;
    esac
}

main "$@"
