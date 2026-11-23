$WinAudioStateScript = Join-Path $WinDotfilesRoot 'tools\Get-AudioState.ps1'
$WinAudioStartWaveLinkScript = Join-Path $WinDotfilesRoot 'tools\Start-WaveLink.ps1'
$WinAudioWaveLinkTaskName = 'win-dotfiles Start-WaveLink'
$WinAudioWaveLinkPackage = 'Elgato.WaveLink_g54w8ztgkx496'
$WinAudioWaveLinkStartupKey = "Registry::HKEY_CURRENT_USER\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\$WinAudioWaveLinkPackage\E31D1357-81DB-467F-8B5B-61BEBA684A0F"
$WinAudioDefaultOutput = 'Music (Elgato Virtual Audio)'
$WinAudioHeadphones = 'WH-1000XM6'
$WinAudioHeadphoneLevel = 100
$WinAudioHeadphoneWarnBelow = 90

function Get-WinAudioEndpoint {
    param([string[]]$ScriptArguments = @())

    $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WinAudioStateScript @ScriptArguments 2>&1
    $exitCode = $LASTEXITCODE
    $json = $output | Where-Object { $_ -is [string] -and $_.StartsWith('[') } | Select-Object -Last 1
    if ($exitCode -ne 0 -or -not $json) {
        throw "Get-AudioState.ps1 failed: $(($output | Out-String).Trim())"
    }
    $json | ConvertFrom-Json
}

function Get-WinWaveLinkState {
    $process = @(Get-Process -Name 'Elgato.WaveLink' -ErrorAction SilentlyContinue)
    $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue |
            Where-Object { $_.Properties[0].Value -eq 'Elgato.WaveLink.exe' })
    $startup = (Get-ItemProperty -LiteralPath $WinAudioWaveLinkStartupKey -ErrorAction SilentlyContinue).State
    $task = Get-ScheduledTask -TaskName $WinAudioWaveLinkTaskName -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        Installed        = [bool](Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Filter $WinAudioWaveLinkPackage -Directory -ErrorAction SilentlyContinue)
        Running          = $process.Count -gt 0
        WindowOpen       = [bool]($process | Where-Object { $_.MainWindowHandle -ne 0 })
        CrashesSinceBoot = @($crashes | Where-Object { $_.TimeCreated -gt $bootTime }).Count
        Crashes30Days    = $crashes.Count
        LastCrash        = ($crashes | Select-Object -First 1).TimeCreated
        # StartupTask states: 2 and 4 start the app at sign-in; 0, 1 and 3 do not.
        SelfStarts       = $startup -in 2, 4
        DelayedTask      = if ($task) { [string]$task.State } else { 'Missing' }
    }
}

