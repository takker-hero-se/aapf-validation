# Wrapper so the ESE survey can be driven from the host without holding a
# WinRM session open for its whole run.
#
# Two earlier attempts failed and both looked like success from the host:
#   * `vagrant powershell -c "& survey..."` -- the session dies partway with
#     an NTLM parse error and vagrant still exits 0.
#   * `Start-Process ... -WindowStyle Hidden` -- the process is a child of the
#     WinRM host and is cleaned up when that session closes.
# A scheduled task is owned by the service control manager instead, so it
# survives both. The host polls C:\out (a synced folder) for the result.
$ErrorActionPreference = 'Stop'

$script = 'C:\vagrant\scripts\survey_ese_revisions.ps1'   # synced: always current
$out    = 'C:\out\ese_revisions_vm_win11_26200.tsv'
$task   = 'AAPF-ESE-Sweep'

if (-not (Test-Path -LiteralPath $script)) { throw "survey script not found at $script" }
Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue

# Unregister-ScheduledTask, not `schtasks /Delete ... 2>$null`: redirecting a
# native command's stderr under ErrorActionPreference='Stop' turns the ordinary
# "task does not exist" message into a terminating error, which aborted this
# script before it ever registered anything.
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Output "{1}" -Sweep' -f $script, $out)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $task

Start-Sleep -Seconds 5
$info = Get-ScheduledTask -TaskName $task | Get-ScheduledTaskInfo
Write-Output ("task={0} state={1} lastResult={2}" -f $task,
    (Get-ScheduledTask -TaskName $task).State, $info.LastTaskResult)
Write-Output ("watch for: {0}" -f $out)
