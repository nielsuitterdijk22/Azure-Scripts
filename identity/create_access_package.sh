#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 -p PACKAGE_NAME -c CATALOG_NAME [-d DESCRIPTION] [-g GROUP_ID ...] [--new-catalog] [-h]"
    echo ""
    echo "  -p, --package      NAME        Access package display name (required)"
    echo "  -c, --catalog      NAME        Catalog name (required)"
    echo "      --new-catalog              Create catalog if it does not exist"
    echo "  -d, --description  TEXT        Access package description"
    echo "  -g, --group        GROUP_ID    Entra group object ID to add as resource (repeatable)"
    echo "      --policy-name  NAME        Assignment policy name (default: 'Default Policy')"
    echo "      --policy-duration DAYS     Policy duration in days (default: 365, use 0 for no expiry)"
    echo "  -h, --help                     Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -p 'Finance Team Access' -c 'Finance Catalog' --new-catalog -g 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
    echo "  $0 -p 'HR Tools' -c 'HR Catalog' -d 'Access to HR resources' -g <group1-id> -g <group2-id>"
}

PACKAGE_NAME=""
CATALOG_NAME=""
DESCRIPTION=""
GROUP_IDS=()
NEW_CATALOG=false
POLICY_NAME="Default Policy"
POLICY_DURATION=365

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--package)     PACKAGE_NAME="$2"; shift 2 ;;
        -c|--catalog)     CATALOG_NAME="$2"; shift 2 ;;
        --new-catalog)    NEW_CATALOG=true; shift ;;
        -d|--description) DESCRIPTION="$2"; shift 2 ;;
        -g|--group)       GROUP_IDS+=("$2"); shift 2 ;;
        --policy-name)    POLICY_NAME="$2"; shift 2 ;;
        --policy-duration) POLICY_DURATION="$2"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$PACKAGE_NAME" || -z "$CATALOG_NAME" ]]; then
    echo "Error: --package and --catalog are required"
    usage; exit 1
fi

DESCRIPTION="${DESCRIPTION:-$PACKAGE_NAME}"

# --- Helper: call Graph API ---
graph_get() {
    az rest --method GET --uri "https://graph.microsoft.com/v1.0/$1" -o json
}

graph_post() {
    az rest --method POST --uri "https://graph.microsoft.com/v1.0/$1" \
        --headers 'Content-Type=application/json' \
        --body "$2" -o json
}

# --- 1. Find or create catalog ---
echo "Searching for catalog: $CATALOG_NAME"

CATALOG_ID=$(graph_get "identityGovernance/entitlementManagement/catalogs?\$filter=displayName eq '${CATALOG_NAME}'" \
    | jq -r '.value[0].id // empty')

if [[ -n "$CATALOG_ID" ]]; then
    echo "Found existing catalog: $CATALOG_NAME ($CATALOG_ID)"
else
    if [[ "$NEW_CATALOG" == false ]]; then
        echo "Error: Catalog '$CATALOG_NAME' not found."
        echo "Use --new-catalog to create it automatically."
        echo ""
        echo "Available catalogs:"
        graph_get "identityGovernance/entitlementManagement/catalogs" \
            | jq -r '.value[] | "  \(.displayName)  (\(.id))"'
        exit 1
    fi

    echo "Creating new catalog: $CATALOG_NAME"
    CATALOG_BODY=$(jq -n \
        --arg name "$CATALOG_NAME" \
        --arg desc "$CATALOG_NAME catalog" \
        '{displayName: $name, description: $desc, isExternallyVisible: false}')

    CATALOG_ID=$(graph_post "identityGovernance/entitlementManagement/catalogs" "$CATALOG_BODY" \
        | jq -r '.id')

    echo "Created catalog: $CATALOG_NAME ($CATALOG_ID)"
fi

# --- 2. Add group resources to catalog ---
for GROUP_ID in "${GROUP_IDS[@]}"; do
    echo "Adding group $GROUP_ID to catalog..."

    # Check if already in catalog
    EXISTING=$(graph_get "identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources?\$filter=originId eq '${GROUP_ID}'" \
        | jq -r '.value[0].id // empty')

    if [[ -n "$EXISTING" ]]; then
        echo "  Group $GROUP_ID already in catalog, skipping."
        continue
    fi

    RESOURCE_BODY=$(jq -n \
        --arg gid "$GROUP_ID" \
        '{requestType: "adminAdd", resources: [{originId: $gid, originSystem: "AadGroup"}]}')

    graph_post "identityGovernance/entitlementManagement/resourceRequests" "$RESOURCE_BODY" >/dev/null
    echo "  Added group $GROUP_ID to catalog."
done

# --- 3. Create access package ---
echo "Creating access package: $PACKAGE_NAME"

# Check if it already exists in the catalog
EXISTING_PKG=$(graph_get "identityGovernance/entitlementManagement/accessPackages?\$filter=displayName eq '${PACKAGE_NAME}' and catalog/id eq '${CATALOG_ID}'" \
    | jq -r '.value[0].id // empty')

