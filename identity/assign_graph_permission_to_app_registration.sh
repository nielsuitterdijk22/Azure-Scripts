#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 -a APP_NAME_OR_ID -r PERMISSION [-h]"
    echo "  -a, --app APP_NAME_OR_ID   App registration name or application ID"
    echo "  -r, --role PERMISSION      Graph permission (e.g., User.Read.All, Mail.Send)"
    echo "  -h, --help                 Show this help"
    echo "Examples:"
    echo "  $0 -a my-app -r User.Read.All"
    echo "  $0 -a 12345678-1234-1234-1234-123456789012 -r Mail.Send"
    echo "Common permissions:"
    echo "  User.Read.All, Mail.Send, Directory.Read.All, Group.ReadWrite.All"
}

find_app_registration() {
    local app_input="$1"

    # Check if it's already a GUID
    if [[ $app_input =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        # Verify the app exists
        if az ad app show --id "$app_input" &>/dev/null; then
            echo "$app_input"
            return 0
        else
            echo "Error: App registration with ID '$app_input' not found" >&2
            return 1
        fi
    else
        # Search by display name
        local app_id
        app_id=$(az ad app list --display-name "$app_input" --query "[0].appId" -o tsv)

        if [[ -z "$app_id" || "$app_id" == "null" ]]; then
            echo "Error: App registration '$app_input' not found" >&2
            return 1
        fi

        echo "$app_id"
    fi
}

get_service_principal_id() {
    local service_name="$1"
    local sp_id
    sp_id=$(az ad sp list --display-name "$service_name" --query "[0].id" -o tsv)

    if [[ -z "$sp_id" || "$sp_id" == "null" ]]; then
        echo "Error: Service principal '$service_name' not found" >&2
        return 1
    fi

    echo "$sp_id"
}

get_app_role_id() {
    local service_principal_id="$1"
    local permission="$2"

    local role_id
    role_id=$(az ad sp show --id "$service_principal_id" --query "appRoles[?value=='$permission'].id" -o tsv)

    if [[ -z "$role_id" || "$role_id" == "null" ]]; then
        echo "Error: Permission '$permission' not found in Microsoft Graph" >&2
        return 1
    fi

    echo "$role_id"
}

get_app_service_principal() {
    local app_id="$1"
    local sp_id
    sp_id=$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" -o tsv)

    if [[ -z "$sp_id" || "$sp_id" == "null" ]]; then
        echo "Error: Service principal for app '$app_id' not found. App may not have a service principal created." >&2
        return 1
    fi

    echo "$sp_id"
}

check_existing_assignment() {
    local principal_id="$1"
    local resource_id="$2"
    local role_id="$3"

    local existing
    existing=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$principal_id/appRoleAssignments" \
        --query "value[?resourceId=='$resource_id' && appRoleId=='$role_id']" -o tsv)

    [[ -n "$existing" ]]
}

assign_app_role() {
    local principal_id="$1"
    local resource_id="$2"
    local role_id="$3"

    local body
    body=$(jq -n --arg principalId "$principal_id" --arg resourceId "$resource_id" --arg appRoleId "$role_id" '{
        principalId: $principalId,
        resourceId: $resourceId,
        appRoleId: $appRoleId
    }')

    az rest --method POST \
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$principal_id/appRoleAssignments" \
        --body "$body" \
        --headers "Content-Type=application/json" >/dev/null

    if [[ $? -eq 0 ]]; then
        echo "Permission assigned successfully"
    else
        echo "Error: Failed to assign permission" >&2
        return 1
    fi
}

APP=""
PERMISSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app) APP="$2"; shift 2 ;;
        -r|--role) PERMISSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$APP" || -z "$PERMISSION" ]]; then
    echo "Error: App and permission are required"
    usage; exit 1
fi

echo "🔍 Finding app registration..."
APP_ID=$(find_app_registration "$APP") || exit 1

echo "🔍 Getting app service principal..."
APP_SP_ID=$(get_app_service_principal "$APP_ID") || exit 1

echo "🔍 Getting Microsoft Graph service principal..."
GRAPH_SP_ID=$(get_service_principal_id "Microsoft Graph") || exit 1

echo "🔍 Getting permission details..."
ROLE_ID=$(get_app_role_id "$GRAPH_SP_ID" "$PERMISSION") || exit 1

echo "🔍 Checking existing assignments..."
if check_existing_assignment "$APP_SP_ID" "$GRAPH_SP_ID" "$ROLE_ID"; then
    echo "✅ Permission '$PERMISSION' already assigned"
    exit 0
fi

echo "🚀 Assigning permission..."
assign_app_role "$APP_SP_ID" "$GRAPH_SP_ID" "$ROLE_ID"

echo "✅ Successfully assigned Microsoft Graph permission: $PERMISSION"