#!/bin/bash

set -euo pipefail

###############################################################################
# APIM Terraform Import Script
#
# Imports existing Azure API Management resources into Terraform state.
# Reads apiList.json and products.json per team to determine what to import.
#
# Prerequisites:
#   - az CLI (logged in to correct subscription)
#   - terraform CLI
#   - jq
#   - pwsh (optional, for auto-generating apiList.json)
#
# Usage:
#   ./import.sh --team osb --env t
#   ./import.sh --team osb --env t --dry-run
#   ./import.sh --env t                        # all teams for test
#   ./import.sh                                # all teams, all envs
#   ./import.sh --team osb --env t --subscription-id <sub-id>
###############################################################################

APIOPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAMS_DIR="${APIOPS_ROOT}/teams"
SCRIPTS_DIR="${APIOPS_ROOT}/_scripts"
LOG_FILE="${APIOPS_ROOT}/import.log"

# Defaults
TEAM=""
ENV_LETTER=""
SUBSCRIPTION_ID=""
DRY_RUN=false
GENERATE_API_LIST=false
ALL_ENVS=(d t a p)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

###############################################################################
# Argument parsing
###############################################################################
while [[ $# -gt 0 ]]; do
  case $1 in
    --team)           TEAM="$2"; shift 2 ;;
    --env)            ENV_LETTER="$2"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --generate)       GENERATE_API_LIST=true; shift ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --team <name>             Import only this team (default: all teams)"
      echo "  --env <letter>            Import only this environment: d|t|a|p (default: all)"
      echo "  --subscription-id <id>    Azure subscription ID (default: auto-detect from az CLI)"
      echo "  --dry-run                 Print import commands without executing"
      echo "  --generate                Generate apiList.json via PowerShell before importing"
      echo "  --help                    Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

###############################################################################
# Helper functions
###############################################################################
log()     { echo -e "${CYAN}[INFO]${NC} $*"; echo "[INFO] $(date +%T) $*" >> "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; echo "[WARN] $(date +%T) $*" >> "$LOG_FILE"; }
err()     { echo -e "${RED}[FAIL]${NC} $*"; echo "[FAIL] $(date +%T) $*" >> "$LOG_FILE"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; echo "[ OK ] $(date +%T) $*" >> "$LOG_FILE"; }

IMPORT_TOTAL=0
IMPORT_OK=0
IMPORT_SKIP=0
IMPORT_FAIL=0

resolve_subscription_id() {
  if [[ -n "$SUBSCRIPTION_ID" ]]; then
    return
  fi
  log "Auto-detecting subscription ID from az CLI..."
  SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null) || {
    err "Failed to detect subscription ID. Log in with 'az login' or pass --subscription-id."
    exit 1
  }
  log "Using subscription: $SUBSCRIPTION_ID"
}

