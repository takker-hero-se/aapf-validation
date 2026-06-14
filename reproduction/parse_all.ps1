# parse_all.ps1 — Reproduce the Schema Robustness rows of Table 5
#
# Walks every ESE sample in this Zenodo record, runs poneglyph.exe info,
# and reports the table count and key record counts. Compare the output
# to expected_outputs.txt to verify byte-identical reproduction.

$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
$SamplesDir = Join-Path $Root 'samples'
$Poneglyph = Join-Path $Root 'poneglyph\poneglyph.exe'

if (-not (Test-Path $Poneglyph)) {
    Write-Error "poneglyph.exe not found at $Poneglyph"
    exit 1
}
if (-not (Test-Path $SamplesDir)) {
    Write-Error "Samples directory not found at $SamplesDir"
    exit 1
}

$Targets = Get-ChildItem -Path $SamplesDir -Recurse -Include 'ntds.dit', 'DataStore.edb', 'WebCacheV01.dat', 'SRUDB.dat' -File |
    Sort-Object FullName

Write-Host "Parsing $($Targets.Count) ESE samples with universal-patched libesedb..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $Targets) {
    $relativePath = $file.FullName.Substring($Root.Length + 1)
    Write-Host "=== $relativePath ===" -ForegroundColor Yellow

    $rawOutput = & "$Poneglyph" info --ntds "$($file.FullName)" 2>&1 | Out-String
    $lines = $rawOutput -split "`r?`n"

    # Skip the banner; preserve the database header, table list, and any errors
    $start = $false
    foreach ($line in $lines) {
        if ($line -match '^Database:') { $start = $true }
        if ($start) {
            if ($line -match '^(Database:|Tables:|Name\s+Records|-+|\S+\s+\d+|\s*$|Error:|Caused by:)') {
                Write-Host $line
            }
        }
    }
    Write-Host ""
}

Write-Host "Done. Compare against reproduction/expected_outputs.txt for verification." -ForegroundColor Cyan
