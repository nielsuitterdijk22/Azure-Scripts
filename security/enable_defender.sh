#!/bin/bash

# Script to enable Microsoft Defender plans on all subscriptions
# Requires: Azure CLI with appropriate permissions

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Valid Defender plan names (az security pricing create --name values)
VALID_PLANS=("SqlServers" "KeyVaults" "ContainerRegistry" "AppServices" "StorageAccounts" "Arm" "AI")

# Display names for output
declare -A PLAN_LABELS=(
    [SqlServers]="SQL Servers"
    [KeyVaults]="Key Vaults"
    [ContainerRegistry]="Container Registry"
    [AppServices]="App Services"
    [StorageAccounts]="Storage Accounts"
    [Arm]="Resource Manager"
    [AI]="AI Threat Protection"
)

# Log functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

usage() {
    echo "Usage: $0 <plan> [-s <subscription_name>]"
    echo ""
    echo "Available plans:"
    for plan in "${VALID_PLANS[@]}"; do
        echo "  ${plan}"
    done
    echo "  all  (enable all plans)"
    echo ""
    echo "Options:"
    echo "  -s <name>  Filter to a specific subscription (case-insensitive substring match)"
    exit 1
}

# Enable a single Defender plan for a given subscription
enable_plan() {
    local plan=$1
    local sub_id=$2
    local sub_name=$3
    local label="${PLAN_LABELS[$plan]}"

    log "  Enabling Defender for ${label}..."
    if [[ "$plan" == "StorageAccounts" ]]; then
        # Enable v2 with malware scanning, then sensitive data discovery (each extension needs a separate call)
        if az security pricing create --name StorageAccounts --tier Standard \
            --subplan DefenderForStorageV2 \
            --extensions name=OnUploadMalwareScanning isEnabled=True \
            --subscription "$sub_id" > /dev/null 2>&1 \
        && az security pricing create --name StorageAccounts --tier Standard \
            --subplan DefenderForStorageV2 \
            --extensions name=SensitiveDataDiscovery isEnabled=True \
            --subscription "$sub_id" > /dev/null 2>&1; then
            log "  ✓ Defender for ${label} (v2 + malware scanning) enabled"
            return 0
        fi
    elif [[ "$plan" == "AI" ]]; then
        # Enable AI Threat Protection with all three extensions (each needs a separate call)
        if az security pricing create --name AI --tier Standard \
            --extensions name=AIPromptEvidence isEnabled=True \
            --subscription "$sub_id" > /dev/null 2>&1 \
        && az security pricing create --name AI --tier Standard \
            --extensions name=AIPromptSharingWithPurview isEnabled=True \
            --subscription "$sub_id" > /dev/null 2>&1 \
        && az security pricing create --name AI --tier Standard \
            --extensions name=AIModelScanner isEnabled=True \
            --subscription "$sub_id" > /dev/null 2>&1; then
            log "  ✓ Defender for ${label} (all extensions) enabled"
            return 0
        fi
    else
        if az security pricing create --name "$plan" --tier Standard --subscription "$sub_id" > /dev/null 2>&1; then
            log "  ✓ Defender for ${label} enabled"
            return 0
        fi
    fi

    # Command failed — check if already enabled
    local current
    current=$(az security pricing show --name "$plan" --subscription "$sub_id" --query "pricingTier" -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$current" == "Standard" ]]; then
        if [[ "$plan" == "StorageAccounts" ]]; then
            local subplan
            subplan=$(az security pricing show --name "$plan" --subscription "$sub_id" --query "subPlan" -o tsv 2>/dev/null)
            if [[ "$subplan" == "DefenderForStorageV2" ]]; then
                log "  ✓ Defender for ${label} (v2) already enabled"
                return 0
            fi
            warn "  ✗ ${label} is on the classic plan, upgrading to v2..."
            if az security pricing create --name StorageAccounts --tier Standard \
                --subplan DefenderForStorageV2 \
                --extensions name=OnUploadMalwareScanning isEnabled=True \
                --subscription "$sub_id" > /dev/null 2>&1 \
            && az security pricing create --name StorageAccounts --tier Standard \
                --subplan DefenderForStorageV2 \
                --extensions name=SensitiveDataDiscovery isEnabled=True \
                --subscription "$sub_id" > /dev/null 2>&1; then
                log "  ✓ Upgraded to Defender for ${label} v2"
                return 0
            fi
        elif [[ "$plan" == "AI" ]]; then
            log "  ✓ Defender for ${label} already enabled, ensuring all extensions..."
            if az security pricing create --name AI --tier Standard \
                --extensions name=AIPromptEvidence isEnabled=True \
                --subscription "$sub_id" > /dev/null 2>&1 \
            && az security pricing create --name AI --tier Standard \
                --extensions name=AIPromptSharingWithPurview isEnabled=True \
                --subscription "$sub_id" > /dev/null 2>&1 \
            && az security pricing create --name AI --tier Standard \
                --extensions name=AIModelScanner isEnabled=True \
                --subscription "$sub_id" > /dev/null 2>&1; then
                log "  ✓ Defender for ${label} (all extensions) enabled"
                return 0
            fi
        else
            log "  ✓ Defender for ${label} already enabled"
            return 0
        fi
    fi

    warn "  ✗ Failed to enable Defender for ${label}"
    echo $(($(cat "$tmp_failed") + 1)) > "$tmp_failed"
    echo "${sub_name} - ${plan}" >> "$tmp_failed_subs"
    return 1
}

# --- Argument parsing & validation ---
if [[ $# -lt 1 ]]; then
    error "Missing required argument: plan"
    usage
fi

requested_plan=$1
shift

subscription_filter=""
while getopts ":s:" opt; do
    case $opt in
        s) subscription_filter="$OPTARG" ;;
        *) error "Unknown option: -${OPTARG}"; usage ;;
    esac
done

# Build the list of plans to enable
plans_to_enable=()
if [[ "${requested_plan,,}" == "all" ]]; then
    plans_to_enable=("${VALID_PLANS[@]}")
else
    # Validate the plan name (case-insensitive match)
    matched=false
    for valid in "${VALID_PLANS[@]}"; do
        if [[ "${requested_plan,,}" == "${valid,,}" ]]; then
            plans_to_enable+=("$valid")
            matched=true
            break
        fi
    done

    if [[ "$matched" == false ]]; then
        error "Invalid plan: '${requested_plan}'"
        usage
    fi
fi

# --- Main ---

# Check if logged in to Azure
log "Checking Azure CLI authentication..."
az account show > /dev/null 2>&1 || {
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
}

log "Plan(s) to enable: ${plans_to_enable[*]}"

# Get subscriptions (optionally filtered)
log "Retrieving subscriptions..."
if [[ -n "$subscription_filter" ]]; then
    subscriptions=$(az account list --query "[?state=='Enabled' && contains(name,'${subscription_filter}')].{id:id, name:name}" -o json)
else
    subscriptions=$(az account list --query "[?state=='Enabled'].{id:id, name:name}" -o json)
fi
subscription_count=$(echo "$subscriptions" | jq length)

if [[ "$subscription_count" -eq 0 ]]; then
    error "No subscriptions found matching '${subscription_filter}'"
    exit 1
fi

log "Found ${subscription_count} subscription(s)"

# Create temporary files for tracking results
tmp_success=$(mktemp)
tmp_failed=$(mktemp)
tmp_failed_subs=$(mktemp)

echo "0" > "$tmp_success"
echo "0" > "$tmp_failed"

# Iterate through each subscription
while IFS= read -r sub; do
    sub_id=$(echo "$sub" | jq -r '.id')
    sub_name=$(echo "$sub" | jq -r '.name')

    echo ""
    log "Processing subscription: ${sub_name} (${sub_id})"

    az account set --subscription "$sub_id"

    # Enable each requested plan
    for plan in "${plans_to_enable[@]}"; do
        enable_plan "$plan" "$sub_id" "$sub_name" || true
    done

    # Verify settings
    log "  Verifying settings..."
    all_standard=true
    for plan in "${plans_to_enable[@]}"; do
        status=$(az security pricing show --name "$plan" --subscription "$sub_id" --query "pricingTier" -o tsv 2>/dev/null || echo "Unknown")
        if [[ "$plan" == "StorageAccounts" && "$status" == "Standard" ]]; then
            subplan=$(az security pricing show --name "$plan" --subscription "$sub_id" --query "subPlan" -o tsv 2>/dev/null)
            malware=$(az security pricing show --name "$plan" --subscription "$sub_id" --query "extensions[?name=='OnUploadMalwareScanning'].isEnabled | [0]" -o tsv 2>/dev/null)
            log "    - ${PLAN_LABELS[$plan]}: ${status} (${subplan}, MalwareScanning=${malware})"
        else
            log "    - ${PLAN_LABELS[$plan]}: ${status}"
        fi
        if [[ "$status" != "Standard" ]]; then
            all_standard=false
        fi
    done

    if [[ "$all_standard" == true ]]; then
        echo $(($(cat "$tmp_success") + 1)) > "$tmp_success"
    fi
done < <(echo "$subscriptions" | jq -c '.[]')

# Read final counts from temp files
success_count=$(cat "$tmp_success")
failed_count=$(cat "$tmp_failed")

failed_subs=()
if [[ -s "$tmp_failed_subs" ]]; then
    while IFS= read -r line; do
        failed_subs+=("$line")
    done < "$tmp_failed_subs"
fi

rm -f "$tmp_success" "$tmp_failed" "$tmp_failed_subs"

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
