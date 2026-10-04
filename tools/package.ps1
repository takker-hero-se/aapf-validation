# package.ps1 — Stage and hash the AAPF Zenodo deposit
#
# Run this script ONCE before uploading to Zenodo. It:
#   1. Copies the patches from C:\dev\libesedb-sys-patched\patches\
#   2. Copies the Poneglyph release binary from C:\dev\Poneglyph\target\release\
#   3. Copies the AAPF samples from C:\dev\aapf-samples\ (skipping the spurious identity$os dir)
#   4. Copies the _validation outputs
#   5. Computes SHA-256 for every file and rewrites MANIFEST.md
#   6. Optionally creates a single .zip archive for download
#
# Run from the staging root (the dir containing this script's parent):
#   cd C:\dev\aapf-validation
#   .\tools\package.ps1
#
# Flags:
#   -SkipCopy   Re-hash and regenerate MANIFEST.md without copying again
#   -Zip        Create aapf-validation-<Version>.zip at the end (slow for ~780 MB)
#   -Version    Version string for the zip name (default 1.1.0)
#   -DryRun     Print intended actions without executing them

[CmdletBinding()]
param(
    [switch]$SkipCopy,
    [switch]$Zip,
    [switch]$DryRun,
    [string]$Version = '1.1.0'
)

$ErrorActionPreference = 'Stop'

$StagingRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $StagingRoot 'README.md'))) {
    throw "Staging root must contain README.md — are you running from C:\dev\aapf-validation\tools\?"
}

Write-Host "Staging root: $StagingRoot" -ForegroundColor Cyan
Write-Host ""

# Source locations
$Sources = @(
    @{
        From = 'C:\dev\libesedb-sys-patched\patches'
        To   = (Join-Path $StagingRoot 'patches')
        Inc  = @('*.patch')
        Exc  = @('*.bak')
    },
    @{
        From = 'C:\dev\Poneglyph\target\release'
        To   = (Join-Path $StagingRoot 'poneglyph')
        Inc  = @('poneglyph.exe')
        Exc  = @()
    },
    @{
        From = 'C:\dev\aapf-samples\identity'
        To   = (Join-Path $StagingRoot 'samples\identity')
        Inc  = @()
        Exc  = @('_validation')   # Handled by the dedicated Sources entry below
    },
    @{
        From = 'C:\dev\aapf-samples\health'
        To   = (Join-Path $StagingRoot 'samples\health')
        Inc  = @()
        Exc  = @()
    },
    @{
        From = 'C:\dev\aapf-samples\activity'
        To   = (Join-Path $StagingRoot 'samples\activity')
        Inc  = @()
        Exc  = @()
    },
    @{
        From = 'C:\dev\aapf-samples\resource'
        To   = (Join-Path $StagingRoot 'samples\resource')
        Inc  = @()
        Exc  = @('final-via-blob.zip')   # Acquisition-pipeline archive; redundant with expanded files
    }
    # Note: samples\_validation\ contents are generated in-place by
    # tools\run_full_validation.ps1 after the samples are staged.
    # No copy step here.
)

if (-not $SkipCopy) {
    foreach ($s in $Sources) {
        if (-not (Test-Path $s.From)) {
            Write-Warning "Source not found, skipping: $($s.From)"
            continue
        }
        if (-not (Test-Path $s.To)) {
            if ($DryRun) {
                Write-Host "[DRY] mkdir $($s.To)" -ForegroundColor DarkGray
            } else {
                New-Item -ItemType Directory -Path $s.To -Force | Out-Null
            }
        }

        if ($s.Inc.Count -gt 0) {
            $files = Get-ChildItem -Path $s.From -Recurse -File -Include $s.Inc
        } else {
            $files = Get-ChildItem -Path $s.From -Recurse -File
        }
        foreach ($exc in $s.Exc) {
            # Match either by file name (e.g., '*.bak') or by directory name anywhere in path (e.g., '_validation')
            $files = $files | Where-Object {
                ($_.Name -notlike $exc) -and `
                ($_.FullName -notlike "*\$exc\*") -and `
                ($_.FullName -notlike "*/$exc/*")
            }
        }

        foreach ($f in $files) {
            $relativeFromSource = $f.FullName.Substring($s.From.Length).TrimStart('\','/')
            $dest = Join-Path $s.To $relativeFromSource
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path $destDir)) {
                if (-not $DryRun) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            }
            if ($DryRun) {
                Write-Host "[DRY] copy $($f.FullName) -> $dest" -ForegroundColor DarkGray
            } else {
                Copy-Item -Path $f.FullName -Destination $dest -Force
            }
        }
        Write-Host ("Staged {0,4} files from {1}" -f $files.Count, $s.From) -ForegroundColor Green
    }
    Write-Host ""
}

