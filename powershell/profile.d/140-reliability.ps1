function Test-PowerShellScriptsParse {
    param([Parameter(Mandatory)][string[]]$Path)

    $parseErrors = @()
    $filesByPath = [ordered]@{}

    foreach ($pathItem in $Path) {
        if (Test-Path -LiteralPath $pathItem -PathType Container) {
            $files = Get-ChildItem -LiteralPath $pathItem -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $pathItem -PathType Leaf) {
            $files = Get-Item -LiteralPath $pathItem -ErrorAction SilentlyContinue
        }
        else {
            $files = @()
        }

        foreach ($file in @($files)) {
            $filePath = [IO.Path]::GetFullPath($file.FullName)
            if (-not $filesByPath.Contains($filePath)) {
                $filesByPath[$filePath] = $file
            }
        }
    }

    foreach ($file in ($filesByPath.Values | Sort-Object FullName)) {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)

        foreach ($errorItem in @($errors)) {
            $parseErrors += [PSCustomObject]@{
                File    = $file.FullName
                Line    = $errorItem.Extent.StartLineNumber
                Column  = $errorItem.Extent.StartColumnNumber
                Message = $errorItem.Message
            }
        }
    }

    $parseErrors
}

function Test-WinDotfilesJsonText {
    # Throws if $Text is not parseable JSON. -AllowComments accepts JSONC (// and /* */ comments
    # plus trailing commas). Uses System.Text.Json so // inside strings (e.g. schema URLs) is not
    # mistaken for a comment — a string-aware parse, unlike naive regex stripping.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$AllowComments
    )

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    if ($AllowComments) {
        $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
        $options.AllowTrailingCommas = $true
    }

    $document = [System.Text.Json.JsonDocument]::Parse($Text, $options)
    $document.Dispose()
}

