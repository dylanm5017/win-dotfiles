$WinWorkstationBackupRoot = Join-Path $CacheRoot 'win-dotfiles\workstation-backups'
$WinWorkstationPowerToysRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$WinWorkstationPowerToysSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'settings.json'
$WinWorkstationTerminalSettingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$WinWorkstationKomorebiSourcePath = Join-Path $WinDotfilesRoot 'komorebi\komorebi.json'
$WinWorkstationWhkdSourcePath = Join-Path $WinDotfilesRoot 'komorebi\whkdrc'
$WinWorkstationKomorebiBarSourcePath = Join-Path $WinDotfilesRoot 'komorebi\komorebi.bar.json'
$WinWorkstationKomorebiTargetPath = Join-Path $HOME 'komorebi.json'
$WinWorkstationWhkdTargetPath = Join-Path $HOME '.config\whkdrc'
$WinWorkstationKomorebiBarTargetPath = Join-Path $HOME 'komorebi.bar.json'
$WinWorkstationYasbConfigSourcePath = Join-Path $WinDotfilesRoot 'yasb\config.yaml'
$WinWorkstationYasbStylesSourcePath = Join-Path $WinDotfilesRoot 'yasb\styles.css'
$WinWorkstationYasbConfigTargetPath = Join-Path $HOME '.config\yasb\config.yaml'
$WinWorkstationYasbStylesTargetPath = Join-Path $HOME '.config\yasb\styles.css'
$WinWorkstationWindhawkImportScript = Join-Path $WinDotfilesRoot 'windhawk\Import-Windhawk.ps1'
$WinWorkstationWindhawkStateManifest = Join-Path $WinDotfilesRoot 'windhawk\state\manifest.json'
$WinWorkstationTerminalOverlaySourcePath = Join-Path $WinDotfilesRoot 'terminal\windows-terminal\settings.json'
$WinWorkstationWeztermSourcePath = Join-Path $WinDotfilesRoot 'terminal\wezterm\wezterm.lua'
$WinWorkstationWeztermTargetPath = Join-Path $HOME '.config\wezterm\wezterm.lua'
$WinWorkstationFastfetchSourcePath = Join-Path $WinDotfilesRoot 'fastfetch\config.jsonc'
$WinWorkstationFastfetchTargetPath = Join-Path $HOME '.config\fastfetch\config.jsonc'
$WinWorkstationVSCodeOverlaySourcePath = Join-Path $WinDotfilesRoot 'vscode\settings.json'
$WinWorkstationVSCodeSettingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
$WinWorkstationApplySpicetifyScript = Join-Path $WinDotfilesRoot 'tools\Apply-Spicetify.ps1'
$WinWorkstationApplyFlowLauncherScript = Join-Path $WinDotfilesRoot 'tools\Apply-FlowLauncher.ps1'
$WinWorkstationApplyNileSoftShellScript = Join-Path $WinDotfilesRoot 'tools\Apply-NileSoftShell.ps1'
$WinWorkstationActiveThemePath = Join-Path $WinDotfilesRoot 'themes\active.txt'
$WinWorkstationWallpaperRoot = Join-Path $WinDotfilesRoot 'wallpapers'
$WinWorkstationRunRegistryPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
$WinWorkstationDittoRegistryPath = 'Registry::HKEY_CURRENT_USER\Software\Ditto'
$WinWorkstationQuickLookPath = Join-Path $env:LOCALAPPDATA 'Programs\QuickLook\QuickLook.exe'
$WinWorkstationDittoPath = 'C:\Program Files\Ditto\Ditto.exe'
$WinWorkstationDittoHotKeyValue = 0x0656
$WinWorkstationDittoHotKeyDisplay = 'Ctrl+Alt+V'
$WinWorkstationEarTrumpetAppId = '40459File-New-Project.EarTrumpet_725pr5jq8wr8a!EarTrumpet'

function New-WinWorkstationCheckResult {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Detail,
        [string]$Recommendation
    )

    [PSCustomObject]@{
        Category       = $Category
        Name           = $Name
        Status         = $Status
        Detail         = $Detail
        Recommendation = $Recommendation
    }
}

function Read-WinWorkstationJson {
    param([Parameter(Mandatory)][string]$Path)

    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-WinWorkstationJson {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 80
    )

    # Depth-truncation guard: beyond the depth cap, ConvertTo-Json replaces the nested object with a
    # .ToString() blob (e.g. "@{...}") — structurally valid JSON but semantically broken settings.
    # PowerShell emits a warning when this happens; capturing it detects truncation for any type.
    $json = $InputObject | ConvertTo-Json -Depth $Depth -WarningVariable jsonWarnings -WarningAction SilentlyContinue
    if ($jsonWarnings) {
        throw "Refusing to write ${Path}: ConvertTo-Json truncated at depth $Depth ($($jsonWarnings -join '; ')). Increase -Depth."
    }

    # Re-parse the serialized text to confirm it is valid JSON before it touches the live file.
    $null = $json | ConvertFrom-Json

    # Atomic write: stage a temp file beside the target, then replace, so an interrupted write can
    # never leave the live settings file truncated. Callers back the target up first (manifest).
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $tempPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Set-Content -LiteralPath $tempPath -Value $json -Encoding utf8
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    catch {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Set-WinWorkstationProperty {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )

    if ($InputObject -is [array]) {
        $InputObject = $InputObject | Select-Object -First 1
    }

    if ($InputObject.PSObject.Properties[$Name]) {
        $InputObject.$Name = $Value
    }
    else {
        $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Get-WinWorkstationBackupRoot {
    New-Item -ItemType Directory -Path $WinWorkstationBackupRoot -Force -ErrorAction SilentlyContinue | Out-Null
    $WinWorkstationBackupRoot
}

function New-WinWorkstationBackupManifest {
    $backupRoot = Join-Path (Get-WinWorkstationBackupRoot) (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $backupRoot 'files') -Force | Out-Null

    [PSCustomObject]@{
        CreatedAt      = (Get-Date).ToString('o')
        BackupRoot     = $backupRoot
        Files          = [System.Collections.ArrayList]::new()
        RegistryValues = [System.Collections.ArrayList]::new()
        Attributes     = [System.Collections.ArrayList]::new()
        DefenderExclusions = [System.Collections.ArrayList]::new()
        PowerPlan      = [System.Collections.ArrayList]::new()
    }
}

function Save-WinWorkstationBackupManifest {
    param([Parameter(Mandatory)]$Manifest)

    $manifestPath = Join-Path $Manifest.BackupRoot 'manifest.json'
    $json = $Manifest | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $manifestPath -Value $json -Encoding utf8
}

function Backup-WinWorkstationFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Manifest
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $backupPath = $null

    if ($exists) {
        $safeName = ([IO.Path]::GetFullPath($Path) -replace '[:\\/]', '_').Trim('_')
        $backupPath = Join-Path (Join-Path $Manifest.BackupRoot 'files') $safeName
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    }

    [void]$Manifest.Files.Add([PSCustomObject]@{
            Path       = $Path
            BackupPath = $backupPath
            Existed    = $exists
        })
}

function Backup-WinWorkstationRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Manifest
    )

    $exists = $false
    $value = $null

    if (Test-Path -LiteralPath $Path) {
        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($property -and $property.PSObject.Properties[$Name]) {
            $exists = $true
            $value = $property.$Name
        }
    }

    [void]$Manifest.RegistryValues.Add([PSCustomObject]@{
            Path    = $Path
            Name    = $Name
            Value   = $value
            Existed = $exists
        })
}

function Set-WinWorkstationRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)]$Manifest,
        [ValidateSet('String', 'ExpandString', 'DWord', 'Binary')][string]$Type = 'String'
    )

    Backup-WinWorkstationRegistryValue -Path $Path -Name $Name -Manifest $Manifest
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null
    }
    # Best-effort tuning: a protected/policy-locked or in-use value should degrade to a verbose note,
    # not a raw error. -ErrorAction Stop makes the failure catchable here instead of leaking out.
    try {
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Verbose "Skipped registry value '$Name' under $($Path -replace '^Registry::', '') ($($_.Exception.Message))"
    }
}

function Backup-WinWorkstationAttributes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Manifest
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    [void]$Manifest.Attributes.Add([PSCustomObject]@{
            Path       = $Path
            Existed    = [bool]$item
            Attributes = if ($item) { [string]$item.Attributes } else { $null }
        })
}

function Get-LastWinWorkstationBackupManifestPath {
    $root = Get-WinWorkstationBackupRoot
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'manifest.json' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
}

function Restore-WinWorkstationBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ManifestPath = (Get-LastWinWorkstationBackupManifestPath))

    if (-not $ManifestPath -or -not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Write-Warning 'No workstation backup manifest was found.'
        return
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

    foreach ($file in @($manifest.Files)) {
        if ($file.Existed -and $file.BackupPath -and (Test-Path -LiteralPath $file.BackupPath -PathType Leaf)) {
            $parent = Split-Path -Parent $file.Path
            if ($parent) {
                New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue | Out-Null
            }

            if ($PSCmdlet.ShouldProcess($file.Path, "Restore from $($file.BackupPath)")) {
                Copy-Item -LiteralPath $file.BackupPath -Destination $file.Path -Force
            }
        }
        elseif (-not $file.Existed -and (Test-Path -LiteralPath $file.Path -PathType Leaf)) {
            if ($PSCmdlet.ShouldProcess($file.Path, 'Remove file created by workstation tuning')) {
                Remove-Item -LiteralPath $file.Path -Force
            }
        }
    }

    foreach ($registryValue in @($manifest.RegistryValues)) {
        if ($registryValue.Existed) {
            if ($PSCmdlet.ShouldProcess("$($registryValue.Path)\$($registryValue.Name)", 'Restore registry value')) {
                New-Item -Path $registryValue.Path -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -LiteralPath $registryValue.Path -Name $registryValue.Name -Value $registryValue.Value -ErrorAction Stop
            }
        }
        elseif (Test-Path -LiteralPath $registryValue.Path) {
            if ($PSCmdlet.ShouldProcess("$($registryValue.Path)\$($registryValue.Name)", 'Remove registry value created by workstation tuning')) {
                Remove-ItemProperty -LiteralPath $registryValue.Path -Name $registryValue.Name -ErrorAction SilentlyContinue
            }
        }
    }

    foreach ($attributeEntry in @($manifest.Attributes)) {
        $item = Get-Item -LiteralPath $attributeEntry.Path -Force -ErrorAction SilentlyContinue
        if ($attributeEntry.Existed -and $item -and $attributeEntry.Attributes) {
            if ($PSCmdlet.ShouldProcess($attributeEntry.Path, "Restore attributes $($attributeEntry.Attributes)")) {
                $item.Attributes = [IO.FileAttributes]$attributeEntry.Attributes
            }
        }
    }

    if ($manifest.PSObject.Properties['DefenderExclusions']) {
        foreach ($defenderExclusion in @($manifest.DefenderExclusions | Where-Object { $_ })) {
            if (-not $defenderExclusion.Existed) {
                if ($PSCmdlet.ShouldProcess($defenderExclusion.Path, 'Remove Defender exclusion added by workstation tuning')) {
                    try {
                        Remove-MpPreference -ExclusionPath $defenderExclusion.Path -ErrorAction Stop
                    }
                    catch {
                        Write-Warning "Could not remove Defender exclusion $($defenderExclusion.Path): $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    if ($manifest.PSObject.Properties['PowerPlan']) {
        foreach ($powerPlan in @($manifest.PowerPlan | Where-Object { $_ -and $_.PreviousScheme })) {
            if ($PSCmdlet.ShouldProcess($powerPlan.PreviousScheme, 'Restore previous power scheme')) {
                try {
                    powercfg /setactive $powerPlan.PreviousScheme | Out-Null
                }
                catch {
                    Write-Warning "Could not restore power scheme $($powerPlan.PreviousScheme): $($_.Exception.Message)"
                }
            }
        }
    }

    Write-Host "Restored workstation backup: $ManifestPath" -ForegroundColor Green
}

function Measure-WinWorkstationProfileLoad {
    $profilePath = Join-Path $WinDotfilesRoot 'powershell\profile.ps1'
    $pwsh = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $pwsh -or -not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        return $null
    }

    $escapedProfilePath = $profilePath.Replace("'", "''")
    $command = "`$env:WINDOTFILES_PROFILE_DEBUG='1'; . '$escapedProfilePath'"
    $output = $null
    $processTime = Measure-Command {
        $output = & $pwsh.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command 2>&1
    }

    $scripts = @($output | Where-Object { $_ -match '^Loaded (.+?) in ([\d,]+) ms' } | ForEach-Object {
            [PSCustomObject]@{
                Script = $Matches[1]
                Ms     = [int](($Matches[2]) -replace ',', '')
            }
        })

    [PSCustomObject]@{
        ProcessMs = [math]::Round($processTime.TotalMilliseconds, 0)
        ScriptMs  = [math]::Round(($scripts | Measure-Object -Property Ms -Sum).Sum, 0)
        Scripts   = $scripts
    }
}

function Measure-WinWorkstationCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    try {
        $elapsed = Measure-Command { & $ScriptBlock }
        [PSCustomObject]@{
            Name = $Name
            Ms   = [math]::Round($elapsed.TotalMilliseconds, 0)
        }
    }
    catch {
        [PSCustomObject]@{
            Name = $Name
            Ms   = $null
            Error = $_.Exception.Message
        }
    }
}

function Measure-WinDotfilesActivePrompt {
    if ($global:WinDotfilesPromptMode -ne 'starship' -and (Get-Command Invoke-WinDotfilesNativePrompt -ErrorAction SilentlyContinue)) {
        return Measure-WinWorkstationCommand -Name 'native prompt' -ScriptBlock { Invoke-WinDotfilesNativePrompt -MeasureOnly *> $null }
    }

    if (Get-Command starship -ErrorAction SilentlyContinue) {
        return Measure-WinWorkstationCommand -Name 'starship prompt' -ScriptBlock { starship prompt *> $null }
    }

    $null
}

function Get-WinWorkstationStartupCommands {
    try {
        @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
            Select-Object Name, Command, Location, User |
            Sort-Object Name)
    }
    catch {
        @()
    }
}

function Get-WinWorkstationServiceState {
    $serviceNames = @('WSearch', 'SysMain', 'WinDefend', 'BITS', 'DoSvc', 'wuauserv', 'Tailscale', 'Everything', 'com.docker.service')

    Get-Service -Name $serviceNames -ErrorAction SilentlyContinue |
    Select-Object Name, DisplayName, Status, StartType |
    Sort-Object Name
}

function Get-WinWorkstationScheduledTasks {
    if ($IsCodexShell) {
        return [PSCustomObject]@{
            Skipped = $true
            Reason  = 'Skipped in Codex sandbox; rerun wincheck in a normal PowerShell session.'
        }
    }

    try {
        @(Get-ScheduledTask -ErrorAction Stop |
            Where-Object { $_.State -eq 'Ready' -and $_.TaskPath -notlike '\Microsoft\Windows\*' } |
            Select-Object -First 40 TaskName, TaskPath, State |
            Sort-Object TaskPath, TaskName)
    }
    catch {
        [PSCustomObject]@{
            Error = $_.Exception.Message
        }
    }
}

function Get-WinWorkstationWslSummary {
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return [PSCustomObject]@{
            Status = 'Missing'
            Detail = 'wsl.exe is not on PATH.'
        }
    }

    try {
        $lines = @(& $wsl.Source --list --verbose 2>&1)
        $text = (($lines -join ' ') -replace "`0", '').Trim()
        if ($LASTEXITCODE -eq 0) {
            return [PSCustomObject]@{
                Status = 'Info'
                Detail = $text
            }
        }

        [PSCustomObject]@{
            Status = 'Unknown'
            Detail = $text
        }
    }
    catch {
        [PSCustomObject]@{
            Status = 'Unknown'
            Detail = $_.Exception.Message
        }
    }
}

