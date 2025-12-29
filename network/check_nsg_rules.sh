#!/bin/bash
set -euo pipefail

echo "🛡️  Analyzing Network Security Group rules..."

# Find overly permissive rules
echo "⚠️  Overly permissive NSG rules:"
az network nsg list --query '[].{name:name, resourceGroup:resourceGroup}' -o tsv | while read -r nsg_name rg; do
    echo "Checking NSG: $nsg_name"

    # Rules allowing access from internet (0.0.0.0/0 or *)
    az network nsg rule list --nsg-name "$nsg_name" --resource-group "$rg" \
        --query '[?sourceAddressPrefix==`0.0.0.0/0` || sourceAddressPrefix==`*`].{name:name, direction:direction, access:access, protocol:protocol, destinationPortRange:destinationPortRange}' \
        -o table

    # Rules with common dangerous ports open
    az network nsg rule list --nsg-name "$nsg_name" --resource-group "$rg" \
        --query '[?(destinationPortRange==`22` || destinationPortRange==`3389` || destinationPortRange==`1433` || destinationPortRange==`3306`) && access==`Allow` && (sourceAddressPrefix==`0.0.0.0/0` || sourceAddressPrefix==`*`)].{name:name, port:destinationPortRange, source:sourceAddressPrefix}' \
        -o table
done

echo "🔍 Unused NSGs:"
az network nsg list --query '[?subnets==null && networkInterfaces==null].{name:name, resourceGroup:resourceGroup}' -o table

echo "📊 NSG rules summary:"
az network nsg list --query '[].{name:name, rulesCount:length(securityRules), defaultRulesCount:length(defaultSecurityRules)}' -o table