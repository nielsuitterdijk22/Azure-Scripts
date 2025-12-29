#!/bin/bash

# Shared utilities for managed identity operations

# Find managed identity object ID by name or return provided object ID
find_managed_identity() {
    local name_or_id="$1"

    # If it looks like a GUID, assume it's an object ID
    if [[ "$name_or_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        if az ad sp show --id "$name_or_id" &>/dev/null; then
            echo "$name_or_id"
            return 0
        else
            echo "Error: Object ID '$name_or_id' not found" >&2
            return 1
        fi
    fi

    # Try user-assigned managed identity first
    local object_id=$(az ad sp list --query "[?displayName=='$name_or_id'].id" -o tsv)

    # If not found, try system-assigned patterns
    if [[ -z "$object_id" ]]; then
        object_id=$(az ad sp list --query "[?contains(alternativeNames, '$name_or_id')].id" -o tsv)
    fi

    if [[ -z "$object_id" ]]; then
        object_id=$(az ad sp list --query "[?starts_with(servicePrincipalNames[0], 'https://identity.azure.net/') && contains(servicePrincipalNames[0], '$name_or_id')].id" -o tsv)
    fi

    if [[ -z "$object_id" ]]; then
        echo "Error: Managed identity '$name_or_id' not found" >&2
        echo "Tip: Use object ID directly or check the exact resource name" >&2
        return 1
    fi

    echo "$object_id"
}

# Get service principal ID by display name
get_service_principal_id() {
    local display_name="$1"
    local sp_id=$(az ad sp list --query '[].[id]' --filter "displayName eq '$display_name'" -o tsv)

    if [[ -z "$sp_id" ]]; then
        echo "Error: Service principal '$display_name' not found" >&2
        return 1
    fi

    echo "$sp_id"
}

# Get app role ID from service principal
get_app_role_id() {
    local service_principal_id="$1"
    local role_name="$2"

    local role_id=$(az ad sp show --id "$service_principal_id" --query "appRoles[?value=='$role_name'].id" -o tsv)

    if [[ -z "$role_id" ]]; then
        echo "Error: Role '$role_name' not found" >&2
        echo "Available roles:" >&2
        az ad sp show --id "$service_principal_id" --query "appRoles[].{value:value, displayName:displayName}" -o table >&2
        return 1
    fi

    echo "$role_id"
}

# Check if role is already assigned
check_existing_assignment() {
    local managed_identity_id="$1"
    local resource_sp_id="$2"
    local app_role_id="$3"

    local existing=$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${managed_identity_id}/appRoleAssignments" --query "value[?resourceId=='${resource_sp_id}' && appRoleId=='${app_role_id}'].id" -o tsv)

    if [[ -n "$existing" ]]; then
        return 0  # Assignment exists
    else
        return 1  # No assignment
    fi
}

# Assign app role
assign_app_role() {
    local managed_identity_id="$1"
    local resource_sp_id="$2"
    local app_role_id="$3"

    az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${managed_identity_id}/appRoleAssignments" \
        --headers 'Content-Type=application/json' \
        --body "{ 'principalId': '${managed_identity_id}', 'resourceId': '${resource_sp_id}', 'appRoleId': '${app_role_id}' }" \
        >/dev/null
}