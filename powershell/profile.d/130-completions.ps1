function Get-ProjectCompletionNames {
    $groupNames = Get-ProjectGroups | ForEach-Object { $_.Name; $_.Command }
    $repoNames = Get-KnownProjectDirectories | ForEach-Object Name
    $seen = @{}

    foreach ($name in @($groupNames + $repoNames)) {
        if (-not $name) {
            continue
        }

        $key = $name.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $name
        }
    }

    $seen.Values | Sort-Object
}

function Get-ProjectDirectoryCompletionNames {
    $configuredPaths = Get-ProjectGroups | ForEach-Object Path
    $configuredKeys = @{}
    foreach ($path in $configuredPaths) {
        if ($path) {
            $configuredKeys[[IO.Path]::GetFullPath($path).ToLowerInvariant()] = $true
        }
    }

    Get-ChildItem -LiteralPath $ProjectsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { -not $configuredKeys.ContainsKey([IO.Path]::GetFullPath($_.FullName).ToLowerInvariant()) } |
    ForEach-Object Name |
    Sort-Object -Unique
}

function Get-ProjectGroupDirectoryNames {
    Get-ProjectGroupDirectories |
    ForEach-Object Name |
    Sort-Object -Unique
}

function Get-NpmScriptCompletionNames {
    Get-PackageScripts |
    ForEach-Object Name |
    Sort-Object -Unique
}

Register-ArgumentCompleter -CommandName dev -ParameterName cmd -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @('status', 'sync', 'outdated', 'clean', 'doctor') |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Add-ProjectGroup, addproj, apg -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-ProjectGroupDirectoryNames |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Add-ProjectGroup, addproj, apg -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-ProjectGroupDirectoryNames |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Add-Project, ap -ParameterName Group -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-ProjectGroupDirectoryNames |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Add-Project, ap -ParameterName Mode -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @('clone', 'empty') |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Invoke-NpmScript, nr -ParameterName Script -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-NpmScriptCompletionNames |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName workon -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-ProjectCompletionNames |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName gnew -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @('codex/', 'feature/', 'fix/', 'chore/') |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName awslambda -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @('list-functions', 'get-function', 'invoke', 'update-function-code', 'get-function-configuration') |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName awslogs -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @('describe-log-groups', 'describe-log-streams', 'filter-log-events', 'tail', 'get-log-events') |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName fbdeploy -ParameterName Only -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @('functions', 'hosting', 'firestore', 'storage', 'remoteconfig') |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName stripetrigger -ParameterName Event -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    @(
        'checkout.session.completed',
        'customer.created',
        'customer.subscription.created',
        'customer.subscription.updated',
        'invoice.payment_succeeded',
        'payment_intent.succeeded'
    ) |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName Show-WinDotfilesCommands, cmds, mycmds -ParameterName Category -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-WinDotfilesCommandCatalog |
    ForEach-Object { $_.Category; $_.Command } |
    Sort-Object -Unique |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName project, proj -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)

    Get-ProjectCompletionNames |
    Where-Object { $_ -like "$wordToComplete*" } |
    ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# --- Native CLI tab completers ---------------------------------------------------------------
# Generators that spawn a subprocess (gh, rustup) are cached to disk so they cost nothing on
# subsequent shell starts; cheap Register-ArgumentCompleter snippets (winget, dotnet) run inline.

function Get-WinDotfilesCompletionCacheDir {
    $dir = Join-Path $CacheRoot 'completions'
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    $dir
}

function Import-WinDotfilesCachedCompletion {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string[]]$GeneratorArgs,
        [switch]$Refresh
    )

    if (-not (Get-Command $Tool -CommandType Application -ErrorAction SilentlyContinue)) {
        return
    }

    $cacheFile = Join-Path (Get-WinDotfilesCompletionCacheDir) "$Tool.ps1"
    if ($Refresh -or -not (Test-Path -LiteralPath $cacheFile)) {
        try {
            & $Tool @GeneratorArgs | Out-File -LiteralPath $cacheFile -Encoding utf8 -ErrorAction Stop
        }
        catch {
            Write-Verbose "$Tool completion generation failed: $($_.Exception.Message)"
            return
        }
    }

    if (Test-Path -LiteralPath $cacheFile) {
        try { . $cacheFile }
        catch { Write-Verbose "$Tool completion load failed: $($_.Exception.Message)" }
    }
}

function Update-WinDotfilesCompletions {
    Import-WinDotfilesCachedCompletion -Tool 'gh' -GeneratorArgs @('completion', '-s', 'powershell') -Refresh
    Import-WinDotfilesCachedCompletion -Tool 'rustup' -GeneratorArgs @('completions', 'powershell') -Refresh
    Write-Host 'Refreshed cached completions (gh, rustup).' -ForegroundColor Green
}

if ($IsInteractiveShell) {
    Import-WinDotfilesCachedCompletion -Tool 'gh' -GeneratorArgs @('completion', '-s', 'powershell')
    Import-WinDotfilesCachedCompletion -Tool 'rustup' -GeneratorArgs @('completions', 'powershell')

    if (Get-Command winget -CommandType Application -ErrorAction SilentlyContinue) {
        Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
            $word = $wordToComplete.Replace('"', '""')
            $ast = $commandAst.ToString().Replace('"', '""')
            winget complete --word="$word" --commandline "$ast" --position $cursorPosition | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }

    if (Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue) {
        Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }

    # scoop completion ships as an optional module; git completion needs posh-git. Wire each only when present.
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Import-WinDotfilesOptionalModule -Name 'scoop-completion' | Out-Null
    }
    if ((Get-Command git -CommandType Application -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable posh-git)) {
        Import-WinDotfilesOptionalModule -Name 'posh-git' | Out-Null
    }
}
