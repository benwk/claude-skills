#!/bin/bash
# Azure Storage Account Migration Script
# Usage: migrate_storage.sh <source_config> <target_config> [--verify-only]
#
# Config format (JSON):
# {
#   "subscription": "subscription-id",
#   "account_name": "stmycompanyprod",
#   "resource_group": "rg-mycompany-prod",
#   "containers": ["xeni", "static", "backups"]
# }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/storage_migration_$(date +%Y%m%d_%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
  cat << EOF
Azure Storage Account Migration Tool

USAGE:
  $0 <source_config.json> <target_config.json> [options]

OPTIONS:
  --verify-only     Only verify data, don't migrate
  --skip-download   Skip download step (use existing local copy)
  --temp-dir DIR    Use specific temp directory
  --help            Show this help message

EXAMPLE:
  $0 staging_storage.json preview_storage.json
  $0 staging_storage.json preview_storage.json --verify-only

CONFIG FILE FORMAT (JSON):
  {
    "subscription": "subscription-id",
    "account_name": "stmycompanyprod",
    "resource_group": "rg-mycompany-prod",
    "containers": ["xeni", "static", "backups"]
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

get_storage_key() {
  local subscription=$1
  local account_name=$2
  local resource_group=$3

  az account set --subscription "$subscription" > /dev/null 2>&1
  az storage account keys list \
    --account-name "$account_name" \
    --resource-group "$resource_group" \
    --query "[0].value" -o tsv
}

generate_sas() {
  local subscription=$1
  local account_name=$2
  local account_key=$3
  local container=$4
  local permissions=$5

  az account set --subscription "$subscription" > /dev/null 2>&1
  local expiry=$(date -u -d "4 hours" '+%Y-%m-%dT%H:%MZ')

  az storage container generate-sas \
    --account-name "$account_name" \
    --account-key "$account_key" \
    --name "$container" \
    --permissions "$permissions" \
    --expiry "$expiry" \
    -o tsv
}

download_container() {
  local subscription=$1
  local account_name=$2
  local account_key=$3
  local container=$4

  log_info "Downloading container: $container"

  local sas=$(generate_sas "$subscription" "$account_name" "$account_key" "$container" "rl")

  mkdir -p "$TEMP_DIR"

  azcopy copy \
    "https://${account_name}.blob.core.windows.net/${container}/*?${sas}" \
    "$TEMP_DIR/" \
    --recursive \
    --log-level=INFO

  local count=$(find "$TEMP_DIR" -type f | wc -l)
  log_info "✓ Downloaded $count files"
}

upload_container() {
  local subscription=$1
  local account_name=$2
  local account_key=$3
  local container=$4

  log_info "Uploading to container: $container"

  # Ensure container exists
  az account set --subscription "$subscription" > /dev/null 2>&1
  az storage container create \
    --name "$container" \
    --account-name "$account_name" \
    --account-key "$account_key" \
    --output none 2>/dev/null || true

  local sas=$(generate_sas "$subscription" "$account_name" "$account_key" "$container" "rwl")

  cd "$TEMP_DIR"
  azcopy copy \
    "./*" \
    "https://${account_name}.blob.core.windows.net/${container}?${sas}" \
    --recursive \
    --log-level=INFO

  local count=$(find "$TEMP_DIR" -type f | wc -l)
  log_info "✓ Uploaded $count files"
}

verify_migration() {
  local source_config=$1
  local target_config=$2

  local src_sub=$(jq -r '.subscription' "$source_config")
  local src_account=$(jq -r '.account_name' "$source_config")
  local src_rg=$(jq -r '.resource_group' "$source_config")

  local tgt_sub=$(jq -r '.subscription' "$target_config")
  local tgt_account=$(jq -r '.account_name' "$target_config")
  local tgt_rg=$(jq -r '.resource_group' "$target_config")

  local containers=($(jq -r '.containers[]' "$source_config"))

  log_info "Verifying migration..."

  local src_key=$(get_storage_key "$src_sub" "$src_account" "$src_rg")
  local tgt_key=$(get_storage_key "$tgt_sub" "$tgt_account" "$tgt_rg")

  echo ""
  echo "=========================================="
  echo "Storage Migration Verification Report"
  echo "=========================================="
  echo ""

  for container in "${containers[@]}"; do
    echo "Container: $container"
    echo "----------------------------------------"

    az account set --subscription "$src_sub" > /dev/null 2>&1
    local src_count=$(az storage blob list \
      --account-name "$src_account" \
      --account-key "$src_key" \
      --container-name "$container" \
      --query "length(@)" -o tsv 2>/dev/null || echo "0")

    az account set --subscription "$tgt_sub" > /dev/null 2>&1
    local tgt_count=$(az storage blob list \
      --account-name "$tgt_account" \
      --account-key "$tgt_key" \
      --container-name "$container" \
      --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [ "$src_count" = "$tgt_count" ]; then
      log_info "✓ Blob counts match: $src_count files"
    else
      log_warn "✗ Blob counts differ - Source: $src_count, Target: $tgt_count"
    fi
    echo ""
  done
}

cleanup_temp() {
  if [ -d "$TEMP_DIR" ]; then
    log_info "Cleaning up temp directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
  fi
}

# Parse arguments
SOURCE_CONFIG=""
TARGET_CONFIG=""
VERIFY_ONLY=false
SKIP_DOWNLOAD=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
    --skip-download)
      SKIP_DOWNLOAD=true
      shift
      ;;
    --temp-dir)
      TEMP_DIR="$2"
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
log_info "Azure Storage Account Migration Tool"
log_info "Source: $(jq -r '.account_name' "$SOURCE_CONFIG")"
log_info "Target: $(jq -r '.account_name' "$TARGET_CONFIG")"
echo ""

if [ "$VERIFY_ONLY" = true ]; then
  verify_migration "$SOURCE_CONFIG" "$TARGET_CONFIG"
else
  # Get configuration
  src_sub=$(jq -r '.subscription' "$SOURCE_CONFIG")
  src_account=$(jq -r '.account_name' "$SOURCE_CONFIG")
  src_rg=$(jq -r '.resource_group' "$SOURCE_CONFIG")

  tgt_sub=$(jq -r '.subscription' "$TARGET_CONFIG")
  tgt_account=$(jq -r '.account_name' "$TARGET_CONFIG")
  tgt_rg=$(jq -r '.resource_group' "$TARGET_CONFIG")

  containers=($(jq -r '.containers[]' "$SOURCE_CONFIG"))

  src_key=$(get_storage_key "$src_sub" "$src_account" "$src_rg")
  tgt_key=$(get_storage_key "$tgt_sub" "$tgt_account" "$tgt_rg")

  for container in "${containers[@]}"; do
    echo "=========================================="
    echo "Migrating container: $container"
    echo "=========================================="
    echo ""

    if [ "$SKIP_DOWNLOAD" = false ]; then
      download_container "$src_sub" "$src_account" "$src_key" "$container"
      echo ""
    fi

    upload_container "$tgt_sub" "$tgt_account" "$tgt_key" "$container"
    echo ""

    cleanup_temp
  done

  verify_migration "$SOURCE_CONFIG" "$TARGET_CONFIG"
fi

log_info "Migration completed successfully!"
