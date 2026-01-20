#!/bin/bash

set -euo pipefail

TENANT_ID="${TENANT_ID:-}"
CLIENT_ID="${CLIENT_ID:-}"
SCOPE="${SCOPE:-https://graph.microsoft.com/.default}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Acquire SSO access token using device code flow"
    echo ""
    echo "Options:"
    echo "  -t, --tenant-id TENANT_ID    Azure AD tenant ID"
    echo "  -c, --client-id CLIENT_ID    Application client ID"
    echo "  -s, --scope SCOPE            OAuth scope (default: https://graph.microsoft.com/.default)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  TENANT_ID    Azure AD tenant ID"
    echo "  CLIENT_ID    Application client ID"
    echo "  SCOPE        OAuth scope"
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
        -s|--scope)
            SCOPE="$2"
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

echo "Initiating device code flow..."

DEVICE_CODE_RESPONSE=$(curl -s -X POST \
    "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/devicecode" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID" \
    -d "scope=$SCOPE")

DEVICE_CODE=$(echo "$DEVICE_CODE_RESPONSE" | jq -r '.device_code')
USER_CODE=$(echo "$DEVICE_CODE_RESPONSE" | jq -r '.user_code')
VERIFICATION_URI=$(echo "$DEVICE_CODE_RESPONSE" | jq -r '.verification_uri')
EXPIRES_IN=$(echo "$DEVICE_CODE_RESPONSE" | jq -r '.expires_in')
INTERVAL=$(echo "$DEVICE_CODE_RESPONSE" | jq -r '.interval')

if [[ "$DEVICE_CODE" == "null" ]]; then
    echo "Error: Failed to get device code"
    echo "$DEVICE_CODE_RESPONSE" | jq '.'
    exit 1
fi

echo "Go to: $VERIFICATION_URI"
echo "Enter code: $USER_CODE"
echo "Expires in: $EXPIRES_IN seconds"
echo ""
echo "Waiting for authentication..."

TIMEOUT=$(($(date +%s) + EXPIRES_IN))

while [[ $(date +%s) -lt $TIMEOUT ]]; do
    sleep "$INTERVAL"

    TOKEN_RESPONSE=$(curl -s -X POST \
        "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
        -d "client_id=$CLIENT_ID" \
        -d "device_code=$DEVICE_CODE")

    ERROR=$(echo "$TOKEN_RESPONSE" | jq -r '.error // empty')

    if [[ -z "$ERROR" ]]; then
        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
        EXPIRES_IN_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')

        echo "Authentication successful!"
        echo "Access token: $ACCESS_TOKEN"
        echo "Expires in: $EXPIRES_IN_TOKEN seconds"

        echo "$ACCESS_TOKEN" > /tmp/sso_access_token
        echo "Token saved to /tmp/sso_access_token"
        exit 0
    elif [[ "$ERROR" == "authorization_pending" ]]; then
        echo -n "."
        continue
    elif [[ "$ERROR" == "slow_down" ]]; then
        INTERVAL=$((INTERVAL + 5))
        continue
    else
        echo ""
        echo "Error: $ERROR"
        echo "$TOKEN_RESPONSE" | jq '.'
        exit 1
    fi
done

echo ""
echo "Timeout: Device code expired"
exit 1