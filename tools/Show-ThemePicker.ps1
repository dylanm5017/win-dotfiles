# win-dotfiles theme picker — the GUI behind the yasb `theme_status` widget's left-click.
# Pops a small palette-styled list of the available themes (each with its accent swatch, the
# active one marked), and on selection applies it exactly like typing `theme <name>` in a shell.
#
# Launched hidden by yasb (yasb/config.yaml -> theme_status.callbacks.on_left, via the sibling
# .vbs so pwsh's console never flashes). The popup is built purely from direct file reads so it
# appears fast; the heavier theme-apply machinery is dot-sourced only after a theme is chosen.

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Capture the click location first thing — this runs within a few hundred ms of the widget click,
# before the pointer drifts, so the dropdown can anchor to where the widget was actually clicked
# rather than to wherever the mouse has wandered by the time the window finishes loading.
$clickPt = [System.Windows.Forms.Cursor]::Position

$repoRoot = Split-Path -Parent $PSScriptRoot
$themesRoot = Join-Path $repoRoot 'themes'
$activePath = Join-Path $themesRoot 'active.txt'

$paletteFallback = @{ bg = '#1c1c1c'; surface = '#2a2a2a'; text = '#e6e6e6'; subtext = '#8a8a8a'; accent = '#7aa2f7'; 'surface-alt' = '#3a3a3a' }

$activeSlug = 'ashes'
if (Test-Path -LiteralPath $activePath -PathType Leaf) {
    $name = (Get-Content -LiteralPath $activePath -TotalCount 1 -ErrorAction SilentlyContinue)
    if ($name) { $activeSlug = $name.Trim().ToLowerInvariant() }
}

# Build the row data (slug / display name / accent swatch / active marker) straight from the theme
# .psd1 files, and grab the active theme's palette to skin the popup. Read directly (not via the
# profile's theme helpers) so the popup doesn't pay for dot-sourcing the workstation profile.
$themeItems = [System.Collections.Generic.List[object]]::new()
$activePalette = $paletteFallback
foreach ($file in Get-ChildItem -LiteralPath $themesRoot -Filter '*.psd1' -ErrorAction SilentlyContinue | Sort-Object Name) {
    $slug = $file.BaseName.ToLowerInvariant()
    try {
        $def = Import-PowerShellDataFile -LiteralPath $file.FullName
    }
    catch {
        continue
    }
    $accent = if ($def.YasbPalette -and $def.YasbPalette['accent']) { $def.YasbPalette['accent'] } else { $paletteFallback.accent }
    $isActive = ($slug -eq $activeSlug)
    if ($isActive -and $def.YasbPalette) { $activePalette = $def.YasbPalette }
    $themeItems.Add([pscustomobject]@{
            Slug    = $slug
            Display = if ($def.Name) { [string]$def.Name } else { $slug }
            Accent  = $accent
            Marker  = if ($isActive) { "$([char]0x25CF)" } else { '' }  # ● on the active theme
        })
}

if ($themeItems.Count -eq 0) { return }

function Get-PaletteColor {
    param([hashtable]$Palette, [string]$Key)
    if ($Palette -and $Palette[$Key]) { return [string]$Palette[$Key] }
    [string]$paletteFallback[$Key]
}

$bg = Get-PaletteColor $activePalette 'bg'
$surface = Get-PaletteColor $activePalette 'surface'
$text = Get-PaletteColor $activePalette 'text'
$subtext = Get-PaletteColor $activePalette 'subtext'
$accent = Get-PaletteColor $activePalette 'accent'
$border = Get-PaletteColor $activePalette 'surface-alt'

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="win-dotfiles Theme Picker"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="WidthAndHeight" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" WindowStartupLocation="Manual" Opacity="0"
        FontFamily="Segoe UI, JetBrainsMono NFP">
  <Border Background="__BG__" CornerRadius="10" BorderBrush="__BORDER__" BorderThickness="1" Padding="8">
    <Border.Effect>
      <DropShadowEffect BlurRadius="20" ShadowDepth="0" Opacity="0.55" Color="#000000"/>
    </Border.Effect>
    <StackPanel Width="216">
      <TextBlock Text="THEME" FontSize="10" FontWeight="Bold" Foreground="__SUBTEXT__"
                 Margin="8,4,8,8" />
      <ListBox x:Name="List" Background="Transparent" BorderThickness="0" Foreground="__TEXT__"
               ScrollViewer.HorizontalScrollBarVisibility="Disabled">
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="Foreground" Value="__TEXT__"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                  <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}">
                    <ContentPresenter/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="Bd" Property="Background" Value="__SURFACE__"/>
                    </Trigger>
                    <Trigger Property="IsSelected" Value="True">
                      <Setter TargetName="Bd" Property="Background" Value="__SURFACE__"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Width="13" Height="13" CornerRadius="4"
                      Background="{Binding Accent}" BorderBrush="__BORDER__" BorderThickness="1"
                      Margin="0,0,10,0"/>
              <TextBlock Grid.Column="1" Text="{Binding Display}" VerticalAlignment="Center" FontSize="13"/>
              <TextBlock Grid.Column="2" Text="{Binding Marker}" Foreground="__ACCENT__"
                         VerticalAlignment="Center" FontSize="12"/>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
    </StackPanel>
  </Border>
