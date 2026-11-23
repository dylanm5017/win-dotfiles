#Requires -Version 7
<#
.SYNOPSIS
    One timeline of what changed on this machine: boots, updates, installs, crashes, audio and drift.
.DESCRIPTION
    Merges the Windows event logs with a recorded history. The logs need no background process but
    roll over (audio and Store after about 12 days) and never record what is installed, so a scheduled
    -Record run archives the events and snapshots app versions, startup items, tasks, services, PATH
    and key files. Differences between snapshots become "change" events, dated when they were noticed.

    The history stays on this machine, under $env:WINDOTFILES_TIMELINE or the dev cache. It holds
    command lines, so keep it out of the repo.
.PARAMETER Around
    Centre the view on this time instead of now; -Hours sets the distance either side. The year and the date
    are optional: '11-13 06:00', '11/13 6am', '06:00', 'yesterday 18:30' or '2026-11-13 06:00'. A date alone
    means noon. Without a year or a date it is the most recent match.
.PARAMETER Kind
    power, update, install, driver, service, crash, audio, security or change.
.PARAMETER All
    Include routine noise (Defender definitions, virtual adapters, installer reconfigurations).
.PARAMETER Plain
    Print a flat list instead of the graph.
.PARAMETER Raw
    Return the events, uncollapsed, instead of printing them.
.PARAMETER Audit
    List things worth a look in the last 30 days (-Days changes it): repeats, failures, rising crashes, new
    services and startup items, vanished files. -All includes ones judged harmless, -Json is for scripts.
.PARAMETER Verdict
    Record what an audit item (-Id) turned out to be: harmless (stays quiet unless it grows), watch or raised.
.PARAMETER AuditDone
    Note that an audit was completed, which quiets the monthly reminder.
.PARAMETER Record
    Archive new events, take a snapshot and store what changed since the last one.
.PARAMETER Register
    Create the scheduled task that runs -Record five minutes after sign-in and daily at 12:30.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 365)][int]$Days = 2,
    [string]$Around,
    [ValidateRange(1, 168)][int]$Hours = 6,
    [ValidateSet('power', 'update', 'install', 'driver', 'service', 'crash', 'audio', 'security', 'change')][string[]]$Kind,
    [string]$Match,
    [switch]$All,
    [switch]$Plain,
    [switch]$Raw,
    [switch]$Audit,
    [switch]$Json,
    [ValidateSet('harmless', 'watch', 'raised')][string]$Verdict,
    [string]$Id,
    [string]$Reason,
    [switch]$AuditDone,
    [switch]$Record,
    [switch]$Register,
    # Loads the functions without running anything, for tests.
    [switch]$FunctionsOnly,
    [string]$Store = $(if ($env:WINDOTFILES_TIMELINE) { $env:WINDOTFILES_TIMELINE } elseif (Test-Path 'C:\Workspace\Dev\Cache') { 'C:\Workspace\Dev\Cache\win-dotfiles\timeline' } else { Join-Path $env:LOCALAPPDATA 'win-dotfiles\timeline' })
)

$taskName = 'win-dotfiles Record-Timeline'

function ConvertTo-TimelineTime {
    # [datetime] casts need a year, which is the part nobody types.
    param([string]$Text, [datetime]$Now = (Get-Date))

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.DateTimeStyles]::AllowWhiteSpaces
    $value = [datetime]::MinValue
    $clean = $Text.Trim().ToLowerInvariant()
    $times = 'H:mm', 'H:mm:ss', 'h:mmtt', 'h:mm tt', 'htt', 'h tt'

    $named = if ($clean -match '^(today|yesterday)\b\s*(.*)$') { $clean = $Matches[2]; if ($Matches[1] -eq 'today') { $Now.Date } else { $Now.Date.AddDays(-1) } }
    if ($named -and -not $clean) { return $named.AddHours(12) }
    if ([datetime]::TryParseExact($clean, [string[]]$times, $culture, $style, [ref]$value)) {
        if ($named) { return $named + $value.TimeOfDay }
        $today = $Now.Date + $value.TimeOfDay
        return $(if ($today -gt $Now) { $today.AddDays(-1) } else { $today })
    }
    if ($named) { throw "Could not read '$Text' as a time. Try '11-13 06:00', '06:00' or 'yesterday 18:30'." }

    # A leap year, so 2-29 parses; the real year is filled in below.
    foreach ($date in 'M-d', 'M/d') {
        foreach ($time in @('') + $times) {
            if (-not [datetime]::TryParseExact("2000$($date[1])$clean", "yyyy$date".Insert(4, $date[1]) + $(if ($time) { " $time" }), $culture, $style, [ref]$value)) { continue }
            if (-not $time) { $value = $value.AddHours(12) }
            for ($year = $Now.Year; $year -gt $Now.Year - 8; $year--) {
                if ($value.Month -eq 2 -and $value.Day -eq 29 -and -not [datetime]::IsLeapYear($year)) { continue }
                $candidate = [datetime]::new($year, $value.Month, $value.Day).Add($value.TimeOfDay)
                if ($candidate.Date -le $Now.Date) { return $candidate }
            }
        }
    }
    if ($clean -match '\d{4}') {
        $parsed = [datetime]::TryParse($Text, $culture, $style, [ref]$value) -or [datetime]::TryParse($Text, [ref]$value)
        if ($parsed) { return $(if ($clean -notmatch ':|\d\s*[ap]m') { $value.Date.AddHours(12) } else { $value }) }
    }
    throw "Could not read '$Text' as a time. Try '11-13 06:00', '06:00' or 'yesterday 18:30'."
}

