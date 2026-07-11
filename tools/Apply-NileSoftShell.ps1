#requires -Version 5.1
<#
.SYNOPSIS
    Stage the win-dotfiles Nilesoft Shell theme into the installed Shell's config.

.DESCRIPTION
    Resolves Nilesoft Shell's install directory (the winget/installer default
    C:\Program Files\Nilesoft Shell, or a scoop install under
    %USERPROFILE%\scoop\apps\nilesoft-shell\current), then copies
    nilesoft-shell\theme.nss into that install's imports\theme.nss (Shell's default modular
    layout, imported by its shell.nss). Idempotent and safe to run repeatedly; a no-op with a
    warning when Nilesoft Shell isn't installed.

    Unlike Yasb (hot-reloads on save) or Flow Launcher (watches its theme file), Nilesoft Shell
    does not reload shell.nss automatically. It reloads either via the manual gesture
    (hold right-click, then left-click) or an Explorer restart. Because this script also runs on
    every `theme <name>` switch (see 45-theme.ps1), it does NOT restart Explorer by default —
    that would be disruptive on every switch. Pass -Restart to force it (e.g. first-time setup).

.PARAMETER Restart
    Restart Explorer after staging the theme so the context menu picks it up immediately.
#>
[CmdletBinding()]
param(
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$themeSource = Join-Path $repoRoot 'nilesoft-shell\theme.nss'
if (-not (Test-Path -LiteralPath $themeSource -PathType Leaf)) {
    Write-Warning "win-dotfiles Nilesoft Shell theme not found: $themeSource"
    return
}

# Resolve Nilesoft Shell's install directory: the winget/installer default, or a scoop install.
$candidates = @(
    (Join-Path ${env:ProgramFiles} 'Nilesoft Shell'),
    (Join-Path $HOME 'scoop\apps\nilesoft-shell\current')
)
if ($env:SCOOP) { $candidates += (Join-Path $env:SCOOP 'apps\nilesoft-shell\current') }
$candidates = $candidates | Select-Object -Unique

$installDir = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'shell.nss') -PathType Leaf } | Select-Object -First 1
if (-not $installDir) {
    Write-Warning 'Nilesoft Shell not detected (no shell.nss found). Install it (winget install Nilesoft.Shell), run `shell -register -restart` from an elevated prompt once, then re-run.'
    return
}

# Stage into the default imports\theme.nss layout when it exists; otherwise fall back to the
# install root and tell the user how to wire it in, rather than guessing at their shell.nss.
$importsDir = Join-Path $installDir 'imports'
if (Test-Path -LiteralPath $importsDir -PathType Container) {
    $themeTarget = Join-Path $importsDir 'theme.nss'
    Copy-Item -LiteralPath $themeSource -Destination $themeTarget -Force
    Write-Host "Nilesoft Shell themed (win-dotfiles): $themeTarget" -ForegroundColor Green
}
else {
    $themeTarget = Join-Path $installDir 'theme.nss'
    Copy-Item -LiteralPath $themeSource -Destination $themeTarget -Force
    Write-Warning "No imports\ folder found under $installDir; staged the theme at $themeTarget instead. Add `"import 'theme.nss'`" to shell.nss so it's picked up."
}

if ($Restart) {
    Write-Host 'Restarting Explorer to reload the context menu...' -ForegroundColor DarkGray
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
else {
    Write-Host "Reload it: hold right-click then left-click on the desktop, or re-run with -Restart." -ForegroundColor DarkGray
}
