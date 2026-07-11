#Requires -Version 5.1
<#
.SYNOPSIS
    Generate a themed desktop wallpaper for each win-dotfiles theme.

.DESCRIPTION
    Reads every themes/<name>.psd1 and renders wallpapers/<name>.png: a diagonal gradient between
    the theme's Wallpaper.From/To stops, a soft vignette, and a faint centered ">_" mark in the
    accent color. The PNGs are committed so install/runtime never needs to render; re-run this only
    when a palette changes. Windows-only (uses GDI+ via System.Drawing).

.EXAMPLE
    ./tools/Build-Wallpapers.ps1
.EXAMPLE
    ./tools/Build-Wallpapers.ps1 -Width 5120 -Height 2160   # match a specific monitor
#>
[CmdletBinding()]
param(
    [int]$Width = 3840,
    [int]$Height = 2160
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$themesRoot = Join-Path $repoRoot 'themes'
$wallpaperRoot = Join-Path $repoRoot 'wallpapers'
New-Item -ItemType Directory -Path $wallpaperRoot -Force | Out-Null

function ConvertTo-DrawingColor {
    param([string]$Hex, [int]$Alpha = 255)
    $h = $Hex.TrimStart('#')
    [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16))
}

$themeFiles = Get-ChildItem -LiteralPath $themesRoot -Filter '*.psd1' -ErrorAction SilentlyContinue
if (-not $themeFiles) { throw "No theme definitions found in $themesRoot" }

foreach ($file in $themeFiles) {
    $theme = Import-PowerShellDataFile -LiteralPath $file.FullName
    $wp = $theme.Wallpaper
    $from = ConvertTo-DrawingColor $wp.From
    $to = ConvertTo-DrawingColor $wp.To
    $glyph = ConvertTo-DrawingColor $wp.Glyph 30   # faint accent mark

    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    try {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)

        # Diagonal gradient backdrop.
        $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $from, $to, 45.0)
        $g.FillRectangle($gradient, $rect)
        $gradient.Dispose()

        # Soft vignette: darken the corners with a radial overlay.
        $vignettePath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $vignettePath.AddEllipse(-$Width * 0.25, -$Height * 0.25, $Width * 1.5, $Height * 1.5)
        $vignette = New-Object System.Drawing.Drawing2D.PathGradientBrush($vignettePath)
        $vignette.CenterColor = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
        $vignette.SurroundColors = @([System.Drawing.Color]::FromArgb(120, 0, 0, 0))
        $g.FillRectangle($vignette, $rect)
        $vignette.Dispose()
        $vignettePath.Dispose()

        # Faint centered ">_" mark (terminal/dev nod) in the accent color.
        $fontSize = [float]($Height * 0.16)
        $font = New-Object System.Drawing.Font('Consolas', $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $brush = New-Object System.Drawing.SolidBrush($glyph)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString('>_', $font, $brush, ($Width / 2.0), ($Height / 2.0), $fmt)
        $brush.Dispose(); $font.Dispose(); $fmt.Dispose()

        $outPath = Join-Path $wallpaperRoot ("{0}.png" -f $file.BaseName)
        $bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host "Wrote $outPath ($Width x $Height)" -ForegroundColor Green
    }
    finally {
        $g.Dispose()
        $bitmap.Dispose()
    }
}

Write-Host 'Done. Apply with: theme <name>  (or winsmooth -Apply for the active theme).' -ForegroundColor Cyan
