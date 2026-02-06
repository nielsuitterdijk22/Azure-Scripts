#!/usr/bin/env bash
set -euo pipefail

#===============================================================================
# transfer-ea-subscriptions.sh
#
# Transfers Azure EA subscriptions from one enrollment account to another
# within the same billing account, using `az rest`.
#
# Usage:
#   ./transfer-ea-subscriptions.sh \
#     --billing-account <billing-account-name> \
#     --source-account <source-enrollment-account-name> \
#     --dest-account <dest-enrollment-account-name> \
#     [--dry-run] \
#     [--subscription-ids sub1,sub2,...] \
#     [--api-version 2024-04-01]
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Sufficient EA billing permissions (Department Admin / EA Admin)
#
# IMPORTANT:
#   The transfer API used here is reverse-engineered from the Azure portal.
#   Always test with --dry-run first and verify in the portal afterwards.
#===============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="transfer-$(date +%Y%m%d-%H%M%S).log"
readonly BILLING_API_BASE="https://management.azure.com/providers/Microsoft.Billing"

# Defaults
API_VERSION="2024-04-01"
DRY_RUN=false
BILLING_ACCOUNT=""
SOURCE_ACCOUNT=""
DEST_ACCOUNT=""
SUBSCRIPTION_IDS=""

#--- Logging -------------------------------------------------------------------

log() {
  local level="$1"; shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

info()  { log "INFO" "$@"; }
warn()  { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

#--- Argument parsing ----------------------------------------------------------

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Required:
  --billing-account   EA billing account name (enrollment number)
  --source-account    Source enrollment account name (GUID)
  --dest-account      Destination enrollment account name (GUID)

Optional:
  --subscription-ids  Comma-separated list of subscription IDs to transfer.
                      If omitted, ALL subscriptions under --source-account are transferred.
  --api-version       Billing API version (default: 2024-04-01)
  --dry-run           List subscriptions and show what would happen, but don't transfer.
  -h, --help          Show this help message.

Examples:
  # Dry run — see what would be transferred
  $SCRIPT_NAME \\
    --billing-account 12345678 \\
    --source-account aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa \\
    --dest-account   bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \\
    --dry-run

  # Transfer specific subscriptions
  $SCRIPT_NAME \\
    --billing-account 12345678 \\
    --source-account aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa \\
    --dest-account   bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \\
    --subscription-ids "11111111-...,22222222-..."

EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --billing-account)  BILLING_ACCOUNT="$2";  shift 2 ;;
      --source-account)   SOURCE_ACCOUNT="$2";   shift 2 ;;
      --dest-account)     DEST_ACCOUNT="$2";     shift 2 ;;
      --subscription-ids) SUBSCRIPTION_IDS="$2"; shift 2 ;;
      --api-version)      API_VERSION="$2";      shift 2 ;;
      --dry-run)          DRY_RUN=true;          shift   ;;
      -h|--help)          usage ;;
      *) error "Unknown option: $1"; usage ;;
    esac
  done

  if [[ -z "$BILLING_ACCOUNT" || -z "$SOURCE_ACCOUNT" || -z "$DEST_ACCOUNT" ]]; then
    error "Missing required arguments."
    usage
  fi
}

#--- Azure helpers -------------------------------------------------------------

check_az_login() {
  if ! az account show &>/dev/null; then
    error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
  fi
  info "Azure CLI session active: $(az account show --query '{user: user.name, tenant: tenantId}' -o tsv)"
}

# List all subscription IDs under a given enrollment account
list_subscriptions_for_account() {
  local billing_acct="$1"
  local enrollment_acct="$2"

  local url="${BILLING_API_BASE}/billingAccounts/${billing_acct}/enrollmentAccounts/${enrollment_acct}/billingSubscriptions?api-version=${API_VERSION}"

  info "Fetching subscriptions from enrollment account: $enrollment_acct"

  az rest --method GET --url "$url" 2>/dev/null \
    | jq -r '.value[]? | .properties.subscriptionId // .name' 2>/dev/null
}

