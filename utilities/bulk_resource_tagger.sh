#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 RESOURCE_GROUP TAG_NAME TAG_VALUE"
    echo "Add tags to all resources in a resource group"
    echo ""
    echo "Example: $0 rg-production Environment Production"
}

if [[ $# -ne 3 ]]; then
    usage
    exit 1
fi

RESOURCE_GROUP="$1"
TAG_NAME="$2"
TAG_VALUE="$3"

echo "🏷️  Tagging all resources in '$RESOURCE_GROUP' with $TAG_NAME=$TAG_VALUE"

# Get all resources in resource group
resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].id' -o tsv)

if [[ -z "$resources" ]]; then
    echo "❌ No resources found in resource group '$RESOURCE_GROUP'"
    exit 1
fi

count=0
while IFS= read -r resource_id; do
    if [[ -n "$resource_id" ]]; then
        echo "🔄 Tagging: $(basename "$resource_id")"
        az resource tag --ids "$resource_id" --tags "$TAG_NAME=$TAG_VALUE" --operation merge
        ((count++))
    fi
done <<< "$resources"

echo "✅ Successfully tagged $count resources"