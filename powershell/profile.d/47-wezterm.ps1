# WezTerm shell integration: OSC 7 (cwd), OSC 133 (semantic prompt/output zones) and OSC 1337
# user vars. No-ops outside WezTerm, so the same profile still behaves in Windows Terminal.
#
# WezTerm ships integration scripts for bash/zsh only; the PowerShell one (wezterm PR #7296) is
# still unmerged, and it hooks the Enter key -- which starship's transient prompt already owns,
# so the two silently cancel each other out. This is a compact equivalent that instead rides the
# seams this profile already has:
#   - prompt marks via starship's Invoke-Starship-PreCommand hook (or a wrapper on the native prompt)
#   - the command-start mark via the AddToHistoryHandler "preexec" seam in 30-history.ps1
#
# What it buys: Shift+Up/Down to jump between prompts in the scrollback, triple-click to select a
# whole command's output, exact cwd inheritance for new tabs/splits, and a WEZTERM_CMD user var so
# a busy tab is titled with the command it's running rather than 'pwsh'.
#
# Disable with WINDOTFILES_WEZTERM_INTEGRATION=off.

$global:WinDotfilesWezTerm = $IsInteractiveShell -and
    -not [string]::IsNullOrEmpty($env:WEZTERM_PANE) -and
    $env:WINDOTFILES_WEZTERM_INTEGRATION -notin @('0', 'off', 'false', 'no')

if ($global:WinDotfilesWezTerm) {
    function Write-WinDotfilesWezOsc {
        param([Parameter(Mandatory)][string]$Body)

        # Written straight to the console rather than through the output stream, so the escape
        # sequence can never end up captured in a pipeline or a transcript.
        [Console]::Out.Write("$([char]27)]$Body$([char]7)")
    }

    function Set-WinDotfilesWezUserVar {
        param([Parameter(Mandatory)][string]$Name, [string]$Value = '')

        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
        Write-WinDotfilesWezOsc "1337;SetUserVar=$Name=$encoded"
    }

    function Write-WinDotfilesWezPrompt {
        # Fires once per prompt. D closes the previous command's output zone (carrying its exit
        # status), A opens the new prompt zone.
        param([int]$ExitCode = 0)

        Write-WinDotfilesWezOsc "133;D;$ExitCode"
        Write-WinDotfilesWezOsc '133;A'

        # OSC 7 so a new tab/split inherits the exact cwd instead of WezTerm inferring it from the
        # process. Meaningless off the filesystem provider (inside a registry or cert: drive).
        $location = Get-Location
        if ($location.Provider.Name -eq 'FileSystem') {
            $posix = ($location.ProviderPath -replace '\\', '/').TrimStart('/')
            [Console]::Out.Write("$([char]27)]7;file://$env:COMPUTERNAME/$posix$([char]27)\")
        }

        # Cleared here and set again at Enter, so an idle tab falls back to its process name.
        Set-WinDotfilesWezUserVar 'WEZTERM_CMD'
        Set-WinDotfilesWezUserVar 'WEZTERM_PROG'
    }

    function Write-WinDotfilesWezExec {
        # Called from the AddToHistoryHandler in 30-history.ps1, which PSReadLine invokes for the
        # accepted line immediately before it runs -- after starship's transient-prompt redraw.
        param([string]$Line)

        if (-not $global:WinDotfilesWezTerm) { return }

        $command = ''
        if ($Line) {
            $command = ($Line.TrimStart() -split '\s+', 2)[0]

            # Resolve through aliases so `gs` titles the tab `git`, not `gs`.
            $resolved = Get-Command -Name $command -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolved) {
                $command = if ($resolved.CommandType -eq 'Alias') { $resolved.Definition } else { $resolved.Name }
            }
            $command = $command -replace '(?i)\.exe$', ''
        }

        Set-WinDotfilesWezUserVar 'WEZTERM_PROG' $Line
        Set-WinDotfilesWezUserVar 'WEZTERM_CMD' $command

        # C closes the input zone and opens the output zone.
        Write-WinDotfilesWezOsc '133;C'
    }

    if ($global:WinDotfilesPromptMode -eq 'starship' -and (Test-Path function:global:prompt)) {
        # starship calls this at the top of its prompt function, before it shells out. Nothing
        # else in this profile defines it, but compose rather than clobber in case that changes.
        $script:WinDotfilesWezPriorPreCommand = if (Test-Path function:global:Invoke-Starship-PreCommand) {
            ${function:global:Invoke-Starship-PreCommand}
        }

        function global:Invoke-Starship-PreCommand {
            $exitCode = if ($global:LASTEXITCODE) { [int]$global:LASTEXITCODE } elseif (-not $global:?) { 1 } else { 0 }
            Write-WinDotfilesWezPrompt -ExitCode $exitCode

            if ($script:WinDotfilesWezPriorPreCommand) { & $script:WinDotfilesWezPriorPreCommand }
        }
    }
    elseif (Test-Path function:global:prompt) {
        $script:WinDotfilesWezOriginalPrompt = $function:global:prompt

        function global:prompt {
            # The native prompt reads $? on its first line to colour the ❯, so both $? and
            # $LASTEXITCODE have to survive the escape sequences we emit in between.
            $origDollarQuestion = $global:?
            $origLastExitCode = $global:LASTEXITCODE

            $exitCode = if ($origLastExitCode) { [int]$origLastExitCode } elseif (-not $origDollarQuestion) { 1 } else { 0 }
            Write-WinDotfilesWezPrompt -ExitCode $exitCode

            $global:LASTEXITCODE = $origLastExitCode

            # $? is read-only, so it can only be restored by performing an action that produces
            # the value we want. This has to be the last thing before the inner prompt runs.
            if ($origDollarQuestion) { $null = 1 } else { Write-Error '' -ErrorAction Ignore }

            & $script:WinDotfilesWezOriginalPrompt
        }
    }
}
