# Cloud Admin Scripts Collection

Organized collection of Azure administration and automation scripts.

## 📁 Folder Structure

### `/identity` - Identity & Access Management
- `assign_graph_permission_to_managed_identity.sh` - Assign Microsoft Graph permissions to managed identities
- `assign_sharepoint_permission_to_managed_identity.sh` - Assign SharePoint permissions to managed identities
- `assign_permissions_to_managed_identity.sh` - Smart dispatcher for permission assignment
- `assign_graph_permission_to_user.sh` - Assign Graph permissions to users
- `audit_app_registrations.sh` - Audit app registrations for security issues
- `send_graph_mail.py` - Send emails via Microsoft Graph API
- `managed_identity_utils.sh` - Shared utility functions

### `/security` - Security & Compliance
- `find_overprivileged_accounts.sh` - Find accounts with excessive permissions

### `/cost-management` - Cost Optimization
- `resource_cost_analyzer.sh` - Analyze resource costs and find waste

### `/monitoring` - Health & Monitoring
- `health_check.sh` - Comprehensive Azure environment health check

### `/network` - Network Security
- `check_nsg_rules.sh` - Analyze NSG rules for security issues

### `/utilities` - General Purpose Tools
- `bulk_resource_tagger.sh` - Add tags to all resources in a resource group
- `network_test.sh` - Network connectivity testing
- `generate_curls.sh` - Generate curl commands for API testing
- `apim_tests.sh` - API Management testing
- `tf_init.sh` - Terraform initialization helper

### `/azure-devops` - Azure DevOps Automation
- `Import-ServiceConnections.ps1` - Import service connections
- `extract_azdo_config.sh` - Extract Azure DevOps configuration
- `format_repos.py` - Format repository configurations
- `format_service_connections.py` - Format service connection data
- `format_teams.py` - Format team configurations
- `import_tf_state.sh` - Import Terraform state

## 🚀 Quick Start

Make scripts executable:
```bash
find . -name "*.sh" -exec chmod +x {} \;
```

Run permission assignment:
```bash
./identity/assign_permissions_to_managed_identity.sh graph my-app User.Read.All
```

Run security audit:
```bash
./security/find_overprivileged_accounts.sh
```

Run health check:
```bash
./monitoring/health_check.sh
```

## 💡 Additional Script Ideas

### Security & Compliance
- `check_conditional_access_policies.sh` - Audit Conditional Access policies
- `scan_storage_public_access.sh` - Find storage accounts with public access
- `audit_key_vault_access.sh` - Review Key Vault access policies
- `check_mfa_status.sh` - Check MFA enrollment status

### Cost Management
- `unused_resources_finder.sh` - Find unused resources across subscriptions
- `rightsizing_recommendations.sh` - VM rightsizing recommendations
- `reserved_instance_optimizer.sh` - RI coverage analysis

### Automation & DevOps
- `auto_scale_scheduler.sh` - Schedule auto-scaling events
- `backup_automation.sh` - Automated backup verification
- `policy_compliance_checker.sh` - Check Azure Policy compliance

### Monitoring & Alerting
- `log_analytics_queries.sh` - Common Log Analytics queries
- `create_standard_alerts.sh` - Create standard monitoring alerts
- `performance_baseline.sh` - Establish performance baselines

## 🛠️ Prerequisites

- Azure CLI installed and authenticated
- PowerShell (for .ps1 scripts)
- jq (for JSON processing)
- Appropriate Azure permissions

## 📖 Usage Patterns

Most scripts follow these patterns:
- `-h` or `--help` for usage information
- Minimal required parameters (smart defaults)
- Clear error messages and validation
- Consistent output formatting

## 🤝 Contributing

When adding new scripts:
1. Place in appropriate folder
2. Follow naming convention: `verb_noun.sh`
3. Include usage function
4. Add to this README
5. Make executable with `chmod +x`# azure_scripts
