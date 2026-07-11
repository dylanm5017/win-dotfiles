function Get-WinDotfilesTemplateRoot {
    Join-Path $WinDotfilesRoot 'templates'
}

function Test-ProjectHasFile {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$Filter
    )

    [bool](Get-ChildItem -LiteralPath $ProjectPath -Filter $Filter -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-ProjectNpmScriptNames {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $packageJsonPath = Join-Path $ProjectPath 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        return @()
    }

    try {
        $package = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
        if ($package.PSObject.Properties['scripts']) {
            return @($package.scripts.PSObject.Properties.Name)
        }
    }
    catch {
        Write-Verbose "Could not parse $packageJsonPath : $($_.Exception.Message)"
    }

    @()
}

function Invoke-ProjectAudit {
    [CmdletBinding()]
    param([switch]$Refresh)

    $directories = @(Get-KnownProjectDirectories -Refresh:$Refresh)
    if (-not $directories) {
        Write-Warning 'No known project directories were found. Check projects.json and projcache -Refresh.'
        return
    }

    $mark = { param($ok) if ($ok) { 'OK' } else { '--' } }
    $results = foreach ($directory in $directories) {
        $path = $directory.FullName
        $isNode = Test-Path -LiteralPath (Join-Path $path 'package.json') -PathType Leaf
        $scriptNames = if ($isNode) { Get-ProjectNpmScriptNames -ProjectPath $path } else { @() }
        $hasVerify = $isNode -and (@('verify', 'test', 'build') | Where-Object { $scriptNames -contains $_ })

        [PSCustomObject]@{
            Project      = Split-Path -Leaf $path
            Type         = if ($isNode) { 'node' } else { 'other' }
            README       = & $mark (Test-ProjectHasFile -ProjectPath $path -Filter 'README*')
            gitignore    = & $mark (Test-Path -LiteralPath (Join-Path $path '.gitignore'))
            editorconfig = & $mark (Test-Path -LiteralPath (Join-Path $path '.editorconfig'))
            nvmrc        = if ($isNode) { & $mark ((Test-Path -LiteralPath (Join-Path $path '.nvmrc')) -or (Test-Path -LiteralPath (Join-Path $path '.node-version'))) } else { 'n/a' }
            verifyScript = if ($isNode) { & $mark $hasVerify } else { 'n/a' }
        }
    }

    $results | Sort-Object Project | Format-Table -AutoSize
    Write-Host 'Use scaffold <template> to drop a template into a project (templates: editorconfig, gitignore, readme).' -ForegroundColor DarkGray
}

Set-Alias -Name proj-audit -Value Invoke-ProjectAudit

function Copy-ProjectTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('editorconfig', 'gitignore', 'readme')][string]$Template,
        [string]$Path = (Get-Location).Path,
        [switch]$Force
    )

    $templateRoot = Get-WinDotfilesTemplateRoot
    $map = @{
        editorconfig = @{ Source = '.editorconfig';   Destination = '.editorconfig' }
        gitignore    = @{ Source = 'gitignore-node';  Destination = '.gitignore' }
        readme       = @{ Source = 'README.md';       Destination = 'README.md' }
    }

    $entry = $map[$Template]
    $sourcePath = Join-Path $templateRoot $entry.Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Write-Warning "Template not found: $sourcePath"
        return
    }

    $destinationPath = Join-Path $Path $entry.Destination
    if ((Test-Path -LiteralPath $destinationPath) -and -not $Force) {
        Write-Warning "$destinationPath already exists. Re-run with -Force to overwrite."
        return
    }

    if ($PSCmdlet.ShouldProcess($destinationPath, "Copy $Template template")) {
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        if ($Template -eq 'readme') {
            $projectName = Split-Path -Leaf ([IO.Path]::GetFullPath($Path))
            (Get-Content -LiteralPath $destinationPath -Raw).Replace('{{PROJECT_NAME}}', $projectName) |
                Set-Content -LiteralPath $destinationPath -Encoding utf8
        }
        Write-Host "Wrote $destinationPath" -ForegroundColor Green
    }
}

Set-Alias -Name scaffold -Value Copy-ProjectTemplate