function Get-WinWorkstationPowerToysSummary {
    if (-not (Test-Path -LiteralPath $WinWorkstationPowerToysSettingsPath -PathType Leaf)) {
        return $null
    }

    try {
        $settings = Read-WinWorkstationJson -Path $WinWorkstationPowerToysSettingsPath
        $runSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\settings.json'
        $runSettings = if (Test-Path -LiteralPath $runSettingsPath -PathType Leaf) {
            Read-WinWorkstationJson -Path $runSettingsPath
        }
        else {
            $null
        }

        $enabled = @($settings.enabled.PSObject.Properties | Where-Object { $_.Value } | ForEach-Object Name | Sort-Object)
        $plugins = if ($runSettings -and $runSettings.PSObject.Properties['plugins']) { @($runSettings.plugins) } else { @() }
        $globalPlugins = @($plugins | Where-Object { -not $_.Disabled -and $_.IsGlobal } | ForEach-Object Name | Sort-Object)
        $everythingPlugin = $plugins | Where-Object { $_.Name -eq 'Everything' } | Select-Object -First 1
        $windowsSearchPlugin = $plugins | Where-Object { $_.Name -eq 'Windows Search' } | Select-Object -First 1
        $folderSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\Settings\Plugins\Microsoft.Plugin.Folder\FolderSettings.json'
        $indexerSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\Settings\Plugins\Microsoft.Plugin.Indexer\IndexerSettings.json'
        $folderSettings = if (Test-Path -LiteralPath $folderSettingsPath -PathType Leaf) { Read-WinWorkstationJson -Path $folderSettingsPath } else { $null }
        $indexerSettings = if (Test-Path -LiteralPath $indexerSettingsPath -PathType Leaf) { Read-WinWorkstationJson -Path $indexerSettingsPath } else { $null }

        $everythingMax = $null
        $everythingPreview = $null
        if ($everythingPlugin) {
            $maxOption = $everythingPlugin.AdditionalOptions | Where-Object { $_.Key -eq 'Max' } | Select-Object -First 1
            $previewOption = $everythingPlugin.AdditionalOptions | Where-Object { $_.Key -eq 'Preview' } | Select-Object -First 1
            if ($maxOption) { $everythingMax = $maxOption.NumberValue }
            if ($previewOption) { $everythingPreview = $previewOption.Value }
        }

        [PSCustomObject]@{
            Version = $settings.powertoys_version
            Startup = $settings.startup
            EnabledCount = $enabled.Count
            Enabled = $enabled
            FancyZonesEnabled = [bool]$settings.enabled.FancyZones
            PowerToysRunEnabled = [bool]$settings.enabled.'PowerToys Run'
            RunMaxResults = if ($runSettings) { $runSettings.properties.maximum_number_of_results } else { $null }
            RunSearchDelay = if ($runSettings) { $runSettings.properties.search_input_delay } else { $null }
            RunWaitForSlowResults = if ($runSettings) { $runSettings.properties.search_wait_for_slow_results } else { $null }
            RunGenerateThumbnails = if ($runSettings) { $runSettings.properties.generate_thumbnails_from_files } else { $null }
            RunClearInputOnLaunch = if ($runSettings) { $runSettings.properties.clear_input_on_launch } else { $null }
            GlobalPlugins = $globalPlugins
            EverythingPluginInstalled = [bool]$everythingPlugin
            EverythingPluginEnabled = [bool]($everythingPlugin -and -not $everythingPlugin.Disabled)
            EverythingPluginGlobal = [bool]($everythingPlugin -and $everythingPlugin.IsGlobal)
            EverythingKeyword = if ($everythingPlugin) { [string]$everythingPlugin.ActionKeyword } else { $null }
            EverythingMax = $everythingMax
            EverythingPreview = $everythingPreview
            WindowsSearchGlobal = [bool]($windowsSearchPlugin -and $windowsSearchPlugin.IsGlobal)
            WindowsSearchKeyword = if ($windowsSearchPlugin) { [string]$windowsSearchPlugin.ActionKeyword } else { $null }
            WindowsSearchMaxCount = if ($indexerSettings) { $indexerSettings.MaxSearchCount } else { $null }
            FolderMaxFolderResults = if ($folderSettings) { $folderSettings.MaxFolderResults } else { $null }
            FolderMaxFileResults = if ($folderSettings) { $folderSettings.MaxFileResults } else { $null }
        }
    }
    catch {
        [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-WinWorkstationTerminalSummary {
    if (-not (Test-Path -LiteralPath $WinWorkstationTerminalSettingsPath -PathType Leaf)) {
        return $null
    }

    try {
        $settings = Read-WinWorkstationJson -Path $WinWorkstationTerminalSettingsPath
        $profiles = @($settings.profiles.list)
        $visible = @($profiles | Where-Object { -not $_.hidden })
        $developerProfiles = @($profiles | Where-Object { $_.name -like 'Developer *' -and -not $_.hidden })

        [PSCustomObject]@{
            DefaultProfile = $settings.defaultProfile
            VisibleProfiles = $visible.Count
            VisibleProfileNames = ($visible.Name -join ', ')
            VisibleDeveloperProfiles = $developerProfiles.Count
        }
    }
    catch {
        [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-WinWorkstationRunValue {
    param([Parameter(Mandatory)][string]$Name)

    $runSettings = Get-ItemProperty -LiteralPath $WinWorkstationRunRegistryPath -ErrorAction SilentlyContinue
    if ($runSettings -and $runSettings.PSObject.Properties[$Name]) {
        return [string]$runSettings.$Name
    }

    $null
}

function Get-WinWorkstationStartApp {
    param([Parameter(Mandatory)][string]$Name)

    try {
        Get-StartApps |
        Where-Object { $_.Name -eq $Name } |
        Select-Object -First 1
    }
    catch {
        $null
    }
}

function Get-WinWorkstationStartupShortcutPath {
    param([Parameter(Mandatory)][string]$Name)

    Join-Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup') "$Name.lnk"
}

function Get-WinWorkstationDittoSettingsSummary {
    $settings = Get-ItemProperty -LiteralPath $WinWorkstationDittoRegistryPath -ErrorAction SilentlyContinue
    if (-not $settings) {
        return $null
    }

    $maxEntries = if ($settings.PSObject.Properties['MaxEntries']) { [int]$settings.MaxEntries } else { $null }
    $expiredEntries = if ($settings.PSObject.Properties['ExpiredEntries']) { [int]$settings.ExpiredEntries } else { $null }
    $checkForMaxEntries = if ($settings.PSObject.Properties['CheckForMaxEntries']) { [bool]$settings.CheckForMaxEntries } else { $null }
    $checkForExpiredEntries = if ($settings.PSObject.Properties['CheckForExpiredEntries']) { [bool]$settings.CheckForExpiredEntries } else { $null }
    $saveMultiPaste = if ($settings.PSObject.Properties['SaveMultiPaste']) { [bool]$settings.SaveMultiPaste } else { $null }
    $maxClipSize = if ($settings.PSObject.Properties['MaxClipSizeInBytes']) { [int]$settings.MaxClipSizeInBytes } else { $null }
    $hotKey = if ($settings.PSObject.Properties['DittoHotKey']) { [int]$settings.DittoHotKey } else { $null }

    [PSCustomObject]@{
        CheckForMaxEntries = $checkForMaxEntries
        MaxEntries = $maxEntries
        CheckForExpiredEntries = $checkForExpiredEntries
        ExpiredEntries = $expiredEntries
        SaveMultiPaste = $saveMultiPaste
        MaxClipSizeInBytes = $maxClipSize
        HotKey = $hotKey
        HotKeyDisplay = if ($hotKey -eq $WinWorkstationDittoHotKeyValue) { $WinWorkstationDittoHotKeyDisplay } elseif ($hotKey) { "custom:$hotKey" } else { 'default' }
        Bounded = (
            $checkForMaxEntries -eq $true -and
            $maxEntries -and $maxEntries -le 300 -and
            $checkForExpiredEntries -eq $true -and
            $expiredEntries -and $expiredEntries -le 14 -and
            $saveMultiPaste -eq $false -and
            $maxClipSize -and $maxClipSize -le 5242880 -and
            $hotKey -eq $WinWorkstationDittoHotKeyValue
        )
    }
}

function Get-WinWorkstationComfortToolsSummary {
    $quickLookStartup = Get-WinWorkstationRunValue -Name 'QuickLook'
    $dittoStartup = Get-WinWorkstationRunValue -Name 'Ditto'
    $earTrumpetShortcut = Get-WinWorkstationStartupShortcutPath -Name 'EarTrumpet'
    $dittoSettings = Get-WinWorkstationDittoSettingsSummary

    @(
        [PSCustomObject]@{
            Name = 'QuickLook'
            Installed = (Test-Path -LiteralPath $WinWorkstationQuickLookPath -PathType Leaf)
            Running = [bool](Get-Process -Name QuickLook -ErrorAction SilentlyContinue)
            Startup = [bool]$quickLookStartup
            Detail = "path=$WinWorkstationQuickLookPath; startup=$quickLookStartup"
            ConfigOK = $true
        }
        [PSCustomObject]@{
            Name = 'EarTrumpet'
            Installed = [bool](Get-WinWorkstationStartApp -Name 'EarTrumpet')
            Running = [bool](Get-Process -Name EarTrumpet -ErrorAction SilentlyContinue)
            Startup = (Test-Path -LiteralPath $earTrumpetShortcut -PathType Leaf)
            Detail = "appId=$WinWorkstationEarTrumpetAppId; startupShortcut=$earTrumpetShortcut"
            ConfigOK = $true
        }
        [PSCustomObject]@{
            Name = 'Ditto'
            Installed = (Test-Path -LiteralPath $WinWorkstationDittoPath -PathType Leaf)
            Running = [bool](Get-Process -Name Ditto -ErrorAction SilentlyContinue)
            Startup = [bool]$dittoStartup
            Detail = if ($dittoSettings) {
                "hotkey=$($dittoSettings.HotKeyDisplay); max=$($dittoSettings.MaxEntries); expireDays=$($dittoSettings.ExpiredEntries); maxClipBytes=$($dittoSettings.MaxClipSizeInBytes); startup=$dittoStartup"
            }
            else {
                "path=$WinWorkstationDittoPath; startup=$dittoStartup"
            }
            ConfigOK = if ($dittoSettings) { [bool]$dittoSettings.Bounded } else { $false }
        }
    )
}

function Get-WinWorkstationDefenderSummary {
    if ($IsCodexShell) {
        return [PSCustomObject]@{
            RealTimeProtectionEnabled = $null
            BehaviorMonitorEnabled    = $null
            ExclusionPath             = @()
            Error                     = 'Skipped in Codex sandbox; rerun wincheck in a normal or elevated PowerShell session.'
        }
    }

    $status = $null
    $preferences = $null
    $errorMessages = @()

    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
    }
    catch {
        $errorMessages += "status: $($_.Exception.Message)"
    }

    try {
        $preferences = Get-MpPreference -ErrorAction Stop
    }
    catch {
        $errorMessages += "preferences: $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        RealTimeProtectionEnabled = if ($status) { $status.RealTimeProtectionEnabled } else { $null }
        BehaviorMonitorEnabled = if ($status) { $status.BehaviorMonitorEnabled } else { $null }
        ExclusionPath = if ($preferences) { @($preferences.ExclusionPath) } else { @() }
        Error = ($errorMessages -join '; ')
    }
}

function Get-WinWorkstationNotIndexedState {
    $paths = @($WorkspaceRoot, $DevRoot, $ProjectsRoot, $ToolsRoot, $CacheRoot) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($path in $paths) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item) {
            [PSCustomObject]@{
                Path = $path
                NotContentIndexed = [bool]($item.Attributes -band [IO.FileAttributes]::NotContentIndexed)
            }
        }
    }
}

function New-WinDotfilesProfilePerfRow {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        $Ms,
        [string]$Detail
    )

    [PSCustomObject]@{
        Category = $Category
        Name     = $Name
        Ms       = $Ms
        Detail   = $Detail
    }
}

function Invoke-WinDotfilesProfilePerf {
    [CmdletBinding()]
    param(
        [switch]$RefreshProjects,
        [switch]$Raw
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $profileTiming = Measure-WinWorkstationProfileLoad

    if ($profileTiming) {
        [void]$rows.Add((New-WinDotfilesProfilePerfRow -Category 'Profile' -Name 'total scripts' -Ms ([int]$profileTiming.ScriptMs) -Detail "process=$($profileTiming.ProcessMs)ms"))
        foreach ($scriptTiming in @($profileTiming.Scripts | Sort-Object Ms -Descending)) {
            [void]$rows.Add((New-WinDotfilesProfilePerfRow -Category 'Profile script' -Name $scriptTiming.Script -Ms ([int]$scriptTiming.Ms)))
        }
    }

    $promptTiming = Measure-WinDotfilesActivePrompt
    if ($promptTiming) {
        [void]$rows.Add((New-WinDotfilesProfilePerfRow -Category 'Prompt' -Name $promptTiming.Name -Ms $promptTiming.Ms -Detail $promptTiming.Error))
    }

    if (Get-Command Get-KnownProjectDirectories -ErrorAction SilentlyContinue) {
        $projectDirectories = @()
        $cachedTiming = Measure-Command { $projectDirectories = @(Get-KnownProjectDirectories) }
        $projectCount = $projectDirectories.Count
        $cacheState = if (Get-Command Get-KnownProjectDirectoryCacheState -ErrorAction SilentlyContinue) {
            Get-KnownProjectDirectoryCacheState
        }
        else {
            $null
        }

        $cacheDetail = if ($cacheState) {
            "projects=$projectCount fresh=$($cacheState.Fresh) age=$($cacheState.AgeMinutes)m"
        }
        else {
            "projects=$projectCount"
        }
        [void]$rows.Add((New-WinDotfilesProfilePerfRow -Category 'Projects' -Name 'cached lookup' -Ms ([int][math]::Round($cachedTiming.TotalMilliseconds, 0)) -Detail $cacheDetail))

        if ($RefreshProjects) {
            $refreshDirectories = @()
            $refreshTiming = Measure-Command { $refreshDirectories = @(Get-KnownProjectDirectories -Refresh) }
            [void]$rows.Add((New-WinDotfilesProfilePerfRow -Category 'Projects' -Name 'refresh scan' -Ms ([int][math]::Round($refreshTiming.TotalMilliseconds, 0)) -Detail "projects=$($refreshDirectories.Count)"))
        }
    }

    if ($Raw) {
        return $rows
    }

    $rows |
    Sort-Object Category, @{ Expression = 'Ms'; Descending = $true }, Name |
    Format-Table Category, Name, Ms, Detail -AutoSize
}

function Invoke-WinWorkstationCheck {
    [CmdletBinding()]
    param(
        [switch]$Detailed,
        [switch]$Raw
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $profileTiming = Measure-WinWorkstationProfileLoad
    if ($profileTiming) {
        $status = if ($profileTiming.ScriptMs -le 350) { 'OK' } elseif ($profileTiming.ScriptMs -le 750) { 'Warn' } else { 'Slow' }
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Shell' -Name 'PowerShell profile load' -Status $status -Detail "scripts=$($profileTiming.ScriptMs)ms process=$($profileTiming.ProcessMs)ms" -Recommendation 'Use WINDOTFILES_PROFILE_DEBUG=1 for per-script detail.'))

        if ($Detailed) {
            foreach ($scriptTiming in @($profileTiming.Scripts | Sort-Object Ms -Descending | Select-Object -First 8)) {
                [void]$results.Add((New-WinWorkstationCheckResult -Category 'Shell timing' -Name $scriptTiming.Script -Status 'Info' -Detail "$($scriptTiming.Ms)ms"))
            }
        }
    }

    $promptTiming = Measure-WinDotfilesActivePrompt
    if ($promptTiming) {
        $status = if ($promptTiming.Ms -and $promptTiming.Ms -le 50) { 'OK' } elseif ($promptTiming.Ms -and $promptTiming.Ms -le 100) { 'Warn' } elseif ($promptTiming.Ms) { 'Slow' } else { 'Error' }
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Shell' -Name $promptTiming.Name -Status $status -Detail "$(if ($promptTiming.Ms) { "$($promptTiming.Ms)ms" } else { $promptTiming.Error })"))
    }

    if (Get-Command Get-KnownProjectDirectories -ErrorAction SilentlyContinue) {
        $projectDirectories = @()
        $projectTiming = Measure-Command { $projectDirectories = @(Get-KnownProjectDirectories) }
        $projectMs = [math]::Round($projectTiming.TotalMilliseconds, 0)
        $projectCount = $projectDirectories.Count
        $projectStatus = if ($projectMs -le 50) { 'OK' } elseif ($projectMs -le 200) { 'Warn' } else { 'Slow' }
        $cacheState = if (Get-Command Get-KnownProjectDirectoryCacheState -ErrorAction SilentlyContinue) {
            Get-KnownProjectDirectoryCacheState
        }
        else {
            $null
        }
        $cacheDetail = if ($cacheState) { "; cacheFresh=$($cacheState.Fresh); age=$($cacheState.AgeMinutes)m" } else { '' }
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Shell' -Name 'Project cache lookup' -Status $projectStatus -Detail "projects=$projectCount time=$($projectMs)ms$cacheDetail" -Recommendation 'Use projcache -Refresh after adding or moving project roots.'))

        if ($Detailed) {
            $refreshDirectories = @()
            $refreshTiming = Measure-Command { $refreshDirectories = @(Get-KnownProjectDirectories -Refresh) }
            $refreshMs = [math]::Round($refreshTiming.TotalMilliseconds, 0)
            [void]$results.Add((New-WinWorkstationCheckResult -Category 'Shell timing' -Name 'Project refresh scan' -Status 'Info' -Detail "projects=$($refreshDirectories.Count) time=$($refreshMs)ms"))
        }
    }

    $startupCommands = @(Get-WinWorkstationStartupCommands)
    if ($startupCommands) {
        $noisyStartup = @($startupCommands | Where-Object { $_.Name -match 'Spotify|Steam|MicrosoftEdgeAutoLaunch|Send to OneNote|Teams|Slack' })
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Startup' -Name 'Startup apps' -Status $(if ($noisyStartup) { 'Warn' } else { 'OK' }) -Detail "total=$($startupCommands.Count); noisy=$($noisyStartup.Name -join ', ')" -Recommendation 'winsmooth -Apply trims the balanced startup set.'))
    }
    else {
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Startup' -Name 'Startup apps' -Status 'Unknown' -Detail 'Win32_StartupCommand was unavailable.'))
    }

    $scheduledTasks = @(Get-WinWorkstationScheduledTasks)
    if ($scheduledTasks.Count -eq 1 -and $scheduledTasks[0].Skipped) {
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Startup' -Name 'Scheduled tasks' -Status 'Skipped' -Detail $scheduledTasks[0].Reason))
    }
    elseif ($scheduledTasks.Count -eq 1 -and $scheduledTasks[0].Error) {
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Startup' -Name 'Scheduled tasks' -Status 'Unknown' -Detail $scheduledTasks[0].Error))
    }
    else {
        $notableTasks = @($scheduledTasks | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Startup' -Name 'Non-Microsoft scheduled tasks' -Status $(if ($scheduledTasks.Count -gt 15) { 'Warn' } else { 'OK' }) -Detail "ready=$($scheduledTasks.Count); root-or-vendor=$($notableTasks.Count)" -Recommendation 'Review updater/background tasks if Windows still feels noisy.'))
        if ($Detailed) {
            foreach ($task in @($scheduledTasks | Select-Object -First 12)) {
                [void]$results.Add((New-WinWorkstationCheckResult -Category 'Scheduled tasks' -Name $task.TaskName -Status ([string]$task.State) -Detail $task.TaskPath))
            }
        }
    }

    $services = @(Get-WinWorkstationServiceState)
    foreach ($service in $services) {
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Services' -Name $service.Name -Status ([string]$service.Status) -Detail "$($service.DisplayName); start=$($service.StartType)"))
    }

    $wslSummary = Get-WinWorkstationWslSummary
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'WSL/Docker' -Name 'WSL distros' -Status $wslSummary.Status -Detail $wslSummary.Detail -Recommendation 'Keep Docker/WSL running only when they are part of the current work block.'))

    $defender = Get-WinWorkstationDefenderSummary
    $defenderStatus = if ($defender.RealTimeProtectionEnabled) { 'OK' } elseif ($defender.Error) { 'Unknown' } else { 'Warn' }
    $workspaceExcluded = @($defender.ExclusionPath | Where-Object { $_ -and ([IO.Path]::GetFullPath($_).TrimEnd('\') -ieq [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')) })
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'Defender' -Name 'Real-time protection' -Status $defenderStatus -Detail "enabled=$($defender.RealTimeProtectionEnabled); exclusions=$(@($defender.ExclusionPath).Count); errors=$($defender.Error)" -Recommendation $(if (-not $workspaceExcluded) { 'Run winsmooth -Apply from an elevated shell to add dev path exclusions.' } else { 'Workspace exclusion present.' })))

    foreach ($indexedState in @(Get-WinWorkstationNotIndexedState)) {
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Search' -Name $indexedState.Path -Status $(if ($indexedState.NotContentIndexed) { 'OK' } else { 'Warn' }) -Detail "NotContentIndexed=$($indexedState.NotContentIndexed)" -Recommendation 'winsmooth marks top-level dev roots as not content indexed.'))
    }

    $powerToys = Get-WinWorkstationPowerToysSummary
    if ($powerToys) {
        if ($powerToys.Error) {
            [void]$results.Add((New-WinWorkstationCheckResult -Category 'PowerToys' -Name 'Settings' -Status 'Error' -Detail $powerToys.Error))
        }
        else {
            $status = if ($powerToys.FancyZonesEnabled) { 'Warn' } else { 'OK' }
            [void]$results.Add((New-WinWorkstationCheckResult -Category 'PowerToys' -Name 'Enabled modules' -Status $status -Detail "count=$($powerToys.EnabledCount); FancyZones=$($powerToys.FancyZonesEnabled); Run=$($powerToys.PowerToysRunEnabled)" -Recommendation 'Use komorebi as the tiling owner and keep PowerToys focused.'))
            $launcherStatus = if (
                $powerToys.PowerToysRunEnabled -and
                $powerToys.EverythingPluginEnabled -and
                $powerToys.EverythingPluginGlobal -and
                $powerToys.RunMaxResults -le 6 -and
                $powerToys.RunSearchDelay -le 120 -and
                $powerToys.RunWaitForSlowResults -eq $false -and
                $powerToys.RunGenerateThumbnails -eq $false -and
                $powerToys.WindowsSearchMaxCount -le 8 -and
                $powerToys.FolderMaxFileResults -le 8
            ) { 'OK' } else { 'Warn' }
            $launcherDetail = "maxResults=$($powerToys.RunMaxResults); delay=$($powerToys.RunSearchDelay)ms; waitSlow=$($powerToys.RunWaitForSlowResults); thumbnails=$($powerToys.RunGenerateThumbnails); clearOnOpen=$($powerToys.RunClearInputOnLaunch); Everything=enabled:$($powerToys.EverythingPluginEnabled)/global:$($powerToys.EverythingPluginGlobal)/keyword:$($powerToys.EverythingKeyword)/max:$($powerToys.EverythingMax)/preview:$($powerToys.EverythingPreview); WindowsSearchMax=$($powerToys.WindowsSearchMaxCount); FolderMax=$($powerToys.FolderMaxFolderResults)/$($powerToys.FolderMaxFileResults)"
            [void]$results.Add((New-WinWorkstationCheckResult -Category 'Launcher' -Name 'PowerToys Run profile' -Status $launcherStatus -Detail $launcherDetail -Recommendation 'winsmooth -Apply keeps PowerToys Run fast, makes Everything the primary file path, and limits duplicate Windows Search/folder noise.'))
            if ($Detailed) {
                [void]$results.Add((New-WinWorkstationCheckResult -Category 'PowerToys' -Name 'Enabled module names' -Status 'Info' -Detail ($powerToys.Enabled -join ', ')))
                [void]$results.Add((New-WinWorkstationCheckResult -Category 'Launcher' -Name 'Global plugin names' -Status 'Info' -Detail ($powerToys.GlobalPlugins -join ', ')))
            }
        }
    }

    foreach ($tool in @(Get-WinWorkstationComfortToolsSummary)) {
        $toolStatus = if (-not $tool.Installed) {
            'Missing'
        }
        elseif (-not $tool.Running -or -not $tool.Startup -or -not $tool.ConfigOK) {
            'Warn'
        }
        else {
            'OK'
        }

        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Comfort tools' -Name $tool.Name -Status $toolStatus -Detail "installed=$($tool.Installed); running=$($tool.Running); startup=$($tool.Startup); configOK=$($tool.ConfigOK); $($tool.Detail)" -Recommendation 'winsmooth -Apply starts and wires the low-friction desktop tools.'))
    }

    $terminal = Get-WinWorkstationTerminalSummary
    if ($terminal) {
        if ($terminal.Error) {
            [void]$results.Add((New-WinWorkstationCheckResult -Category 'Terminal' -Name 'Settings' -Status 'Error' -Detail $terminal.Error))
        }
        else {
            $status = if ($terminal.VisibleDeveloperProfiles -gt 0 -or $terminal.VisibleProfiles -gt 6) { 'Warn' } else { 'OK' }
            [void]$results.Add((New-WinWorkstationCheckResult -Category 'Terminal' -Name 'Visible profiles' -Status $status -Detail "visible=$($terminal.VisibleProfiles); developer=$($terminal.VisibleDeveloperProfiles); $($terminal.VisibleProfileNames)" -Recommendation 'winsmooth hides duplicate Visual Studio/Azure/docker profiles.'))
        }
    }

    $komorebi = Get-Command komorebic -ErrorAction SilentlyContinue
    $komorebiProcesses = @(Get-Process -Name komorebi, whkd -ErrorAction SilentlyContinue)
    $komorebiStatus = if ($komorebiProcesses.ProcessName -contains 'komorebi' -and $komorebiProcesses.ProcessName -contains 'whkd') { 'OK' } elseif ($komorebi) { 'Warn' } else { 'Missing' }
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'Window manager' -Name 'komorebi/whkd' -Status $komorebiStatus -Detail "komorebic=$(if ($komorebi) { $komorebi.Source } else { 'not found' }); running=$($komorebiProcesses.ProcessName -join ', ')" -Recommendation 'Run winsmooth -Apply to link configs/autostart, then wmstart.'))

    $yasb = Get-Command yasbc -ErrorAction SilentlyContinue
    $yasbRunning = [bool](Get-Process -Name yasb -ErrorAction SilentlyContinue)
    $yasbStatus = if ($yasbRunning) { 'OK' } elseif ($yasb) { 'Warn' } else { 'Missing' }
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'Status bar' -Name 'Yasb' -Status $yasbStatus -Detail "yasbc=$(if ($yasb) { $yasb.Source } else { 'not found' }); running=$yasbRunning" -Recommendation 'Install AmN.yasb (winget), then winsmooth -Apply links config + enables autostart; control with yasbc start/stop/reload.'))

    $windhawk = Get-Command windhawk -ErrorAction SilentlyContinue
    $windhawkInstalled = $windhawk -or (Test-Path -LiteralPath (Join-Path $env:ProgramData 'Windhawk'))
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'Customization' -Name 'Windhawk' -Status $(if ($windhawkInstalled) { 'OK' } else { 'Missing' }) -Detail "installed=$([bool]$windhawkInstalled)" -Recommendation 'Install RamenSoftware.Windhawk (winget); enable mods from windhawk/mods.md, capture them with windhawk\Export-Windhawk.ps1, and winsmooth -Apply restores windhawk/state.'))

    $responsiveness = Get-WinWorkstationResponsivenessSummary
    $responsivenessStatus = if ($responsiveness.AnimationsOff -and $responsiveness.PointerAccelOff -and $responsiveness.KeyRepeatMaxed -and $responsiveness.FastPower) { 'OK' } else { 'Warn' }
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'Responsiveness' -Name 'Input + animations + power' -Status $responsivenessStatus -Detail "menuDelay=$($responsiveness.MenuShowDelay); animationsOff=$($responsiveness.AnimationsOff); pointerAccelOff=$($responsiveness.PointerAccelOff); keyRepeat=$($responsiveness.KeyboardDelay)/$($responsiveness.KeyboardSpeed); power=$($responsiveness.PowerScheme)" -Recommendation 'winsmooth -Apply kills animations, sets raw pointer + fast key repeat, and activates a high-performance power plan.'))

    $shellDefaults = Get-WinWorkstationShellDefaultsSummary
    $shellDefaultsStatus = if ($shellDefaults.ExtensionsShown -and $shellDefaults.DarkMode -and $shellDefaults.TaskbarDecluttered -and $shellDefaults.LongPaths) { 'OK' } else { 'Warn' }
    [void]$results.Add((New-WinWorkstationCheckResult -Category 'Desktop' -Name 'Shell defaults + status bar' -Status $shellDefaultsStatus -Detail "extensionsShown=$($shellDefaults.ExtensionsShown); darkMode=$($shellDefaults.DarkMode); taskbarClean=$($shellDefaults.TaskbarDecluttered); longPaths=$($shellDefaults.LongPaths); yasbBar=$($shellDefaults.BarRunning); theme=$($shellDefaults.ActiveTheme); themedWallpaper=$($shellDefaults.ThemedWallpaper); accentTitlebars=$($shellDefaults.AccentOnTitlebars)" -Recommendation 'winsmooth -Apply declutters Windows shell defaults, links + starts the Yasb status bar, and applies the active theme; switch themes with "theme <name>".'))

    $topMemory = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 ProcessName, Id, WorkingSet64, CPU)
    foreach ($process in $topMemory) {
        [void]$results.Add((New-WinWorkstationCheckResult -Category 'Processes memory' -Name "$($process.ProcessName) [$($process.Id)]" -Status 'Info' -Detail ("{0:n0} MB; CPU={1:n1}" -f ($process.WorkingSet64 / 1MB), $process.CPU)))
    }

    if ($Raw) {
        return $results
    }

    $results |
    Sort-Object Category, Name |
    Format-Table Category, Name, Status, Detail, Recommendation -AutoSize
}

