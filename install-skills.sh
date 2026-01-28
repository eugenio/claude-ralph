#!/bin/bash
# Install ralph skills globally for Claude Code
# Usage: ./install-skills.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
RALPH_DIR="$SCRIPT_DIR/scripts/ralph"

# If SCRIPT_DIR is the repo root, ralph scripts are in scripts/ralph
# If SCRIPT_DIR is scripts/ralph itself, use that directly
if [ -f "$SCRIPT_DIR/ralph.sh" ]; then
    RALPH_DIR="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/scripts/ralph/ralph.sh" ]; then
    RALPH_DIR="$SCRIPT_DIR/scripts/ralph"
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}     Installing Ralph Skills for Claude Code${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Create skills directory
echo -e "Creating skills directory: ${SKILLS_DIR}"
mkdir -p "$SKILLS_DIR"

# Copy skills
echo -e "Copying skills..."
cp -r "$SCRIPT_DIR/skills/prd" "$SKILLS_DIR/"
echo -e "  ${GREEN}✓${NC} prd skill installed"

cp -r "$SCRIPT_DIR/skills/ralph" "$SKILLS_DIR/"
echo -e "  ${GREEN}✓${NC} ralph skill installed"

cp -r "$SCRIPT_DIR/skills/dev-browser" "$SKILLS_DIR/"
echo -e "  ${GREEN}✓${NC} dev-browser skill installed"

echo ""
echo -e "${GREEN}Success!${NC} Skills installed to: $SKILLS_DIR"
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo -e "  Start Claude Code: ${BLUE}claude${NC}"
echo -e "  Then in conversation:"
echo -e "    - Load the prd skill and create a PRD for [feature]"
echo -e "    - Load the ralph skill and convert tasks/prd-[name].md to prd.json"
echo -e "    - Load the dev-browser skill and verify [page]"
echo ""
echo -e "${YELLOW}Verify installation:${NC}"
echo -e "  ${BLUE}ls -la $SKILLS_DIR${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Optional alias installation
# ─────────────────────────────────────────────────────────────────────────────

install_aliases() {
    local config_files=()
    local modified_files=()

    # Detect which shell config files exist
    [ -f "$HOME/.bashrc" ] && config_files+=("$HOME/.bashrc")
    [ -f "$HOME/.zshrc" ] && config_files+=("$HOME/.zshrc")
    [ -f "$HOME/.profile" ] && config_files+=("$HOME/.profile")

    if [ ${#config_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No shell config files found (.bashrc, .zshrc, .profile)${NC}"
        echo -e "${GRAY}Creating ~/.bashrc...${NC}"
        touch "$HOME/.bashrc"
        config_files+=("$HOME/.bashrc")
    fi

    echo -e "${GRAY}Installing aliases to shell config files...${NC}"

    for config_file in "${config_files[@]}"; do
        # Check if Ralph aliases already exist
        if grep -q "# Ralph aliases" "$config_file" 2>/dev/null; then
            echo -e "  ${YELLOW}⊘${NC} $(basename "$config_file") - aliases already exist, skipping"
            continue
        fi

        # Append aliases to config file
        {
            echo ""
            echo "# Ralph aliases"
            echo "alias ralph='$RALPH_DIR/ralph.sh'"
            echo "alias ralph-once='$RALPH_DIR/ralph-once.sh'"
            echo "alias ralph-status='$RALPH_DIR/ralph-status.sh'"
        } >> "$config_file"

        modified_files+=("$config_file")
        echo -e "  ${GREEN}✓${NC} $(basename "$config_file") - aliases added"
    done

    # Show post-installation instructions
    if [ ${#modified_files[@]} -gt 0 ]; then
        echo ""
        echo -e "${GREEN}Aliases installed successfully!${NC}"
        echo ""
        echo -e "${YELLOW}To activate the aliases, run one of:${NC}"
        for file in "${modified_files[@]}"; do
            echo -e "  ${BLUE}source $file${NC}"
        done
        echo -e "  ${GRAY}Or restart your terminal${NC}"
        echo ""
        echo -e "${YELLOW}Available commands (work from any directory):${NC}"
        echo -e "  ${BLUE}ralph${NC}        - Run the ralph loop"
        echo -e "  ${BLUE}ralph-once${NC}   - Run a single ralph iteration"
        echo -e "  ${BLUE}ralph-status${NC} - Check ralph progress"
        echo ""
        echo -e "${GRAY}Note: Aliases use absolute paths and will always run the scripts from:${NC}"
        echo -e "${GRAY}  $RALPH_DIR${NC}"
    else
        echo ""
        echo -e "${GRAY}No files were modified (aliases already installed).${NC}"
    fi
}

# Prompt for alias installation
echo -e "${BLUE}─────────────────────────────────────────────────────────${NC}"
read -r -p "Would you like to install shell aliases for ralph tools? (y/N) " response
case "$response" in
    [yY]|[yY][eE][sS])
        install_aliases
        ;;
    *)
        echo -e "${GRAY}Skipping alias installation.${NC}"
        ;;
esac
echo ""
