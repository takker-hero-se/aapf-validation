<#
.SYNOPSIS
    Survey the ESE page size and format revision of every ESE-backed database
    present on this host, not just the four the paper measures.

.DESCRIPTION
    The paper's finding is gated on the ESE *format revision*, not on page
    size, so the question "is artifact X affected?" reduces to "what revision
    does this copy of X carry?". That is a header read: no record is parsed
    and no database is modified.

    The paper deliberately does not generalise beyond the four artifacts it
    measures, because revision is not uniform -- NTDS.dit was 0x0122 while
    SRUDB.dat and DataStore.edb were 0x012C on the same system, and WS2019's
    32KiB WebCacheV01.dat sits below the gate entirely. This script is how
    that limitation gets closed: run it on a Windows Server 2025 host and on a
    Windows 11 24H2+ client and the answer is measured rather than inferred.

    Method, and why:
      * Every candidate is read through a single VSS shadow copy. The live
        files are held open by their owning services, so a direct read fails,
        and taking one shadow for all of them is cheaper than one per file.
      * esentutl /mh is the same header dump the verification harness uses
        (run-verification.ps1, sections [1] and [9]). /mm is NOT used: on
        ntds.dit it requires the Active Directory callback library ntdsai.dll
        and blocks on a modal dialog off a domain controller.
      * esentutl is resolved by absolute path. Impacket installs an
        esentutl.py into its Scripts directory, so a bare `esentutl` can
        resolve to that script on exactly the machines this work runs on.

    Read-only. It creates a shadow copy, reads headers, and deletes the
    shadow. It never writes to a live database and never runs /r recovery.

.PARAMETER Output
    TSV file to write. Defaults to .\ese_revision_survey.tsv

.PARAMETER KeepShadow
    Leave the VSS shadow copy in place (for follow-up acquisition).

.PARAMETER Sweep
    Do not stop at the candidate list. Walk the system directories, read the
    first bytes of every plausible file through the shadow, and report any
    whose header carries the ESE magic (0x89ABCDEF at +4) but which the
    candidate list did not name.

    This matters because the candidate list can only find databases someone
    thought to list, and ESE databases do not share an extension: .dit, .dat,
    .db, .mdb, .sdb and .edb are all in use. Without the sweep, "we found N ESE
    databases" means "N of the ones we looked for".

.EXAMPLE
    .\survey_ese_revisions.ps1 -Output C:\out\ese_revisions_ws2025.tsv
#>
[CmdletBinding()]
param(
    [string]$Output = (Join-Path (Get-Location) 'ese_revision_survey.tsv'),
    [switch]$KeepShadow,
    [switch]$Sweep
)

$ErrorActionPreference = 'Continue'

# Absolute path: a bare `esentutl` can resolve to Impacket's esentutl.py.
$ESENTUTL = Join-Path $env:WINDIR 'System32\esentutl.exe'
if (-not (Test-Path -LiteralPath $ESENTUTL)) { throw "esentutl not found at $ESENTUTL" }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run as Administrator: VSS and the protected paths both require it.' }

