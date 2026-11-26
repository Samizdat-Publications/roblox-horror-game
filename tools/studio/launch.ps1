# Starts Roblox Studio on this project's built place and records its process id.
#   powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\studio\launch.ps1"
# Build first (the gate does: tools\check.ps1). Close it with tools\studio\close.ps1, which
# closes only the process id written to artifacts\studio.pid. Windows PowerShell 5.1. ASCII only.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$place = Join-Path $root "DeadCalm.rbxl"
$pidFile = Join-Path $root "artifacts\studio.pid"

if (-not (Test-Path $place)) {
	Write-Host "No $place yet. Run the gate first: tools\check.ps1" -ForegroundColor Red
	exit 1
}

if (Test-Path $pidFile) {
	$oldId = (Get-Content $pidFile -Raw).Trim()
	$old = $null
	if ($oldId -match '^\d+$') { $old = Get-Process -Id ([int]$oldId) -ErrorAction SilentlyContinue }
	if ($old) {
		Write-Host "Studio from this project is already running (pid $oldId). Close it with tools\studio\close.ps1 first." -ForegroundColor Yellow
		exit 1
	}
	Remove-Item $pidFile
}

$roots = @(
	(Join-Path $env:LOCALAPPDATA "Roblox\Versions"),
	(Join-Path ${env:ProgramFiles(x86)} "Roblox\Versions"),
	(Join-Path $env:ProgramFiles "Roblox\Versions")
) | Where-Object { $_ -and (Test-Path $_) }

$exe = $null
if ($roots) {
	$exe = Get-ChildItem -Path $roots -Recurse -Filter "RobloxStudioBeta.exe" -ErrorAction SilentlyContinue |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1
}
if (-not $exe) {
	Write-Host "RobloxStudioBeta.exe not found under $env:LOCALAPPDATA\Roblox\Versions" -ForegroundColor Red
	exit 1
}

# Studio opens a copy, so a rebuild of DeadCalm.rbxl never fights Studio's lock on the file.
$playDir = Join-Path $root "artifacts\studio"
New-Item -ItemType Directory -Force $playDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$playPlace = Join-Path $playDir ("DeadCalm-play-{0}.rbxl" -f $stamp)
Copy-Item $place $playPlace -Force
$place = $playPlace

$proc = Start-Process -FilePath $exe.FullName -ArgumentList ('"{0}"' -f $place) -PassThru
New-Item -ItemType Directory -Force (Split-Path -Parent $pidFile) | Out-Null
Set-Content -Path $pidFile -Value $proc.Id -Encoding ascii
Write-Host ("Studio started: pid {0} ({1}) on {2}" -f $proc.Id, $exe.FullName, $place)
Write-Output $proc.Id
