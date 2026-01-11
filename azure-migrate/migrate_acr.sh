#!/bin/bash
# Azure Container Registry (ACR) Migration Script
# Usage: migrate_acr.sh <source_config> <target_config> [options]
#
# Config format (JSON):
# {
#   "subscription": "subscription-id",
#   "registry_name": "myacr",
#   "repositories": ["repo1", "repo2"]  // optional, if not specified will sync all
# }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DAYS_AGO=7
DIFF_ONLY=false
VERIFY_ONLY=false

usage() {
  cat << EOF
Azure Container Registry (ACR) Migration Tool

USAGE:
  $0 <source_config.json> <target_config.json> [options]

OPTIONS:
  --days N          Only sync images updated in last N days (default: 7)
  --all-images      Sync all images regardless of age
  --diff-only       Only show differences, don't sync
  --verify-only     Only verify sync status, don't sync
  --help            Show this help message

EXAMPLE:
  $0 source_acr.json target_acr.json
  $0 source_acr.json target_acr.json --days 3
  $0 source_acr.json target_acr.json --diff-only
  $0 source_acr.json target_acr.json --verify-only

CONFIG FILE FORMAT (JSON):
  {
    "subscription": "subscription-id",
    "registry_name": "myacr",
    "repositories": ["repo1", "repo2"]  // optional
  }

NOTES:
  - If repositories is not specified, all repositories will be synced
  - Images already existing in target ACR will be skipped
  - Use --diff-only to preview changes before actual sync
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

log_debug() {
  echo -e "${BLUE}[DEBUG]${NC} $1"
}

get_acr_password() {
  local subscription=$1
  local registry_name=$2

  az account set --subscription "$subscription" > /dev/null 2>&1
  az acr credential show \
    --name "$registry_name" \
    --query "passwords[0].value" -o tsv
}

get_repositories() {
  local subscription=$1
  local registry_name=$2
  local config_file=$3

  # Check if repositories are specified in config
  local repos_from_config=$(jq -r '.repositories[]?' "$config_file" 2>/dev/null)

  if [ -n "$repos_from_config" ]; then
    echo "$repos_from_config"
  else
    # Get all repositories from ACR
    az account set --subscription "$subscription" > /dev/null 2>&1
    az acr repository list \
      --name "$registry_name" \
      --output tsv 2>&1
  fi
}

get_recent_tags() {
  local subscription=$1
  local registry_name=$2
  local repository=$3
  local days_ago=$4

  az account set --subscription "$subscription" > /dev/null 2>&1

  if [ "$days_ago" = "all" ]; then
    # Get all tags
    az acr repository show-tags \
      --name "$registry_name" \
      --repository "$repository" \
      --orderby time_desc \
      --output tsv 2>/dev/null || echo ""
  else
    # Calculate cutoff date
    local cutoff_date=$(date -u -d "$days_ago days ago" '+%Y-%m-%dT%H:%M:%SZ')

    # Get tags with details and filter by date
    local tags_json=$(az acr repository show-tags --detail \
      --name "$registry_name" \
      --repository "$repository" \
      --orderby time_desc \
      --output json 2>/dev/null || echo "[]")

    echo "$tags_json" | jq -r --arg cutoff "$cutoff_date" \
      '.[] | select(.lastUpdateTime >= $cutoff) | .name'
  fi
}

get_tag_info() {
  local subscription=$1
  local registry_name=$2
  local repository=$3
  local tag=$4

  az account set --subscription "$subscription" > /dev/null 2>&1

  az acr repository show-tags --detail \
    --name "$registry_name" \
    --repository "$repository" \
    --output json 2>/dev/null | \
    jq -r --arg tag "$tag" '.[] | select(.name == $tag) | .lastUpdateTime'
}

check_tag_exists() {
  local subscription=$1
  local registry_name=$2
  local repository=$3
  local tag=$4

  az account set --subscription "$subscription" > /dev/null 2>&1

  az acr repository show-tags \
    --name "$registry_name" \
    --repository "$repository" \
    --output tsv 2>/dev/null | grep -q "^$tag$"
}

import_image() {
  local src_sub=$1
  local src_registry=$2
  local src_password=$3
  local tgt_sub=$4
  local tgt_registry=$5
  local repository=$6
  local tag=$7

  az account set --subscription "$tgt_sub" > /dev/null 2>&1

  az acr import \
    --name "$tgt_registry" \
    --source "$src_registry.azurecr.io/$repository:$tag" \
    --image "$repository:$tag" \
    --username "$src_registry" \
    --password "$src_password" \
    --only-show-errors 2>&1
}

verify_sync() {
  local source_config=$1
  local target_config=$2
  local days_filter=$3

  local src_sub=$(jq -r '.subscription' "$source_config")
  local src_registry=$(jq -r '.registry_name' "$source_config")

  local tgt_sub=$(jq -r '.subscription' "$target_config")
  local tgt_registry=$(jq -r '.registry_name' "$target_config")

  log_info "Verifying ACR sync status..."
  echo ""
  echo "=========================================="
  echo "ACR Sync Verification Report"
  echo "=========================================="
  echo "Source: $src_registry.azurecr.io"
  echo "Target: $tgt_registry.azurecr.io"
  if [ "$days_filter" != "all" ]; then
    echo "Filter: Images from last $days_filter days"
  fi
  echo "=========================================="
  echo ""

  local repos=$(get_repositories "$src_sub" "$src_registry" "$source_config")

  local total_missing=0
  local total_synced=0

  for repo in $repos; do
    echo "Repository: $repo"
    echo "----------------------------------------"

    local tags=$(get_recent_tags "$src_sub" "$src_registry" "$repo" "$days_filter")

    if [ -z "$tags" ]; then
      echo "  No images found"
      echo ""
      continue
    fi

    local repo_missing=0
    local repo_synced=0

    for tag in $tags; do
      if check_tag_exists "$tgt_sub" "$tgt_registry" "$repo" "$tag"; then
        echo "  ✓ $tag (synced)"
        repo_synced=$((repo_synced + 1))
        total_synced=$((total_synced + 1))
      else
        echo "  ✗ $tag (missing)"
        repo_missing=$((repo_missing + 1))
        total_missing=$((total_missing + 1))
      fi
    done

    echo "  Summary: $repo_synced synced, $repo_missing missing"
    echo ""
  done

  echo "=========================================="
  echo "Overall: $total_synced synced, $total_missing missing"
  echo "=========================================="
}

# Parse arguments
SOURCE_CONFIG=""
TARGET_CONFIG=""
ALL_IMAGES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --days)
      DAYS_AGO="$2"
      shift 2
      ;;
    --all-images)
      ALL_IMAGES=true
      shift
      ;;
    --diff-only)
      DIFF_ONLY=true
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=true
      shift
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

