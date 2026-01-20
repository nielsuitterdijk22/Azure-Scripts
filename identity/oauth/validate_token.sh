#!/bin/bash

set -euo pipefail

TOKEN="${TOKEN:-}"
TOKEN_FILE="${TOKEN_FILE:-}"
DECODE_ONLY="${DECODE_ONLY:-false}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Validate and decode OAuth access tokens"
    echo ""
    echo "Options:"
    echo "  -t, --token TOKEN            Access token to validate"
    echo "  -f, --token-file FILE        Read token from file"
    echo "  -d, --decode-only            Only decode token, don't validate"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  TOKEN         Access token"
    echo "  TOKEN_FILE    File containing access token"
    echo "  DECODE_ONLY   Set to 'true' to only decode"
    echo ""
    echo "Examples:"
    echo "  # Validate token from command line"
    echo "  $0 -t \$ACCESS_TOKEN"
    echo ""
    echo "  # Validate token from file"
    echo "  $0 -f /tmp/api_access_token"
    echo ""
    echo "  # Only decode token without validation"
    echo "  $0 -t \$ACCESS_TOKEN -d"
    exit 1
}

decode_jwt() {
    local token="$1"

    if [[ ! "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
        echo "Error: Invalid JWT format"
        return 1
    fi

    local header=$(echo "$token" | cut -d. -f1)
    local payload=$(echo "$token" | cut -d. -f2)
    local signature=$(echo "$token" | cut -d. -f3)

    echo "=== JWT Header ==="
    echo "$header" | base64 -d 2>/dev/null | jq '.' || echo "Failed to decode header"
    echo ""

    echo "=== JWT Payload ==="
    echo "$payload" | base64 -d 2>/dev/null | jq '.' || echo "Failed to decode payload"
    echo ""

    if [[ "$DECODE_ONLY" != "true" ]]; then
        local exp=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.exp // empty')
        local iat=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.iat // empty')
        local nbf=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.nbf // empty')

        local current_time=$(date +%s)

        echo "=== Token Validation ==="

        if [[ -n "$exp" ]]; then
            local exp_date=$(date -d "@$exp" 2>/dev/null || echo "Invalid date")
            echo "Expires: $exp_date (epoch: $exp)"
            if [[ "$exp" -gt "$current_time" ]]; then
                echo "Status: ✓ Token is not expired"
            else
                echo "Status: ✗ Token is expired"
            fi
        else
            echo "Expiration: Not found in token"
        fi

        if [[ -n "$iat" ]]; then
            local iat_date=$(date -d "@$iat" 2>/dev/null || echo "Invalid date")
            echo "Issued at: $iat_date (epoch: $iat)"
        fi

        if [[ -n "$nbf" ]]; then
            local nbf_date=$(date -d "@$nbf" 2>/dev/null || echo "Invalid date")
            echo "Not before: $nbf_date (epoch: $nbf)"
            if [[ "$nbf" -le "$current_time" ]]; then
                echo "Status: ✓ Token is valid (not before time passed)"
            else
                echo "Status: ✗ Token not yet valid (not before time not reached)"
            fi
        fi

        echo ""
        echo "Current time: $(date) (epoch: $current_time)"
    fi

    echo ""
    echo "=== Signature ==="
    echo "Signature (base64): $signature"
    echo "Note: Signature verification requires the public key from the issuer"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--token)
            TOKEN="$2"
            shift 2
            ;;
        -f|--token-file)
            TOKEN_FILE="$2"
            shift 2
            ;;
        -d|--decode-only)
            DECODE_ONLY="true"
            shift
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

if [[ -n "$TOKEN_FILE" ]]; then
    if [[ ! -f "$TOKEN_FILE" ]]; then
        echo "Error: Token file '$TOKEN_FILE' not found"
        exit 1
    fi
    TOKEN=$(cat "$TOKEN_FILE" | tr -d '\n\r' | xargs)
fi

if [[ -z "$TOKEN" ]]; then
    echo "Error: No token provided"
    echo "Use -t for token or -f for token file"
    usage
fi

if [[ "$TOKEN" =~ ^Bearer[[:space:]]+ ]]; then
    TOKEN=${TOKEN#Bearer }
    TOKEN=$(echo "$TOKEN" | xargs)
fi

echo "Validating token..."
echo ""

decode_jwt "$TOKEN"

if [[ "$DECODE_ONLY" != "true" ]]; then
    echo ""
    echo "=== Token Health Check ==="

    local issuer=$(echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.iss // empty')
    if [[ -n "$issuer" ]]; then
        echo "Issuer: $issuer"

        if [[ "$issuer" =~ login\.microsoftonline\.com ]]; then
            echo "Token type: Microsoft Azure AD token"

            local tenant_id=$(echo "$issuer" | grep -oE '[0-9a-f-]{36}')
            if [[ -n "$tenant_id" ]]; then
                echo "Tenant ID: $tenant_id"

                echo "Attempting to fetch OIDC configuration..."
                local oidc_config_url="https://login.microsoftonline.com/$tenant_id/.well-known/openid_configuration"

                if curl -s -f "$oidc_config_url" > /dev/null; then
                    echo "✓ OIDC configuration accessible"
                    local jwks_uri=$(curl -s "$oidc_config_url" | jq -r '.jwks_uri // empty')
                    if [[ -n "$jwks_uri" ]]; then
                        echo "JWKS URI: $jwks_uri"
                        if curl -s -f "$jwks_uri" > /dev/null; then
                            echo "✓ JWKS endpoint accessible"
                        else
                            echo "✗ JWKS endpoint not accessible"
                        fi
                    fi
                else
                    echo "✗ OIDC configuration not accessible"
                fi
            fi
        fi
    fi

    local aud=$(echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.aud // empty')
    if [[ -n "$aud" ]]; then
        echo "Audience: $aud"
    fi

    local sub=$(echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.sub // empty')
    if [[ -n "$sub" ]]; then
        echo "Subject: $sub"
    fi

    local scopes=$(echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.scp // .scope // empty')
    if [[ -n "$scopes" ]]; then
        echo "Scopes: $scopes"
    fi
fi