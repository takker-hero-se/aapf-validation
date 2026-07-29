# scan_zeroed_pages.ps1 — Count fully-zeroed pages in an ESE database file
#
# Walks every page of an ESE file and reports counts and page numbers of
# pages whose every byte is 0x00 (a structurally "unallocated" page).
#
# Used to empirically validate that the B-tree IS_LEAF fix in
# zzz-fix-ws2025-btree.patch is not masking widespread corruption: if zeroed
# pages are rare across the AAPF testbed, then the page-847 case analyzed in
# Section 4 of the paper is a focused finding rather than an artifact of
# pervasive empty pages.
#
# Usage:
#   .\scan_zeroed_pages.ps1 -Path <db> [-PageSize <bytes>]
#   .\scan_zeroed_pages.ps1 -Path <db>                # auto-detect via esentutl /mh
#
# Output:
#   JSON object with: path, page_size_bytes, total_pages, zeroed_pages_count,
#   zeroed_page_numbers (1-based; up to 100 reported, truncated otherwise),
#   first_zeroed_page, last_zeroed_page.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [int]$PageSize = 0
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Path)) {
    throw "File not found: $Path"
}

if ($PageSize -eq 0) {
    # Auto-detect via esentutl /mh
    $mh = & esentutl /mh "$Path" 2>&1 | Out-String
    $line = ($mh -split "`r?`n" | Where-Object { $_ -match '^\s*cbDbPage:\s*(\d+)' })
    if (-not $line) { throw "Could not detect cbDbPage from esentutl /mh output for $Path" }
    $PageSize = [int]($line -replace '^\s*cbDbPage:\s*', '')
}

$file = Get-Item $Path
$totalPages = [Math]::Floor($file.Length / $PageSize)

$fs = [System.IO.File]::OpenRead($Path)
$buf = New-Object byte[] $PageSize
$zeroedPages = New-Object 'System.Collections.Generic.List[int]'

try {
    for ($pageNo = 1; $pageNo -le $totalPages; $pageNo++) {
        $offset = ($pageNo - 1) * $PageSize
        $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $read = $fs.Read($buf, 0, $PageSize)
        if ($read -ne $PageSize) { break }

        # Check if the page is all zeros.
        # Fast-path: scan as 64-bit integers (8x faster than byte-by-byte).
        $isZero = $true
        for ($i = 0; $i -lt $PageSize; $i += 8) {
            $v = [BitConverter]::ToInt64($buf, $i)
            if ($v -ne 0) { $isZero = $false; break }
        }
        if ($isZero) { $zeroedPages.Add($pageNo) }
    }
} finally {
    $fs.Close()
}

$truncated = $zeroedPages.Count -gt 100
$reportedPages = if ($truncated) { $zeroedPages.GetRange(0, 100) } else { $zeroedPages }

$result = [PSCustomObject]@{
    path                = $Path
    file_bytes          = $file.Length
    page_size_bytes     = $PageSize
    total_pages         = $totalPages
    zeroed_pages_count  = $zeroedPages.Count
    zeroed_pages_ratio  = if ($totalPages -gt 0) { [Math]::Round($zeroedPages.Count / $totalPages, 6) } else { 0 }
    first_zeroed_page   = if ($zeroedPages.Count -gt 0) { $zeroedPages[0] } else { $null }
    last_zeroed_page    = if ($zeroedPages.Count -gt 0) { $zeroedPages[$zeroedPages.Count - 1] } else { $null }
    zeroed_page_numbers = $reportedPages
    truncated_at_100    = $truncated
}

$result | ConvertTo-Json -Depth 4