function Set-WinWorkstationPowerToysSettings {
    param([Parameter(Mandatory)]$Manifest)

    if (-not (Test-Path -LiteralPath $WinWorkstationPowerToysSettingsPath -PathType Leaf)) {
        Write-Warning "PowerToys settings not found: $WinWorkstationPowerToysSettingsPath"
        return
    }

    Backup-WinWorkstationFile -Path $WinWorkstationPowerToysSettingsPath -Manifest $Manifest
    $settings = Read-WinWorkstationJson -Path $WinWorkstationPowerToysSettingsPath

    # PowerToys Run is intentionally disabled: Flow Launcher is the launcher now (Win+Space),
    # themed in lock-step by the `theme` command. The PT Run settings block further down stays
    # (harmless for a disabled module) so it's still tuned if you ever re-enable it.
    $enabledModules = @('AlwaysOnTop', 'ColorPicker', 'EnvironmentVariables', 'File Locksmith', 'Hosts', 'Keyboard Manager', 'PowerRename', 'TextExtractor')
    $disabledModules = @('AdvancedPaste', 'Awake', 'CropAndLock', 'FancyZones', 'File Explorer', 'FindMyMouse', 'Image Resizer', 'LightSwitch', 'Measure Tool', 'MouseHighlighter', 'MousePointerCrosshairs', 'MouseWithoutBorders', 'Peek', 'PowerToys Run', 'Shortcut Guide', 'Workspaces', 'ZoomIt')

    foreach ($moduleName in $enabledModules) {
        if ($settings.enabled.PSObject.Properties[$moduleName]) {
            $settings.enabled.$moduleName = $true
        }
    }

    foreach ($moduleName in $disabledModules) {
        if ($settings.enabled.PSObject.Properties[$moduleName]) {
            $settings.enabled.$moduleName = $false
        }
    }

    foreach ($plugin in @($settings.plugins)) {
        switch ($plugin.Name) {
            'Everything' {
                $plugin.Disabled = $false
                $plugin.IsGlobal = $true
            }
            'Windows Search' {
                $plugin.Disabled = $false
                $plugin.IsGlobal = $false
                $plugin.ActionKeyword = '?'
            }
        }
    }

    Write-WinWorkstationJson -InputObject $settings -Path $WinWorkstationPowerToysSettingsPath

    $fancyZonesSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'FancyZones\settings.json'
    if (Test-Path -LiteralPath $fancyZonesSettingsPath -PathType Leaf) {
        Backup-WinWorkstationFile -Path $fancyZonesSettingsPath -Manifest $Manifest
        $fancyZonesSettings = Read-WinWorkstationJson -Path $fancyZonesSettingsPath
        if ($fancyZonesSettings.properties.fancyzones_overrideSnapHotkeys) {
            $fancyZonesSettings.properties.fancyzones_overrideSnapHotkeys.value = $false
        }
        Write-WinWorkstationJson -InputObject $fancyZonesSettings -Path $fancyZonesSettingsPath
    }

    $runSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\settings.json'
    if (Test-Path -LiteralPath $runSettingsPath -PathType Leaf) {
        Backup-WinWorkstationFile -Path $runSettingsPath -Manifest $Manifest
        $runSettings = Read-WinWorkstationJson -Path $runSettingsPath
        # PowerToys Run activation: Win+Space (code 32 = Space). Win+Space is also Windows' default
        # input-language switch; PowerToys Run overrides it while focused.
        $winSpace = [PSCustomObject]@{ win = $true; ctrl = $false; alt = $false; shift = $false; code = 32; key = '' }
        $runSettings.properties.open_powerlauncher = $winSpace
        $runSettings.properties.DefaultOpenPowerLauncher = $winSpace
        $runSettings.properties.maximum_number_of_results = 6
        $runSettings.properties.search_input_delay = 100
        $runSettings.properties.search_wait_for_slow_results = $false
        $runSettings.properties.generate_thumbnails_from_files = $false
        $runSettings.properties.clear_input_on_launch = $true

        $everythingPlugin = $runSettings.plugins | Where-Object { $_.Name -eq 'Everything' } | Select-Object -First 1
        if ($everythingPlugin) {
            foreach ($option in @($everythingPlugin.AdditionalOptions)) {
                switch ($option.Key) {
                    'Max' { $option.NumberValue = 8 }
                    'Preview' { $option.Value = $false }
                    'ShowMore' { $option.Value = $true }
                    'Updates' { $option.Value = $false }
                }
            }
        }

        Write-WinWorkstationJson -InputObject $runSettings -Path $runSettingsPath
    }

    $folderSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\Settings\Plugins\Microsoft.Plugin.Folder\FolderSettings.json'
    if (Test-Path -LiteralPath $folderSettingsPath -PathType Leaf) {
        Backup-WinWorkstationFile -Path $folderSettingsPath -Manifest $Manifest
        $folderSettings = Read-WinWorkstationJson -Path $folderSettingsPath
        $folderSettings.MaxFolderResults = 8
        $folderSettings.MaxFileResults = 5
        Write-WinWorkstationJson -InputObject $folderSettings -Path $folderSettingsPath
    }

    $indexerSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\Settings\Plugins\Microsoft.Plugin.Indexer\IndexerSettings.json'
    if (Test-Path -LiteralPath $indexerSettingsPath -PathType Leaf) {
        Backup-WinWorkstationFile -Path $indexerSettingsPath -Manifest $Manifest
        $indexerSettings = Read-WinWorkstationJson -Path $indexerSettingsPath
        $indexerSettings.MaxSearchCount = 6
        $indexerSettings.UseLocationAsWorkingDir = $false
        Write-WinWorkstationJson -InputObject $indexerSettings -Path $indexerSettingsPath
    }

    $runUserSettingsPath = Join-Path $WinWorkstationPowerToysRoot 'PowerToys Run\Settings\PowerToysRunSettings.json'
    if (Test-Path -LiteralPath $runUserSettingsPath -PathType Leaf) {
        Backup-WinWorkstationFile -Path $runUserSettingsPath -Manifest $Manifest
        $runUserSettings = Read-WinWorkstationJson -Path $runUserSettingsPath
        $runUserSettings.Hotkey = 'Win + Space'
        $runUserSettings.MaxResultsToShow = 6
        $runUserSettings.SearchInputDelay = 100
        $runUserSettings.SearchWaitForSlowResults = $false
        $runUserSettings.GenerateThumbnailsFromFiles = $false
        $runUserSettings.ClearInputOnLaunch = $true
        Write-WinWorkstationJson -InputObject $runUserSettings -Path $runUserSettingsPath
    }
}

