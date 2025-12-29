#!/bin/bash

set -euo pipefail

usage() {
    echo "Permission Assignment Helper for Managed Identities"
    echo "=================================================="
    echo ""
    echo "This script helps you choose the right permission assignment tool."
    echo ""
    echo "Usage: $0 [TYPE]"
    echo ""
    echo "Available permission types:"
    echo "  graph        Assign Microsoft Graph permissions (User.Read.All, Mail.Send, etc.)"
    echo "  sharepoint   Assign SharePoint permissions (Sites.ReadWrite.All, Sites.Selected, etc.)"
    echo "  help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 graph        # Launch Microsoft Graph permission assignment"
    echo "  $0 sharepoint   # Launch SharePoint permission assignment"
    echo ""
    echo "Specific tools:"
    echo "  ./assign_graph_permission_to_managed_identity.sh      - Microsoft Graph permissions"
    echo "  ./assign_sharepoint_permission_to_managed_identity.sh - SharePoint permissions"
    echo ""
}

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case $1 in
    graph|Graph|GRAPH)
        echo "🚀 Launching Microsoft Graph permission assignment..."
        echo ""
        shift
        exec "$(dirname "$0")/assign_graph_permission_to_managed_identity.sh" "$@"
        ;;
    sharepoint|SharePoint|SHAREPOINT|sp|SP)
        echo "🚀 Launching SharePoint permission assignment..."
        echo ""
        shift
        exec "$(dirname "$0")/assign_sharepoint_permission_to_managed_identity.sh" "$@"
        ;;
    help|--help|-h)
        usage
        exit 0
        ;;
    *)
        echo "❌ Unknown permission type: $1"
        echo ""
        usage
        exit 1
        ;;
esac