<#
.SYNOPSIS
  Upload one file into an existing Zenodo draft (new-version draft) via the REST API.
  Does NOT publish. Verifies the server-side MD5 against the local file afterwards.

.USAGE
  $env:ZENODO_TOKEN = '<personal access token with deposit:write>'
  .\tools\zenodo_upload_file.ps1 -DepositId 23344091 -File C:\dev\aapf-validation-1.1.1.zip

  The token is read from the environment only; it is never written to disk or printed.
  Create one at https://zenodo.org/account/settings/applications/tokens/new/ (scope: deposit:write).
#>
param(
    [Parameter(Mandatory = $true)][int]$DepositId,
    [Parameter(Mandatory = $true)][string]$File,
    [string]$ZenodoUrl = 'https://zenodo.org'
)

$ErrorActionPreference = 'Stop'

$token = $env:ZENODO_TOKEN
if (-not $token) { throw 'ZENODO_TOKEN is not set. Set $env:ZENODO_TOKEN first (scope deposit:write).' }
if (-not (Test-Path -LiteralPath $File)) { throw "File not found: $File" }

$name = [System.IO.Path]::GetFileName($File)
$size = (Get-Item -LiteralPath $File).Length
Write-Host ("Local file: {0} ({1:N0} bytes)" -f $name, $size)

# 1. Fetch the draft and its upload bucket
$headers = @{ Authorization = "Bearer $token" }
$dep = Invoke-RestMethod -Headers $headers -Uri "$ZenodoUrl/api/deposit/depositions/$DepositId" -Method Get
$bucket = $dep.links.bucket
if (-not $bucket) { throw 'Draft has no bucket link; is the deposit id right and the draft still open?' }
Write-Host "Draft title : $($dep.metadata.title)"
Write-Host "Draft state : $($dep.state)  version: $($dep.metadata.version)"
Write-Host "Bucket      : $bucket"

# 2. Stream the file with curl.exe (handles multi-hundred-MB bodies without buffering)
$curl = (Get-Command curl.exe -ErrorAction Stop).Source
Write-Host 'Uploading (this takes a few minutes for ~220 MB)...'
& $curl -sS --fail -H "Authorization: Bearer $token" -X PUT "$bucket/$name" --upload-file $File -o "$env:TEMP\zenodo_put.json"
if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE" }
$put = Get-Content "$env:TEMP\zenodo_put.json" -Raw | ConvertFrom-Json
Remove-Item "$env:TEMP\zenodo_put.json" -Force

# 3. Verify size and MD5
$remoteMd5 = ($put.checksum -replace '^md5:', '')
$localMd5 = (Get-FileHash -LiteralPath $File -Algorithm MD5).Hash.ToLower()
Write-Host ("Remote size : {0:N0}  checksum: {1}" -f $put.size, $put.checksum)
Write-Host ("Local  MD5  : {0}" -f $localMd5)
if ($put.size -ne $size) { throw 'Size mismatch between local file and Zenodo.' }
if ($remoteMd5 -ne $localMd5) { throw 'MD5 mismatch between local file and Zenodo.' }

Write-Host ''
Write-Host "OK: $name is attached to draft $DepositId and verified. Nothing has been published."
Write-Host "Review and press Publish at $ZenodoUrl/uploads/$DepositId"
