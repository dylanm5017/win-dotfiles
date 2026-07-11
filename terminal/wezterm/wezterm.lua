-- win-dotfiles WezTerm config (try-alongside Windows Terminal).
-- Linked to ~/.config/wezterm/wezterm.lua by install.ps1 / winsmooth -Apply.
-- The color scheme is a WezTerm built-in, kept in lock-step with the rest of the system
-- by the `theme` command (which rewrites the marked color_scheme line below).

local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Shell + working directory: match the rest of the setup.
config.default_prog = { 'pwsh.exe', '-NoLogo' }
config.default_cwd = 'C:/Workspace'

-- Font: same Nerd Font as the bar and Windows Terminal.
config.font = wezterm.font_with_fallback { 'CaskaydiaCove NF', 'Cascadia Code', 'Consolas' }
config.font_size = 11.0

-- Window: minimal chrome so komorebi owns the frame. Subtle acrylic frost to echo the
-- frosted yasb bars + Windows Terminal (useAcrylic); kept conservative (0.94) so text
-- stays crisp. win32_system_backdrop = 'Acrylic' needs opacity < 1 to show through.
config.window_decorations = 'RESIZE'
config.window_background_opacity = 0.94
config.win32_system_backdrop = 'Acrylic'
config.window_padding = { left = 10, right = 10, top = 8, bottom = 8 }
config.enable_scroll_bar = false
config.scrollback_lines = 10000
config.audible_bell = 'Disabled'
config.default_cursor_style = 'SteadyBlock'

-- Tabs: compact, hidden when there is only one.
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.tab_max_width = 28

-- Color scheme: a WezTerm built-in, rewritten by `theme set <name>` (themes/<name>.psd1
-- WeztermScheme). Keep the trailing marker comment intact so the switcher can find this line.
config.color_scheme = 'Dracula' -- win-dotfiles:theme

-- Pane keybindings mirror the Windows Terminal overlay (ctrl+shift / ctrl+alt) so they do
-- not collide with komorebi/whkd's global alt bindings.
config.keys = {
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'o', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'w', mods = 'CTRL|SHIFT', action = wezterm.action.CloseCurrentPane { confirm = false } },
  { key = 'h', mods = 'CTRL|ALT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'CTRL|ALT', action = wezterm.action.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'CTRL|ALT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'CTRL|ALT', action = wezterm.action.ActivatePaneDirection 'Right' },
}

return config