# Set days filter
if [ "$ALL_IMAGES" = true ]; then
  DAYS_FILTER="all"
else
  DAYS_FILTER="$DAYS_AGO"
fi

# Get configuration
src_sub=$(jq -r '.subscription' "$SOURCE_CONFIG")
src_registry=$(jq -r '.registry_name' "$SOURCE_CONFIG")

tgt_sub=$(jq -r '.subscription' "$TARGET_CONFIG")
tgt_registry=$(jq -r '.registry_name' "$TARGET_CONFIG")

# Main execution
echo "=========================================="
echo "Azure Container Registry Migration Tool"
echo "=========================================="
echo "Source: $src_registry.azurecr.io"
echo "Target: $tgt_registry.azurecr.io"
if [ "$DAYS_FILTER" != "all" ]; then
  echo "Filter: Images from last $DAYS_FILTER days"
else
  echo "Filter: All images"
fi
if [ "$DIFF_ONLY" = true ]; then
  echo "Mode: Diff only (no sync)"
elif [ "$VERIFY_ONLY" = true ]; then
  echo "Mode: Verify only"
else
  echo "Mode: Sync"
fi
echo "=========================================="
echo ""

if [ "$VERIFY_ONLY" = true ]; then
  verify_sync "$SOURCE_CONFIG" "$TARGET_CONFIG" "$DAYS_FILTER"
  exit 0
