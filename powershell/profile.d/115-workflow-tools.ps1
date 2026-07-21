function Find-UpwardFile {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$StartPath = (Get-Location).Path
    )

    $current = Get-Item -LiteralPath $StartPath -ErrorAction SilentlyContinue
    if (-not $current) {
        return $null
    }

    if (-not $current.PSIsContainer) {
        $current = $current.Directory
    }

    while ($current) {
        $candidate = Join-Path $current.FullName $FileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }

        $current = $current.Parent
    }

    $null
}

function Find-UpwardChildFile {
    param(
        [Parameter(Mandatory)][string]$Filter,
        [string]$StartPath = (Get-Location).Path
    )

    $current = Get-Item -LiteralPath $StartPath -ErrorAction SilentlyContinue
    if (-not $current) {
        return $null
    }

    if (-not $current.PSIsContainer) {
        $current = $current.Directory
    }

    while ($current) {
        $candidate = Get-ChildItem -LiteralPath $current.FullName -Filter $Filter -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }

        $current = $current.Parent
    }

    $null
}

function dotnet {
    [CmdletBinding(PositionalBinding = $false)]
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $dotnetCommand = Get-Command dotnet.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $dotnetCommand) {
        Write-Warning 'dotnet.exe is not installed or not on PATH.'
        return
    }

    $dotnetArgs = @($Arguments)
    $subcommand = if ($dotnetArgs.Count -gt 0) { $dotnetArgs[0].ToLowerInvariant() } else { '' }

    if ($IsCodexShell -and $subcommand -in @('build', 'test', 'publish', 'pack')) {
        $hasArtifactsPath = [bool]($dotnetArgs | Where-Object { $_ -eq '--artifacts-path' -or $_ -like '--artifacts-path=*' })
        if ($env:WINDOTFILES_DOTNET_ARTIFACTS_PATH -and -not $hasArtifactsPath) {
            $dotnetArgs += @('--artifacts-path', $env:WINDOTFILES_DOTNET_ARTIFACTS_PATH)
        }

        $hasSharedCompilationProperty = [bool]($dotnetArgs | Where-Object { $_ -like '-p:UseSharedCompilation=*' -or $_ -like '/p:UseSharedCompilation=*' })
        if (-not $hasSharedCompilationProperty) {
            $dotnetArgs += '-p:UseSharedCompilation=false'
        }
    }

    & $dotnetCommand.Source @dotnetArgs
}

function Get-PackageJsonPath {
    Find-UpwardFile -FileName 'package.json'
}

function Get-PackageScripts {
    param([string]$PackageJsonPath = (Get-PackageJsonPath))

    if (-not $PackageJsonPath -or -not (Test-Path -LiteralPath $PackageJsonPath -PathType Leaf)) {
        return @()
    }

    try {
        $package = Get-Content -LiteralPath $PackageJsonPath -Raw | ConvertFrom-Json
        if (-not $package.scripts) {
            return @()
        }

        @($package.scripts.PSObject.Properties | Sort-Object Name | ForEach-Object {
            [PSCustomObject]@{
                Name    = $_.Name
                Command = [string]$_.Value
            }
        })
    }
    catch {
        Write-Warning "package.json could not be read: $($_.Exception.Message)"
        @()
    }
}

function Select-NpmScript {
    param([Parameter(Mandatory)][object[]]$Scripts)

    if (Test-Command fzf -Application) {
        $fzfArgs = New-FzfArgs `
            -Prompt 'npm run> ' `
            -Label 'npm scripts' `
            -Preview 'echo {2}' `
            -PreviewWindow 'down:4,border-rounded,wrap' `
            -ExtraArgs @('--with-nth', '1,2', '--delimiter', "`t")

        $selected = $Scripts |
        ForEach-Object { "{0}`t{1}" -f $_.Name, $_.Command } |
        fzf @fzfArgs

        if ($selected) {
            return ($selected -split "`t", 2)[0]
        }

        return $null
    }

    Select-FromNumberedMenu -Items $Scripts -Prompt 'npm script' -PassThruText `
        -DisplayScript { param($script) '{0}  {1}' -f $script.Name, $script.Command } `
        -ValueScript { param($script) $script.Name }
}

function Invoke-NpmScript {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Script,

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$ScriptArgs
    )

    if (-not (Test-Command npm -Application)) {
        Write-Warning 'npm is not installed or not on PATH.'
        return
    }

    $packageJsonPath = Get-PackageJsonPath
    if (-not $packageJsonPath) {
        Write-Warning 'No package.json found in this directory or any parent.'
        return
    }

    $scripts = @(Get-PackageScripts -PackageJsonPath $packageJsonPath)
    if (-not $scripts) {
        Write-Warning "No npm scripts found in $packageJsonPath"
        return
    }

    if (-not $Script) {
        $Script = Select-NpmScript -Scripts $scripts
    }

    if (-not $Script) {
        return
    }

    if ($scripts.Name -notcontains $Script) {
        Write-Warning "npm script not found: $Script"
        return
    }

    Push-Location -LiteralPath (Split-Path -Parent $packageJsonPath)
    try {
        if ($ScriptArgs) {
            npm run $Script -- @ScriptArgs
        }
        else {
            npm run $Script
        }
    }
    finally {
        Pop-Location
    }
}

