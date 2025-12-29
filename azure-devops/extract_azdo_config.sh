#!/bin/bash

# Ensure being run from project root
cd "$(dirname "$0")"/..

# az extension add -n azure-devops
# az login
echo "Fetching teams"
echo "{\"teams\": $(az devops team list -p DAS -o json)}" > DAS/teams.json
echo "> Found $(jq 'length' DAS/teams.json) teams."

echo "Fetching team members & admins"
python scripts/format_teams.py

echo "Fetching security namespaces"
az devops security permission namespace list > 'DAS/securityNamespaces.json'

echo "Fetching groups"
echo "{\"groups\": $(az devops security group list \
  -p DAS \
  --query "graphGroups[?contains(descriptor, 'vss')].{name:displayName, descriptor:descriptor}" \
  -o json)}" > DAS/groups.json
echo "> Found $(jq '.groups | length' DAS/groups.json) groups"

echo "Fetching repositories"
echo "{\"repositories\": $(az repos list \
  -p DAS \
  --query "[].{id:id, name:name, default_branch:defaultBranch}" \
  -o json)}" > DAS/repos.json

echo "Formatting repos with contributors"
python scripts/format_repos.py

echo "Fetching service connections" 
echo "{\"service_connections\": $(az devops service-endpoint list \
  --query "[].{name:name, id:id}" \
  -o json)}" > DAS/service_connections.json

echo "Fetching pipelines"
echo "{\"pipelines\": $(az pipelines list \
  --query "[].{id:id, name:name}" \
  -o json)}" > DAS/pipelines.json

echo "Formatting service connections with pipelines"
python scripts/format_service_connections.py