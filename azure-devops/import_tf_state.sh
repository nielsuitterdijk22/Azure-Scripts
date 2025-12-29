#!/bin/bash

# We only have to import the project, repos & teams
# We use data for service connections while importing. 
# Permissions are overwritten

PROJECT_ID="f6cf529d-e936-4726-9e52-f08674a7c154"
TF_CPP_MIN_LOG_LEVEL=3

# echo "Importing project"
# terraform import -var service_connections=[] -var teams=[] -var groups=[] -var repositories=[] 'azuredevops_project.DAS' $PROJECT_ID

# echo "Importing TEAMS from DAS/teams.json..."
# jq -c '.teams[]' "DAS/test_params.json" | while read -r team; do
#   echo -e "\n ********************************************** \n"
#   echo $team
#   NAME=$(echo "$team" | jq -r '.name')
#   TEAM_ID=$(echo "$team" | jq -r '.id')

#   if [ -z "$NAME" ]; then
#     echo "Skipping an entry due to missing name."
#     continue
#   fi

#   echo "Importing team '${NAME}' with ID ${TEAM_ID}..."
#   TF_LOG=warn terraform import \
#     -var repositories=[] \
#     -var groups=[] \
#     -var "teams=[$team]" \
#     -var service_connections=[] \
#     "module.teams[\"$NAME\"].azuredevops_team.team" \
#     "${PROJECT_ID}/${TEAM_ID}"
# done

# echo "Importing repositories from $REPOS_JSON..."
# # Loop through each repository in the JSON file.
# jq -c '.repositories[]' "DAS/test_params.json" | while read repo; do
#   echo -e "\n ********************************************** \n"
#   NAME=$(echo "$repo" | jq -r '.name')
#   REPO_ID=$(echo "$repo" | jq -r '.id')

#   if [ -z "$NAME" ] || [ -z "$REPO_ID" ]; then
#     echo "Skipping an entry due to missing name or id."
#     continue
#   fi

#   echo "Importing repository '${NAME}' with ID ${REPO_ID}..."
#   TF_LOG=warn terraform import \
#     -var repositories=[$repo] \
#     -var groups=[] \
#     -var teams=[] \
#     -var service_connections=[] \
#     "module.repositories.azuredevops_git_repository.repo[\"$NAME\"]" \
#     "${PROJECT_ID}/${REPO_ID}"
# done


echo "Import process complete."