function Test-WinDotfilesConfig {
    # Syntax-validate the committed config files so a malformed config can never reach the live
    # desktop (every repo config is symlinked live). JSON/JSONC/XML are hard-fail syntax gates;
    # YAML/TOML/Lua are best-effort and cleanly reported as skipped when no parser is present.
    # -RepoRoot is explicit so this works from a CI checkout, not just $WinDotfilesRoot.
    [CmdletBinding()]
    param([string]$RepoRoot = $WinDotfilesRoot)

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $RepoRoot -or -not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
        [void]$results.Add((New-WinDotfilesCheckResult 'Config repo root exists' $false ([string]$RepoRoot)))
        return $results
    }

    $yamlModule = Get-Module -ListAvailable -Name 'powershell-yaml' -ErrorAction SilentlyContinue | Select-Object -First 1
    $luac = Get-Command luac -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $wezterm = Get-Command wezterm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

    $specs = @(
        @{ Rel = 'komorebi\komorebi.json'; Kind = 'Json' }
        @{ Rel = 'komorebi\komorebi.bar.json'; Kind = 'Json' }
        @{ Rel = 'packages\scoop.json'; Kind = 'Json' }
        @{ Rel = 'packages\winget.json'; Kind = 'Json' }
        @{ Rel = 'terminal\windows-terminal\settings.json'; Kind = 'Jsonc' }
        @{ Rel = 'vscode\settings.json'; Kind = 'Jsonc' }
        @{ Rel = 'fastfetch\config.jsonc'; Kind = 'Jsonc' }
        @{ Rel = 'flowlauncher\win-dotfiles.xaml'; Kind = 'Xml' }
        @{ Rel = 'yasb\config.yaml'; Kind = 'Yaml' }
        @{ Rel = 'starship.toml'; Kind = 'Toml' }
        @{ Rel = 'terminal\wezterm\wezterm.lua'; Kind = 'Lua' }
    )

    foreach ($spec in $specs) {
        $name = "Config valid: $($spec.Rel)"
        $path = Join-Path $RepoRoot $spec.Rel

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [void]$results.Add((New-WinDotfilesCheckResult $name $false 'file not found'))
            continue
        }

        try {
            switch ($spec.Kind) {
                'Json' {
                    Test-WinDotfilesJsonText -Text (Get-Content -LiteralPath $path -Raw)
                    [void]$results.Add((New-WinDotfilesCheckResult $name $true 'JSON OK'))
                }
                'Jsonc' {
                    Test-WinDotfilesJsonText -Text (Get-Content -LiteralPath $path -Raw) -AllowComments
                    [void]$results.Add((New-WinDotfilesCheckResult $name $true 'JSONC OK'))
                }
                'Xml' {
                    $null = [xml](Get-Content -LiteralPath $path -Raw)
                    [void]$results.Add((New-WinDotfilesCheckResult $name $true 'XML OK'))
                }
                'Yaml' {
                    if ($yamlModule) {
                        Import-Module 'powershell-yaml' -ErrorAction Stop
                        $null = ConvertFrom-Yaml (Get-Content -LiteralPath $path -Raw)
                        [void]$results.Add((New-WinDotfilesCheckResult $name $true 'YAML OK'))
                    }
                    else {
                        [void]$results.Add((New-WinDotfilesCheckResult $name $true 'skipped: install powershell-yaml to validate'))
                    }
                }
                'Toml' {
                    [void]$results.Add((New-WinDotfilesCheckResult $name $true 'skipped: no TOML parser available'))
                }
                'Lua' {
                    if ($luac) {
                        & $luac.Source -p $path 2>&1 | Out-Null
                        $ok = $LASTEXITCODE -eq 0
                        [void]$results.Add((New-WinDotfilesCheckResult $name $ok $(if ($ok) { 'Lua OK (luac -p)' } else { 'luac -p reported a syntax error' })))
                    }
                    elseif ($wezterm) {
                        & $wezterm.Source --config-file $path ls-fonts 2>&1 | Out-Null
                        $ok = $LASTEXITCODE -eq 0
                        [void]$results.Add((New-WinDotfilesCheckResult $name $ok $(if ($ok) { 'Lua OK (wezterm)' } else { 'wezterm rejected the config' })))
                    }
                    else {
                        [void]$results.Add((New-WinDotfilesCheckResult $name $true 'skipped: no Lua parser available'))
                    }
                }
            }
        }
        catch {
            [void]$results.Add((New-WinDotfilesCheckResult $name $false $_.Exception.Message))
        }
    }

    # komorebi schema check: komorebi is the most fragile config (a bad komorebi.json = no window
    # manager). Scope KOMOREBI_CONFIG_HOME to the repo so `komorebic check` validates the repo copy.
    # Best-effort: skipped (as passing) when komorebic is absent, e.g. in CI.
    $komorebic = Get-Command komorebic -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($komorebic) {
        $previousConfigHome = $env:KOMOREBI_CONFIG_HOME
        try {
            $env:KOMOREBI_CONFIG_HOME = Join-Path $RepoRoot 'komorebi'
            $checkOutput = & $komorebic.Source check 2>&1
            $checkPassed = $LASTEXITCODE -eq 0
            $detail = if ($checkPassed) { 'komorebic check OK' } else { (@($checkOutput) -join ' ').Trim() }
            [void]$results.Add((New-WinDotfilesCheckResult 'Config valid: komorebic check' $checkPassed $detail))
        }
        catch {
            [void]$results.Add((New-WinDotfilesCheckResult 'Config valid: komorebic check' $true "skipped: $($_.Exception.Message)"))
        }
        finally {
            if ($null -eq $previousConfigHome) {
                Remove-Item Env:KOMOREBI_CONFIG_HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:KOMOREBI_CONFIG_HOME = $previousConfigHome
            }
        }
    }

    $results
}

