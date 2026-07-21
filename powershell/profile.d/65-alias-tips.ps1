# Alias tips: when a typed command has a shorter alias or wrapper function in this profile, print
# the shorter form after the line is accepted (PowerShell's answer to zsh-you-should-use). The
# index is derived from the live session — Alias: entries plus single-statement passthrough
# functions like `function gs { git status @args }` — so new shortcuts are picked up for free.
# Mute with WINDOTFILES_ALIAS_TIPS=off; tune the noise floor with WINDOTFILES_ALIAS_TIPS_MIN.

$script:WinDotfilesAliasTipIndex = $null
$script:WinDotfilesAliasTipCoverage = $null
$script:WinDotfilesAliasTipMinSaving = if ($env:WINDOTFILES_ALIAS_TIPS_MIN -match '^\d+$') {
    [int]$env:WINDOTFILES_ALIAS_TIPS_MIN
}
else {
    4
}

function Test-WinDotfilesAliasTipsEnabled {
    $IsInteractiveShell -and $env:WINDOTFILES_ALIAS_TIPS -notin @('0', 'off', 'false', 'no')
}

function Resolve-WinDotfilesAliasTipExpansion {
    # Returns the command a wrapper function stands for ('git status' for `{ git status @args }`),
    # or $null when the body is anything more interesting than a single literal passthrough.
    param([Parameter(Mandatory)]$Function)

    $ast = $Function.ScriptBlock.Ast
    if (-not $ast) {
        return $null
    }

    $body = if ($ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $ast.Body } else { $ast }
    if (-not $body -or $body.ParamBlock -or $body.BeginBlock -or $body.ProcessBlock -or -not $body.EndBlock) {
        return $null
    }

    $statements = @($body.EndBlock.Statements)
    if ($statements.Count -ne 1) {
        return $null
    }

    $pipeline = $statements[0] -as [System.Management.Automation.Language.PipelineAst]
    if (-not $pipeline -or $pipeline.PipelineElements.Count -ne 1) {
        return $null
    }

    $command = $pipeline.PipelineElements[0] -as [System.Management.Automation.Language.CommandAst]
    if (-not $command) {
        return $null
    }

    $elements = @($command.CommandElements)
    $last = $elements[-1]
    if ($last -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $last.Splatted -and $last.VariablePath.UserPath -eq 'args') {
        $elements = if ($elements.Count -gt 1) { @($elements[0..($elements.Count - 2)]) } else { @() }
    }

    if ($elements.Count -eq 0) {
        return $null
    }

    foreach ($element in $elements) {
        # Anything with a variable or subexpression in it would never match what gets typed.
        if ($element -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            return $null
        }
    }

    ($elements | ForEach-Object { $_.Extent.Text }) -join ' '
}

function Add-WinDotfilesAliasTipEntry {
    param(
        [Parameter(Mandatory)][hashtable]$Index,
        [string]$Expansion,
        [string]$Name
    )

    if (-not $Expansion -or -not $Name -or $Name.Length -ge $Expansion.Length) {
        return
    }

    $key = $Expansion.Trim().ToLowerInvariant()
    if (-not $key -or $key -eq $Name.ToLowerInvariant()) {
        return
    }

    $existing = $Index[$key]
    if ($existing -and ($existing.Length -lt $Name.Length -or ($existing.Length -eq $Name.Length -and $existing -le $Name))) {
        return
    }

    $Index[$key] = $Name
}

function Update-WinDotfilesAliasTipIndex {
    [CmdletBinding()]
    param()

    $index = @{}
    $expansions = @{}

    foreach ($function in Get-ChildItem -Path Function: -ErrorAction SilentlyContinue) {
        $expansion = Resolve-WinDotfilesAliasTipExpansion -Function $function
        if ($expansion) {
            $expansions[$function.Name] = $expansion
            Add-WinDotfilesAliasTipEntry -Index $index -Expansion $expansion -Name $function.Name
        }
    }

    foreach ($alias in Get-ChildItem -Path Alias: -ErrorAction SilentlyContinue) {
        # `gci` for Get-ChildItem, and one hop further so `nv` also covers Use-NodeVersion's body.
        Add-WinDotfilesAliasTipEntry -Index $index -Expansion $alias.Definition -Name $alias.Name
        if ($expansions.ContainsKey($alias.Definition)) {
            Add-WinDotfilesAliasTipEntry -Index $index -Expansion $expansions[$alias.Definition] -Name $alias.Name
        }
    }

    $script:WinDotfilesAliasTipIndex = $index
    $index
}

function Get-WinDotfilesAliasTipIndex {
    if ($null -eq $script:WinDotfilesAliasTipIndex) {
        # Built on first use rather than at load so the profile keeps its startup budget and the
        # index still sees everything, including profile.local.ps1 and lazily imported modules.
        Update-WinDotfilesAliasTipIndex | Out-Null
    }

    $script:WinDotfilesAliasTipIndex
}