function New-TimelineEvent {
    param([datetime]$Time, [string]$Kind, [string]$Subject, [string]$Detail, [switch]$Noise)
    # The .NET SDK unpacks its daily update catalog with an MSI admin install, which Windows logs as "installed".
    # Handled here, not where the log is read, so archived copies get the same wording and still deduplicate.
    if ($Kind -eq 'install' -and $Subject -match '^Microsoft\.NET\.Workloads\.\d' -and $Detail -eq 'installed') {
        $Detail = 'update catalog unpacked (nothing installed)'
        $Noise = $true
    }
    [PSCustomObject]@{ Time = $Time; Kind = $Kind; Subject = $Subject; Detail = $Detail; Noise = [bool]$Noise }
}

function Get-EventField {
    param($Event)
    $fields = @{}
    foreach ($node in ([xml]$Event.ToXml()).Event.EventData.Data) {
        if ($node -is [Xml.XmlElement] -and $node.Name) { $fields[$node.Name] = $node.'#text' }
    }
    $fields
}

function Get-TimelineLog {
    param([hashtable]$Filter, [datetime]$Start, [datetime]$End)
    $query = $Filter.Clone()
    $query.StartTime = $Start
    $query.EndTime = $End
    try { Get-WinEvent -FilterHashtable $query -ErrorAction Stop }
    catch {
        # An empty result is an error to Get-WinEvent; anything else means a source is missing from the view.
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { Write-Warning "Timeline source $($Filter.LogName) $($Filter.ProviderName): $($_.Exception.Message)" }
    }
}

function ConvertTo-AudioTransition {
    # Most endpoint events swap one inactive state for another. Only a change into or out of active (1) is
    # worth showing, tracked per endpoint; the first sighting of an inactive endpoint is not a change.
    param([object[]]$Changes)
    $names = @{ '1' = 'active'; '2' = 'disabled'; '4' = 'not present'; '8' = 'unplugged' }
    $active = @{}
    foreach ($change in ($Changes | Sort-Object Time)) {
        $isActive = "$($change.State)" -eq '1'
        $was = $active[$change.Id]
        $active[$change.Id] = $isActive
        if ($was -eq $isActive -or ($null -eq $was -and -not $isActive)) { continue }
        New-TimelineEvent -Time $change.Time -Kind audio -Subject $change.Name -Detail $(if ($names["$($change.State)"]) { $names["$($change.State)"] } else { "state $($change.State)" })
    }
}

