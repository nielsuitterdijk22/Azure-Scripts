#!/bin/bash

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/managed_identity_utils.sh"


usage() {
    echo "Usage: $0 -i IDENTITY_NAME_OR_ID [-f FORMAT] [-h]"
    echo "  -i, --identity IDENTITY    Managed identity name or object ID"
    echo "  -f, --format FORMAT        Output format: table (default), json, tsv"
    echo "  -h, --help                 Show this help"
    echo "Examples:"
    echo "  $0 -i my-function-app"
    echo "  $0 -i 12345678-1234-1234-1234-123456789012 -f json"
}

IDENTITY=""
FORMAT="table"

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--identity) IDENTITY="$2"; shift 2 ;;
        -f|--format) FORMAT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$IDENTITY" ]]; then
    echo "Error: Identity is required"
    usage; exit 1
fi

if [[ ! "$FORMAT" =~ ^(table|json|tsv)$ ]]; then
    echo "Error: Format must be table, json, or tsv"
    exit 1
fi

echo "🔍 Finding managed identity..."
MANAGED_IDENTITY_ID=$(find_managed_identity "$IDENTITY") || exit 1

echo "🔍 Getting Microsoft Graph service principal..."
GRAPH_SP_ID=$(get_service_principal_id "Microsoft Graph") || exit 1

echo "🔍 Getting assigned Graph permissions..."

# Get app role assignments for this managed identity to Microsoft Graph
ASSIGNMENTS=$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${MANAGED_IDENTITY_ID}/appRoleAssignments" --query "value[?resourceId=='${GRAPH_SP_ID}']")

if [[ "$ASSIGNMENTS" == "[]" ]]; then
    echo "❌ No Microsoft Graph permissions found for this managed identity"
    exit 0
fi

# Get the app roles details from Microsoft Graph service principal
echo "🔍 Getting permission details from Microsoft Graph..."
GRAPH_ROLES=$(az ad sp show --id "$GRAPH_SP_ID" --query "appRoles" -o json)

# Process and display the permissions
echo ""
echo "📋 Microsoft Graph Permissions for Managed Identity:"
echo "Identity: $IDENTITY"
echo "Object ID: $MANAGED_IDENTITY_ID"
echo ""

# Create temporary files to avoid command line argument length issues
TEMP_DIR=$(mktemp -d)
ASSIGNMENTS_FILE="$TEMP_DIR/assignments.json"
ROLES_FILE="$TEMP_DIR/roles.json"

# Write data to temporary files
echo "$ASSIGNMENTS" > "$ASSIGNMENTS_FILE"
echo "$GRAPH_ROLES" > "$ROLES_FILE"

case $FORMAT in
    "table")
        echo "Microsoft Graph Permissions:"
        echo "=============================="
        jq -r --slurpfile roles "$ROLES_FILE" '
            .[] |
            .appRoleId as $roleId |
            ($roles[0][] | select(.id == $roleId)) as $role |
            "Permission:    \($role.value)\nDisplay Name:  \($role.displayName)\nDescription:   \($role.description)\n"
        ' "$ASSIGNMENTS_FILE"
        ;;
    "json")
        jq --slurpfile roles "$ROLES_FILE" '
            map(
                .appRoleId as $roleId |
                ($roles[0][] | select(.id == $roleId)) as $role |
                {
                    permission: $role.value,
                    displayName: $role.displayName,
                    description: $role.description,
                    appRoleId: .appRoleId,
                    assignmentId: .id
                }
            )
        ' "$ASSIGNMENTS_FILE"
        ;;
    "tsv")
        echo -e "Permission\tDisplay Name\tDescription\tApp Role ID\tAssignment ID"
        jq -r --slurpfile roles "$ROLES_FILE" '
            .[] |
            .appRoleId as $roleId |
            ($roles[0][] | select(.id == $roleId)) as $role |
            "\($role.value)\t\($role.displayName)\t\($role.description)\t\(.appRoleId)\t\(.id)"
        ' "$ASSIGNMENTS_FILE"
        ;;
esac

# Clean up temporary files
rm -rf "$TEMP_DIR"

PERMISSION_COUNT=$(echo "$ASSIGNMENTS" | jq length)
echo ""
echo "✅ Found $PERMISSION_COUNT Microsoft Graph permission(s)"