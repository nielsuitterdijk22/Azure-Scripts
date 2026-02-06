#!/bin/bash

# Script to remove all Azure Security Center (ASC) subscription policy assignments
# Useful when moving to mg level policies or cleaning up unwanted ASC policies
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
total_assignments_removed=0
failed_assignments=()

# Create temporary files for tracking results
tmp_success=$(mktemp)
tmp_failed=$(mktemp)
tmp_removed=$(mktemp)
tmp_failed_assignments=$(mktemp)

echo "0" > "$tmp_success"
echo "0" > "$tmp_failed"
echo "0" > "$tmp_removed"

# ASC/Microsoft Defender initiative definition IDs (commonly assigned ASC policies)
ASC_INITIATIVES=(
    "1f3afdf9-d0c9-4c3d-847f-89da613e70a8"  # Azure Security Benchmark
    "4f9dc7db-30c1-420c-b61a-e1d640128d26"  # Microsoft Defender for Cloud (ASC Default)
    "2c89a2e5-7285-40fe-afe4-40d0b03fab63"  # Configure Microsoft Defender for Cloud to be enabled
    "06e5a4f5-05b5-4fc9-8094-eaf6f8a83c0d"  # ASC DataProtection
)

# Iterate through each subscription
while IFS= read -r sub; do
    sub_id=$(echo "$sub" | jq -r '.id')
    sub_name=$(echo "$sub" | jq -r '.name')

    echo ""
    log "Processing subscription: ${sub_name} (${sub_id})"

    # Set the subscription context
    az account set --subscription "$sub_id"

    # Get all policy assignments for this subscription
    assignments=$(az policy assignment list --subscription "$sub_id" --query "[].{name:name, displayName:displayName, policyDefinitionId:policyDefinitionId, scope:scope}" -o json 2>/dev/null)

    if [ $? -ne 0 ] || [ "$assignments" == "null" ] || [ "$assignments" == "[]" ]; then
        log "  No policy assignments found or unable to retrieve assignments"
        continue
    fi

    assignment_count=$(echo "$assignments" | jq length)
    log "  Found ${assignment_count} policy assignment(s)"

    sub_removed_count=0

    # Process each assignment
    while IFS= read -r assignment; do
        assignment_name=$(echo "$assignment" | jq -r '.name')
        display_name=$(echo "$assignment" | jq -r '.displayName // "N/A"')
        policy_def_id=$(echo "$assignment" | jq -r '.policyDefinitionId // ""')
        scope=$(echo "$assignment" | jq -r '.scope')

        # Check if this is an ASC/Microsoft Defender related policy
        is_asc_policy=false

        # Check against known ASC initiative IDs
        for asc_id in "${ASC_INITIATIVES[@]}"; do
            if [[ "$policy_def_id" == *"$asc_id"* ]]; then
                is_asc_policy=true
                break
            fi
        done

        # Also check for common ASC/Security Center keywords in names
        if [[ "$display_name" == *"Security Center"* ]] || \
           [[ "$display_name" == *"Microsoft Defender"* ]] || \
           [[ "$display_name" == *"ASC"* ]] || \
           [[ "$display_name" == *"Azure Security Benchmark"* ]] || \
           [[ "$assignment_name" == *"SecurityCenterBuiltIn"* ]] || \
           [[ "$assignment_name" == *"ASC"* ]]; then
            is_asc_policy=true
        fi

        if [ "$is_asc_policy" = true ]; then
            # Remove the policy assignment
            az policy assignment delete --name "$assignment_name" --scope "$scope" > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                log "  ✓ Successfully removed: ${display_name}"
                sub_removed_count=$((sub_removed_count + 1))
            else
                warn "  ✗ Failed to remove: ${display_name} (${assignment_name})"
                echo $(($(cat "$tmp_failed") + 1)) > "$tmp_failed"
                echo "${sub_name} - ${display_name}" >> "$tmp_failed_assignments"
            fi
        fi

    done < <(echo "$assignments" | jq -c '.[]')

done < <(echo "$subscriptions" | jq -c '.[]')

# Read final counts from temp files
success_count=$(cat "$tmp_success")
failed_count=$(cat "$tmp_failed")
total_assignments_removed=$(cat "$tmp_removed")

# Read failed assignments into array
failed_assignments=()
if [[ -s "$tmp_failed_assignments" ]]; then
    while IFS= read -r line; do
        failed_assignments+=("$line")
    done < "$tmp_failed_assignments"
fi

# Clean up temp files
rm -f "$tmp_success" "$tmp_failed" "$tmp_removed" "$tmp_failed_assignments"

# Print summary
echo ""
echo "======================================"
log "Summary"
echo "======================================"
log "Total subscriptions processed: ${subscription_count}"
log "Subscriptions with ASC policies removed: ${success_count}"
log "Total ASC policy assignments removed: ${total_assignments_removed}"

if [ ${#failed_assignments[@]} -gt 0 ]; then
    warn "Failed to remove ${failed_count} assignment(s):"
    for failed in "${failed_assignments[@]}"; do
        warn "  - $failed"
    done
fi

log "Script completed"