function Get-LoggedEvent {
    param([datetime]$Start, [datetime]$End)

    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12, 13 } $Start $End) {
        New-TimelineEvent $e.TimeCreated power $(if ($e.Id -eq 12) { 'boot' } else { 'shutdown' })
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 } $Start $End) {
        $f = Get-EventField $e
        New-TimelineEvent $e.TimeCreated power 'unclean shutdown' "the previous session did not shut down; bugcheck $($f.BugcheckCode)"
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'User32'; Id = 1074 } $Start $End) {
        $f = Get-EventField $e
        New-TimelineEvent $e.TimeCreated power "$($f.param5) requested" "$((Split-Path -Leaf ($f.param1 -replace '\s\(.*\)$')) ) as $($f.param7)"
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19, 20 } $Start $End) {
        $f = Get-EventField $e
        $title = $f.updateTitle -replace '^[0-9A-Z]{12}-', ''
        New-TimelineEvent $e.TimeCreated update $title $(if ($e.Id -eq 19) { 'installed' } else { "FAILED $($f.errorCode)" }) -Noise:($e.Id -eq 19 -and $title -match 'Security Intelligence Update|WindowsAppRuntime')
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'Setup'; Id = 2 } $Start $End) {
        $p = $e.Properties
        if ($p.Count -ge 3 -and "$($p[2].Value)" -eq 'Installed') { New-TimelineEvent $e.TimeCreated update "$($p[0].Value)" 'Windows package installed' -Noise:("$($p[0].Value)" -notmatch '^KB') }
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; Id = 658 } $Start $End) {
        if ($e.Message -match 'Marking package \{?([^}_\s]+)_([\d.]+)_') { New-TimelineEvent $e.TimeCreated update $Matches[1] "$($Matches[2]) is waiting for the app to close" }
    }
    $msi = @{ 1033 = 'installed'; 1034 = 'removed'; 1035 = 'reconfigured' }
    foreach ($e in Get-TimelineLog @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; Id = 1033, 1034, 1035 } $Start $End) {
        $p = $e.Properties
        $status = "$($p[3].Value)"
        New-TimelineEvent $e.TimeCreated install "$($p[0].Value) $($p[1].Value)" "$($msi[$e.Id])$(if ($status -notin '0', '3010') { " (error $status)" })" -Noise:($e.Id -eq 1035)
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; Id = 400 } $Start $End) {
        $f = Get-EventField $e
        $device = ($f.DeviceInstanceId -split '\\')[0..1] -join '\'
        New-TimelineEvent $e.TimeCreated driver "$($f.DriverProvider) $($f.DriverName)" "$($f.DriverVersion) on $device" -Noise:($f.DriverInbox -eq 'true' -or $device -match 'Wintun|XvddEnum|PRINTENUM|vwifimp' -or ($f.DriverProvider -eq 'Advanced Micro Devices' -and $device -eq 'ROOT\SYSTEM'))
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7031, 7034, 7045 } $Start $End) {
        $f = Get-EventField $e
        if ($e.Id -eq 7045) { New-TimelineEvent $e.TimeCreated service $f.ServiceName "new service or driver: $($f.ImagePath)" -Noise:($f.ImagePath -match '\\(NTIOLib|MpKsl|AmdTools)') }
        else { New-TimelineEvent $e.TimeCreated crash "service $($f.param1)" 'stopped unexpectedly' }
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000 } $Start $End) {
        $p = $e.Properties
        New-TimelineEvent $e.TimeCreated crash "$($p[0].Value) $($p[1].Value)" "crashed in $($p[3].Value) ($($p[6].Value))"
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002 } $Start $End) {
        $p = $e.Properties
        New-TimelineEvent $e.TimeCreated crash "$($p[0].Value) $($p[1].Value)" 'stopped responding'
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001 } $Start $End) {
        New-TimelineEvent $e.TimeCreated crash 'Windows' "blue screen $($e.Properties[0].Value)"
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'System'; ProviderName = 'nvlddmkm' } $Start $End) {
        New-TimelineEvent $e.TimeCreated crash 'NVIDIA driver' "$(if ($e.Properties.Count -gt 1) { $e.Properties[1].Value }) (event $($e.Id))"
    }
    foreach ($e in Get-TimelineLog @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1116, 1117 } $Start $End) {
        $f = Get-EventField $e
        New-TimelineEvent $e.TimeCreated security $f.'Threat Name' "$(if ($e.Id -eq 1116) { 'detected' } else { 'action taken' }): $($f.Path)"
    }
    $changes = foreach ($e in Get-TimelineLog @{ LogName = 'Microsoft-Windows-Audio/Operational'; Id = 65 } $Start $End) {
        $f = Get-EventField $e
        if ($f.flow -eq '0') { [PSCustomObject]@{ Time = $e.TimeCreated; Name = $f.DeviceName; Id = $f.DeviceId; State = $f.NewState } }
    }
    if ($changes) { ConvertTo-AudioTransition -Changes @($changes) }
}

function Get-KeyFile {
    $paths = @(
        "$env:ProgramFiles\YASB\yasb.exe", "$env:ProgramFiles\YASB\lib\library.zip", "$env:ProgramFiles\YASB\lib\library.dat"
        "$HOME\scoop\apps\komorebi\current\komorebi.exe", "$HOME\scoop\apps\whkd\current\whkd.exe"
        "$HOME\komorebi.json", "$HOME\.config\whkdrc", "$HOME\.config\yasb\config.yaml", "$HOME\.config\yasb\styles.css", "$HOME\.config\wezterm\wezterm.lua"
        $PROFILE.CurrentUserCurrentHost
    )
    $files = @{}
    foreach ($path in $paths) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        $files[$path] = if (-not $item) { 'missing' }
        # A linked config changes with every edit in the repo; what matters is whether it is still linked.
        elseif ($item.LinkType) { "$($item.LinkType) -> $($item.Target)" }
        else { '{0} bytes, sha256 {1}' -f $item.Length, (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.Substring(0, 12) }
    }
    $files
}

