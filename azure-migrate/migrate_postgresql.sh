#!/bin/bash
# PostgreSQL Database Migration Script
# Usage: migrate_postgresql.sh <source_config> <target_config> [--verify-only]
#
# Config format (JSON):
# {
#   "subscription": "subscription-id",
#   "host": "psql-server.postgres.database.azure.com",
#   "username": "psqladmin",
#   "keyvault": "kv-name",
#   "databases": ["db1", "db2", "db3"]
# }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/tmp/pg_migration_$(date +%Y%m%d_%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
  cat << EOF
PostgreSQL Migration Tool

USAGE:
  $0 <source_config.json> <target_config.json> [options]

OPTIONS:
  --verify-only     Only verify data, don't migrate
  --skip-backup     Skip backup step (use existing backup)
  --backup-dir DIR  Use specific backup directory
  --help            Show this help message

EXAMPLE:
  $0 staging.json preview.json
  $0 staging.json preview.json --verify-only

CONFIG FILE FORMAT (JSON):
  {
    "subscription": "subscription-id",
    "host": "server.postgres.database.azure.com",
    "username": "psqladmin",
    "keyvault": "kv-name",
    "databases": ["app_production", "analytics", "users"]
  }
EOF
  exit 1
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

get_password() {
  local subscription=$1
  local keyvault=$2

  az account set --subscription "$subscription" > /dev/null 2>&1
  az keyvault secret show \
    --vault-name "$keyvault" \
    --name postgresql-admin-password \
    --query value -o tsv
}

backup_database() {
  local config_file=$1
  local subscription=$(jq -r '.subscription' "$config_file")
  local host=$(jq -r '.host' "$config_file")
  local username=$(jq -r '.username' "$config_file")
  local keyvault=$(jq -r '.keyvault' "$config_file")
  local databases=($(jq -r '.databases[]' "$config_file"))

  log_info "Backing up databases from $host"

  mkdir -p "$BACKUP_DIR"

  local password=$(get_password "$subscription" "$keyvault")

  for db in "${databases[@]}"; do
    log_info "Backing up database: $db"

    PGPASSWORD="$password" pg_dump \
      -h "$host" \
      -U "$username" \
      -d "$db" \
      -F c \
      -b \
      -v \
      -f "$BACKUP_DIR/${db}.dump" 2>&1 | grep -E "dumping contents" | tail -5

    local size=$(du -h "$BACKUP_DIR/${db}.dump" | cut -f1)
    log_info "✓ $db backed up (Size: $size)"
  done

  log_info "Backup location: $BACKUP_DIR"
}

restore_database() {
  local config_file=$1
  local subscription=$(jq -r '.subscription' "$config_file")
  local host=$(jq -r '.host' "$config_file")
  local username=$(jq -r '.username' "$config_file")
  local keyvault=$(jq -r '.keyvault' "$config_file")
  local databases=($(jq -r '.databases[]' "$config_file"))

  log_info "Restoring databases to $host"

  local password=$(get_password "$subscription" "$keyvault")

  for db in "${databases[@]}"; do
    local dump_file="$BACKUP_DIR/${db}.dump"

    if [ ! -f "$dump_file" ]; then
      log_warn "Skipping $db (dump file not found)"
      continue
    fi

    log_info "Restoring database: $db"

    # Drop and recreate database
    PGPASSWORD="$password" psql \
      -h "$host" \
      -U "$username" \
      -d postgres \
      -c "DROP DATABASE IF EXISTS $db;" 2>/dev/null || true

    PGPASSWORD="$password" psql \
      -h "$host" \
      -U "$username" \
      -d postgres \
      -c "CREATE DATABASE $db;"

    # Restore from dump
    PGPASSWORD="$password" pg_restore \
      -h "$host" \
      -U "$username" \
      -d "$db" \
      -v \
      "$dump_file" 2>&1 | grep -E "restoring|processing" | tail -5

    log_info "✓ $db restored"
  done
}

