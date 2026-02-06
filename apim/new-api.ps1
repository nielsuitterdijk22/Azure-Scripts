param(
  [string]$Team,
  [string]$ApiName,
  [int]$VersionNumber = 1,
  [string]$Description = "",
  [bool]$Force = $false
)
# Check if the required parameters are provided
if (-not $Team -or -not $ApiName) {
  Write-Host "Usage: .\new-api.ps1 -Team <Team> -ApiName <Name> [-Version <Version>] [-Description <Description>]"
  exit 1
}

$Version = "v$VersionNumber"

# Define the base path for the API
$basePath = "$Team/$ApiName/$Version"
Set-Location -Path 'teams'

Write-Host "Creating API structure for $ApiName in team $Team with version $Version..."

if (-not (Test-Path $basePath)) {
  New-Item -ItemType Directory -Path $basePath -Force | Out-Null
}
else {
  if ($Force) {
    Write-Host "Overwriting existing directory: $basePath"
    Remove-Item -Path $basePath -Recurse -Force
    New-Item -ItemType Directory -Path $basePath -Force | Out-Null
  }
  else {
    Write-Host "Directory $basePath already exists. Use -Force `$true to overwrite."
  }
}

# Create apiDefinition.json file
$jsonFile = "$basePath/apiDefinition.json"
$jsonContent = @"
{
  "path": "path/to/api",
  "description": "description of api",
  "service_url": {
    "d": "https://url.com",
    "s": "https://url.com",
    "p": "https://url.com",
    "t": "https://url.com",
    "a": "https://url.com"
  },
  "tags": ["audience_public", "ownership_external", "confidentiality_low"]
}
"@
$jsonContent  | Set-Content -Path $jsonFile

# Create openapi.yaml file
$openApiDescription = if ($Description) { $Description } else { "Description of api" }
$openApiFile = "$basePath/openapi.yaml"
$openApiContent = @"
openapi: 3.1.0
info:
  title: "$ApiName"
  description: "$openApiDescription"
  version: "$Version"

servers:
  - url: "https://api.example.com"

paths:
  /sample:
    get:
      operationId: getSample
      summary: Returns a list of sample items.
      description: Optional extended description in CommonMark or HTML.
      responses:
        '200':
          description: A JSON array of sample items
          content:
            application/json:
              schema:
                type: array
                items:
                  type: string
"@
$openApiContent | Set-Content -Path $openApiFile

Set-Location -Path '..'