@{
    # win-dotfiles theme definition — see ashes.psd1 for the field contract.
    Name            = 'Nord'
    ColorScheme     = 'Nord'
    WeztermScheme   = 'nord'
    StarshipPalette = 'nord'
    KomorebiTheme   = @{ palette = 'Base16'; name = 'Nord'; unfocused_border = 'Base03'; bar_accent = 'Base0D' }
    BarTheme        = @{ palette = 'Base16'; name = 'Nord'; accent = 'Base0D' }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#2E3440'
        'surface'     = '#3B4252'
        'surface-alt' = '#434C5E'
        'text'        = '#E5E9F0'
        'subtext'     = '#81A1C1'
        'accent'      = '#88C0D0'
        'accent-alt'  = '#5E81AC'
        'ok'          = '#A3BE8C'
        'warn'        = '#EBCB8B'
        'err'         = '#BF616A'
        'island'      = 'rgba(46, 52, 64, 0.82)'
        'border'      = 'rgba(136, 192, 208, 0.35)'
    }
    Accent          = '#88C0D0'
    Wallpaper       = @{ From = '#2E3440'; To = '#232831'; Glyph = '#88C0D0' }
}
