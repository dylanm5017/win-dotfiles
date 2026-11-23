# Dot-sourced by Get-Timeline.ps1 for -Audit, -Verdict and -AuditDone. Finds candidates worth a look with
# plain rules; deciding what they mean is left to a person or the /audit-timeline skill.

# A harmless verdict stays quiet until the count grows past this, or it is this old.
$auditGrowthFactor = 2
$auditGrowthMinimum = 3
$auditRecheckDays = 180

function Get-AuditId([string]$Rule, [string]$Subject) {
    # Versions are dropped, so a verdict survives the next update of the same thing.
    "$Rule|$(($Subject -replace '\d+(\.\d+)+', '#' -replace '\s+', ' ').Trim().ToLowerInvariant())"
}

function New-AuditCandidate {
    param([string]$Rule, [string]$Subject, [string]$Detail, [object[]]$Events, [int]$Previous = -1, [string]$Hint)
    $times = @($Events | ForEach-Object { $_.Time } | Sort-Object)
    [PSCustomObject]@{
        Id       = Get-AuditId $Rule $Subject
        Rule     = $Rule
        Subject  = $Subject
        Detail   = $Detail
        Count    = [math]::Max(1, $times.Count)
        Previous = if ($Previous -ge 0) { $Previous } else { $null }
        Days     = @($times | ForEach-Object { $_.Date } | Sort-Object -Unique).Count
        First    = if ($times) { $times[0] } else { $null }
        Last     = if ($times) { $times[-1] } else { $null }
        Hint     = $Hint
        Status   = 'new'
        Verdict  = $null
        Reason   = $null
    }
}