function Get-SnapshotCollector {
    [ordered]@{
        windows  = {
            $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            @{ build = "$($v.CurrentBuild).$($v.UBR)"; release = "$($v.DisplayVersion)" }
        }
        apps     = {
            $map = @{}
            foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
                Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object DisplayName | ForEach-Object { $map[$_.DisplayName] = "$($_.DisplayVersion)" }
            }
            $map
        }
        store    = {
            # Inbox PowerShell: the Appx module only loads in pwsh through a slow compatibility session.
            $lines = & powershell.exe -NoProfile -NonInteractive -Command 'Get-AppxPackage -ErrorAction Stop | ForEach-Object { $_.Name + [char]9 + $_.Version }'
            if ($LASTEXITCODE -ne 0) { throw 'Get-AppxPackage failed' }
            $map = @{}
            foreach ($line in $lines) {
                $name, $version = $line -split "`t"
                if ($version -and (-not $map[$name] -or [version]$version -gt [version]$map[$name])) { $map[$name] = $version }
            }
            $map
        }
        scoop    = {
            $map = @{}
            Get-ChildItem -LiteralPath "$HOME\scoop\apps" -Directory -ErrorAction Stop | ForEach-Object {
                $current = Get-Item -LiteralPath (Join-Path $_.FullName 'current') -Force -ErrorAction SilentlyContinue
                if ($current.Target) { $map[$_.Name] = Split-Path -Leaf @($current.Target)[0] }
            }
            $map
        }
        startup  = {
            $map = @{}
            foreach ($key in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
                $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
                if ($item) { foreach ($name in $item.GetValueNames()) { $map["$($key.Substring(0, 4)) $name"] = "$($item.GetValue($name))" } }
            }
            foreach ($folder in [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) {
                Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini' | ForEach-Object { $map["folder $($_.Name)"] = 'present' }
            }
            $root = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
            Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                $package = $_.PSChildName
                Get-ChildItem -LiteralPath $_.PSPath -ErrorAction SilentlyContinue | Where-Object { 'UserEnabledStartupOnce' -in $_.GetValueNames() } | ForEach-Object {
                    $map["store $package"] = if ($_.GetValue('State') -in 2, 4) { 'on' } else { 'off' }
                }
            }
            $map
        }
        tasks    = {
            $map = @{}
            Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
                # Enabled rather than State, which flips between Ready and Running.
                $map[(($_.TaskPath + $_.TaskName) -replace 'S-1-5-21[-\d]+', '<sid>')] = "$(if ($_.Settings.Enabled) { 'on' } else { 'off' }): $(($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; ')"
            }
            $map
        }
        services = {
            $map = @{}
            # Per-user services get a new numeric suffix at every sign-in.
            Get-CimInstance Win32_Service -ErrorAction Stop | ForEach-Object { $map[($_.Name -replace '_[0-9a-f]{4,}$', '_<user>')] = "$($_.StartMode): $($_.PathName)" }
            $map
        }
        gpu      = {
            $map = @{}
            Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { $map[$_.Name] = $_.DriverVersion }
            $map
        }
        path     = {
            $map = @{}
            foreach ($scope in 'User', 'Machine') { [Environment]::GetEnvironmentVariable('Path', $scope) -split ';' | Where-Object { $_ } | ForEach-Object { $map["$scope $_"] = 'present' } }
            $map
        }
        audio    = {
            $json = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Get-AudioState.ps1')
            if ($LASTEXITCODE -ne 0) { throw 'Get-AudioState.ps1 failed' }
            $endpoints = $json | ConvertFrom-Json
            @{
                'default output' = "$(($endpoints | Where-Object DefaultMultimedia).Name)"
                'calls output'   = "$(($endpoints | Where-Object DefaultCommunications).Name)"
            }
        }
        files    = { Get-KeyFile }
    }
}

function New-TimelineSnapshot {
    $sections = [ordered]@{}
    $collectors = Get-SnapshotCollector
    foreach ($name in $collectors.Keys) {
        # A section that could not be read is stored as null, which Compare-TimelineSnapshot skips.
        try { $sections[$name] = & $collectors[$name] } catch { $sections[$name] = $null; Write-Warning "Snapshot section '$name' failed: $($_.Exception.Message)" }
    }
    [PSCustomObject]@{ Time = (Get-Date).ToString('o'); Sections = [PSCustomObject]$sections }
}