function New-WinDotfilesCheckResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Detail
    )

    [PSCustomObject]@{
        Name   = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

function Test-WinDotfilesWritableDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [PSCustomObject]@{
            Passed = $false
            Detail = 'directory not found'
        }
    }

    $testPath = Join-Path $Path 'win-dotfiles-write-test.tmp'

    try {
        Set-Content -LiteralPath $testPath -Value 'ok' -Encoding utf8 -ErrorAction Stop
        $cleanupDetail = 'OK'

        try {
            Remove-Item -LiteralPath $testPath -Force -ErrorAction Stop
        }
        catch {
            $cleanupDetail = "write OK; cleanup denied: $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            Passed = $true
            Detail = $cleanupDetail
        }
    }
    catch {
        [PSCustomObject]@{
            Passed = $false
            Detail = $_.Exception.Message
        }
    }
}

function Test-WinDotfiles {
    [CmdletBinding()]
    param([switch]$Quiet)

    $results = @()
    $profileRoot = Join-Path $WinDotfilesRoot 'powershell'
    $profileScriptsRoot = Join-Path $profileRoot 'profile.d'
    $profilePath = Join-Path $profileRoot 'profile.ps1'
    $projectRegistryPath = Join-Path $profileRoot 'projects.json'

    $results += New-WinDotfilesCheckResult 'PowerShell profile exists' (Test-Path -LiteralPath $profilePath -PathType Leaf) $profilePath
    $results += New-WinDotfilesCheckResult 'PowerShell profile.d exists' (Test-Path -LiteralPath $profileScriptsRoot -PathType Container) $profileScriptsRoot
    $results += New-WinDotfilesCheckResult 'Starship config exists' (Test-Path -LiteralPath $env:STARSHIP_CONFIG -PathType Leaf) $env:STARSHIP_CONFIG
    $results += New-WinDotfilesCheckResult 'Komorebi config exists' (Test-Path -LiteralPath (Join-Path $WinDotfilesRoot 'komorebi\komorebi.json') -PathType Leaf) (Join-Path $WinDotfilesRoot 'komorebi\komorebi.json')
    $results += New-WinDotfilesCheckResult 'whkd config exists' (Test-Path -LiteralPath (Join-Path $WinDotfilesRoot 'komorebi\whkdrc') -PathType Leaf) (Join-Path $WinDotfilesRoot 'komorebi\whkdrc')

    $requiredDirectories = @($WorkspaceRoot, $ProjectsRoot, $ToolsRoot, $CacheRoot, $TempRoot, $env:STARSHIP_CACHE, $env:NPM_CONFIG_PREFIX, $env:NPM_CONFIG_CACHE, $env:PIP_CACHE_DIR, $env:DOTNET_CLI_HOME, $env:WINDOTFILES_DOTNET_ARTIFACTS_PATH, $env:NUGET_HTTP_CACHE_PATH, $env:NUGET_PLUGINS_CACHE_PATH)
    foreach ($directory in $requiredDirectories | Where-Object { $_ } | Select-Object -Unique) {
        $results += New-WinDotfilesCheckResult "Directory exists: $directory" (Test-Path -LiteralPath $directory -PathType Container) $directory
    }

    foreach ($directory in @($env:TEMP, $env:TMP, $env:TMPDIR, $env:DOTNET_CLI_HOME, $env:WINDOTFILES_DOTNET_ARTIFACTS_PATH, $env:NUGET_HTTP_CACHE_PATH, $env:NUGET_PLUGINS_CACHE_PATH) | Where-Object { $_ } | Select-Object -Unique) {
        $writeCheck = Test-WinDotfilesWritableDirectory -Path $directory
        $results += New-WinDotfilesCheckResult "Directory writable: $directory" $writeCheck.Passed $writeCheck.Detail
    }

    if ($IsCodexShell) {
        $resolvedCodexTempRoot = [IO.Path]::GetFullPath($TempRoot)
        $resolvedWinDotfilesRoot = [IO.Path]::GetFullPath($WinDotfilesRoot)
        $resolvedSlashTempRoot = [IO.Path]::GetFullPath('C:\tmp')
        $resolvedLocalAppDataTempRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp'))
        $resolvedCurrentDirectory = $null
        try {
            if ((Get-Location).Provider.Name -eq 'FileSystem') {
                $resolvedCurrentDirectory = [IO.Path]::GetFullPath((Get-Location).Path)
            }
        }
        catch {
            $resolvedCurrentDirectory = $null
        }

        $codexTempIsSandboxScoped = $resolvedCodexTempRoot.StartsWith($resolvedWinDotfilesRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $resolvedCodexTempRoot.StartsWith($resolvedSlashTempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $resolvedCodexTempRoot.StartsWith($resolvedLocalAppDataTempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        ($resolvedCurrentDirectory -and $resolvedCodexTempRoot.StartsWith($resolvedCurrentDirectory, [StringComparison]::OrdinalIgnoreCase))
        $results += New-WinDotfilesCheckResult 'Codex temp root is sandbox-scoped' $codexTempIsSandboxScoped $TempRoot

        $dotnetCliHomeIsWorkspaceLocal = [IO.Path]::GetFullPath($env:DOTNET_CLI_HOME).StartsWith([IO.Path]::GetFullPath($WinDotfilesRoot), [StringComparison]::OrdinalIgnoreCase)
        $dotnetCliHomeIsSlashTempLocal = [IO.Path]::GetFullPath($env:DOTNET_CLI_HOME).StartsWith($resolvedSlashTempRoot, [StringComparison]::OrdinalIgnoreCase)
        $dotnetCliHomeIsLocalAppDataTempLocal = [IO.Path]::GetFullPath($env:DOTNET_CLI_HOME).StartsWith($resolvedLocalAppDataTempRoot, [StringComparison]::OrdinalIgnoreCase)
        $dotnetCliHomeIsCurrentDirectoryLocal = $resolvedCurrentDirectory -and [IO.Path]::GetFullPath($env:DOTNET_CLI_HOME).StartsWith($resolvedCurrentDirectory, [StringComparison]::OrdinalIgnoreCase)
        $results += New-WinDotfilesCheckResult 'Codex DOTNET_CLI_HOME is sandbox-scoped' ($dotnetCliHomeIsWorkspaceLocal -or $dotnetCliHomeIsSlashTempLocal -or $dotnetCliHomeIsLocalAppDataTempLocal -or $dotnetCliHomeIsCurrentDirectoryLocal) $env:DOTNET_CLI_HOME

        $msbuildNodeReuseDisabled = $env:MSBUILDDISABLENODEREUSE -eq '1'
        $results += New-WinDotfilesCheckResult 'Codex MSBuild node reuse disabled' $msbuildNodeReuseDisabled $env:MSBUILDDISABLENODEREUSE
    }

    $scriptParsePaths = @(
        $profilePath
        $profileScriptsRoot
        (Join-Path $profileRoot 'Modules')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $parseErrors = Test-PowerShellScriptsParse -Path $scriptParsePaths
    $results += New-WinDotfilesCheckResult 'PowerShell scripts parse' (-not $parseErrors) ($(if ($parseErrors) { "$(@($parseErrors).Count) parse error(s)" } else { 'OK' }))

    # Syntax-validate every committed config file (they are symlinked live, so a bad config would
    # otherwise fail silently on the desktop). Same gate the pre-commit hook and CI run.
    $results += @(Test-WinDotfilesConfig -RepoRoot $WinDotfilesRoot)

    $requiredCommands = @('git', 'rg', 'fzf', 'eza', 'bat', 'zoxide', 'nvm', 'dotnet', 'code', 'starship', 'komorebic', 'whkd')
    foreach ($command in $requiredCommands) {
        $resolved = Get-Command $command -ErrorAction SilentlyContinue
        $detail = if ($resolved) { $resolved.Source } else { 'not found' }
        $results += New-WinDotfilesCheckResult "Command available: $command" ([bool]$resolved) $detail
    }

    $baseProfileCommands = @(
        'project', 'proj', 'p', 'Add-ProjectGroup', 'addproj', 'apg', 'Add-Project', 'ap',
        'dev', 'gpl', 'gpsh', 'nr', 'gmain', 'gnew', 'gsync', 'gpub', 'gprune',
        'verify', 'awslambda', 'awslogs', 'fbdeploy', 'fbemu', 'stripelisten',
        'stripetrigger', 'histdoctor', 'workon', 'cmds', 'mycmds', 'gitlocks', 'gunlock',
        'projcache', 'profileperf', 'wincheck', 'winsmooth', 'wmstart', 'wmstop', 'wmcheck',
        'wmdev', 'wmbrowse', 'wmfocus', 'wmreset'
    )
    $projectGroupCommands = Get-ProjectGroups | ForEach-Object Command
    $requiredProfileCommands = @($baseProfileCommands + $projectGroupCommands) | Where-Object { $_ } | Select-Object -Unique
    foreach ($command in $requiredProfileCommands) {
        $resolved = Get-Command $command -ErrorAction SilentlyContinue
        $detail = if ($resolved) { [string]$resolved.CommandType } else { 'not found' }
        $results += New-WinDotfilesCheckResult "Profile command available: $command" ([bool]$resolved) $detail
    }

    $currentGitLock = Get-GitIndexLockInfo
    if ($currentGitLock) {
        $lockDetail = if ($currentGitLock.Exists) { "age=$($currentGitLock.AgeSeconds)s; stale=$($currentGitLock.Stale); $($currentGitLock.LockPath)" } else { $currentGitLock.LockPath }
        $results += New-WinDotfilesCheckResult 'Current Git index.lock absent' (-not $currentGitLock.Exists) $lockDetail
    }

    if (Test-Path -LiteralPath $projectRegistryPath -PathType Leaf) {
        try {
            $projectRegistry = Get-Content -LiteralPath $projectRegistryPath -Raw | ConvertFrom-Json
            $registryValid = [bool]$projectRegistry.groups
            $results += New-WinDotfilesCheckResult 'Project registry loads' $registryValid $projectRegistryPath

            foreach ($group in @($projectRegistry.groups)) {
                $hasRequiredFields = [bool]($group.name -and $group.command -and $group.path)
                $results += New-WinDotfilesCheckResult "Project group fields: $($group.name)" $hasRequiredFields $group.command

                if ($group.path) {
                    $projectPath = Resolve-ProjectPath ([string]$group.path)
                    $results += New-WinDotfilesCheckResult "Project group path exists: $($group.name)" (Test-Path -LiteralPath $projectPath -PathType Container) $projectPath
                }
            }
        }
        catch {
            $results += New-WinDotfilesCheckResult 'Project registry loads' $false $_.Exception.Message
        }
    }
    else {
        $results += New-WinDotfilesCheckResult 'Project registry exists' $false $projectRegistryPath
    }

    $profileLinkPath = Join-Path $PowerShellRoot 'Microsoft.PowerShell_profile.ps1'
    $profileLink = Get-Item -LiteralPath $profileLinkPath -Force -ErrorAction SilentlyContinue
    $linkOk = [bool]$profileLink
    if ($profileLink -and $profileLink.LinkType -eq 'SymbolicLink') {
        $linkOk = [IO.Path]::GetFullPath($profileLink.Target) -eq [IO.Path]::GetFullPath($profilePath)
    }
    elseif ($profileLink -and $profileLink.LinkType -eq 'HardLink') {
        $linkOk = $true
    }
    $results += New-WinDotfilesCheckResult 'Active profile link exists' $linkOk $profileLinkPath

    if (-not $Quiet) {
        $results |
        Sort-Object Passed, Name |
        Format-Table -AutoSize |
        Out-Host
    }

    if ($results.Passed -contains $false) {
        return $results
    }

    $results
}

function Invoke-WinDotfilesDoctor {
    [CmdletBinding()]
    param()

    $results = Test-WinDotfiles
    $failed = @($results | Where-Object { -not $_.Passed })

    if ($failed) {
        Write-Warning "$($failed.Count) win-dotfiles check(s) failed."
    }
    else {
        Write-Host 'All win-dotfiles checks passed.' -ForegroundColor Green
    }
}

Set-Alias -Name dotdoctor -Value Invoke-WinDotfilesDoctor
