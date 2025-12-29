#!/bin/bash

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/managed_identity_utils.sh"

usage() {
    echo "Usage: $0 IDENTITY_NAME_OR_ID PERMISSION"
    echo ""
    echo "Remove Microsoft Graph permissions from managed identities"
    echo ""
    echo "Arguments:"
    echo "  IDENTITY_NAME_OR_ID  Managed identity name or object ID"
    echo "  PERMISSION           Graph permission to remove (e.g., User.Read.All, Mail.Send)"
    echo ""
    echo "Examples:"
    echo "  $0 my-function-app User.Read.All"
    echo "  $0 12345678-1234-1234-1234-123456789012 Mail.Send"
    echo ""
    echo "Common permissions:"
    echo "  User.Read.All, Mail.Send, Directory.Read.All, Group.ReadWrite.All"
}

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

IDENTITY="$1"
PERMISSION="$2"

echo "🔍 Finding managed identity..."
MANAGED_IDENTITY_ID=$(find_managed_identity "$IDENTITY") || exit 1

echo "🔍 Getting Microsoft Graph service principal..."
GRAPH_SP_ID=$(get_service_principal_id "Microsoft Graph") || exit 1

echo "🔍 Getting permission details..."
ROLE_ID=$(get_app_role_id "$GRAPH_SP_ID" "$PERMISSION") || exit 1

echo "🔍 Checking existing assignments..."
if ! check_existing_assignment "$MANAGED_IDENTITY_ID" "$GRAPH_SP_ID" "$ROLE_ID"; then
    echo "✅ Permission '$PERMISSION' is not assigned to managed identity"
    exit 0
fi

echo "🔍 Getting assignment ID..."
ASSIGNMENT_ID=$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${MANAGED_IDENTITY_ID}/appRoleAssignments" --query "value[?resourceId=='${GRAPH_SP_ID}' && appRoleId=='${ROLE_ID}'].id" -o tsv)

if [[ -z "$ASSIGNMENT_ID" ]]; then
    echo "❌ Error: Could not find assignment ID"
    exit 1
fi

echo "🗑️  Removing permission..."
az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${MANAGED_IDENTITY_ID}/appRoleAssignments/${ASSIGNMENT_ID}"

echo "✅ Successfully removed Microsoft Graph permission: $PERMISSION"