function Find-AuditCandidate {
    # Reads hidden events too: a repeat can be routine noise or a stuck loop, and only looking tells which.
    param([object[]]$Events, [datetime]$Now, [int]$Days = 30, [datetime]$HistoryStart, $State, $Snapshot)

    $cut = $Now.AddDays(-$Days)
    $recent = @($Events | Where-Object { $_.Time -ge $cut })
    $older = @($Events | Where-Object { $_.Time -lt $cut })
    $before = @($older | Where-Object { $_.Time -ge $cut.AddDays(-$Days) })
    $comparable = $HistoryStart -le $cut.AddDays(-$Days + 1)
    $boots = @($recent | Where-Object { $_.Kind -eq 'power' -and $_.Subject -eq 'boot' }).Count
    $stripVersion = { param($s) ($s -replace '\s+[\d.]+$', '') }

    foreach ($group in $recent | Where-Object { $_.Kind -in 'install', 'update', 'service', 'driver' -and $_.Detail -notmatch 'FAILED|error \d' } | Group-Object Kind, Subject, Detail | Where-Object Count -ge 5) {
        $dayCount = @($group.Group | ForEach-Object { $_.Time.Date } | Sort-Object -Unique).Count
        $hint = @()
        if ($boots -ge 3 -and [math]::Abs($group.Count / $boots - 1) -le 0.25) { $hint += "about once per boot ($boots boots)" }
        if ($group.Count -ge 2 * $dayCount) { $hint += "$([math]::Round($group.Count / $dayCount, 1)) times on each day it happened" }
        if ($group.Group[0].Noise) { $hint += 'hidden as noise in the normal view' }
        New-AuditCandidate -Rule repeat -Subject $group.Group[0].Subject -Detail $group.Group[0].Detail -Events $group.Group `
            -Previous $(if ($comparable) { @($before | Where-Object { $_.Subject -eq $group.Group[0].Subject -and $_.Detail -eq $group.Group[0].Detail }).Count } else { -1 }) -Hint ($hint -join '; ')
    }

    foreach ($group in $recent | Where-Object { $_.Kind -in 'install', 'update' -and $_.Detail -match 'FAILED|error \d' } | Group-Object Subject) {
        New-AuditCandidate -Rule failure -Subject $group.Name -Detail (($group.Group.Detail | Sort-Object -Unique) -join '; ') -Events $group.Group
    }

    foreach ($group in $recent | Where-Object Kind -eq 'crash' | Group-Object { & $stripVersion $_.Subject }) {
        $previous = @($before | Where-Object { $_.Kind -eq 'crash' -and (& $stripVersion $_.Subject) -eq $group.Name }).Count
        $rising = $comparable -and $group.Count -ge 2 -and $group.Count -ge 2 * $previous
        if ($group.Count -lt 3 -and -not $rising) { continue }
        $hint = if (-not $comparable) { 'no full earlier period to compare with' } elseif ($previous -eq 0) { "none in the $Days days before" } elseif ($rising) { 'rising' } elseif ($group.Count -lt $previous) { 'falling' } else { 'steady' }
        New-AuditCandidate -Rule crash -Subject $group.Name -Detail (($group.Group.Detail | Group-Object | Sort-Object Count -Descending | Select-Object -First 2 -ExpandProperty Name) -join '; ') -Events $group.Group -Previous $(if ($comparable) { $previous } else { -1 }) -Hint $hint
    }

    $unclean = @($recent | Where-Object { ($_.Kind -eq 'power' -and $_.Subject -eq 'unclean shutdown') -or ($_.Kind -eq 'crash' -and $_.Subject -eq 'Windows') })
    if ($unclean) { New-AuditCandidate -Rule shutdown -Subject 'unclean shutdown or blue screen' -Detail (($unclean.Detail | Sort-Object -Unique) -join '; ') -Events $unclean }

    $security = @($recent | Where-Object Kind -eq 'security')
    foreach ($group in $security | Group-Object Subject) { New-AuditCandidate -Rule security -Subject $group.Name -Detail (($group.Group.Detail | Sort-Object -Unique) -join '; ') -Events $group.Group }

    $knownServices = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($event in $older | Where-Object Kind -eq 'service') { [void]$knownServices.Add((Get-AuditId service $event.Subject)) }
    foreach ($group in $recent | Where-Object Kind -eq 'service' | Group-Object { Get-AuditId service $_.Subject } | Where-Object { -not $knownServices.Contains($_.Name) }) {
        New-AuditCandidate -Rule newservice -Subject $group.Group[0].Subject -Detail $group.Group[0].Detail -Events $group.Group -Hint 'not seen before this period'
    }

    $changes = @($recent | Where-Object Kind -eq 'change')
    foreach ($event in $changes | Where-Object { $_.Subject -match '^(startup|tasks|services): ' -and $_.Detail -match '^added' }) {
        New-AuditCandidate -Rule autostart -Subject $event.Subject -Detail $event.Detail -Events @($event)
    }
    foreach ($event in $changes | Where-Object { $_.Subject -match '^files: ' -and $_.Detail -match '-> missing' }) {
        New-AuditCandidate -Rule missing -Subject $event.Subject -Detail $event.Detail -Events @($event)
    }
    foreach ($group in $changes | Group-Object Subject | Where-Object Count -ge 3) {
        New-AuditCandidate -Rule flapping -Subject $group.Name -Detail $group.Group[-1].Detail -Events $group.Group -Hint "changed $($group.Count) times"
    }

    $through = if ($State.ArchivedThrough) { ([datetime]$State.ArchivedThrough).ToLocalTime() }
    if (-not $through -or $through -lt $Now.AddDays(-3)) {
        New-AuditCandidate -Rule recorder -Subject 'timeline recorder' -Detail $(if ($through) { "last recorded $($through.ToString('yyyy-MM-dd HH:mm'))" } else { 'has never recorded' }) -Hint 'changes since then are missing from this audit'
    }
    if ($Snapshot) {
        $empty = @($Snapshot.Sections.PSObject.Properties | Where-Object { $null -eq $_.Value } | ForEach-Object Name)
        if ($empty) { New-AuditCandidate -Rule recorder -Subject 'snapshot sections' -Detail "could not be read: $($empty -join ', ')" }
    }
}

function Read-AuditVerdict {
    $path = Join-Path $Store 'verdicts.json'
    $map = @{}
    if (Test-Path -LiteralPath $path) {
        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) { $map[$p.Name] = $p.Value }
    }
    $map
}

function Add-AuditVerdict {
    # Sets Status: new, known (quiet), returned (grew since it was called harmless), recheck (old verdict) or open.
    param([object[]]$Candidates, [hashtable]$Verdicts, [datetime]$Now)
    foreach ($candidate in $Candidates) {
        $verdict = $Verdicts[$candidate.Id]
        if ($verdict) {
            $candidate.Verdict = $verdict.Verdict
            $candidate.Reason = $verdict.Reason
            $limit = [math]::Max($auditGrowthFactor * $verdict.Count, $verdict.Count + $auditGrowthMinimum)
            $candidate.Status = if ($verdict.Verdict -ne 'harmless') { 'open' }
            elseif ($candidate.Count -gt $limit) { 'returned' }
            elseif (([datetime]$verdict.Date).AddDays($auditRecheckDays) -lt $Now) { 'recheck' }
            else { 'known' }
        }
        $candidate
    }
}

function Get-TimelineAudit {
    param([int]$Days, [datetime]$Now = (Get-Date))

    $start = $Now.AddDays(-2 * $Days)
    $events = @(Join-TimelineEvent -Events (@(Get-LoggedEvent -Start $start -End $Now) + @(Read-TimelineArchive -Start $start.AddYears(-5) -End $Now)))
    $read = { param($name) $path = Join-Path $Store $name; if (Test-Path -LiteralPath $path) { try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { } } }
    $candidates = @(Find-AuditCandidate -Events $events -Now $Now -Days $Days -HistoryStart $(if ($events) { $events[0].Time } else { $Now }) -State (& $read 'state.json') -Snapshot (& $read 'snapshot.json'))
    # Two versions of the same thing share an id; keep the larger.
    $candidates = @($candidates | Group-Object Id | ForEach-Object { $_.Group | Sort-Object Count -Descending | Select-Object -First 1 })
    $rank = @{ security = 0; missing = 1; shutdown = 2; failure = 3; crash = 4; autostart = 5; newservice = 6; flapping = 7; repeat = 8; recorder = 9 }
    [PSCustomObject]@{
        Now            = $Now
        Days           = $Days
        HistoryStart   = if ($events) { $events[0].Time } else { $null }
        # Drift can only be seen from the first snapshot on.
        SnapshotsSince = if (Test-Path -LiteralPath $Store) { (Get-Item -LiteralPath $Store).CreationTime } else { $null }
        LastAudit      = (& $read 'audit.json').LastAudit
        Candidates     = @(Add-AuditVerdict -Candidates $candidates -Verdicts (Read-AuditVerdict) -Now $Now | Sort-Object { $rank[$_.Rule] }, { -$_.Count }, Id)
    }
}

function Save-AuditVerdict {
    param([string]$Id, [string]$Verdict, [string]$Reason, [int]$Days)
    $candidate = (Get-TimelineAudit -Days $Days).Candidates | Where-Object Id -eq $Id | Select-Object -First 1
    if (-not $candidate) { throw "No current audit candidate has the id '$Id'. List them with: timeline -Audit -All" }
    if (-not $Reason) { throw 'A verdict needs -Reason, so next month you can tell why.' }
    $verdicts = Read-AuditVerdict
    $verdicts[$Id] = [ordered]@{ Verdict = $Verdict; Reason = $Reason; Count = $candidate.Count; Date = (Get-Date).ToString('o') }
    Write-AuditFile 'verdicts.json' ([PSCustomObject]$verdicts)
    Write-Output "Recorded '$Verdict' for $Id (at $($candidate.Count) in $Days days)."
}

function Write-AuditFile([string]$Name, $Value) {
    [void][IO.Directory]::CreateDirectory($Store)
    $path = Join-Path $Store $Name
    [IO.File]::WriteAllText("$path.tmp", ($Value | ConvertTo-Json -Depth 5))
    [IO.File]::Move("$path.tmp", $path, $true)
}

function Show-TimelineAudit {
    param($Audit, [switch]$IncludeKnown)
    $list = @($Audit.Candidates | Where-Object { $IncludeKnown -or $_.Status -ne 'known' })
    $codes = @{ new = '33'; returned = '31'; recheck = '36'; open = '35'; known = '90' }
    $esc = [char]27
    Write-Host "Audit of the last $($Audit.Days) days. Logs reach back to $(if ($Audit.HistoryStart) { $Audit.HistoryStart.ToString('yyyy-MM-dd') } else { 'nothing' }); snapshots since $(if ($Audit.SnapshotsSince) { $Audit.SnapshotsSince.ToString('yyyy-MM-dd') } else { 'never' })." -ForegroundColor White
    foreach ($c in $list) {
        $trend = if ($null -ne $c.Previous) { ", $($c.Previous) in the $($Audit.Days) before" }
        Write-Host "`n$esc[$($codes[$c.Status])m$($c.Status.PadRight(9))$esc[0m $($c.Rule): $($c.Subject)"
        Write-Host "          $($c.Count) on $($c.Days) day(s)$trend$(if ($c.Hint) { "; $($c.Hint)" })" -ForegroundColor DarkGray
        if ($c.Detail) { Write-Host "          $($c.Detail)" -ForegroundColor DarkGray }
        if ($c.Verdict) { Write-Host "          was $($c.Verdict): $($c.Reason)" -ForegroundColor DarkGray }
        Write-Host "          id: $($c.Id)" -ForegroundColor DarkGray
    }
    $quiet = @($Audit.Candidates | Where-Object Status -eq 'known').Count
    if (-not $list) { Write-Host "`nNothing new to look at." }
    if ($quiet -and -not $IncludeKnown) { Write-Host "`n$quiet known-harmless item(s) hidden; -All shows them." -ForegroundColor DarkGray }
}
