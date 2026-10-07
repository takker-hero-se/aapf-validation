<#
.SYNOPSIS
  Can a legacy (pre-WS2025) 32KiB ESE page carry more than 4,095 tags?

.DESCRIPTION
  Reproduces the tag-count bound and the measurement cited in the paper's
  Section 5 ("Why gate on the revision rather than mask unconditionally").

  Theory, from the engine's own accounting (microsoft/Extensible-Storage-Engine,
  node.hxx and cpage.hxx): every node costs cbNDNullKeyData = cbKeyCount (2) +
  TAG (4) = 6 bytes even with a null key and no data; the usable page space is
  CbPageDataMax(32768) = (32768 - 80) - 4 * ctagReservedLegacy - cbInsertionOverhead
  = 32,680 bytes. A page therefore holds at most floor(32680 / (6 + key + data))
  tags. Counting four bytes per tag alone would give 8,172, but the engine never
  allocates a tag without a line.

  Measurement, from the deposited 32KiB samples: for every data page, the tag
  count the header declares and, from the tag array itself, the size of each
  value, so the maximum real tag count and the minimum real node size are
  observed rather than assumed. Legacy layout (WS2019, revision 0x0014): the
  16-bit field at header offset 34 is the tag count. WS2025 layout: the lower
  12 bits of itagState. Tags on pages of 16KiB and above carry a 15-bit size.

.NOTES
  Run from anywhere; sample paths resolve relative to this script.
  Expected result (2026-10-07): WS2019 WebCacheV01.dat max 116 tags/page,
  Win11 25H2 WebCacheV01.dat max 498, WS2025 ntds.dit max 2,514. None exceeds 4,095.
#>
[CmdletBinding()]
param()

$PageSize = 32768
$Header   = 80          # extended header on 16KiB/32KiB pages
$Tag      = 4
$DataMax  = ($PageSize - $Header) - $Tag * 1 - $Tag   # CbPageDataMax(32768) = 32680

$root = Join-Path $PSScriptRoot '..\samples'
$samples = @(
    @{ Title = 'WS2019 WebCacheV01.dat (legacy 32KiB, rev 0x0014)'; Path = Join-Path $root 'activity\2019\clean\WebCacheV01.dat';     Layout = 'legacy' },
    @{ Title = 'Win11 25H2 WebCacheV01.dat (32KiB, rev 0x012C)';     Path = Join-Path $root 'activity\w11-25h2\clean\WebCacheV01.dat'; Layout = 'new' },
    @{ Title = 'WS2025 ntds.dit (32KiB, rev 0x0122)';                 Path = Join-Path $root 'identity\2025\clean\ntds.dit';           Layout = 'new' }
)

Write-Output '=== Theory: nodes per 32KiB page, by minimum node size ==='
Write-Output ("  usable data+tag space CbPageDataMax(32768) = {0} bytes" -f $DataMax)
foreach ($row in @(
    @{ Label = 'engine floor: null key, no data (2 + 4)';                      Bytes = 6 },
    @{ Label = '+ 4-byte record header, zero key (table leaf)';                Bytes = 10 },
    @{ Label = '+ 4-byte DBK key + 4-byte record header';                      Bytes = 14 },
    @{ Label = 'tag only, no key-count word (never allocated by the engine)'; Bytes = 4 }
)) {
    $n = [math]::Floor($DataMax / $row.Bytes)
    $verdict = if ($n -gt 4095) { '> 4095' } else { '<= 4095' }
    Write-Output ("  {0,-60} {1,3} bytes/node -> max {2,5} tags  {3}" -f $row.Label, $row.Bytes, $n, $verdict)
}
Write-Output ''

foreach ($s in $samples) {
    if (-not (Test-Path -LiteralPath $s.Path)) {
        Write-Output ("{0}: file not found ({1})" -f $s.Title, $s.Path)
        continue
    }
    $bytes  = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $s.Path).Path)
    $npages = [math]::Floor($bytes.Length / $PageSize)
    $maxTags = 0; $maxTagsPage = $null; $minNonZero = $null
    $zeroTags = 0; $tagsTotal = 0; $pagesNonEmpty = 0
    $hist = @{}
    # pages 0 and 1 are the database/shadow header; data pages start at 2
    for ($p = 2; $p -lt $npages; $p++) {
        $base = $p * $PageSize
        $raw  = [BitConverter]::ToUInt16($bytes, $base + 34)
        $ntags = if ($s.Layout -eq 'new') { $raw -band 0x0FFF } else { $raw }
        if ($ntags -eq 0 -or $ntags -gt [math]::Floor(($PageSize - $Header) / $Tag)) { continue }
        # a page that is all zero bytes has ntags == 0 and is skipped above
        $pagesNonEmpty++
        $tagsTotal += $ntags
        if ($ntags -gt $maxTags) { $maxTags = $ntags; $maxTagsPage = $p }
        $bucket = [int]([math]::Floor($ntags / 100) * 100)
        $hist[$bucket] = 1 + $(if ($hist.ContainsKey($bucket)) { $hist[$bucket] } else { 0 })
        for ($i = 0; $i -lt $ntags; $i++) {
            $off   = $base + $PageSize - $Tag * ($i + 1)
            $vsize = [BitConverter]::ToUInt16($bytes, $off + 2) -band 0x7FFF
            if ($vsize -eq 0) { $zeroTags++ }
            elseif ($null -eq $minNonZero -or $vsize -lt $minNonZero) { $minNonZero = $vsize }
        }
    }
    $verdict = if ($maxTags -gt 4095) { 'exceeds' } else { 'below' }
    Write-Output ("=== {0} ===" -f $s.Title)
    Write-Output ("  pages: {0} (non-empty data pages: {1}), tags total: {2}" -f $npages, $pagesNonEmpty, $tagsTotal)
    Write-Output ("  max tags on one page: {0} (page {1})  -> {2} 4095" -f $maxTags, $maxTagsPage, $verdict)
    Write-Output ("  min non-zero value size: {0} bytes; zero-size tags: {1}" -f $minNonZero, $zeroTags)
    $h = ($hist.Keys | Sort-Object | ForEach-Object { "{0}-{1}:{2}" -f $_, ($_ + 99), $hist[$_] }) -join ', '
    Write-Output ("  tag-count histogram (per 100): {0}" -f $h)
    Write-Output ''
}
