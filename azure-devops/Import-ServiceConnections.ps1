# Import role assignments from Azure AD to Terraform state
# This script will read groups from a json file and import them to Terraform state

$filePath = "$PSScriptRoot\..\DAS\service_connections.json"
$projectId = "f6cf529d-e936-4726-9e52-f08674a7c154"



# Check if the file exists
if (Test-Path $filePath) {
    Write-Host "Starting import of Service Connections from $filePath"

    $content = get-content -Path $filePath | ConvertFrom-Json


    foreach ($serviceConnection in $content.azure_service_connections) {
        # Import role assignments to Terraform state

        $to = 'module.service_connections["'+ $($serviceConnection.Name) +'"].azuredevops_serviceendpoint_azurerm.main'
        $resource = "$($projectId)/$($serviceConnection.Id)"

        terraform import -var-file='DAS/groups.json' -var-file='DAS/repos.json' -var-file='DAS/teams.json' -var-file $filePath  $to $resource
        
        $appId = (az ad app list --display-name "dasrechtsbijstand-DAS-$($serviceConnection.Name)" | ConvertFrom-Json).id

        $to = 'module.service_connections["'+ $($serviceConnection.Name) +'"].azuread_application.main'
        $resource = "applications/$($appId)"

        terraform import -var-file='DAS/groups.json' -var-file='DAS/repos.json' -var-file='DAS/teams.json' -var-file $filePath  $to $resource

        $spId = (az ad sp list --display-name "dasrechtsbijstand-DAS-$($serviceConnection.Name)" | ConvertFrom-Json).id

        $to = 'module.service_connections["'+ $($serviceConnection.Name) +'"].azuread_service_principal.main'
        $resource = "servicePrincipals/$($spId)"

        terraform import -var-file='DAS/groups.json' -var-file='DAS/repos.json' -var-file='DAS/teams.json' -var-file $filePath  $to $resource

        $fdId = (az ad app federated-credential list --id $appId | ConvertFrom-Json).id

        $to = 'module.service_connections["'+ $($serviceConnection.Name) +'"].azuread_application_federated_identity_credential.main'
        $resource = "$($appId)/federatedIdentityCredential/$($fdId)"

        terraform import -var-file='DAS/groups.json' -var-file='DAS/repos.json' -var-file='DAS/teams.json' -var-file $filePath  $to $resource



    }
} else {
    Write-Host "File not found: $filePath"
}