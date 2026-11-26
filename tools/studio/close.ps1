# Closes ONLY the Roblox Studio process this project launched (the id in artifacts\studio.pid).
#   powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\studio\close.ps1"
# Never selects a process by name: another Studio (another game) may be open on this PC.
# Asks the window to close first, waits up to 15 s, then stops that one id. Windows PowerShell 5.1. ASCII only.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pidFile = Join-Path $root "artifacts\studio.pid"

if (-not (Test-Path $pidFile)) {
	Write-Host "No ${pidFile}, nothing to close."
	exit 0
}

$raw = (Get-Content $pidFile -Raw).Trim()
if ($raw -notmatch '^\d+$') {
	Write-Host "Bad pid file contents '$raw'; removing it and closing nothing." -ForegroundColor Yellow
	Remove-Item $pidFile
	exit 1
}
$id = [int]$raw

$proc = Get-Process -Id $id -ErrorAction SilentlyContinue
if (-not $proc) {
	Write-Host "Process $id is not running."
	Remove-Item $pidFile
	exit 0
}
# Safety check on the process we found by id: if the id was reused by some other program, leave it alone.
if ($proc.ProcessName -notlike "RobloxStudio*") {
	Write-Host "Process $id is '$($proc.ProcessName)', not Roblox Studio (id reused?). Not touching it." -ForegroundColor Yellow
	Remove-Item $pidFile
	exit 1
}

[void]$proc.CloseMainWindow()
if ($proc.WaitForExit(15000)) {
	Write-Host "Studio (pid $id) closed."
} else {
	Write-Host "Studio (pid $id) did not close within 15 s; stopping that process."
	Stop-Process -Id $id -Force
	[void]$proc.WaitForExit(5000)
}
Remove-Item $pidFile
exit 0