function Set-WinWorkstationTerminalSettings {
    param([Parameter(Mandatory)]$Manifest)

    if (-not (Test-Path -LiteralPath $WinWorkstationTerminalSettingsPath -PathType Leaf)) {
        Write-Warning "Windows Terminal settings not found: $WinWorkstationTerminalSettingsPath"
        return
    }

    Backup-WinWorkstationFile -Path $WinWorkstationTerminalSettingsPath -Manifest $Manifest
    $settings = Read-WinWorkstationJson -Path $WinWorkstationTerminalSettingsPath
    $keepVisibleNames = @('PowerShell', 'Git', 'Command Prompt')

    foreach ($profile in @($settings.profiles.list)) {
        $name = [string]$profile.name
        $source = [string]$profile.source
        $isVisibleUbuntu = $name -eq 'Ubuntu' -and ($source -like 'CanonicalGroupLimited*' -or $source -eq 'Windows.Terminal.Wsl')
        $shouldHide = $name -like 'Developer *' -or $name -eq 'Azure Cloud Shell' -or $name -eq 'docker-desktop' -or $source -eq 'Windows.Terminal.Azure' -or $source -eq 'VSDebugConsole'

        if ($keepVisibleNames -contains $name -or $isVisibleUbuntu) {
            Set-WinWorkstationProperty -InputObject $profile -Name hidden -Value $false
        }
        elseif ($shouldHide) {
            Set-WinWorkstationProperty -InputObject $profile -Name hidden -Value $true
        }

        $isDefaultPowerShell = $profile.guid -eq $settings.defaultProfile -or $source -eq 'Windows.Terminal.PowershellCore'
        $isWindowsShell = $isDefaultPowerShell -or $name -eq 'Command Prompt' -or $name -eq 'Git'
        if ($isWindowsShell) {
            Set-WinWorkstationProperty -InputObject $profile -Name startingDirectory -Value $WorkspaceRoot
        }
    }

    # Styling (schemes, profile defaults, app settings, pane keybindings) is sourced from the
    # committed overlay so the terminal look is version-controlled and portable. The live
    # settings.json keeps its machine-specific profiles/GUIDs; only the overlay's keys are merged.
    Merge-WinWorkstationTerminalOverlay -Settings $settings

    Write-WinWorkstationJson -InputObject $settings -Path $WinWorkstationTerminalSettingsPath
}

function Set-WinWorkstationWeztermSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Link the repo WezTerm config to ~/.config/wezterm so it can be tried alongside Windows
    # Terminal. WezTerm is optional; this is a no-op warning when the repo file is absent.
    Set-WinWorkstationManagedConfigFile -Source $WinWorkstationWeztermSourcePath -Destination $WinWorkstationWeztermTargetPath -Manifest $Manifest
}

