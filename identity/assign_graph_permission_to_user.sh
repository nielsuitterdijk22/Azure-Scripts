#!/bin/bash


set -euo pipefail

usage() {
    echo "Usage: $0 -u USER_EMAIL -r ROLE [-h]"
    echo "  -u, --user USER_EMAIL     User email address"
    echo "  -r, --role ROLE          Graph permission role (e.g., Mail.Send, User.Read.All)"
    echo "  -h, --help               Show this help"
    echo "Examples:"
    echo "  $0 -u user@domain.com -r Mail.Send"
    echo "Requires Privileged Role Administrator"
}

USER_EMAIL=""
ROLE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user) USER_EMAIL="$2"; shift 2 ;;
        -r|--role) ROLE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$USER_EMAIL" || -z "$ROLE" ]]; then
    echo "Error: User email and role are required"
    usage; exit 1
fi

echo "Getting user ID for: $USER_EMAIL"
userId=$(az ad user show --id "$USER_EMAIL" --query 'id' -o tsv)

echo "Getting Microsoft Graph service principal..."
graphSpId=$(az ad sp list --display-name "Microsoft Graph" --query "[0].id" -o tsv)

echo "Getting app role ID for: $ROLE"
appRoleId=$(az ad sp show --id "$graphSpId" --query "appRoles[?value=='$ROLE'].id" -o tsv)

if [[ -z "$appRoleId" ]]; then
    echo "Error: Role '$ROLE' not found. Available roles:"
    az ad sp show --id "$graphSpId" --query "appRoles[].{value:value, displayName:displayName}" -o table
    exit 1
fi

echo "Checking existing assignments..."
existingAssignment=$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/users/$userId/appRoleAssignments" --query "value[?resourceId=='$graphSpId' && appRoleId=='$appRoleId'].id" -o tsv)

if [[ -n "$existingAssignment" ]]; then
    echo "Role '$ROLE' already assigned to user '$USER_EMAIL'"
else
    echo "Assigning role '$ROLE' to user '$USER_EMAIL'..."
    az rest --method POST --uri "https://graph.microsoft.com/v1.0/users/$userId/appRoleAssignments" --headers 'Content-Type=application/json' --body "{ 'principalId': '$userId', 'resourceId': '$graphSpId', 'appRoleId': '$appRoleId' }"
    echo "Role assignment completed!"
fi