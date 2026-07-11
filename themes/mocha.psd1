@{
    # win-dotfiles theme definition — Catppuccin Mocha. See ashes.psd1 for the field contract.
    Name            = 'Catppuccin Mocha'
    ColorScheme     = 'Catppuccin Mocha'
    WeztermScheme   = 'Catppuccin Mocha'
    StarshipPalette = 'mocha'
    # komorebi ships a native Catppuccin palette; accent/borders use Catppuccin color tokens.
    KomorebiTheme   = @{ palette = 'Catppuccin'; name = 'Mocha'; unfocused_border = 'Surface1'; bar_accent = 'Mauve' }
    BarTheme        = @{ palette = 'Catppuccin'; name = 'Mocha'; accent = 'Mauve' }
    # Yasb status bar — real hex per role (Yasb CSS has no native palette). Rewritten into the
    # :root block of yasb/styles.css by the `theme` command. island/border are translucent.
    YasbPalette     = @{
        'bg'          = '#1e1e2e'
        'surface'     = '#313244'
        'surface-alt' = '#45475a'
        'text'        = '#cdd6f4'
        'subtext'     = '#a6adc8'
        'accent'      = '#cba6f7'
        'accent-alt'  = '#89b4fa'
        'ok'          = '#a6e3a1'
        'warn'        = '#f9e2af'
        'err'         = '#f38ba8'
        'island'      = 'rgba(30, 30, 46, 0.78)'
        'border'      = 'rgba(203, 166, 247, 0.35)'
    }
    Accent          = '#CBA6F7'
    Wallpaper       = @{ From = '#1E1E2E'; To = '#11111B'; Glyph = '#CBA6F7' }
}
