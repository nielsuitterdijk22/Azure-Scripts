#!/bin/bash
set -euo pipefail

echo "🏥 Azure Environment Health Check"
echo "================================"

# Check Azure CLI authentication
echo "🔐 Authentication Status:"
if az account show &>/dev/null; then
    echo "✅ Authenticated as: $(az account show --query user.name -o tsv)"
    echo "📋 Subscription: $(az account show --query name -o tsv)"
else
    echo "❌ Not authenticated. Run 'az login'"
    exit 1
fi

# Check resource health
echo "🏥 Resource Health Issues:"
az resource list --query '[?tags.environment==`production`]' --output tsv | while read resource; do
    health=$(az resource show --ids "$resource" --query 'properties.healthStatus' -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$health" != "Healthy" && "$health" != "Unknown" ]]; then
        echo "⚠️  $resource: $health"
    fi
done

# Check failed deployments
echo "💥 Recent Failed Deployments:"
az deployment group list --query '[?provisioningState==`Failed`].{name:name, timestamp:timestamp, error:error.message}' -o table

# Check alerts
echo "🚨 Active Alerts:"
az monitor alert list --query '[?properties.enabled==`true` && properties.condition.allOf[0].metricValue > properties.condition.allOf[0].threshold].{name:name, severity:properties.severity}' -o table

# Check backup status
echo "💾 Backup Status:"
az backup job list --query '[?status!=`Completed`].{name:name, status:status, startTime:startTime}' -o table

echo "✅ Health check complete!"