if [[ -n "$EXISTING_PKG" ]]; then
    echo "Access package '$PACKAGE_NAME' already exists in catalog ($EXISTING_PKG)"
    ACCESS_PACKAGE_ID="$EXISTING_PKG"
else
    PACKAGE_BODY=$(jq -n \
        --arg name "$PACKAGE_NAME" \
        --arg desc "$DESCRIPTION" \
        --arg cid "$CATALOG_ID" \
        '{displayName: $name, description: $desc, isHidden: false, catalog: {id: $cid}}')

    ACCESS_PACKAGE_ID=$(graph_post "identityGovernance/entitlementManagement/accessPackages" "$PACKAGE_BODY" \
        | jq -r '.id')

    echo "Created access package: $PACKAGE_NAME ($ACCESS_PACKAGE_ID)"
fi

# --- 4. Link group resource scopes to access package ---
if [[ ${#GROUP_IDS[@]} -gt 0 ]]; then
    echo "Linking resource scopes to access package..."

    for GROUP_ID in "${GROUP_IDS[@]}"; do
        # Get the catalog resource ID for this group
        RESOURCE_ID=$(graph_get "identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources?\$filter=originId eq '${GROUP_ID}'" \
            | jq -r '.value[0].id // empty')

        if [[ -z "$RESOURCE_ID" ]]; then
            echo "  Warning: Could not find resource for group $GROUP_ID in catalog, skipping."
            continue
        fi

        # Get the member scope for the group resource
        SCOPE_ID=$(graph_get "identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resourceScopes?\$filter=originSystem eq 'AadGroup' and originId eq '${GROUP_ID}'" \
            | jq -r '.value[0].id // empty')

        # If no scope returned via filter, get directly from resource
        if [[ -z "$SCOPE_ID" ]]; then
            SCOPE_ID=$(graph_get "identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources/${RESOURCE_ID}/scopes" \
                | jq -r '.value[0].id // empty')
        fi

        if [[ -z "$SCOPE_ID" ]]; then
            echo "  Warning: Could not find scope for group $GROUP_ID, skipping."
            continue
        fi

        ROLE_ID=$(graph_get "identityGovernance/entitlementManagement/catalogs/${CATALOG_ID}/resources/${RESOURCE_ID}/roles" \
            | jq -r '.value[] | select(.displayName == "Member") | .id' | head -1)

        if [[ -z "$ROLE_ID" ]]; then
            echo "  Warning: Could not find Member role for group $GROUP_ID, skipping."
            continue
        fi

        SCOPE_BODY=$(jq -n \
            --arg rid "$RESOURCE_ID" \
            --arg roleid "$ROLE_ID" \
            --arg scopeid "$SCOPE_ID" \
            '{role: {id: $roleid, originSystem: "AadGroup", resource: {id: $rid}}, scope: {id: $scopeid, originSystem: "AadGroup"}}')

        graph_post "identityGovernance/entitlementManagement/accessPackages/${ACCESS_PACKAGE_ID}/resourceRoleScopes" "$SCOPE_BODY" >/dev/null
        echo "  Linked group $GROUP_ID (Member role) to access package."
    done
fi

# --- 5. Create default assignment policy ---
echo "Creating assignment policy: $POLICY_NAME"

if [[ "$POLICY_DURATION" -eq 0 ]]; then
    EXPIRATION_JSON='{"endDateTime": null, "duration": null, "type": "noExpiration"}'
else
    EXPIRATION_JSON=$(jq -n --argjson days "$POLICY_DURATION" \
        '{endDateTime: null, duration: ("P" + ($days | tostring) + "D"), type: "afterDuration"}')
fi

POLICY_BODY=$(jq -n \
    --arg name "$POLICY_NAME" \
    --arg pkgid "$ACCESS_PACKAGE_ID" \
    --argjson expiration "$EXPIRATION_JSON" \
    '{
        displayName: $name,
        description: "",
        allowedTargetScope: "notSpecified",
        specificAllowedTargets: [],
        expiration: $expiration,
        requestorSettings: {enableTargetsToSelfAddAccess: false, enableTargetsToSelfUpdateAccess: false, enableTargetsToSelfRemoveAccess: false},
        requestApprovalSettings: {isApprovalRequiredForAdd: false, isApprovalRequiredForUpdate: false},
        accessPackage: {id: $pkgid}
    }')

POLICY_ID=$(graph_post "identityGovernance/entitlementManagement/assignmentPolicies" "$POLICY_BODY" \
    | jq -r '.id')

echo "Created assignment policy: $POLICY_NAME ($POLICY_ID)"

# --- Summary ---
echo ""
echo "Done."
echo "  Catalog:        $CATALOG_NAME ($CATALOG_ID)"
echo "  Access Package: $PACKAGE_NAME ($ACCESS_PACKAGE_ID)"
echo "  Policy:         $POLICY_NAME ($POLICY_ID)"
echo ""
echo "Manage it at: https://entra.microsoft.com/#view/Microsoft_AAD_ERM/DashboardBlade"
