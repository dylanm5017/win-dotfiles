@{
    # win-dotfiles theme definition — Gruvbox Material Dark (Soft). See ashes.psd1 for the contract.
    # A low-contrast, single-accent-hue variant of themes/gruvbox.psd1: a muted cream accent on a
    # warm dark-brown base, instead of the classic multi-hue orange/aqua/green look.
    Name            = 'Gruvbox Material'
    ColorScheme     = 'Gruvbox Material'                # Windows Terminal overlay scheme name
    WeztermScheme   = 'Gruvbox Material (Gogh)'         # WezTerm built-in scheme
    StarshipPalette = 'gruvbox-material'
    KomorebiTheme   = @{ palette = 'Base16'; name = 'GruvboxMaterialDarkSoft'; unfocused_border = 'Base03'; bar_accent = 'Base09' }
    BarTheme        = @{ palette = 'Base16'; name = 'GruvboxMaterialDarkSoft'; accent = 'Base09' }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#32302F'
        'surface'     = '#3C3836'
        'surface-alt' = '#45403D'
        'text'        = '#D4BE98'
        'subtext'     = '#928374'
        'accent'      = '#DDC7A1'   # cream — the signature low-contrast accent
        'accent-alt'  = '#89B482'   # aqua
        'ok'          = '#A9B665'   # green
        'warn'        = '#D8A657'   # yellow
        'err'         = '#EA6962'   # red
        'island'      = 'rgba(50, 48, 47, 0.85)'
        'border'      = 'rgba(221, 199, 161, 0.35)'
    }
    Accent          = '#DDC7A1'
    Wallpaper       = @{ From = '#32302F'; To = '#242220'; Glyph = '#DDC7A1' }
}
