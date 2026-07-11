# win-dotfiles theme switcher.
# `theme` reskins the whole system from a single palette: Windows Terminal, WezTerm, Starship,
# the komorebi window manager + bar, and the Windows desktop (accent + wallpaper). Theme
# definitions live in themes/<name>.psd1; the active choice is recorded in themes/active.txt.
#
#   theme                 show the active theme and the available ones
#   theme list            list available themes
#   theme dracula         switch to the Dracula theme (and re-apply live)
#   theme nord -NoApply   rewrite the config files only, without touching the running system

$WinDotfilesThemesRoot = Join-Path $WinDotfilesRoot 'themes'
$WinDotfilesActiveThemePath = Join-Path $WinDotfilesThemesRoot 'active.txt'

function Get-WinDotfilesAvailableTheme {
    if (-not (Test-Path -LiteralPath $WinDotfilesThemesRoot -PathType Container)) {
        return @()
    }
    Get-ChildItem -LiteralPath $WinDotfilesThemesRoot -Filter '*.psd1' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName } | Sort-Object
}

function Get-WinDotfilesActiveThemeName {
    if (Test-Path -LiteralPath $WinDotfilesActiveThemePath -PathType Leaf) {
        $name = (Get-Content -LiteralPath $WinDotfilesActiveThemePath -TotalCount 1 -ErrorAction SilentlyContinue)
        if ($name) { return $name.Trim().ToLowerInvariant() }
    }
    'ashes'
}

function Import-WinDotfilesThemeDefinition {
    param([Parameter(Mandatory)][string]$Name)

    $path = Join-Path $WinDotfilesThemesRoot ("{0}.psd1" -f $Name.ToLowerInvariant())
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Unknown theme '$Name'. Available: $((Get-WinDotfilesAvailableTheme) -join ', ')"
    }

    $theme = Import-PowerShellDataFile -LiteralPath $path
    foreach ($key in 'Name', 'ColorScheme', 'WeztermScheme', 'StarshipPalette', 'KomorebiTheme', 'BarTheme', 'YasbPalette', 'Accent', 'Wallpaper') {
        if (-not $theme.ContainsKey($key)) {
            throw "Theme '$Name' is missing required key '$key' ($path)."
        }
    }
    $theme
}

function Set-WinDotfilesFileContent {
    # Replace the first match of $Pattern (singleline) in a file, only writing when it changes.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Replacement
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warning "Theme target not found, skipped: $Path"
        return
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $regex = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $regex.IsMatch($content)) {
        Write-Warning "Theme marker not found in $([IO.Path]::GetFileName($Path)); left unchanged."
        return
    }
    # Evaluator avoids $-substitution surprises in the replacement text.
    $updated = $regex.Replace($content, { param($m) $Replacement }, 1)
    if ($updated -ne $content) {
        # Preserve the file's existing newline style; Set-Content -Raw keeps it as-is.
        Set-Content -LiteralPath $Path -Value $updated -NoNewline -Encoding utf8
    }
}

function New-WinDotfilesKomorebiThemeBlock {
    param([Parameter(Mandatory)]$Theme, [Parameter(Mandatory)][string[]]$Order)

    $lines = foreach ($k in $Order) { '    "{0}": "{1}"' -f $k, $Theme[$k] }
    "`"theme`": {`n" + ($lines -join ",`n") + "`n  }"
}

function New-WinDotfilesYasbThemeBlock {
    # Render the marker-delimited :root block for yasb/styles.css from a YasbPalette hashtable.
    # Yasb CSS supports :root + var(), so the rest of the stylesheet references these tokens.
    param([Parameter(Mandatory)][hashtable]$Palette)

    $order = @('bg', 'surface', 'surface-alt', 'text', 'subtext', 'accent', 'accent-alt', 'ok', 'warn', 'err', 'island', 'border')
    $lines = foreach ($k in $order) { '    --{0}: {1};' -f $k, $Palette[$k] }
    "/* win-dotfiles:theme:start */`n:root {`n" + ($lines -join "`n") + "`n}`n/* win-dotfiles:theme:end */"
}

