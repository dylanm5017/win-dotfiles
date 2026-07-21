# fzf helper library. Shared by 50-navigation (project group/dir pickers), 70-keybindings
# (Ctrl+R history / Ctrl+T files), and 115-workflow-tools (npm-script + workon pickers). Loads
# before all of them so the helpers are defined first. Mirrors the zsh setup's lib/fzf.zsh:
# one place for the fzf defaults, argument builder, preview commands, and the non-fzf fallback.

if (Test-Command rg -Application) {
    $env:FZF_DEFAULT_COMMAND = 'rg --files --hidden --glob "!{.git,node_modules,dist,build,.next,.cache}/**"'
}

$env:FZF_DEFAULT_OPTS = @(
    '--with-shell="pwsh -NoProfile -Command"'
    '--height=70%'
    '--min-height=18'
    '--layout=reverse'
    '--border=rounded'
    '--margin=1'
    '--padding=1,2'
    '--info=inline-right'
    '--highlight-line'
    '--cycle'
    '--scroll-off=4'
    '--pointer=>'
    '--marker=+'
    '--separator=-'
    '--scrollbar=|'
    '--bind=ctrl-/:toggle-preview,ctrl-u:clear-query'
    '--color=bg:-1,bg+:#303030,fg:#d0d0d0,fg+:#ffffff,hl:#5fd7ff,hl+:#5fd7ff,info:#af87ff,prompt:#87d7af,pointer:#ffaf5f,marker:#ffd75f,spinner:#ffaf5f,header:#87d7af,border:#5f5f87,label:#c0c0c0,query:#ffffff'
) -join ' '

function New-FzfArgs {
    param(
        [string]$Prompt = 'search> ',
        [string]$Label,
        [string]$Preview,
        [string]$PreviewWindow = 'right:60%,border-rounded,wrap',
        [string[]]$ExtraArgs
    )

    $fzfArgs = @('--prompt', $Prompt)
    if ($Label) {
        $fzfArgs += @('--border-label', " $Label ")
    }

    if ($Preview) {
        $fzfArgs += @('--preview', $Preview, '--preview-window', $PreviewWindow)
    }

    if ($ExtraArgs) {
        $fzfArgs += $ExtraArgs
    }

    $fzfArgs
}

function Get-FzfDirectoryPreviewCommand {
    "if (Test-Path -LiteralPath '{}') { Get-ChildItem -LiteralPath '{}' -Force | Sort-Object Name | Select-Object -First 40 Mode,Length,LastWriteTime,Name | Format-Table -AutoSize }"
}

function Get-FzfFilePreviewCommand {
    if (Test-Command bat -Application) {
        return "bat --style=numbers --color=always --line-range=:200 '{}'"
    }

    "Get-Content -LiteralPath '{}' -TotalCount 160"
}

function Select-FromNumberedMenu {
    # The non-fzf fallback for every picker in the profile. Prints a numbered list, reads a
    # choice, and maps it back to a value. -DisplayScript renders each item's line; -ValueScript
    # maps the chosen item to the return value. A non-numeric / out-of-range entry returns the
    # raw text when -PassThruText is set (so a picker can accept a typed name), else $null.
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][scriptblock]$DisplayScript,
        [Parameter(Mandatory)][scriptblock]$ValueScript,
        [string]$Prompt = 'Select',
        [switch]$PassThruText
    )

    $number = 1
    foreach ($item in $Items) {
        Write-Host ("{0,2}. {1}" -f $number, (& $DisplayScript $item))
        $number++
    }

    $selectedIndex = 0
    $choice = Read-Host $Prompt
    if ([int]::TryParse($choice, [ref]$selectedIndex) -and $selectedIndex -ge 1 -and $selectedIndex -le $Items.Count) {
        return (& $ValueScript $Items[$selectedIndex - 1])
    }

    if ($PassThruText) {
        return $choice
    }

    $null
}

function Invoke-FzfFile {
    if (-not (Test-Command fzf -Application)) {
        Write-Warning 'fzf is not installed or not on PATH.'
        return
    }

    $source = if (Test-Command rg -Application) {
        rg --files
    }
    elseif (Test-Command fd -Application) {
        fd --type file
    }
    else {
        Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object FullName
    }

    $fzfArgs = New-FzfArgs -Prompt 'file> ' -Label 'files' -Preview (Get-FzfFilePreviewCommand)
    $source | fzf @fzfArgs
}

function Invoke-FzfHistory {
    if (-not (Test-Command fzf -Application)) {
        Write-Warning 'fzf is not installed or not on PATH.'
        return
    }

    $historyPath = if (Get-Module PSReadLine) {
        (Get-PSReadLineOption).HistorySavePath
    }

    if ($historyPath -and (Test-Path $historyPath)) {
        $fzfArgs = New-FzfArgs -Prompt 'history> ' -Label 'history' -ExtraArgs @('--tac', '--scheme=history')
        Get-Content -LiteralPath $historyPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique |
        fzf @fzfArgs
    }
}

function ff {
    Invoke-FzfFile
}
