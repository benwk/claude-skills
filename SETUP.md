# Quick Setup Guide

Follow these steps to publish your Claude skills repository and use it across devices.

## Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Create a **private** repository named `claude-skills`
3. **Do NOT** initialize with README (we already have one)
4. Copy the repository URL

## Step 2: Push to GitHub

```bash
cd /tmp/claude-skills

# Rename branch to main (if needed)
git branch -M main

# Add your GitHub repository as remote
git remote add origin https://github.com/YOUR_USERNAME/claude-skills.git

# Push to GitHub
git push -u origin main
```

## Step 3: Install on Current Device

```bash
# Clone to home directory
git clone https://github.com/YOUR_USERNAME/claude-skills.git ~/claude-skills

# Run installer
cd ~/claude-skills
./install.sh

# Restart Claude Code
```

## Step 4: Install on Other Devices

On any other device:

```bash
# One-time setup
git clone https://github.com/YOUR_USERNAME/claude-skills.git ~/claude-skills
cd ~/claude-skills
./install.sh
```

Restart Claude Code and you're done!

## Updating Skills

When you add or update skills:

```bash
# On the device where you made changes
cd ~/claude-skills
git add .
git commit -m "Update skills"
git push

# On other devices
cd ~/claude-skills
git pull
./install.sh
```

## Alternative: Using SSH

If you prefer SSH authentication:

```bash
# Create repository with SSH URL
git clone git@github.com:YOUR_USERNAME/claude-skills.git ~/claude-skills
```

## Verify Installation

After installation, check installed skills:

```bash
ls -la ~/.claude/skills/
```

You should see:
```
azure-migrate/
```

Restart Claude Code and test:
```
Ask Claude: "migrate staging database to preview"
```

## Adding More Skills Later

1. Create a new directory in `~/claude-skills/YOUR_SKILL_NAME/`
2. Add `SKILL.md` and other files
3. Commit and push:
   ```bash
   cd ~/claude-skills
   git add .
   git commit -m "Add new skill: YOUR_SKILL_NAME"
   git push
   ```
4. On other devices: `git pull && ./install.sh`

## Troubleshooting

**Skills not showing up?**
- Make sure you restarted Claude Code
- Check `~/.claude/skills/` for installed skills
- Verify `SKILL.md` exists in each skill directory

**Permission denied?**
- Make sure install.sh is executable: `chmod +x install.sh`
- Check that you have write access to `~/.claude/skills/`

**Git authentication issues?**
- Use GitHub CLI: `gh auth login`
- Or set up SSH keys: https://docs.github.com/en/authentication