function New-WinDotfilesVSCodeColorBlock {
    # Render the marker-delimited workbench.colorCustomizations block for vscode/settings.json
    # from a YasbPalette hashtable. This recolours VSCode's *chrome* (title bar, activity/side
    # bar, tabs, status bar, panels) to match the palette; syntax highlighting stays on whatever
    # color theme the user picks, so there's no third-party theme dependency to keep in sync.
    param([Parameter(Mandatory)][hashtable]$Palette)

    # Workbench colour key -> palette role. Only solid-hex roles are used (VSCode colour
    # customizations don't accept the rgba island/border tokens).
    $map = @(
        @('titleBar.activeBackground', 'bg'),
        @('titleBar.activeForeground', 'text'),
        @('titleBar.inactiveBackground', 'bg'),
        @('titleBar.inactiveForeground', 'subtext'),
        @('titleBar.border', 'surface'),
        @('activityBar.background', 'bg'),
        @('activityBar.foreground', 'accent'),
        @('activityBar.inactiveForeground', 'subtext'),
        @('activityBar.activeBorder', 'accent'),
        @('activityBarBadge.background', 'accent'),
        @('activityBarBadge.foreground', 'bg'),
        @('sideBar.background', 'bg'),
        @('sideBar.foreground', 'subtext'),
        @('sideBarTitle.foreground', 'text'),
        @('sideBarSectionHeader.background', 'surface'),
        @('sideBarSectionHeader.foreground', 'text'),
        @('statusBar.background', 'bg'),
        @('statusBar.foreground', 'subtext'),
        @('statusBar.noFolderBackground', 'bg'),
        @('statusBar.debuggingBackground', 'accent'),
        @('statusBar.debuggingForeground', 'bg'),
        @('editor.background', 'bg'),
        @('editorGroupHeader.tabsBackground', 'bg'),
        @('tab.activeBackground', 'surface'),
        @('tab.inactiveBackground', 'bg'),
        @('tab.activeForeground', 'text'),
        @('tab.inactiveForeground', 'subtext'),
        @('tab.activeBorderTop', 'accent'),
        @('tab.border', 'bg'),
        @('panel.background', 'bg'),
        @('panelTitle.activeForeground', 'text'),
        @('button.background', 'accent'),
        @('button.foreground', 'bg'),
        @('button.hoverBackground', 'accent-alt'),
        @('focusBorder', 'accent'),
        @('list.activeSelectionBackground', 'surface'),
        @('list.activeSelectionForeground', 'text'),
        @('list.hoverBackground', 'surface'),
        @('badge.background', 'accent'),
        @('badge.foreground', 'bg'),
        @('terminal.background', 'bg'),
        @('terminal.foreground', 'text')
    )

    $lines = foreach ($pair in $map) { '        "{0}": "{1}"' -f $pair[0], $Palette[$pair[1]] }
    "// win-dotfiles:theme:start`n" +
    "    `"workbench.colorCustomizations`": {`n" +
    ($lines -join ",`n") + "`n" +
    "    }`n" +
    "    // win-dotfiles:theme:end"
}

function New-WinDotfilesFlowThemeBlock {
    # Render the marker-delimited palette-brush block for flowlauncher/win-dotfiles.xaml from a
    # YasbPalette hashtable. The Flow theme's styles reference these brushes via StaticResource,
    # so rewriting this block recolours the launcher in lock-step (same pattern as the yasb :root
    # and VSCode colorCustomizations blocks).
    param([Parameter(Mandatory)][hashtable]$Palette)

    $map = @(
        @('wdBg', 'bg'),
        @('wdSurface', 'surface'),
        @('wdSurfaceAlt', 'surface-alt'),
        @('wdText', 'text'),
        @('wdSubtext', 'subtext'),
        @('wdAccent', 'accent'),
        @('ItemSelectedBackgroundColor', 'surface')   # required Flow key = selected-row background
    )
    $lines = foreach ($pair in $map) { '    <SolidColorBrush x:Key="{0}" Color="{1}" />' -f $pair[0], $Palette[$pair[1]] }
    "<!-- win-dotfiles:theme:start -->`n" + ($lines -join "`n") + "`n    <!-- win-dotfiles:theme:end -->"
}