function Update-WinDotfilesAliasTipCoverage {
    # The tip index only understands one-line passthrough functions. The interesting wrappers in
    # this profile (fbemu, gpub, gsync…) are full commands with param blocks and guards, so they
    # stay invisible to it — which is why aliasdoctor kept suggesting aliases for work they already
    # do. This second pass digs the external tool invocations out of those bodies.
    #
    # Deliberately NOT fed into the tips: a wrapper like gsync runs several git commands, so
    # "you typed git fetch, use gsync" would be wrong. Suppressing a suggestion on this evidence is
    # safe; making one is not.
    [CmdletBinding()]
    param()

    $coverage = @{}
    $isApplication = @{}
    $verbs = [System.Collections.Generic.HashSet[string]]::new([string[]](Get-Verb).Verb, [StringComparer]::OrdinalIgnoreCase)

    foreach ($function in Get-ChildItem -Path Function: -ErrorAction SilentlyContinue) {
        # Module-provided functions aren't this profile's shortcuts.
        if ($function.Module -or -not $function.ScriptBlock.Ast) {
            continue
        }

        # This profile's own convention: Verb-Noun means internal helper, short CLI-style name means
        # something you actually type. Only the latter can "cover" a command — and skipping the
        # helpers keeps this off the multi-thousand-line ASTs in 150-workstation.
        $dash = $function.Name.IndexOf('-')
        if ($dash -gt 0 -and $verbs.Contains($function.Name.Substring(0, $dash))) {
            continue
        }

        foreach ($command in $function.ScriptBlock.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $root = $command.GetCommandName()
            if (-not $root) {
                continue
            }

            if (-not $isApplication.ContainsKey($root)) {
                $isApplication[$root] = [bool](Get-Command -Name $root -CommandType Application -ErrorAction SilentlyContinue)
            }

            # Only real tools count. Without this, a Write-Host inside `gs` would register the
            # profile's shortest function name as the shortcut for `Write-Host`.
            if (-not $isApplication[$root]) {
                continue
            }

            foreach ($prefix in Get-WinDotfilesLiteralCommandPrefixes -Command $command) {
                # A bare tool name says nothing; it takes a subcommand to mean anything.
                if (-not $prefix.Contains(' ')) {
                    continue
                }

                $key = $prefix.ToLowerInvariant()
                if (-not $coverage.ContainsKey($key)) {
                    $coverage[$key] = $function.Name
                }
            }
        }
    }

    $script:WinDotfilesAliasTipCoverage = $coverage
    $coverage
}

function Get-WinDotfilesAliasTipCoverage {
    if ($null -eq $script:WinDotfilesAliasTipCoverage) {
        Update-WinDotfilesAliasTipCoverage | Out-Null
    }

    $script:WinDotfilesAliasTipCoverage
}

function Find-WinDotfilesAliasTip {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line)

    $index = Get-WinDotfilesAliasTipIndex
    if (-not $index -or $index.Count -eq 0) {
        return
    }

    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$null, [ref]$parseErrors)
    if (-not $ast -or $parseErrors.Count -gt 0) {
        return
    }

    $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($command in $commands) {
        $elements = @($command.CommandElements | ForEach-Object { $_.Extent.Text })
        $best = $null

        # Longest match wins: `git status --short` should suggest gs, not something matching `git`.
        for ($take = $elements.Count; $take -ge 1; $take--) {
            $typed = ($elements[0..($take - 1)]) -join ' '
            $name = $index[$typed.ToLowerInvariant()]
            if (-not $name) {
                continue
            }

            $saving = $typed.Length - $name.Length
            if ($saving -lt $script:WinDotfilesAliasTipMinSaving) {
                continue
            }

            if (-not $best -or $saving -gt $best.Saving) {
                $best = [PSCustomObject]@{ Typed = $typed; Alias = $name; Saving = $saving }
            }
        }

        if ($best -and $seen.Add($best.Alias)) {
            $best
        }
    }
}

function Show-WinDotfilesAliasTip {
    [CmdletBinding()]
    param([string]$Line)

    if (-not (Test-WinDotfilesAliasTipsEnabled) -or [string]::IsNullOrWhiteSpace($Line)) {
        return
    }

    foreach ($tip in Find-WinDotfilesAliasTip -Line $Line) {
        Write-Host '  tip ' -NoNewline -ForegroundColor DarkYellow
        Write-Host $tip.Alias -NoNewline -ForegroundColor Yellow
        Write-Host "  →  $($tip.Typed)" -ForegroundColor DarkGray
    }
}

