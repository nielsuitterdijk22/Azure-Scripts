#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 [DAYS] [SUBSCRIPTION_ID]"
    echo "Analyze Azure resource costs over the last N days"
    echo "Default: 30 days, current subscription"
}

DAYS=${1:-30}
SUBSCRIPTION=${2:-$(az account show --query id -o tsv)}

echo "💰 Analyzing costs for last $DAYS days..."

# Top expensive resources
echo "🔥 Most expensive resources:"
az consumption usage list --subscription "$SUBSCRIPTION" --start-date "$(date -d "$DAYS days ago" +%Y-%m-%d)" --end-date "$(date +%Y-%m-%d)" \
    --query 'sort_by([].{resource:instanceName, cost:pretaxCost, meter:meterName}, &cost)' \
    --output table | tail -10

# Cost by resource group
echo "📊 Cost by resource group:"
az consumption usage list --subscription "$SUBSCRIPTION" --start-date "$(date -d "$DAYS days ago" +%Y-%m-%d)" \
    --query 'sort_by([].{resourceGroup:resourceGroup, totalCost:sum(pretaxCost)}, &totalCost)' \
    --output table

# Unused resources detection
echo "🗑️ Potentially unused resources:"
echo "- Stopped VMs:"
az vm list --show-details --query '[?powerState==`VM stopped`].{name:name, resourceGroup:resourceGroup, size:hardwareProfile.vmSize}' -o table

echo "- Unattached disks:"
az disk list --query '[?diskState==`Unattached`].{name:name, resourceGroup:resourceGroup, sizeGb:diskSizeGb}' -o table