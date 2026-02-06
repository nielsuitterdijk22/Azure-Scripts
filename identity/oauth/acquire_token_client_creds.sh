#!/bin/bash

set -euo pipefail

# Default values
TENANT_ID=16b5d29f-ebed-43c7-8312-6bf69ffe5e3b
API_CLIENT_ID=4c52751f-dc4f-40bd-9785-32451d90aa95
CLIENT_SECRET=""
SCOPE=api://4c52751f-dc4f-40bd-9785-32451d90aa95/.default

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Acquire API access token using OAuth Client Credentials flow"
    echo ""
    echo "Options:"
    echo "  -t, --tenant-id TENANT_ID        Azure AD tenant ID (default: $TENANT_ID)"
    echo "  -c, --client-id CLIENT_ID        Application client ID (default: $API_CLIENT_ID)"
    echo "  -s, --client-secret SECRET       Application client secret (required)"
    echo "  --scope SCOPE                    OAuth scope (default: $SCOPE)"
    echo "  -h, --help                       Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tenant-id) TENANT_ID="$2"; shift 2 ;;
        -c|--client-id) API_CLIENT_ID="$2"; shift 2 ;;
        -s|--client-secret) CLIENT_SECRET="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validation
[[ -z "$TENANT_ID" ]] && { echo "Error: TENANT_ID required"; usage; }
[[ -z "$API_CLIENT_ID" ]] && { echo "Error: CLIENT_ID required"; usage; }
[[ -z "$CLIENT_SECRET" ]] && { echo "Error: CLIENT_SECRET required for client credentials flow"; usage; }
[[ -z "$SCOPE" ]] && { echo "Error: SCOPE required"; usage; }

echo "=== OAuth Client Credentials Flow ==="
echo "Tenant: $TENANT_ID"
echo "Client: $API_CLIENT_ID"
echo "Scope: $SCOPE"
echo ""

echo "🔄 Acquiring access token with client credentials..."

# Request token
TOKEN_RESPONSE=$(curl -s -X POST \
    "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=$API_CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "scope=$SCOPE")

# Check for errors
ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
if [[ -n "$ERROR" ]]; then
    echo "❌ Error: $ERROR"
    echo "Description: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // "No description"')"
    echo ""
    echo "Full response:"
    echo "$TOKEN_RESPONSE" | jq '.'
    exit 1
fi

# Extract token
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')

echo "✅ Token acquired successfully!"
echo "Token Type: $TOKEN_TYPE"
echo "Expires in: $EXPIRES_IN seconds"
echo ""
echo "Access Token:"
echo "$ACCESS_TOKEN"
echo ""

# Save token
TOKEN_FILE="/tmp/api_token_$(echo "$SCOPE" | sed 's/[^a-zA-Z0-9]/_/g')"
echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
echo "💾 Saved to: $TOKEN_FILE"

# Decode and show claims
echo ""
echo "=== Token Claims ==="
PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.')
echo "$PAYLOAD" | jq '{aud, scp, roles, appid, oid, sub}' 2>/dev/null || echo "Could not decode claims"