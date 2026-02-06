#!/bin/bash

# Shared utilities for managed identity operations

# Find managed identity object ID by name or return provided object ID
find_managed_identity() {
    local name_or_id="$1"

    # If it looks like a GUID, try to validate it directly
    if [[ "$name_or_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "🔍 Validating object ID: $name_or_id" >&2
        local sp_type=$(az ad sp show --id "$name_or_id" --query "servicePrincipalType" -o tsv 2>&1)
        if [[ $? -ne 0 ]]; then
            if echo "$sp_type" | grep -q "AADSTS70043\|refresh token has expired\|Interactive authentication is needed"; then
                echo "Error: Authentication required" >&2
                echo "" >&2
                echo "💡 Please run:" >&2
                echo "   az login --scope https://graph.microsoft.com//.default" >&2
                echo "" >&2
            else
                echo "Error: Object ID '$name_or_id' not found" >&2
            fi
            return 1
        fi
        if echo "$sp_type" | grep -q "ManagedIdentity"; then
            echo "$name_or_id"
            return 0
        else
            echo "Error: Object ID '$name_or_id' is not a managed identity" >&2
            return 1
        fi
    fi

    echo "🔍 Searching for managed identity: $name_or_id" >&2

    # Use filter-based search first (most efficient, avoids truncation)
    local object_id=$(az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity' and displayName eq '$name_or_id'" --query "[0].id" -o tsv 2>&1)

    # Check for authentication errors
    if [[ $? -ne 0 ]] && echo "$object_id" | grep -q "AADSTS70043\|refresh token has expired\|Interactive authentication is needed"; then
        echo "Error: Authentication required" >&2
        echo "" >&2
        echo "💡 Please run:" >&2
        echo "   az login --scope https://graph.microsoft.com//.default" >&2
        echo "" >&2
        return 1
    fi

    # If exact match not found, try startswith filter for partial matches
    if [[ -z "$object_id" || "$object_id" == "null" ]]; then
        object_id=$(az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity' and startswith(displayName,'$name_or_id')" --query "[?displayName=='$name_or_id'].id" -o tsv 2>&1)
        if [[ $? -ne 0 ]] && echo "$object_id" | grep -q "AADSTS70043\|refresh token has expired\|Interactive authentication is needed"; then
            echo "Error: Authentication required" >&2
            echo "" >&2
            echo "💡 Please run:" >&2
            echo "   az login --scope https://graph.microsoft.com//.default" >&2
            echo "" >&2
            return 1
        fi
    fi

    # If still not found, try contains filter for broader matching
    if [[ -z "$object_id" || "$object_id" == "null" ]]; then
        echo "🔍 Trying broader search..." >&2
        object_id=$(az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity'" --query "[?contains(displayName, '$name_or_id')].{id:id,name:displayName}" -o json 2>&1 | jq -r '.[0].id // empty')
    fi

    # Fallback: search system-assigned managed identities by alternative names
    if [[ -z "$object_id" || "$object_id" == "null" ]]; then
        echo "🔍 Searching system-assigned managed identities..." >&2
        object_id=$(az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity'" --query "[?alternativeNames != null && length(alternativeNames) > \`0\`] | [?contains(join('', alternativeNames), '$name_or_id')].id" -o tsv 2>&1)
    fi

    if [[ -z "$object_id" || "$object_id" == "null" ]]; then
        echo "Error: Managed identity '$name_or_id' not found" >&2
        echo "Available managed identities (showing first 10):" >&2
        local list_result=$(az ad sp list --filter "servicePrincipalType eq 'ManagedIdentity'" --query "[0:9].[displayName,id]" -o table 2>&1)
        if echo "$list_result" | grep -q "AADSTS70043\|refresh token has expired\|Interactive authentication is needed"; then
            echo "Could not list available identities (authentication required)" >&2
            echo "" >&2
            echo "💡 Please run:" >&2
            echo "   az login --scope https://graph.microsoft.com//.default" >&2
        else
            echo "$list_result" >&2
        fi
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