function Merge-WinWorkstationTerminalOverlay {
    param([Parameter(Mandatory)]$Settings)

    if (-not (Test-Path -LiteralPath $WinWorkstationTerminalOverlaySourcePath -PathType Leaf)) {
        Write-Warning "Terminal overlay not found: $WinWorkstationTerminalOverlaySourcePath"
        return
    }

    $overlay = Read-WinWorkstationJson -Path $WinWorkstationTerminalOverlaySourcePath

    # Top-level scalar app settings (everything except the structured sections handled below).
    $structuredKeys = @('schemes', 'profiles', 'actions', 'keybindings')
    foreach ($property in $overlay.PSObject.Properties) {
        if ($property.Name -like '_*' -or $structuredKeys -contains $property.Name) {
            continue
        }
        Set-WinWorkstationProperty -InputObject $Settings -Name $property.Name -Value $property.Value
    }

    # Schemes: replace each overlay scheme by name, leaving the user's other schemes intact.
    if ($overlay.PSObject.Properties['schemes']) {
        if (-not $Settings.PSObject.Properties['schemes']) {
            Set-WinWorkstationProperty -InputObject $Settings -Name schemes -Value @()
        }
        $overlayNames = @($overlay.schemes | ForEach-Object { $_.name })
        $kept = @($Settings.schemes | Where-Object { $overlayNames -notcontains $_.name })
        $Settings.schemes = @($kept + @($overlay.schemes))
    }

    # Profile defaults: merge keys. Font is special-cased so a missing Nerd Font leaves the
    # terminal font untouched (matching prior behaviour) instead of pointing at a missing face.
    if ($overlay.PSObject.Properties['profiles'] -and $overlay.profiles.PSObject.Properties['defaults']) {
        if (-not $Settings.profiles.PSObject.Properties['defaults']) {
            Set-WinWorkstationProperty -InputObject $Settings.profiles -Name defaults -Value ([PSCustomObject]@{})
        }
        $defaults = $Settings.profiles.defaults
        foreach ($property in $overlay.profiles.defaults.PSObject.Properties) {
            if ($property.Name -eq 'font') {
                $face = [string]$property.Value.face
                if ($face -and -not (Test-WinWorkstationFontInstalled -Name $face)) {
                    Write-Warning "$face not installed; left Terminal font unchanged. Install a Nerd Font (e.g. scoop install CascadiaCode-NF) for glyphs."
                    continue
                }
            }
            Set-WinWorkstationProperty -InputObject $defaults -Name $property.Name -Value $property.Value
        }
    }

    # Actions/keybindings: union by key chord so existing user bindings are preserved.
    $overlayActions = @()
    if ($overlay.PSObject.Properties['actions']) { $overlayActions = @($overlay.actions) }
    elseif ($overlay.PSObject.Properties['keybindings']) { $overlayActions = @($overlay.keybindings) }

    if ($overlayActions.Count -gt 0) {
        if (-not $Settings.PSObject.Properties['actions']) {
            Set-WinWorkstationProperty -InputObject $Settings -Name actions -Value @()
        }
        $overlayKeys = @($overlayActions | ForEach-Object { $_.keys } | Where-Object { $_ })
        $kept = @($Settings.actions | Where-Object { $overlayKeys -notcontains $_.keys })
        $Settings.actions = @($kept + $overlayActions)
    }
}

function Test-WinWorkstationFontInstalled {
    param([Parameter(Mandatory)][string]$Name)

    $fontKeys = @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    )

    foreach ($fontKey in $fontKeys) {
        $properties = Get-ItemProperty -LiteralPath $fontKey -ErrorAction SilentlyContinue
        if (-not $properties) { continue }
        $match = $properties.PSObject.Properties | Where-Object { $_.Name -like "$Name*" }
        if ($match) { return $true }
    }

    $false
}

function New-WinWorkstationStartupShortcut {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$Arguments,
        [Parameter(Mandatory)]$Manifest
    )

    $startupShortcutPath = Get-WinWorkstationStartupShortcutPath -Name $Name
    Backup-WinWorkstationFile -Path $startupShortcutPath -Manifest $Manifest
    New-Item -ItemType Directory -Path (Split-Path -Parent $startupShortcutPath) -Force | Out-Null

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupShortcutPath)
        $shortcut.TargetPath = $TargetPath
        if ($Arguments) {
            $shortcut.Arguments = $Arguments
        }
        $shortcut.WorkingDirectory = $HOME
        $shortcut.WindowStyle = 7
        $shortcut.Save()
        Write-Host "Created startup shortcut: $startupShortcutPath" -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Could not create startup shortcut $startupShortcutPath`: $($_.Exception.Message)"
    }
}

function Set-WinWorkstationComfortToolsSettings {
    param([Parameter(Mandatory)]$Manifest)

    if (Test-Path -LiteralPath $WinWorkstationQuickLookPath -PathType Leaf) {
        Set-WinWorkstationRegistryValue -Path $WinWorkstationRunRegistryPath -Name 'QuickLook' -Value "`"$WinWorkstationQuickLookPath`"" -Manifest $Manifest
    }
    else {
        Write-Warning "QuickLook is not installed at $WinWorkstationQuickLookPath"
    }

    if (Test-Path -LiteralPath $WinWorkstationDittoPath -PathType Leaf) {
        Set-WinWorkstationRegistryValue -Path $WinWorkstationRunRegistryPath -Name 'Ditto' -Value "`"$WinWorkstationDittoPath`"" -Manifest $Manifest

        $dittoDwordSettings = @{
            CheckForMaxEntries = 1
            MaxEntries = 300
            CheckForExpiredEntries = 1
            ExpiredEntries = 14
            SaveMultiPaste = 0
            MaxClipSizeInBytes = 5242880
            MaxFileContentsSize = 16777216
            PromptWhenDeletingClips = 1
            EnsureConnected2 = 1
            ShowStartupMessage = 0
            DittoHotKey = $WinWorkstationDittoHotKeyValue
        }

        foreach ($setting in $dittoDwordSettings.GetEnumerator()) {
            Set-WinWorkstationRegistryValue -Path $WinWorkstationDittoRegistryPath -Name $setting.Key -Value ([int]$setting.Value) -Manifest $Manifest -Type DWord
        }
    }
    else {
        Write-Warning "Ditto is not installed at $WinWorkstationDittoPath"
    }

    if (Get-WinWorkstationStartApp -Name 'EarTrumpet') {
        $explorerPath = Join-Path $env:WINDIR 'explorer.exe'
        New-WinWorkstationStartupShortcut -Name 'EarTrumpet' -TargetPath $explorerPath -Arguments "shell:AppsFolder\$WinWorkstationEarTrumpetAppId" -Manifest $Manifest
    }
    else {
        Write-Warning 'EarTrumpet is not registered as a Start app.'
    }
}

function Start-WinWorkstationComfortTools {
    if ((Test-Path -LiteralPath $WinWorkstationQuickLookPath -PathType Leaf) -and -not (Get-Process -Name QuickLook -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $WinWorkstationQuickLookPath -WindowStyle Hidden
    }

    if ((Test-Path -LiteralPath $WinWorkstationDittoPath -PathType Leaf) -and -not (Get-Process -Name Ditto -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $WinWorkstationDittoPath -WindowStyle Hidden
    }

    if ((Get-WinWorkstationStartApp -Name 'EarTrumpet') -and -not (Get-Process -Name EarTrumpet -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "shell:AppsFolder\$WinWorkstationEarTrumpetAppId" -WindowStyle Hidden
    }
}

function Set-WinWorkstationManagedConfigFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)]$Manifest
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        Write-Warning "Managed config source not found: $Source"
        return
    }

    Backup-WinWorkstationFile -Path $Destination -Manifest $Manifest
    $parent = Split-Path -Parent $Destination
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Build the replacement beside the target first, then swap it in. If every link/copy strategy
    # fails, the live config is left untouched — never deleted-with-no-replacement (the old order
    # removed the destination before creating the link, so a denied link left no config at all).
    $stagePath = "$Destination.$([guid]::NewGuid().ToString('N')).new"
    $method = $null
    try {
        try {
            New-Item -ItemType SymbolicLink -Path $stagePath -Target $Source -ErrorAction Stop | Out-Null
            $method = 'Linked'
        }
        catch {
            try {
                New-Item -ItemType HardLink -Path $stagePath -Target $Source -ErrorAction Stop | Out-Null
                $method = 'Hard-linked'
            }
            catch {
                Copy-Item -LiteralPath $Source -Destination $stagePath -Force -ErrorAction Stop
                $method = 'Copied'
            }
        }
    }
    catch {
        Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue
        Write-Warning "Could not stage $Destination from $Source ($($_.Exception.Message)); left the existing file untouched."
        return
    }

    try {
        Move-Item -LiteralPath $stagePath -Destination $Destination -Force -ErrorAction Stop
    }
    catch {
        # Some providers won't overwrite via Move; remove then move the already-staged replacement.
        try {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $stagePath -Destination $Destination -Force -ErrorAction Stop
        }
        catch {
            Remove-Item -LiteralPath $stagePath -Force -ErrorAction SilentlyContinue
            Write-Warning "Could not replace $Destination ($($_.Exception.Message)); the existing file is unchanged."
            return
        }
    }

    if ($method -eq 'Copied') {
        Write-Warning "Copied $Source to $Destination because link creation was denied."
    }
    else {
        Write-Host "$method $Destination -> $Source" -ForegroundColor Green
    }
}

function Test-WinWorkstationKomorebiConfig {
    # Validate the repo komorebi.json with `komorebic check` before it is linked to the live WM.
    # Scope KOMOREBI_CONFIG_HOME to the repo komorebi dir so check reads the repo copy. Returns
    # $true when komorebic is absent (nothing to gate) so callers only bail on a real failure.
    $komorebic = Get-Command komorebic -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $komorebic) {
        return $true
    }

    $previousConfigHome = $env:KOMOREBI_CONFIG_HOME
    try {
        $env:KOMOREBI_CONFIG_HOME = Split-Path -Parent $WinWorkstationKomorebiSourcePath
        $output = & $komorebic.Source check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "komorebic check rejected ${WinWorkstationKomorebiSourcePath}: $((@($output) -join ' ').Trim())"
            return $false
        }
        return $true
    }
    catch {
        # Treat an unexpected komorebic failure as non-blocking (it is a best-effort gate); the
        # JSON syntax check in Test-WinDotfilesConfig already covers the crash-class corruption.
        Write-Verbose "komorebic check skipped: $($_.Exception.Message)"
        return $true
    }
    finally {
        if ($null -eq $previousConfigHome) {
            Remove-Item Env:KOMOREBI_CONFIG_HOME -ErrorAction SilentlyContinue
        }
        else {
            $env:KOMOREBI_CONFIG_HOME = $previousConfigHome
        }
    }
}

function Set-WinWorkstationKomorebiSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Gate on config validity BEFORE linking: a malformed komorebi.json linked live can leave you
    # with no window manager. If it fails, keep the current (last-known-good) link untouched.
    if (-not (Test-WinWorkstationKomorebiConfig)) {
        Write-Warning 'Skipping komorebi config link/restart until the config validates. Fix it and re-run winsmooth -Apply.'
        return
    }

    Set-WinWorkstationManagedConfigFile -Source $WinWorkstationKomorebiSourcePath -Destination $WinWorkstationKomorebiTargetPath -Manifest $Manifest
    Set-WinWorkstationManagedConfigFile -Source $WinWorkstationWhkdSourcePath -Destination $WinWorkstationWhkdTargetPath -Manifest $Manifest
    # komorebi.bar.json is intentionally not linked: Yasb is the primary status bar now. The file
    # is kept in the repo as a fallback (relink it and re-add --bar below to switch back).

    if (Get-Command komorebic -ErrorAction SilentlyContinue) {
        $komorebiAutostartShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\komorebi.lnk'
        Backup-WinWorkstationFile -Path $komorebiAutostartShortcut -Manifest $Manifest
        # Autostart komorebi together with whkd (keybindings). The status bar is Yasb, started
        # separately by Set-WinWorkstationYasbSettings; no --bar flag here.
        komorebic enable-autostart --whkd

        # A komorebi started in --bar mode respawns its bar if we only kill the process, so when a
        # stale bar is detected, restart komorebi cleanly without --bar (Yasb is the bar now).
        if (Get-Process -Name komorebi-bar -ErrorAction SilentlyContinue) {
            komorebic stop --whkd --bar 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
            Get-Process -Name komorebi-bar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            komorebic start --whkd --clean-state 2>$null | Out-Null
            # Report the actual outcome: a failed start (e.g. bad config) must not print "Restarted".
            if ($LASTEXITCODE -eq 0) {
                Write-Host 'Restarted komorebi without the built-in bar (Yasb owns the strip now).' -ForegroundColor Yellow
            }
            else {
                Write-Warning "komorebi failed to restart (komorebic start exit $LASTEXITCODE). Run 'wmstart' after checking 'komorebic check'."
            }
        }
        Write-Host 'Enabled komorebi autostart with whkd. Run "wmstop; wmstart" once (or reboot) to relaunch.' -ForegroundColor Yellow
    }
    else {
        Write-Warning 'komorebic is not installed or not on PATH.'
    }
}

function Set-WinWorkstationYasbSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Link the repo Yasb config + stylesheet to ~/.config/yasb so the bar is version-controlled
    # and the `theme` command's live styles.css rewrites repaint the running bar via hot-reload.
    Set-WinWorkstationManagedConfigFile -Source $WinWorkstationYasbConfigSourcePath -Destination $WinWorkstationYasbConfigTargetPath -Manifest $Manifest
    Set-WinWorkstationManagedConfigFile -Source $WinWorkstationYasbStylesSourcePath -Destination $WinWorkstationYasbStylesTargetPath -Manifest $Manifest

    if (Get-Command yasbc -ErrorAction SilentlyContinue) {
        # enable-autostart uses a per-user Run/Startup entry (no admin). Use `yasbc enable-autostart
        # --task` for a Task Scheduler entry if you want it to survive without the Startup folder.
        yasbc enable-autostart
        if (Get-Process -Name yasb -ErrorAction SilentlyContinue) {
            yasbc reload --silent 2>$null | Out-Null
        }
        else {
            yasbc start --silent 2>$null | Out-Null
        }
        # Confirm the bar is actually up before claiming success (start/reload can fail on a bad config).
        Start-Sleep -Milliseconds 300
        if (Get-Process -Name yasb -ErrorAction SilentlyContinue) {
            Write-Host 'Linked Yasb config + styles and enabled Yasb autostart (started the bar).' -ForegroundColor Yellow
        }
        else {
            Write-Warning 'Linked Yasb config + styles and enabled autostart, but the bar is not running. Check "yasbc start" output and yasb/config.yaml.'
        }
    }
    else {
        Write-Warning 'yasbc is not installed or not on PATH. Install AmN.yasb (winget) then re-run winsmooth -Apply.'
    }
}

function Set-WinWorkstationVSCodeSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Deep-merge the committed VSCode overlay (vscode/settings.json) into the live user
    # settings.json. Only the overlay's keys are touched; the user's other settings are kept.
    # The workbench.colorCustomizations object is merged key-by-key (preserving any custom
    # colours the user added) and is itself rewritten per-theme by the `theme` command.
    if (-not (Test-Path -LiteralPath $WinWorkstationVSCodeOverlaySourcePath -PathType Leaf)) {
        Write-Warning "VSCode overlay not found: $WinWorkstationVSCodeOverlaySourcePath"
        return
    }

    if (-not (Test-Path -LiteralPath $WinWorkstationVSCodeSettingsPath -PathType Leaf)) {
        if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
            Write-Host 'VSCode not detected (no code on PATH, no user settings.json); skipping VSCode theming.' -ForegroundColor DarkGray
            return
        }
        $parent = Split-Path -Parent $WinWorkstationVSCodeSettingsPath
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Set-Content -LiteralPath $WinWorkstationVSCodeSettingsPath -Value '{}' -Encoding utf8
    }

    Backup-WinWorkstationFile -Path $WinWorkstationVSCodeSettingsPath -Manifest $Manifest
    $overlay = Read-WinWorkstationJson -Path $WinWorkstationVSCodeOverlaySourcePath
    $settings = Read-WinWorkstationJson -Path $WinWorkstationVSCodeSettingsPath

    foreach ($property in $overlay.PSObject.Properties) {
        if ($property.Name -like '_*') { continue }

        if ($property.Name -eq 'workbench.colorCustomizations') {
            $existing = $settings.PSObject.Properties['workbench.colorCustomizations']
            if (-not $existing -or $existing.Value -isnot [System.Management.Automation.PSCustomObject]) {
                Set-WinWorkstationProperty -InputObject $settings -Name 'workbench.colorCustomizations' -Value ([PSCustomObject]@{})
            }
            $target = $settings.PSObject.Properties['workbench.colorCustomizations'].Value
            foreach ($colour in $property.Value.PSObject.Properties) {
                Set-WinWorkstationProperty -InputObject $target -Name $colour.Name -Value $colour.Value
            }
            continue
        }

        Set-WinWorkstationProperty -InputObject $settings -Name $property.Name -Value $property.Value
    }

    Write-WinWorkstationJson -InputObject $settings -Path $WinWorkstationVSCodeSettingsPath
    Write-Host "Merged VSCode theme overlay into $WinWorkstationVSCodeSettingsPath" -ForegroundColor Green
}

function Set-WinWorkstationSpicetifySettings {
    param([Parameter(Mandatory)]$Manifest)

    # Spotify theming is handled by tools\Apply-Spicetify.ps1 (copies the theme into
    # %APPDATA%\spicetify\Themes and runs spicetify apply). It self-skips when Spicetify isn't
    # installed, so this is a safe no-op on machines without it. $Manifest is unused (Spicetify
    # keeps its own reversible backup via `spicetify restore`), kept for signature consistency.
    if (-not (Get-Command spicetify -ErrorAction SilentlyContinue)) {
        Write-Host 'Spicetify not detected; skipping Spotify theming. Install with: scoop install spicetify-cli' -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path -LiteralPath $WinWorkstationApplySpicetifyScript -PathType Leaf)) {
        Write-Warning "Apply-Spicetify.ps1 not found: $WinWorkstationApplySpicetifyScript"
        return
    }
    & $WinWorkstationApplySpicetifyScript
}

function Set-WinWorkstationFlowLauncherSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Flow Launcher is the launcher (replacing PowerToys Run). tools\Apply-FlowLauncher.ps1
    # installs the palette-themed win-dotfiles theme, binds Alt+Space (Win+Space is OS-reserved
    # and can't be registered), and enables autostart. It resolves either a scoop portable data
    # root or the standard %APPDATA% one and self-skips when Flow isn't installed/run yet. So
    # this is a safe no-op. $Manifest is unused (Flow keeps its own Settings.json), kept for
    # signature consistency.
    $flowRoots = @()
    if ($env:SCOOP) { $flowRoots += (Join-Path $env:SCOOP 'persist\Flow-Launcher\UserData') }
    $flowRoots += (Join-Path $HOME 'scoop\persist\Flow-Launcher\UserData')
    $flowRoots += (Join-Path $env:APPDATA 'FlowLauncher')
    if (-not ($flowRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })) {
        Write-Host 'Flow Launcher not detected; skipping. Install with: winget install Flow-Launcher.Flow.Launcher (then run it once).' -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path -LiteralPath $WinWorkstationApplyFlowLauncherScript -PathType Leaf)) {
        Write-Warning "Apply-FlowLauncher.ps1 not found: $WinWorkstationApplyFlowLauncherScript"
        return
    }
    & $WinWorkstationApplyFlowLauncherScript
}

function Set-WinWorkstationNileSoftShellSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Nilesoft Shell re-skins the right-click context menu. tools\Apply-NileSoftShell.ps1 stages
    # the palette-themed win-dotfiles theme.nss into the install's imports\ folder; it resolves
    # either the winget/installer default (Program Files\Nilesoft Shell) or a scoop install and
    # self-skips when Shell isn't installed. So this is a safe no-op. $Manifest is unused (Shell
    # keeps its own config outside the backup manifest), kept for signature consistency.
    $shellRoots = @((Join-Path ${env:ProgramFiles} 'Nilesoft Shell'), (Join-Path $HOME 'scoop\apps\nilesoft-shell\current'))
    if ($env:SCOOP) { $shellRoots += (Join-Path $env:SCOOP 'apps\nilesoft-shell\current') }
    if (-not ($shellRoots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'shell.nss') -PathType Leaf })) {
        Write-Host 'Nilesoft Shell not detected; skipping. Install with: winget install Nilesoft.Shell (then run `shell -register -restart` from an elevated prompt once).' -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path -LiteralPath $WinWorkstationApplyNileSoftShellScript -PathType Leaf)) {
        Write-Warning "Apply-NileSoftShell.ps1 not found: $WinWorkstationApplyNileSoftShellScript"
        return
    }
    & $WinWorkstationApplyNileSoftShellScript
}

function Set-WinWorkstationWindhawkSettings {
    param([Parameter(Mandatory)]$Manifest)

    # Windhawk mod state (enable + per-mod settings) is captured into windhawk/state by
    # windhawk\Export-Windhawk.ps1. If that state exists, restore it best-effort; otherwise skip.
    if (-not (Test-Path -LiteralPath $WinWorkstationWindhawkStateManifest -PathType Leaf)) {
        Write-Host 'No committed Windhawk state (windhawk/state); skipping. Run windhawk\Export-Windhawk.ps1 to capture your mods.' -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $env:ProgramData 'Windhawk'))) {
        Write-Warning 'Windhawk is not installed; skipping mod import. Install RamenSoftware.Windhawk (winget) then re-run.'
        return
    }

    # Import-Windhawk self-elevates if needed and writes its own reversible backup under %LOCALAPPDATA%.
    Write-Host 'Importing Windhawk mods from windhawk\state (best-effort; restarts Explorer)...' -ForegroundColor Yellow
    & $WinWorkstationWindhawkImportScript
}

function ConvertTo-WinWorkstationRegistryPath {
    param([Parameter(Mandatory)][string]$Location)

    if ($Location -like 'HKU\*') {
        return "Registry::HKEY_USERS\$($Location.Substring(4))"
    }

    if ($Location -like 'HKCU\*') {
        return "Registry::$($Location -replace '^HKCU', 'HKEY_CURRENT_USER')"
    }

    if ($Location -like 'HKLM\*') {
        return "Registry::$($Location -replace '^HKLM', 'HKEY_LOCAL_MACHINE')"
    }

    $null
}

function Disable-WinWorkstationStartupItems {
    param(
        [Parameter(Mandatory)]$Manifest,
        [switch]$DeepWork
    )

    $targetPatterns = @('^Spotify$', '^Steam$', '^MicrosoftEdgeAutoLaunch_', '^Send to OneNote$')
    if ($DeepWork) {
        $targetPatterns += @('^Teams$', '^com\.squirrel\.slack\.slack$')
    }

    $startupCommands = @(Get-WinWorkstationStartupCommands)
    foreach ($startupCommand in $startupCommands) {
        $matched = $false
        foreach ($pattern in $targetPatterns) {
            if ($startupCommand.Name -match $pattern) {
                $matched = $true
                break
            }
        }

        if (-not $matched) {
            continue
        }

        $registryPath = ConvertTo-WinWorkstationRegistryPath -Location ([string]$startupCommand.Location)
        if ($registryPath) {
            Backup-WinWorkstationRegistryValue -Path $registryPath -Name $startupCommand.Name -Manifest $Manifest
            Remove-ItemProperty -LiteralPath $registryPath -Name $startupCommand.Name -ErrorAction SilentlyContinue
            Write-Host "Disabled startup registry item: $($startupCommand.Name)" -ForegroundColor Yellow
            continue
        }

        $commandPath = ([string]$startupCommand.Command).Trim('"')
        if ($commandPath -and (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
            Backup-WinWorkstationFile -Path $commandPath -Manifest $Manifest
            Remove-Item -LiteralPath $commandPath -Force
            Write-Host "Disabled startup shortcut: $($startupCommand.Name)" -ForegroundColor Yellow
        }
    }
}

function Set-WinWorkstationSearchIndexing {
    param([Parameter(Mandatory)]$Manifest)

    $paths = @($WorkspaceRoot, $DevRoot, $ProjectsRoot, $ToolsRoot, $CacheRoot) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($path in $paths) {
        Backup-WinWorkstationAttributes -Path $path -Manifest $Manifest
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and -not ($item.Attributes -band [IO.FileAttributes]::NotContentIndexed)) {
            $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::NotContentIndexed
            Write-Host "Marked as not content indexed: $path" -ForegroundColor Yellow
        }
    }
}

