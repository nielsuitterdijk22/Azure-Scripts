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
env=d
sub_id=e046e77b-ae26-45d2-be42-b69f7d1215c3 # conn-d
terraform init \
  -reconfigure \
  -backend-config="resource_group_name=rg-apim-${env}-we-001" \
  -backend-config="storage_account_name=stapim${env}we001" \
  -backend-config="container_name=terraformstates" \
  -backend-config="subscription_id=$sub_id" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="key=$state"
