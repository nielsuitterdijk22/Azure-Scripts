#!/bin/bash

set -euo pipefail

# Default values
TENANT_ID=16b5d29f-ebed-43c7-8312-6bf69ffe5e3b
SSO_CLIENT_ID=3a806e97-a0ca-4caf-9693-89d793393fbf
# SCOPE="https://api-d.das.nl/ api://partiesapi/4c52751f-dc4f-40bd-9785-32451d90aa95 offline_access"
SCOPE="https://api-d.das.nl/.default offline_access"
REDIRECT_URI="https://das-dev.appiancloud.com/suite/oidc/callback"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Acquire API access token using OAuth Authorization Code flow"
    echo ""
    echo "Options:"
    echo "  -t, --tenant-id TENANT_ID        Azure AD tenant ID (default: $TENANT_ID)"
    echo "  -c, --client-id CLIENT_ID        Application client ID (default: $SSO_CLIENT_ID)"
    echo "  -s, --client-secret SECRET       Application client secret"
    echo "  --scope SCOPE                    OAuth scope (default: $SCOPE)"
    echo "  --redirect-uri URI               Redirect URI (default: $REDIRECT_URI)"
    echo "  -h, --help                       Show this help message"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tenant-id) TENANT_ID="$2"; shift 2 ;;
        -c|--client-id) SSO_CLIENT_ID="$2"; shift 2 ;;
        -s|--client-secret) SSO_CLIENT_SECRET="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        --redirect-uri) REDIRECT_URI="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validation
[[ -z "$TENANT_ID" ]] && { echo "Error: TENANT_ID required"; usage; }
[[ -z "$SSO_CLIENT_ID" ]] && { echo "Error: CLIENT_ID required"; usage; }
[[ -z "$SSO_CLIENT_SECRET" ]] && { echo "Error: CLIENT_SECRET required"; usage; }
[[ -z "$SCOPE" ]] && { echo "Error: SCOPE required"; usage; }
[[ -z "$REDIRECT_URI" ]] && { echo "Error: REDIRECT_URI required"; usage; }

echo "=== OAuth Authorization Code Flow ==="
echo "Tenant: $TENANT_ID"
echo "Client: $SSO_CLIENT_ID"
echo "Scope: $SCOPE"
echo "Redirect URI: $REDIRECT_URI"
echo ""

# Generate authorization URL
AUTH_URL="https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/authorize?client_id=$SSO_CLIENT_ID&response_type=code&redirect_uri=$(echo "$REDIRECT_URI" | sed 's/+/%2B/g; s/:/%3A/g; s/\//%2F/g')&scope=$(echo "$SCOPE" | sed 's/ /%20/g')&response_mode=query"

echo "📋 STEP 1: Open this URL in your browser:"
echo ""
echo "$AUTH_URL"
echo ""
echo "📋 STEP 2: After authentication, you'll be redirected to:"
echo "$REDIRECT_URI?code=AUTHORIZATION_CODE&..."
echo ""
echo "📋 STEP 3: Copy the authorization code from the URL parameter 'code'"
echo ""

# Interactive input for authorization code
read -p "🔑 Enter the authorization code: " AUTH_CODE

[[ -z "$AUTH_CODE" ]] && { echo "Error: Authorization code cannot be empty"; exit 1; }

echo ""
echo "🔄 Exchanging authorization code for access token..."

# Exchange code for token
TOKEN_RESPONSE=$(curl -s -X POST \
    "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=$SSO_CLIENT_ID" \
    -d "client_secret=$SSO_CLIENT_SECRET" \
    -d "code=$AUTH_CODE" \
    -d "redirect_uri=$REDIRECT_URI" \
    -d "scope=$SCOPE")

# Check for errors
ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')
echo "$TOKEN_RESPONSE" | jq '.'
if [[ -n "$ERROR" ]]; then
    echo "❌ Error: $ERROR"
    echo "Description: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // "No description"')"
    echo ""
    echo "Full response:"
    exit 1
fi

# Extract token
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // "none"')

echo "✅ Token acquired successfully!"
echo "Expires in: $EXPIRES_IN seconds"
[[ "$REFRESH_TOKEN" != "none" ]] && echo "Refresh token: Available"
echo ""
echo "Access Token:"
echo "$ACCESS_TOKEN"
echo ""

# Save token
TOKEN_FILE="/tmp/api_token_$(echo "$SCOPE" | sed 's/[^a-zA-Z0-9]/_/g')"
echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
echo "💾 Saved to: $TOKEN_FILE"


# Try use token
# echo 'curl https://func-easyauth-s-we-001-c9c7bsgaghdhbwb5.westeurope-01.azurewebsites.net/ -H "Authorization: Bearer $ACCESS_TOKEN"'
# curl https://func-easyauth-s-we-001-c9c7bsgaghdhbwb5.westeurope-01.azurewebsites.net/ -H "Authorization: Bearer $ACCESS_TOKEN" -f


# Decode and show claims
echo ""
echo "=== Token Claims ==="
PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d'.' -f2 | base64 -d 2>/dev/null | jq '.')
echo "$PAYLOAD" | jq '{aud, scp, roles, oid, upn, appid}' 2>/dev/null || echo "Could not decode claims"
