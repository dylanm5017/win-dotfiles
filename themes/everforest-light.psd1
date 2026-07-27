@{
    # win-dotfiles theme definition — Everforest Light Soft. See ashes.psd1 for the contract.
    # The light counterpart of themes/everforest.psd1: the same forest palette on a warm
    # parchment base — cream backgrounds with the sage-green accent deepened for contrast.
    Name            = 'Everforest Light'
    ColorScheme     = 'Everforest Light Soft'            # Windows Terminal overlay scheme name
    WeztermScheme   = 'Everforest Light Soft'            # custom scheme in wezterm.lua (no built-in)
    StarshipPalette = 'everforest-light'
    # No light Everforest in komorebi's Base16 set, so use the Custom palette with the official
    # Light Soft hexes mapped to Base16 slots (bg0-bg3 -> Base00-03, fg -> Base05, accents 08-0F).
    KomorebiTheme   = @{
        palette          = 'Custom'
        colours          = @{
            'base_00' = '#F3EAD3'; 'base_01' = '#EAE4CA'; 'base_02' = '#E5DFC5'; 'base_03' = '#DDD8BE'
            'base_04' = '#939F91'; 'base_05' = '#5C6A72'; 'base_06' = '#5C6A72'; 'base_07' = '#333C43'
            'base_08' = '#F85552'; 'base_09' = '#F57D26'; 'base_0a' = '#DFA000'; 'base_0b' = '#8DA101'
            'base_0c' = '#35A77C'; 'base_0d' = '#3A94C5'; 'base_0e' = '#DF69BA'; 'base_0f' = '#E66868'
        }
        unfocused_border = 'Base03'
        bar_accent       = 'Base0B'
    }
    BarTheme        = @{
        palette = 'Custom'
        colours = @{
            'base_00' = '#F3EAD3'; 'base_01' = '#EAE4CA'; 'base_02' = '#E5DFC5'; 'base_03' = '#DDD8BE'
            'base_04' = '#939F91'; 'base_05' = '#5C6A72'; 'base_06' = '#5C6A72'; 'base_07' = '#333C43'
            'base_08' = '#F85552'; 'base_09' = '#F57D26'; 'base_0a' = '#DFA000'; 'base_0b' = '#8DA101'
            'base_0c' = '#35A77C'; 'base_0d' = '#3A94C5'; 'base_0e' = '#DF69BA'; 'base_0f' = '#E66868'
        }
        accent  = 'Base0B'
    }
    # Yasb status bar — real hex per role; rewritten into yasb/styles.css :root by `theme`.
    YasbPalette     = @{
        'bg'          = '#F3EAD3'
        'surface'     = '#EAE4CA'
        'surface-alt' = '#E5DFC5'
        'text'        = '#5C6A72'
        'subtext'     = '#939F91'
        'accent'      = '#8DA101'   # sage green, deepened for light backgrounds
        'accent-alt'  = '#3A94C5'   # blue
        'ok'          = '#35A77C'   # aqua (green is the accent, so ok gets its own shade)
        'warn'        = '#DFA000'   # yellow
        'err'         = '#F85552'   # red
        'island'      = 'rgba(243, 234, 211, 0.85)'
        'border'      = 'rgba(141, 161, 1, 0.35)'
    }
    Accent          = '#8DA101'
    Wallpaper       = @{ From = '#F3EAD3'; To = '#E5DFC5'; Glyph = '#8DA101' }
    # Flips Windows into light mode (see latte.psd1).
    IsLight         = $true
}
