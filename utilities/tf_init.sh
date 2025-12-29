#!/bin/bash

# terraform init \
#   -reconfigure \
#   -backend-config="resource_group_name=rg-agent-s-we-001" \
#   -backend-config="storage_account_name=stterraformstateswe001" \
#   -backend-config="container_name=terraformstates" \
#   -backend-config="subscription_id=321c9872-a70f-4ee1-a36f-01a9991c9158" \
#   -backend-config="use_azuread_auth=true" \
#   -backend-config="key=azuredevops.tfstate"

state=apiops_osb.tfstate
terraform init \
  -reconfigure \
  -backend-config="resource_group_name=rg-agent-p-we-001" \
  -backend-config="storage_account_name=stterraformstatepwe001" \
  -backend-config="container_name=terraformstatep" \
  -backend-config="subscription_id=f7195be9-1112-49e1-9697-cdc0ed846069" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="key=$state"