# ---------------------------------------------------------------------------
# Candidates. "Measured" marks the four the paper already reports; they are
# included as controls, so a run that disagrees with the paper is visible.
# ---------------------------------------------------------------------------
$profiles = @()
try {
    $profiles = Get-ChildItem 'C:\Users' -Directory -ErrorAction Stop |
        Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }
} catch {
    Write-Host ("  (could not enumerate user profiles; per-user WebCache will be skipped: {0})" -f `
        $_.Exception.Message) -ForegroundColor DarkGray
}

$candidates = New-Object System.Collections.Generic.List[object]
function Add-Cand([string]$path, [string]$artifact, [string]$role, [bool]$measured) {
    $candidates.Add([pscustomobject]@{
        Path = $path; Artifact = $artifact; Role = $role; Measured = $measured })
}

# --- the four the paper measures (controls) ---
Add-Cand 'C:\Windows\NTDS\ntds.dit'                                   'NTDS.dit (Active Directory)'        'DC'     $true
Add-Cand 'C:\Windows\System32\SRU\SRUDB.dat'                          'SRUDB.dat (SRUM)'                   'any'    $true
Add-Cand 'C:\Windows\SoftwareDistribution\DataStore\DataStore.edb'    'DataStore.edb (Windows Update)'     'any'    $true
foreach ($p in $profiles) {
    Add-Cand (Join-Path $p.FullName 'AppData\Local\Microsoft\Windows\WebCache\WebCacheV01.dat') `
             ("WebCacheV01.dat (Edge/IE legacy, user {0})" -f $p.Name) 'any' $true
}

# --- the ones the paper lists as untested ---
# Windows Search used ESE (Windows.edb) historically. On Windows 11 25H2 the
# index is SQLite (Windows.db, with -wal/-shm companions), so both are probed:
# "absent" for the .edb plus "not-ESE" for the .db is the migration, recorded
# rather than assumed.
Add-Cand 'C:\ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb' 'Windows.edb (Search index, legacy ESE)' 'any' $false
Add-Cand 'C:\ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.db'  'Windows.db (Search index, current)'     'any' $false
Add-Cand 'C:\Windows\System32\LogFiles\SUM\Current.mdb'               'UAL Current.mdb'                    'Server' $false
Add-Cand 'C:\Windows\System32\LogFiles\SUM\SystemIdentity.mdb'        'UAL SystemIdentity.mdb'             'Server' $false
Add-Cand 'C:\Windows\ADAM\adamntds.dit'                               'adamntds.dit (AD LDS)'              'Server' $false
Add-Cand 'C:\Windows\System32\dhcp\dhcp.mdb'                          'dhcp.mdb (DHCP Server)'             'Server' $false
Add-Cand 'C:\Windows\System32\wins\wins.mdt'                          'wins.mdt (WINS)'                    'Server' $false
Add-Cand 'C:\Windows\security\database\secedit.sdb'                   'secedit.sdb (security config)'      'any'    $false
Add-Cand 'C:\ProgramData\Microsoft\Network\Downloader\qmgr.db'        'qmgr.db (BITS queue)'               'any'    $false

# UAL also writes per-role GUID-named databases alongside Current.mdb.
if (Test-Path 'C:\Windows\System32\LogFiles\SUM') {
    Get-ChildItem 'C:\Windows\System32\LogFiles\SUM' -Filter *.mdb -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Current.mdb', 'SystemIdentity.mdb') } |
        ForEach-Object { Add-Cand $_.FullName ("UAL {0}" -f $_.Name) 'Server' $false }
}

# ---------------------------------------------------------------------------
# One shadow copy of C:, reused for every candidate.
# ---------------------------------------------------------------------------
Write-Host 'Creating VSS shadow of C:\ ...' -ForegroundColor Cyan
$vss    = [WMIClass]'root\cimv2:Win32_ShadowCopy'
$create = $vss.Create('C:\', 'ClientAccessible')
if ($create.ReturnValue -ne 0) { throw "VSS Create failed with code $($create.ReturnValue)" }
$shadow = Get-WmiObject Win32_ShadowCopy | Where-Object { $_.ID -eq $create.ShadowID }
if (-not $shadow) { throw "Could not locate shadow $($create.ShadowID)" }
$shadowDev = $shadow.DeviceObject
Write-Host "  shadow: $shadowDev" -ForegroundColor DarkGray

$scratch = Join-Path $env:TEMP ('esesurvey_' + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$rows = New-Object System.Collections.Generic.List[object]

try {
    foreach ($c in $candidates) {
        $verdict = ''; $page = ''; $rev = ''; $state = ''
        if (-not (Test-Path -LiteralPath $c.Path)) {
            # Absent is a result: it tells us the role is not installed here.
            $verdict = 'absent'
        } else {
            $rel = $c.Path.Substring(3)                      # strip "C:\"
            $src = "$shadowDev\$rel"
            $dst = Join-Path $scratch (Split-Path $c.Path -Leaf)
            # Copy-Item does not reliably understand \\?\GLOBALROOT; cmd copy does.
            & cmd.exe /c copy /y "$src" "$dst" > $null 2>&1
            if (-not (Test-Path -LiteralPath $dst)) {
                $verdict = 'unreadable'
            } else {
                $mh = & $ESENTUTL /mh $dst 2>&1 | Out-String
                $mPage = [regex]::Match($mh, 'cbDbPage:\s+(\d+)')
                $mRev  = [regex]::Match($mh, 'Format ulVersion:\s+0x([0-9a-fA-F]+),(\d+)')
                $mSt   = [regex]::Match($mh, 'State:\s+(.+?)\r?\n')
                if ($mPage.Success -and $mRev.Success) {
                    $verdict = 'ESE'
                    $page = $mPage.Groups[1].Value
                    $rev  = '0x{0:X4} ({1})' -f [int]$mRev.Groups[2].Value, $mRev.Groups[2].Value
                    if ($mSt.Success) { $state = $mSt.Groups[1].Value.Trim() }
                } else {
                    # Present and readable, but esentutl does not recognise it.
                    $verdict = 'not-ESE'
                }
                Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
            }
        }
        $gate = ''
        if ($verdict -eq 'ESE' -and $rev -match '\((\d+)\)') {
            $gate = if ([int]$Matches[1] -ge 290) { 'AT-OR-ABOVE-GATE' } else { 'below gate' }
        }
        $rows.Add([pscustomobject]@{
            Artifact = $c.Artifact; Role = $c.Role
            Measured = $(if ($c.Measured) { 'paper' } else { 'new' })
            Verdict = $verdict; PageSize = $page; Revision = $rev
            Gate = $gate; State = $state; Path = $c.Path })
        $col = switch ($verdict) { 'ESE' { 'Green' } 'absent' { 'DarkGray' } default { 'Yellow' } }
        Write-Host ("  [{0,-10}] {1,-42} page={2,-6} rev={3,-12} {4}" -f `
            $verdict, $c.Artifact, $page, $rev, $gate) -ForegroundColor $col
    }
    # -----------------------------------------------------------------------
    # Sweep: catch ESE databases the candidate list does not name.
    # Paths are enumerated on the LIVE filesystem (metadata reads work even on
    # files held open) and the header is then read through the shadow.
    # -----------------------------------------------------------------------
    if ($Sweep) {
        Write-Host ''
        Write-Host 'Sweeping for unlisted ESE databases ...' -ForegroundColor Cyan
        $exts  = @('.edb', '.dat', '.db', '.mdb', '.sdb', '.dit', '.stm')
        $roots = @('C:\Windows', 'C:\ProgramData', 'C:\Users')
        $known = @{}
        foreach ($c in $candidates) { $known[$c.Path.ToLower()] = $true }
        $seen = 0; $found = 0
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $exts -contains $_.Extension.ToLower() -and $_.Length -ge 65536 } |
              ForEach-Object {
                $seen++
                if ($known.ContainsKey($_.FullName.ToLower())) { return }
                # Evidence that merely sits on this host is not a finding about
                # this host: our own deposited corpus, anything collected from
                # another machine, and downloads. Without this the sweep reports
                # a domain controller's ntds.dit as if the workstation had one.
                if ($_.FullName -match '\\aapf-(samples|validation)\\|\\paper-ese-32k\\|\\research-papers\\|poneglyph-collect|\\Downloads\\|\\uploads\\') { return }
                $rel = $_.FullName.Substring(3)
                try {
                    $fs  = [IO.File]::Open("$shadowDev\$rel", 'Open', 'Read', 'ReadWrite')
                    $buf = New-Object byte[] 16
                    $n   = $fs.Read($buf, 0, 16)
                    $fs.Close()
                } catch { return }
                if ($n -lt 16) { return }
                # ulMagic 0x89ABCDEF at +4, little-endian on disk.
                if (-not ($buf[4] -eq 0xEF -and $buf[5] -eq 0xCD -and
                          $buf[6] -eq 0xAB -and $buf[7] -eq 0x89)) { return }
                $found++
                # Measure it too: a swept file with no revision would leave the
                # very question the survey exists to answer unanswered.
                $sPage = ''; $sRev = ''; $sGate = ''
                $sDst = Join-Path $scratch ('swept_' + [IO.Path]::GetRandomFileName() + $_.Extension)
                & cmd.exe /c copy /y "$shadowDev\$rel" "$sDst" > $null 2>&1
                if (Test-Path -LiteralPath $sDst) {
                    $sMh = & $ESENTUTL /mh $sDst 2>&1 | Out-String
                    $m1 = [regex]::Match($sMh, 'cbDbPage:\s+(\d+)')
                    $m2 = [regex]::Match($sMh, 'Format ulVersion:\s+0x[0-9a-fA-F]+,(\d+)')
                    if ($m1.Success) { $sPage = $m1.Groups[1].Value }
                    if ($m2.Success) {
                        $sRev  = '0x{0:X4} ({1})' -f [int]$m2.Groups[1].Value, $m2.Groups[1].Value
                        $sGate = if ([int]$m2.Groups[1].Value -ge 290) { 'AT-OR-ABOVE-GATE' } else { 'below gate' }
                    }
                    Remove-Item -LiteralPath $sDst -Force -ErrorAction SilentlyContinue
                }
                Write-Host ("  [UNLISTED  ] page={0,-6} rev={1,-12} {2}  {3}" -f `
                    $sPage, $sRev, $sGate, $_.FullName) -ForegroundColor Magenta
                $rows.Add([pscustomobject]@{
                    Artifact = ('(swept) ' + $_.Name); Role = 'any'; Measured = 'swept'
                    Verdict = 'ESE'; PageSize = $sPage; Revision = $sRev
                    Gate = $sGate; State = ''; Path = $_.FullName })
              }
        }
        Write-Host ("  examined {0} candidate files; unlisted ESE found: {1}" -f $seen, $found) `
            -ForegroundColor DarkGray
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $scratch -ErrorAction SilentlyContinue
    if (-not $KeepShadow) {
        try {
            $shadow.Delete()
            Write-Host 'shadow deleted' -ForegroundColor DarkGray
        } catch {
            # A leaked shadow copy keeps consuming disk, so say so rather than
            # swallowing it.
            Write-Host ("shadow NOT deleted -- remove it manually: {0} ({1})" -f `
                $shadowDev, $_.Exception.Message) -ForegroundColor Yellow
        }
    } else {
        Write-Host "shadow kept: $shadowDev" -ForegroundColor Yellow
    }
}

$rows | Export-Csv -NoTypeInformation -Delimiter "`t" -Encoding UTF8 -Path $Output
Write-Host ''
Write-Host ("host    : {0}  (build {1})" -f $env:COMPUTERNAME, [Environment]::OSVersion.Version)
Write-Host ("written : {0}" -f $Output)
$ese = @($rows | Where-Object Verdict -eq 'ESE')
Write-Host ("ESE databases found: {0}   at/above gate: {1}" -f `
    $ese.Count, @($ese | Where-Object Gate -eq 'AT-OR-ABOVE-GATE').Count)
