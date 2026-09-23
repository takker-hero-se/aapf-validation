# run-verification.ps1 -- reproduces the paper's empirical checks (REPRODUCE.md)
# against the deposited AAPF corpus mounted at C:\aapf. Prints PASS/FAIL per
# claim and a final summary. Read-only: never modifies the samples.
#
# -ClientOnly runs section [9] alone. The generation sandbox emits its samples in
# the same layout the client axis uses here, so pointing AAPF_CORPUS at a freshly
# generated tree and passing this switch verifies new samples with the very
# assertions that cover the deposited ones. Without it a generated tree would
# fail sections [1]-[8], which look for server samples it does not contain.
param([switch]$ClientOnly)

$ErrorActionPreference = "Continue"
# AAPF_ROOT lets this run on the host, against an extracted record, with no VM.
# That matters more than it looks: every logic defect in this script used to cost
# a 20-35 minute VM cycle to find, and 6 of 16 of those cycles never reached the
# script at all because the guest timed out booting. The VM run is what produces
# the recorded evidence; it should not also be the debugger.
$AAPF     = if ($env:AAPF_ROOT) { $env:AAPF_ROOT } else { "C:\aapf" }
$S        = Join-Path $AAPF "samples"
$PONE     = Join-Path $AAPF "poneglyph\poneglyph.exe"
$ESENTUTL = Join-Path $env:WINDIR "System32\esentutl.exe"
$PY       = if ($env:AAPF_PYTHON) { $env:AAPF_PYTHON }
            elseif (Test-Path C:\scripts\python_path.txt) { (Get-Content C:\scripts\python_path.txt).Trim() }
            else { "python" }

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
# Invariants get Check: an exact value the format guarantees. Environment-dependent
# observations must NOT be written as exact values -- the client SRUDB carried 15,
# 15 and 16 tables across three independent generations (the sixteenth being an
# empty SRUM push-notification provider table), and WebCache moved between 25 and
# 27 with the guest's WinINet use. Asserting those as constants turns a legitimate
# reproduction into a reported mismatch, which is how the paper ended up claiming
# "all fifteen tables". Assert the floor, record the value.
function CheckAtLeast($name, $min, $actual) {
  if ([int]$actual -ge [int]$min) {
    Write-Host ("  [PASS] {0} = {1}  (>= {2}, environment-dependent)" -f $name, $actual, $min) -ForegroundColor Green; $script:pass++
  } else {
    Write-Host ("  [FAIL] {0}: expected at least {1}, got {2}" -f $name, $min, $actual) -ForegroundColor Red; $script:fail++
  }
}
# Recorded as evidence, deliberately not asserted.
function Observe($name, $value) {
  Write-Host ("  [note] {0} = {1}" -f $name, $value) -ForegroundColor DarkGray
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
  Write-Host ("  {0}  @ 0x{1:X}  (page 2)" -f $label, $off) -ForegroundColor Cyan
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
function ImpacketReadAll($path, $interp) {
  # Deep probe: open the DB AND read every row of every non-system table, so the
  # itagState page-tag path (getTag) is actually exercised. On a 4KiB WS2025 DB,
  # Impacket v0.13.1 does not mask itagState (page_size <= 8192) and aborts here.
  #
  # PROBE-READY is printed only once Python has started, Impacket has imported and
  # the database is where we expect it. The caller requires it: without a sentinel,
  # "no READALL-OK" cannot be told apart from "the probe never ran", and a missing
  # interpreter would silently confirm the paper's claim.
  $tmp = Join-Path $env:TEMP ("imp_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys, os
from impacket.ese import ESENT_DB
if not os.path.isfile(sys.argv[1]):
    print("PROBE-NOFILE %s" % sys.argv[1]); sys.exit(2)
print("PROBE-READY"); sys.stdout.flush()
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
  if (-not $interp) { $interp = $PY }
  # A probe that cannot even start must come back as text we can classify.
  # Letting CommandNotFoundException escape here once left $PY pointing at a
  # bogus path for the rest of the run, and every later Impacket check failed.
  try   { $out = & $interp $tmp $path 2>&1 }
  catch { $out = "PROBE-LAUNCH-FAILED: " + $_.Exception.Message }
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}

function ImpacketSecrets($ntdsPath, $systemPath, $ponePath) {
  # Runs secretsdump's library path over the same (ntds, SYSTEM) pair Poneglyph
  # read, and compares NT hash values per RID against Poneglyph's output.
  # Returns counts only: the hashes themselves never leave the guest's temp file,
  # because this run is recorded to video and the video is deposited.
  #
  # SECRETS-READY proves the probe started. SECRETS-DONE proves it finished; if
  # dump() raises, the reason is printed and the caller reports it rather than
  # reading "0 compared, 0 mismatched" as agreement.
  #
  # useVSSMethod=$true is what makes this read the local ntds.dit at all. Without
  # it NTDSHashes takes the remote DRSUAPI path, needs a remoteOps it does not
  # have, and yields nothing -- which is exactly what the first run produced.
  $tmp = Join-Path $env:TEMP ("sd_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys, io, re, contextlib, traceback
from impacket.examples.secretsdump import LocalOperations, NTDSHashes
ntds, system, ponefile = sys.argv[1], sys.argv[2], sys.argv[3]
print("SECRETS-READY"); sys.stdout.flush()

imp = {}
def cb(secretType, secret, username=None, secretItem=None):
    m = re.match(r"^([^:]+):(\d+):([0-9a-fA-F]{32}):([0-9a-fA-F]{32})", str(secret))
    if m:
        imp[int(m.group(2))] = m.group(4).lower()

try:
    lo = LocalOperations(system)
    boot = lo.getBootKey()
    n = NTDSHashes(ntds, boot, isRemote=False, useVSSMethod=True,
                   justNTLM=True, printUserStatus=False, perSecretCallback=cb)
    with contextlib.redirect_stdout(io.StringIO()):
        n.dump()
        n.finish()
except Exception as e:
    print("SECRETS-ERROR %s: %s" % (type(e).__name__, e))
    traceback.print_exc(file=sys.stdout)
    sys.exit(3)

pone = {}
try:
    with open(ponefile, "r", errors="replace") as fh:
        for line in fh:
            m = re.match(r"^([^:]+):(\d+):([0-9a-fA-F]{32}):([0-9a-fA-F]{32})", line.strip())
            if m:
                pone[int(m.group(2))] = m.group(4).lower()
except Exception as e:
    print("SECRETS-ERROR reading poneglyph output: %s" % e)
    sys.exit(3)

common = set(pone) & set(imp)
mismatch = sum(1 for r in common if pone[r] != imp[r])
print("total=%d common=%d mismatch=%d" % (len(imp), len(common), mismatch))
print("SECRETS-DONE")
'@ | Set-Content -Path $tmp -Encoding ASCII
  try   { $out = & $PY $tmp $ntdsPath $systemPath $ponePath 2>&1 }
  catch { $out = "PROBE-LAUNCH-FAILED: " + $_.Exception.Message }
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}

function ImpacketOpenCount($path, $interp) {
  # Paper's claim for 16KiB is that Impacket *opens* it (the >8192 gate applies the
  # itagState mask so the catalog parses). This tests exactly that: construct
  # ESENT_DB (which reads the catalog via the masked page-tag path) and enumerate
  # the table list. (A full record read is out of scope: Impacket has an unrelated
  # variable-data-type record bug on DataStore's tbDownloadJob, not an itagState issue.)
  # PROBE-READY carries the same meaning as in ImpacketReadAll.
  $tmp = Join-Path $env:TEMP ("impo_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys, os
from impacket.ese import ESENT_DB
if not os.path.isfile(sys.argv[1]):
    print("PROBE-NOFILE %s" % sys.argv[1]); sys.exit(2)
print("PROBE-READY"); sys.stdout.flush()
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
  if (-not $interp) { $interp = $PY }
  # A probe that cannot even start must come back as text we can classify.
  # Letting CommandNotFoundException escape here once left $PY pointing at a
  # bogus path for the rest of the run, and every later Impacket check failed.
  try   { $out = & $interp $tmp $path 2>&1 }
  catch { $out = "PROBE-LAUNCH-FAILED: " + $_.Exception.Message }
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AAPF empirical verification  (paper: Silent Evidence Loss)" -ForegroundColor Cyan
Write-Host "  corpus: $S" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format o)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "`n[0] Negative controls  (each of these MUST trip)" -ForegroundColor Yellow
Write-Host "    A check that cannot fail cannot pass either. These feed deliberately" -ForegroundColor DarkGray
Write-Host "    corrupted input to the SAME helpers the counted checks use, and require the" -ForegroundColor DarkGray
Write-Host "    result to differ from the real one. They are reported separately and do" -ForegroundColor DarkGray
Write-Host "    not count toward the total." -ForegroundColor DarkGray
$script:ctlOk = 0; $script:ctlBad = 0
function Control($name, $tripped) {
  if ($tripped) {
    Write-Host ("  [OK]     {0}" -f $name) -ForegroundColor Green; $script:ctlOk++
  } else {
    Write-Host ("  [BROKEN] {0} -- the matching check cannot fail" -f $name) -ForegroundColor Red; $script:ctlBad++
  }
}

$scratch = Join-Path $env:TEMP ("aapf_ctl_" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
  # (a) Section [3] reads itagState at bytes 34-35 of page 2. Corrupt exactly
  #     those two bytes in a copy and Hex2 must report something else.
  $srudb = "$S\resource\2025\clean\SRUDB.dat"
  $realHex = Hex2 $srudb 0x3000
  $buf = ReadBytes $srudb 0 0x3040
  $buf[0x3000 + 34] = 0xFF; $buf[0x3000 + 35] = 0xFF
  $mutA = Join-Path $scratch 'itagstate.bin'
  [IO.File]::WriteAllBytes($mutA, $buf)
  Control ("itagState corruption at page 2 is visible (real $realHex -> " + (Hex2 $mutA 0x3000) + ")") `
          ((Hex2 $mutA 0x3000) -ne $realHex)

  # (b) Section [8] asserts the page at 0x98000 is entirely zero. Put one byte
  #     back in a copy; the non-zero count must move off zero.
  $ntds = "$S\identity\2025\clean\ntds.dit"
  $zbuf = ReadBytes $ntds 0 0x98040
  $zbuf[0x98000 + 10] = 0x01
  $mutB = Join-Path $scratch 'zeropage.bin'
  [IO.File]::WriteAllBytes($mutB, $zbuf)
  $mutNonZero = ((ReadBytes $mutB 0x98000 64) | Where-Object { $_ -ne 0 }).Count
  Control "a single non-zero byte in the zeroed page is counted (0 -> $mutNonZero)" ($mutNonZero -ne 0)

  # (c) The one that matters most. Section [4] used to read ANY non-clean outcome
  #     as "Impacket aborted, as the paper says" -- including the probe never
  #     running at all. Point it at an interpreter that does not exist: the output
  #     must lack PROBE-READY, which is what [4] now refuses to accept as a result.
  $dead = ImpacketReadAll $srudb (Join-Path $scratch 'no-such-python.exe')
  Control "an Impacket probe that never ran is not counted as an abort" ($dead -notmatch 'PROBE-READY')
}
finally {
  Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($ClientOnly) {
  Write-Host "`n[1]-[8] skipped: -ClientOnly verifies the client axis alone." -ForegroundColor DarkGray
} else {
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

Write-Host "`n[3] itagState hex at page 2 (bytes 34-35, little-endian)" -ForegroundColor Yellow
Check "NTDS 2025 @0x18000 (=0x100A)"      "0A 10" (Hex2 "$S\identity\2025\clean\ntds.dit"      0x18000)
Check "DataStore 2025 @0xC000 (=0x1041)"  "41 10" (Hex2 "$S\health\2025\clean\DataStore.edb"   0xC000)
Check "SRUDB 2025 @0x3000 (=0x1010)"      "10 10" (Hex2 "$S\resource\2025\clean\SRUDB.dat"     0x3000)
# The catalog root (MSysObjects FDP) is page 4, at (4+1)*32768 = 0x28000. This is
# the page the unpatched parser actually aborts on, and it carries the same
# reinterpreted itagState (0x1006: ctagReserved=1, tag count=6) as page 2 above,
# so the change is not confined to the page the figures happen to dump.
Check "NTDS 2025 @0x28000 catalog root (=0x1006)" "06 10" (Hex2 "$S\identity\2025\clean\ntds.dit" 0x28000)

# Impacket's version is MEASURED, not assumed. This log is evidence: a hard-coded
# "v0.13.1" would keep printing after a pip upgrade quietly replaced the parser
# under test. provision.ps1 pins 0.13.1; this reports what actually got installed.
function ImpacketVersion {
  $tmp = Join-Path $env:TEMP ("impv_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
v = None
try:
    from importlib.metadata import version as _v
    v = _v("impacket")
except Exception:
    pass
if not v:
    try:
        import impacket.version as iv
        v = getattr(iv, "VERSION", None)
        if not v:
            b = getattr(iv, "BANNER", "")
            v = b.strip().split()[-1] if b else None
    except Exception:
        pass
print(v or "UNKNOWN")
'@ | Set-Content -Path $tmp -Encoding ASCII
  $out = (& $PY $tmp 2>&1 | Out-String).Trim()
  Remove-Item $tmp -ErrorAction SilentlyContinue
  if (-not $out) { $out = "UNKNOWN" }
  return $out
}
$IMPV = ImpacketVersion
if ($IMPV -ne "0.13.1") {
  Write-Host "  [WARN] impacket $IMPV is installed; every claim below was measured" -ForegroundColor Yellow
  Write-Host "         against 0.13.1, which provision.ps1 pins. Results may differ." -ForegroundColor Yellow
}

Write-Host "`n[4] Impacket v$IMPV - full ESE read (openTable + getNextRow on every table)" -ForegroundColor Yellow
Write-Host "    (reads records so the itagState page-tag path is exercised; NOT secretsdump)" -ForegroundColor DarkGray

# The paper's claim is specific: Impacket does not merely fail on the 4KiB
# database, it aborts inside getTag with a struct.error, because page_size 4096
# does not satisfy its `> 8192` gate and itagState is therefore never masked.
# Assert exactly that. The previous form was `if READALL-OK { FAIL } else { PASS }`,
# which reported PASS for ANY outcome that was not a clean read -- a missing
# interpreter, an unimported Impacket or a mistyped path all "confirmed" the
# paper. PROBE-READY proves the probe ran; the message match proves it failed
# for the reason claimed.
$expectedAbort = 'unpack requires a buffer of 2 bytes'
$sr = ImpacketReadAll "$S\resource\2025\clean\SRUDB.dat"
$last = ($sr -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
if ($last) { $last = $last.Trim() }
if ($sr -notmatch 'PROBE-READY') {
  Write-Host "  [FAIL] SRUDB 4KiB: the Impacket probe never ran, so this proves nothing: $last" -ForegroundColor Red; $script:fail++
} elseif ($sr -match 'READALL-OK') {
  Write-Host "  [FAIL] SRUDB 4KiB fully read by Impacket v$IMPV (paper claims it aborts)" -ForegroundColor Red; $script:fail++
} elseif ($sr -notmatch [regex]::Escape($expectedAbort)) {
  Write-Host "  [FAIL] SRUDB 4KiB aborted, but not the way the paper describes (expected '$expectedAbort'): $last" -ForegroundColor Red; $script:fail++
} else {
  Write-Host "  [PASS] SRUDB 4KiB aborts under Impacket v$IMPV (page 4096 <= 8192 gate, itagState unmasked): $last" -ForegroundColor Green; $script:pass++
}

$ds = ImpacketOpenCount "$S\health\2025\clean\DataStore.edb"
if ($ds -notmatch 'PROBE-READY') {
  Write-Host "  [FAIL] DataStore 16KiB: the Impacket probe never ran, so this proves nothing" -ForegroundColor Red; $script:fail++
} elseif ($ds -match "OPEN-OK") {
  $tc = ([regex]::Match($ds, 'tables=(\d+)')).Groups[1].Value
  Write-Host "  [PASS] DataStore 16KiB opens under Impacket v$IMPV (16384 > 8192 gate, itagState masked; $tc tables)" -ForegroundColor Green; $script:pass++
} else {
  Write-Host "  [FAIL] DataStore 16KiB failed to open under Impacket" -ForegroundColor Red; $script:fail++
}

Write-Host "`n[5] Page-2 header hex dump  (reproduces Figure 1; itagState @ bytes 34-35 in red)" -ForegroundColor Yellow
DumpHeader "$S\identity\2025\clean\ntds.dit"    0x18000 "NTDS.dit 2025      (32KiB)"
DumpHeader "$S\health\2025\clean\DataStore.edb" 0xC000  "DataStore.edb 2025 (16KiB)"
DumpHeader "$S\resource\2025\clean\SRUDB.dat"   0x3000  "SRUDB.dat 2025     (4KiB)"

# --- Derive everything below from the real page-2 header of the deposited NTDS ---
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
Write-Host ("    (b) CORRECT   - upper nibble = ctagReserved (3 bits) + reserved bit 15, lower 12 = tag count:") -ForegroundColor DarkGray
Write-Host ("          ctagReserved = 0x{0:X4} >> 12   = {1}" -f $raw, $resv)
Write-Host ("          tagCount     = 0x{0:X4} & 0x0FFF = {1}" -f $raw, $count)
Write-Host ("          N = {0}  ->  tag_array = 4 x {0} = {1} bytes  ->  OK" -f $count, (4*$count)) -ForegroundColor Green
Check "masked tagCount (page 2)" 10 $count

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
}

Write-Host "`n[9] Client axis (w11-25h2)  -- the 4/16/32 KiB spectrum on one client" -ForegroundColor Yellow
Write-Host "    The paper's client-applicability claim rests on these three databases," -ForegroundColor DarkGray
Write-Host "    and until now nothing checked them: sections [1]-[8] only look at the" -ForegroundColor DarkGray
Write-Host "    server samples. The layout is the same one the generation sandbox emits," -ForegroundColor DarkGray
Write-Host "    so pointing AAPF_CORPUS at a freshly generated tree (with -ClientOnly)" -ForegroundColor DarkGray
Write-Host "    verifies new samples with this very section." -ForegroundColor DarkGray

$C = @(
  @{ n = 'SRUDB.dat';       p = "$S\resource\w11-25h2\clean\SRUDB.dat";       ps = 4096;  floor = 15 },
  @{ n = 'DataStore.edb';   p = "$S\health\w11-25h2\clean\DataStore.edb";     ps = 16384; floor = 36 },
  @{ n = 'WebCacheV01.dat'; p = "$S\activity\w11-25h2\clean\WebCacheV01.dat"; ps = 32768; floor = 25 }
)
$missing = @($C | Where-Object { -not (Test-Path $_.p) })
if ($missing.Count -gt 0) {
  # Loud, not skipped. A section that quietly does nothing is the same defect as a
  # check that cannot fail.
  foreach ($m in $missing) {
    Write-Host ("  [FAIL] client sample missing: {0}" -f $m.p) -ForegroundColor Red; $script:fail++
  }
} else {
  $seen = @()
  foreach ($c in $C) {
    Check   ("client {0} cbDbPage" -f $c.n)      $c.ps  (PageSize $c.p)
    Check   ("client {0} revision(dec)" -f $c.n) 300    (Revision $c.p)
    $cnt = (Counts $c.p).tables
    if ($c.n -eq 'DataStore.edb') {
      Check ("client {0} tables" -f $c.n) $c.floor $cnt
    } else {
      CheckAtLeast ("client {0} tables" -f $c.n) $c.floor $cnt
    }
    Observe ("client {0} MSysObjects" -f $c.n) (Counts $c.p).MSysObjects
    $seen += [int](PageSize $c.p)
  }
  # The claim is the spectrum itself: all three page sizes, all at one revision,
  # on a single client.
  Check "client page-size spectrum" "4096,16384,32768" ((($seen | Sort-Object { [int]$_ }) -join ','))

  $cs = "$S\resource\w11-25h2\clean\SRUDB.dat"
  $cd = "$S\health\w11-25h2\clean\DataStore.edb"
  $csr = ImpacketReadAll $cs
  $lastC = ($csr -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
  if ($lastC) { $lastC = $lastC.Trim() }
  if ($csr -notmatch 'PROBE-READY') {
    Write-Host "  [FAIL] client SRUDB: the Impacket probe never ran, so this proves nothing: $lastC" -ForegroundColor Red; $script:fail++
  } elseif ($csr -match 'READALL-OK') {
    Write-Host "  [FAIL] client SRUDB 4KiB fully read by Impacket v$IMPV (paper claims it aborts)" -ForegroundColor Red; $script:fail++
  } elseif ($csr -notmatch [regex]::Escape($expectedAbort)) {
    Write-Host "  [FAIL] client SRUDB 4KiB aborted, but not the way the paper describes: $lastC" -ForegroundColor Red; $script:fail++
  } else {
    Write-Host "  [PASS] client SRUDB 4KiB aborts under Impacket v$IMPV : $lastC" -ForegroundColor Green; $script:pass++
  }
  $cdo = ImpacketOpenCount $cd
  if ($cdo -notmatch 'PROBE-READY') {
    Write-Host "  [FAIL] client DataStore: the Impacket probe never ran, so this proves nothing" -ForegroundColor Red; $script:fail++
  } elseif ($cdo -match 'OPEN-OK') {
    $ctc = ([regex]::Match($cdo, 'tables=(\d+)')).Groups[1].Value
    Write-Host "  [PASS] client DataStore 16KiB opens under Impacket v$IMPV ($ctc tables)" -ForegroundColor Green; $script:pass++
  } else {
    Write-Host "  [FAIL] client DataStore 16KiB failed to open under Impacket" -ForegroundColor Red; $script:fail++
  }
}

Write-Host "`n[10] Credential value fidelity  (Poneglyph vs Impacket, counts only)" -ForegroundColor Yellow
Write-Host "     The paper reports that every account Poneglyph emits decrypts to the same" -ForegroundColor DarkGray
Write-Host "     bytes Impacket produces. That claim was verified once, by hand, and" -ForegroundColor DarkGray
Write-Host "     deposited as reproduction/hash_value_validation.txt; nothing re-derived it." -ForegroundColor DarkGray
Write-Host "     NOTHING BELOW PRINTS A HASH. This run is screen-recorded and the video is" -ForegroundColor DarkGray
Write-Host "     deposited, so only counts and a match verdict reach the log; the extracted" -ForegroundColor DarkGray
Write-Host "     values live in a temp file that is deleted before the section returns." -ForegroundColor DarkGray

$hashScratch = Join-Path $env:TEMP ("aapf_hash_" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $hashScratch | Out-Null
try {
  foreach ($h in @(
      @{ os = '2019'; pone = 2494; imp = 2595 },
      @{ os = '2025'; pone = 2492; imp = 2593 })) {
    $ntds = "$S\identity\$($h.os)\clean\ntds.dit"
    $sys  = "$S\identity\$($h.os)\clean\SYSTEM"
    if (-not (Test-Path $ntds) -or -not (Test-Path $sys)) {
      Write-Host ("  [FAIL] WS{0}: ntds.dit or SYSTEM hive missing" -f $h.os) -ForegroundColor Red; $script:fail++
      continue
    }
    $pf = Join-Path $hashScratch ("p" + $h.os + ".txt")
    & $PONE hashes --ntds $ntds --system $sys -o $pf 2>&1 | Out-Null
    if (-not (Test-Path $pf)) {
      Write-Host ("  [FAIL] WS{0}: Poneglyph produced no hash output, so this proves nothing" -f $h.os) -ForegroundColor Red; $script:fail++
      continue
    }
    $rows = @(Get-Content $pf | Where-Object { $_ -match ':' })
    Check ("WS{0} accounts emitted by Poneglyph" -f $h.os) $h.pone $rows.Count

    # $pf is Poneglyph's output, which the probe reads to compare per RID.
    # This argument was a path Poneglyph never wrote, so the probe died on an
    # open() and the section reported nothing useful until it said why.
    $ir = ImpacketSecrets $ntds $sys $pf
    $tail = ($ir -split "`n" | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
    if ($tail) { $tail = $tail.Trim() }
    if ($ir -notmatch 'SECRETS-READY') {
      Write-Host ("  [FAIL] WS{0}: the Impacket probe never started, so this proves nothing: {1}" -f $h.os, $tail) -ForegroundColor Red; $script:fail++
      continue
    }
    if ($ir -notmatch 'SECRETS-DONE') {
      # An extraction that died partway must not be scored as agreement.
      Write-Host ("  [FAIL] WS{0}: the Impacket extraction did not complete: {1}" -f $h.os, $tail) -ForegroundColor Red; $script:fail++
      continue
    }
    $itotal   = [int]([regex]::Match($ir, 'total=(\d+)').Groups[1].Value)
    $common   = [int]([regex]::Match($ir, 'common=(\d+)').Groups[1].Value)
    $mismatch = [int]([regex]::Match($ir, 'mismatch=(\d+)').Groups[1].Value)
    Check ("WS{0} accounts emitted by Impacket" -f $h.os) $h.imp $itotal
    Check ("WS{0} common RIDs compared" -f $h.os) $h.pone $common
    # Zero mismatches out of zero comparisons is not agreement. The first version
    # of this section passed on exactly that, while Impacket had returned nothing.
    if ($common -lt 1) {
      Write-Host ("  [FAIL] WS{0} value mismatches: nothing was compared, so 0 mismatches means nothing" -f $h.os) -ForegroundColor Red; $script:fail++
    } else {
      Check ("WS{0} value mismatches (of {1} compared)" -f $h.os, $common) 0 $mismatch
    }
  }
}
finally {
  # The extracted material never outlives the section.
  Remove-Item $hashScratch -Recurse -Force -ErrorAction SilentlyContinue
}


Write-Host "`n[11] Three-parser record-count agreement  (patched libesedb vs impacket.ese vs dissect.esedb)" -ForegroundColor Yellow
Write-Host "     Table 5 and the integrity table report counts our patched parser produced," -ForegroundColor DarkGray
Write-Host "     and a reviewer is entitled to ask whether the patch merely makes libesedb" -ForegroundColor DarkGray
Write-Host "     agree with itself. This section re-derives the same four tables with two" -ForegroundColor DarkGray
Write-Host "     parsers that share no code with it: Impacket's pure-Python ESE reader and" -ForegroundColor DarkGray
Write-Host "     Fox-IT's dissect.esedb. The counts below are compared, not assumed." -ForegroundColor DarkGray

# dissect.esedb: independent reimplementation, pure Python.
function DissectCounts($path) {
  $tmp = Join-Path $env:TEMP ("dis_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys, os
try:
    from dissect.esedb import EseDB
except Exception as e:
    print("PROBE-NOLIB %s" % e); sys.exit(3)
if not os.path.isfile(sys.argv[1]):
    print("PROBE-NOFILE %s" % sys.argv[1]); sys.exit(2)
print("PROBE-READY"); sys.stdout.flush()
with open(sys.argv[1], "rb") as fh:
    db = EseDB(fh)
    names = [t.name for t in db.tables()]
    print("tables=%d" % len(names))
    for n in ("datatable", "link_table", "sd_table", "MSysObjects"):
        if n not in names:
            print("%s=MISSING" % n); continue
        c = 0
        for _r in db.table(n).records():
            c += 1
        print("%s=%d" % (n, c))
print("DISSECT-OK")
'@ | Set-Content -Path $tmp -Encoding ASCII
  try   { $out = & $PY $tmp $path 2>&1 }
  catch { $out = "PROBE-LAUNCH-FAILED: " + $_.Exception.Message }
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}

# impacket.ese: the same reader section [4] uses, here counting rows per table.
function ImpacketCounts($path) {
  $tmp = Join-Path $env:TEMP ("impc_" + [IO.Path]::GetRandomFileName() + ".py")
  @'
import sys, os
from impacket.ese import ESENT_DB
if not os.path.isfile(sys.argv[1]):
    print("PROBE-NOFILE %s" % sys.argv[1]); sys.exit(2)
print("PROBE-READY"); sys.stdout.flush()
db = ESENT_DB(sys.argv[1])
tabs = None
for a in ("tables", "_ESENT_DB__tables"):
    if hasattr(db, a):
        try:
            tabs = list(getattr(db, a).keys()); break
        except Exception:
            pass
names = []
for t in (tabs or []):
    names.append(t.decode("latin-1") if isinstance(t, (bytes, bytearray)) else t)
print("tables=%d" % len(names))
for n in ("datatable", "link_table", "sd_table", "MSysObjects"):
    if n not in names:
        print("%s=MISSING" % n); continue
    cur = db.openTable(n)
    c = 0
    while True:
        r = db.getNextRow(cur)
        if r is None:
            break
        c += 1
    print("%s=%d" % (n, c))
print("IMPACKET-OK")
'@ | Set-Content -Path $tmp -Encoding ASCII
  try   { $out = & $PY $tmp $path 2>&1 }
  catch { $out = "PROBE-LAUNCH-FAILED: " + $_.Exception.Message }
  Remove-Item $tmp -ErrorAction SilentlyContinue
  return (J $out)
}

# No "$" anchor: Out-String leaves a \r before each \n, so "(\d+)$" would
# never match. Counts() above omits the anchor for the same reason.
function KV($text, $key) {
  $m = [regex]::Match($text, ("(?m)^\s*" + [regex]::Escape($key) + "\s*=\s*(\d+)"))
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return $null
}

foreach ($nt in @(
  @{ os = '2019'; path = "$S\identity\2019\clean\ntds.dit" },
  @{ os = '2025'; path = "$S\identity\2025\clean\ntds.dit" }
)) {
  Write-Host ("  -- WS{0} {1}" -f $nt.os, (Split-Path $nt.path -Leaf)) -ForegroundColor DarkGray
  $poneCnt = Counts $nt.path   # NOT $pone: that would clobber $PONE
  $dis  = DissectCounts $nt.path
  $imp  = ImpacketCounts $nt.path

  # A probe that never ran must not be read as agreement.
  if ($dis -notmatch 'PROBE-READY') {
    Write-Host ("  [FAIL] WS{0} dissect.esedb probe did not run: {1}" -f $nt.os, (($dis -split "`n")[0])) -ForegroundColor Red
    $script:fail++
  } elseif ($imp -notmatch 'PROBE-READY') {
    Write-Host ("  [FAIL] WS{0} impacket probe did not run: {1}" -f $nt.os, (($imp -split "`n")[0])) -ForegroundColor Red
    $script:fail++
  } else {
    foreach ($tbl in 'datatable','link_table','sd_table','MSysObjects') {
      $p = $null
      if ($poneCnt.ContainsKey($tbl)) { $p = [int]$poneCnt[$tbl] }
      $d = KV $dis $tbl
      $i = KV $imp $tbl
      if ($null -eq $p) {
        Write-Host ("  [FAIL] WS{0} {1}: patched libesedb returned no count" -f $nt.os, $tbl) -ForegroundColor Red
        $script:fail++
        continue
      }
      Check ("WS{0} {1}: dissect.esedb agrees with patched libesedb" -f $nt.os, $tbl) $p $d
      Check ("WS{0} {1}: impacket.ese agrees with patched libesedb"  -f $nt.os, $tbl) $p $i
    }
  }
}

Write-Host "`n============================================================" -ForegroundColor Cyan
$col = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host ("  SUMMARY:  PASS = {0}   FAIL = {1}" -f $script:pass, $script:fail) -ForegroundColor $col
if ($script:ctlBad -gt 0) {
  Write-Host ("  NEGATIVE CONTROLS: {0} of {1} did NOT trip -- treat every PASS above as unproven" -f $script:ctlBad, ($script:ctlOk + $script:ctlBad)) -ForegroundColor Red
} else {
  Write-Host ("  Negative controls: {0}/{0} tripped, as they must" -f $script:ctlOk) -ForegroundColor DarkGray
}
Write-Host "============================================================" -ForegroundColor Cyan