verify_migration() {
  local source_config=$1
  local target_config=$2

  local src_sub=$(jq -r '.subscription' "$source_config")
  local src_host=$(jq -r '.host' "$source_config")
  local src_user=$(jq -r '.username' "$source_config")
  local src_kv=$(jq -r '.keyvault' "$source_config")

  local tgt_sub=$(jq -r '.subscription' "$target_config")
  local tgt_host=$(jq -r '.host' "$target_config")
  local tgt_user=$(jq -r '.username' "$target_config")
  local tgt_kv=$(jq -r '.keyvault' "$target_config")

  local databases=($(jq -r '.databases[]' "$source_config"))

  log_info "Verifying migration..."

  local src_pass=$(get_password "$src_sub" "$src_kv")
  local tgt_pass=$(get_password "$tgt_sub" "$tgt_kv")

  echo ""
  echo "=========================================="
  echo "Migration Verification Report"
  echo "=========================================="
  echo ""

  for db in "${databases[@]}"; do
    echo "Database: $db"
    echo "----------------------------------------"

    # Get all tables
    local tables=$(PGPASSWORD="$src_pass" psql -h "$src_host" -U "$src_user" -d "$db" -t -A -c "
      SELECT n.nspname || '.' || c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'r'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
      ORDER BY n.nspname, c.relname;
    ")

    local total=0
    local matched=0
    local mismatched=0

    while IFS= read -r table; do
      [ -z "$table" ] && continue

      total=$((total + 1))

      local src_count=$(PGPASSWORD="$src_pass" psql -h "$src_host" -U "$src_user" -d "$db" -t -A -c "SELECT COUNT(*) FROM $table;")
      local tgt_count=$(PGPASSWORD="$tgt_pass" psql -h "$tgt_host" -U "$tgt_user" -d "$db" -t -A -c "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "ERROR")

      if [ "$src_count" = "$tgt_count" ]; then
        matched=$((matched + 1))
      else
        mismatched=$((mismatched + 1))
        echo "  ✗ $table: Source=$src_count, Target=$tgt_count"
      fi
    done <<< "$tables"

    if [ $mismatched -eq 0 ]; then
      log_info "✓ All $total tables match!"
    else
      log_warn "$mismatched of $total tables have mismatches"
    fi
    echo ""
  done
}

# Parse arguments
SOURCE_CONFIG=""
TARGET_CONFIG=""
VERIFY_ONLY=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=true
      shift
      ;;
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      if [ -z "$SOURCE_CONFIG" ]; then
        SOURCE_CONFIG="$1"
      elif [ -z "$TARGET_CONFIG" ]; then
        TARGET_CONFIG="$1"
      else
        log_error "Unknown argument: $1"
        usage
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [ -z "$SOURCE_CONFIG" ] || [ -z "$TARGET_CONFIG" ]; then
  log_error "Source and target config files are required"
  usage
fi

if [ ! -f "$SOURCE_CONFIG" ]; then
  log_error "Source config file not found: $SOURCE_CONFIG"
  exit 1
fi

if [ ! -f "$TARGET_CONFIG" ]; then
  log_error "Target config file not found: $TARGET_CONFIG"
  exit 1
fi

# Main execution
log_info "PostgreSQL Migration Tool"
log_info "Source: $(jq -r '.host' "$SOURCE_CONFIG")"
log_info "Target: $(jq -r '.host' "$TARGET_CONFIG")"
echo ""

if [ "$VERIFY_ONLY" = true ]; then
  verify_migration "$SOURCE_CONFIG" "$TARGET_CONFIG"
else
  if [ "$SKIP_BACKUP" = false ]; then
    backup_database "$SOURCE_CONFIG"
    echo ""
  fi

  restore_database "$TARGET_CONFIG"
  echo ""

  verify_migration "$SOURCE_CONFIG" "$TARGET_CONFIG"
fi

log_info "Migration completed successfully!"
