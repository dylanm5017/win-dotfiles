#requires -Version 5.1
<#
.SYNOPSIS
    Install/refresh the win-dotfiles Flow Launcher theme and point Flow at it.

.DESCRIPTION
    Resolves Flow's data root (works for both a standard installer build, which keeps data in
    %APPDATA%\FlowLauncher, and a scoop *portable* build, whose data lives in
    <scoop>\persist\Flow-Launcher\UserData). Copies flowlauncher\win-dotfiles.xaml into that
    root's Themes folder, then patches Settings.json to select the theme, bind Alt+Space, use
    the dark color scheme, the repo Nerd Font, and start on login.

    Alt+Space is deliberate: Flow registers hotkeys via the Win32 RegisterHotKey API, and
    Windows permanently reserves Win+Space (the input-switcher), so Flow cannot bind Win+Space
    (it errors "hot key is already registered"). Alt+Space is Flow's reliable default.

    Flow watches its active theme file, so a palette change (the `theme` command rewrites the
    .xaml's marker block) repaints the launcher live. Idempotent and safe to run repeatedly;
    a no-op with a warning when Flow isn't installed / hasn't been run yet.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$themeSource = Join-Path $repoRoot 'flowlauncher\win-dotfiles.xaml'
if (-not (Test-Path -LiteralPath $themeSource -PathType Leaf)) {
    Write-Warning "win-dotfiles Flow theme not found: $themeSource"
    return
}

# Resolve Flow's data root: prefer a scoop portable UserData, else the standard %APPDATA% root.
$candidates = @()
if ($env:SCOOP) { $candidates += (Join-Path $env:SCOOP 'persist\Flow-Launcher\UserData') }
$candidates += (Join-Path $HOME 'scoop\persist\Flow-Launcher\UserData')
$candidates += (Join-Path $env:APPDATA 'FlowLauncher')
$candidates = $candidates | Select-Object -Unique

$dataRoot = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'Settings\Settings.json') -PathType Leaf } | Select-Object -First 1
if (-not $dataRoot) {
    # No settings yet — fall back to any existing candidate dir just to stage the theme.
    $dataRoot = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
}
if (-not $dataRoot) {
    Write-Warning 'Flow Launcher not detected. Install it (winget install Flow-Launcher.Flow.Launcher, or scoop install Flow-Launcher) and run it once, then re-run.'
    return
}

# Stage the theme into Flow's Themes directory.
$themesDir = Join-Path $dataRoot 'Themes'
New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
Copy-Item -LiteralPath $themeSource -Destination (Join-Path $themesDir 'win-dotfiles.xaml') -Force

$settingsPath = Join-Path $dataRoot 'Settings\Settings.json'
if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    Write-Warning "Flow settings not found ($settingsPath). Launch Flow once so it creates Settings.json, then re-run. The theme file is already staged."
    return
}

function Set-FlowProperty($obj, $name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -MemberType NoteProperty -Name $name -Value $value -Force }
}

try {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    Set-FlowProperty $settings 'Theme' 'win-dotfiles'
    Set-FlowProperty $settings 'Hotkey' 'Alt + Space'
    Set-FlowProperty $settings 'ColorScheme' 'Dark'
    Set-FlowProperty $settings 'QueryBoxFont' 'CaskaydiaCove NF'
    Set-FlowProperty $settings 'StartFlowLauncherOnSystemStartup' $true
    # Skip the network plugin-update check at launch so the hotkey is ready sooner after login
    # (update manually anytime via the `pm` action keyword).
    Set-FlowProperty $settings 'AutoUpdatePlugins' $false

    # Depth-truncation guard: past the cap ConvertTo-Json emits a .ToString() blob instead of the
    # nested object, silently corrupting Flow settings. Its truncation warning is the reliable signal.
    $json = $settings | ConvertTo-Json -Depth 32 -WarningVariable jsonWarnings -WarningAction SilentlyContinue
    if ($jsonWarnings) {
        throw 'ConvertTo-Json truncated at depth 32; not writing Flow settings.'
    }
    $null = $json | ConvertFrom-Json  # confirm valid JSON before it touches the live file

    # Flow is outside the winsmooth backup manifest, so keep a one-time copy of the pristine
    # settings as a recovery point, then write atomically (temp + move) so a crash can't truncate it.
    $backupPath = "$settingsPath.win-dotfiles.bak"
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
    }
    $tempPath = "$settingsPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Set-Content -LiteralPath $tempPath -Value $json -Encoding utf8
        Move-Item -LiteralPath $tempPath -Destination $settingsPath -Force
    }
    catch {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw
    }

    Write-Host "Flow Launcher themed (win-dotfiles), bound to Alt+Space, autostart on. Data root: $dataRoot" -ForegroundColor Green
    Write-Host 'Theme hot-reloads if Flow is running; a hotkey change needs a Flow restart.' -ForegroundColor DarkGray
}
catch {
    Write-Warning "Could not patch Flow settings. Theme file is staged; select 'win-dotfiles' in Flow settings manually. Detail: $($_.Exception.Message)"
}
