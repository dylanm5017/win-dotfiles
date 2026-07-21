if ($IsInteractiveShell -and (Get-Module PSReadLine)) {
    # fish/zsh-like completion menu on Tab.
    Set-PSReadLineKeyHandler -Chord Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord Shift+Tab -Function MenuComplete

    # Arrows filter history by what has already been typed ("git" + Up walks only git commands)
    # instead of walking every command blindly. PSReadLine routes these through the prediction
    # ListView first, so the inline/list suggestions from 30-history keep working.
    Set-PSReadLineKeyHandler -Chord UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Chord DownArrow -Function HistorySearchForward
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # bash/zsh line editing that Windows EditMode leaves unbound.
    Set-PSReadLineKeyHandler -Chord Alt+. -Function YankLastArg
    Set-PSReadLineKeyHandler -Chord Alt+d -Function KillWord
    Set-PSReadLineKeyHandler -Chord Ctrl+w -Function BackwardKillWord
    Set-PSReadLineKeyHandler -Chord Ctrl+Backspace -Function BackwardKillWord
    Set-PSReadLineKeyHandler -Chord Ctrl+u -Function BackwardDeleteLine
    Set-PSReadLineKeyHandler -Chord Ctrl+k -Function ForwardDeleteLine

    # Compose a multi-line command without submitting it.
    Set-PSReadLineKeyHandler -Chord Shift+Enter -Function AddLine
}

if ($IsInteractiveShell -and (Get-Module PSReadLine) -and $env:WINDOTFILES_AUTOPAIR -notin @('0', 'off', 'false', 'no')) {
    # Auto-pairing, editor style: an opening delimiter brings its partner, typing the closing one
    # steps over an auto-inserted partner instead of doubling it, and Backspace between an empty
    # pair removes both. Disable with WINDOTFILES_AUTOPAIR=off.
    $WinDotfilesPairs = [ordered]@{ '(' = ')'; '[' = ']'; '{' = '}' }

    foreach ($opening in $WinDotfilesPairs.Keys) {
        $closing = $WinDotfilesPairs[$opening]

        Set-PSReadLineKeyHandler -Chord $opening -BriefDescription "Insert $opening$closing" -LongDescription "Insert the $opening$closing pair, or wrap the selection in it" -ScriptBlock {
            param($key)

            $pairs = [ordered]@{ '(' = ')'; '[' = ']'; '{' = '}' }
            $open = [string]$key.KeyChar
            $close = $pairs[$open]

            $selectionStart = $null
            $selectionLength = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            if ($selectionStart -ne -1) {
                $selected = $line.Substring($selectionStart, $selectionLength)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "$open$selected$close")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
                return
            }

            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$open$close")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }

        Set-PSReadLineKeyHandler -Chord $closing -BriefDescription "Insert or skip $closing" -LongDescription "Step over an auto-inserted $closing rather than doubling it" -ScriptBlock {
            param($key)

            $close = [string]$key.KeyChar
            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            if ($cursor -lt $line.Length -and $line[$cursor] -eq $close) {
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            }
            else {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($close)
            }
        }
    }

    foreach ($quoteChar in '"', "'") {
        Set-PSReadLineKeyHandler -Chord $quoteChar -BriefDescription 'Smart quote' -LongDescription 'Insert a matching quote pair, wrap the selection, or step over the closing quote' -ScriptBlock {
            param($key)

            $quote = [string]$key.KeyChar

            $selectionStart = $null
            $selectionLength = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            if ($selectionStart -ne -1) {
                $selected = $line.Substring($selectionStart, $selectionLength)
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "$quote$selected$quote")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
                return
            }

            if ($cursor -lt $line.Length -and $line[$cursor] -eq $quote) {
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                return
            }

            # Mid-word (my'file, don't) a lone quote is what was meant, not a pair.
            if ($cursor -gt 0 -and $line[$cursor - 1] -match '\w') {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
                return
            }

            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
    }

    Set-PSReadLineKeyHandler -Chord Backspace -BriefDescription 'Backspace through pairs' -LongDescription 'Delete both halves of an empty delimiter pair' -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -gt 0 -and $cursor -lt $line.Length) {
            $pair = $line.Substring($cursor - 1, 2)
            if ($pair -in '()', '[]', '{}', '""', "''") {
                [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
                return
            }
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
    }
}

function Show-WinDotfilesKeyBindings {
    # Companion to `cmds` and `aliastips`: what this profile has actually bound, minus the
    # hundred-odd PSReadLine defaults you never think about.
    [CmdletBinding()]
    param(
        [string]$Filter,
        [switch]$All
    )

    $bound = Get-PSReadLineKeyHandler -Bound |
    Where-Object { $All -or $_.Function -notin @('SelfInsert', 'Ignore') }

    if ($Filter) {
        $bound = $bound | Where-Object { $_.Key -like "*$Filter*" -or $_.Function -like "*$Filter*" -or $_.Description -like "*$Filter*" }
    }

    $bound | Sort-Object Key | Select-Object Key, Function, Description
}

Set-Alias -Name keys -Value Show-WinDotfilesKeyBindings -Force

if ($IsInteractiveShell -and (Get-Module PSReadLine) -and (Test-Command fzf -Application)) {
    Set-PSReadLineKeyHandler -Chord Ctrl+r -BriefDescription FzfHistory -LongDescription 'Search command history with fzf' -ScriptBlock {
        $selected = Invoke-FzfHistory
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }

    Set-PSReadLineKeyHandler -Chord Ctrl+t -BriefDescription FzfFiles -LongDescription 'Insert a file selected with fzf' -ScriptBlock {
        $selected = Invoke-FzfFile
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
}
