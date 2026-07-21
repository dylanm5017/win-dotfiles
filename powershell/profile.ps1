$ProfileScripts = @(
    '00-env.ps1'
    '10-path.ps1'
    '20-modules.ps1'
    '30-history.ps1'
    '40-prompt.ps1'
    '45-theme.ps1'
    '48-fzf.ps1'
    '50-navigation.ps1'
    '60-aliases.ps1'
    '70-keybindings.ps1'
    '80-bootstrap.ps1'
    '90-sql.ps1'
    '100-project-marks.ps1'
    '110-dev.ps1'
    '115-workflow-tools.ps1'
    '130-completions.ps1'
    '140-reliability.ps1'
    '150-workstation.ps1'
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
