# Grabs a still of the Roblox Studio window into a JPG, without moving or focusing it.
# Usage: powershell -ExecutionPolicy Bypass -File tools\capture-studio.ps1 -Out docs\making-of\stills\name.jpg [-Width 1280] [-ViewportOnly]
# -ViewportOnly crops off Studio's ribbon and side panels using the largest child pane, best effort.
param(
  [Parameter(Mandatory = $true)][string]$Out,
  [int]$Width = 1280,
  [switch]$ViewportOnly
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
# Without this, display scaling shrinks the window rect and the right side gets cut off.
[void][Win]::SetProcessDPIAware()

$proc = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { throw "Roblox Studio is not open." }
$h = $proc.MainWindowHandle
if ([Win]::IsIconic($h)) { throw "Roblox Studio is minimized; restore it so it can be captured." }

$r = New-Object Win+RECT
[void][Win]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $hgt = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
# 2 = PW_RENDERFULLCONTENT, needed for the GPU-drawn 3D viewport
$ok = [Win]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
if (-not $ok) { throw "PrintWindow failed." }

$src = $bmp
if ($ViewportOnly) {
  # Find the game viewport by Studio's saturated blue focus border. Falls back to the whole window.
  $isBorder = { param($c) ($c.B -gt 180 -and $c.R -lt 95 -and $c.G -lt 140) }
  $xs = @(); $ys = @()
  foreach ($fy in 0.35, 0.5, 0.65) {
    $y = [int]($hgt * $fy)
    for ($x = 0; $x -lt $w; $x++) { if (& $isBorder $bmp.GetPixel($x, $y)) { $xs += $x } }
  }
  # Keep only columns that are part of a long vertical blue line (the border), not blue icons.
  $longRun = {
    param($cx)
    $best = @(0, 0, 0); $start = -1
    for ($y = 0; $y -le $hgt; $y++) {
      $on = ($y -lt $hgt) -and (& $isBorder $bmp.GetPixel($cx, $y))
      if ($on -and $start -lt 0) { $start = $y }
      elseif (-not $on -and $start -ge 0) { if (($y - $start) -gt $best[0]) { $best = @(($y - $start), $start, ($y - 1)) }; $start = -1 }
    }
    return ,$best
  }
  $cands = @($xs | Sort-Object -Unique | Where-Object { (& $longRun $_)[0] -gt ($hgt * 0.3) })
  if ($cands.Count -ge 2) {
    $x0 = ($cands | Measure-Object -Minimum).Minimum; $x1 = ($cands | Measure-Object -Maximum).Maximum
    $run = & $longRun $x0
    $ys = @($run[1], $run[2])
    if ($ys[1] -gt $ys[0]) {
      $y0 = $ys[0]; $y1 = $ys[1]
      if (($x1 - $x0) -gt 200 -and ($y1 - $y0) -gt 150) {
        $crop = New-Object System.Drawing.Rectangle ($x0 + 3), ($y0 + 3), ($x1 - $x0 - 6), ($y1 - $y0 - 6)
        $src = $bmp.Clone($crop, $bmp.PixelFormat)
      }
    }
  }
  if ($src -eq $bmp) { Write-Warning "Viewport border not found; saving the whole window." }
}

$scale = [Math]::Min(1.0, $Width / $src.Width)
$ow = [int]($src.Width * $scale); $oh = [int]($src.Height * $scale)
$outBmp = New-Object System.Drawing.Bitmap $ow, $oh
$og = [System.Drawing.Graphics]::FromImage($outBmp)
$og.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$og.DrawImage($src, 0, 0, $ow, $oh); $og.Dispose()

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 85L
$full = [System.IO.Path]::GetFullPath($Out)
$outBmp.Save($full, $codec, $ep)
$outBmp.Dispose(); if ($src -ne $bmp) { $src.Dispose() }; $bmp.Dispose()
"Saved $full ($ow x $oh)"