Set-Alias -Name nr -Value Invoke-NpmScript

function Test-GitRepository {
    git rev-parse --is-inside-work-tree *> $null
    $LASTEXITCODE -eq 0
}

function Get-GitDefaultBranch {
    if (-not (Test-GitRepository)) {
        return $null
    }

    $remoteHead = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $remoteHead) {
        return ($remoteHead -replace '^origin/', '')
    }

    foreach ($branch in 'main', 'master') {
        git show-ref --verify --quiet "refs/heads/$branch"
        if ($LASTEXITCODE -eq 0) {
            return $branch
        }
    }

    'main'
}

function Get-GitRepositoryRoot {
    param([string]$Path = (Get-Location).Path)

    $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $gitCommand -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $root = & $gitCommand.Source -C $Path rev-parse --show-toplevel 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $root) {
        return $null
    }

    [IO.Path]::GetFullPath($root)
}

function Get-GitDirectoryPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        return $null
    }

    $gitDirectory = & $gitCommand.Source -C $RepositoryRoot rev-parse --git-dir 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $gitDirectory) {
        return $null
    }

    if ([IO.Path]::IsPathRooted($gitDirectory)) {
        return [IO.Path]::GetFullPath($gitDirectory)
    }

    [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $gitDirectory))
}

function Test-StringContainsPath {
    param(
        [string]$Value,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or [string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $normalizedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $forwardSlashPath = $normalizedPath -replace '\\', '/'

    $Value.IndexOf($normalizedPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $Value.IndexOf($forwardSlashPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-GitProcessesForRepository {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    try {
        Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object {
            $_.Name -like 'git*.exe' -and
            (Test-StringContainsPath -Value $_.CommandLine -Path $RepositoryRoot)
        } |
        Select-Object ProcessId, Name, CommandLine
    }
    catch {
        @()
    }
}

function Get-GitIndexLockInfo {
    param(
        [string]$Path = (Get-Location).Path,
        [int]$MinimumAgeSeconds = 30
    )

    $repositoryRoot = Get-GitRepositoryRoot -Path $Path
    if (-not $repositoryRoot) {
        return $null
    }

    $gitDirectory = Get-GitDirectoryPath -RepositoryRoot $repositoryRoot
    if (-not $gitDirectory) {
        return $null
    }

    $lockPath = Join-Path $gitDirectory 'index.lock'
    $lockItem = Get-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    $activeProcesses = if ($lockItem) { @(Get-GitProcessesForRepository -RepositoryRoot $repositoryRoot) } else { @() }
    $age = if ($lockItem) { (Get-Date) - $lockItem.LastWriteTime } else { $null }

    [PSCustomObject]@{
        RepositoryRoot       = $repositoryRoot
        GitDirectory         = $gitDirectory
        LockPath             = $lockPath
        Exists               = [bool]$lockItem
        LastWriteTime        = if ($lockItem) { $lockItem.LastWriteTime } else { $null }
        AgeSeconds           = if ($age) { [math]::Round($age.TotalSeconds, 1) } else { $null }
        Size                 = if ($lockItem) { $lockItem.Length } else { $null }
        ActiveGitProcesses   = $activeProcesses.Count
        ActiveGitProcessIds  = ($activeProcesses.ProcessId -join ',')
        Stale                = [bool]($lockItem -and $age.TotalSeconds -ge $MinimumAgeSeconds -and -not $activeProcesses)
        MinimumAgeSeconds    = $MinimumAgeSeconds
    }
}

function Get-GitLockScanRoots {
    param([switch]$All)

    $roots = New-Object System.Collections.Generic.List[string]
    $currentRoot = Get-GitRepositoryRoot
    if ($currentRoot) {
        $roots.Add($currentRoot)
    }

    if ($All -and (Test-Command Get-KnownProjectDirectories)) {
        foreach ($projectDirectory in @(Get-KnownProjectDirectories)) {
            $projectRoot = Get-GitRepositoryRoot -Path $projectDirectory.FullName
            if ($projectRoot) {
                $roots.Add($projectRoot)
            }
        }
    }

    $roots | Sort-Object -Unique
}

function Show-GitIndexLocks {
    [CmdletBinding()]
    param(
        [switch]$All,
        [switch]$IncludeClean,
        [int]$MinimumAgeSeconds = 30
    )

    $lockInfos = @(Get-GitLockScanRoots -All:$All | ForEach-Object {
            Get-GitIndexLockInfo -Path $_ -MinimumAgeSeconds $MinimumAgeSeconds
        } | Where-Object { $_ })

    if (-not $IncludeClean) {
        $lockInfos = @($lockInfos | Where-Object Exists)
    }

    if (-not $lockInfos) {
        Write-Host 'No Git index.lock files found.' -ForegroundColor Green
        return
    }

    $lockInfos |
    Select-Object RepositoryRoot, Exists, Stale, AgeSeconds, ActiveGitProcesses, LockPath |
    Format-Table -AutoSize
}

function Repair-GitIndexLock {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$All,
        [switch]$Force,
        [int]$MinimumAgeSeconds = 30
    )

    $lockInfos = @(Get-GitLockScanRoots -All:$All | ForEach-Object {
            Get-GitIndexLockInfo -Path $_ -MinimumAgeSeconds $MinimumAgeSeconds
        } | Where-Object { $_ -and $_.Exists })

    if (-not $lockInfos) {
        Write-Host 'No Git index.lock files found.' -ForegroundColor Green
        return
    }

    foreach ($lockInfo in $lockInfos) {
        if ($lockInfo.ActiveGitProcesses -gt 0) {
            Write-Warning "Skipping active Git lock in $($lockInfo.RepositoryRoot). Active git process id(s): $($lockInfo.ActiveGitProcessIds)"
            continue
        }

        if (-not $Force -and -not $lockInfo.Stale) {
            Write-Warning "Skipping young Git lock in $($lockInfo.RepositoryRoot). Age: $($lockInfo.AgeSeconds)s; use -Force if you know Git is not running."
            continue
        }

        if ($PSCmdlet.ShouldProcess($lockInfo.LockPath, 'Remove stale Git index.lock')) {
            try {
                Remove-Item -LiteralPath $lockInfo.LockPath -Force -ErrorAction Stop
                Write-Host "Removed stale Git index.lock: $($lockInfo.LockPath)" -ForegroundColor Green
            }
            catch {
                Write-Warning "Could not remove $($lockInfo.LockPath): $($_.Exception.Message)"

                if ($IsCodexShell) {
                    $retryCommand = @('gunlock')
                    if ($All) {
                        $retryCommand += '-All'
                    }

                    if ($Force) {
                        $retryCommand += '-Force'
                    }
                    elseif ($MinimumAgeSeconds -ne 30) {
                        $retryCommand += "-MinimumAgeSeconds $MinimumAgeSeconds"
                    }

                    Write-Warning "Codex may need an escalated shell command for .git metadata writes. Retry the same scoped repair with escalation: $($retryCommand -join ' ')"
                }
            }
        }
    }
}

Set-Alias -Name gitlocks -Value Show-GitIndexLocks
Set-Alias -Name gunlock -Value Repair-GitIndexLock

function gmain {
    [CmdletBinding()]
    param([switch]$Pull)

    $defaultBranch = Get-GitDefaultBranch
    if (-not $defaultBranch) {
        Write-Warning 'Not inside a Git repository.'
        return
    }

    git switch $defaultBranch
    if ($LASTEXITCODE -eq 0 -and $Pull) {
        git pull --ff-only
    }
}

function gnew {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [switch]$FromMain
    )

    if (-not (Test-GitRepository)) {
        Write-Warning 'Not inside a Git repository.'
        return
    }

    if ($FromMain) {
        gmain -Pull
        if ($LASTEXITCODE -ne 0) {
            return
        }
    }

    git switch -c $Name
}

function gsync {
    [CmdletBinding()]
    param([switch]$NoFetch)

    if (-not (Test-GitRepository)) {
        Write-Warning 'Not inside a Git repository.'
        return
    }

    if (-not $NoFetch) {
        git fetch --prune
        if ($LASTEXITCODE -ne 0) {
            return
        }
    }

    $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstream) {
        git pull --ff-only
    }
    else {
        Write-Warning 'Current branch has no upstream. Use gpub to publish it.'
    }
}

function gpub {
    [CmdletBinding()]
    param([string]$Remote = 'origin')

    if (-not (Test-GitRepository)) {
        Write-Warning 'Not inside a Git repository.'
        return
    }

    $branch = git branch --show-current
    if (-not $branch) {
        Write-Warning 'Could not determine the current branch.'
        return
    }

    git push -u $Remote $branch
}

function gprune {
    [CmdletBinding()]
    param(
        [switch]$GoneOnly,
        [switch]$MergedOnly,
        [switch]$ForceDelete
    )

    if (-not (Test-GitRepository)) {
        Write-Warning 'Not inside a Git repository.'
        return
    }

    git fetch --prune

    $defaultBranch = Get-GitDefaultBranch
    $currentBranch = git branch --show-current
    $goneBranches = @()
    $mergedBranches = @()

    if (-not $MergedOnly) {
        $goneBranches = @(git branch --format='%(refname:short)|%(upstream:track)' |
            Where-Object { $_ -match '\[gone\]' } |
            ForEach-Object { ($_ -split '\|', 2)[0].Trim() })
    }

    if (-not $GoneOnly -and $defaultBranch) {
        $mergedBranches = @(git branch --merged $defaultBranch |
            ForEach-Object { $_.Trim().TrimStart('*').Trim() } |
            Where-Object { $_ -and $_ -notin @($currentBranch, $defaultBranch, 'main', 'master') })
    }

    $branches = @($goneBranches + $mergedBranches) | Where-Object { $_ } | Sort-Object -Unique
    if (-not $branches) {
        Write-Host 'No local branches to prune.' -ForegroundColor Green
        return
    }

    Write-Host 'Local branches eligible for pruning:' -ForegroundColor Cyan
    $branches | ForEach-Object { Write-Host "  $_" }
    $deleteArg = if ($ForceDelete) { '-D' } else { '-d' }
    $all = $false

    foreach ($branch in $branches) {
        if ($branch -eq $currentBranch) {
            continue
        }

        if (-not $all) {
            $answer = Read-Host "Delete '$branch'? (y/n/all/q)"
            if ($answer -match '^(q|quit)$') {
                break
            }
            if ($answer -match '^(all|a)$') {
                $all = $true
            }
            elseif ($answer -notmatch '^(y|yes)$') {
                continue
            }
        }

        git branch $deleteArg $branch
    }
}

function Invoke-ProjectVerify {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'verify', 'test', 'build')]
        [string]$Mode = 'auto'
    )

    $packageJsonPath = Get-PackageJsonPath
    if ($packageJsonPath) {
        $scripts = @(Get-PackageScripts -PackageJsonPath $packageJsonPath)
        $scriptNames = @($scripts | ForEach-Object Name)
        $preferredScripts = if ($Mode -eq 'auto') { @('verify', 'test', 'build') } else { @($Mode) }
        $script = $preferredScripts | Where-Object { $scriptNames -contains $_ } | Select-Object -First 1

        if ($script) {
            Push-Location -LiteralPath (Split-Path -Parent $packageJsonPath)
            try {
                npm run $script
            }
            finally {
                Pop-Location
            }
            return
        }
    }

    $solutionPath = Find-UpwardChildFile -Filter '*.sln'
    if (-not $solutionPath) {
        $solutionPath = Find-UpwardChildFile -Filter '*.csproj'
    }

    if ($solutionPath -and (Test-Command dotnet -Application)) {
        $dotnetCommand = if ($Mode -eq 'build') { 'build' } else { 'test' }
        dotnet $dotnetCommand $solutionPath
        return
    }

    Write-Warning 'No npm, .NET solution, or .NET project verification target was found.'
}

