@{
    # win-dotfiles theme definition — Gruvbox Dark (warm retro). See ashes.psd1 for the contract.
    Name            = 'Gruvbox Dark'
    ColorScheme     = 'Gruvbox Dark'                    # Windows Terminal overlay scheme name
    WeztermScheme   = 'Gruvbox dark, medium (base16)'   # WezTerm built-in scheme
    StarshipPalette = 'gruvbox'
    KomorebiTheme   = @{ palette = 'Base16'; name = 'GruvboxDarkMedium'; unfocused_border = 'Base03'; bar_accent = 'Base09' }
    BarTheme        = @{ palette = 'Base16'; name = 'GruvboxDarkMedium'; accent = 'Base09' }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#282828'
        'surface'     = '#3c3836'
        'surface-alt' = '#504945'
        'text'        = '#ebdbb2'
        'subtext'     = '#a89984'
        'accent'      = '#fe8019'   # orange — the signature warm accent
        'accent-alt'  = '#8ec07c'   # aqua
        'ok'          = '#b8bb26'   # green
        'warn'        = '#fabd2f'   # yellow
        'err'         = '#fb4934'   # red
        'island'      = 'rgba(40, 40, 40, 0.85)'
        'border'      = 'rgba(254, 128, 25, 0.35)'
    }
    Accent          = '#FE8019'
    Wallpaper       = @{ From = '#282828'; To = '#1D2021'; Glyph = '#FE8019' }
}
