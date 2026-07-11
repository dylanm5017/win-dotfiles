@{
    # win-dotfiles theme definition — Catppuccin Latte. See ashes.psd1 for the field contract.
    # The official light counterpart to themes/mocha.psd1 — same Catppuccin token names
    # (Surface1, Mauve, ...), just the Latte flavor's hex values.
    Name            = 'Catppuccin Latte'
    ColorScheme     = 'Catppuccin Latte'
    WeztermScheme   = 'Catppuccin Latte'
    StarshipPalette = 'latte'
    # komorebi ships a native Catppuccin palette; accent/borders use Catppuccin color tokens.
    KomorebiTheme   = @{ palette = 'Catppuccin'; name = 'Latte'; unfocused_border = 'Surface1'; bar_accent = 'Mauve' }
    BarTheme        = @{ palette = 'Catppuccin'; name = 'Latte'; accent = 'Mauve' }
    # Yasb status bar — real hex per role (Yasb CSS has no native palette). Rewritten into the
    # :root block of yasb/styles.css by the `theme` command. island/border are translucent.
    YasbPalette     = @{
        'bg'          = '#EFF1F5'
        'surface'     = '#E6E9EF'
        'surface-alt' = '#CCD0DA'
        'text'        = '#4C4F69'
        'subtext'     = '#6C6F85'
        'accent'      = '#8839EF'   # mauve
        'accent-alt'  = '#1E66F5'   # blue
        'ok'          = '#40A02B'   # green
        'warn'        = '#DF8E1D'   # yellow
        'err'         = '#D20F39'   # red
        'island'      = 'rgba(239, 241, 245, 0.85)'
        'border'      = 'rgba(136, 57, 239, 0.35)'
    }
    Accent          = '#8839EF'
    Wallpaper       = @{ From = '#EFF1F5'; To = '#DCE0E8'; Glyph = '#8839EF' }
    # Optional: signals Set-WinWorkstationDesktopTheme to flip Windows into light mode
    # (AppsUseLightTheme/SystemUsesLightTheme) instead of the default dark. Themes without this
    # key are treated as dark, so existing themes need no changes.
    IsLight         = $true
}
