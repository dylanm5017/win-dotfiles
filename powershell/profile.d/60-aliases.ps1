foreach ($aliasName in 'ls', 'll', 'gs', 'gc', 'gp', 'grep', 'cat', 'ni', 'nv', 'nd', 'rm', 'cp', 'mv') {
    if (Test-Path "Alias:$aliasName") {
        Remove-Item "Alias:$aliasName" -Force
    }
}

function ls {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --icons @args
        return
    }

    Get-ChildItem @args
}

function ll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza -lah --icons --git @args
        return
    }

    Get-ChildItem -Force @args
}

function lt {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --tree --level=2 --icons --git-ignore @args
        return
    }

    Get-ChildItem -Recurse @args
}

function gs {
    git status @args
}

function gc {
    git commit @args
}

function gp {
    git pull @args
}

function gpl {
    git pull @args
}

function gpull {
    git pull @args
}

function gpsh {
    git push @args
}

function gpush {
    git push @args
}

function grep {
    if (Get-Command rg -ErrorAction SilentlyContinue) {
        rg @args
        return
    }

    Select-String @args
}

function cat {
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        bat @args
        return
    }

    Get-Content @args
}

function Resolve-NodeVersion {
    param([string]$Version)

    if ($Version) {
        return $Version
    }

    foreach ($versionFile in '.node-version', '.nvmrc') {
        $path = Join-Path (Get-Location) $versionFile
        if (Test-Path $path) {
            return (Get-Content -LiteralPath $path -TotalCount 1).Trim()
        }
    }

    throw 'No Node version was supplied and no .node-version or .nvmrc file was found.'
}

function ni {
    param([string]$Version)

    $resolvedVersion = Resolve-NodeVersion $Version
    nvm install $resolvedVersion
    if ($LASTEXITCODE -eq 0) {
        nvm use $resolvedVersion
    }
}

function nv {
    param([string]$Version)

    nvm use (Resolve-NodeVersion $Version)
}

function nd {
    param([string]$Version)

    nvm use (Resolve-NodeVersion $Version)
}

function nvmrc {
    param([string]$Version)

    $resolvedVersion = Resolve-NodeVersion $Version
    nvm use $resolvedVersion
    if ($LASTEXITCODE -ne 0) {
        nvm install $resolvedVersion
        if ($LASTEXITCODE -eq 0) {
            nvm use $resolvedVersion
        }
    }
}

function dot {
    git -C $DotfilesRoot @args
}

function dot-add {
    dot add -p @args
}

function Sync-WinDotfilesPackages {
    # Refresh the committed Scoop manifest from what is currently installed, keeping the clean
    # (name + source) shape used by packages/scoop.json so diffs stay meaningful. winget.json is
    # hand-curated (a full winget export is mostly machine-specific noise), so it is left alone.
    [CmdletBinding()]
    param()

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Warning 'scoop is not installed or not on PATH.'
        return
    }

    $packagesRoot = Join-Path $WinDotfilesRoot 'packages'
    New-Item -ItemType Directory -Path $packagesRoot -Force -ErrorAction SilentlyContinue | Out-Null
    $scoopManifestPath = Join-Path $packagesRoot 'scoop.json'

    $export = scoop export | ConvertFrom-Json
    $clean = [ordered]@{
        buckets = @($export.buckets | ForEach-Object { [ordered]@{ Name = $_.Name; Source = $_.Source } })
        apps    = @($export.apps | ForEach-Object { [ordered]@{ Name = $_.Name; Source = $_.Source } })
    }

    $clean | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $scoopManifestPath -Encoding utf8
    Write-Host "Wrote Scoop manifest to $scoopManifestPath" -ForegroundColor Green
    Write-Host 'packages/winget.json is hand-curated; run "winget export -o -" to review what is installed.' -ForegroundColor DarkGray
}

Set-Alias -Name pkgsync -Value Sync-WinDotfilesPackages
Set-Alias -Name pkglist -Value Sync-WinDotfilesPackages

function rm {
    Remove-Item -Confirm @args
}

function cp {
    Copy-Item -Confirm @args
}

function mv {
    Move-Item -Confirm @args
}

function mkcd {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location -LiteralPath $Path
}

function touch {
    param([Parameter(Mandatory)][string[]]$Path)

    foreach ($item in $Path) {
        if (Test-Path -LiteralPath $item) {
            (Get-Item -LiteralPath $item).LastWriteTime = Get-Date
        }
        else {
            New-Item -ItemType File -Path $item -Force | Out-Null
        }
    }
}
