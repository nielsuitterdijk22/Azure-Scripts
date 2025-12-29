#!/bin/bash

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/managed_identity_utils.sh"

usage() {
    echo "Usage: $0 -i IDENTITY_NAME_OR_ID -r PERMISSION [-h]"
    echo "  -i, --identity IDENTITY    Managed identity name or object ID"
    echo "  -r, --role PERMISSION      Graph permission (e.g., User.Read.All, Mail.Send)"
    echo "  -h, --help                 Show this help"
    echo "Examples:"
    echo "  $0 -i my-function-app -r User.Read.All"
    echo "  $0 -i 12345678-1234-1234-1234-123456789012 -r Mail.Send"
    echo "Common permissions:"
    echo "  User.Read.All, Mail.Send, Directory.Read.All, Group.ReadWrite.All"
}

IDENTITY=""
PERMISSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--identity) IDENTITY="$2"; shift 2 ;;
        -r|--role) PERMISSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$IDENTITY" || -z "$PERMISSION" ]]; then
    echo "Error: Identity and permission are required"
    usage; exit 1
fi

echo "🔍 Finding managed identity..."
MANAGED_IDENTITY_ID=$(find_managed_identity "$IDENTITY") || exit 1

echo "🔍 Getting Microsoft Graph service principal..."
GRAPH_SP_ID=$(get_service_principal_id "Microsoft Graph") || exit 1

echo "🔍 Getting permission details..."
ROLE_ID=$(get_app_role_id "$GRAPH_SP_ID" "$PERMISSION") || exit 1

echo "🔍 Checking existing assignments..."
if check_existing_assignment "$MANAGED_IDENTITY_ID" "$GRAPH_SP_ID" "$ROLE_ID"; then
    echo "✅ Permission '$PERMISSION' already assigned"
    exit 0
fi

echo "🚀 Assigning permission..."
assign_app_role "$MANAGED_IDENTITY_ID" "$GRAPH_SP_ID" "$ROLE_ID"

echo "✅ Successfully assigned Microsoft Graph permission: $PERMISSION"