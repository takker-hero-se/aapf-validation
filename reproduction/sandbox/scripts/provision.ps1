# provision.ps1 -- runs once during `vagrant up` (WinRM, non-interactive).
# Installs Python + impacket + ffmpeg, enables auto-logon, and installs a
# Startup launcher so the RECORDED verification runs on the next interactive
# logon (triggered by `vagrant reload`).

$ErrorActionPreference = "Stop"
Write-Host "== AAPF sandbox provisioning =="

# --- Toolchain, from the vendored copy: no network during provisioning -----
# ffmpeg, Python and Impacket used to come from Chocolatey and PyPI. That made
# a recorded run depend on three external services staying up and unchanged,
# and it failed outright whenever the host's VMware NAT service died and the
# guest lost DNS. The vendored copy ships with the corpus; vendor/MANIFEST.txt
# records each file's origin and SHA-256. The versions are exactly the ones the
# recorded runs measured. Nothing here decides an assertion -- ffmpeg only
# records the screen, Python only hosts Impacket -- but a toolchain that moves
# under a rerun is a toolchain that can break one.
$vendor = 'C:\aapf\vendor'
if (-not (Test-Path (Join-Path $vendor 'MANIFEST.txt'))) {
  throw "No vendored toolchain at $vendor. It ships with the corpus that " +
        'AAPF_CORPUS points at; see VERIFICATION.md.'
}

# ffmpeg is one static binary. Put it on the MACHINE path: the recording runs in
# the interactive auto-logon session, not in this one.
New-Item -ItemType Directory -Force -Path 'C:\tools' | Out-Null
Copy-Item (Join-Path $vendor 'ffmpeg.exe') 'C:\tools\ffmpeg.exe' -Force
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike '*C:\tools*') {
  [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';C:\tools'), 'Machine')
}

# Python, silent install from the vendored installer (PrependPath puts it on the
# machine path, which the auto-logon session inherits).
$pyExe = Join-Path $vendor 'python-3.14.7-amd64.exe'
$proc = Start-Process -FilePath $pyExe -Wait -PassThru -ArgumentList @(
  '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_test=0')
if ($proc.ExitCode -ne 0) { throw "vendored Python installer failed ($($proc.ExitCode))" }
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')

# --- impacket (pure-Python; used only for the read-only ESE .open() probe) --
# NOTE: we never run secretsdump here; only `impacket.ese.ESENT_DB(path)` to
# demonstrate the page-size gate. Pinned to 0.13.1 because every Impacket claim
# in run-verification.ps1 and in the paper was measured against that release.
# --no-index keeps pip off the network completely.
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-ChildItem 'C:\Program Files\Python*\python.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
if (-not $py) { throw 'python not found after installing the vendored copy' }
& $py -m pip install --no-index --find-links (Join-Path $vendor 'wheels') 'impacket==0.13.1'
if ($LASTEXITCODE -ne 0) { throw "offline impacket install failed ($LASTEXITCODE)" }
New-Item -ItemType Directory -Force -Path 'C:\scripts' | Out-Null
$py | Set-Content -Path 'C:\scripts\python_path.txt' -Encoding ASCII
Write-Host ("  python: {0}" -f $py)
Write-Host ("  ffmpeg: C:\tools\ffmpeg.exe")

# --- Keep the auto-logon desktop ACTIVE & UNLOCKED --------------------------
# The box auto-locks (lock screen), which stops the Startup launcher from running
# and makes ffmpeg gdigrab capture an empty screen. Disable screensaver / auto-lock
# / lock screen / display+standby timeouts so the desktop stays live for recording.
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f | Out-Null
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveTimeOut /t REG_SZ /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v InactivityTimeoutSecs /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f | Out-Null
powercfg /change monitor-timeout-ac 0 2>$null
powercfg /change standby-timeout-ac 0 2>$null
powercfg /change disk-timeout-ac 0 2>$null

# --- Enable auto-logon for the 'vagrant' user ------------------------------
$winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $winlogon -Name AutoAdminLogon  -Value "1"
Set-ItemProperty $winlogon -Name DefaultUserName -Value "vagrant"
Set-ItemProperty $winlogon -Name DefaultPassword -Value "vagrant"
Set-ItemProperty $winlogon -Name DefaultDomainName -Value $env:COMPUTERNAME

# --- Startup launcher: run orchestrate.ps1 at interactive logon -------------
$startup = "C:\Users\vagrant\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
New-Item -ItemType Directory -Force -Path $startup | Out-Null
@"
@echo off
start "" powershell -NoProfile -ExecutionPolicy Bypass -File C:\scripts\orchestrate.ps1
"@ | Set-Content -Path "$startup\aapf-verify.cmd" -Encoding ASCII

# Record where python is for the verification script.
$py | Set-Content -Path "C:\scripts\python_path.txt" -Encoding ASCII

Write-Host "== Provisioning complete. Run 'vagrant reload' to start the recorded verification. =="
