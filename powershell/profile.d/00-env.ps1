$WorkspaceRoot = 'C:\Workspace'
$DevRoot = Join-Path $WorkspaceRoot 'Dev'
$ProjectsRoot = Join-Path $WorkspaceRoot 'Projects'
$ToolsRoot = Join-Path $DevRoot 'Tools'
$CacheRoot = Join-Path $DevRoot 'Cache'
$WinDotfilesRoot = Join-Path $ProjectsRoot 'win-dotfiles'
$DotfilesRoot = Join-Path $HOME 'Documents\dotfiles'
$PowerShellRoot = Join-Path $HOME 'Documents\PowerShell'
$IsCodexShell = [bool]($env:CODEX_THREAD_ID -or $env:CODEX_SANDBOX_NETWORK_DISABLED -or $env:CODEX_INTERNAL_ORIGINATOR_OVERRIDE)

function Test-WinDotfilesTempRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$RequireDelete
    )

    try {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        $testPath = Join-Path $Path ("win-dotfiles-temp-{0}.tmp" -f ([guid]::NewGuid().ToString('N')))
        Set-Content -LiteralPath $testPath -Value 'ok' -Encoding utf8 -ErrorAction Stop

        if ($RequireDelete) {
            Remove-Item -LiteralPath $testPath -Force -ErrorAction Stop
        }

        $true
    }
    catch {
        $false
    }
}

$AppDataCodexTempRoot = Join-Path $env:LOCALAPPDATA 'Temp\codex'
$WorkspaceCodexTempRoot = Join-Path $WinDotfilesRoot '.tmp\codex'
$SlashCodexTempRoot = 'C:\tmp\codex'
$CurrentDirectoryCodexTempRoot = $null
try {
    if ((Get-Location).Provider.Name -eq 'FileSystem') {
        $CurrentDirectoryCodexTempRoot = Join-Path (Get-Location).Path '.tmp\codex'
    }
}
catch {
    $CurrentDirectoryCodexTempRoot = $null
}

$CodexTempRootSupportsDelete = $false
$CodexTempRoot = if ($IsCodexShell) { $AppDataCodexTempRoot } else { $WorkspaceCodexTempRoot }

if ($IsCodexShell) {
    $CodexTempCandidates = @($AppDataCodexTempRoot, $CurrentDirectoryCodexTempRoot, $SlashCodexTempRoot, $WorkspaceCodexTempRoot) |
    Where-Object { $_ } |
    Select-Object -Unique

    foreach ($candidate in $CodexTempCandidates) {
        if (Test-WinDotfilesTempRoot -Path $candidate -RequireDelete) {
            $CodexTempRoot = $candidate
            $CodexTempRootSupportsDelete = $true
            break
        }
    }
}

$TempRoot = if ($IsCodexShell) { $CodexTempRoot } else { Join-Path $DevRoot 'Temp' }
$DotnetCliHome = if ($IsCodexShell) { Join-Path $CodexTempRoot 'dotnet-home' } else { $env:DOTNET_CLI_HOME }
$DotnetArtifactsPath = if ($IsCodexShell) { Join-Path $CodexTempRoot 'dotnet-artifacts' } else { $env:WINDOTFILES_DOTNET_ARTIFACTS_PATH }
$NuGetHttpCachePath = if ($IsCodexShell) { Join-Path $CodexTempRoot 'nuget-http-cache' } else { $env:NUGET_HTTP_CACHE_PATH }
$NuGetPluginsCachePath = if ($IsCodexShell) { Join-Path $CodexTempRoot 'nuget-plugins-cache' } else { $env:NUGET_PLUGINS_CACHE_PATH }
$WinDotfilesStateRoot = if ($IsCodexShell) { Join-Path $CodexTempRoot 'win-dotfiles' } else { Join-Path $CacheRoot 'win-dotfiles' }

$env:STARSHIP_CONFIG = Join-Path $WinDotfilesRoot 'starship.toml'
$env:STARSHIP_CACHE = Join-Path $CacheRoot 'starship'
$env:NPM_CONFIG_PREFIX = Join-Path $ToolsRoot 'npm'
$env:NPM_CONFIG_CACHE = Join-Path $CacheRoot 'npm'
$env:PIP_CACHE_DIR = Join-Path $CacheRoot 'pip'
$env:TEMP = $TempRoot
$env:TMP = $TempRoot
$env:TMPDIR = $TempRoot

if ($IsCodexShell) {
    $env:DOTNET_CLI_HOME = $DotnetCliHome
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
    $env:DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE = '1'
    $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
    $env:MSBUILDDISABLENODEREUSE = '1'
    $env:WINDOTFILES_CODEX_TEMP_DELETE_OK = if ($CodexTempRootSupportsDelete) { '1' } else { '0' }
    $env:WINDOTFILES_DOTNET_ARTIFACTS_PATH = $DotnetArtifactsPath
    $env:NUGET_HTTP_CACHE_PATH = $NuGetHttpCachePath
    $env:NUGET_PLUGINS_CACHE_PATH = $NuGetPluginsCachePath
}

@($CacheRoot, $TempRoot, $WinDotfilesStateRoot, $env:STARSHIP_CACHE, $env:NPM_CONFIG_PREFIX, $env:NPM_CONFIG_CACHE, $env:PIP_CACHE_DIR, $DotnetCliHome, $DotnetArtifactsPath, $NuGetHttpCachePath, $NuGetPluginsCachePath) |
Where-Object { $_ -and -not (Test-Path -LiteralPath $_ -PathType Container) } |
ForEach-Object { New-Item -ItemType Directory -Path $_ -Force -ErrorAction SilentlyContinue | Out-Null }

$IsInteractiveShell = [Environment]::UserInteractive -and
-not [Console]::IsInputRedirected -and
-not [Console]::IsOutputRedirected

function Set-LocationIfExists {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Set-Location -LiteralPath $Path
    }
    else {
        Write-Warning "Directory does not exist: $Path"
    }
}

function Get-WinDotfilesStateRoot {
    New-Item -ItemType Directory -Path $WinDotfilesStateRoot -Force -ErrorAction SilentlyContinue | Out-Null
    $WinDotfilesStateRoot
}

function Test-ShouldUseDefaultWorkspaceLocation {
    if (-not $IsInteractiveShell) {
        return $false
    }

    if ((Get-Location).Provider.Name -ne 'FileSystem') {
        return $false
    }

    $currentPath = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
    $homePath = [IO.Path]::GetFullPath($HOME).TrimEnd('\')

    $currentPath -ieq $homePath
}
