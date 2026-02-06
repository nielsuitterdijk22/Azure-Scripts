#!/bin/bash

# Copy all secrets (with metadata) from a source Key Vault to a destination Key Vault,
# across subscriptions. Overwrites existing secrets in the destination.
#
# Metadata copied per secret: value, contentType, tags, expires, notBefore.
# Only enabled secrets are copied. Secret values are never printed.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn()  { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $1"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }

usage() {
    cat <<EOF
Usage: $0 --src-vault <name> --src-sub <sub> --dst-vault <name> --dst-sub <sub> [--dry-run]

Options:
  --src-vault   Source Key Vault name
  --src-sub     Source subscription (name or id)
  --dst-vault   Destination Key Vault name
  --dst-sub     Destination subscription (name or id)
  --dry-run     List what would be copied, do not write
  -h, --help    Show this help
EOF
    exit 1
}

SRC_VAULT=""
SRC_SUB=""
DST_VAULT=""
DST_SUB=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-vault) SRC_VAULT="$2"; shift 2 ;;
        --src-sub)   SRC_SUB="$2";   shift 2 ;;
        --dst-vault) DST_VAULT="$2"; shift 2 ;;
        --dst-sub)   DST_SUB="$2";   shift 2 ;;
        --dry-run)   DRY_RUN=true;   shift ;;
        -h|--help)   usage ;;
        *) error "Unknown argument: $1"; usage ;;
    esac
done

if [[ -z "$SRC_VAULT" || -z "$SRC_SUB" || -z "$DST_VAULT" || -z "$DST_SUB" ]]; then
    error "Missing required arguments"
    usage
fi

az account show > /dev/null 2>&1 || { error "Not logged in. Run 'az login'."; exit 1; }

log "Resolving source subscription..."
SRC_SUB_ID=$(az account show --subscription "$SRC_SUB" --query id -o tsv)
log "Resolving destination subscription..."
DST_SUB_ID=$(az account show --subscription "$DST_SUB" --query id -o tsv)

log "Source:      $SRC_VAULT  (sub: $SRC_SUB_ID)"
log "Destination: $DST_VAULT  (sub: $DST_SUB_ID)"
[[ "$DRY_RUN" == true ]] && warn "DRY RUN — no writes will be made"

log "Listing enabled secrets in source vault..."
SECRETS_JSON=$(az keyvault secret list \
    --vault-name "$SRC_VAULT" \
    --subscription "$SRC_SUB_ID" \
    --query "[?attributes.enabled].{name:name}" \
    -o json)

COUNT=$(echo "$SECRETS_JSON" | jq 'length')
log "Found $COUNT enabled secret(s)"

if [[ "$COUNT" -eq 0 ]]; then
    warn "Nothing to copy"
    exit 0
fi

# Secure temp files: one holds the full JSON (metadata + value), the other holds
# only the raw value for use with `az keyvault secret set --file`. Using --file
# keeps the value out of the process command line (ps-safe). Both are 600 perms
# and scrubbed between iterations + removed on exit.
TMP_PAYLOAD=$(mktemp)
TMP_VALUE=$(mktemp)
chmod 600 "$TMP_PAYLOAD" "$TMP_VALUE"
trap 'shred -u "$TMP_PAYLOAD" "$TMP_VALUE" 2>/dev/null || rm -f "$TMP_PAYLOAD" "$TMP_VALUE"' EXIT

SUCCESS=0
FAILED=0
FAILED_NAMES=()

while IFS= read -r name; do
    echo ""
    log "→ $name"

    # Pull full secret (value + metadata) into temp file; never echo to stdout
    if ! az keyvault secret show \
            --vault-name "$SRC_VAULT" \
            --name "$name" \
            --subscription "$SRC_SUB_ID" \
            -o json > "$TMP_PAYLOAD" 2>/dev/null; then
        error "  failed to read from source"
        FAILED=$((FAILED+1))
        FAILED_NAMES+=("$name")
        continue
    fi

    CONTENT_TYPE=$(jq -r '.contentType // empty' "$TMP_PAYLOAD")
    EXPIRES=$(jq -r '.attributes.expires // empty' "$TMP_PAYLOAD")
    NOT_BEFORE=$(jq -r '.attributes.notBefore // empty' "$TMP_PAYLOAD")
    TAGS=$(jq -r '.tags // {} | to_entries | map("\(.key)=\(.value)") | join(" ")' "$TMP_PAYLOAD")

    if [[ "$DRY_RUN" == true ]]; then
        log "  would copy (contentType=${CONTENT_TYPE:-none}, tags=${TAGS:-none}, expires=${EXPIRES:-none})"
        SUCCESS=$((SUCCESS+1))
        : > "$TMP_PAYLOAD"
        continue
    fi

    # Write raw value to its own file (no trailing newline) so --file uploads exactly the original bytes.
    jq -j '.value' "$TMP_PAYLOAD" > "$TMP_VALUE"

    ERR_FILE=$(mktemp); chmod 600 "$ERR_FILE"
    # shellcheck disable=SC2086 # intentional word-splitting on $TAGS
    if ! az keyvault secret set \
            --vault-name "$DST_VAULT" \
            --subscription "$DST_SUB_ID" \
            --name "$name" \
            --file "$TMP_VALUE" \
            ${CONTENT_TYPE:+--content-type "$CONTENT_TYPE"} \
            ${EXPIRES:+--expires "$EXPIRES"} \
            ${NOT_BEFORE:+--not-before "$NOT_BEFORE"} \
            ${TAGS:+--tags $TAGS} \
            -o none 2>"$ERR_FILE"; then
        error "  failed to write to destination: $(head -1 "$ERR_FILE")"
        rm -f "$ERR_FILE"
        FAILED=$((FAILED+1))
        FAILED_NAMES+=("$name")
        : > "$TMP_PAYLOAD"; : > "$TMP_VALUE"
        continue
    fi
    rm -f "$ERR_FILE"

    log "  ✓ copied"
    SUCCESS=$((SUCCESS+1))

    # Scrub temp files between iterations so the value doesn't linger on disk
    : > "$TMP_PAYLOAD"
    : > "$TMP_VALUE"
done < <(echo "$SECRETS_JSON" | jq -r '.[].name')

echo ""
echo "======================================"
log "Summary"
echo "======================================"
log "Total:      $COUNT"
log "Successful: $SUCCESS"
if [[ "$FAILED" -gt 0 ]]; then
    warn "Failed:     $FAILED"
    for n in "${FAILED_NAMES[@]}"; do warn "  - $n"; done
    exit 1
fi