function Get-WinDotfilesLiteralCommandPrefixes {
    # The leading run of bareword tokens for a command, as cumulative prefixes: `git status --short`
    # yields git / git status / git status --short. Stops at the first quoted string, variable, or
    # expression, since those are the parts that vary between runs and can't be baked into an alias.
    param([Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$Command)

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($element in $Command.CommandElements) {
        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
            $tokens.Add($element.Extent.Text)
        }
        elseif ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $element.StringConstantType -eq [System.Management.Automation.Language.StringConstantType]::BareWord) {
            $tokens.Add($element.Extent.Text)
        }
        else {
            break
        }
    }

    for ($take = 1; $take -le $tokens.Count; $take++) {
        ($tokens[0..($take - 1)]) -join ' '
    }
}

function New-WinDotfilesAliasTipName {
    # gs for `git status`, gci for a lone `Get-ChildItem` — initials, with Verb-Noun split on the
    # dash so single-token commands still produce something pronounceable. Flags and paths are
    # skipped for naming (they make noise like `nrtn.esf`), and only the first few words count.
    # When the initials are taken, the last word grows a letter at a time — `gc` is already git
    # commit, so `git checkout` lands on `gco` rather than a useless `gc2`.
    param([Parameter(Mandatory)][string[]]$Tokens)

    $words = @(
        $Tokens |
        Where-Object { -not $_.StartsWith('-') } |
        ForEach-Object { ($_.ToLowerInvariant() -replace '[^a-z0-9-]', '').Trim('-') } |
        Where-Object { $_ } |
        Select-Object -First 3
    )

    if (-not $words) {
        return $null
    }

    $initials = foreach ($word in $words) {
        if ($word.Contains('-')) {
            ($word -split '-' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1) }) -join ''
        }
        else {
            $word.Substring(0, 1)
        }
    }

    $base = -join $initials
    if (-not $base) {
        return $null
    }

    # Single-letter aliases are a footgun in a shell this dense, so treat one as already taken.
    if ($base.Length -ge 2 -and -not (Test-Command $base)) {
        return $base
    }

    $stem = if ($initials.Count -gt 1) { -join $initials[0..($initials.Count - 2)] } else { '' }
    $last = $words[-1] -replace '-', ''

    for ($take = 2; $take -le [Math]::Min(4, $last.Length); $take++) {
        $candidate = $stem + $last.Substring(0, $take)
        if ($candidate.Length -le 6 -and -not (Test-Command $candidate)) {
            return $candidate
        }
    }

    # A numbered alias is worse than no alias — drop the suggestion instead.
    $null
}

