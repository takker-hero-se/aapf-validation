# verify_pagesize.ps1 — Verify ESE page sizes across the AAPF dataset
#
# Reproduces the page-size footnotes in Tables 1 and 5 of the companion paper.
# Calls Windows' native esentutl /mh on each sample and extracts cbDbPage.

$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
$SamplesDir = Join-Path $Root 'samples'

if (-not (Test-Path $SamplesDir)) {
    Write-Error "Samples directory not found at $SamplesDir. Are you running from the extracted Zenodo record?"
    exit 1
}

$Targets = Get-ChildItem -Path $SamplesDir -Recurse -Include 'ntds.dit', 'DataStore.edb', 'WebCacheV01.dat', 'SRUDB.dat' -File

if ($Targets.Count -eq 0) {
    Write-Error "No ESE samples found under $SamplesDir."
    exit 1
}

Write-Host "Verifying page sizes for $($Targets.Count) ESE samples..." -ForegroundColor Cyan
Write-Host ""

$Results = foreach ($file in $Targets) {
    $relativePath = $file.FullName.Substring($Root.Length + 1)
    $mhOutput = & esentutl /mh "$($file.FullName)" 2>&1 | Out-String
    $cbPage = ($mhOutput -split "`r?`n" | Where-Object { $_ -match '^\s*cbDbPage:\s*(\d+)' }) -replace '^\s*cbDbPage:\s*', ''
    $state = ($mhOutput -split "`r?`n" | Where-Object { $_ -match '^\s*State:\s*(.+)$' }) -replace '^\s*State:\s*', ''

    [PSCustomObject]@{
        Path        = $relativePath
        cbDbPage    = $cbPage[0]
        Shutdown    = ($state[0] -replace ',.*$', '').Trim()
    }
}

$Results | Format-Table -AutoSize

Write-Host ""
Write-Host "Expected mapping (per MANIFEST.md):" -ForegroundColor Cyan
Write-Host "  identity/ntds.dit               8192 (WS2019) / 32768 (WS2025)"
Write-Host "  health/DataStore.edb           16384 (both OS versions)"
Write-Host "  activity/WebCacheV01.dat       32768 (WS2019)"
Write-Host "  resource/SRUDB.dat              4096 (both OS versions)"
Write-Host ""
Write-Host "Shutdown state convention:" -ForegroundColor Cyan
Write-Host "  Clean: Clean Shutdown"
Write-Host "  Crashed: Clean Shutdown (NTDS Stop-Service performs a graceful close)"
Write-Host "  Locked: Dirty Shutdown (VSS snapshot of running process)"