Set-Alias -Name verify -Value Invoke-ProjectVerify

function Set-WinDotfilesGitDefaults {
    [CmdletBinding()]
    param()

    if (-not (Test-Command git -Application)) {
        Write-Warning 'git is not installed or not on PATH.'
        return
    }

    # Friction-reducing global defaults, set only when unset so existing preferences are never clobbered.
    $defaults = [ordered]@{
        'rebase.autostash'      = 'true'
        'push.autoSetupRemote'  = 'true'
        'fetch.prune'           = 'true'
        'help.autocorrect'      = 'prompt'
    }

    foreach ($entry in $defaults.GetEnumerator()) {
        $current = git config --global --get $entry.Key
        if ([string]::IsNullOrWhiteSpace($current)) {
            git config --global $entry.Key $entry.Value
            Write-Host "git config --global $($entry.Key) = $($entry.Value)" -ForegroundColor Green
        }
        else {
            Write-Host "git config --global $($entry.Key) already set ($current); left as-is." -ForegroundColor DarkGray
        }
    }
}

Set-Alias -Name gitdefaults -Value Set-WinDotfilesGitDefaults

function Show-AwsCommandContext {
    param([Parameter(Mandatory)][string]$Service)

    $awsProfile = if ($env:AWS_PROFILE) { $env:AWS_PROFILE } else { 'default' }
    $region = if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { 'default' }
    Write-Host ("AWS {0}: profile={1}, region={2}" -f $Service, $awsProfile, $region) -ForegroundColor Cyan
}