get_teams() {
  if [[ -n "$TEAM" ]]; then
    echo "$TEAM"
  else
    for dir in "$TEAMS_DIR"/*/; do
      local t
      t=$(basename "$dir")
      # skip non-team directories (cicc is the pipeline template source)
      [[ "$t" == "cicc" ]] && continue
      echo "$t"
    done
  fi
}

get_envs() {
  if [[ -n "$ENV_LETTER" ]]; then
    echo "$ENV_LETTER"
  else
    printf '%s\n' "${ALL_ENVS[@]}"
  fi
}

generate_api_list() {
  local team=$1 env=$2
  if [[ ! -f "$SCRIPTS_DIR/get-apiList.ps1" ]]; then
    warn "PowerShell script not found at $SCRIPTS_DIR/get-apiList.ps1 - skipping generation"
    return 1
  fi
  if ! command -v pwsh &>/dev/null; then
    warn "pwsh not found - cannot generate apiList.json. Install PowerShell Core or run manually."
    return 1
  fi
  log "Generating apiList.json for team=$team env=$env ..."
  (cd "$APIOPS_ROOT" && pwsh -File "$SCRIPTS_DIR/get-apiList.ps1" -Team "$team" -EnvironmentLetter "$env")
}

init_terraform() {
  local team=$1 env=$2
  log "Running terraform init (team=$team, env=$env) ..."

  local init_args=(
    -reconfigure
    -backend-config="key=import_test_apiops_${team}.tfstate"
    -backend-config="resource_group_name=rg-apim-${env}-we-001"
    -backend-config="storage_account_name=stapim${env}we001"
    -backend-config="container_name=terraformstates"
    -backend-config="use_azuread_auth=true"
  )

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY RUN] terraform init ${init_args[*]}"
    return 0
  fi

  (cd "$APIOPS_ROOT" && terraform init "${init_args[@]}") || {
    err "terraform init failed for team=$team env=$env"
    return 1
  }
}

# Run a single terraform import. Continues on failure.
do_import() {
  local tf_address=$1
  local azure_id=$2
  local env=$3
  local team=$4

  IMPORT_TOTAL=$((IMPORT_TOTAL + 1))

  if [[ "$DRY_RUN" == true ]]; then
    echo "  terraform import \\"
    echo "    -var=\"environment_letter=${env}\" -var=\"team_name=${team}\" \\"
    echo "    '${tf_address}' \\"
    echo "    '${azure_id}'"
    IMPORT_OK=$((IMPORT_OK + 1))
    return 0
  fi

  local output
  output=$(cd "$APIOPS_ROOT" && terraform import \
    -var="environment_letter=${env}" \
    -var="team_name=${team}" \
    "${tf_address}" "${azure_id}" 2>&1) && {
      success "Imported ${tf_address}"
      IMPORT_OK=$((IMPORT_OK + 1))
      return 0
  }

  # Categorize the failure
  if echo "$output" | grep -qi "already managed\|already exists in the state"; then
    warn "Already in state: ${tf_address}"
    IMPORT_SKIP=$((IMPORT_SKIP + 1))
  elif echo "$output" | grep -qi "non-existent remote object\|Cannot import"; then
    warn "Not found in Azure (will be created on apply): ${tf_address}"
    IMPORT_SKIP=$((IMPORT_SKIP + 1))
  else
    err "Failed to import: ${tf_address}"
    err "  Azure ID: ${azure_id}"
    echo "$output" >> "$LOG_FILE"
    IMPORT_FAIL=$((IMPORT_FAIL + 1))
  fi
}

###############################################################################
# Import logic - APIs
###############################################################################
import_apis() {
  local team=$1 env=$2 sub_id=$3

  local api_list_file="$TEAMS_DIR/$team/apiList.json"
  if [[ ! -f "$api_list_file" ]]; then
    warn "No apiList.json for team $team - skipping APIs"
    return
  fi

  local base="/subscriptions/${sub_id}/resourceGroups/rg-shared-${env}-we-001/providers/Microsoft.ApiManagement/service/apim-shared-${env}-we-002"

  local api_count
  api_count=$(jq 'length' "$api_list_file")

  for ((i = 0; i < api_count; i++)); do
    local name version self_managed api_key api_apim_name
    name=$(jq -r ".[$i].name" "$api_list_file")
    version=$(jq -r ".[$i].version" "$api_list_file")
    self_managed=$(jq -r ".[$i].api_definition.self_managed" "$api_list_file")
    api_key="${name}-${version}"

    # API name in APIM follows the TF naming: name-version (or just name for v0)
    # if [[ "$version" != "v0" ]]; then
    #   api_apim_name="${name}-${version}"
    # else
    #   api_apim_name="${name}"
    # fi
    api_apim_name="${name}"

    echo ""
    log "--- API: ${api_key} ---"

    local mod="module.import_api.module.import_api[\"${api_key}\"]"

    # 1. Version Set
    do_import \
      "${mod}.azurerm_api_management_api_version_set.version" \
      "${base}/apiVersionSets/${name}" \
      "$env" "$team"

    # 2. API resource (this[0] or self_managed[0])
    if [[ "$self_managed" == "true" ]]; then
      do_import \
        "${mod}.azurerm_api_management_api.self_managed[0]" \
        "${base}/apis/${api_apim_name};rev=1" \
        "$env" "$team"
    else
      do_import \
        "${mod}.azurerm_api_management_api.this[0]" \
        "${base}/apis/${api_apim_name};rev=1" \
        "$env" "$team"
    fi

    # 3. API Policy
    do_import \
      "${mod}.azurerm_api_management_api_policy.policy" \
      "${base}/apis/${api_apim_name}" \
      "$env" "$team"

    # 4. Tags (from apiDefinition + the auto-added team tag)
    # local tags
    # tags=$(jq -r ".[$i].api_definition.tags // [] | .[]" "$api_list_file" 2>/dev/null || true)
    # # TF module adds team_{team_name} tag via setunion
    # tags="${tags}"$'\n'"team_${team}"

    # while IFS= read -r tag; do
    #   [[ -z "$tag" ]] && continue
    #   do_import \
    #     "${mod}.azurerm_api_management_api_tag.api_tag[\"${tag}\"]" \
    #     "${base}/apis/${api_apim_name}/tags/${tag}" \
    #     "$env" "$team"
    # done <<< "$tags"

    # 5. Operation Policies
    local op_keys
    op_keys=$(jq -r ".[$i].operation_policies // {} | keys[]" "$api_list_file" 2>/dev/null || true)
    while IFS= read -r op_id; do
      [[ -z "$op_id" ]] && continue
      do_import \
        "${mod}.azurerm_api_management_api_operation_policy.operation_policy[\"${op_id}\"]" \
        "${base}/apis/${api_apim_name}/operations/${op_id}" \
        "$env" "$team"
    done <<< "$op_keys"
  done
}

###############################################################################
# Import logic - Products
###############################################################################
import_products() {
  local team=$1 env=$2 sub_id=$3

  local products_file="$TEAMS_DIR/$team/products.json"
  if [[ ! -f "$products_file" ]]; then
    warn "No products.json for team $team - skipping products"
    return
  fi

  local base="/subscriptions/${sub_id}/resourceGroups/rg-shared-${env}-we-001/providers/Microsoft.ApiManagement/service/apim-shared-${env}-we-002"

  local product_count
  product_count=$(jq 'length' "$products_file")

  for ((j = 0; j < product_count; j++)); do
    local name
    name=$(jq -r ".[$j].name" "$products_file")

    echo ""
    log "--- Product: ${name} ---"

    local mod="module.import_api.module.import_products[\"${name}\"]"

    # 1. Product
    do_import \
      "${mod}.azurerm_api_management_product.this" \
      "${base}/products/${name}" \
      "$env" "$team"

    # 2. Product Policy
    do_import \
      "${mod}.azurerm_api_management_product_policy.policy" \
      "${base}/products/${name}" \
      "$env" "$team"

    # 3. Product-API associations
    local api_names
    api_names=$(jq -r ".[$j].api_names // [] | .[]" "$products_file" 2>/dev/null || true)
    while IFS= read -r api_name; do
      [[ -z "$api_name" ]] && continue
      do_import \
        "${mod}.azurerm_api_management_product_api.product_api[\"${api_name}\"]" \
        "${base}/products/${name}/apis/${api_name}" \
        "$env" "$team"
    done <<< "$api_names"

    # 4. Subscriptions
    local subs
    subs=$(jq -r ".[$j].subscriptions // [] | .[]" "$products_file" 2>/dev/null || true)
    while IFS= read -r sub; do
      [[ -z "$sub" ]] && continue
      do_import \
        "${mod}.azurerm_api_management_subscription.subscription[\"${sub}\"]" \
        "${base}/subscriptions/${sub}" \
        "$env" "$team"
    done <<< "$subs"

    # 5. Product Groups (guests + developers)
    do_import \
      "${mod}.azurerm_api_management_product_group.group_guests" \
      "${base}/products/${name}/groups/guests" \
      "$env" "$team"

    do_import \
      "${mod}.azurerm_api_management_product_group.group_developers" \
      "${base}/products/${name}/groups/developers" \
      "$env" "$team"
  done
}

###############################################################################
# Main
###############################################################################
main() {
  echo "" > "$LOG_FILE"
  echo "============================================="
  log "APIM Terraform Import Script"
  echo "============================================="
  [[ "$DRY_RUN" == true ]] && warn "DRY RUN MODE - no changes will be made"
  echo ""

  resolve_subscription_id
  export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

  local teams envs
  teams=$(get_teams)
  envs=$(get_envs)

  while IFS= read -r team; do
    [[ -z "$team" ]] && continue
    while IFS= read -r env; do
      [[ -z "$env" ]] && continue

      echo ""
      echo "============================================="
      log "Team: $team | Environment: $env"
      echo "============================================="

      # Optionally generate apiList.json
      if [[ "$GENERATE_API_LIST" == true ]]; then
        generate_api_list "$team" "$env" || true
      fi

      # Check minimum required files
      if [[ ! -f "$TEAMS_DIR/$team/apiList.json" && ! -f "$TEAMS_DIR/$team/products.json" ]]; then
        warn "Team $team has neither apiList.json nor products.json - skipping"
        continue
      fi

      # Initialize terraform for this team/env backend
      init_terraform "$team" "$env" || continue

      import_products "$team" "$env" "$SUBSCRIPTION_ID"
      import_apis "$team" "$env" "$SUBSCRIPTION_ID"

    done <<< "$envs"
  done <<< "$teams"

  echo ""
  echo "============================================="
  log "Import Summary"
  echo "============================================="
  log "Total:   $IMPORT_TOTAL"
  success "Success: $IMPORT_OK"
  warn "Skipped: $IMPORT_SKIP  (already in state)"
  err "Failed:  $IMPORT_FAIL"
  log "Full log: $LOG_FILE"
}

main
