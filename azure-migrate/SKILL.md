---
name: azure-migrate
description: Migrate Azure PostgreSQL databases, Storage Accounts, and Container Registry (ACR) images between subscriptions/regions. Use when user asks to migrate databases, storage, container images, or Azure resources between environments.
user-invocable: true
---

# Azure Resource Migration Skill

You are helping with Azure resource migration using the migration tools bundled with this skill.

**IMPORTANT**: The migration scripts are located in the skill directory at `.claude/skills/azure-migrate/`. When executing the scripts, use the full path from the project root or navigate to the skill directory first.

## Available Tools

### 1. PostgreSQL Migration (`migrate_postgresql.sh`)

**Purpose**: Migrate PostgreSQL databases between Azure subscriptions/regions

**Usage**:
```bash
.claude/skills/azure-migrate/migrate_postgresql.sh <source_config.json> <target_config.json> [options]
```

**Options**:
- `--verify-only` - Only verify data, don't migrate
- `--skip-backup` - Skip backup step (use existing backup)
- `--backup-dir DIR` - Use specific backup directory

**Configuration Format** (JSON):
```json
{
  "subscription": "subscription-id",
  "host": "psql-server-name.postgres.database.azure.com",
  "username": "psqladmin",
  "keyvault": "kv-name",
  "databases": ["db1", "db2", "db3"]
}
```

**Features**:
- Auto-retrieves passwords from Azure Key Vault
- Uses pg_dump/pg_restore for complete backup/restore
- Accurate verification using COUNT(*) on all tables
- Supports multiple databases in one run

### 2. Storage Account Migration (`migrate_storage.sh`)

**Purpose**: Migrate Azure Storage Account blob containers between subscriptions/regions

**Usage**:
```bash
.claude/skills/azure-migrate/migrate_storage.sh <source_config.json> <target_config.json> [options]
```

**Options**:
- `--verify-only` - Only verify file counts, don't migrate
- `--skip-download` - Skip download step (use existing local files)
- `--temp-dir DIR` - Use specific temporary directory

**Configuration Format** (JSON):
```json
{
  "subscription": "subscription-id",
  "account_name": "storageaccountname",
  "resource_group": "rg-name",
  "containers": ["container1", "container2"]
}
```

**Features**:
- Uses SAS tokens for secure transfer
- Three-step migration: source → local → destination
- Automatically creates target containers if missing
- File count verification

### 3. Container Registry Migration (`migrate_acr.sh`)

**Purpose**: Migrate Azure Container Registry (ACR) images between subscriptions/regions with time-based filtering

**Usage**:
```bash
.claude/skills/azure-migrate/migrate_acr.sh <source_config.json> <target_config.json> [options]
```

**Options**:
- `--days N` - Only sync images updated in last N days (default: 7)
- `--all-images` - Sync all images regardless of age
- `--diff-only` - Only show differences, don't sync
- `--verify-only` - Only verify sync status, don't sync

**Configuration Format** (JSON):
```json
{
  "subscription": "subscription-id",
  "registry_name": "myacrname",
  "repositories": ["repo1", "repo2"]  // optional, if omitted will sync all
}
```

**Features**:
- Time-based filtering for incremental syncing (last N days)
- Diff mode to preview changes before syncing
- Smart deduplication - skips images already in target ACR
- Repository filtering - sync specific repos or all
- Detailed statistics (synced, skipped, failed counts)
- Uses ACR Import API for secure cross-subscription migration

**Common Use Cases**:
- Incremental sync: `--days 3` for recent images only
- Initial migration: `--all-images` for full sync
- Preview changes: `--diff-only` before actual sync
- Scheduled sync: Run daily with `--days 1` for continuous sync

## Example Configurations

See `.claude/skills/azure-migrate/examples/` for sample configuration files:
- `source_db.json.example` / `target_db.json.example` - Database examples
- `source_storage.json.example` / `target_storage.json.example` - Storage examples
- `source_acr.json.example` / `target_acr.json.example` - Container Registry examples

Users should copy these `.example` files, remove the `.example` extension, and fill in their actual Azure resource details.

## When User Requests Migration

1. **Ask for source and target details**:
   - Subscription ID
   - Resource names (PostgreSQL server or Storage Account)
   - Resource group (for Storage Account)
   - Key Vault name (for PostgreSQL)
   - Database/container names

2. **Create configuration files**:
   - Save as JSON in a temporary location or project directory
   - Use descriptive names like `source_db.json` and `target_db.json`

3. **Execute migration**:
   - Run the appropriate script with configuration files
   - Monitor output for errors
   - Report progress to user

4. **Verify results**:
   - Run with `--verify-only` flag to confirm data integrity
   - Report verification results to user

## Best Practices

- **Always verify first**: Run `--verify-only` on existing data to check if migration is needed
- **Test with small datasets**: If migrating large databases, suggest testing with one small database first
- **Check prerequisites**: Ensure Azure CLI is authenticated, azcopy is installed, PostgreSQL tools available
- **Network access**: Verify firewall rules allow access from current machine
- **Backup awareness**: Let users know where backups are stored (`/tmp` by default)
- **Cleanup**: Remind users to clean up temporary backup files after successful migration

## Error Handling

Common issues and solutions:
- **Key Vault access denied**: User needs proper RBAC permissions on Key Vault
- **PostgreSQL connection failed**: Check firewall rules and network access
- **Container not found**: Script auto-creates containers, but verify storage account exists
- **SAS token expired**: Tokens have 4-hour expiry, re-run if needed
- **Disk space**: Large migrations need significant temporary disk space

## Workflow Example

When user says "Migrate production database to staging" (or similar):

1. Check if user has existing config files or ask them to provide environment details
2. Create JSON config files based on user's Azure resource information
3. Save configs with descriptive names (e.g., `source_prod.json`, `target_staging.json`)
4. Run migration with full script path: `.claude/skills/azure-migrate/migrate_postgresql.sh`
5. Run verification with `--verify-only` flag
6. Report results including any mismatches or errors

Example `.example` files are available in `.claude/skills/azure-migrate/examples/` for reference.
