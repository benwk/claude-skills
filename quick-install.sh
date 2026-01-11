#!/bin/bash
# Claude Skills - Quick Install Script
# Usage: curl -fsSL https://raw.githubusercontent.com/benwk/claude-skills/main/quick-install.sh | bash

set -e

SKILLS_DIR="$HOME/.claude/skills"
REPO_URL="https://github.com/benwk/claude-skills.git"
TEMP_DIR="/tmp/claude-skills-install-$$"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Claude Code Skills - Quick Installer${NC}"
echo ""

# Clean up function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Clone repository to temp directory
echo -e "${BLUE}Downloading skills...${NC}"
git clone --depth 1 "$REPO_URL" "$TEMP_DIR" 2>/dev/null || {
    echo -e "${YELLOW}Error: Failed to clone repository${NC}"
    exit 1
}

# Create skills directory
mkdir -p "$SKILLS_DIR"

# Install each skill
echo ""
skill_count=0
for skill_dir in "$TEMP_DIR"/*; do
    if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
        skill_name=$(basename "$skill_dir")
        skill_dest="$SKILLS_DIR/$skill_name"

        echo -e "${BLUE}Installing skill: $skill_name${NC}"

        # Remove existing installation
        if [ -d "$skill_dest" ]; then
            rm -rf "$skill_dest"
        fi

        # Copy skill
        cp -r "$skill_dir" "$skill_dest"

        # Make scripts executable
        find "$skill_dest" -name "*.sh" -type f -exec chmod +x {} \;

        echo -e "${GREEN}✓ Installed: $skill_name${NC}"
        ((skill_count++))
    fi
done

echo ""
if [ $skill_count -eq 0 ]; then
    echo -e "${YELLOW}No skills found to install${NC}"
else
    echo -e "${GREEN}✓ Successfully installed $skill_count skill(s)${NC}"
fi

echo ""
echo -e "${BLUE}Installation complete!${NC}"
echo ""
echo "Skills are installed in: $SKILLS_DIR"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart Claude Code to load the skills"
echo "2. Use natural language to invoke skills"
echo ""
echo "Examples:"
echo "  - 'migrate production database to staging'"
echo "  - 'verify storage account migration'"
echo ""
echo "For more info: https://github.com/benwk/claude-skills"
echo ""