function New-WinDotfilesNileSoftThemeBlock {
    # Render the marker-delimited theme{} block for nilesoft-shell/theme.nss from a YasbPalette
    # hashtable. Nilesoft Shell's config language (nss) supports `//` comments, so the whole
    # theme{} block (structure + color setters) is regenerated together, same as yasb's :root.
    param([Parameter(Mandatory)][hashtable]$Palette)

    $bg = $Palette['bg']
    $accent = $Palette['accent']
    $subtext = $Palette['subtext']
    $surfaceAlt = $Palette['surface-alt']

    @"
theme
{
	name = "win-dotfiles"

	view = view.small

	background
	{
		color = $bg
		opacity = 100
	}

	item
	{
		opacity = 100
		radius = 0
		prefix = 1

		text
		{
			normal = $accent
			select = $accent
			normal-disabled = $subtext
			select-disabled = $accent
		}

		back
		{
			select = $surfaceAlt
			select-disabled = $surfaceAlt
		}
	}

	font
	{
		size = 16
		name = "JetBrainsMono NFP"
		weight = 1
		italic = 0
	}

	border
	{
		enabled = false
		size = 1
		color = $accent
		opacity = 100
		radius = 0
	}

	shadow
	{
		enabled = true
		size = 5
		opacity = 5
		color = #11111b
	}

	separator
	{
		size = 1
		color = $bg
	}

	symbol
	{
		normal = $accent
		select = $accent
		normal-disabled = ${accent}7a
		select-disabled = ${accent}7a
	}

	image
	{
		enabled = false
		color = [$accent, $accent, $accent]
	}
}
"@
}

