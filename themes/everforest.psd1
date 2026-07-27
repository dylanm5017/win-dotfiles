@{
    # win-dotfiles theme definition — Everforest Dark Soft. See ashes.psd1 for the contract.
    # Sainnhe's green sibling of themes/gruvbox-material.psd1: the same low-contrast material
    # feel, but on a blue-green forest base with a sage-green accent instead of brown + cream.
    Name            = 'Everforest'
    ColorScheme     = 'Everforest Dark Soft'            # Windows Terminal overlay scheme name
    WeztermScheme   = 'Everforest Dark Soft'            # custom scheme in wezterm.lua (no Dark Soft built-in)
    StarshipPalette = 'everforest'
    # komorebi's Base16 'Everforest' is the medium-contrast variant; its accent hexes are
    # identical across the dark variants, so borders/bar still match Dark Soft exactly.
    KomorebiTheme   = @{ palette = 'Base16'; name = 'Everforest'; unfocused_border = 'Base03'; bar_accent = 'Base0B' }
    BarTheme        = @{ palette = 'Base16'; name = 'Everforest'; accent = 'Base0B' }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#333C43'
        'surface'     = '#3A464C'
        'surface-alt' = '#434F55'
        'text'        = '#D3C6AA'
        'subtext'     = '#859289'
        'accent'      = '#A7C080'   # sage green — the signature accent
        'accent-alt'  = '#7FBBB3'   # blue
        'ok'          = '#83C092'   # aqua (green is the accent, so ok gets its own shade)
        'warn'        = '#DBBC7F'   # yellow
        'err'         = '#E67E80'   # red
        'island'      = 'rgba(51, 60, 67, 0.85)'
        'border'      = 'rgba(167, 192, 128, 0.35)'
    }
    Accent          = '#A7C080'
    Wallpaper       = @{ From = '#333C43'; To = '#293136'; Glyph = '#A7C080' }
}
