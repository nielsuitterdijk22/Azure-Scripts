[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)] [string] $Root = "teams",
  [Parameter(Mandatory = $false)] [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info($m) { 
  if (-not $Quiet) { 
    Write-Host $m -ForegroundColor Cyan 
  } 
}
function Write-Ok($m) { 
  if (-not $Quiet) { 
    Write-Host $m -ForegroundColor Green 
  } 
}
function Write-Err($m) { 
  Write-Host $m -ForegroundColor Red 
}
function Write-Warn($m) { 
  if (-not $Quiet) { 
    Write-Host $m -ForegroundColor Yellow 
  } 
}

$rootFull = $(Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$files = Get-ChildItem -Path $rootFull -Recurse -Filter apiDefinition.json | Sort-Object FullName
if (-not $files) { 
  Write-Warn "No apiDefinition.json files found"; 
  exit 0 
}

$requiredTop = 'path', 'description', 'service_url', 'tags'
$requiredEnv = 'd', 'p', 't', 'a'
$audience = 'audience_public', 'audience_internal', 'audience_partner', 'audience_composite'
$ownership = 'ownership_internal', 'ownership_external', 'ownership_co-owned', 'ownership_delegated', 'ownership_open'
$confidentiality = 'confidentiality_low', 'confidentiality_medium', 'confidentiality_high'

$errors = @()
$warnings = @()
foreach ($f in $files) {
  $fileName = $f.FullName.Substring($rootFull.Path.Length + 1)
  $raw = Get-Content -LiteralPath $f.FullName -Raw
  try { 
    $json = $raw | ConvertFrom-Json -ErrorAction Stop 
  }
  catch { 
    $errors += "$fileName : Invalid JSON (${($_.Exception.Message)})";
    continue 
  }
  foreach ($rp in $requiredTop) {
    if (-not ($json.PSObject.Properties.Name -contains $rp)) { 
      $errors += "$fileName : Missing property '$rp'" 
    } 
  }
  if ($json.path -and ($json.path -notmatch '^[a-z0-9-_/]+$')) {
    $errors += "$fileName : : path invalid format" 
  }
  if ($json.path -and $json.path.Length -gt 80) { 
    $errors += "$fileName : path exceeds 80 chars" 
  }
  if ($json.description) { 
    if ($json.description.Length -lt 5 -or $json.description.Length -gt 500) { 
      $errors += "$fileName : description length out of bounds" 
    } 
  }
  if ($json.service_url) {
    foreach ($e in $requiredEnv) { 
      if (-not ($json.service_url.PSObject.Properties.Name -contains $e)) { 
        $errors += "$fileName : service_url missing env '$e'" 
      } 
    }
    foreach ($e in $requiredEnv) {
      $u = $json.service_url.$e; 
      if (-not $u) { 
        $warnings += "$fileName : service_url.$e empty"; 
        continue 
      }; 
      if ($u -notmatch '^https://') { 
        $warnings += "$fileName : service_url.$e must start with https://" 
      } 
    }
  }
  else { 
    $errors += "$fileName : service_url missing" 
  }
  if ($json.tags) {
    if (-not ($json.tags -is [System.Collections.IEnumerable])) { 
      $errors += "$fileName : tags not an array"; 
      continue 
    }
    $tagArr = @($json.tags)
    if ($tagArr.Count -ne 3) { 
      $errors += "$fileName : tags must have exactly 3 entries (have $($tagArr.Count))" 
    }
    if (@($tagArr | Select-Object -Unique).Count -ne $tagArr.Count) { 
      $errors += "$fileName : duplicate tags detected"
    }
    if (-not ($tagArr | Where-Object { $audience -contains $_ })) { 
      $errors += "$fileName : missing audience_* tag" 
    }
    if (-not ($tagArr | Where-Object { $ownership -contains $_ })) { 
      $errors += "$fileName : missing ownership_* tag" 
    }
    if (-not ($tagArr | Where-Object { $confidentiality -contains $_ })) { 
      $errors += "$fileName : missing confidentiality_* tag" 
    }
  }
  else { 
    $errors += "$fileName : tags missing"
  }
  if (-not ($errors | Where-Object { $_ -like "$($f.FullName):*" })) { 
    Write-Ok "OK: $($f.FullName.Substring($rootFull.Path.Length+1))"
  } 
}
if ($warnings.Count -gt 0) { 
  Write-Warn "Validation warnings:"; $warnings | Sort-Object | ForEach-Object { Write-Warn " - $_" } 
}
if ($errors.Count -gt 0) { 
  Write-Err "Validation failed:"; $errors | Sort-Object | ForEach-Object { Write-Err " - $_" }; 
  exit 1 
}
Write-Info "All apiDefinition.json files passed validation."; 
exit 0