function Get-WinAudioResult {
    param(
        $WaveLink = (Get-WinWaveLinkState),
        $Endpoints
    )

    if (-not $PSBoundParameters.ContainsKey('Endpoints')) {
        try {
            $Endpoints = @(Get-WinAudioEndpoint)
        }
        catch {
            New-WinWorkstationCheckResult -Category 'Audio' -Name 'Endpoints' -Status 'Unknown' -Detail $_.Exception.Message
            return
        }
    }

    $default = $Endpoints | Where-Object { $_.DefaultMultimedia } | Select-Object -First 1
    $console = $Endpoints | Where-Object { $_.DefaultConsole } | Select-Object -First 1
    $calls = $Endpoints | Where-Object { $_.DefaultCommunications } | Select-Object -First 1
    $defaultOk = -not $WaveLink.Installed -or ($default.Name -eq $WinAudioDefaultOutput -and $console.Name -eq $WinAudioDefaultOutput)
    New-WinWorkstationCheckResult -Category 'Audio' -Name 'Default output' `
        -Status $(if (-not $defaultOk -or $default.Muted) { 'Warn' } else { 'OK' }) `
        -Detail "default=$($default.Name) $($default.Volume)%$(if ($default.Muted) { ' MUTED' })$(if ($console.Name -ne $default.Name) { "; console=$($console.Name)" })" `
        -Recommendation "Expected $WinAudioDefaultOutput, unmuted. audiofix sets the device; a reconnected HDMI/DP monitor usually takes it."

    $callsOnMonitor = [bool]($calls -and $calls.Name -match 'NVIDIA|AMD High Definition|Intel\(R\) Display')
    New-WinWorkstationCheckResult -Category 'Audio' -Name 'Calls output' -Status $(if ($callsOnMonitor) { 'Warn' } else { 'OK' }) `
        -Detail "communications=$($calls.Name) $($calls.Volume)%" `
        -Recommendation 'A monitor holds the calls output. Pick another device in mmsys.cpl; audiofix leaves this one alone.'

    $headphones = $Endpoints | Where-Object { $_.Name.Contains($WinAudioHeadphones) } | Select-Object -First 1
    New-WinWorkstationCheckResult -Category 'Audio' -Name $WinAudioHeadphones `
        -Status $(if (-not $headphones) { 'Info' } elseif ($headphones.Volume -lt $WinAudioHeadphoneWarnBelow -or $headphones.Muted) { 'Warn' } else { 'OK' }) `
        -Detail $(if ($headphones) { "volume=$($headphones.Volume)%$(if ($headphones.Muted) { ' MUTED' })" } else { 'not connected' }) `
        -Recommendation "audiofix sets it to $WinAudioHeadphoneLevel% when it is below $WinAudioHeadphoneWarnBelow% or muted."

    if (-not $WaveLink.Installed) { return }

    New-WinWorkstationCheckResult -Category 'Audio' -Name 'Wave Link' `
        -Status $(if (-not $WaveLink.Running) { 'Error' } elseif ($WaveLink.CrashesSinceBoot -gt 0 -or -not $WaveLink.WindowOpen) { 'Warn' } else { 'OK' }) `
        -Detail "running=$($WaveLink.Running); window=$($WaveLink.WindowOpen); crashesSinceBoot=$($WaveLink.CrashesSinceBoot); crashes30d=$($WaveLink.Crashes30Days); last=$(if ($WaveLink.LastCrash) { $WaveLink.LastCrash.ToString('MM-dd HH:mm') } else { 'none' })" `
        -Recommendation 'Only system sounds audible? Run audiofix (starts it or opens its window), then audiofix -RestartWaveLink if that is not enough.'

    $taskStarts = $WaveLink.DelayedTask -notin 'Missing', 'Disabled'
    New-WinWorkstationCheckResult -Category 'Audio' -Name 'Wave Link startup' `
        -Status $(if (-not $WaveLink.SelfStarts -and -not $taskStarts) { 'Error' } elseif ($WaveLink.SelfStarts -and $taskStarts) { 'Warn' } else { 'OK' }) `
        -Detail "ownStartup=$($WaveLink.SelfStarts); delayedTask=$($WaveLink.DelayedTask)" `
        -Recommendation 'Exactly one should be on. winsmooth -Apply uses the delayed task and turns Wave Link''s own startup off.'
}

function Test-WinAudio {
    [CmdletBinding()]
    param([switch]$Raw)

    $results = @(Get-WinAudioResult)
    if ($Raw) { return $results }

    $results | Format-Table Name, Status, Detail -AutoSize -Wrap | Out-Host
    $results | Where-Object { $_.Status -in 'Warn', 'Error' } | ForEach-Object {
        Write-Host "$($_.Name): $($_.Recommendation)" -ForegroundColor Yellow
    }
}

function Open-WinWaveLink {
    param([int]$TimeoutSeconds = 30)

    # Activating a running instance reopens its window; Start-WaveLink.ps1 covers a stopped one.
    if (Get-Process -Name 'Elgato.WaveLink' -ErrorAction SilentlyContinue) {
        Start-Process "shell:AppsFolder\$WinAudioWaveLinkPackage!App"
    }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WinAudioStartWaveLinkScript -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Wave Link did not open a window.' }
}

