#!/bin/bash

# Script to enable Microsoft Defender for SQL and Key Vault on all subscriptions
# Requires: Azure CLI with appropriate permissions

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if logged in to Azure
log "Checking Azure CLI authentication..."
az account show > /dev/null 2>&1 || {
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
}

# Get all subscriptions
log "Retrieving all subscriptions..."
subscriptions=$(az account list --query "[?state=='Enabled'].{id:id, name:name}" -o json)
subscription_count=$(echo "$subscriptions" | jq length)

log "Found ${subscription_count} enabled subscription(s)"

# Summary counters
success_count=0
failed_count=0
failed_subs=()

# Iterate through each subscription
echo "$subscriptions" | jq -c '.[]' | while read -r sub; do
    sub_id=$(echo "$sub" | jq -r '.id')
    sub_name=$(echo "$sub" | jq -r '.name')
    
    echo ""
    log "Processing subscription: ${sub_name} (${sub_id})"
    
    # Set the subscription context
    az account set --subscription "$sub_id"
    
    # Enable Defender for SQL
    log "  Enabling Defender for SQL..."
    if az security pricing create \
        --name SqlServers \
        --tier Standard \
        --subscription "$sub_id" > /dev/null 2>&1; then
        log "  ✓ Defender for SQL enabled"
    else
        warn "  ✗ Failed to enable Defender for SQL"
        failed_count=$((failed_count + 1))
        failed_subs+=("${sub_name} - SQL")
    fi
    
    # Enable Defender for Key Vault
    log "  Enabling Defender for Key Vault..."
    if az security pricing create \
        --name KeyVaults \
        --tier Standard \
        --subscription "$sub_id" > /dev/null 2>&1; then
        log "  ✓ Defender for Key Vault enabled"
    else
        warn "  ✗ Failed to enable Defender for Key Vault"
        failed_count=$((failed_count + 1))
        failed_subs+=("${sub_name} - KeyVault")
    fi
    
    # Verify the settings
    log "  Verifying settings..."
    sql_status=$(az security pricing show --name SqlServers --subscription "$sub_id" --query "pricingTier" -o tsv 2>/dev/null || echo "Unknown")
    kv_status=$(az security pricing show --name KeyVaults --subscription "$sub_id" --query "pricingTier" -o tsv 2>/dev/null || echo "Unknown")
    
    log "  Current status:"
    log "    - SQL Servers: ${sql_status}"
    log "    - Key Vaults: ${kv_status}"
    
    if [[ "$sql_status" == "Standard" ]] && [[ "$kv_status" == "Standard" ]]; then
        success_count=$((success_count + 1))
    fi
done

# Print summary
echo ""
echo "======================================"
log "Summary"
echo "======================================"
log "Total subscriptions processed: ${subscription_count}"
log "Successful: ${success_count}"

if [ ${#failed_subs[@]} -gt 0 ]; then
    warn "Failed: ${failed_count}"
    warn "Failed items:"
    for failed in "${failed_subs[@]}"; do
        warn "  - $failed"
    done
fi

log "Script completed"