#!/bin/bash
# Azure Migrate Skill Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/azure-migrate-skill/main/install.sh | bash

set -e

SKILL_NAME="azure-migrate"
INSTALL_DIR="$HOME/.claude/skills/$SKILL_NAME"
REPO_URL="https://github.com/YOUR_USERNAME/azure-migrate-skill"

echo "Installing $SKILL_NAME skill..."

# Create skills directory if it doesn't exist
mkdir -p "$HOME/.claude/skills"

# Clone or update the skill
if [ -d "$INSTALL_DIR" ]; then
  echo "Skill already installed. Updating..."
  cd "$INSTALL_DIR"
  git pull
else
  echo "Cloning skill repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Make scripts executable
chmod +x "$INSTALL_DIR"/*.sh

echo "✓ $SKILL_NAME skill installed successfully to $INSTALL_DIR"
echo ""
echo "The skill is now available globally across all your Claude Code projects."
echo "Restart Claude Code to load the skill."
echo ""
echo "Usage examples:"
echo "  - 'migrate staging database to preview'"
echo "  - 'verify database migration'"
echo ""
