# Default to starship when it is installed (richer, language-aware prompt); fall back to the
# fast native prompt otherwise. Force either with WINDOTFILES_PROMPT=starship|native.
$global:WinDotfilesPromptMode = if ($env:WINDOTFILES_PROMPT) {
    $env:WINDOTFILES_PROMPT.ToLowerInvariant()
}
elseif (Get-Command starship -ErrorAction SilentlyContinue) {
    'starship'
}
else {
    'native'
}
$script:WinDotfilesPromptGitCache = @{}

function ConvertTo-WinDotfilesPromptPath {
    param([Parameter(Mandatory)][string]$Path)

    $displayPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $homePath = [IO.Path]::GetFullPath($HOME).TrimEnd('\')
    $workspacePath = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')

    if ($displayPath.Equals($homePath, [StringComparison]::OrdinalIgnoreCase)) {
        return '~'
    }

    if ($displayPath.StartsWith("$homePath\", [StringComparison]::OrdinalIgnoreCase)) {
        $displayPath = "~\$($displayPath.Substring($homePath.Length + 1))"
    }
    elseif ($displayPath.Equals($workspacePath, [StringComparison]::OrdinalIgnoreCase)) {
        $displayPath = 'Workspace'
    }
    elseif ($displayPath.StartsWith("$workspacePath\", [StringComparison]::OrdinalIgnoreCase)) {
        $displayPath = "Workspace\$($displayPath.Substring($workspacePath.Length + 1))"
    }

    $segments = @($displayPath -split '[\\/]')
    if ($segments.Count -gt 5) {
        $displayPath = @('...', $segments[-4], $segments[-3], $segments[-2], $segments[-1]) -join '\'
    }

    $displayPath
}

function Get-WinDotfilesPromptDirectory {
    $location = Get-Location
    if ($location.Provider.Name -ne 'FileSystem') {
        return $location.ToString()
    }

    ConvertTo-WinDotfilesPromptPath -Path $location.ProviderPath
}

function Resolve-WinDotfilesGitMetadata {
    param([string]$Path = (Get-Location).Path)

    $current = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $current) {
        return $null
    }

    if (-not $current.PSIsContainer) {
        $current = $current.Directory
    }

    while ($current) {
        $gitPath = Join-Path $current.FullName '.git'
        $gitItem = Get-Item -LiteralPath $gitPath -Force -ErrorAction SilentlyContinue

        if ($gitItem -and $gitItem.PSIsContainer) {
            return [PSCustomObject]@{
                RepositoryRoot = $current.FullName
                GitDirectory   = $gitItem.FullName
                HeadPath       = Join-Path $gitItem.FullName 'HEAD'
            }
        }

        if ($gitItem -and -not $gitItem.PSIsContainer) {
            $gitFileLine = Get-Content -LiteralPath $gitItem.FullName -TotalCount 1 -ErrorAction SilentlyContinue
            if ($gitFileLine -match '^gitdir:\s*(.+)$') {
                $gitDirectory = $Matches[1].Trim()
                if (-not [IO.Path]::IsPathRooted($gitDirectory)) {
                    $gitDirectory = [IO.Path]::GetFullPath((Join-Path $current.FullName $gitDirectory))
                }

                return [PSCustomObject]@{
                    RepositoryRoot = $current.FullName
                    GitDirectory   = $gitDirectory
                    HeadPath       = Join-Path $gitDirectory 'HEAD'
                }
            }
        }

        $current = $current.Parent
    }

    $null
}

function Get-WinDotfilesPromptGitBranch {
    $metadata = Resolve-WinDotfilesGitMetadata
    if (-not $metadata -or -not (Test-Path -LiteralPath $metadata.HeadPath -PathType Leaf)) {
        return $null
    }

    $headItem = Get-Item -LiteralPath $metadata.HeadPath -Force -ErrorAction SilentlyContinue
    if (-not $headItem) {
        return $null
    }

    $cacheKey = $headItem.FullName
    $cached = $script:WinDotfilesPromptGitCache[$cacheKey]
    if ($cached -and $cached.LastWriteTimeUtc -eq $headItem.LastWriteTimeUtc) {
        return $cached.Branch
    }

    $head = Get-Content -LiteralPath $headItem.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    $branch = $null

    if ($head -match '^ref:\s+refs/heads/(.+)$') {
        $branch = $Matches[1]
    }
    elseif ($head -match '^[a-f0-9]{7,40}$') {
        $branch = $head.Substring(0, 7)
    }

    $script:WinDotfilesPromptGitCache[$cacheKey] = [PSCustomObject]@{
        LastWriteTimeUtc = $headItem.LastWriteTimeUtc
        Branch           = $branch
    }

    $branch
}

function Invoke-WinDotfilesNativePrompt {
    [CmdletBinding()]
    param([switch]$MeasureOnly)

    $lastCommandSucceeded = $?
    $directory = Get-WinDotfilesPromptDirectory
    $branch = Get-WinDotfilesPromptGitBranch

    if ($MeasureOnly) {
        return [PSCustomObject]@{
            Directory = $directory
            Branch    = $branch
        }
    }

    Write-Host $directory -NoNewline -ForegroundColor Cyan
    if ($branch) {
        Write-Host " git:$branch" -NoNewline -ForegroundColor Magenta
    }

    $symbolColor = if ($lastCommandSucceeded) { "`e[32m" } else { "`e[31m" }
    "`n${symbolColor}❯`e[0m "
}

if ($IsInteractiveShell -and $global:WinDotfilesPromptMode -eq 'starship' -and ($script:starshipCommand = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    # `starship init powershell` emits a one-line bootstrap that *re-invokes* starship with
    # --print-full-init, so the naive `Invoke-Expression (&starship init powershell)` spawns the
    # binary twice on every shell (~140 ms through scoop's shim). Cache the full init script and
    # dot-source it instead (~50 ms); regenerate only when starship.exe is newer than the cache.
    $starshipInitCache = Join-Path $env:STARSHIP_CACHE 'init.ps1'
    $starshipInitFresh = $false
    if (Test-Path -LiteralPath $starshipInitCache -PathType Leaf) {
        $starshipInitFresh = (Get-Item -LiteralPath $starshipInitCache).LastWriteTimeUtc -ge (Get-Item -LiteralPath $script:starshipCommand.Source).LastWriteTimeUtc
    }

    if (-not $starshipInitFresh) {
        try {
            New-Item -ItemType Directory -Path $env:STARSHIP_CACHE -Force -ErrorAction SilentlyContinue | Out-Null
            & $script:starshipCommand.Source init powershell --print-full-init | Out-File -LiteralPath $starshipInitCache -Encoding utf8 -ErrorAction Stop
            $starshipInitFresh = $true
        }
        catch {
            Write-Verbose "starship init cache write failed: $($_.Exception.Message)"
        }
    }

    if ($starshipInitFresh) {
        . $starshipInitCache
    }
    else {
        Invoke-Expression (&starship init powershell)
    }

    # Transient prompt: once a command runs, collapse its (multi-line) prompt back to just the
    # ❯ character so scrollback stays clean and focused on output. starship's PowerShell init
    # defines Enable-TransientPrompt (needs PSReadLine); guard so a stripped env is a no-op.
    if (Get-Command Enable-TransientPrompt -ErrorAction SilentlyContinue) {
        Enable-TransientPrompt
    }
}
elseif ($IsInteractiveShell) {
    function global:prompt {
        Invoke-WinDotfilesNativePrompt
    }
}
