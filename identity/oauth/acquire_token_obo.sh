#!/bin/bash

set -euo pipefail

# Default values
TENANT_ID=16b5d29f-ebed-43c7-8312-6bf69ffe5e3b
SSO_CLIENT_ID=3a806e97-a0ca-4caf-9693-89d793393fbf
SCOPE=api://4c52751f-dc4f-40bd-9785-32451d90aa95/Parties.Write
ASSERTION=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Acquire API access token using OAuth On-Behalf-Of (OBO) flow"
    echo ""
    echo "Options:"
    echo "  -t, --tenant-id TENANT_ID        Azure AD tenant ID (default: $TENANT_ID)"
    echo "  -c, --client-id CLIENT_ID        Application client ID (default: $SSO_CLIENT_ID)"
    echo "  -s, --client-secret SECRET       Application client secret"
    echo "  --scope SCOPE                    OAuth scope (default: $SCOPE)"
    echo "  --assertion TOKEN                User access token (required)"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Description:"
    echo "  The OBO flow allows a service to call another API on behalf of the user."
    echo "  You need a user access token (assertion) obtained from a previous authentication."
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tenant-id) TENANT_ID="$2"; shift 2 ;;
        -c|--client-id) SSO_CLIENT_ID="$2"; shift 2 ;;
        -s|--client-secret) SSO_CLIENT_SECRET="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        --assertion) ASSERTION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validation
[[ -z "$TENANT_ID" ]] && { echo "Error: TENANT_ID required"; usage; }
[[ -z "$SSO_CLIENT_ID" ]] && { echo "Error: CLIENT_ID required"; usage; }
[[ -z "$SSO_CLIENT_SECRET" ]] && { echo "Error: CLIENT_SECRET required for OBO flow"; usage; }
[[ -z "$SCOPE" ]] && { echo "Error: SCOPE required"; usage; }
[[ -z "$ASSERTION" ]] && { echo "Error: --assertion (user token) required for OBO flow"; usage; }

echo "=== OAuth On-Behalf-Of (OBO) Flow ==="
echo "Tenant: $TENANT_ID"
echo "Client: $SSO_CLIENT_ID"
echo "Scope: $SCOPE"
echo ""

# Validate assertion token (basic check)
if [[ ! "$ASSERTION" =~ ^eyJ ]]; then
    echo "⚠️  Warning: Assertion doesn't look like a JWT token (should start with 'eyJ')"
fi

echo "🔄 Exchanging user token for API access token..."

# Request token using OBO flow
TOKEN_RESPONSE=$(curl -s -X POST \
    "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
    -d "client_id=$SSO_CLIENT_ID" \
    -d "client_secret=$SSO_CLIENT_SECRET" \
    -d "assertion=$ASSERTION" \
    -d "scope=$SCOPE" \
    -d "requested_token_use=on_behalf_of")

# Check for errors
ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
if [[ -n "$ERROR" ]]; then
    echo "❌ Error: $ERROR"
    echo "Description: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // "No description"')"
    echo ""
    echo "Common OBO issues:"
    echo "  - User token expired or invalid"
    echo "  - Application not configured for OBO"
    echo "  - Insufficient permissions in user token"
    echo "  - Target API doesn't trust the application"
    echo ""
    echo "Full response:"
    echo "$TOKEN_RESPONSE" | jq '.'
    exit 1
fi

# Extract token
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')

echo "✅ OBO token acquired successfully!"
echo "Token Type: $TOKEN_TYPE"
echo "Expires in: $EXPIRES_IN seconds"
echo ""
echo "Access Token:"
echo "$ACCESS_TOKEN"
echo ""

# Save token
TOKEN_FILE="/tmp/api_token_obo_$(echo "$SCOPE" | sed 's/[^a-zA-Z0-9]/_/g')"
echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
echo "💾 Saved to: $TOKEN_FILE"

# Decode and show claims
echo ""
echo "=== Token Claims ==="
PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.')
echo "$PAYLOAD" | jq '{aud, scp, roles, oid, upn, appid, actort}' 2>/dev/null || echo "Could not decode claims"

# Show original user info from assertion
echo ""
echo "=== Original User Token Claims ==="
ASSERTION_PAYLOAD=$(echo "$ASSERTION" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.')
echo "$ASSERTION_PAYLOAD" | jq '{aud, scp, oid, upn, appid, name}' 2>/dev/null || echo "Could not decode assertion claims"