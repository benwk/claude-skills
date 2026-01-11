#!/bin/bash
# Azure Container Registry (ACR) Migration Script
# Usage: migrate_acr.sh <source_config> <target_config> [options]

set -e

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

CONFIG FILE FORMAT (JSON):
  {
    "subscription": "subscription-id",
    "registry_name": "myacr",
    "repositories": ["repo1", "repo2"]  // optional
  }
EOF
  exit 1
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
        echo "ERROR: Unknown argument: $1"
        usage
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [ -z "$SOURCE_CONFIG" ] || [ -z "$TARGET_CONFIG" ]; then
  echo "ERROR: Source and target config files are required"
  usage
fi

if [ ! -f "$SOURCE_CONFIG" ]; then
  echo "ERROR: Source config file not found: $SOURCE_CONFIG"
  exit 1
fi

if [ ! -f "$TARGET_CONFIG" ]; then
  echo "ERROR: Target config file not found: $TARGET_CONFIG"
  exit 1
fi

# Read configuration
SOURCE_SUB=$(jq -r '.subscription' "$SOURCE_CONFIG")
SOURCE_ACR=$(jq -r '.registry_name' "$SOURCE_CONFIG")
TARGET_SUB=$(jq -r '.subscription' "$TARGET_CONFIG")
TARGET_ACR=$(jq -r '.registry_name' "$TARGET_CONFIG")

# Calculate cutoff date
if [ "$ALL_IMAGES" = true ]; then
  CUTOFF_DATE=""
  FILTER_MSG="All images"
else
  CUTOFF_DATE=$(date -u -d "$DAYS_AGO days ago" '+%Y-%m-%dT%H:%M:%SZ')
  FILTER_MSG="Images from last $DAYS_AGO days"
fi

echo "=========================================="
echo "ACR Image Sync"
echo "=========================================="
echo "Source: $SOURCE_ACR.azurecr.io"
echo "Target: $TARGET_ACR.azurecr.io"
echo "Filter: $FILTER_MSG"
if [ "$CUTOFF_DATE" != "" ]; then
  echo "Cutoff Date: $CUTOFF_DATE"
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

# Get source ACR password (for import authentication)
echo "Getting source ACR credentials..."
SOURCE_PASSWORD=$(az acr credential show --name $SOURCE_ACR --subscription $SOURCE_SUB --query 'passwords[0].value' -o tsv)

# Get list of repositories
echo "Getting repository list from source ACR..."

# Check if repositories are specified in config
REPOS_FROM_CONFIG=$(jq -r '.repositories[]?' "$SOURCE_CONFIG" 2>/dev/null)
if [ -n "$REPOS_FROM_CONFIG" ]; then
  REPOS="$REPOS_FROM_CONFIG"
  echo "Using repositories from config"
else
  az account set --subscription $SOURCE_SUB > /dev/null 2>&1
  REPOS=$(az acr repository list --name $SOURCE_ACR --output tsv 2>&1)

  if [ -z "$REPOS" ]; then
    echo "ERROR: No repositories found in source ACR"
    exit 1
  fi
fi

echo "Found $(echo "$REPOS" | wc -l) repository/repositories"
echo ""

# Track statistics
TOTAL_IMAGES=0
SYNCED_IMAGES=0
SKIPPED_IMAGES=0
FAILED_IMAGES=0

# Process each repository
for REPO in $REPOS; do
  echo "=========================================="
  echo "Repository: $REPO"
  echo "=========================================="

  # Get all tags with last update time
  az account set --subscription $SOURCE_SUB > /dev/null 2>&1
  TAGS_JSON=$(az acr repository show-tags --detail \
    --name $SOURCE_ACR \
    --repository $REPO \
    --orderby time_desc \
    --output json 2>/dev/null || echo "[]")

  if [ "$TAGS_JSON" == "[]" ]; then
    echo "  Unable to list tags"
    echo ""
    continue
  fi

  # Filter tags by date if needed
  if [ "$ALL_IMAGES" = true ] || [ -z "$CUTOFF_DATE" ]; then
    RECENT_TAGS=$(echo "$TAGS_JSON" | jq -r '.[].name')
  else
    RECENT_TAGS=$(echo "$TAGS_JSON" | jq -r --arg cutoff "$CUTOFF_DATE" \
      '.[] | select(.lastUpdateTime >= $cutoff) | .name')
  fi

  if [ -z "$RECENT_TAGS" ]; then
    echo "No images found matching filter criteria"
    echo ""
    continue
  fi

  echo "Found $(echo "$RECENT_TAGS" | wc -l) image(s)"
  echo ""

  for TAG in $RECENT_TAGS; do
    TOTAL_IMAGES=$((TOTAL_IMAGES + 1))

    # Get last update time for this tag
    LAST_UPDATE=$(echo "$TAGS_JSON" | jq -r --arg tag "$TAG" \
      '.[] | select(.name == $tag) | .lastUpdateTime')

    echo "  Tag: $TAG"
    if [ -n "$LAST_UPDATE" ] && [ "$LAST_UPDATE" != "null" ]; then
      echo "  Last updated: $LAST_UPDATE"
    fi

    # Check if tag exists in target
    az account set --subscription $TARGET_SUB > /dev/null 2>&1
    if az acr repository show-tags --name $TARGET_ACR --repository $REPO --output tsv 2>/dev/null | grep -q "^$TAG$"; then
      echo "  Status: ✓ Already exists in target"
      SKIPPED_IMAGES=$((SKIPPED_IMAGES + 1))
    else
      echo "  Status: ✗ Missing in target"

      if [ "$DIFF_ONLY" = false ] && [ "$VERIFY_ONLY" = false ]; then
        echo "  Action: Importing..."

        # Import with source credentials
        if az acr import \
          --name $TARGET_ACR \
          --subscription $TARGET_SUB \
          --source $SOURCE_ACR.azurecr.io/$REPO:$TAG \
          --image $REPO:$TAG \
          --username $SOURCE_ACR \
          --password "$SOURCE_PASSWORD" \
          --only-show-errors 2>&1; then
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
echo "Summary"
echo "=========================================="
echo "Total images checked: $TOTAL_IMAGES"
if [ "$DIFF_ONLY" = true ]; then
  echo "Already synced: $SKIPPED_IMAGES"
  echo "Missing in target: $((TOTAL_IMAGES - SKIPPED_IMAGES))"
elif [ "$VERIFY_ONLY" = true ]; then
  echo "Synced: $SKIPPED_IMAGES"
  echo "Missing: $((TOTAL_IMAGES - SKIPPED_IMAGES))"
else
  echo "Synced: $SYNCED_IMAGES"
  echo "Skipped (already exists): $SKIPPED_IMAGES"
  echo "Failed: $FAILED_IMAGES"
fi
echo "=========================================="
echo ""

if [ "$DIFF_ONLY" = true ] && [ $TOTAL_IMAGES -gt $SKIPPED_IMAGES ]; then
  echo "⚠️  $((TOTAL_IMAGES - SKIPPED_IMAGES)) image(s) need to be synced"
  exit 1
elif [ "$VERIFY_ONLY" = false ] && [ $FAILED_IMAGES -gt 0 ]; then
  echo "❌ $FAILED_IMAGES image(s) failed to sync"
  exit 1
else
  echo "✅ Done!"
fi
