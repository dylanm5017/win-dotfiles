function Find-Kill-Port {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Port
    )

    try {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue

        if (-not $listeners) {
            Write-Host "No process is listening on port $Port." -ForegroundColor Green
            return
        }

        $listeners | ForEach-Object {
            $processId = $_.OwningProcess
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue

            if ($proc) {
                Write-Host "PID $processId ($($proc.ProcessName)) is listening on port $Port."
                $response = Read-Host 'Do you want to kill it? (y/n)'

                if ($response -match '^[Yy]$') {
                    Stop-Process -Id $processId -Force
                    Write-Host "Killed PID $processId" -ForegroundColor Green
                }
                else {
                    Write-Host "Keeping PID $processId alive." -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "Process $processId disappeared before we could act on it." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }
}

Set-Alias findkill Find-Kill-Port

function ConvertTo-TimeDifferencePoint {
    param([Parameter(Mandatory)][string]$Value)

    $text = $Value.Trim().ToLowerInvariant()
    $baseDate = (Get-Date).Date
    $isPm = $text.EndsWith('pm')
    $isAm = $text.EndsWith('am')
    $text = $text -replace '\s*(am|pm)$', ''

    if ($text -match '^\d{3,4}$') {
        $minutes = [int]$text.Substring($text.Length - 2)
        $hours = [int]$text.Substring(0, $text.Length - 2)
    }
    elseif ($text -match '^\d{1,2}(:\d{1,2})?$') {
        $parts = $text -split ':'
        $hours = [int]$parts[0]
        $minutes = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    }
    else {
        throw "Time value is not understood: $Value"
    }

    if ($minutes -lt 0 -or $minutes -gt 59) {
        throw "Minute value is invalid: $Value"
    }

    if ($isPm -and $hours -lt 12) {
        $hours += 12
    }
    elseif ($isAm -and $hours -eq 12) {
        $hours = 0
    }

    $baseDate.AddHours($hours).AddMinutes($minutes)
}

function ConvertTo-TimeDifferenceRange {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '^\s*(.+?)\s*-\s*(.+?)\s*$') {
        throw "Range must look like start-end: $Value"
    }

    [PSCustomObject]@{
        Start = $Matches[1]
        End   = $Matches[2]
    }
}

function Format-TimeDifferenceDuration {
    param([Parameter(Mandatory)][TimeSpan]$Duration)

    '{0}:{1:00}' -f [math]::Floor($Duration.TotalHours), $Duration.Minutes
}

function Find-Time-Difference {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Range,

        [switch]$DecimalOnly,
        [switch]$ClockOnly
    )

    if (-not $Range) {
        Write-Warning 'Usage: td 9:15 10:45 or td 9:15-10:45 11-12:30'
        return
    }

    $ranges = if ($Range.Count -eq 2 -and $Range[0] -notmatch '-' -and $Range[1] -notmatch '-') {
        @([PSCustomObject]@{ Start = $Range[0]; End = $Range[1] })
    }
    else {
        @($Range | ForEach-Object { ConvertTo-TimeDifferenceRange $_ })
    }

    $rows = foreach ($rangeItem in $ranges) {
        $start = ConvertTo-TimeDifferencePoint $rangeItem.Start
        $end = ConvertTo-TimeDifferencePoint $rangeItem.End

        while ($end -le $start) {
            $end = $end.AddHours(12)
        }

        $duration = $end - $start
        [PSCustomObject]@{
            Range        = "$($rangeItem.Start)-$($rangeItem.End)"
            Duration     = Format-TimeDifferenceDuration $duration
            DecimalHours = [math]::Round($duration.TotalHours, 2)
        }
    }

    $totalHours = ($rows | Measure-Object -Property DecimalHours -Sum).Sum
    $totalDuration = [TimeSpan]::FromHours($totalHours)

    if ($ranges.Count -eq 1) {
        if ($DecimalOnly) {
            '{0:n2}' -f $rows[0].DecimalHours
        }
        elseif ($ClockOnly) {
            $rows[0].Duration
        }
        else {
            "{0} ({1:n2}h)" -f $rows[0].Duration, $rows[0].DecimalHours
        }
        return
    }

    $rows
    [PSCustomObject]@{
        Range        = 'Total'
        Duration     = Format-TimeDifferenceDuration $totalDuration
        DecimalHours = [math]::Round($totalHours, 2)
    }
}

Set-Alias td Find-Time-Difference

function npm2excel {
    param([string]$Output = 'npm-outdated.xlsx')

    try {
        $json = npm outdated --json | Out-String
        if (-not $json) {
            Write-Host 'All packages up to date.'
            return
        }

        $data = $json | ConvertFrom-Json
        $rows = foreach ($pkg in $data.PSObject.Properties.Name) {
            $info = $data.$pkg
            [PSCustomObject]@{
                Package    = $pkg
                Current    = $info.current
                Wanted     = $info.wanted
                Latest     = $info.latest
                UpdateType = if ($info.current -eq $info.latest) {
                    'Up to date'
                }
                elseif ($info.wanted -eq $info.latest) {
                    'Minor/Patch'
                }
                else {
                    'Major'
                }
            }
        }

        $rows | Export-Excel -Path $Output -AutoSize -BoldTopRow -WorksheetName 'Outdated'
        Write-Host "Created $Output"
    }
    catch {
        Write-Host "Error: $_"
    }
}

