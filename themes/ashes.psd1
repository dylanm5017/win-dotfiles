@{
    # win-dotfiles theme definition. Consumed by the `theme` command (45-theme.ps1) and the
    # desktop-theme + wallpaper steps in winsmooth. One palette, mapped to each tool's native
    # theme name so a switch reskins terminal, prompt, window manager, and desktop together.
    Name            = 'Ashes'

    # Windows Terminal: the overlay ships all scheme hex; the switcher only flips colorScheme.
    ColorScheme     = 'Ashes'

    # WezTerm built-in color scheme name (config.color_scheme).
    WeztermScheme   = 'Ashes (base16)'

    # Starship palette: starship.toml ships all palettes; the switcher flips the active `palette`.
    StarshipPalette = 'ashes'

    # komorebi window manager + bar take a native Base16/Catppuccin theme name.
    KomorebiTheme   = @{ palette = 'Base16'; name = 'Ashes'; unfocused_border = 'Base03'; bar_accent = 'Base0D' }
    BarTheme        = @{ palette = 'Base16'; name = 'Ashes'; accent = 'Base0D' }

    # Yasb status bar — real hex per role (Yasb CSS has no native palette). Rewritten into the
    # :root block of yasb/styles.css by the `theme` command. island/border are translucent.
    YasbPalette     = @{
        'bg'          = '#1C2023'
        'surface'     = '#393F45'
        'surface-alt' = '#565E65'
        'text'        = '#C7CCD1'
        'subtext'     = '#ADB3BA'
        'accent'      = '#95AEC7'
        'accent-alt'  = '#AE95C7'
        'ok'          = '#95C7AE'
        'warn'        = '#C7C795'
        'err'         = '#C7AE95'
        'island'      = 'rgba(28, 32, 35, 0.80)'
        'border'      = 'rgba(149, 174, 199, 0.35)'
    }

    # Windows desktop accent (title bars / DWM) — Base0D (blue) from the Ashes palette.
    Accent          = '#95AEC7'

    # Generated wallpaper: diagonal gradient between two stops + a faint accent glyph.
    Wallpaper       = @{ From = '#1C2023'; To = '#2A2F35'; Glyph = '#95AEC7' }
}