function Repair-WinAudio {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Stops and restarts Wave Link; all audio drops for a few seconds.
        [switch]$RestartWaveLink
    )

    $waveLink = Get-WinWaveLinkState
    if ($waveLink.Installed) {
        if ($RestartWaveLink -and $waveLink.Running) {
            if ($PSCmdlet.ShouldProcess('Wave Link', 'Restart')) {
                $running = @(Get-Process -Name 'Elgato.WaveLink' -ErrorAction SilentlyContinue)
                $running | Stop-Process -Force
                $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
                Open-WinWaveLink
            }
        }
        elseif (-not $waveLink.Running -or -not $waveLink.WindowOpen) {
            if ($PSCmdlet.ShouldProcess('Wave Link', $(if ($waveLink.Running) { 'Open window' } else { 'Start' }))) {
                Open-WinWaveLink
            }
        }
    }

    $endpoints = @(Get-WinAudioEndpoint)
    $headphones = $endpoints | Where-Object { $_.Name.Contains($WinAudioHeadphones) } | Select-Object -First 1
    if ($headphones -and ($headphones.Volume -lt $WinAudioHeadphoneWarnBelow -or $headphones.Muted)) {
        if ($PSCmdlet.ShouldProcess("$($headphones.Name) ($($headphones.Volume)%)", "Set to $WinAudioHeadphoneLevel% and unmute")) {
            [void](Get-WinAudioEndpoint -ScriptArguments '-DeviceMatch', $WinAudioHeadphones, '-SetLevel', "$WinAudioHeadphoneLevel")
        }
    }

    $expected = $endpoints | Where-Object { $_.Name -eq $WinAudioDefaultOutput } | Select-Object -First 1
    if ($expected -and -not ($expected.DefaultConsole -and $expected.DefaultMultimedia)) {
        if ($PSCmdlet.ShouldProcess($WinAudioDefaultOutput, 'Set as default output')) {
            try {
                [void](Get-WinAudioEndpoint -ScriptArguments '-DeviceMatch', $WinAudioDefaultOutput, '-SetDefault')
            }
            catch {
                Write-Warning "$($_.Exception.Message) Set it by hand in the Sound panel."
                Start-Process mmsys.cpl
            }
        }
    }
    elseif ($waveLink.Installed -and -not $expected) {
        Write-Warning "$WinAudioDefaultOutput is not an active endpoint. Is Wave Link running?"
    }

    if (-not $WhatIfPreference) { Test-WinAudio }
}

function Set-WinWorkstationWaveLinkStartup {
    param([Parameter(Mandatory)]$Manifest)

    # Starts Wave Link from a delayed logon task instead of its own startup task. The task must exist
    # before the startup task goes off, or Wave Link never starts. -RestoreLast turns the startup task
    # back on; the logon task then finds Wave Link running and only docks it.
    if (-not (Test-Path -LiteralPath $WinAudioWaveLinkStartupKey)) {
        Write-Host 'Wave Link startup task not found; skipping the delayed start.' -ForegroundColor DarkGray
        return
    }
    & $WinAudioStartWaveLinkScript -Register
    if (-not (Get-ScheduledTask -TaskName $WinAudioWaveLinkTaskName -ErrorAction SilentlyContinue)) {
        throw "Scheduled task '$WinAudioWaveLinkTaskName' was not registered; leaving Wave Link's own startup on."
    }
    # 1 = DisabledByUser, which the app itself cannot switch back on.
    Set-WinWorkstationRegistryValue -Path $WinAudioWaveLinkStartupKey -Name 'State' -Value 1 -Type DWord -Manifest $Manifest
}

Set-Alias -Name audiocheck -Value Test-WinAudio -Force
Set-Alias -Name audiofix -Value Repair-WinAudio -Force