function Add-WinWorkstationDefenderExclusions {
    param([Parameter(Mandatory)]$Manifest)

    $candidatePaths = @(
        $WorkspaceRoot
        $DevRoot
        $ToolsRoot
        $CacheRoot
        $env:NPM_CONFIG_PREFIX
        $env:NPM_CONFIG_CACHE
        $env:PIP_CACHE_DIR
        (Join-Path $HOME 'scoop\apps')
        (Join-Path $HOME 'scoop\shims')
        (Join-Path $HOME '.nuget\packages')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $existingExclusions = @()
    try {
        $existingExclusions = @((Get-MpPreference -ErrorAction Stop).ExclusionPath | Where-Object { $_ })
    }
    catch {
        Write-Warning "Could not read current Defender exclusions before adding paths: $($_.Exception.Message)"
    }

    foreach ($path in $candidatePaths) {
        $normalizedPath = [IO.Path]::GetFullPath($path).TrimEnd('\')
        $alreadyExcluded = [bool]($existingExclusions | Where-Object {
                try {
                    [IO.Path]::GetFullPath($_).TrimEnd('\') -ieq $normalizedPath
                }
                catch {
                    ([string]$_).TrimEnd('\') -ieq $path.TrimEnd('\')
                }
            })

        try {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            [void]$Manifest.DefenderExclusions.Add([PSCustomObject]@{
                    Path    = $path
                    Existed = $alreadyExcluded
                })
            Write-Host "Added Defender path exclusion: $path" -ForegroundColor Yellow
        }
        catch {
            Write-Warning "Could not add Defender exclusion for $path. Run winsmooth -Apply from an elevated shell if this is an access issue. $($_.Exception.Message)"
        }
    }
}

function Initialize-WinWorkstationNativeMethods {
    if (([System.Management.Automation.PSTypeName]'WinDotfiles.NativeMethods').Type) {
        return
    }

    Add-Type -Namespace 'WinDotfiles' -Name 'NativeMethods' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, System.IntPtr pvParam, uint fWinIni);

[System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
public static extern bool SystemParametersInfoMouse(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

[System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfoWallpaper(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@
}

function Update-WinWorkstationUserSettings {
    # Push the freshly written input/animation registry values into the live session so they
    # apply without a sign-out. Window min/max animation still needs an explorer.exe restart.
    try {
        Initialize-WinWorkstationNativeMethods
        $nm = [WinDotfiles.NativeMethods]
        $flags = 0x03  # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE

        [void]$nm::SystemParametersInfo(0x0017, 0, [IntPtr]::Zero, $flags)   # SPI_SETKEYBOARDDELAY  -> shortest
        [void]$nm::SystemParametersInfo(0x000B, 31, [IntPtr]::Zero, $flags)  # SPI_SETKEYBOARDSPEED  -> fastest
        [void]$nm::SystemParametersInfo(0x006B, 0, [IntPtr]::Zero, $flags)   # SPI_SETMENUSHOWDELAY  -> instant
        [void]$nm::SystemParametersInfoMouse(0x0004, 0, @(0, 0, 0), $flags)  # SPI_SETMOUSE          -> accel off (1:1)
        [void]$nm::SystemParametersInfo(0x103F, 0, [IntPtr]::Zero, $flags)   # SPI_SETUIEFFECTS      -> off
    }
    catch {
        Write-Warning "Could not broadcast input/animation settings live; sign out to apply them. $($_.Exception.Message)"
    }
}

function Set-WinWorkstationResponsivenessSettings {
    param([Parameter(Mandatory)]$Manifest)

    $desktop  = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop'
    $metrics  = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics'
    $mouse    = 'Registry::HKEY_CURRENT_USER\Control Panel\Mouse'
    $keyboard = 'Registry::HKEY_CURRENT_USER\Control Panel\Keyboard'
    $advanced = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $visualfx = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'

    # Animations: kill all. UserPreferencesMask is the "Adjust for best performance" master bitmask.
    Set-WinWorkstationRegistryValue -Path $desktop -Name 'MenuShowDelay' -Value '0' -Type String -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $desktop -Name 'UserPreferencesMask' -Value ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) -Type Binary -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $metrics -Name 'MinAnimate' -Value '0' -Type String -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'TaskbarAnimations' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'ListviewAlphaSelect' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'ListviewShadow' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $visualfx -Name 'VisualFXSetting' -Value 3 -Type DWord -Manifest $Manifest

    # Input: raw 1:1 pointer (no acceleration) + fastest key repeat / shortest delay.
    Set-WinWorkstationRegistryValue -Path $mouse -Name 'MouseSpeed' -Value '0' -Type String -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $mouse -Name 'MouseThreshold1' -Value '0' -Type String -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $mouse -Name 'MouseThreshold2' -Value '0' -Type String -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $keyboard -Name 'KeyboardDelay' -Value '0' -Type String -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $keyboard -Name 'KeyboardSpeed' -Value '31' -Type String -Manifest $Manifest

    Update-WinWorkstationUserSettings
    Write-Host 'Tuned responsiveness: animations off, raw pointer, fast key repeat (restart explorer.exe or sign out for window animations).' -ForegroundColor Yellow
}

function Set-WinWorkstationPowerPlan {
    param([Parameter(Mandatory)]$Manifest)

    $ultimateTemplate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $highPerformance  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

    # Capture the current active scheme so winsmooth -RestoreLast can revert it.
    $current = $null
    try {
        $active = (powercfg /getactivescheme) -join ' '
        if ($active -match '([0-9a-fA-F-]{36})') { $current = $Matches[1] }
    }
    catch {
        Write-Warning "Could not read the current power scheme: $($_.Exception.Message)"
    }
    if ($current) {
        [void]$Manifest.PowerPlan.Add([PSCustomObject]@{ PreviousScheme = $current })
    }

    # Prefer Ultimate Performance; materialize it from the template if it isn't present yet.
    $target = $null
    try {
        $schemes = (powercfg /list) -join "`n"
        if ($schemes -match '([0-9a-fA-F-]{36})\s+\(Ultimate Performance\)') {
            $target = $Matches[1]
        }
        else {
            $dup = (powercfg -duplicatescheme $ultimateTemplate) -join ' '
            if ($dup -match '([0-9a-fA-F-]{36})') { $target = $Matches[1] }
        }
    }
    catch {
        Write-Warning "Could not enumerate power schemes: $($_.Exception.Message)"
    }
    if (-not $target) { $target = $highPerformance }

    try {
        powercfg /setactive $target | Out-Null
        Write-Host "Activated high-performance power scheme: $target" -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Could not activate power scheme $target. Run winsmooth -Apply from an elevated shell. $($_.Exception.Message)"
        return
    }

    # Desktop is always plugged in: disable USB selective suspend and core parking, hold CPU at 100% on AC.
    $usbSub      = '2a737441-1930-4402-8d77-b2bebba308a3'
    $usbSetting  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    $procSub     = '54533251-82be-4824-96c1-47b60b740d00'
    $minState    = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    $coreParkMin = '0cc5b647-c1df-4637-891a-dec35c318583'
    powercfg /setacvalueindex SCHEME_CURRENT $usbSub $usbSetting 0 | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT $procSub $minState 100 | Out-Null
    powercfg /setacvalueindex SCHEME_CURRENT $procSub $coreParkMin 100 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
}

function Get-WinWorkstationResponsivenessSummary {
    $desktop  = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop'
    $metrics  = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics'
    $mouse    = 'Registry::HKEY_CURRENT_USER\Control Panel\Mouse'
    $keyboard = 'Registry::HKEY_CURRENT_USER\Control Panel\Keyboard'
    $advanced = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    $menuDelay   = (Get-ItemProperty -LiteralPath $desktop -Name 'MenuShowDelay' -ErrorAction SilentlyContinue).MenuShowDelay
    $minAnimate  = (Get-ItemProperty -LiteralPath $metrics -Name 'MinAnimate' -ErrorAction SilentlyContinue).MinAnimate
    $taskbarAnim = (Get-ItemProperty -LiteralPath $advanced -Name 'TaskbarAnimations' -ErrorAction SilentlyContinue).TaskbarAnimations
    $mouseSpeed  = (Get-ItemProperty -LiteralPath $mouse -Name 'MouseSpeed' -ErrorAction SilentlyContinue).MouseSpeed
    $keyDelay    = (Get-ItemProperty -LiteralPath $keyboard -Name 'KeyboardDelay' -ErrorAction SilentlyContinue).KeyboardDelay
    $keySpeed    = (Get-ItemProperty -LiteralPath $keyboard -Name 'KeyboardSpeed' -ErrorAction SilentlyContinue).KeyboardSpeed

    $scheme = $null
    try {
        $activeScheme = (powercfg /getactivescheme) -join ' '
        if ($activeScheme -match '\(([^)]+)\)') { $scheme = $Matches[1] }
    }
    catch { }

    [PSCustomObject]@{
        MenuShowDelay = $menuDelay
        KeyboardDelay = $keyDelay
        KeyboardSpeed = $keySpeed
        PowerScheme   = $scheme
        AnimationsOff = (("$menuDelay" -eq '0') -and ("$minAnimate" -eq '0') -and ($taskbarAnim -eq 0))
        PointerAccelOff = ("$mouseSpeed" -eq '0')
        KeyRepeatMaxed = (("$keyDelay" -eq '0') -and ("$keySpeed" -eq '31'))
        FastPower     = ($scheme -match 'Ultimate Performance|High performance')
    }
}

function Set-WinWorkstationShellDefaults {
    param([Parameter(Mandatory)]$Manifest)

    $advanced    = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $search      = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search'
    $explorerPol = 'Registry::HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\Explorer'
    $fileSystem  = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem'

    # Explorer + taskbar declutter
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'HideFileExt' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'Hidden' -Value 1 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'ShowTaskViewButton' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'TaskbarDa' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'TaskbarMn' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $advanced -Name 'LaunchTo' -Value 1 -Type DWord -Manifest $Manifest

    # Light/dark mode for apps and system is theme state (themes/<name>.psd1 IsLight), not a
    # one-time default — it's set by Set-WinWorkstationDesktopTheme so it stays in lock-step with
    # `theme <name>` instead of being clobbered back to a hardcoded value on every -Apply.

    # Taskbar search box hidden + no Start/web search suggestions
    Set-WinWorkstationRegistryValue -Path $search -Name 'SearchboxTaskbarMode' -Value 0 -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $search -Name 'BingSearchEnabled' -Value 0 -Type DWord -Manifest $Manifest
    # DisableSearchBoxSuggestions can be ACL-locked by Group Policy on managed devices; the helper
    # below degrades that case to a verbose note. BingSearchEnabled above covers the user-facing path.
    Set-WinWorkstationRegistryValue -Path $explorerPol -Name 'DisableSearchBoxSuggestions' -Value 1 -Type DWord -Manifest $Manifest

    # Long path support (HKLM; requires the elevated shell winsmooth -Apply already expects)
    try {
        Set-WinWorkstationRegistryValue -Path $fileSystem -Name 'LongPathsEnabled' -Value 1 -Type DWord -Manifest $Manifest
    }
    catch {
        Write-Warning "Could not set LongPathsEnabled (needs an elevated shell): $($_.Exception.Message)"
    }

    Set-WinWorkstationTaskbarAutohide -Manifest $Manifest

    Write-Host 'Applied shell defaults: extensions/hidden files shown, decluttered taskbar, Explorer opens This PC, long paths, taskbar autohide.' -ForegroundColor Yellow
}

function Set-WinWorkstationTaskbarAutohide {
    param([Parameter(Mandatory)]$Manifest)

    # The taskbar autohide flag lives in byte 8 of StuckRects3\Settings (a REG_BINARY blob).
    # Yasb is the primary status bar now, so reclaim the space; the tray still reveals on hover.
    $stuckRects = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'

    $settings = (Get-ItemProperty -LiteralPath $stuckRects -Name 'Settings' -ErrorAction SilentlyContinue).Settings
    if (-not $settings -or $settings.Length -lt 9) {
        Write-Warning 'StuckRects3\Settings not found or unexpected size; skipped taskbar autohide.'
        return
    }

    Backup-WinWorkstationRegistryValue -Path $stuckRects -Name 'Settings' -Manifest $Manifest
    $bytes = [byte[]]::new($settings.Length)
    [Array]::Copy($settings, $bytes, $settings.Length)
    $bytes[8] = $bytes[8] -bor 0x01
    New-ItemProperty -LiteralPath $stuckRects -Name 'Settings' -Value $bytes -PropertyType Binary -Force | Out-Null
}

function Restart-WinWorkstationExplorer {
    # Taskbar and Explorer registry changes only take effect after explorer.exe is recycled.
    try {
        Stop-Process -Name explorer -Force -ErrorAction Stop
        Write-Host 'Restarted explorer.exe to apply shell defaults.' -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Could not restart explorer.exe automatically; sign out to apply shell defaults. $($_.Exception.Message)"
    }
}

function Get-WinWorkstationShellDefaultsSummary {
    $advanced    = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $personalize = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $fileSystem  = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem'

    $hideFileExt  = (Get-ItemProperty -LiteralPath $advanced -Name 'HideFileExt' -ErrorAction SilentlyContinue).HideFileExt
    $taskbarDa    = (Get-ItemProperty -LiteralPath $advanced -Name 'TaskbarDa' -ErrorAction SilentlyContinue).TaskbarDa
    $appsLight    = (Get-ItemProperty -LiteralPath $personalize -Name 'AppsUseLightTheme' -ErrorAction SilentlyContinue).AppsUseLightTheme
    $longPaths    = (Get-ItemProperty -LiteralPath $fileSystem -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue).LongPathsEnabled
    $barRunning   = [bool](Get-Process -Name yasb -ErrorAction SilentlyContinue)

    $desktop      = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop'
    $activeTheme  = Get-WinWorkstationActiveThemeName
    $wallpaperSet = (Get-ItemProperty -LiteralPath $desktop -Name 'Wallpaper' -ErrorAction SilentlyContinue).Wallpaper
    $themedWallpaper = [bool]($wallpaperSet -and $wallpaperSet -like (Join-Path $WinWorkstationWallpaperRoot '*'))
    $accentOnTitlebars = ((Get-ItemProperty -LiteralPath $personalize -Name 'ColorPrevalence' -ErrorAction SilentlyContinue).ColorPrevalence -eq 1)

    [PSCustomObject]@{
        ExtensionsShown   = ($hideFileExt -eq 0)
        DarkMode          = ($appsLight -eq 0)
        TaskbarDecluttered = ($taskbarDa -eq 0)
        LongPaths         = ($longPaths -eq 1)
        BarRunning        = $barRunning
        ActiveTheme       = $activeTheme
        ThemedWallpaper   = $themedWallpaper
        AccentOnTitlebars = $accentOnTitlebars
    }
}

function Get-WinWorkstationActiveThemeName {
    if (Test-Path -LiteralPath $WinWorkstationActiveThemePath -PathType Leaf) {
        $name = Get-Content -LiteralPath $WinWorkstationActiveThemePath -TotalCount 1 -ErrorAction SilentlyContinue
        if ($name) { return $name.Trim().ToLowerInvariant() }
    }
    'ashes'
}

function Set-WinWorkstationFastfetchConfig {
    param([Parameter(Mandatory)]$Manifest)

    # Link the themed fastfetch config so the interactive login banner (170-greeting.ps1) renders
    # consistently. fastfetch is optional; this is a no-op warning when the source is absent.
    Set-WinWorkstationManagedConfigFile -Source $WinWorkstationFastfetchSourcePath -Destination $WinWorkstationFastfetchTargetPath -Manifest $Manifest
}

function Set-WinWorkstationDesktopTheme {
    # Apply the active theme's Windows desktop surfaces: accent color (DWM + title bars) and the
    # generated wallpaper. Registry writes go through Set-WinWorkstationRegistryValue so they are
    # captured in the backup manifest and reverted by winsmooth -RestoreLast.
    param(
        [Parameter(Mandatory)]$Manifest,
        [string]$ThemeName
    )

    if (-not $ThemeName) { $ThemeName = Get-WinWorkstationActiveThemeName }
    $themePath = Join-Path $WinDotfilesRoot ("themes\{0}.psd1" -f $ThemeName)
    if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
        Write-Warning "Theme '$ThemeName' not found ($themePath); skipped desktop theming."
        return
    }
    $theme = Import-PowerShellDataFile -LiteralPath $themePath
    $personalize = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

    # ── Light/dark mode ──────────────────────────────────────────────────────────────────
    # Themes without an IsLight key (all the originally-shipped ones) are treated as dark, so
    # this preserves prior behavior for them. This is the single place these keys are written —
    # Set-WinWorkstationShellDefaults used to hardcode them dark, which clobbered a light theme's
    # choice on every winsmooth -Apply since it runs after this step.
    $lightMode = if ($theme.IsLight) { 1 } else { 0 }
    Set-WinWorkstationRegistryValue -Path $personalize -Name 'AppsUseLightTheme' -Value $lightMode -Type DWord -Manifest $Manifest
    Set-WinWorkstationRegistryValue -Path $personalize -Name 'SystemUsesLightTheme' -Value $lightMode -Type DWord -Manifest $Manifest

    # ── Accent color ──────────────────────────────────────────────────────────────────────
    $hex = ([string]$theme.Accent).TrimStart('#')
    if ($hex.Length -eq 6) {
        $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
        # DWM\AccentColor is 0xAABBGGRR; ColorizationColor is 0xAARRGGBB. Build via bytes so the
        # full-alpha high bit doesn't overflow Int32 arithmetic.
        $accentAbgr = [BitConverter]::ToInt32([byte[]]@($r, $g, $b, 0xFF), 0)
        $colorArgb = [BitConverter]::ToInt32([byte[]]@($b, $g, $r, 0xFF), 0)

        $dwm = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM'
        Set-WinWorkstationRegistryValue -Path $dwm -Name 'AccentColor' -Value $accentAbgr -Type DWord -Manifest $Manifest
        Set-WinWorkstationRegistryValue -Path $dwm -Name 'ColorizationColor' -Value $colorArgb -Type DWord -Manifest $Manifest
        Set-WinWorkstationRegistryValue -Path $dwm -Name 'ColorizationAfterglow' -Value $colorArgb -Type DWord -Manifest $Manifest
        # Use the accent on title bars and window borders.
        Set-WinWorkstationRegistryValue -Path $personalize -Name 'ColorPrevalence' -Value 1 -Type DWord -Manifest $Manifest
    }
    else {
        Write-Warning "Theme '$ThemeName' has an invalid Accent '$($theme.Accent)'; skipped accent color."
    }

    # ── Wallpaper ─────────────────────────────────────────────────────────────────────────
    $wallpaper = Join-Path $WinWorkstationWallpaperRoot ("{0}.png" -f $ThemeName)
    if (Test-Path -LiteralPath $wallpaper -PathType Leaf) {
        $desktop = 'Registry::HKEY_CURRENT_USER\Control Panel\Desktop'
        Set-WinWorkstationRegistryValue -Path $desktop -Name 'Wallpaper' -Value $wallpaper -Type String -Manifest $Manifest
        Set-WinWorkstationRegistryValue -Path $desktop -Name 'WallpaperStyle' -Value '10' -Type String -Manifest $Manifest
        Set-WinWorkstationRegistryValue -Path $desktop -Name 'TileWallpaper' -Value '0' -Type String -Manifest $Manifest

        # Apply live: SPI_SETDESKWALLPAPER (0x0014) with SPIF_UPDATEINIFILE|SPIF_SENDCHANGE (0x03).
        Initialize-WinWorkstationNativeMethods
        [void][WinDotfiles.NativeMethods]::SystemParametersInfoWallpaper(0x0014, 0, $wallpaper, 0x03)
    }
    else {
        Write-Warning "Wallpaper for '$ThemeName' not found ($wallpaper); run tools/Build-Wallpapers.ps1 to generate it."
    }

    Write-Host "Applied desktop theme '$ThemeName' (accent $($theme.Accent) + wallpaper). Accent on title bars fully applies after sign-out." -ForegroundColor Yellow
}

function Invoke-WinWorkstationStep {
    # Run one apply step in isolation: a failure is reported and recorded, not fatal, so an early
    # throw (e.g. a hand-corrupted live settings.json) no longer aborts every later step and leaves
    # the machine half-configured. Failures are collected for the end-of-run summary.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][System.Collections.IList]$Failures
    )

    try {
        & $Action
    }
    catch {
        Write-Warning "winsmooth step '$Name' failed: $($_.Exception.Message). Continuing with the remaining steps."
        [void]$Failures.Add([PSCustomObject]@{ Step = $Name; Error = $_.Exception.Message })
    }
}

function Invoke-WinWorkstationSmooth {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Apply,
        [switch]$RestoreLast,
        [switch]$DeepWork,
        [switch]$SkipDefender,
        [switch]$SkipTerminal,
        [switch]$SkipPowerToys,
        [switch]$SkipComfortTools,
        [switch]$SkipKomorebi,
        [switch]$SkipYasb,
        [switch]$SkipVSCode,
        [switch]$SkipSpicetify,
        [switch]$SkipFlowLauncher,
        [switch]$SkipNileSoftShell,
        [switch]$SkipWindhawk,
        [switch]$SkipDesktopTheme,
        [switch]$SkipStartup,
        [switch]$SkipSearchIndexing,
        [switch]$SkipResponsiveness,
        [switch]$SkipShellDefaults
    )

    if ($RestoreLast) {
        Restore-WinWorkstationBackup
        return
    }

    $plannedActions = @(
        'Sync User Path once, outside profile startup'
        'Trim PowerToys modules and disable PowerToys Run (Flow Launcher is the launcher now)'
        'Keep the PowerToys Run config tuned (Everything primary, low noise) in case it is re-enabled'
        'Start and autostart QuickLook, EarTrumpet, and Ditto with bounded Ditto history'
        'Hide duplicate Windows Terminal profiles, merge the tracked terminal styling overlay, and link the WezTerm + fastfetch configs'
        'Link komorebi and whkd configs from this repo and enable komorebi autostart (whkd only; the bar is Yasb)'
        'Link Yasb config + styles, enable Yasb autostart, and start the status bar'
        'Merge the VSCode theme overlay (palette-driven workbench colours) into user settings'
        'Theme Spotify via Spicetify from the active palette (no-op if Spicetify is absent)'
        'Theme Flow Launcher, bind it to Alt+Space, and enable its autostart (no-op if Flow is absent)'
        'Import committed Windhawk mods (windhawk/state) when present'
        'Apply the active desktop theme: window accent color and the generated wallpaper'
        'Disable balanced startup noise: Spotify, Steam, Edge autolaunch, Send to OneNote'
        'Mark dev roots as not content indexed'
        'Add Defender path exclusions for dev/tool/cache roots when permissions allow'
        'Kill shell animations and set raw pointer + fast key repeat'
        'Set desktop power plan to Ultimate Performance, disable USB suspend + core parking'
        'Declutter Windows shell defaults: show extensions/hidden files, dark mode, clean + autohide taskbar, This PC, long paths'
    )

    if (-not $Apply) {
        Write-Host 'Preview only. Re-run with winsmooth -Apply to change host settings.' -ForegroundColor Cyan
        $plannedActions | ForEach-Object {
            [PSCustomObject]@{
                Action = $_
                Mode   = 'WhatIf'
            }
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess('Windows workstation settings', 'Apply reversible workstation tuning')) {
        return
    }

    $manifest = New-WinWorkstationBackupManifest
    $stepFailures = [System.Collections.Generic.List[object]]::new()

    try {
        Invoke-WinWorkstationStep -Name 'User Path sync' -Failures $stepFailures -Action {
            Backup-WinWorkstationRegistryValue -Path 'Registry::HKEY_CURRENT_USER\Environment' -Name 'Path' -Manifest $manifest
            Sync-WinDotfilesUserPath
        }

        if (-not $SkipPowerToys) {
            Invoke-WinWorkstationStep -Name 'PowerToys' -Failures $stepFailures -Action { Set-WinWorkstationPowerToysSettings -Manifest $manifest }
        }

        if (-not $SkipComfortTools) {
            Invoke-WinWorkstationStep -Name 'Comfort tools' -Failures $stepFailures -Action {
                Set-WinWorkstationComfortToolsSettings -Manifest $manifest
                Start-WinWorkstationComfortTools
            }
        }

        if (-not $SkipTerminal) {
            Invoke-WinWorkstationStep -Name 'Terminal + WezTerm + fastfetch' -Failures $stepFailures -Action {
                Set-WinWorkstationTerminalSettings -Manifest $manifest
                Set-WinWorkstationWeztermSettings -Manifest $manifest
                Set-WinWorkstationFastfetchConfig -Manifest $manifest
            }
        }

        if (-not $SkipKomorebi) {
            Invoke-WinWorkstationStep -Name 'komorebi' -Failures $stepFailures -Action { Set-WinWorkstationKomorebiSettings -Manifest $manifest }
        }

        if (-not $SkipYasb) {
            Invoke-WinWorkstationStep -Name 'Yasb' -Failures $stepFailures -Action { Set-WinWorkstationYasbSettings -Manifest $manifest }
        }

        if (-not $SkipVSCode) {
            Invoke-WinWorkstationStep -Name 'VSCode' -Failures $stepFailures -Action { Set-WinWorkstationVSCodeSettings -Manifest $manifest }
        }

        if (-not $SkipSpicetify) {
            Invoke-WinWorkstationStep -Name 'Spicetify' -Failures $stepFailures -Action { Set-WinWorkstationSpicetifySettings -Manifest $manifest }
        }

        if (-not $SkipFlowLauncher) {
            Invoke-WinWorkstationStep -Name 'Flow Launcher' -Failures $stepFailures -Action { Set-WinWorkstationFlowLauncherSettings -Manifest $manifest }
        }

        if (-not $SkipNileSoftShell) {
            Invoke-WinWorkstationStep -Name 'Nilesoft Shell' -Failures $stepFailures -Action { Set-WinWorkstationNileSoftShellSettings -Manifest $manifest }
        }

        if (-not $SkipWindhawk) {
            Invoke-WinWorkstationStep -Name 'Windhawk' -Failures $stepFailures -Action { Set-WinWorkstationWindhawkSettings -Manifest $manifest }
        }

        if (-not $SkipDesktopTheme) {
            Invoke-WinWorkstationStep -Name 'Desktop theme' -Failures $stepFailures -Action { Set-WinWorkstationDesktopTheme -Manifest $manifest }
        }

        if (-not $SkipStartup) {
            Invoke-WinWorkstationStep -Name 'Startup items' -Failures $stepFailures -Action { Disable-WinWorkstationStartupItems -Manifest $manifest -DeepWork:$DeepWork }
        }

        if (-not $SkipSearchIndexing) {
            Invoke-WinWorkstationStep -Name 'Search indexing' -Failures $stepFailures -Action { Set-WinWorkstationSearchIndexing -Manifest $manifest }
        }

        if (-not $SkipDefender) {
            Invoke-WinWorkstationStep -Name 'Defender exclusions' -Failures $stepFailures -Action { Add-WinWorkstationDefenderExclusions -Manifest $manifest }
        }

        if (-not $SkipResponsiveness) {
            Invoke-WinWorkstationStep -Name 'Responsiveness + power plan' -Failures $stepFailures -Action {
                Set-WinWorkstationResponsivenessSettings -Manifest $manifest
                Set-WinWorkstationPowerPlan -Manifest $manifest
            }
        }

        if (-not $SkipShellDefaults) {
            Invoke-WinWorkstationStep -Name 'Shell defaults' -Failures $stepFailures -Action {
                Set-WinWorkstationShellDefaults -Manifest $manifest
                Restart-WinWorkstationExplorer
            }
        }
    }
    finally {
        Save-WinWorkstationBackupManifest -Manifest $manifest
        Write-Host "Backup manifest: $(Join-Path $manifest.BackupRoot 'manifest.json')" -ForegroundColor Cyan

        if ($stepFailures.Count -gt 0) {
            Write-Warning "$($stepFailures.Count) winsmooth step(s) failed; the remaining steps were still applied:"
            foreach ($failure in $stepFailures) {
                Write-Warning "  - $($failure.Step): $($failure.Error)"
            }
            Write-Host 'Undo this run with: winsmooth -RestoreLast' -ForegroundColor Yellow
        }
    }
}

function Start-WinWindowManager {
    [CmdletBinding()]
    param()

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Warning 'komorebic is not installed or not on PATH.'
        return
    }

    # No --bar: Yasb is the status bar. Start it alongside komorebi so the rice comes up together.
    komorebic start --whkd --clean-state
    if (Get-Command yasbc -ErrorAction SilentlyContinue) {
        if (Get-Process -Name yasb -ErrorAction SilentlyContinue) {
            yasbc reload --silent 2>$null | Out-Null
        }
        else {
            yasbc start --silent 2>$null | Out-Null
        }
    }
}

function Stop-WinWindowManager {
    [CmdletBinding()]
    param()

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Warning 'komorebic is not installed or not on PATH.'
        return
    }

    komorebic stop --whkd
    # Defensive: clear any komorebi-bar still running from an old --bar session.
    Get-Process -Name komorebi-bar -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Get-Command yasbc -ErrorAction SilentlyContinue) {
        yasbc stop --silent 2>$null | Out-Null
    }
}

function Test-WinWindowManager {
    [CmdletBinding()]
    param()

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Warning 'komorebic is not installed or not on PATH.'
        return
    }

    Write-Host "Repo komorebi config: $WinWorkstationKomorebiSourcePath" -ForegroundColor Cyan
    Write-Host "Repo whkd config:     $WinWorkstationWhkdSourcePath" -ForegroundColor Cyan
    komorebic check
}

