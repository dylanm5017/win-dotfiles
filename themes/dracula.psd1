@{
    # win-dotfiles theme definition — see ashes.psd1 for the field contract.
    Name            = 'Dracula'
    ColorScheme     = 'Dracula'
    WeztermScheme   = 'Dracula'
    StarshipPalette = 'dracula'
    KomorebiTheme   = @{ palette = 'Base16'; name = 'Dracula'; unfocused_border = 'Base03'; bar_accent = 'Base0E' }
    BarTheme        = @{ palette = 'Base16'; name = 'Dracula'; accent = 'Base0E' }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#282A36'
        'surface'     = '#44475A'
        'surface-alt' = '#6272A4'
        'text'        = '#F8F8F2'
        'subtext'     = '#6272A4'
        'accent'      = '#BD93F9'
        'accent-alt'  = '#8BE9FD'
        'ok'          = '#50FA7B'
        'warn'        = '#F1FA8C'
        'err'         = '#FF5555'
        'island'      = 'rgba(40, 42, 54, 0.80)'
        'border'      = 'rgba(189, 147, 249, 0.35)'
    }
    Accent          = '#BD93F9'
    Wallpaper       = @{ From = '#282A36'; To = '#191A21'; Glyph = '#BD93F9' }
}
