# THE GATE. Run before every commit:
#   powershell -ExecutionPolicy Bypass -File "C:\Users\stewa\Documents\Claude\Roblox\dead-calm\tools\check.ps1"
# Works from any folder. Stops at the first failing step. Exit code 0 only on a full pass.
# Windows PowerShell 5.1 compatible. Keep this file ASCII.

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$started = Get-Date

function Find-Tool([string]$name) {
	$cmd = Get-Command "$name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($cmd) { return $cmd.Source }
	$local = Join-Path $env:USERPROFILE ".rokit\bin\$name.exe"
	if (Test-Path $local) { return $local }
	Write-Host "FAIL: $name not found on PATH or in $env:USERPROFILE\.rokit\bin (run: rokit install)" -ForegroundColor Red
	exit 1
}

function Find-Python {
	foreach ($name in @("python", "python3", "py")) {
		$cmd = Get-Command "$name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($cmd -and $cmd.Source -notmatch "WindowsApps") { return $cmd.Source }
	}
	if (Test-Path "C:\Python314\python.exe") { return "C:\Python314\python.exe" }
	Write-Host "FAIL: Python 3 not found" -ForegroundColor Red
	exit 1
}

$selene = Find-Tool "selene"
$stylua = Find-Tool "stylua"
$lune = Find-Tool "lune"
$rojo = Find-Tool "rojo"
$python = Find-Python

$steps = @(
	@{ Name = "selene"; Exe = $selene; Args = @("src", "tests", "tools/test", "tools/sim", "tools/lint", "tools/smoke") },
	@{ Name = "stylua --check"; Exe = $stylua; Args = @("--check", "src", "tests", "tools") },
	@{ Name = "lune specs"; Exe = $lune; Args = @("run", "tools/test/run.luau") },
	@{ Name = "pacing sim --fast"; Exe = $lune; Args = @("run", "tools/sim/pacing.luau", "--fast") },
	@{ Name = "lint: em dash"; Exe = $python; Args = @("tools/lint/emdash.py") },
	@{ Name = "lint: asset ids"; Exe = $python; Args = @("tools/lint/asset_ids.py") },
	@{ Name = "lint: secrets"; Exe = $python; Args = @("tools/lint/secrets.py") },
	@{ Name = "lint: core purity"; Exe = $python; Args = @("tools/lint/core_purity.py") },
	@{ Name = "lint: ui words"; Exe = $python; Args = @("tools/lint/ui_words.py") },
	@{ Name = "rojo build"; Exe = $rojo; Args = @("build", "-o", "DeadCalm.rbxl") },
	@{ Name = "place smoke test"; Exe = $lune; Args = @("run", "tools/smoke/place.luau", "DeadCalm.rbxl") }
)

Push-Location $root
$failedStep = $null
try {
	$i = 0
	foreach ($step in $steps) {
		$i++
		Write-Host ""
		Write-Host ("==== [{0}/{1}] {2} ====" -f $i, $steps.Count, $step.Name) -ForegroundColor Cyan
		$t0 = Get-Date
		& $step.Exe @($step.Args)
		$code = $LASTEXITCODE
		$secs = ((Get-Date) - $t0).TotalSeconds
		if ($code -ne 0) {
			Write-Host ("---- {0}: FAILED (exit {1}, {2:N1} s)" -f $step.Name, $code, $secs) -ForegroundColor Red
			$failedStep = $step.Name
			break
		}
		Write-Host ("---- {0}: ok ({1:N1} s)" -f $step.Name, $secs) -ForegroundColor Green
	}
}
finally {
	Pop-Location
}

$total = ((Get-Date) - $started).TotalSeconds
Write-Host ""
if ($failedStep) {
	Write-Host ("GATE FAIL at '{0}' after {1:N1} s" -f $failedStep, $total) -ForegroundColor Red
	exit 1
}
Write-Host ("GATE PASS: {0} steps in {1:N1} s" -f $steps.Count, $total) -ForegroundColor Green
exit 0
