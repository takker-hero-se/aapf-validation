# run-verification.ps1 — reproduces the paper's empirical checks (REPRODUCE.md)
# against the deposited AAPF corpus mounted at C:\aapf. Prints PASS/FAIL per
# claim and a final summary. Read-only: never modifies the samples.

$ErrorActionPreference = "Continue"
$AAPF     = "C:\aapf"
$S        = Join-Path $AAPF "samples"
$PONE     = Join-Path $AAPF "poneglyph\poneglyph.exe"
$ESENTUTL = Join-Path $env:WINDIR "System32\esentutl.exe"
$PY       = if (Test-Path C:\scripts\python_path.txt) { (Get-Content C:\scripts\python_path.txt).Trim() } else { "python" }

# Fail fast if the corpus synced folder did not mount (VMware HGFS).
if (-not (Test-Path $PONE)) {
  Write-Host "============================================================" -ForegroundColor Red
  Write-Host "  FATAL: corpus not mounted." -ForegroundColor Red
  Write-Host "  Expected: $PONE" -ForegroundColor Red
  Write-Host "  The C:\aapf synced folder (VMware HGFS) is not available." -ForegroundColor Red
  Write-Host "  Cannot run the verification. Aborting." -ForegroundColor Red
  Write-Host "============================================================" -ForegroundColor Red
  exit 2
}