if ($DryRun) {
    Write-Host "Dry run complete; no manifest written." -ForegroundColor Yellow
    return
}

# Generate MANIFEST.md
Write-Host "Hashing all files in staging tree..." -ForegroundColor Cyan
# Repository housekeeping that is not part of the data record: excluded from
# both the manifest and the zip, so the manifest describes exactly the zip.
$RepoOnlyDirs  = @('.git', 'tools')
$RepoOnlyFiles = @('MANIFEST.md', 'UPLOAD_INSTRUCTIONS.md', 'SETUP_GITHUB.md',
                   'CONTRIBUTING.md', '.gitignore', '.gitattributes')
$allFiles = Get-ChildItem -Path $StagingRoot -Recurse -File -Force |
    Where-Object {
        $rel = $_.FullName.Substring($StagingRoot.Length + 1)
        $topDir = ($rel -split '[\\/]')[0]
        ($RepoOnlyDirs -notcontains $topDir) -and ($RepoOnlyFiles -notcontains $rel)
    } |
    Sort-Object FullName

$manifest = @()
$manifest += "# File Manifest"
$manifest += ""
$manifest += "Generated by ``tools/package.ps1`` on $(Get-Date -Format 'yyyy-MM-dd')."
$manifest += ""
$manifest += "All files SHA-256 hashed. Sizes in bytes."
$manifest += ""
$manifest += "| Path | Size | SHA-256 |"
$manifest += "|---|---:|---|"

$totalBytes = 0
foreach ($f in $allFiles) {
    $relPath = $f.FullName.Substring($StagingRoot.Length + 1) -replace '\\','/'
    $hash = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower()
    $manifest += "| ``$relPath`` | $($f.Length) | ``$hash`` |"
    $totalBytes += $f.Length
}

$manifest += ""
$manifest += "**Total**: $($allFiles.Count) files, $totalBytes bytes ($(("{0:N1}" -f ($totalBytes / 1MB))) MB)."

$manifestPath = Join-Path $StagingRoot 'MANIFEST.md'
$manifest | Out-File -FilePath $manifestPath -Encoding utf8 -Force
Write-Host "MANIFEST.md written: $($allFiles.Count) files, $(("{0:N1}" -f ($totalBytes / 1MB))) MB" -ForegroundColor Green
Write-Host ""

if ($Zip) {
    $zipName = "aapf-validation-$Version.zip"
    $zipPath = Join-Path (Split-Path -Parent $StagingRoot) $zipName
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    Write-Host "Creating $zipName (this may take several minutes for ~780 MB)..." -ForegroundColor Cyan
    $zipItems = Get-ChildItem -Path $StagingRoot -Force |
        Where-Object { ($RepoOnlyDirs -notcontains $_.Name) -and ($RepoOnlyFiles -notcontains $_.Name) -or ($_.Name -eq 'MANIFEST.md') } |
        ForEach-Object { $_.FullName }
    Compress-Archive -Path $zipItems -DestinationPath $zipPath -CompressionLevel Optimal
    $zipHash = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToLower()
    $zipSize = (Get-Item $zipPath).Length
    Write-Host ""
    Write-Host "Zip created:" -ForegroundColor Green
    Write-Host "  Path:   $zipPath"
    Write-Host "  Size:   $($zipSize) bytes ($(("{0:N1}" -f ($zipSize / 1MB))) MB)"
    Write-Host "  SHA-256: $zipHash"
}

Write-Host ""
Write-Host "Pre-upload checklist:" -ForegroundColor Yellow
Write-Host "  [ ] Pin BadBlood / PSWindowsUpdate / Playwright / Atomic Red Team versions in docs/BADBLOOD_PROVENANCE.md"
Write-Host "  [ ] Update Zenodo DOI placeholders (CITATION.cff, .zenodo.json, README.md, docs/PAPER.md)"
Write-Host "  [ ] Add author ORCID iDs to CITATION.cff and .zenodo.json"
Write-Host "  [ ] Verify ETHICAL_USE.md responsible disclosure timeline matches actual disclosure log"
Write-Host "  [ ] Spot-check 3 random files against MANIFEST.md SHA-256 to confirm integrity"
Write-Host ""
Write-Host "Done." -ForegroundColor Green