function Update-WinDotfilesThemeConfigFiles {
    param([Parameter(Mandatory)]$Theme)

    $wtOverlay = Join-Path $WinDotfilesRoot 'terminal\windows-terminal\settings.json'
    $wezterm = Join-Path $WinDotfilesRoot 'terminal\wezterm\wezterm.lua'
    $starship = Join-Path $WinDotfilesRoot 'starship.toml'
    $komorebi = Join-Path $WinDotfilesRoot 'komorebi\komorebi.json'
    $komorebiBar = Join-Path $WinDotfilesRoot 'komorebi\komorebi.bar.json'
    $yasbStyles = Join-Path $WinDotfilesRoot 'yasb\styles.css'
    $vscode = Join-Path $WinDotfilesRoot 'vscode\settings.json'
    $flow = Join-Path $WinDotfilesRoot 'flowlauncher\win-dotfiles.xaml'
    $nilesoft = Join-Path $WinDotfilesRoot 'nilesoft-shell\theme.nss'

    # Windows Terminal: flip the default colorScheme (all schemes already ship in the overlay).
    Set-WinDotfilesFileContent -Path $wtOverlay `
        -Pattern '"colorScheme"\s*:\s*"[^"]*"' `
        -Replacement ('"colorScheme": "{0}"' -f $Theme.ColorScheme)

    # WezTerm: rewrite the marked built-in color_scheme line.
    Set-WinDotfilesFileContent -Path $wezterm `
        -Pattern "config\.color_scheme\s*=\s*'[^']*'\s*-- win-dotfiles:theme" `
        -Replacement ("config.color_scheme = '{0}' -- win-dotfiles:theme" -f $Theme.WeztermScheme)

    # Starship: flip the active palette line. No `$` anchor: starship.toml is CRLF, and a
    # trailing `\r` before the newline makes `"$` fail, which previously left the prompt
    # palette stale. `[^"]*` bounds the match to the quoted value on that line.
    Set-WinDotfilesFileContent -Path $starship `
        -Pattern '(?m)^palette = "[^"]*"' `
        -Replacement ('palette = "{0}"' -f $Theme.StarshipPalette)

    # komorebi window manager + bar: rewrite the native theme block.
    Set-WinDotfilesFileContent -Path $komorebi `
        -Pattern '"theme"\s*:\s*\{.*?\}' `
        -Replacement (New-WinDotfilesKomorebiThemeBlock -Theme $Theme.KomorebiTheme -Order @('palette', 'name', 'unfocused_border', 'bar_accent'))

    Set-WinDotfilesFileContent -Path $komorebiBar `
        -Pattern '"theme"\s*:\s*\{.*?\}' `
        -Replacement (New-WinDotfilesKomorebiThemeBlock -Theme $Theme.BarTheme -Order @('palette', 'name', 'accent'))

    # Yasb status bar: rewrite the marked :root block in styles.css. Yasb hot-reloads on save
    # (the file is symlinked to ~/.config/yasb/styles.css), so the bar repaints live.
    Set-WinDotfilesFileContent -Path $yasbStyles `
        -Pattern '/\* win-dotfiles:theme:start \*/.*?/\* win-dotfiles:theme:end \*/' `
        -Replacement (New-WinDotfilesYasbThemeBlock -Palette $Theme.YasbPalette)

    # VSCode: rewrite the marked workbench.colorCustomizations block from the same palette.
    # winsmooth deep-merges this overlay into the live settings.json (Set-WinWorkstationVSCodeSettings).
    Set-WinDotfilesFileContent -Path $vscode `
        -Pattern '// win-dotfiles:theme:start.*?// win-dotfiles:theme:end' `
        -Replacement (New-WinDotfilesVSCodeColorBlock -Palette $Theme.YasbPalette)

    # Flow Launcher: rewrite the marked palette-brush block in the theme XAML. Apply-FlowLauncher
    # copies it into %APPDATA%\FlowLauncher\Themes; Flow hot-reloads the active theme file.
    Set-WinDotfilesFileContent -Path $flow `
        -Pattern '<!-- win-dotfiles:theme:start -->.*?<!-- win-dotfiles:theme:end -->' `
        -Replacement (New-WinDotfilesFlowThemeBlock -Palette $Theme.YasbPalette)

    # Nilesoft Shell: rewrite the marked theme{} block in nilesoft-shell/theme.nss.
    # tools/Apply-NileSoftShell.ps1 copies it into the installed shell's imports\theme.nss.
    Set-WinDotfilesFileContent -Path $nilesoft `
        -Pattern '// win-dotfiles:theme:start.*?// win-dotfiles:theme:end' `
        -Replacement ("// win-dotfiles:theme:start`n" + (New-WinDotfilesNileSoftThemeBlock -Palette $Theme.YasbPalette) + "`n// win-dotfiles:theme:end")
}

function Show-WinDotfilesThemeStatus {
    $active = Get-WinDotfilesActiveThemeName
    Write-Host "Active theme: " -NoNewline
    Write-Host $active -ForegroundColor Cyan
    Write-Host "Available:    $((Get-WinDotfilesAvailableTheme) -join ', ')" -ForegroundColor DarkGray
    Write-Host 'Switch with:  theme <name>' -ForegroundColor DarkGray
}

