#!/bin/bash

set -euo pipefail

TENANT_ID="${TENANT_ID:-}"
CLIENT_ID="${CLIENT_ID:-}"
CLIENT_SECRET="${CLIENT_SECRET:-}"
SCOPE="${SCOPE:-}"
GRANT_TYPE="${GRANT_TYPE:-client_credentials}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Acquire API access token using client credentials flow"
    echo ""
    echo "Options:"
    echo "  -t, --tenant-id TENANT_ID        Azure AD tenant ID"
    echo "  -c, --client-id CLIENT_ID        Application client ID"
    echo "  -s, --client-secret SECRET       Application client secret"
    echo "  --scope SCOPE                    OAuth scope (required)"
    echo "  --grant-type GRANT_TYPE          Grant type (default: client_credentials)"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  TENANT_ID       Azure AD tenant ID"
    echo "  CLIENT_ID       Application client ID"
    echo "  CLIENT_SECRET   Application client secret"
    echo "  SCOPE           OAuth scope"
    echo "  GRANT_TYPE      Grant type"
    echo ""
    echo "Examples:"
    echo "  # Get token for Microsoft Graph API"
    echo "  $0 -t \$TENANT_ID -c \$CLIENT_ID -s \$CLIENT_SECRET --scope https://graph.microsoft.com/.default"
    echo ""
    echo "  # Get token for custom API"
    echo "  $0 -t \$TENANT_ID -c \$CLIENT_ID -s \$CLIENT_SECRET --scope api://myapi/.default"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        -c|--client-id)
            CLIENT_ID="$2"
            shift 2
            ;;
        -s|--client-secret)
            CLIENT_SECRET="$2"
            shift 2
            ;;
        --scope)
            SCOPE="$2"
            shift 2
            ;;
        --grant-type)
            GRANT_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$TENANT_ID" ]]; then
    echo "Error: TENANT_ID is required"
    usage
fi

if [[ -z "$CLIENT_ID" ]]; then
    echo "Error: CLIENT_ID is required"
    usage
fi

if [[ -z "$CLIENT_SECRET" ]]; then
    echo "Error: CLIENT_SECRET is required"
    usage
fi

if [[ -z "$SCOPE" ]]; then
    echo "Error: SCOPE is required"
    usage
fi

echo "Acquiring API access token..."
echo "Tenant ID: $TENANT_ID"
echo "Client ID: $CLIENT_ID"
echo "Scope: $SCOPE"
echo "Grant Type: $GRANT_TYPE"
echo ""

TOKEN_RESPONSE=$(curl -s -X POST \
    "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=$GRANT_TYPE" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "scope=$SCOPE")

ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

if [[ -n "$ERROR" ]]; then
    echo "Error: $ERROR"
    echo "Description: $(echo "$TOKEN_RESPONSE" | jq -r '.error_description // "No description"')"
    echo ""
    echo "Full response:"
    echo "$TOKEN_RESPONSE" | jq '.'
    exit 1
fi

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
TOKEN_TYPE=$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')
EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')

echo "Token acquired successfully!"
echo "Token Type: $TOKEN_TYPE"
echo "Expires In: $EXPIRES_IN seconds"
echo ""
echo "Access Token:"
echo "$ACCESS_TOKEN"

echo "$ACCESS_TOKEN" > /tmp/api_access_token
echo ""
echo "Token saved to /tmp/api_access_token"

TOKEN_FILE="/tmp/api_access_token_$(echo "$SCOPE" | sed 's/[^a-zA-Z0-9]/_/g')"
echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
echo "Token also saved to $TOKEN_FILE"