# Get subscription display name for logging
get_subscription_name() {
  local sub_id="$1"
  az account show --subscription "$sub_id" --query "name" -o tsv 2>/dev/null || echo "(unknown)"
}

# Transfer a single subscription to the destination enrollment account
transfer_subscription() {
  local billing_acct="$1"
  local sub_id="$2"
  local dest_enrollment_acct="$3"

  # The portal uses a POST to .../transfer or a PATCH on the billingSubscription.
  # We try the PATCH approach to reassign the enrollment account.
  local url="${BILLING_API_BASE}/billingAccounts/${billing_acct}/billingSubscriptions/${sub_id}?api-version=${API_VERSION}"

  local body
  body=$(cat <<JSON
{
  "properties": {
    "enrollmentAccountName": "${dest_enrollment_acct}"
  }
}
JSON
  )

  az rest \
    --method PATCH \
    --url "$url" \
    --headers "Content-Type=application/json" \
    --body "$body" 2>&1
}

#--- Main ----------------------------------------------------------------------

main() {
  parse_args "$@"

  info "=========================================="
  info "EA Subscription Transfer"
  info "=========================================="
  info "Billing account:     $BILLING_ACCOUNT"
  info "Source account:       $SOURCE_ACCOUNT"
  info "Destination account:  $DEST_ACCOUNT"
  info "Dry run:             $DRY_RUN"
  info "Log file:            $LOG_FILE"
  info "=========================================="

  check_az_login

  # Build subscription list
  local -a subs=()

  if [[ -n "$SUBSCRIPTION_IDS" ]]; then
    IFS=',' read -ra subs <<< "$SUBSCRIPTION_IDS"
    info "Using ${#subs[@]} subscription(s) from --subscription-ids"
  else
    info "No --subscription-ids provided; listing all under source account..."
    while IFS= read -r sub; do
      [[ -n "$sub" ]] && subs+=("$sub")
    done < <(list_subscriptions_for_account "$BILLING_ACCOUNT" "$SOURCE_ACCOUNT")
    info "Found ${#subs[@]} subscription(s) under source account"
  fi

  if [[ ${#subs[@]} -eq 0 ]]; then
    warn "No subscriptions found. Nothing to do."
    exit 0
  fi

  # Show summary
  info ""
  info "Subscriptions to transfer:"
  for sub in "${subs[@]}"; do
    local name
    name=$(get_subscription_name "$sub")
    info "  - $sub ($name)"
  done
  info ""

  # Confirm unless dry run
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY RUN] Would transfer ${#subs[@]} subscription(s). Exiting."
    exit 0
  fi

  echo ""
  read -rp "Proceed with transferring ${#subs[@]} subscription(s)? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "Aborted by user."
    exit 0
  fi

  # Transfer loop
  local success=0
  local failed=0

  for sub in "${subs[@]}"; do
    local name
    name=$(get_subscription_name "$sub")
    info "Transferring: $sub ($name) → $DEST_ACCOUNT ..."

    local result
    if result=$(transfer_subscription "$BILLING_ACCOUNT" "$sub" "$DEST_ACCOUNT"); then
      # Check for error in the JSON response
      local error_code
      error_code=$(echo "$result" | jq -r '.error.code // empty' 2>/dev/null)

      if [[ -n "$error_code" ]]; then
        local error_msg
        error_msg=$(echo "$result" | jq -r '.error.message // "unknown error"' 2>/dev/null)
        error "  FAILED: [$error_code] $error_msg"
        ((failed++))
      else
        info "  OK"
        ((success++))
      fi
    else
      error "  FAILED: az rest returned non-zero exit code"
      error "  Response: $result"
      ((failed++))
    fi

    # Brief pause to avoid throttling
    sleep 2
  done

  # Summary
  info ""
  info "=========================================="
  info "Transfer complete"
  info "  Succeeded: $success"
  info "  Failed:    $failed"
  info "  Total:     ${#subs[@]}"
  info "  Log:       $LOG_FILE"
  info "=========================================="

  if [[ $failed -gt 0 ]]; then
    warn "Some transfers failed. Check $LOG_FILE for details."
    exit 1
  fi
}

main "$@"