function ConvertTo-Map($Value) {
    $map = @{}
    if ($Value -is [Collections.IDictionary]) { foreach ($k in $Value.Keys) { $map["$k"] = "$($Value[$k])" } }
    elseif ($Value) { foreach ($p in $Value.PSObject.Properties) { $map[$p.Name] = "$($p.Value)" } }
    $map
}

function Compare-TimelineSnapshot {
    param($Before, $After)
    $time = [datetime]$After.Time
    $since = ([datetime]$Before.Time).ToString('MM-dd HH:mm')
    foreach ($section in $After.Sections.PSObject.Properties.Name) {
        $oldValue = $Before.Sections.$section
        $newValue = $After.Sections.$section
        if ($null -eq $oldValue -or $null -eq $newValue) { continue }
        $old = ConvertTo-Map $oldValue
        $new = ConvertTo-Map $newValue
        # A populated section that comes back empty is a failed read, not a mass removal.
        if ($old.Count -gt 5 -and $new.Count -eq 0) { continue }
        foreach ($key in @($old.Keys) + @($new.Keys) | Sort-Object -Unique) {
            $detail = if (-not $old.ContainsKey($key)) { "added$(if ($new[$key]) { ": $($new[$key])" })" }
            elseif (-not $new.ContainsKey($key)) { "removed$(if ($old[$key]) { " (was $($old[$key]))" })" }
            elseif ($old[$key] -cne $new[$key]) { "$($old[$key]) -> $($new[$key])" }
            if ($detail) { New-TimelineEvent $time change "$section`: $key" "$detail [since $since]" }
        }
    }
}

function Get-EventKey($Event) { '{0}|{1}|{2}|{3}' -f ([datetime]$Event.Time).ToUniversalTime().Ticks, $Event.Kind, $Event.Subject, $Event.Detail }

function Read-TimelineArchive {
    param([datetime]$Start, [datetime]$End)
    if (-not (Test-Path -LiteralPath $Store)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Store -Filter 'events-*.jsonl') {
        foreach ($line in [IO.File]::ReadLines($file.FullName)) {
            # A run killed mid-append leaves a partial last line.
            try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            $time = ([datetime]$event.Time).ToLocalTime()
            if ($time -ge $Start -and $time -le $End) { New-TimelineEvent $time $event.Kind $event.Subject $event.Detail -Noise:$event.Noise }
        }
    }
}

function Join-TimelineEvent {
    param([object[]]$Events)
    $seen = [Collections.Generic.HashSet[string]]::new()
    $Events | Where-Object { $_ -and $seen.Add((Get-EventKey $_)) } | Sort-Object Time
}

function Group-TimelineEvent {
    # Folds repeats of the same thing within ten minutes into one row with a count. Audio folds by device,
    # since a monitor waking flips its endpoints several times. Boots and shutdowns are never folded,
    # and nothing folds across one.
    param([object[]]$Events, [int]$WindowMinutes = 10)
    $open = @{}
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($event in ($Events | Sort-Object Time)) {
        if ($event.Kind -eq 'power') { $open = @{} }
        $key = if ($event.Kind -eq 'audio') { "audio|$($event.Subject)" } else { "$($event.Kind)|$($event.Subject)|$($event.Detail)" }
        $row = $open[$key]
        if ($row -and $event.Kind -ne 'power' -and ($event.Time - $row.Last).TotalMinutes -le $WindowMinutes) {
            $row.Count++
            $row.Last = $event.Time
            # Several endpoints can share a device name, so differing states are listed, not resolved to the last.
            if ($event.Detail -notin ($row.Detail -split '/')) { $row.Detail = "$($row.Detail)/$($event.Detail)" }
        }
        else {
            $row = [PSCustomObject]@{ Time = $event.Time; Last = $event.Time; Kind = $event.Kind; Subject = $event.Subject; Detail = $event.Detail; Count = 1 }
            $open[$key] = $row
            $rows.Add($row)
        }
    }
    $rows | Sort-Object Time
}

function Format-Span([timespan]$Span) {
    if ($Span.TotalDays -ge 1) { return '{0}d{1:00}h' -f [int][math]::Floor($Span.TotalDays), $Span.Hours }
    if ($Span.TotalHours -ge 1) { return '{0}h{1:00}m' -f [int][math]::Floor($Span.TotalHours), $Span.Minutes }
    if ($Span.TotalMinutes -ge 1) { return "$([int][math]::Floor($Span.TotalMinutes))m" }
    "$([int][math]::Floor($Span.TotalSeconds))s"
}

