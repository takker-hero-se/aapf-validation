# provision.ps1 — runs once during `vagrant up` (WinRM, non-interactive).
# Installs Python + impacket + ffmpeg, enables auto-logon, and installs a
# Startup launcher so the RECORDED verification runs on the next interactive
# logon (triggered by `vagrant reload`).

$ErrorActionPreference = "Stop"
Write-Host "== AAPF sandbox provisioning =="

# --- Chocolatey ------------------------------------------------------------
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = 3072
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}
$choco = "$env:ProgramData\chocolatey\bin\choco.exe"

# --- Tools: ffmpeg (recording) + python (impacket ESE probe) ---------------
& $choco install -y --no-progress ffmpeg python3
# Make python/ffmpeg visible to this session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# --- impacket (pure-Python; used only for the read-only ESE .open() probe) --
# NOTE: we never run secretsdump here; only `impacket.ese.ESENT_DB(path)` to
# demonstrate the page-size gate. Inside this isolated VM, AV does not interfere.
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-ChildItem "C:\Python*\python.exe" | Select-Object -First 1).FullName }
& $py -m pip install --upgrade pip
& $py -m pip install impacket

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
