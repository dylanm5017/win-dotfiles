@{
    # win-dotfiles theme definition — Rosé Pine (warm plum/rose/gold). See ashes.psd1 for the contract.
    Name            = 'Rosé Pine'
    ColorScheme     = 'Rose Pine'        # Windows Terminal overlay scheme name (ASCII)
    WeztermScheme   = 'rose-pine'        # WezTerm built-in scheme
    StarshipPalette = 'rosepine'
    KomorebiTheme   = @{ palette = 'Base16'; name = 'RosePine'; unfocused_border = 'Base03'; bar_accent = 'Base0E' }
    BarTheme        = @{ palette = 'Base16'; name = 'RosePine'; accent = 'Base0E' }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#191724'
        'surface'     = '#1f1d2e'
        'surface-alt' = '#26233a'
        'text'        = '#e0def4'
        'subtext'     = '#908caa'
        'accent'      = '#ebbcba'   # rose — warm signature accent
        'accent-alt'  = '#c4a7e7'   # iris
        'ok'          = '#9ccfd8'   # foam
        'warn'        = '#f6c177'   # gold
        'err'         = '#eb6f92'   # love
        'island'      = 'rgba(25, 23, 36, 0.82)'
        'border'      = 'rgba(235, 188, 186, 0.35)'
    }
    Accent          = '#EBBCBA'
    Wallpaper       = @{ From = '#191724'; To = '#100F1A'; Glyph = '#EBBCBA' }
}
