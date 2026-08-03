# generate_expected_outputs.ps1 -- Build reproduction/expected_outputs.txt
# from the per-sample validation files in samples/_validation/.
#
# Run AFTER tools/run_full_validation.ps1 has produced the 57 validation files.

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$ValDir = Join-Path $Root 'samples\_validation'
$OutFile = Join-Path $Root 'reproduction\expected_outputs.txt'

if (-not (Test-Path $ValDir)) { throw "Validation directory not found: $ValDir" }

# Same 19-sample order as run_full_validation.ps1
$Samples = @(
    @{ Cat='identity'; OS='2019'; State='clean';   Note='8KiB WS2019 baseline (Clean Shutdown)' },
    @{ Cat='identity'; OS='2019'; State='crashed'; Note='8KiB WS2019 -- Stop-Service NTDS produces Clean Shutdown (control for Section4.4)' },
    @{ Cat='identity'; OS='2019'; State='locked';  Note='8KiB WS2019 Dirty Shutdown (VSS) -- parses fully, contrast with 32KiB' },
    @{ Cat='identity'; OS='2025'; State='clean';   Note='32KiB WS2025 -- universal patch required for catalog read' },
    @{ Cat='identity'; OS='2025'; State='crashed'; Note='32KiB WS2025 -- Stop-Service produces Clean Shutdown; identical to Clean (R2-W3 rebuttal)' },
    @{ Cat='identity'; OS='2025'; State='locked';  Note='32KiB WS2025 Dirty (VSS) -- parses fully (15 tables, datatable 7030) with the revision-gated patch; State-Resilience discussion in Section8.5.3.' },

    @{ Cat='health';   OS='2019'; State='clean';   Note='16KiB WS2019' },
    @{ Cat='health';   OS='2019'; State='crashed'; Note='16KiB WS2019 -- extra log files captured; same parse' },
    @{ Cat='health';   OS='2019'; State='locked';  Note='16KiB WS2019' },
    @{ Cat='health';   OS='2025'; State='clean';   Note='16KiB WS2025 -- universal patch required (Issue 3)' },
    @{ Cat='health';   OS='2025'; State='crashed'; Note='16KiB WS2025 -- WU clean-detach makes this Clean-equivalent' },
    @{ Cat='health';   OS='2025'; State='locked';  Note='16KiB WS2025 -- 1-record snapshot drift on MSys tables' },

    @{ Cat='activity'; OS='2019'; State='clean';   Note='32KiB WS2019 -- WebCache uses 32KiB on WS2019 already (refutes "32K = WS2025 only")' },
    @{ Cat='activity'; OS='2019'; State='crashed'; Note='32KiB WS2019 -- WebCache cannot be cleanly stopped; all 3 states equivalent' },
    @{ Cat='activity'; OS='2019'; State='locked';  Note='32KiB WS2019' },

    @{ Cat='resource'; OS='2019'; State='clean';   Note='4KiB WS2019 -- Stop-Service DPS clean stop' },
    @{ Cat='resource'; OS='2019'; State='partial'; Note='4KiB WS2019 -- partial / mid-collection snapshot' },
    @{ Cat='resource'; OS='2025'; State='clean';   Note='4KiB WS2025 -- universal patch required (Issue 4)' },
    @{ Cat='resource'; OS='2025'; State='partial'; Note='4KiB WS2025 -- partial' }
)

$out = New-Object 'System.Collections.Generic.List[string]'

$out.Add('# Expected outputs for parse_all.ps1')
$out.Add('#')
$out.Add('# Auto-generated from samples/_validation/*.poneglyph.txt by tools/generate_expected_outputs.ps1.')
$out.Add('# Reviewer reproduction should match each section line-for-line modulo VSS-snapshot timing drift')
$out.Add('# (Locked states may differ by +-1 record; see REPRODUCE.md "Tolerance and known sources of nondeterminism").')
$out.Add('#')
$out.Add('# For each sample the canonical parse output is the corresponding _validation/<sample>.poneglyph.txt;')
$out.Add('# the per-page-size, per-shutdown-state metadata is in _validation/<sample>.esentutl.txt;')
$out.Add('# the zeroed-page distribution (R4 Section4.4 evidence) is in _validation/<sample>.zeroed.json.')
$out.Add('#')
$out.Add('')

foreach ($s in $Samples) {
    $stem = "$($s.Cat)-$($s.OS)-$($s.State)"
    $pgFile = Join-Path $ValDir "$stem.poneglyph.txt"
    if (-not (Test-Path $pgFile)) {
        $out.Add("# $stem -- MISSING validation output")
        $out.Add('')
        continue
    }

    $out.Add("# === $stem ===")
    $out.Add("# $($s.Note)")
    $out.Add('')

    # Read the .poneglyph.txt and extract the meaningful lines:
    # Database: ..., Tables: N, then the table list.
    $lines = Get-Content $pgFile -Encoding utf8
    $inBlock = $false
    foreach ($line in $lines) {
        if ($line -match '^Database:') { $inBlock = $true }
        if ($inBlock) {
            if ($line -match '^(Database:|Tables:|Name\s+Records|-+|\s*$|Error:|Caused by:|libesedb_|\S+\s+\d+)') {
                $out.Add($line.TrimEnd())
            }
        }
    }
    $out.Add('')
}

# Final summary statistics from zeroed-page JSON
$out.Add('# === Zeroed-page distribution summary (R4 Section4.4 evidence) ===')
$out.Add('# Format: <sample>  <page_size>  <total_pages>  <zeroed>  <ratio>')
$out.Add('')
foreach ($s in $Samples) {
    $stem = "$($s.Cat)-$($s.OS)-$($s.State)"
    $zFile = Join-Path $ValDir "$stem.zeroed.json"
    if (-not (Test-Path $zFile)) { continue }
    $j = (Get-Content $zFile -Raw) | ConvertFrom-Json
    $pageKB = "$($j.page_size_bytes/1024)K"
    $ratio = "$([Math]::Round($j.zeroed_pages_ratio * 100, 1))%"
    $line = ("# {0,-30} {1,-6} {2,6} {3,6} {4,8}" -f $stem, $pageKB, $j.total_pages, $j.zeroed_pages_count, $ratio)
    $out.Add($line)
}

$out | Set-Content -Path $OutFile -Encoding utf8

$lineCount = $out.Count
Write-Host "Wrote $OutFile" -ForegroundColor Green
Write-Host "  $lineCount lines covering 19 samples" -ForegroundColor Green