$timelineColors = @{ power = '1;37'; update = '34'; install = '34'; driver = '35'; service = '35'; crash = '31'; audio = '36'; security = '1;31'; change = '33' }

function Get-TimelineGraph {
    # Draws the rows like git log --graph. The trunk is the machine: solid while on, dotted while off. Lane 1 is
    # what changed, 2 is audio, 3 is what broke; a lane branches off at its first event and merges at shutdown.
    param([object[]]$Rows, [int]$Width = 120, [switch]$Color, [switch]$Gaps, [Nullable[datetime]]$Now)

    $esc = [char]27
    $laneOf = @{ power = 0; update = 1; install = 1; driver = 1; service = 1; change = 1; audio = 2; crash = 3; security = 3 }
    $laneCode = '1;37', '34', '36', '31'
    $glyphs = @{ update = '▲'; install = '+'; driver = '◆'; service = '◇'; change = '∆'; audio = '●'; crash = '✗'; security = '!' }
    function Paint([string]$Text, [string]$Code) { if ($Color) { "$esc[${Code}m$Text$esc[0m" } else { $Text } }

    $open = @($false, $false, $false, $false)
    $off = $Rows -and $Rows[0].Kind -eq 'power' -and $Rows[0].Subject -eq 'boot'
    $day = $null
    $last = $null

    function Get-Rail([string]$Trunk, [string]$TrunkCode = '1;37', [int]$From = 1) {
        $rail = if ($Trunk) { Paint $Trunk $TrunkCode } else { '' }
        for ($i = $From; $i -le 3; $i++) { $rail += if ($open[$i]) { ' ' + (Paint '│' $laneCode[$i]) } else { '  ' } }
        $rail
    }

    foreach ($row in $Rows) {
        $trunk = if ($off) { '┊' } else { '│' }
        $isBoot = $row.Kind -eq 'power' -and $row.Subject -eq 'boot'
        if ($Gaps -and $last) {
            $span = $row.Time - $last
            $note = if ($off -and $isBoot -and $span.TotalMinutes -ge 1) { "off $(Format-Span $span)" } elseif (-not $off -and -not $isBoot -and $span.TotalHours -ge 2) { "quiet $(Format-Span $span)" }
            if ($note) { (Get-Rail $trunk $(if ($off) { '90' } else { '1;37' })) + '  ' + (Paint $note '90') }
        }
        if ($row.Time.Date -ne $day) {
            $day = $row.Time.Date
            (Get-Rail $trunk $(if ($off) { '90' } else { '1;37' })) + '  ' + (Paint $day.ToString('ddd yyyy-MM-dd') '1')
        }

        $lane = $laneOf[$row.Kind]
        if ($isBoot) {
            # Lanes still open here were cut off by a shutdown that was never logged.
            $open = @($false, $false, $false, $false)
            $off = $false
            $graph = Get-Rail '◉' '1;32'
        }
        elseif ($row.Kind -eq 'power' -and $row.Subject -eq 'shutdown') {
            $graph = Paint '○' '1;37'
            $end = 3
            while ($end -gt 0 -and -not $open[$end]) { $end-- }
            for ($i = 1; $i -le 3; $i++) {
                $graph += if ($i -gt $end) { '  ' } else { Paint ('─' + $(if ($i -eq $end) { '╯' } elseif ($open[$i]) { '┴' } else { '─' })) $laneCode[$end] }
            }
            $open = @($false, $false, $false, $false)
            $off = $true
        }
        elseif ($lane -eq 0) {
            $graph = if ($row.Subject -eq 'unclean shutdown') { Get-Rail '✗' '1;31' } else { Get-Rail '◌' }
        }
        else {
            # Anything logged means the machine is running, whatever the last power event said.
            $off = $false
            $glyph = Paint $glyphs[$row.Kind] $timelineColors[$row.Kind]
            if ($open[$lane]) {
                $graph = Paint '│' '1;37'
                for ($i = 1; $i -lt $lane; $i++) { $graph += if ($open[$i]) { ' ' + (Paint '│' $laneCode[$i]) } else { '  ' } }
                $graph += " $glyph"
            }
            else {
                $graph = Paint '├' '1;37'
                for ($i = 1; $i -lt $lane; $i++) { $graph += Paint ('─' + $(if ($open[$i]) { '┼' } else { '─' })) $laneCode[$lane] }
                $graph += (Paint '─' $laneCode[$lane]) + $glyph
                $open[$lane] = $true
            }
            $graph += Get-Rail '' '' ($lane + 1)
        }

        $text = "$($row.Subject)$(if ($row.Detail) { "  $($row.Detail)" })$(if ($row.Count -gt 1) { " x$($row.Count)" })" -replace '\p{C}', ' '
        # 7 graph columns, then two spaces, the time, two spaces and the padded kind.
        $room = [math]::Max(10, $Width - 28)
        if ($text.Length -gt $room) { $text = $text.Substring(0, $room - 1) + '…' }
        $graph + '  ' + (Paint $row.Time.ToString('HH:mm:ss') '90') + '  ' + (Paint $row.Kind.PadRight(8) $timelineColors[$row.Kind]) + ' ' + $text
        $last = if ($row.Last -gt $row.Time) { $row.Last } else { $row.Time }
    }

    if ($Now) {
        if ($Gaps -and $last -and ($Now - $last).TotalHours -ge 2) { (Get-Rail '│') + '  ' + (Paint "quiet $(Format-Span ($Now - $last))" '90') }
        (Get-Rail '◎' '1;32') + '  ' + (Paint "$($Now.ToString('HH:mm:ss'))  now" '90')
    }
}