function port {
    param([int]$p)

    Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess
}

function repostat {
    param([string]$Root = (Get-Location).Path)

    Get-ChildItem -LiteralPath $Root -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } | ForEach-Object {
        Push-Location -LiteralPath $_.FullName
        try {
            $branch = git rev-parse --abbrev-ref HEAD
            $status = git status --porcelain

            [PSCustomObject]@{
                Repo   = $_.Name
                Branch = $branch
                Dirty  = if ($status) { 'Yes' } else { 'Clean' }
            }
        }
        finally {
            Pop-Location
        }
    } | Format-Table
}

function note {
    param([string]$text)

    Add-Content "$HOME\notes.txt" "$(Get-Date): $text"
}

Set-Alias npmout npm2excel

function npmout-all {
    param(
        [string]$Output = 'all-npm-outdated.xlsx',
        [string]$Root = (Get-Location).Path
    )

    $results = @()

    Get-ChildItem -LiteralPath $Root -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'package.json') } | ForEach-Object {
        Push-Location -LiteralPath $_.FullName
        try {
            $json = npm outdated --json | Out-String

            if ($json) {
                $data = $json | ConvertFrom-Json

                foreach ($pkg in $data.PSObject.Properties.Name) {
                    $info = $data.$pkg

                    $results += [PSCustomObject]@{
                        Repo    = $_.Name
                        Package = $pkg
                        Current = $info.current
                        Latest  = $info.latest
                    }
                }
            }
        }
        finally {
            Pop-Location
        }
    }

    if ($results.Count -eq 0) {
        Write-Host 'No outdated packages found.'
        return
    }

    $results | Export-Excel -Path $Output -AutoSize
    Write-Host "Created $Output"
}

function foreachrepo {
    param(
        [Parameter(Mandatory, Position = 0)][string]$cmd,
        [string]$Root = (Get-Location).Path
    )

    Get-ChildItem -LiteralPath $Root -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } | ForEach-Object {
        Write-Host "---- $($_.Name) ----" -ForegroundColor Cyan
        Push-Location -LiteralPath $_.FullName
        try {
            Invoke-Expression $cmd
        }
        finally {
            Pop-Location
        }
    }
}

function Get-CommandSummary {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        $command.Source
    }
    else {
        'not found'
    }
}

function Invoke-DevDoctor {
    Write-Host 'Running environment checks...' -ForegroundColor Cyan

    Write-Host "`nNode/npm:"
    Write-Host "node path: $(Get-CommandSummary node)"
    if (Get-Command node -ErrorAction SilentlyContinue) { node -v }
    Write-Host "npm path:  $(Get-CommandSummary npm)"
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm -v
        Write-Host "npm prefix:"
        npm config get prefix
        Write-Host "npm cache:"
        npm config get cache
    }

    Write-Host "`nPython/pip:"
    Write-Host "python path: $(Get-CommandSummary python)"
    if (Get-Command python -ErrorAction SilentlyContinue) { python --version }
    Write-Host "pip path:    $(Get-CommandSummary pip)"
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        pip --version
        Write-Host "pip cache:"
        pip cache dir
    }

    Write-Host "`n.NET/NuGet:"
    Write-Host "dotnet path: $(Get-CommandSummary dotnet)"
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        dotnet --version
        dotnet nuget locals all --list
    }

    Write-Host "`nGo:"
    Write-Host "go path: $(Get-CommandSummary go)"
    if (Get-Command go -ErrorAction SilentlyContinue) {
        go env GOPATH GOMODCACHE GOCACHE
    }

    Write-Host "`nRust/Cargo:"
    Write-Host "cargo path: $(Get-CommandSummary cargo)"
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        cargo --version
        Write-Host "CARGO_HOME=$env:CARGO_HOME"
        Write-Host "RUSTUP_HOME=$env:RUSTUP_HOME"
    }
    Write-Host "rustc path: $(Get-CommandSummary rustc)"
    if (Get-Command rustc -ErrorAction SilentlyContinue) { rustc --version }
}

function dev {
    param(
        [Parameter(Mandatory)]
        [string]$cmd
    )

    switch ($cmd) {
        'status' {
            repostat
        }

        'sync' {
            Write-Host 'Syncing all repos...' -ForegroundColor Cyan
            foreachrepo 'git pull'
            dev status
        }

        'outdated' {
            npmout-all
        }

        'clean' {
            Write-Host 'Cleaning node_modules...' -ForegroundColor Yellow
            Get-ChildItem -Recurse -Directory -Filter node_modules |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        'doctor' {
            Invoke-DevDoctor
        }

        default {
            Write-Host 'Available commands:'
            Write-Host '  dev status    -> repo health'
            Write-Host '  dev sync      -> git pull all'
            Write-Host '  dev outdated  -> npm outdated (all repos)'
            Write-Host '  dev clean     -> remove all node_modules'
            Write-Host '  dev doctor    -> environment check'
        }
    }
}
