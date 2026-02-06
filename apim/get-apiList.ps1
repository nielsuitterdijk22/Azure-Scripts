[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Team,
  [Parameter(Mandatory = $true)]
  [string]$EnvironmentLetter
)

$TeamFolder = "teams/$Team"

if (-not (Test-Path $TeamFolder -PathType Container)) {
  Write-Output "Error: Team folder '$TeamFolder' does not exist"
  exit 1
}

$ApiList = @()

$apiFolders = Get-ChildItem -Path $TeamFolder -Directory -ErrorAction SilentlyContinue
foreach ($apiFolder in $apiFolders) {
  $versionFolders = Get-ChildItem -Path $apiFolder.FullName -Directory -ErrorAction SilentlyContinue
  foreach ($versionFolder in $versionFolders) {
    Get-ChildItem -Path $versionFolder.FullName -Filter "apiDefinition.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
      $apiDefinition = Get-Content -Path $_.FullName | ConvertFrom-Json
      if ($null -ne $apiDefinition.tags) {

        $service_url = $apiDefinition.service_url
        $definition = @{
          path                = $apiDefinition.path
          description         = $apiDefinition.description
          service_url         = $service_url.$EnvironmentLetter
          policy_file_name    = if (Test-Path "$versionFolder/api_policy.xml") {
            "$versionFolder/api_policy.xml" 
          }
          else {
            "global/api_policy.xml" 
          }
          openapi_file_format = if ($apiDefinition.openapi_file_format) {
            $apiDefinition.openapi_file_format 
          }
          else {
            "openapi" 
          }
          openapi_file_name   = if ($apiDefinition.openapi_file_name) {
            "$versionFolder/$($apiDefinition.openapi_file_name)" 
          }
          else {
            "$versionFolder/openapi.yaml" 
          }
          self_managed        = if ($apiDefinition.self_managed) {
            $apiDefinition.self_managed 
          }
          else {
            $false 
          }
          tags                = $apiDefinition.tags
        }
      }

      $operation = @{}
      Get-ChildItem -Path "$($versionFolder.FullName)\operation" -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $operation += @{ $_.Name.Replace(".xml", "") = "$versionFolder/operation/$($_.Name)" }
      }
    }

    $ApiList += [PSCustomObject]@{
      name               = $apiFolder.Name
      version            = $versionFolder.Name
      api_definition     = $definition
      operation_policies = $operation
    }
  }
}

Write-Output $ApiList

# create json output file
$outputFile = Join-Path $TeamFolder "apiList.json"
if ($ApiList.Count -eq 0) {
  Set-Content -Path $outputFile -Value '[]'
}
else {
  $ApiList | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile
}