function Set-WinDotfilesTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        # Rewrite the config files but do not touch the running system (no live re-apply).
        [switch]$NoApply
    )

    if (-not $Name) { Show-WinDotfilesThemeStatus; return }
    if ($Name -in 'list', 'ls', '-list') {
        Write-Host "Available themes: $((Get-WinDotfilesAvailableTheme) -join ', ')" -ForegroundColor Cyan
        return
    }

    $theme = Import-WinDotfilesThemeDefinition -Name $Name
    $slug = $Name.ToLowerInvariant()

    Update-WinDotfilesThemeConfigFiles -Theme $theme
    Set-Content -LiteralPath $WinDotfilesActiveThemePath -Value $slug -Encoding utf8
    Write-Host "Theme set to $($theme.Name)." -ForegroundColor Green

    if ($NoApply) {
        Write-Host 'Config files updated. Open a new shell / reload apps to see it (-NoApply skipped live re-apply).' -ForegroundColor Yellow
        return
    }

    # Re-apply to the running system. komorebi/WezTerm/Starship pick up their symlinked/direct
    # configs automatically; Windows Terminal needs the overlay re-merged, and the desktop
    # accent/wallpaper are applied via the winsmooth helpers (which back up what they change).
    $manifest = $null
    if (Get-Command New-WinWorkstationBackupManifest -ErrorAction SilentlyContinue) {
        $manifest = New-WinWorkstationBackupManifest
    }

    try {
        if ($manifest -and (Get-Command Set-WinWorkstationTerminalSettings -ErrorAction SilentlyContinue)) {
            Set-WinWorkstationTerminalSettings -Manifest $manifest
        }
        if ($manifest -and (Get-Command Set-WinWorkstationDesktopTheme -ErrorAction SilentlyContinue)) {
            Set-WinWorkstationDesktopTheme -Manifest $manifest -ThemeName $slug
        }
        # VSCode: deep-merge the (just-rewritten) overlay into the live settings.json. VSCode
        # watches settings.json, so the workbench recolours instantly.
        if ($manifest -and (Get-Command Set-WinWorkstationVSCodeSettings -ErrorAction SilentlyContinue)) {
            Set-WinWorkstationVSCodeSettings -Manifest $manifest
        }
    }
    finally {
        if ($manifest -and (Get-Command Save-WinWorkstationBackupManifest -ErrorAction SilentlyContinue)) {
            Save-WinWorkstationBackupManifest -Manifest $manifest
        }
    }

    if (Get-Command komorebic -ErrorAction SilentlyContinue) {
        if (Get-Process -Name komorebi -ErrorAction SilentlyContinue) {
            komorebic reload-configuration | Out-Null
            Write-Host 'Reloaded komorebi (borders repaint).' -ForegroundColor DarkGray
        }
    }

    # Yasb hot-reloads the symlinked styles.css automatically; nudge it for the copy-fallback case.
    if (Get-Command yasbc -ErrorAction SilentlyContinue) {
        if (Get-Process -Name yasb -ErrorAction SilentlyContinue) {
            yasbc reload --silent 2>$null | Out-Null
            Write-Host 'Reloaded Yasb (status bar repaint).' -ForegroundColor DarkGray
        }
    }

    # Spotify: re-theme via Spicetify (no-op if Spicetify/Spotify aren't installed).
    $spicetifyScript = Join-Path $WinDotfilesRoot 'tools\Apply-Spicetify.ps1'
    if ((Get-Command spicetify -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $spicetifyScript -PathType Leaf)) {
        & $spicetifyScript -Scheme $slug
    }

    # Flow Launcher: restage the (just-rewritten) theme and point Flow at it (no-op if absent).
    # Detect either a scoop *portable* data root or the standard %APPDATA% one.
    $flowScript = Join-Path $WinDotfilesRoot 'tools\Apply-FlowLauncher.ps1'
    $flowRoots = @()
    if ($env:SCOOP) { $flowRoots += (Join-Path $env:SCOOP 'persist\Flow-Launcher\UserData') }
    $flowRoots += (Join-Path $HOME 'scoop\persist\Flow-Launcher\UserData')
    $flowRoots += (Join-Path $env:APPDATA 'FlowLauncher')
    if ((Test-Path -LiteralPath $flowScript -PathType Leaf) -and
        ($flowRoots | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'Settings\Settings.json') -PathType Leaf })) {
        & $flowScript
    }

    # Nilesoft Shell: restage the (just-rewritten) theme and reload it. Self-skips with a warning
    # when Nilesoft isn't installed, same as Apply-FlowLauncher.ps1.
    $nilesoftScript = Join-Path $WinDotfilesRoot 'tools\Apply-NileSoftShell.ps1'
    if (Test-Path -LiteralPath $nilesoftScript -PathType Leaf) {
        & $nilesoftScript
    }

    Write-Host 'Windows Terminal, WezTerm, and Starship pick up the new theme on save / next prompt.' -ForegroundColor DarkGray
}

Set-Alias -Name theme -Value Set-WinDotfilesTheme -Force
