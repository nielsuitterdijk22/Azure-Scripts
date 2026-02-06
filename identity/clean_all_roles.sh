#!/bin/bash
set -euo pipefail

DRY_RUN=false
MANAGEMENT_GROUP_ID="DAS-Enterprise"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *)         MANAGEMENT_GROUP_ID="$1"; shift ;;
    esac
done

LOG_FILE="role-assignments-output.txt"
SUCCESS_COUNT=0
FAIL_COUNT=0

> "$LOG_FILE"

log() {
    local level="${2:-INFO}"
    local entry="$(date '+%Y-%m-%d %H:%M:%S') [$level] $1"
    echo "$entry" >> "$LOG_FILE"
    if [[ "$level" == "ERROR" ]]; then
        echo -e "\033[31m$entry\033[0m"
    else
        echo "$entry"
    fi
}

EXCLUDED_SCOPES=(
    "/providers/Microsoft.Management/managementGroups/DAS-Enterprise"
    "/providers/Microsoft.Management/16b5d29f-ebed-43c7-8312-6bf69ffe5e3b"
    "/providers/Microsoft.Management/managementGroups/16b5d29f-ebed-43c7-8312-6bf69ffe5e3b"
    "Tenant Root Group"
)

is_excluded() {
    local scope="$1"
    for s in "${EXCLUDED_SCOPES[@]}"; do
        [[ "$scope" == "$s" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# 1. Fetch all Team* groups from Entra via Graph
# ---------------------------------------------------------------------------
log "Fetching Team* groups from Entra..."
GROUPS_JSON=$(az rest --method get \
    --url 'https://graph.microsoft.com/v1.0/groups?$filter=startswith(displayName,'\''Team'\'')&$select=id,displayName&$top=999' \
    --only-show-errors)

mapfile -t GROUP_IDS   < <(echo "$GROUPS_JSON" | jq -r '.value[].id')
mapfile -t GROUP_NAMES < <(echo "$GROUPS_JSON" | jq -r '.value[].displayName')

if [[ ${#GROUP_IDS[@]} -eq 0 ]]; then
    log "No Team* groups found. Exiting."
    exit 0
fi
log "Found ${#GROUP_IDS[@]} groups."

# Build group ID csv and name lookup for eligible role matching
GID_CSV=""
declare -A GID_NAME_MAP
for i in "${!GROUP_IDS[@]}"; do
    GID_CSV+="${GROUP_IDS[$i]},"
    GID_NAME_MAP[${GROUP_IDS[$i]}]="${GROUP_NAMES[$i]}"
done
GID_CSV="${GID_CSV%,}"

# ---------------------------------------------------------------------------
# 2. Get all subscriptions under the management group (single recursive call)
# ---------------------------------------------------------------------------
log "Traversing management group $MANAGEMENT_GROUP_ID..."
MG_JSON=$(az account management-group show --name "$MANAGEMENT_GROUP_ID" --expand --recurse -o json --only-show-errors)

mapfile -t SUB_ENTRIES < <(echo "$MG_JSON" | jq -r '
    [.. | objects | select(.type == "/subscriptions")] | .[] | "\(.displayName)\t\(.id)"
')

log "Found ${#SUB_ENTRIES[@]} subscriptions."

# ---------------------------------------------------------------------------
# 3. Process each subscription
# ---------------------------------------------------------------------------
for entry in "${SUB_ENTRIES[@]}"; do
    SUB_NAME=$(echo "$entry" | cut -f1)
    SUB_ID=$(echo "$entry" | cut -f2)

    log "Processing $SUB_NAME..."

    # --- Active role assignments (batched delete via --ids) ---
    ACTIVE_ROLES=$(az role assignment list --all --subscription "$SUB_NAME" \
        --query "[?principalType=='Group' && starts_with(principalName, 'Team')].{id:id, name:principalName, role:roleDefinitionName, scope:scope}" \
        -o json --only-show-errors 2>/dev/null || echo "[]")

    ACTIVE_IDS=()
    ACTIVE_DETAILS=()
    while IFS=$'\t' read -r id pname role scope; do
        [[ -z "$id" ]] && continue
        if is_excluded "$scope"; then continue; fi
        if $DRY_RUN; then
            log "WOULD DELETE: $(printf '%-50s' "$pname") | $(printf '%-50s' "$role") | Active     | $scope"
        fi
        ACTIVE_IDS+=("$id")
        ACTIVE_DETAILS+=("$(printf '%-50s' "$pname") | $(printf '%-50s' "$role") | Active     | $scope")
    done < <(echo "$ACTIVE_ROLES" | jq -r '.[] | [.id, .name, .role, .scope] | @tsv')

    if [[ ${#ACTIVE_IDS[@]} -gt 0 ]]; then
        if $DRY_RUN; then
            ((SUCCESS_COUNT += ${#ACTIVE_IDS[@]})) || true
        else
            if az role assignment delete --ids "${ACTIVE_IDS[@]}" --only-show-errors 2>/dev/null; then
                ((SUCCESS_COUNT += ${#ACTIVE_IDS[@]})) || true
                for detail in "${ACTIVE_DETAILS[@]}"; do
                    log "Deleted:      $detail"
                done
            else
                ((FAIL_COUNT += ${#ACTIVE_IDS[@]})) || true
                for detail in "${ACTIVE_DETAILS[@]}"; do
                    log "FAILED:       $detail" "ERROR"
                done
            fi
        fi
    fi

    # --- Eligible (PIM) role assignments (throttled parallel deletes, max 5) ---
    MAX_PARALLEL=5
    ELIGIBLE_ROLES=$(az rest --method get \
        --url "https://management.azure.com${SUB_ID}/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01" \
        --only-show-errors 2>/dev/null | jq '.value // []' || echo "[]")

    PIM_PIDS=()
    PIM_DETAILS=()
    while IFS=$'\t' read -r gid rdname sdname sid rdid; do
        [[ -z "$gid" ]] && continue
        gname="${GID_NAME_MAP[$gid]:-$gid}"

        if is_excluded "$sid"; then continue; fi

        if $DRY_RUN; then
            log "WOULD DELETE: $(printf '%-50s' "$gname") | $(printf '%-50s' "$rdname") | Eligible   | $sid"
            ((SUCCESS_COUNT++)) || true
            continue
        fi

        # Throttle: wait for a slot when at max concurrency
        while [[ ${#PIM_PIDS[@]} -ge $MAX_PARALLEL ]]; do
            REMAINING_PIDS=()
            REMAINING_DETAILS=()
            for j in "${!PIM_PIDS[@]}"; do
                if ! kill -0 "${PIM_PIDS[$j]}" 2>/dev/null; then
                    if wait "${PIM_PIDS[$j]}"; then
                        ((SUCCESS_COUNT++)) || true
                        log "Deleted:      ${PIM_DETAILS[$j]}"
                    else
                        ((FAIL_COUNT++)) || true
                        log "FAILED:       ${PIM_DETAILS[$j]}" "ERROR"
                    fi
                else
                    REMAINING_PIDS+=("${PIM_PIDS[$j]}")
                    REMAINING_DETAILS+=("${PIM_DETAILS[$j]}")
                fi
            done
            PIM_PIDS=("${REMAINING_PIDS[@]}")
            PIM_DETAILS=("${REMAINING_DETAILS[@]}")
            [[ ${#PIM_PIDS[@]} -ge $MAX_PARALLEL ]] && sleep 0.5
        done

        PIM_DETAILS+=("$(printf '%-50s' "$gname") | $(printf '%-50s' "$rdname") | Eligible   | $sid")
        guid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)
        payload="{\"properties\":{\"roleDefinitionId\":\"$rdid\",\"principalId\":\"$gid\",\"requestType\":\"AdminRemove\"}}"

        if [[ "$sid" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]]; then
            url="https://management.azure.com/subscriptions/$sid/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$guid?api-version=2020-10-01"
        else
            url="https://management.azure.com$sid/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$guid?api-version=2020-10-01"
        fi

        az rest --method put --url "$url" --body "$payload" -o none --only-show-errors 2>/dev/null &
        PIM_PIDS+=($!)
    done < <(echo "$ELIGIBLE_ROLES" | jq -r --arg ids "$GID_CSV" '
        ($ids | split(",")) as $id_list |
        [.[] | select(.properties.principalId as $p | $id_list | index($p) != null)]
        | unique_by(.id)
        | .[]
        | [.properties.principalId, .properties.expandedProperties.roleDefinition.displayName, .properties.expandedProperties.scope.displayName, .properties.scope, .properties.roleDefinitionId]
        | @tsv
    ')

    # Wait for remaining PIM deletes
    for i in "${!PIM_PIDS[@]}"; do
        if wait "${PIM_PIDS[$i]}"; then
            ((SUCCESS_COUNT++)) || true
            log "Deleted:      ${PIM_DETAILS[$i]}"
        else
            ((FAIL_COUNT++)) || true
            log "FAILED:       ${PIM_DETAILS[$i]}" "ERROR"
        fi
    done
done

if $DRY_RUN; then
    log "DRY RUN complete. $SUCCESS_COUNT would be deleted."
else
    log "Complete. $SUCCESS_COUNT deleted, $FAIL_COUNT failed."
fi