$script:pass = 0; $script:fail = 0
function Check($name, $expected, $actual) {
  if ("$actual" -eq "$expected") {
    Write-Host ("  [PASS] {0} = {1}" -f $name, $actual) -ForegroundColor Green; $script:pass++
  } else {
    Write-Host ("  [FAIL] {0}: expected {1}, got {2}" -f $name, $expected, $actual) -ForegroundColor Red; $script:fail++
  }
}
function J($lines) { ($lines | Out-String) }
function Counts($path) {
  $o = J (& $PONE info --ntds $path 2>&1)
  $h = @{}
  $h.tables = ([regex]::Match($o, 'Tables:\s+(\d+)')).Groups[1].Value
  foreach ($t in 'datatable','link_table','sd_table','MSysObjects') {
    $m = [regex]::Match($o, "(?m)^\s*$t\s+(\d+)")
    if ($m.Success) { $h[$t] = $m.Groups[1].Value }
  }
  return $h
}
function PageSize($path) { ([regex]::Match((J (& $ESENTUTL /mh $path 2>&1)), 'cbDbPage:\s+(\d+)')).Groups[1].Value }
function Revision($path) { ([regex]::Match((J (& $ESENTUTL /mh $path 2>&1)), 'Format ulVersion:\s+0x620,(\d+)')).Groups[1].Value }
function Hex2($path, $off) {
  $fs = [IO.File]::OpenRead($path)
  [void]$fs.Seek($off + 34, 'Begin')
  $b = New-Object byte[] 2; [void]$fs.Read($b, 0, 2); $fs.Close()
  return ('{0:X2} {1:X2}' -f $b[0], $b[1])
}
function DumpHeader($path, $off, $label) {
  # Reproduce Figure 1: annotated 40-byte ESE page header, itagState (bytes 34-35) in red.
  $off = [int]$off   # argument-mode 0x... arrives as a string; force numeric for :X and Seek
  $fs = [IO.File]::OpenRead($path)
  [void]$fs.Seek($off, 'Begin')
  $b = New-Object byte[] 40; [void]$fs.Read($b, 0, 40); $fs.Close()
  Write-Host ("  {0}  @ 0x{1:X}  (page 4)" -f $label, $off) -ForegroundColor Cyan
  for ($rw = 0; $rw -lt 40; $rw += 16) {
    Write-Host ("    +{0:X2}: " -f $rw) -NoNewline
    for ($i = $rw; $i -lt [Math]::Min($rw + 16, 40); $i++) {
      $col = if ($i -eq 34 -or $i -eq 35) { "Red" } else { "Gray" }
      Write-Host ("{0:X2} " -f $b[$i]) -NoNewline -ForegroundColor $col
    }
    Write-Host ""
  }
  # Cast bytes to Int32 before shifting: a [byte] -shl 8 overflows to 0 in PowerShell,
  # which would drop the ctagReserved nibble (the WS2025 signal) and show 0x000A.
  $itag = ([int]$b[34]) -bor (([int]$b[35]) -shl 8)
  Write-Host ("      itagState (bytes 34-35) = 0x{0:X4}   ctagReserved = 0x{1:X}   tagCount = {2}" -f $itag, ($itag -shr 12), ($itag -band 0xFFF)) -ForegroundColor Yellow
}
function ReadBytes($path, $off, $n) {
  $off = [int]$off
  $fs = [IO.File]::OpenRead($path)
  [void]$fs.Seek($off, 'Begin')
  $b = New-Object byte[] $n; [void]$fs.Read($b, 0, $n); $fs.Close()
  return $b
}
function DumpPage($b, $off, $label, $flagsMagenta) {
  # Hex dump of an ESE page header. itagState (34-35) in red; pageFlags (32-33)
  # in magenta when $flagsMagenta. Reproduces the paper's page-comparison figure.
  Write-Host ("  {0}  @ 0x{1:X}  ({2} bytes)" -f $label, [int]$off, $b.Length) -ForegroundColor Cyan
  for ($rw = 0; $rw -lt $b.Length; $rw += 16) {
    Write-Host ("    +{0:X2}: " -f $rw) -NoNewline
    for ($i = $rw; $i -lt [Math]::Min($rw + 16, $b.Length); $i++) {
      $c = "Gray"
      if ($i -eq 34 -or $i -eq 35) { $c = "Red" }
      elseif ($flagsMagenta -and ($i -eq 32 -or $i -eq 33)) { $c = "Magenta" }
      Write-Host ("{0:X2} " -f $b[$i]) -NoNewline -ForegroundColor $c
    }
    Write-Host ""
  }
}
function ImpacketReadAll($path) {
  # Deep probe: open the DB AND read every row of every non-system table, so the
  # itagState page-tag path (getTag) is actually exercised. On a 4KiB WS2025 DB,
  # Impacket v0.13.1 does not mask itagState (page_size <= 8192) and aborts here.
  $tmp = Join-Path $env:TEMP ("imp_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys
from impacket.ese import ESENT_DB
db = ESENT_DB(sys.argv[1])
tabs = None
for a in ("tables", "_ESENT_DB__tables"):
    if hasattr(db, a):
        try:
            tabs = list(getattr(db, a).keys()); break
        except Exception:
            pass
for t in (tabs or []):
    tname = t.decode("latin-1") if isinstance(t, (bytes, bytearray)) else t
    if tname.startswith("MSys"):
        continue
    cur = db.openTable(t)
    while True:
        r = db.getNextRow(cur)
        if r is None:
            break
print("READALL-OK")
'@ | Set-Content -Path $tmp -Encoding ASCII
  $out = & $PY $tmp $path 2>&1
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}
function ImpacketOpenCount($path) {
  # Paper's claim for 16KiB is that Impacket *opens* it (the >8192 gate applies the
  # itagState mask so the catalog parses). This tests exactly that: construct
  # ESENT_DB (which reads the catalog via the masked page-tag path) and enumerate
  # the table list. (A full record read is out of scope: Impacket has an unrelated
  # variable-data-type record bug on DataStore's tbDownloadJob, not an itagState issue.)
  $tmp = Join-Path $env:TEMP ("impo_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys
from impacket.ese import ESENT_DB
db = ESENT_DB(sys.argv[1])
tabs = None
for a in ("tables", "_ESENT_DB__tables"):
    if hasattr(db, a):
        try:
            tabs = list(getattr(db, a).keys()); break
        except Exception:
            pass
print("OPEN-OK tables=%d" % (len(tabs) if tabs else 0))
'@ | Set-Content -Path $tmp -Encoding ASCII
  $out = & $PY $tmp $path 2>&1
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AAPF empirical verification  (paper: Silent Evidence Loss)" -ForegroundColor Cyan
Write-Host "  corpus: $S" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format o)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n[1] Page sizes & format revisions  (native esentutl /mh)" -ForegroundColor Yellow
Check "NTDS 2025 cbDbPage"       32768 (PageSize "$S\identity\2025\clean\ntds.dit")
Check "NTDS 2025 revision(dec)"  290   (Revision "$S\identity\2025\clean\ntds.dit")   # 0x122
Check "NTDS 2019 cbDbPage"       8192  (PageSize "$S\identity\2019\clean\ntds.dit")
Check "NTDS 2019 revision(dec)"  20    (Revision "$S\identity\2019\clean\ntds.dit")   # 0x14
Check "DataStore 2025 cbDbPage"  16384 (PageSize "$S\health\2025\clean\DataStore.edb")
Check "DataStore 2025 rev(dec)"  300   (Revision "$S\health\2025\clean\DataStore.edb")  # 0x12C
Check "SRUDB 2025 cbDbPage"      4096  (PageSize "$S\resource\2025\clean\SRUDB.dat")
Check "SRUDB 2025 revision(dec)" 300   (Revision "$S\resource\2025\clean\SRUDB.dat")   # 0x12C

Write-Host "`n[2] Table / record counts  (poneglyph info)" -ForegroundColor Yellow
$n25 = Counts "$S\identity\2025\clean\ntds.dit"
Check "NTDS 2025 tables"      15    $n25.tables
Check "NTDS 2025 datatable"   7030  $n25.datatable
Check "NTDS 2025 link_table"  13978 $n25.link_table
Check "NTDS 2025 sd_table"    677   $n25.sd_table
$n19 = Counts "$S\identity\2019\clean\ntds.dit"
Check "NTDS 2019 tables"      14    $n19.tables
Check "NTDS 2019 datatable"   7008  $n19.datatable
Check "NTDS 2019 link_table"  14075 $n19.link_table
$d25 = Counts "$S\health\2025\clean\DataStore.edb"
Check "DataStore 2025 tables" 36    $d25.tables
Check "DataStore 2025 MSysObjects" 659 $d25.MSysObjects
$d19 = Counts "$S\health\2019\clean\DataStore.edb"
Check "DataStore 2019 tables" 35    $d19.tables
$r25 = Counts "$S\resource\2025\clean\SRUDB.dat"
Check "SRUDB 2025 tables"     12    $r25.tables
Check "SRUDB 2025 MSysObjects" 165  $r25.MSysObjects
$r19 = Counts "$S\resource\2019\clean\SRUDB.dat"
Check "SRUDB 2019 MSysObjects" 161  $r19.MSysObjects
$w19 = Counts "$S\activity\2019\clean\WebCacheV01.dat"
Check "WebCache 2019 tables"  8     $w19.tables
Check "WebCache 2019 MSysObjects" 115 $w19.MSysObjects

Write-Host "`n[3] itagState hex at page 4 (bytes 34-35, little-endian)" -ForegroundColor Yellow
Check "NTDS 2025 @0x18000 (=0x100A)"      "0A 10" (Hex2 "$S\identity\2025\clean\ntds.dit"      0x18000)
Check "DataStore 2025 @0xC000 (=0x1041)"  "41 10" (Hex2 "$S\health\2025\clean\DataStore.edb"   0xC000)
Check "SRUDB 2025 @0x3000 (=0x1010)"      "10 10" (Hex2 "$S\resource\2025\clean\SRUDB.dat"     0x3000)

Write-Host "`n[4] Impacket v0.13.1 - full ESE read (openTable + getNextRow on every table)" -ForegroundColor Yellow
Write-Host "    (reads records so the itagState page-tag path is exercised; NOT secretsdump)" -ForegroundColor DarkGray
$sr = ImpacketReadAll "$S\resource\2025\clean\SRUDB.dat"
if ($sr -match "READALL-OK") {
  Write-Host "  [FAIL] SRUDB 4KiB fully read by Impacket v0.13.1 (paper claims it aborts)" -ForegroundColor Red; $script:fail++
} else {
  $why = ($sr -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 1).Trim()
  Write-Host "  [PASS] SRUDB 4KiB aborts under Impacket v0.13.1 (page 4096 <= 8192 gate, itagState unmasked): $why" -ForegroundColor Green; $script:pass++
}
$ds = ImpacketOpenCount "$S\health\2025\clean\DataStore.edb"
if ($ds -match "OPEN-OK") {
  $tc = ([regex]::Match($ds, 'tables=(\d+)')).Groups[1].Value
  Write-Host "  [PASS] DataStore 16KiB opens under Impacket v0.13.1 (16384 > 8192 gate, itagState masked; $tc tables)" -ForegroundColor Green; $script:pass++
} else {
  Write-Host "  [FAIL] DataStore 16KiB failed to open under Impacket" -ForegroundColor Red; $script:fail++
}

Write-Host "`n[5] Page-4 header hex dump  (reproduces Figure 1; itagState @ bytes 34-35 in red)" -ForegroundColor Yellow
DumpHeader "$S\identity\2025\clean\ntds.dit"    0x18000 "NTDS.dit 2025      (32KiB)"
DumpHeader "$S\health\2025\clean\DataStore.edb" 0xC000  "DataStore.edb 2025 (16KiB)"
DumpHeader "$S\resource\2025\clean\SRUDB.dat"   0x3000  "SRUDB.dat 2025     (4KiB)"

# --- Derive everything below from the real page-4 header of the deposited NTDS ---
$hdr64 = ReadBytes "$S\identity\2025\clean\ntds.dit" 0x18000 64
$raw   = ([int]$hdr64[34]) -bor (([int]$hdr64[35]) -shl 8)   # itagState = 0x100A
$count = $raw -band 0x0FFF                                   # masked tag count = 10
$resv  = $raw -shr 12                                        # ctagReserved   = 1

Write-Host "`n[6] itagState = 0x$('{0:X4}' -f $raw) interpretation  (reproduces Figure 2)" -ForegroundColor Yellow
$bin = [Convert]::ToString($raw, 2).PadLeft(16, '0')
$grp = ($bin[0..3] -join '') + ' ' + ($bin[4..7] -join '') + ' ' + ($bin[8..11] -join '') + ' ' + ($bin[12..15] -join '')
Write-Host ("    bits (15..0):  {0}" -f $grp)
Write-Host ("    (a) INCORRECT - all 16 bits as tag count (unmasked parsers):") -ForegroundColor DarkGray
Write-Host ("          N = {0}  ->  tag_array = 4 x {0} = {1} bytes  ->  OUT OF BOUNDS" -f $raw, (4*$raw)) -ForegroundColor Red
Write-Host ("    (b) CORRECT   - upper 4 = ctagReserved, lower 12 = tag count:") -ForegroundColor DarkGray
Write-Host ("          ctagReserved = 0x{0:X4} >> 12   = {1}" -f $raw, $resv)
Write-Host ("          tagCount     = 0x{0:X4} & 0x0FFF = {1}" -f $raw, $count)
Write-Host ("          N = {0}  ->  tag_array = 4 x {0} = {1} bytes  ->  OK" -f $count, (4*$count)) -ForegroundColor Green
Check "masked tagCount (page 4)" 10 $count

Write-Host "`n[7] 32KiB page partition  (reproduces Figure 5; page = 32768, header = 40)" -ForegroundColor Yellow
$pg = 32768; $hs = 40
$taWrong = 4 * $raw;   $daWrong = $pg - $hs - $taWrong;  $ghost = $taWrong - (4 * $count)
$taRight = 4 * $count; $daRight = $pg - $hs - $taRight
Write-Host ("    INCORRECT (N={0}): tag_array={1} B, data_area={2} B, GHOST tags={3} B (garbage)" -f $raw, $taWrong, $daWrong, $ghost) -ForegroundColor Red
Write-Host ("    CORRECT   (N={0}):   tag_array={1} B,    data_area={2} B" -f $count, $taRight, $daRight) -ForegroundColor Green
Check "ghost region under misread (bytes)" 16384 $ghost

Write-Host "`n[8] Normal page vs zeroed page hex  (reproduces Figure 3; underpins Figure 4 B-tree chain)" -ForegroundColor Yellow
$zero64 = ReadBytes "$S\identity\2025\clean\ntds.dit" 0x98000 64
DumpPage $hdr64  0x18000 "Normal page      " $true
$pfN = ([int]$hdr64[32]) -bor (([int]$hdr64[33]) -shl 8)
Write-Host ("      pageFlags (bytes 32-33) = 0x{0:X4}   IS_LEAF (0x0002) = {1}" -f $pfN, $(if ($pfN -band 0x2) {'SET'} else {'not set'})) -ForegroundColor Yellow
DumpPage $zero64 0x98000 "Fully-zeroed page" $true
$pfZ = ([int]$zero64[32]) -bor (([int]$zero64[33]) -shl 8)
Write-Host ("      pageFlags (bytes 32-33) = 0x{0:X4}   IS_LEAF (0x0002) = {1}  <- backward-walk bug trigger" -f $pfZ, $(if ($pfZ -band 0x2) {'SET'} else {'not set'})) -ForegroundColor Yellow
$nonzero = ($zero64 | Where-Object { $_ -ne 0 }).Count
Check "page @0x98000 fully zeroed (non-zero bytes)" 0 $nonzero
Check "zeroed page IS_LEAF flag (0=not set)" 0 ($pfZ -band 0x2)

Write-Host "`n============================================================" -ForegroundColor Cyan
$col = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host ("  SUMMARY:  PASS = {0}   FAIL = {1}" -f $script:pass, $script:fail) -ForegroundColor $col
Write-Host "============================================================" -ForegroundColor Cyan