</Window>
'@

$xaml = $xaml.
Replace('__BG__', $bg).
Replace('__SURFACE__', $surface).
Replace('__TEXT__', $text).
Replace('__SUBTEXT__', $subtext).
Replace('__ACCENT__', $accent).
Replace('__BORDER__', $border)

# WPF needs an STA apartment with a live runspace (pwsh 7 starts MTA, and a raw thread has no
# runspace for the event-handler scriptblocks). So drive the UI through a [powershell] instance on
# a dedicated STA runspace, passing data in via SessionStateProxy and handing the chosen slug back
# through a synchronized bag. The apply happens after the UI runspace closes.
$sync = [hashtable]::Synchronized(@{ Selected = $null })

$uiScript = {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $list = $window.FindName('List')
    $list.ItemsSource = $themeItems

    $active = $themeItems | Where-Object { $_.Slug -eq $activeSlug } | Select-Object -First 1
    if ($active) { $list.SelectedItem = $active } else { $list.SelectedIndex = 0 }

    $commit = {
        if ($list.SelectedItem) {
            $sync.Selected = $list.SelectedItem.Slug
            $window.Close()
        }
    }

    $list.Add_MouseLeftButtonUp($commit)
    $window.Add_KeyDown({
            param($s, $e)
            switch ($e.Key) {
                'Enter' { & $commit }
                'Escape' { $window.Close() }
            }
        })
    # Dismiss when focus leaves the popup (click elsewhere), like a normal menu.
    $window.Add_Deactivated({ $window.Close() })

    # Anchor as a dropdown hanging just under the top bar, on the monitor the widget was clicked on.
    # Yasb can't hand an external process the widget's rect, so use the click point captured at
    # launch: pin the top under the bar (bar sits at y=6, height 38 -> ~44px) and drop the menu
    # down-and-left from the click X, clamped to the monitor.
    $barGap = 48
    $window.Add_Loaded({
            $src = [System.Windows.PresentationSource]::FromVisual($window)
            $toDip = $src.CompositionTarget.TransformFromDevice
            $screen = [System.Windows.Forms.Screen]::FromPoint($clickPt)
            $b = $screen.Bounds
            $wa = $screen.WorkingArea

            $clickDip = $toDip.Transform([System.Windows.Point]::new($clickPt.X, $clickPt.Y))
            $barTop = $toDip.Transform([System.Windows.Point]::new($b.Left, $b.Top))
            $waTL = $toDip.Transform([System.Windows.Point]::new($wa.Left, $wa.Top))
            $waBR = $toDip.Transform([System.Windows.Point]::new($wa.Right, $wa.Bottom))
            $w = $window.ActualWidth
            $h = $window.ActualHeight

            $left = $clickDip.X - $w + 24
            $top = $barTop.Y + $barGap
            if ($left + $w -gt $waBR.X) { $left = $waBR.X - $w - 8 }
            if ($left -lt $waTL.X) { $left = $waTL.X + 8 }
            if ($top + $h -gt $waBR.Y) { $top = $waBR.Y - $h - 8 }

            $window.Left = $left
            $window.Top = $top
            # Reveal only once positioned, so the window never flashes at its (0,0) default first.
            $window.Opacity = 1
            $window.Activate()
            $list.Focus()
        })

    $window.ShowDialog() | Out-Null
}

$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = [System.Threading.ApartmentState]::STA
$rs.ThreadOptions = 'ReuseThread'
$rs.Open()
$rs.SessionStateProxy.SetVariable('xaml', $xaml)
$rs.SessionStateProxy.SetVariable('themeItems', $themeItems)
$rs.SessionStateProxy.SetVariable('activeSlug', $activeSlug)
$rs.SessionStateProxy.SetVariable('clickPt', $clickPt)
$rs.SessionStateProxy.SetVariable('sync', $sync)

$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript($uiScript)
$ps.Invoke() | Out-Null
$ps.Dispose()
$rs.Dispose()

if ($sync.Selected) {
    # Only now (a theme was picked) pay for the profile parts the live apply needs: 00-env defines
    # $WinDotfilesRoot + Test-Command; 150-workstation provides the backup/terminal/desktop/VSCode
    # helpers; 45-theme provides Set-WinDotfilesTheme. Order matters.
    $profileD = Join-Path $repoRoot 'powershell\profile.d'
    foreach ($part in '00-env.ps1', '150-workstation.ps1', '45-theme.ps1') {
        . (Join-Path $profileD $part)
    }
    Set-WinDotfilesTheme -Name $sync.Selected
}