function Invoke-WinDotfilesAliasDoctor {
    # The mirror image of the alias tips: tips catch long forms that already have a shortcut, this
    # finds the ones that *should* and don't, ranked by the typing they would have saved. Pairs with
    # histdoctor, which reports frequent commands that no longer resolve.
    [CmdletBinding()]
    param(
        [int]$Top = 15,
        [int]$MinCount = 5,
        [switch]$AsSnippet
    )

    $historyPath = (Get-PSReadLineOption -ErrorAction SilentlyContinue).HistorySavePath
    if (-not $historyPath -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning "PowerShell history was not found: $historyPath"
        return
    }

    $secretPattern = '(?i)(token|secret|password|passwd|pwd|apikey|api[_-]?key|authorization|bearer|credential|connectionstring|client[_-]?secret|access[_-]?token|refresh[_-]?token|sas|tenant|login)'
    $index = Get-WinDotfilesAliasTipIndex
    $coverage = Get-WinDotfilesAliasTipCoverage
    $counts = @{}

    foreach ($line in Get-Content -LiteralPath $historyPath) {
        if (-not $line -or $line -match $secretPattern) {
            continue
        }

        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$null, [ref]$parseErrors)
        if (-not $ast -or $parseErrors.Count -gt 0) {
            continue
        }

        # Walk straight to the line's first command rather than Find()-ing it: a scriptblock
        # predicate runs per AST node, which over 20k history lines is most of the runtime.
        $endBlock = $ast.EndBlock
        if (-not $endBlock -or $endBlock.Statements.Count -eq 0) {
            continue
        }

        $pipeline = $endBlock.Statements[0] -as [System.Management.Automation.Language.PipelineAst]
        if (-not $pipeline -or $pipeline.PipelineElements.Count -eq 0) {
            continue
        }

        $command = $pipeline.PipelineElements[0] -as [System.Management.Automation.Language.CommandAst]
        if (-not $command) {
            continue
        }

        # Navigation is the project registry's job (p / goto / mark / workon), not an alias per path.
        if ($command.GetCommandName() -in @('cd', 'sl', 'set-location', 'pushd', 'z', 'zi')) {
            continue
        }

        foreach ($prefix in Get-WinDotfilesLiteralCommandPrefixes -Command $command) {
            $counts[$prefix] = 1 + $counts[$prefix]
        }
    }

    # Rank on string arithmetic alone first. Naming a candidate costs several Get-Command probes,
    # so that only happens for the shortlist that survives ranking and de-duplication.
    $ranked = foreach ($entry in $counts.GetEnumerator()) {
        if ($entry.Value -lt $MinCount) {
            continue
        }

        $tokens = @($entry.Key -split ' ')

        # A lone short word (`clear`, `code`) is already about as terse as an alias would be.
        if ($tokens.Count -eq 1 -and $entry.Key.Length -lt 8) {
            continue
        }

        $key = $entry.Key.ToLowerInvariant()
        if ($index[$key]) {
            # Has a shortcut; the tips already nudge toward it.
            continue
        }

        # Which existing wrapper, if any, already speaks to this command. Reported rather than
        # suppressed: gpub genuinely replaces `git push --set-upstream origin`, but gprune only
        # touches some of `git branch`, and only you can tell those apart.
        $coveredBy = $null
        for ($take = $tokens.Count; $take -ge 2; $take--) {
            $head = (($tokens[0..($take - 1)]) -join ' ').ToLowerInvariant()
            if ($coverage[$head]) {
                $coveredBy = $coverage[$head]
                break
            }
        }

        # Score against the shortest form already available, not the raw text. Once `gch` exists,
        # `git checkout -b` is really `gch -b` to type, so a dedicated alias saves 2 characters and
        # not 10 — otherwise every flag variant of an aliased command looks like a huge win.
        $baseline = $entry.Key
        for ($take = $tokens.Count - 1; $take -ge 1; $take--) {
            $head = ($tokens[0..($take - 1)]) -join ' '
            $existing = $index[$head.ToLowerInvariant()]
            if ($existing) {
                $baseline = $existing + $entry.Key.Substring($head.Length)
                break
            }
        }

        # One char per token is the best an initials-based name could do.
        $bestCase = $baseline.Length - $tokens.Count
        if ($bestCase -lt $script:WinDotfilesAliasTipMinSaving) {
            continue
        }

        [PSCustomObject]@{
            Command   = $entry.Key
            Baseline  = $baseline
            Tokens    = $tokens
            Count     = $entry.Value
            CoveredBy = $coveredBy
            Estimate  = $bestCase * $entry.Value
        }
    }

    # One suggestion per command family: `git push origin` beating `git push` shouldn't also emit
    # `git push`, and `git` alone shouldn't crowd out either of them.
    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in ($ranked | Sort-Object Estimate -Descending)) {
        $overlaps = $false
        foreach ($existing in $kept) {
            if ($existing.Command.StartsWith("$($candidate.Command) ") -or $candidate.Command.StartsWith("$($existing.Command) ")) {
                $overlaps = $true
                break
            }
        }

        if (-not $overlaps) {
            $kept.Add($candidate)
        }
    }

    # Over-fetch: naming can still reject a candidate, and so can a command that no longer resolves.
    $results = foreach ($candidate in ($kept | Select-Object -First ($Top * 3))) {
        if (-not (Test-Command $candidate.Tokens[0])) {
            # Already histdoctor's department: a command that no longer resolves.
            continue
        }

        $name = New-WinDotfilesAliasTipName -Tokens $candidate.Tokens
        if (-not $name) {
            continue
        }

        $saving = $candidate.Baseline.Length - $name.Length
        if ($saving -lt $script:WinDotfilesAliasTipMinSaving) {
            continue
        }

        [PSCustomObject]@{
            Alias     = $name
            Count     = $candidate.Count
            Saved     = $saving * $candidate.Count
            CoveredBy = $candidate.CoveredBy
            Command   = $candidate.Command
        }
    }

    $results = @($results | Sort-Object Saved -Descending | Select-Object -First $Top)

    if (-not $AsSnippet) {
        return $results
    }

    foreach ($result in $results) {
        "function $($result.Alias) { $($result.Command) @args }   # $($result.Count)x, saves $($result.Saved) chars"
    }
}

Set-Alias -Name aliasdoctor -Value Invoke-WinDotfilesAliasDoctor -Force

function Show-WinDotfilesAliasTipList {
    [CmdletBinding()]
    param(
        [string]$Filter,
        [switch]$Wrapped
    )

    $source = if ($Wrapped) { Get-WinDotfilesAliasTipCoverage } else { Get-WinDotfilesAliasTipIndex }

    $source.GetEnumerator() |
    Where-Object { -not $Filter -or $_.Key -like "*$Filter*" -or $_.Value -like "*$Filter*" } |
    Sort-Object { $_.Value } |
    ForEach-Object { [PSCustomObject]@{ Alias = $_.Value; Expands = $_.Key } }
}

Set-Alias -Name aliastips -Value Show-WinDotfilesAliasTipList -Force