function awslambda {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][string[]]$AwsArgs)

    if (-not (Test-Command aws -Application)) {
        Write-Warning 'aws is not installed or not on PATH.'
        return
    }

    Show-AwsCommandContext -Service 'lambda'
    if ($AwsArgs) {
        aws lambda @AwsArgs
    }
    else {
        aws lambda help
    }
}

function awslogs {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][string[]]$AwsArgs)

    if (-not (Test-Command aws -Application)) {
        Write-Warning 'aws is not installed or not on PATH.'
        return
    }

    Show-AwsCommandContext -Service 'logs'
    if ($AwsArgs) {
        aws logs @AwsArgs
    }
    else {
        aws logs help
    }
}

function Get-FirebaseProjectContext {
    $firebaseConfigPath = Find-UpwardFile -FileName '.firebaserc'
    if (-not $firebaseConfigPath) {
        return 'unknown'
    }

    try {
        $config = Get-Content -LiteralPath $firebaseConfigPath -Raw | ConvertFrom-Json
        if ($config.projects.default) {
            return $config.projects.default
        }
    }
    catch {
        return 'unreadable .firebaserc'
    }

    'unknown'
}

function fbdeploy {
    [CmdletBinding()]
    param(
        [string]$Project,
        [string[]]$Only,
        [switch]$Yes,
        [Parameter(ValueFromRemainingArguments)][string[]]$FirebaseArgs
    )

    if (-not (Test-Command firebase -Application)) {
        Write-Warning 'firebase is not installed or not on PATH.'
        return
    }

    $context = if ($Project) { $Project } else { Get-FirebaseProjectContext }
    Write-Host "Firebase deploy target: $context" -ForegroundColor Cyan
    if (-not $Yes) {
        $answer = Read-Host 'Continue with firebase deploy? (y/n)'
        if ($answer -notmatch '^(y|yes)$') {
            return
        }
    }

    $args = @('deploy')
    if ($Project) {
        $args += @('--project', $Project)
    }
    if ($Only) {
        $args += @('--only', ($Only -join ','))
    }
    if ($FirebaseArgs) {
        $args += $FirebaseArgs
    }

    firebase @args
}