fi

# Get source ACR password
log_info "Getting source ACR credentials..."
src_password=$(get_acr_password "$src_sub" "$src_registry")

# Get repositories
log_info "Getting repository list..."
repos=$(get_repositories "$src_sub" "$src_registry" "$SOURCE_CONFIG")

if [ -z "$repos" ]; then
  log_error "No repositories found"
  exit 1
fi

echo "Found $(echo "$repos" | wc -l) repository/repositories"
echo ""

# Track statistics
TOTAL_IMAGES=0
SYNCED_IMAGES=0
SKIPPED_IMAGES=0
FAILED_IMAGES=0
DIFF_IMAGES=0

# Process each repository
for repo in $repos; do
  echo "=========================================="
  echo "Repository: $repo"
  echo "=========================================="

  # Get recent tags
  tags=$(get_recent_tags "$src_sub" "$src_registry" "$repo" "$DAYS_FILTER")

  if [ -z "$tags" ]; then
    log_info "No images found matching filter criteria"
    echo ""
    continue
  fi

  echo "Found $(echo "$tags" | wc -l) image(s):"
  echo ""

  for tag in $tags; do
    TOTAL_IMAGES=$((TOTAL_IMAGES + 1))

    # Get tag metadata
    last_update=$(get_tag_info "$src_sub" "$src_registry" "$repo" "$tag")

    echo "  Tag: $tag"
    if [ -n "$last_update" ]; then
      echo "  Last updated: $last_update"
    fi

    # Check if exists in target
    if check_tag_exists "$tgt_sub" "$tgt_registry" "$repo" "$tag"; then
      echo "  Status: ✓ Already exists in target"
      SKIPPED_IMAGES=$((SKIPPED_IMAGES + 1))
    else
      echo "  Status: ✗ Missing in target"
      DIFF_IMAGES=$((DIFF_IMAGES + 1))

      if [ "$DIFF_ONLY" = false ]; then
        echo "  Action: Importing..."

        if import_image "$src_sub" "$src_registry" "$src_password" \
                        "$tgt_sub" "$tgt_registry" "$repo" "$tag"; then
          echo "  Result: ✓ Imported successfully"
          SYNCED_IMAGES=$((SYNCED_IMAGES + 1))
        else
          echo "  Result: ✗ Import failed"
          FAILED_IMAGES=$((FAILED_IMAGES + 1))
        fi
      fi
    fi

    echo ""
  done
done

echo "=========================================="
echo "Migration Summary"
echo "=========================================="
echo "Total images checked: $TOTAL_IMAGES"
if [ "$DIFF_ONLY" = true ]; then
  echo "Already synced: $SKIPPED_IMAGES"
  echo "Missing in target: $DIFF_IMAGES"
else
  echo "Synced: $SYNCED_IMAGES"
  echo "Skipped (already exists): $SKIPPED_IMAGES"
  echo "Failed: $FAILED_IMAGES"
fi
echo "=========================================="
echo ""

if [ "$DIFF_ONLY" = true ]; then
  if [ $DIFF_IMAGES -gt 0 ]; then
    log_warn "$DIFF_IMAGES image(s) need to be synced"
    exit 1
  else
    log_info "All images are in sync!"
  fi
else
  if [ $FAILED_IMAGES -gt 0 ]; then
    log_error "$FAILED_IMAGES image(s) failed to sync"
    exit 1
  else
    log_info "Migration completed successfully!"
  fi
fi
