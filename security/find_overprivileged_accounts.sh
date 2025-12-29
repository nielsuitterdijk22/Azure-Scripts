#!/bin/bash
set -euo pipefail

echo "🔍 Finding overprivileged accounts in Azure..."

echo "1. Global Administrators:"
az ad group member list --group "Global Administrator" --query '[].{displayName:displayName, userPrincipalName:userPrincipalName}' -o table

echo "2. Privileged Role Administrators:"
az ad group member list --group "Privileged Role Administrator" --query '[].{displayName:displayName, userPrincipalName:userPrincipalName}' -o table

echo "3. Users with Owner role on subscriptions:"
for sub in $(az account list --query '[].id' -o tsv); do
    echo "Subscription: $sub"
    az role assignment list --scope "/subscriptions/$sub" --role "Owner" --query '[].{principalName:principalName, principalType:principalType}' -o table
done

echo "4. Service Principals with excessive permissions:"
az ad sp list --all --query '[?appRoles[0]].{displayName:displayName, appId:appId}' -o table