function fbemu {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][string[]]$FirebaseArgs)

    if (-not (Test-Command firebase -Application)) {
        Write-Warning 'firebase is not installed or not on PATH.'
        return
    }

    Write-Host "Firebase emulator project: $(Get-FirebaseProjectContext)" -ForegroundColor Cyan
    firebase emulators:start @FirebaseArgs
}

function stripelisten {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)][string[]]$StripeArgs)

    if (-not (Test-Command stripe -Application)) {
        Write-Warning 'stripe is not installed or not on PATH.'
        return
    }

    Write-Host "Stripe listen in $(Get-Location)" -ForegroundColor Cyan
    stripe listen @StripeArgs
}

function stripetrigger {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Event,

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$StripeArgs
    )

    if (-not (Test-Command stripe -Application)) {
        Write-Warning 'stripe is not installed or not on PATH.'
        return
    }

    if (-not $Event) {
        Write-Warning 'Provide a Stripe trigger event, such as checkout.session.completed.'
        return
    }

    Write-Host "Stripe trigger: $Event" -ForegroundColor Cyan
    stripe trigger $Event @StripeArgs
}

function Get-HistoryCommandName {
    param([Parameter(Mandatory)][string]$Line)

    $trimmed = $Line.Trim()
    if (-not $trimmed) {
        return $null
    }

    if ($trimmed.StartsWith('& ')) {
        $trimmed = $trimmed.Substring(2).Trim()
    }

    $first = ($trimmed -split '\s+')[0].Trim('"', "'", '&')
    if (-not $first -or $first -match '^[`{}().;|]+$' -or $first -match '^[-$]') {
        return $null
    }

    $keywords = @('if', 'else', 'elseif', 'foreach', 'for', 'while', 'do', 'try', 'catch', 'finally', 'switch', 'function', 'param', 'return')
    if ($keywords -contains $first.ToLowerInvariant()) {
        return $null
    }

    $first
}

function Invoke-HistoryDoctor {
    [CmdletBinding()]
    param(
        [int]$Top = 30,
        [switch]$All
    )

    $historyPath = (Get-PSReadLineOption -ErrorAction SilentlyContinue).HistorySavePath
    if (-not $historyPath) {
        $historyPath = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
    }

    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning "PowerShell history was not found: $historyPath"
        return
    }

    $secretPattern = '(?i)(token|secret|password|passwd|pwd|apikey|api[_-]?key|authorization|bearer|credential|connectionstring|client[_-]?secret|access[_-]?token|refresh[_-]?token|sas|tenant|login)'
    $lines = @(Get-Content -LiteralPath $historyPath | Where-Object { $_ -and ($_ -notmatch $secretPattern) })
    $commands = @($lines | ForEach-Object { Get-HistoryCommandName $_ } | Where-Object { $_ })
    $groups = @($commands | Group-Object | Sort-Object Count -Descending)

    if ($All) {
        $groups | Select-Object -First $Top Count, Name
        return
    }

    $groups |
    Where-Object { -not (Test-Command $_.Name) } |
    Select-Object -First $Top Count, Name
}

Set-Alias -Name histdoctor -Value Invoke-HistoryDoctor

function New-WinDotfilesCommandInfo {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Description,
        [string]$Example,
        [string]$AliasOf
    )

    [PSCustomObject]@{
        Category    = $Category
        Command     = $Command
        Description = $Description
        Example     = $Example
        AliasOf     = $AliasOf
    }
}