function Invoke-WinWindowManagerCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $komorebic = Get-Command komorebic -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $komorebic) {
        Write-Warning 'komorebic is not installed or not on PATH.'
        return $false
    }

    & $komorebic.Source @Arguments
    $LASTEXITCODE -eq 0
}

function Set-WinWindowManagerDevIntent {
    [CmdletBinding()]
    param()

    [void](Invoke-WinWindowManagerCommand -Arguments @('focus-named-workspace', 'DEV'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('named-workspace-layout', 'DEV', 'ultrawide-vertical-stack'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('named-workspace-padding', 'DEV', '8'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('named-workspace-container-padding', 'DEV', '6'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('retile'))
}

function Set-WinWindowManagerBrowseIntent {
    [CmdletBinding()]
    param()

    [void](Invoke-WinWindowManagerCommand -Arguments @('focus-named-workspace', 'BROWSER'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('named-workspace-layout', 'BROWSER', 'columns'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('named-workspace-padding', 'BROWSER', '8'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('named-workspace-container-padding', 'BROWSER', '6'))
    [void](Invoke-WinWindowManagerCommand -Arguments @('retile'))
}

function Set-WinWindowManagerFocusIntent {
    [CmdletBinding()]
    param()

    [void](Invoke-WinWindowManagerCommand -Arguments @('toggle-monocle'))
}

function Reset-WinWindowManagerLayout {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $WinWorkstationKomorebiSourcePath -PathType Leaf)) {
        Write-Warning "Komorebi config not found: $WinWorkstationKomorebiSourcePath"
        return
    }

    [void](Invoke-WinWindowManagerCommand -Arguments @('replace-configuration', $WinWorkstationKomorebiSourcePath))
    [void](Invoke-WinWindowManagerCommand -Arguments @('retile'))
}

function Invoke-WinHardening {
    [CmdletBinding()]
    param(
        # Reverse the hardening (run enable-ai.ps1 + rebloat.ps1) instead of applying it.
        [switch]$Restore
    )

    $scripts = if ($Restore) { @('enable-ai.ps1', 'rebloat.ps1') } else { @('disable-ai.ps1', 'debloat.ps1') }

    $paths = foreach ($s in $scripts) {
        $p = Join-Path $WinDotfilesRoot "windows\$s"
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            Write-Warning "Hardening script not found: $p"
            return
        }
        $p
    }

    if ($Restore) {
        Write-Host 'Restoring Windows AI + diagnostics defaults (enable-ai, rebloat)' -ForegroundColor Cyan
    } else {
        Write-Host 'Applying Windows AI + diagnostics hardening (disable-ai, debloat)' -ForegroundColor Cyan
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        foreach ($p in $paths) { & $p }
        return
    }

    # Not elevated: relaunch one elevated window that runs both scripts (avoids two UAC prompts).
    # -NoExit keeps it open so the OK/FAIL lines stay readable.
    $exe = (Get-Process -Id $PID).Path
    $inner = ($paths | ForEach-Object { "& `"$_`"" }) -join '; '
    Write-Host 'Elevation required - launching one elevated window for both scripts...' -ForegroundColor Yellow
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $inner)
}

Set-Alias -Name wincheck -Value Invoke-WinWorkstationCheck -Force
Set-Alias -Name winsmooth -Value Invoke-WinWorkstationSmooth -Force
Set-Alias -Name winharden -Value Invoke-WinHardening -Force
Set-Alias -Name profileperf -Value Invoke-WinDotfilesProfilePerf -Force
Set-Alias -Name wmstart -Value Start-WinWindowManager -Force
Set-Alias -Name wmstop -Value Stop-WinWindowManager -Force
Set-Alias -Name wmcheck -Value Test-WinWindowManager -Force
Set-Alias -Name wmdev -Value Set-WinWindowManagerDevIntent -Force
Set-Alias -Name wmbrowse -Value Set-WinWindowManagerBrowseIntent -Force
Set-Alias -Name wmfocus -Value Set-WinWindowManagerFocusIntent -Force
Set-Alias -Name wmreset -Value Reset-WinWindowManagerLayout -Force