function Save-TimelineRecord {
    [void][IO.Directory]::CreateDirectory($Store)
    $snapshotPath = Join-Path $Store 'snapshot.json'
    $statePath = Join-Path $Store 'state.json'
    $now = Get-Date

    $previous = if (Test-Path -LiteralPath $snapshotPath) { try { Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json } catch { Write-Warning "Unreadable snapshot, starting over: $($_.Exception.Message)" } }
    $state = if (Test-Path -LiteralPath $statePath) { try { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { } }
    # A day of overlap covers events written late; the key check drops repeats. The first run takes what the logs still hold.
    $start = if ($state.ArchivedThrough) { ([datetime]$state.ArchivedThrough).ToLocalTime().AddDays(-1) } else { $now.AddDays(-30) }

    $snapshot = New-TimelineSnapshot
    $fresh = @(Get-LoggedEvent -Start $start -End $now)
    if ($previous) {
        $fresh += @(Compare-TimelineSnapshot -Before $previous -After $snapshot)
        # Keep the last good copy of a section that failed, so the next run still has something to compare.
        foreach ($name in @($snapshot.Sections.PSObject.Properties.Name)) {
            if ($null -eq $snapshot.Sections.$name -and $null -ne $previous.Sections.$name) { $snapshot.Sections.$name = $previous.Sections.$name }
        }
    }

    $known = [Collections.Generic.HashSet[string]]::new()
    foreach ($event in Read-TimelineArchive -Start $start.AddMinutes(-1) -End $now.AddMinutes(1)) { [void]$known.Add((Get-EventKey $event)) }
    $added = @($fresh | Where-Object { $known.Add((Get-EventKey $_)) } | Sort-Object Time)
    foreach ($month in $added | Group-Object { $_.Time.ToString('yyyy-MM') }) {
        $lines = $month.Group | ForEach-Object { [ordered]@{ Time = $_.Time.ToUniversalTime().ToString('o'); Kind = $_.Kind; Subject = $_.Subject; Detail = $_.Detail; Noise = $_.Noise } | ConvertTo-Json -Compress }
        $file = Join-Path $Store "events-$($month.Name).jsonl"
        # Close off a partial last line first, or the next event would be glued to it and lost.
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0 -and (Get-Content -LiteralPath $file -AsByteStream -Tail 1) -ne 10) { [IO.File]::AppendAllText($file, "`n") }
        [IO.File]::AppendAllLines($file, [string[]]@($lines))
    }

    foreach ($pair in @($snapshotPath, $snapshot), @($statePath, [PSCustomObject]@{ ArchivedThrough = $now.ToUniversalTime().ToString('o') })) {
        $temp = "$($pair[0]).tmp"
        [IO.File]::WriteAllText($temp, ($pair[1] | ConvertTo-Json -Depth 6))
        [IO.File]::Move($temp, $pair[0], $true)
    }
    Write-Output "Recorded $($added.Count) new events ($(@($added | Where-Object Kind -eq 'change').Count) changes since the last snapshot)."
}

. (Join-Path $PSScriptRoot 'timeline-audit.ps1')

if ($FunctionsOnly) { return }