function Get-WinDotfilesCommandCatalog {
    $commands = @(
        New-WinDotfilesCommandInfo 'Help' 'cmds' 'Show this custom command catalog.' 'cmds git'
        New-WinDotfilesCommandInfo 'Help' 'mycmds' 'Alias for cmds.' 'mycmds git' 'cmds'

        New-WinDotfilesCommandInfo 'Navigation' 'ws' 'Jump to C:\Workspace.' 'ws'
        New-WinDotfilesCommandInfo 'Navigation' 'projects' 'Jump to C:\Workspace\Projects.' 'projects'
        New-WinDotfilesCommandInfo 'Navigation' 'devroot' 'Jump to C:\Workspace\Dev.' 'devroot'
        New-WinDotfilesCommandInfo 'Navigation' 'tools' 'Jump to the tools directory.' 'tools'
        New-WinDotfilesCommandInfo 'Navigation' 'cache' 'Jump to the cache directory.' 'cache'
        New-WinDotfilesCommandInfo 'Navigation' 'inbox' 'Jump to C:\Workspace\Inbox.' 'inbox'
        New-WinDotfilesCommandInfo 'Navigation' 'winfiles' 'Jump to this dotfiles repo.' 'winfiles'
        New-WinDotfilesCommandInfo 'Navigation' 'project' 'Open the project picker or a named project/group in the terminal (add -Code to also open VS Code).' 'project sandbox'
        New-WinDotfilesCommandInfo 'Navigation' 'proj' 'Alias for project.' 'proj win-dotfiles' 'project'
        New-WinDotfilesCommandInfo 'Navigation' 'p' 'Alias for project.' 'p win-dotfiles' 'project'
        New-WinDotfilesCommandInfo 'Navigation' 'projcache' 'Show or refresh the cached project directory list.' 'projcache -Refresh'
        New-WinDotfilesCommandInfo 'Navigation' 'workon' 'Pick a project root, cd into it, remember it, and show git status.' 'workon sandbox'
        New-WinDotfilesCommandInfo 'Navigation' 'mark' 'Remember the current directory as a temporary mark.' 'mark'
        New-WinDotfilesCommandInfo 'Navigation' 'goto' 'Jump back to the temporary mark.' 'goto'
        New-WinDotfilesCommandInfo 'Navigation' 'ff' 'Find a file with fzf and preview it.' 'ff'

        New-WinDotfilesCommandInfo 'Project Registry' 'addproj' 'Add or update a project group in projects.json.' 'addproj Sandbox' 'Add-ProjectGroup'
        New-WinDotfilesCommandInfo 'Project Registry' 'apg' 'Alias for addproj.' 'apg Clients' 'Add-ProjectGroup'
        New-WinDotfilesCommandInfo 'Project Registry' 'ap' 'Create or clone a project inside a group.' 'ap -Group Clients -Mode empty -Name app' 'Add-Project'

        New-WinDotfilesCommandInfo 'Git' 'gs' 'git status.' 'gs'
        New-WinDotfilesCommandInfo 'Git' 'gc' 'git commit.' 'gc -m "message"'
        New-WinDotfilesCommandInfo 'Git' 'gp' 'git pull.' 'gp'
        New-WinDotfilesCommandInfo 'Git' 'gpl' 'git pull.' 'gpl'
        New-WinDotfilesCommandInfo 'Git' 'gpull' 'git pull.' 'gpull'
        New-WinDotfilesCommandInfo 'Git' 'gpsh' 'git push.' 'gpsh'
        New-WinDotfilesCommandInfo 'Git' 'gpush' 'git push.' 'gpush'
        New-WinDotfilesCommandInfo 'Git' 'gmain' 'Switch to the repo default branch; optionally pull.' 'gmain -Pull'
        New-WinDotfilesCommandInfo 'Git' 'gnew' 'Create and switch to a new branch.' 'gnew codex/my-change'
        New-WinDotfilesCommandInfo 'Git' 'gsync' 'Fetch/prune and fast-forward pull the current branch.' 'gsync'
        New-WinDotfilesCommandInfo 'Git' 'gpub' 'Publish the current branch with upstream tracking.' 'gpub'
        New-WinDotfilesCommandInfo 'Git' 'gprune' 'Interactively delete gone or merged local branches.' 'gprune'
        New-WinDotfilesCommandInfo 'Git' 'gitlocks' 'Show Git index.lock files in the current repo or known project roots.' 'gitlocks -All'
        New-WinDotfilesCommandInfo 'Git' 'gunlock' 'Safely remove stale Git index.lock files after checking age and active Git processes.' 'gunlock -All'
        New-WinDotfilesCommandInfo 'Git' 'dot' 'Run git against the old dotfiles root.' 'dot status'
        New-WinDotfilesCommandInfo 'Git' 'dot-add' 'Patch-add changes in the old dotfiles root.' 'dot-add'

        New-WinDotfilesCommandInfo 'Node/npm' 'nr' 'Pick or run an npm script from the nearest package.json.' 'nr build'
        New-WinDotfilesCommandInfo 'Node/npm' 'ni' 'Install a Node version, then use it.' 'ni 20'
        New-WinDotfilesCommandInfo 'Node/npm' 'nv' 'Use a Node version.' 'nv 20'
        New-WinDotfilesCommandInfo 'Node/npm' 'nd' 'Alias-style Node version switch.' 'nd'
        New-WinDotfilesCommandInfo 'Node/npm' 'nvmrc' 'Use or install the version from .node-version/.nvmrc.' 'nvmrc'
        New-WinDotfilesCommandInfo 'Node/npm' 'npmout' 'Export npm outdated results for the current repo.' 'npmout'
        New-WinDotfilesCommandInfo 'Node/npm' 'npmout-all' 'Export npm outdated results for child repos.' 'npmout-all'

        New-WinDotfilesCommandInfo 'Verification' 'verify' 'Run the best local project check.' 'verify'
        New-WinDotfilesCommandInfo 'Verification' 'dotdoctor' 'Run the win-dotfiles health check.' 'dotdoctor'
        New-WinDotfilesCommandInfo 'Verification' 'dev' 'Run repo/environment helper commands.' 'dev doctor'
        New-WinDotfilesCommandInfo 'Verification' 'histdoctor' 'Find stale/unavailable command names in PowerShell history.' 'histdoctor'
        New-WinDotfilesCommandInfo 'Verification' 'profileperf' 'Measure profile scripts, Starship prompt, and project cache timings.' 'profileperf -RefreshProjects'
        New-WinDotfilesCommandInfo 'Verification' 'wincheck' 'Report workstation friction across shell, startup, Defender, launcher roles, comfort tools, PowerToys, Terminal, and windowing.' 'wincheck -Detailed'
        New-WinDotfilesCommandInfo 'Verification' 'winsmooth' 'Preview or apply reversible workstation tuning with backups.' 'winsmooth -Apply'

        New-WinDotfilesCommandInfo 'Window Manager' 'wmcheck' 'Check the komorebi/whkd configuration.' 'wmcheck'
        New-WinDotfilesCommandInfo 'Window Manager' 'wmbrowse' 'Focus the browser workspace and set a clean columns layout.' 'wmbrowse'
        New-WinDotfilesCommandInfo 'Window Manager' 'wmdev' 'Focus DEV and set the ultrawide main-stack layout.' 'wmdev'
        New-WinDotfilesCommandInfo 'Window Manager' 'wmfocus' 'Toggle monocle for the focused container.' 'wmfocus'
        New-WinDotfilesCommandInfo 'Window Manager' 'wmreset' 'Reload the repo komorebi config and retile to clear layout quirks.' 'wmreset'
        New-WinDotfilesCommandInfo 'Window Manager' 'wmstart' 'Start komorebi with whkd using the repo-backed config.' 'wmstart'
        New-WinDotfilesCommandInfo 'Window Manager' 'wmstop' 'Stop komorebi and whkd, restoring hidden windows.' 'wmstop'

        New-WinDotfilesCommandInfo 'Theming' 'theme' 'Reskin terminal, prompt, komorebi, and the Windows desktop from one palette (ashes/dracula/nord/mocha).' 'theme dracula'

        New-WinDotfilesCommandInfo '.NET' 'dotnet' 'In Codex, adds sandbox-aware artifacts/MSBuild settings for build-like commands.' 'dotnet build'

        New-WinDotfilesCommandInfo 'Dev Utilities' 'findkill' 'Find and optionally kill the process listening on a port.' 'findkill 4200'
        New-WinDotfilesCommandInfo 'Dev Utilities' 'port' 'Show listeners for a local port.' 'port 3000'
        New-WinDotfilesCommandInfo 'Dev Utilities' 'repostat' 'Show branch and dirty status for child Git repos.' 'repostat'
        New-WinDotfilesCommandInfo 'Dev Utilities' 'foreachrepo' 'Run a command in each child Git repo.' 'foreachrepo "git status"'
        New-WinDotfilesCommandInfo 'Dev Utilities' 'note' 'Append a quick timestamped note to ~/notes.txt.' 'note "remember this"'
        New-WinDotfilesCommandInfo 'Dev Utilities' 'pkglist' 'Regenerate packages/scoop.json from the installed Scoop apps.' 'pkglist'
        New-WinDotfilesCommandInfo 'Dev Utilities' 'td' 'Calculate one or more time ranges.' 'td 9:15-10:45 11-12:30'

        New-WinDotfilesCommandInfo 'Cloud' 'awslambda' 'Run aws lambda commands after showing profile/region.' 'awslambda list-functions'
        New-WinDotfilesCommandInfo 'Cloud' 'awslogs' 'Run aws logs commands after showing profile/region.' 'awslogs tail /aws/lambda/name --follow'
        New-WinDotfilesCommandInfo 'Cloud' 'fbdeploy' 'Firebase deploy with visible target and confirmation.' 'fbdeploy -Only functions'
        New-WinDotfilesCommandInfo 'Cloud' 'fbemu' 'Start Firebase emulators with visible target.' 'fbemu'
        New-WinDotfilesCommandInfo 'Cloud' 'stripelisten' 'Start stripe listen in the current repo.' 'stripelisten'
        New-WinDotfilesCommandInfo 'Cloud' 'stripetrigger' 'Trigger a Stripe event.' 'stripetrigger checkout.session.completed'

        New-WinDotfilesCommandInfo 'SQL' 'startsql' 'Start the default SQL Server service as admin.' 'startsql'
        New-WinDotfilesCommandInfo 'SQL' 'stopsql' 'Stop the default SQL Server service as admin.' 'stopsql'
        New-WinDotfilesCommandInfo 'SQL' 'startagent' 'Start SQL Server Agent as admin.' 'startagent'
        New-WinDotfilesCommandInfo 'SQL' 'stopagent' 'Stop SQL Server Agent as admin.' 'stopagent'
        New-WinDotfilesCommandInfo 'SQL' 'startbrowser' 'Start SQL Browser as admin.' 'startbrowser'
        New-WinDotfilesCommandInfo 'SQL' 'stopbrowser' 'Stop SQL Browser as admin.' 'stopbrowser'
        New-WinDotfilesCommandInfo 'SQL' 'getSQL' 'List local SQL services.' 'getSQL'

        New-WinDotfilesCommandInfo 'Shell Aliases' 'ls' 'List directory contents with eza fallback.' 'ls'
        New-WinDotfilesCommandInfo 'Shell Aliases' 'll' 'Detailed directory listing with git info when eza exists.' 'll'
        New-WinDotfilesCommandInfo 'Shell Aliases' 'grep' 'Search with rg fallback to Select-String.' 'grep TODO'
        New-WinDotfilesCommandInfo 'Shell Aliases' 'cat' 'Read files with bat fallback to Get-Content.' 'cat README.md'
        New-WinDotfilesCommandInfo 'Shell Aliases' 'rm' 'Remove item with confirmation.' 'rm file.txt'
        New-WinDotfilesCommandInfo 'Shell Aliases' 'cp' 'Copy item with confirmation.' 'cp a b'
        New-WinDotfilesCommandInfo 'Shell Aliases' 'mv' 'Move item with confirmation.' 'mv a b'

        New-WinDotfilesCommandInfo 'Bootstrap' 'init-win-dotfiles' 'Initialize/link this Windows dotfiles setup.' 'init-win-dotfiles -WhatIf'
    )

    foreach ($group in Get-ProjectGroups) {
        if ($group.Command) {
            $commands += New-WinDotfilesCommandInfo 'Project Shortcuts' $group.Command "Open the $($group.Name) project group picker." $group.Command
        }
    }

    $commands | Sort-Object Category, Command
}

