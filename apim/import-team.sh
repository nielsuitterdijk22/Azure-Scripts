#!/sbin/bash

# Inputs
TEAM_NAME=$1
ENVIRONMENT=$2

# Config
tf_vars="-var=\"environment_letter=${ENVIRONMENT}\" -var=\"team_name=${TEAM_NAME}\""

# Validate input
if [ -z "$TEAM_NAME" ] || [ -z "$ENVIRONMENT" ]; then
  echo "Usage: ./import-team.sh <TEAM_NAME> <ENVIRONMENT>"
  exit 1
fi
if [ "$ENVIRONMENT" != "D" ] && [ "$ENVIRONMENT" != "T" ] && [ "$ENVIRONMENT" != "A" ] && [ "$ENVIRONMENT" != "P" ]; then
  echo "Error: ENVIRONMENT must be either D, T, A, P."
  exit 1
fi

# Generate api-list
pwsh ./get-apiList.ps1 -Team $TEAM_NAME -Environment $ENVIRONMENT

# Import APIs
apis=$(cat teams/${TEAM_NAME}/apiList.json)

for api in $(echo "${apis}" | jq -r '.[]'); do
  echo "Importing API: $api"
  
  
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api.this[0]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_operation_policy.operation_policy["plaatsdocument"]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_operation_policy.operation_policy["plaatsopdracht"]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_policy.policy
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_tag.api_tag["audience_internal"]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_tag.api_tag["confidentiality_low"]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_tag.api_tag["ownership_internal"]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_tag.api_tag["team_osb"]
    tf import $tf_vars module.import_api.module.import_api["CED-v1"].azurerm_api_management_api_version_set.version

done
