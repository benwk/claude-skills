#!/bin/bash
# Claude Skills Installer
# Install skills to ~/.claude/skills/

set -e

SKILLS_DIR="$HOME/.claude/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Claude Code Skills Installer${NC}"
echo ""

# Create skills directory if it doesn't exist
mkdir -p "$SKILLS_DIR"

# Function to install a single skill
install_skill() {
    local skill_name="$1"
    local skill_src="$SCRIPT_DIR/$skill_name"
    local skill_dest="$SKILLS_DIR/$skill_name"

    if [ ! -d "$skill_src" ]; then
        echo -e "${YELLOW}Warning: Skill '$skill_name' not found in repository${NC}"
        return 1
    fi

    echo -e "${BLUE}Installing skill: $skill_name${NC}"

    # Remove existing installation
    if [ -d "$skill_dest" ]; then
        rm -rf "$skill_dest"
    fi

    # Copy skill directory
    cp -r "$skill_src" "$skill_dest"

    # Make shell scripts executable
    find "$skill_dest" -name "*.sh" -type f -exec chmod +x {} \;

    echo -e "${GREEN}✓ Installed: $skill_name${NC}"
}

# If specific skill provided, install only that
if [ $# -eq 1 ]; then
    install_skill "$1"
else
    # Install all skills (directories with SKILL.md)
    echo "Installing all skills..."
    echo ""

    skill_count=0
    for skill_dir in "$SCRIPT_DIR"/*; do
        if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            skill_name=$(basename "$skill_dir")
            install_skill "$skill_name"
            ((skill_count++))
        fi
    done

    echo ""
    if [ $skill_count -eq 0 ]; then
        echo -e "${YELLOW}No skills found to install${NC}"
    else
        echo -e "${GREEN}✓ Installed $skill_count skill(s)${NC}"
    fi
fi

echo ""
echo -e "${BLUE}Installation complete!${NC}"
echo ""
echo "Skills are installed in: $SKILLS_DIR"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart Claude Code to load the skills"
echo "2. Use natural language to invoke skills (e.g., 'migrate staging database')"
echo ""
echo "To update skills later:"
echo "  cd ~/claude-skills"
echo "  git pull"
echo "  ./install.sh"
echo ""