if ($Register) {
    $arguments = "--headless pwsh.exe -NoLogo -NoProfile -NonInteractive -File `"$PSCommandPath`" -Record"
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arguments
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $logon.Delay = 'PT5M'
    $daily = New-ScheduledTaskTrigger -Daily -At '12:30'
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon, $daily) -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
    Write-Host "Registered scheduled task '$taskName'." -ForegroundColor Green
    return
}

if ($Record) {
    Save-TimelineRecord
    return
}

if ($Audit -or $Verdict -or $AuditDone) {
    $auditDays = if ($PSBoundParameters.ContainsKey('Days')) { $Days } else { 30 }
    if ($Verdict) {
        try { Save-AuditVerdict -Id $Id -Verdict $Verdict -Reason $Reason -Days $auditDays } catch { Write-Error $_.Exception.Message; exit 1 }
    }
    elseif ($AuditDone) {
        Write-AuditFile 'audit.json' ([PSCustomObject]@{ LastAudit = (Get-Date).ToString('o') })
        Write-Output 'Audit noted.'
    }
    else {
        $report = Get-TimelineAudit -Days $auditDays
        if (-not $All -and $Json) { $report.Candidates = @($report.Candidates | Where-Object Status -ne 'known') }
        if ($Json) { $report | ConvertTo-Json -Depth 5 } else { Show-TimelineAudit -Audit $report -IncludeKnown:$All }
    }
    return
}

$end = Get-Date
$start = $end.AddDays(-$Days)
if ($PSBoundParameters.ContainsKey('Around')) {
    $center = try { ConvertTo-TimelineTime $Around } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow; return }
    $start = $center.AddHours(-$Hours)
    $end = $center.AddHours($Hours)
}

# Read audio from further back so the first transition in view is judged against a known state.
$logged = @(Get-LoggedEvent -Start $start.AddDays(-1) -End $end | Where-Object { $_.Time -ge $start })
$events = @(Join-TimelineEvent -Events ($logged + @(Read-TimelineArchive -Start $start -End $end)))
if (-not $All) { $events = @($events | Where-Object { -not $_.Noise }) }
if ($Kind) { $events = @($events | Where-Object { $_.Kind -in $Kind }) }
if ($Match) { $events = @($events | Where-Object { "$($_.Subject) $($_.Detail)" -match $Match }) }
if ($Raw) { return $events }

$width = try { [math]::Max(80, [Console]::WindowWidth - 1) } catch { 120 }
$rows = @(Group-TimelineEvent -Events $events)
if ($Plain) {
    $day = $null
    foreach ($row in $rows) {
        if ($row.Time.Date -ne $day) {
            $day = $row.Time.Date
            Write-Host "`n$($day.ToString('ddd yyyy-MM-dd'))" -ForegroundColor White
        }
        $text = "$($row.Subject)$(if ($row.Detail) { "  $($row.Detail)" })$(if ($row.Count -gt 1) { " x$($row.Count)" })" -replace '\p{C}', ' '
        $room = $width - 20
        if ($text.Length -gt $room) { $text = $text.Substring(0, $room - 1) + '…' }
        Write-Host "  $($row.Time.ToString('HH:mm:ss'))  " -NoNewline -ForegroundColor DarkGray
        Write-Host "$([char]27)[$($timelineColors[$row.Kind])m$($row.Kind.PadRight(8))$([char]27)[0m $text"
    }
}
elseif ($rows) {
    # A filtered view hides events, so its gaps would not mean the machine was quiet or off.
    $filtered = [bool]($Kind -or $Match)
    $graphOptions = @{ Rows = $rows; Width = $width; Color = $true; Gaps = -not $filtered }
    if (-not $filtered -and -not $PSBoundParameters.ContainsKey('Around')) { $graphOptions.Now = $end }
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        Get-TimelineGraph @graphOptions | ForEach-Object { Write-Host $_ }
    }
    finally {
        [Console]::OutputEncoding = $encoding
    }
}
if (-not $events) { Write-Host 'Nothing in this range.' }

$snapshotFile = Get-Item -LiteralPath ([IO.Path]::Combine($Store, 'snapshot.json')) -ErrorAction SilentlyContinue
if (-not $snapshotFile) { Write-Host "`nNo snapshot yet, so app, startup and file changes are not shown. Run: timeline -Record" -ForegroundColor Yellow }
elseif ($snapshotFile.LastWriteTime -lt (Get-Date).AddDays(-3)) { Write-Host "`nLast snapshot was $($snapshotFile.LastWriteTime.ToString('MM-dd HH:mm')); is the '$taskName' task running?" -ForegroundColor Yellow }