function Show-WinDotfilesCommands {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Category,

        [string]$Search,
        [switch]$Markdown,
        [switch]$NamesOnly
    )

    $commands = @(Get-WinDotfilesCommandCatalog)

    if ($Category) {
        $commands = @($commands | Where-Object {
                $_.Category -like "*$Category*" -or
                $_.Command -like "*$Category*" -or
                $_.Description -like "*$Category*"
            })
    }

    if ($Search) {
        $commands = @($commands | Where-Object {
                $_.Category -like "*$Search*" -or
                $_.Command -like "*$Search*" -or
                $_.Description -like "*$Search*" -or
                $_.Example -like "*$Search*"
            })
    }

    if (-not $commands) {
        Write-Warning 'No custom commands matched.'
        return
    }

    if ($NamesOnly) {
        $commands | ForEach-Object Command | Sort-Object -Unique
        return
    }

    if ($Markdown) {
        foreach ($group in ($commands | Group-Object Category | Sort-Object Name)) {
            "# $($group.Name)"
            ''
            $group.Group | Sort-Object Command | ForEach-Object {
                '- `{0}`: {1} Example: `{2}`' -f $_.Command, $_.Description, $_.Example
            }
            ''
        }
        return
    }

    foreach ($group in ($commands | Group-Object Category | Sort-Object Name)) {
        Write-Host "`n$($group.Name)" -ForegroundColor Cyan
        $group.Group |
        Sort-Object Command |
        Select-Object Command, Description, Example |
        Format-Table -AutoSize |
        Out-Host
    }
}

