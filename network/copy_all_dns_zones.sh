#!/bin/bash

set -e

SOURCE_RG="rg-shared-p-we-001"
SOURCE_SUBSCRIPTION="Connectivity-P"
TARGET_RG="rg-dns-p-we-001"
TARGET_SUBSCRIPTION="Connectivity-P"

echo "Getting subscription IDs..."
SOURCE_SUB_ID=$(az account list --query "[?name=='$SOURCE_SUBSCRIPTION'].id" -o tsv)
TARGET_SUB_ID=$(az account list --query "[?name=='$TARGET_SUBSCRIPTION'].id" -o tsv)

if [ -z "$SOURCE_SUB_ID" ]; then
    echo "Error: Could not find subscription '$SOURCE_SUBSCRIPTION'"
    exit 1
fi

if [ -z "$TARGET_SUB_ID" ]; then
    echo "Error: Could not find subscription '$TARGET_SUBSCRIPTION'"
    exit 1
fi

echo "Source subscription ID: $SOURCE_SUB_ID"
echo "Target subscription ID: $TARGET_SUB_ID"

echo "Getting DNS zones from source resource group..."
az account set --subscription "$SOURCE_SUB_ID"

ZONES=$(az network private-dns zone list --resource-group "$SOURCE_RG" --query "[].name" -o tsv)

if [ -z "$ZONES" ]; then
    echo "No DNS zones found in source resource group"
    exit 0
fi

echo "Found DNS zones:"
echo "$ZONES"
echo ""

for ZONE in $ZONES; do
    echo "Processing zone: $ZONE"
    python3 copy_dns_records.py \
        --source-sub "$SOURCE_SUB_ID" \
        --source-rg "$SOURCE_RG" \
        --source-zone "$ZONE" \
        --target-sub "$TARGET_SUB_ID" \
        --target-rg "$TARGET_RG" \
        --target-zone "$ZONE"
    echo "Completed zone: $ZONE"
    echo ""
done

echo "All DNS zones processed successfully!"