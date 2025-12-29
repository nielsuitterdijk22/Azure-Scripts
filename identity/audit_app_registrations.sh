#!/bin/bash
set -euo pipefail

echo "🔍 Auditing App Registrations..."

# Apps with expiring secrets
echo "⏰ Apps with secrets expiring in next 30 days:"
az ad app list --all --query '[].{displayName:displayName, appId:appId, passwordCredentials:passwordCredentials}' -o json | \
jq -r '.[] | select(.passwordCredentials | length > 0) |
       select(.passwordCredentials[] | .endDateTime | fromdateiso8601 < (now + (30 * 24 * 60 * 60))) |
       "\(.displayName) (\(.appId))"'

# Apps with excessive permissions
echo "🔐 Apps with high-risk permissions:"
az ad app list --all --query '[].{displayName:displayName, appId:appId, requiredResourceAccess:requiredResourceAccess}' -o json | \
jq -r '.[] | select(.requiredResourceAccess[]?.resourceAccess[]?.id | contains("1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9") or contains("06da0dbc-49e2-44d2-8312-53f166ab848a")) |
       "\(.displayName) - Has Directory.ReadWrite.All or similar"'

# Unused apps (no sign-ins in 90 days)
echo "💤 Potentially unused apps:"
az ad app list --all --query '[?passwordCredentials[0].endDateTime < `'"$(date -d '90 days ago' -Iseconds)"'`].{displayName:displayName, appId:appId}' -o table

# Apps without owners
echo "👤 Apps without owners:"
az ad app list --all --query '[].{displayName:displayName, appId:appId}' -o tsv | while read -r name appId; do
    owners=$(az ad app owner list --id "$appId" --query '[].displayName' -o tsv)
    if [[ -z "$owners" ]]; then
        echo "$name ($appId)"
    fi
done