Set-Alias -Name cmds -Value Show-WinDotfilesCommands
Set-Alias -Name mycmds -Value Show-WinDotfilesCommands

function Get-WorkonStatePath {
    $stateRoot = Join-Path $CacheRoot 'win-dotfiles'
    New-Item -ItemType Directory -Path $stateRoot -Force -ErrorAction SilentlyContinue | Out-Null
    Join-Path $stateRoot 'workon-last.txt'
}

function Select-ProjectPathFromDirectories {
    param([Parameter(Mandatory)][object[]]$Directories)

    if (-not $Directories) {
        return $null
    }

    $orderedDirectories = @($Directories | Sort-Object FullName)

    if ($orderedDirectories.Count -eq 1) {
        return $orderedDirectories[0].FullName
    }

    if (Test-Command fzf -Application) {
        $fzfArgs = New-FzfArgs -Prompt 'workon> ' -Label 'workon' -Preview (Get-FzfDirectoryPreviewCommand)
        $selected = $orderedDirectories |
        ForEach-Object FullName |
        fzf @fzfArgs

        return $selected
    }

    Select-FromNumberedMenu -Items $orderedDirectories -Prompt 'Project' `
        -DisplayScript { param($directory) $directory.FullName } `
        -ValueScript { param($directory) $directory.FullName }
}

function Resolve-WorkonProjectPath {
    param(
        [string]$Name,
        [switch]$Last
    )

    if ($Last) {
        $statePath = Get-WorkonStatePath
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $lastPath = Get-Content -LiteralPath $statePath -TotalCount 1
            if ($lastPath -and (Test-Path -LiteralPath $lastPath -PathType Container)) {
                return $lastPath
            }
        }

        Write-Warning 'No previous workon project was found.'
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Select-ProjectPathFromDirectories -Directories @(Get-KnownProjectDirectories)
    }

    $group = Get-ProjectGroup $Name
    if ($group -and (Test-Path -LiteralPath $group.Path -PathType Container)) {
        $groupProjects = @(Get-ChildItem -LiteralPath $group.Path -Directory -ErrorAction SilentlyContinue)
        return Select-ProjectPathFromDirectories -Directories $groupProjects
    }

    $matches = @(Get-KnownProjectDirectories | Where-Object {
            $_.Name -ieq $Name -or $_.FullName -like "*$Name*"
        })

    Select-ProjectPathFromDirectories -Directories $matches
}

function workon {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [switch]$Code,
        [switch]$NoStatus,
        [switch]$Last
    )

    $projectPath = Resolve-WorkonProjectPath -Name $Name -Last:$Last
    if (-not $projectPath) {
        Write-Warning 'Project was not selected.'
        return
    }

    Set-Location -LiteralPath $projectPath
    Set-Content -LiteralPath (Get-WorkonStatePath) -Value $projectPath -Encoding utf8

    if (-not $NoStatus -and (Test-Path -LiteralPath (Join-Path $projectPath '.git') -PathType Container)) {
        git status --short --branch
    }

    if ($Code) {
        if (Test-Command code -Application) {
            code .
        }
        else {
            Write-Warning 'VS Code command `code` is not installed or not on PATH.'
        }
    }
}
