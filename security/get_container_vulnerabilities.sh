#!/usr/bin/env bash
# Usage: ./get-acr-vulns.sh <SUBSCRIPTION> <RG> <ACR_NAME> <REPO> <TAG>

SUBSCRIPTION_INPUT=$1
RG=$2
ACR=$3
REPO=$4
TAG=$5

# Convert subscription name to subscription ID if needed
if [[ $SUBSCRIPTION_INPUT =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    SUBSCRIPTION=$SUBSCRIPTION_INPUT
else
    echo "Converting subscription name '$SUBSCRIPTION_INPUT' to subscription ID..."
    SUBSCRIPTION=$(az account list --query "[?name=='$SUBSCRIPTION_INPUT'].id" -o tsv)
    if [ -z "$SUBSCRIPTION" ]; then
        echo "Error: Subscription '$SUBSCRIPTION_INPUT' not found"
        echo "Available subscriptions:"
        az account list --query "[].{Name:name, SubscriptionId:id}" -o table
        exit 1
    fi
    echo "Using subscription ID: $SUBSCRIPTION"
fi

# Assessment ID for Container Registry Vulnerabilities
ASSESSMENT="c0b7cfc6-3172-465a-b378-53c7ff2cc0d5"

# Get an access token for the REST API
TOKEN=$(az account get-access-token --subscription "$SUBSCRIPTION" --resource https://management.azure.com --query accessToken -o tsv)

# Show available images first if no specific repo/tag provided
if [ -z "$REPO" ] || [ -z "$TAG" ]; then
  echo "Available container images with vulnerabilities in $ACR:"
  az graph query --subscriptions "$SUBSCRIPTION" -q "
  SecurityResources
  | where type =~ 'microsoft.security/assessments/subassessments'
  | where properties.additionalData.assessedResourceType == 'AzureContainerRegistryVulnerability'
  | extend assessmentKey=extract(@'(?i)providers/Microsoft.Security/assessments/([^/]*)', 1, id)
  | where assessmentKey == '$ASSESSMENT'
  | where id contains '$ACR'
  | extend
    registryHost = tostring(properties.additionalData.artifactDetails.registryHost),
    repositoryName = tostring(properties.additionalData.artifactDetails.repositoryName),
    tags = properties.additionalData.artifactDetails.tags,
    severity = tostring(properties.status.severity)
  | mv-expand tag = tags
  | project
    Registry = registryHost,
    Repository = repositoryName,
    Tag = tostring(tag),
    Severity = severity
  | distinct Registry, Repository, Tag, Severity
  " --query "data" -o table
  exit 0
fi

# Single comprehensive query to get vulnerability data for specific image
echo "Fetching vulnerability data for $REPO:$TAG from ACR: $ACR"

az graph query --subscriptions "$SUBSCRIPTION" -q "
SecurityResources
| where type =~ 'microsoft.security/assessments/subassessments'
| where properties.additionalData.assessedResourceType == 'AzureContainerRegistryVulnerability'
| extend assessmentKey=extract(@'(?i)providers/Microsoft.Security/assessments/([^/]*)', 1, id)
| where assessmentKey == '$ASSESSMENT'
| where id contains '$ACR'
| extend
  registryHost = tostring(properties.additionalData.artifactDetails.registryHost),
  repositoryName = tostring(properties.additionalData.artifactDetails.repositoryName),
  tags = properties.additionalData.artifactDetails.tags
| mv-expand tag = tags
| where repositoryName =~ '$REPO' and tostring(tag) =~ '$TAG'
| extend
  vuln = properties.additionalData.vulnerabilityDetails,
  software = properties.additionalData.softwareDetails
| where vuln.severity in ('High', 'Critical')
| project
  Registry = registryHost,
  Repository = repositoryName,
  Tag = tostring(tag),
  CVE = tostring(vuln.cveId),
  Severity = tostring(vuln.severity),
  Package = tostring(software.packageName),
  CurrentVersion = tostring(software.version),
  FixedVersion = tostring(software.fixedVersion),
  Description = tostring(vuln.weaknesses.cwe[0].id)
" --query "data" -o table
