#requires -Version 5.1
<#
.SYNOPSIS
    Install/refresh the win-dotfiles Spicetify theme and point Spotify at a palette.

.DESCRIPTION
    Copies spicetify\win-dotfiles into %APPDATA%\spicetify\Themes\win-dotfiles, then sets
    Spicetify's current_theme + color_scheme (one section per win-dotfiles palette) and
    applies it so Spotify recolours in lock-step with the rest of the rice.

    Idempotent and safe to run repeatedly. No-op (with a warning) when Spicetify isn't
    installed, and a soft warning — not a hard error — when `spicetify apply` fails (e.g.
    Spotify not installed yet), so the `theme` command never breaks on a missing app.

.PARAMETER Scheme
    Palette slug = color.ini section name (ashes|dracula|nord|mocha).
    Defaults to the active theme recorded in themes/active.txt.

.PARAMETER FirstRun
    Use `spicetify backup apply` instead of `spicetify apply`. Needed the very first time
    Spicetify themes a fresh Spotify install (creates the backup it patches against).
#>
[CmdletBinding()]
param(
    [string]$Scheme,
    [switch]$FirstRun
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command spicetify -ErrorAction SilentlyContinue)) {
    Write-Warning 'spicetify is not installed or not on PATH; skipping Spotify theming. Install with: scoop install spicetify-cli'
    return
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$themeSource = Join-Path $repoRoot 'spicetify\win-dotfiles'
if (-not (Test-Path -LiteralPath $themeSource -PathType Container)) {
    Write-Warning "win-dotfiles Spicetify theme not found: $themeSource"
    return
}

if (-not $Scheme) {
    $activePath = Join-Path $repoRoot 'themes\active.txt'
    if (Test-Path -LiteralPath $activePath -PathType Leaf) {
        $Scheme = (Get-Content -LiteralPath $activePath -TotalCount 1 -ErrorAction SilentlyContinue)
    }
    if ($Scheme) { $Scheme = $Scheme.Trim().ToLowerInvariant() } else { $Scheme = 'mocha' }
}

# Spicetify reads real files from its Themes directory, so copy (don't symlink) a fresh tree.
$themesRoot = Join-Path $env:APPDATA 'spicetify\Themes'
$themeTarget = Join-Path $themesRoot 'win-dotfiles'
New-Item -ItemType Directory -Path $themesRoot -Force | Out-Null
if (Test-Path -LiteralPath $themeTarget) { Remove-Item -LiteralPath $themeTarget -Recurse -Force }
Copy-Item -LiteralPath $themeSource -Destination $themeTarget -Recurse -Force

try {
    spicetify config current_theme win-dotfiles color_scheme $Scheme | Out-Null
    if ($FirstRun) {
        spicetify backup apply
    }
    else {
        spicetify apply
    }
    Write-Host "Spotify themed: win-dotfiles / $Scheme." -ForegroundColor Green
}
catch {
    Write-Warning "Spicetify could not apply (is Spotify installed?). Theme files are staged; run 'spicetify backup apply' once. Detail: $($_.Exception.Message)"
}
