# orchestrate.ps1 — runs on the interactive desktop at auto-logon.
# Starts ffmpeg screen recording, runs the verification visibly, then stops
# ffmpeg gracefully (so the .mp4 is finalized) and writes the DONE sentinel.

$ErrorActionPreference = "Continue"
$ts    = Get-Date -Format "yyyyMMdd-HHmmss"
$out   = "C:\out"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$video = Join-Path $out "verification-$ts.mp4"
$log   = Join-Path $out "verification-$ts.log"

# Bring THIS console to the foreground and maximize it, so the gdigrab screen
# capture records the visible verification output (not an idle desktop). Needed
# because a console launched non-interactively can open hidden/behind.
try {
  Add-Type -Name Win -Namespace Fg -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
'@
  $h = [Fg.Win]::GetConsoleWindow()
  [void][Fg.Win]::ShowWindow($h, 3)          # SW_MAXIMIZE
  [void][Fg.Win]::SetForegroundWindow($h)
} catch { }

# Give the desktop/shell a moment to settle so the recording captures the run.
Start-Sleep -Seconds 8

# --- Start ffmpeg screen capture (stdin kept open so we can send 'q') -------
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { $ffmpeg = "ffmpeg" }
$ffLog = Join-Path $out "ffmpeg-$ts.log"
$psi = New-Object System.Diagnostics.ProcessStartInfo
# Run ffmpeg via cmd so its stderr goes to a log file (to diagnose empty capture)
# while cmd forwards our stdin 'q' to ffmpeg for a clean finalize.
$psi.FileName  = $env:ComSpec
# scale to an even width (gdigrab desktop can be an odd width, e.g. 1629, which
# makes libx264 fail with "width not divisible by 2"). scale=1280:-2 keeps aspect
# and forces even dimensions.
$psi.Arguments = "/c `"`"$ffmpeg`" -y -f gdigrab -framerate 10 -i desktop -vf scale=1280:-2 -vcodec libx264 -pix_fmt yuv420p -preset ultrafast `"$video`" 2> `"$ffLog`"`""
$psi.RedirectStandardInput = $true
$psi.UseShellExecute = $false
$psi.WindowStyle = "Minimized"
$rec = [System.Diagnostics.Process]::Start($psi)
Start-Sleep -Seconds 3

# --- Run the verification in a VISIBLE window, tee to the log --------------
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\scripts\run-verification.ps1 *>&1 |
  Tee-Object -FilePath $log
Start-Sleep -Seconds 4

# --- Stop ffmpeg gracefully (send 'q' on stdin so the mp4 is finalized) -----
try {
  $rec.StandardInput.WriteLine("q")
  $rec.StandardInput.Flush()
  if (-not $rec.WaitForExit(20000)) { $rec.Kill() }
} catch {
  try { $rec.Kill() } catch {}
}

# --- Sentinel so the host wrapper / operator knows it finished --------------
"video=$video" | Set-Content -Path (Join-Path $out "DONE.txt") -Encoding ASCII
Add-Content   -Path (Join-Path $out "DONE.txt") -Value "log=$log"
Add-Content   -Path (Join-Path $out "DONE.txt") -Value "finished=$(Get-Date -Format o)"

Write-Host ""
Write-Host "Recording saved: $video"
Write-Host "Log saved:       $log"
Write-Host "This window closes in 20s."
Start-Sleep -Seconds 20
