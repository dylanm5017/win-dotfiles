function Initialize-WinDotfiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Root = $WinDotfilesRoot,
        [switch]$NoRelink,
        [switch]$NoCommit
    )

    $repoRoot = [IO.Path]::GetFullPath($Root)
    $repoPowerShellRoot = Join-Path $repoRoot 'powershell'
    $repoProfileRoot = Join-Path $repoPowerShellRoot 'profile.d'
    $repoProfilePath = Join-Path $repoPowerShellRoot 'profile.ps1'
    $repoConfigPath = Join-Path $repoPowerShellRoot 'powershell.config.json'
    $repoStarshipPath = Join-Path $repoRoot 'starship.toml'
    $profileLinkPath = Join-Path $PowerShellRoot 'Microsoft.PowerShell_profile.ps1'
    $sourceProfilePath = $profileLinkPath
    $profileItem = Get-Item -LiteralPath $profileLinkPath -Force -ErrorAction SilentlyContinue

    if ($profileItem -and $profileItem.LinkType -eq 'SymbolicLink' -and $profileItem.Target) {
        $sourceProfilePath = $profileItem.Target
    }
    elseif ($profileItem -and $profileItem.LinkType -eq 'HardLink' -and (Test-Path -LiteralPath $repoProfilePath)) {
        $sourceProfilePath = $repoProfilePath
    }

    $pathsToCreate = @($repoRoot, $repoPowerShellRoot, $repoProfileRoot)
    foreach ($path in $pathsToCreate) {
        if ($PSCmdlet.ShouldProcess($path, 'Create directory')) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    $gitignorePath = Join-Path $repoRoot '.gitignore'
    $gitignoreContent = @'
.cache/
.tmp/
Scripts/InstalledScriptInfos/
Modules/ImportExcel/
Modules/PSReadLine/
Modules/Terminal-Icons/
Modules/Microsoft.WinGet.*/
*.log
*.tmp
*.temp
*.xlsx
*.xls
*.csv
*.secret
*.secrets
*.token
*.tokens
.env
.env.*
powershell/profile.local.ps1
'@

    if (-not (Test-Path -LiteralPath $gitignorePath)) {
        if ($PSCmdlet.ShouldProcess($gitignorePath, 'Create .gitignore')) {
            Set-Content -LiteralPath $gitignorePath -Value $gitignoreContent -Encoding utf8
        }
    }

    $readmePath = Join-Path $repoRoot 'README.md'
    $readmeContent = @'
# Windows Dotfiles

Personal Windows shell configuration.

Tracked:
- PowerShell profile loader
- PowerShell profile.d scripts
- Project registry
- PowerShell config
- Starship config
- Shell helper functions and aliases

Not tracked:
- Installed PowerShell Gallery modules
- Caches
- Generated reports
- Local secrets

## Project navigation

Project groups live in `powershell/projects.json` (a generic example). To keep private
group names out of the repo, create `powershell/projects.local.json` with the same shape —
it is gitignored and takes precedence over the committed example when present.

- `project` / `proj` opens the fuzzy project picker.
- `project Sandbox` opens the configured group picker.
- `project win-dotfiles` jumps directly when a unique repo match exists.
- Group shortcuts such as `play`, `sbx`, and `clients` are generated from the registry.
- `addproj Sandbox` adds a new group to the registry, deriving the command and relative path by default.
- `apg Clients` creates/registers a project group under `C:\Workspace\Projects`.
- `ap -Group Clients -Mode empty -Name app` creates an empty project inside a group.
- `ap -Group Clients -Mode clone -GitUrl <url>` clones a repo into a group.
- `projcache` shows the persistent project directory cache; `projcache -Refresh` rebuilds it after adding or moving repos.

## Reliability

- `dotdoctor` runs the win-dotfiles health check.
- `powershell/Test-WinDotfiles.ps1` runs the same checks from a clean PowerShell process.
- Set `WINDOTFILES_PROFILE_DEBUG=1` before loading the profile to print per-script load times.
- `profileperf` reports profile script timing, Starship prompt timing, and cached project lookup timing; add `-RefreshProjects` to include a full project scan.
- Codex shells prefer `C:\tmp\codex` when it supports create/delete; otherwise they fall back to repo-local `.tmp\codex` for `TEMP`/`TMP`/`TMPDIR`, `DOTNET_CLI_HOME`, .NET artifacts, and NuGet transient caches, with MSBuild node reuse disabled so sandboxed .NET builds avoid user-profile temp/state permission issues where possible.
- Add machine-specific settings to `powershell/profile.local.ps1`; it is ignored by git.

## Workflow helpers

- `cmds` / `mycmds` shows a grouped catalog of custom commands; use `cmds git` or `cmds -Search deploy` to filter it.
- `nr` fuzzy-picks or runs npm scripts from the nearest `package.json`.
- `verify` runs the best available project check: npm `verify`/`test`/`build`, then .NET test/build.
- `gmain`, `gnew`, `gsync`, `gpub`, and `gprune` cover common Git branch chores.
- `gitlocks` shows Git `index.lock` files; `gunlock` clears a stale current-repo lock, and `gunlock -All` scans known project roots. In Codex, `gunlock` will call out when the sandbox requires an escalated rerun for `.git` metadata writes.
- `td` calculates one or more time ranges, with clock and decimal-hour output.
- `awslambda`, `awslogs`, `fbdeploy`, `fbemu`, `stripelisten`, and `stripetrigger` wrap common cloud CLI commands with visible context.
- `histdoctor` summarizes unavailable commands from PowerShell history without printing raw history lines.
- `workon` jumps to a project, records the last selection, and runs `git status`.
'@

    if (-not (Test-Path -LiteralPath $readmePath)) {
        if ($PSCmdlet.ShouldProcess($readmePath, 'Create README')) {
            Set-Content -LiteralPath $readmePath -Value $readmeContent -Encoding utf8
        }
    }

    $resolvedSourceProfile = if (Test-Path -LiteralPath $sourceProfilePath) {
        [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $sourceProfilePath).Path)
    }
    else {
        $null
    }

    $resolvedRepoProfile = [IO.Path]::GetFullPath($repoProfilePath)
    if ($resolvedSourceProfile -and ($resolvedSourceProfile -ne $resolvedRepoProfile) -and -not (Test-Path -LiteralPath $repoProfilePath)) {
        if ($PSCmdlet.ShouldProcess($repoProfilePath, "Copy profile from $resolvedSourceProfile")) {
            Copy-Item -LiteralPath $resolvedSourceProfile -Destination $repoProfilePath -Force
        }
    }
    elseif (-not (Test-Path -LiteralPath $repoProfilePath)) {
        if ($PSCmdlet.ShouldProcess($repoProfilePath, 'Create empty profile placeholder')) {
            New-Item -ItemType File -Path $repoProfilePath -Force | Out-Null
        }
    }

    $sourceConfigPath = Join-Path $PowerShellRoot 'powershell.config.json'
    if (Test-Path -LiteralPath $sourceConfigPath) {
        if ($PSCmdlet.ShouldProcess($repoConfigPath, "Copy PowerShell config from $sourceConfigPath")) {
            Copy-Item -LiteralPath $sourceConfigPath -Destination $repoConfigPath -Force
        }
    }
    elseif (-not (Test-Path -LiteralPath $repoConfigPath)) {
        if ($PSCmdlet.ShouldProcess($repoConfigPath, 'Create PowerShell config placeholder')) {
            Set-Content -LiteralPath $repoConfigPath -Value '{}' -Encoding utf8
        }
    }

    $starshipSources = @(
        $repoStarshipPath
        (Join-Path $DotfilesRoot 'starship.toml')
    ) | Select-Object -Unique
    $sourceStarshipPath = $starshipSources | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($sourceStarshipPath -and ([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $sourceStarshipPath).Path) -ne [IO.Path]::GetFullPath($repoStarshipPath))) {
        if ($PSCmdlet.ShouldProcess($repoStarshipPath, "Copy starship config from $sourceStarshipPath")) {
            Copy-Item -LiteralPath $sourceStarshipPath -Destination $repoStarshipPath -Force
        }
    }
    elseif (-not (Test-Path -LiteralPath $repoStarshipPath)) {
        if ($PSCmdlet.ShouldProcess($repoStarshipPath, 'Create starship config placeholder')) {
            Set-Content -LiteralPath $repoStarshipPath -Value '# Windows starship config' -Encoding utf8
        }
    }

    if (-not $NoRelink) {
        $profileLinkItem = Get-Item -LiteralPath $profileLinkPath -Force -ErrorAction SilentlyContinue
        $manualRelink = "New-Item -ItemType SymbolicLink -Path '$profileLinkPath' -Target '$repoProfilePath' -Force"

        if ($profileLinkItem -and $profileLinkItem.LinkType -eq 'HardLink') {
            Write-Host "Profile path is already a hard link: $profileLinkPath"
        }
        elseif ($profileLinkItem -and $profileLinkItem.LinkType -ne 'SymbolicLink') {
            Write-Warning "Refusing to replace non-symlink profile: $profileLinkPath"
            Write-Warning "Manual relink command, after backing up that file: $manualRelink"
        }
        elseif (-not $profileLinkItem -or $profileLinkItem.Target -ne $repoProfilePath) {
            try {
                if ($profileLinkItem -and $PSCmdlet.ShouldProcess($profileLinkPath, 'Remove existing profile symlink')) {
                    Remove-Item -LiteralPath $profileLinkPath -Force
                }

                if ($PSCmdlet.ShouldProcess($profileLinkPath, "Create profile symlink to $repoProfilePath")) {
                    New-Item -ItemType SymbolicLink -Path $profileLinkPath -Target $repoProfilePath -Force -ErrorAction Stop | Out-Null
                }
            }
            catch {
                Write-Warning "Profile relink failed: $($_.Exception.Message)"
                $hardLinkCommand = "New-Item -ItemType HardLink -Path '$profileLinkPath' -Target '$repoProfilePath' -Force"

                if (-not (Test-Path -LiteralPath $profileLinkPath)) {
                    try {
                        if ($PSCmdlet.ShouldProcess($profileLinkPath, "Create hard link fallback to $repoProfilePath")) {
                            New-Item -ItemType HardLink -Path $profileLinkPath -Target $repoProfilePath -Force -ErrorAction Stop | Out-Null
                            Write-Warning "Created a hard link fallback because Windows denied symlink creation."
                        }
                    }
                    catch {
                        Write-Warning "Hard link fallback failed: $($_.Exception.Message)"
                        Write-Warning "Run this in an elevated shell if needed:"
                        Write-Warning $manualRelink
                        Write-Warning "Non-admin fallback command:"
                        Write-Warning $hardLinkCommand
                    }
                }
                else {
                    Write-Warning "Run this in an elevated shell if needed:"
                    Write-Warning $manualRelink
                }
            }
        }
    }

    if (-not (Test-Command git -Application)) {
        Write-Warning 'git is not installed or not on PATH.'
        return
    }

    if ($WhatIfPreference) {
        Write-Host "What if: git init -b main in $repoRoot"
        Write-Host "What if: git add . in $repoRoot"
        if (-not $NoCommit) {
            Write-Host "What if: git commit -m 'Initial Windows dotfiles' if the repo has no commits"
        }
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
        git -C $repoRoot init -b main | Out-Host
    }

    git -C $repoRoot add . | Out-Host

    if (-not $NoCommit) {
        git -C $repoRoot rev-parse --verify HEAD *> $null
        if ($LASTEXITCODE -ne 0) {
            git -C $repoRoot commit -m 'Initial Windows dotfiles' | Out-Host
        }
    }

    git -C $repoRoot status --short | Out-Host
}

Set-Alias -Name init-win-dotfiles -Value Initialize-WinDotfiles
