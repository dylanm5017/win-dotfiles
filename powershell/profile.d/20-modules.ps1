function Import-WinDotfilesOptionalModule {
    param([Parameter(Mandatory)][string]$Name)

    try {
        Import-Module -Name $Name -ErrorAction Stop
        $true
    }
    catch {
        Write-Verbose "$Name skipped: $($_.Exception.Message)"
        $false
    }
}

try {
    Import-Module PSReadLine -ErrorAction Stop
}
catch {
    Write-Verbose "PSReadLine skipped: $($_.Exception.Message)"
}

# CompletionPredictor powers PSReadLine HistoryAndPlugin predictions; load it early when present so
# 30-history.ps1 can opt into plugin predictions. Install with: Install-Module CompletionPredictor
if ($IsInteractiveShell) {
    Import-WinDotfilesOptionalModule -Name CompletionPredictor | Out-Null
}

function Enable-TerminalIcons {
    Import-WinDotfilesOptionalModule -Name Terminal-Icons | Out-Null
}

function Enable-WinGetCommandNotFound {
    Import-WinDotfilesOptionalModule -Name Microsoft.WinGet.CommandNotFound | Out-Null
}

if ($IsInteractiveShell -and $env:WINDOTFILES_EAGER_OPTIONAL_MODULES -in @('1', 'true', 'yes', 'on')) {
    Enable-TerminalIcons
    Enable-WinGetCommandNotFound
}
