# Claude Code Skills

Personal collection of Claude Code skills for development and operations tasks.

## Available Skills

### azure-migrate

Azure resource migration tool for PostgreSQL databases and Storage Accounts.

**Features:**
- Migrate PostgreSQL databases between Azure subscriptions/regions
- Migrate Storage Account blob containers
- Automatic password retrieval from Key Vault
- Built-in data verification
- Support for multiple databases/containers in one run

**Installation:**
```bash
./install.sh azure-migrate
```

## Quick Start

### Install all skills
```bash
git clone <your-repo-url> ~/claude-skills
cd ~/claude-skills
./install.sh
```

### Install specific skill
```bash
./install.sh azure-migrate
```

### Update skills
```bash
cd ~/claude-skills
git pull
./install.sh
```

## Repository Structure

```
claude-skills/
├── README.md           # This file
├── install.sh          # Installation script
├── azure-migrate/      # Azure migration skill
│   ├── SKILL.md
│   ├── README.md
│   ├── migrate_postgresql.sh
│   ├── migrate_storage.sh
│   └── examples/
└── (future skills...)
```

## Requirements

Skills are installed to `~/.claude/skills/` and will be available globally across all Claude Code projects.

**Prerequisites:**
- Claude Code installed
- Git (for cloning and updating)
- Skill-specific dependencies (see individual skill READMEs)

## Usage

After installation, restart Claude Code to load the skills. You can then use them with natural language:

```
# Azure migration examples
migrate staging database to preview
verify storage account migration
```

## Adding New Skills

To add a new skill to this repository:

1. Create a new directory with your skill name
2. Add `SKILL.md` (required) and any supporting files
3. Update this README with the skill description
4. Commit and push
5. Run `./install.sh` on your devices to update

## License

Private repository for personal use.
