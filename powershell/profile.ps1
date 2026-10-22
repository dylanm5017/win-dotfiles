$ProfileScripts = @(
    '00-env.ps1'
    '10-path.ps1'
    '20-modules.ps1'
    '30-history.ps1'
    '40-prompt.ps1'
    '45-theme.ps1'
    '47-wezterm.ps1'
    '48-fzf.ps1'
    '50-navigation.ps1'
    '60-aliases.ps1'
    '65-alias-tips.ps1'
    '70-keybindings.ps1'
    '80-bootstrap.ps1'
    '90-sql.ps1'
    '100-project-marks.ps1'
    '110-dev.ps1'
    '115-workflow-tools.ps1'
    '130-completions.ps1'
    '140-reliability.ps1'
    '150-workstation.ps1'
    '155-raise.ps1'
    '160-projects.ps1'
    '170-greeting.ps1'
)

$ProfileScriptRoot = Join-Path $PSScriptRoot 'profile.d'
$ProfileDebugEnabled = $env:WINDOTFILES_PROFILE_DEBUG -in @('1', 'true', 'yes', 'on')

if (-not (Test-Path -LiteralPath $ProfileScriptRoot -PathType Container)) {
    $RepoProfileScriptRoot = 'C:\Workspace\Projects\win-dotfiles\powershell\profile.d'

    if (Test-Path -LiteralPath $RepoProfileScriptRoot -PathType Container) {
        $ProfileScriptRoot = $RepoProfileScriptRoot
    }
}

function Get-WinDotfilesProfileBundle {
    # Each dot-sourced file carries ~6 ms of fixed overhead, so loading profile.d as one
    # concatenated file saves ~125 ms per shell. The first line of the bundle records the name,
    # mtime and size of every source; any difference triggers a rebuild. Returns $null to fall back
    # to per-file loading when a script is missing or cannot be bundled safely.
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][string[]]$Scripts
    )

    try {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $ScriptRoot)
        $bundlePath = Join-Path $repoRoot '.cache\profile.bundle.ps1'
        $sources = @(Join-Path (Split-Path -Parent $ScriptRoot) 'profile.ps1') + @($Scripts | ForEach-Object { Join-Path $ScriptRoot $_ })

        $infos = @($sources | ForEach-Object { [IO.FileInfo]::new($_) })
        if ($infos | Where-Object { -not $_.Exists }) { return $null }
        $signature = '# win-dotfiles profile bundle ' + (($infos | ForEach-Object { '{0}:{1}:{2}' -f $_.Name, $_.LastWriteTimeUtc.Ticks, $_.Length }) -join '|')

        if ([IO.File]::Exists($bundlePath)) {
            $reader = [IO.StreamReader]::new($bundlePath)
            try { $currentSignature = $reader.ReadLine() } finally { $reader.Dispose() }
            if ($currentSignature -ceq $signature) { return $bundlePath }
        }

        $builder = [Text.StringBuilder]::new()
        [void]$builder.AppendLine($signature)
        foreach ($source in $sources | Select-Object -Skip 1) {
            $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$null, [ref]$errors)
            if ($errors) { return $null }

            # Top-level return/exit, param blocks and using statements change meaning once the
            # file is no longer its own script.
            $topLevelFlow = $ast.FindAll({
                    param($node)
                    if ($node -isnot [Management.Automation.Language.ReturnStatementAst] -and $node -isnot [Management.Automation.Language.ExitStatementAst]) { return $false }
                    for ($parent = $node.Parent; $parent; $parent = $parent.Parent) {
                        if ($parent -is [Management.Automation.Language.FunctionDefinitionAst] -or $parent -is [Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
                    }
                    $true
                }, $true)
            if ($topLevelFlow -or $ast.ParamBlock -or $ast.UsingStatements) {
                Write-Warning "Profile bundle skipped: $(Split-Path -Leaf $source) has a top-level return/exit, param block or using statement."
                return $null
            }

            [void]$builder.AppendLine("# source: $(Split-Path -Leaf $source)")
            [void]$builder.AppendLine($ast.Extent.Text)
        }

        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $bundlePath))
        $tempPath = "$bundlePath.$PID.tmp"
        [IO.File]::WriteAllText($tempPath, $builder.ToString(), [Text.UTF8Encoding]::new($true))
        [IO.File]::Move($tempPath, $bundlePath, $true)
        $bundlePath
    }
    catch {
        Write-Verbose "Profile bundle unavailable: $($_.Exception.Message)"
        $null
    }
}

# Debug mode keeps per-file loading so profileperf/wincheck can time each script.
# WINDOTFILES_PROFILE_BUNDLE=0 forces per-file loading (e.g. for accurate error line numbers).
$ProfileBundlePath = if (-not $ProfileDebugEnabled -and $env:WINDOTFILES_PROFILE_BUNDLE -notin @('0', 'false', 'no', 'off')) {
    Get-WinDotfilesProfileBundle -ScriptRoot $ProfileScriptRoot -Scripts $ProfileScripts
}

if ($ProfileBundlePath) {
    . $ProfileBundlePath
}
else {
    foreach ($script in $ProfileScripts) {
        $scriptPath = Join-Path $ProfileScriptRoot $script

        if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
            if ($ProfileDebugEnabled) {
                $loadTime = Measure-Command { . $scriptPath }
                Write-Host ("Loaded {0} in {1:n0} ms" -f $script, $loadTime.TotalMilliseconds) -ForegroundColor DarkGray
            }
            else {
                . $scriptPath
            }
        }
        else {
            Write-Warning "Profile script not found: $scriptPath"
        }
    }
}

$ProfileLocalPath = Join-Path (Split-Path -Parent $ProfileScriptRoot) 'profile.local.ps1'
if (Test-Path -LiteralPath $ProfileLocalPath -PathType Leaf) {
    if ($ProfileDebugEnabled) {
        $loadTime = Measure-Command { . $ProfileLocalPath }
        Write-Host ("Loaded profile.local.ps1 in {0:n0} ms" -f $loadTime.TotalMilliseconds) -ForegroundColor DarkGray
    }
    else {
        . $ProfileLocalPath
    }
}
