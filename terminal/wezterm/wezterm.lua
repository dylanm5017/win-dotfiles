-- win-dotfiles WezTerm config (try-alongside Windows Terminal).
-- Linked to ~/.config/wezterm/wezterm.lua by install.ps1 / winsmooth -Apply.
-- The color scheme is a WezTerm built-in, kept in lock-step with the rest of the system
-- by the `theme` command (which rewrites the marked color_scheme line below).

local wezterm = require 'wezterm'
local act = wezterm.action
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
-- Extra top padding so terminal content isn't crammed right up against the tab/status bar.
config.window_padding = { left = 10, right = 10, top = 18, bottom = 8 }
-- Base off; update-right-status turns it on per-window only when there is scrollback to scroll
-- and we're not inside a full-screen TUI.
config.enable_scroll_bar = false
config.scrollback_lines = 10000
config.audible_bell = 'Disabled'
config.default_cursor_style = 'SteadyBlock'
config.max_fps = 120
-- Dim the panes you aren't typing in, so the active split is obvious without a border.
config.inactive_pane_hsb = { brightness = 0.9 }
config.switch_to_last_active_tab_when_closing_tab = true
-- The status bar shells out (git); repaint it every 5s instead of every second.
config.status_update_interval = 5000

-- Tabs: the bar stays visible even with one tab so the right-status line (workspace, project,
-- git branch, battery, clock) is always shown. The fancy tab bar is used for its built-in
-- vertical padding, so tabs + status aren't crammed against the window's top edge.
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
local TAB_MAX_WIDTH = 28
config.tab_max_width = TAB_MAX_WIDTH

-- Color scheme: a WezTerm built-in, rewritten by `theme set <name>` (themes/<name>.psd1
-- WeztermScheme). Keep the trailing marker comment intact so the switcher can find this line.
config.color_scheme = 'Everforest Light Soft' -- win-dotfiles:theme

-- The Everforest Soft variants aren't among this WezTerm build's built-ins (only the darker
-- Gogh pair), so ship them inline; custom color_schemes entries resolve by name like built-ins.
-- Values mirror themes/everforest*.psd1 and the Windows Terminal schemes of the same names.
config.color_schemes = {
  ['Everforest Dark Soft'] = {
    background = '#333c43',
    foreground = '#d3c6aa',
    cursor_bg = '#d3c6aa',
    cursor_fg = '#333c43',
    cursor_border = '#d3c6aa',
    selection_bg = '#434f55',
    selection_fg = '#d3c6aa',
    ansi = { '#333c43', '#e67e80', '#a7c080', '#dbbc7f', '#7fbbb3', '#d699b6', '#83c092', '#d3c6aa' },
    brights = { '#859289', '#e67e80', '#a7c080', '#dbbc7f', '#7fbbb3', '#d699b6', '#83c092', '#f2efdf' },
  },
  ['Everforest Light Soft'] = {
    background = '#f3ead3',
    foreground = '#5c6a72',
    cursor_bg = '#5c6a72',
    cursor_fg = '#f3ead3',
    cursor_border = '#5c6a72',
    selection_bg = '#ddd8be',
    selection_fg = '#5c6a72',
    ansi = { '#7a8478', '#e67e80', '#8da666', '#c1a266', '#72aea6', '#c98ca9', '#76b385', '#a5a292' },
    brights = { '#99a393', '#f85552', '#8da101', '#dfa000', '#3a94c5', '#df69ba', '#35a77c', '#fffbef' },
  },
}

-- OS auto light/dark: when Windows is in light mode, override the theme-managed (dark) scheme
-- with a light counterpart. Dark mode leaves the marker scheme untouched, so `theme set` stays
-- authoritative. WezTerm re-evaluates this whole file when the OS appearance changes, so no
-- extra event wiring is needed. The candidate is only applied if it resolves to a real scheme
-- (custom or built-in), so a bad mapping falls back to the dark scheme instead of erroring.
local light_for = {
  ['Dracula'] = 'Catppuccin Latte',
  ['Catppuccin Mocha'] = 'Catppuccin Latte',
  ['nord'] = 'Catppuccin Latte',
  ['rose-pine'] = 'rose-pine-dawn',
  ['Gruvbox dark, medium (base16)'] = 'Gruvbox light, medium (base16)',
  ['Gruvbox Material (Gogh)'] = 'Gruvbox light, medium (base16)',
  ['Ashes (base16)'] = 'Catppuccin Latte',
  ['Everforest Dark Soft'] = 'Everforest Light Soft',
}
do
  local ok, appearance = pcall(function() return wezterm.gui.get_appearance() end)
  if ok and appearance and appearance:find 'Light' then
    local candidate = light_for[config.color_scheme]
    if candidate and ((config.color_schemes or {})[candidate]
        or wezterm.color.get_builtin_schemes()[candidate]) then
      config.color_scheme = candidate
    end
  end
end

-- Resolve the active scheme's colors at load time so the tab bar chrome matches it. (The status
-- bar reads the live palette at render time below, so it also re-tints on `theme set` reloads.)
local scheme = (config.color_schemes or {})[config.color_scheme]
  or wezterm.color.get_builtin_schemes()[config.color_scheme] or {}
local s_bg = scheme.background or '#1e1e2e'
local s_fg = scheme.foreground or '#cdd6f4'
local s_ansi = scheme.ansi or {}
local s_bright = scheme.brights or {}
local s_accent = s_ansi[6] or s_fg   -- magenta/pink, echoing the Starship + fastfetch accents
local s_dim = s_bright[1] or s_fg    -- muted grey for inactive chrome

config.colors = {
  tab_bar = {
    background = s_bg,
    active_tab = { bg_color = s_accent, fg_color = s_bg, intensity = 'Bold' },
    inactive_tab = { bg_color = s_bg, fg_color = s_dim },
    inactive_tab_hover = { bg_color = s_bg, fg_color = s_fg },
    new_tab = { bg_color = s_bg, fg_color = s_dim },
    new_tab_hover = { bg_color = s_bg, fg_color = s_fg },
  },
}

-- The command palette defaults to its own colors; pull it into the active scheme. (Its stock
-- ctrl+shift+p binding is taken by the project switcher below, so it's rebound there too.)
config.command_palette_bg_color = s_bg
config.command_palette_fg_color = s_fg

-- Fancy tab bar frame: match the scheme background and give the bar a little more height/padding
-- than the retro bar so tabs and the status pills aren't jammed against the top edge.
config.window_frame = {
  font = wezterm.font { family = 'CaskaydiaCove NF', weight = 'Regular' },
  font_size = 10.0,
  active_titlebar_bg = s_bg,
  inactive_titlebar_bg = s_bg,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local PROJECTS_ROOT = 'C:/Workspace/Projects'
-- The dotfiles repo itself (source of projects.local.json). This is a personal path, not a
-- client name, so it is safe to reference directly.
local PROJECTS_LOCAL_JSON = 'C:/Workspace/Projects/win-dotfiles/powershell/projects.local.json'

local function basename(p)
  return (p:gsub('[/\\]+$', '')):match '[^/\\]+$' or p
end

-- Resolve a pane's cwd to a plain Windows path (handles both the newer Url userdata and the
-- older file://host/path string form, and strips the leading slash from /C:/...).
local function cwd_path(pane)
  local d = pane:get_current_working_dir()
  if not d then return nil end
  local p
  if type(d) == 'userdata' then
    p = d.file_path
  else
    p = tostring(d):gsub('^file://[^/]*', '')
  end
  if not p then return nil end
  return (p:gsub('^/(%a:)', '%1'))
end

-- Current git branch, cached by cwd and refreshed on a wall-clock interval so the status bar
-- doesn't shell out on every repaint. Counting repaints instead would be unpredictable:
-- update-status also fires on resize, focus change and theme switch, not just on the interval.
-- Fails silently to '' when cwd isn't a repo.
local BRANCH_TTL_SECONDS = 10
local branch_state = { cwd = nil, branch = '', checked_at = 0 }
local function git_branch(cwd)
  local now = os.time()
  if cwd ~= branch_state.cwd or (now - branch_state.checked_at) >= BRANCH_TTL_SECONDS then
    branch_state.cwd = cwd
    branch_state.checked_at = now
    local ok, success, stdout = pcall(wezterm.run_child_process,
      { 'git', '-C', cwd, 'rev-parse', '--abbrev-ref', 'HEAD' })
    if ok and success and stdout then
      branch_state.branch = (stdout:gsub('%s+$', ''))
    else
      branch_state.branch = ''
    end
  end
  return branch_state.branch
end

-- Read optional project group roots from the gitignored projects.local.json. Names are only
-- ever read/displayed at runtime on this machine, never written back, so this stays NDA-safe.
local function local_group_roots()
  local roots = {}
  local f = io.open(PROJECTS_LOCAL_JSON, 'r')
  if not f then return roots end
  local content = f:read '*a'
  f:close()
  local ok, data = pcall(wezterm.json_parse, content)
  if not ok or type(data) ~= 'table' or type(data.groups) ~= 'table' then return roots end
  for _, g in ipairs(data.groups) do
    if type(g) == 'table' and type(g.path) == 'string' and g.path ~= '' then
      local p = g.path
      if not p:match '^%a:[/\\]' and not p:match '^[/\\]' then
        p = PROJECTS_ROOT .. '/' .. p
      end
      table.insert(roots, p)
    end
  end
  return roots
end

-- Enumerate project directories under all roots via a single pwsh call, so directory semantics
-- match the `proj` picker (Get-ChildItem -Directory). Only runs on the project-switcher keypress.
local function project_choices()
  local roots = { PROJECTS_ROOT }
  for _, r in ipairs(local_group_roots()) do table.insert(roots, r) end

  -- Embed the roots as a single-quoted PowerShell array literal (quotes doubled to escape) so
  -- we don't depend on $args binding, which is unreliable with pwsh -Command.
  local quoted = {}
  for _, r in ipairs(roots) do
    table.insert(quoted, "'" .. r:gsub("'", "''") .. "'")
  end
  local script = 'Get-ChildItem -LiteralPath @(' .. table.concat(quoted, ',') ..
    ') -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName'

  local ok, success, stdout = pcall(wezterm.run_child_process,
    { 'pwsh.exe', '-NoProfile', '-NoLogo', '-Command', script })
  local choices, seen = {}, {}
  if ok and success and stdout then
    for line in stdout:gmatch '[^\r\n]+' do
      local path = (line:gsub('%s+$', ''))
      local key = path:lower()
      if path ~= '' and not seen[key] then
        seen[key] = true
        table.insert(choices, { id = path, label = basename(path) })
      end
    end
  end
  table.sort(choices, function(a, b) return a.label:lower() < b.label:lower() end)
  return choices
end

local function project_switcher(window, pane)
  local choices = project_choices()
  if #choices == 0 then return end
  window:perform_action(act.InputSelector {
    title = 'Projects',
    fuzzy = true,
    choices = choices,
    action = wezterm.action_callback(function(win, p, id, label)
      if not id then return end
      win:perform_action(act.SwitchToWorkspace {
        name = label,
        spawn = { cwd = id, args = { 'pwsh.exe', '-NoLogo' } },
      }, p)
    end),
  }, pane)
end

-- ---------------------------------------------------------------------------
-- Tab titles: index + whatever is actually interesting about the tab.
-- ---------------------------------------------------------------------------

-- A pane title of 'pwsh' tells you nothing — every tab says it. When the pane is sitting on a
-- shell we'd rather name the command it's running; when it isn't (nvim, ssh, a TUI that sets its
-- own title) the pane title is the better answer.
local KNOWN_SHELLS = {
  pwsh = true, powershell = true, cmd = true, bash = true, zsh = true,
  fish = true, sh = true, nu = true, wsl = true,
}

local function strip_exe(s)
  return (s:gsub('%.[eE][xX][eE]$', ''))
end

wezterm.on('format-tab-title', function(tab, _tabs, _panes, _cfg, _hover, max_width)
  local title = tab.tab_title

  if not title or title == '' then
    local pane = tab.active_pane or {}
    -- WEZTERM_CMD is set by the shell integration in powershell/profile.d/47-wezterm.ps1 and
    -- holds the command currently running (empty at an idle prompt).
    local user_vars = pane.user_vars or {}
    local cmd = user_vars.WEZTERM_CMD or ''
    local pane_title = pane.title or ''
    local proc = pane.foreground_process_name or ''
    proc = proc ~= '' and strip_exe(basename(proc)) or ''
    local is_shell = KNOWN_SHELLS[strip_exe(basename(pane_title)):lower()] or false

    if cmd ~= '' and (pane_title == '' or is_shell) then
      title = cmd
    elseif pane_title ~= '' and not is_shell then
      title = pane_title
    elseif proc ~= '' then
      title = proc
    else
      title = pane_title
    end
  end

  title = strip_exe(title):gsub('%s+$', '')
  if title == '' then title = 'shell' end

  -- Truncate ourselves so a long title (a full ssh command, a deep path) can't blow past the
  -- space the tab bar actually has; -2 leaves room for the padding spaces added back below.
  local label = (tab.tab_index + 1) .. '  ' .. title
  return ' ' .. wezterm.truncate_right(label, math.max(1, (max_width or TAB_MAX_WIDTH) - 2)) .. ' '
end)

-- ---------------------------------------------------------------------------
-- Status bar: rounded pills on the right of the tab bar, tinted from the live scheme.
-- ---------------------------------------------------------------------------

-- Nerd Font glyphs, built from codepoints so the source stays plain ASCII (swap freely).
local CAP_L = utf8.char(0xe0b6)   -- rounded left cap
local CAP_R = utf8.char(0xe0b4)   -- rounded right cap
local ICON_WS = utf8.char(0xf009) -- th-large (workspaces)
local ICON_DIR = utf8.char(0xf07b) -- folder
local ICON_GIT = utf8.char(0xe0a0) -- git branch
local ICON_BATT = utf8.char(0xf240) -- battery
local ICON_CLOCK = utf8.char(0xf017) -- clock

wezterm.on('update-right-status', function(window, pane)
  local p = window:effective_config().resolved_palette or {}
  local bg = p.background or s_bg
  local ansi = p.ansi or {}
  local bright = p.brights or {}

  local cells = {}
  local function attr(fg, back)
    table.insert(cells, { Background = { Color = back } })
    table.insert(cells, { Foreground = { Color = fg } })
  end
  -- Rounded pill: color cap on the bar bg, then bg-coloured text on the color, then closing cap.
  local function pill(color, icon, str)
    attr(color, bg)
    table.insert(cells, { Text = CAP_L })
    attr(bg, color)
    table.insert(cells, { Text = ' ' .. icon .. ' ' .. str .. ' ' })
    attr(color, bg)
    table.insert(cells, { Text = CAP_R })
    attr(bg, bg)
    table.insert(cells, { Text = ' ' })
  end

  pill(ansi[6] or '#ff79c6', ICON_WS, window:active_workspace())

  local cwd = cwd_path(pane)
  if cwd then
    pill(ansi[5] or '#bd93f9', ICON_DIR, basename(cwd))
    local branch = git_branch(cwd)
    if branch ~= '' then pill(ansi[3] or '#50fa7b', ICON_GIT, branch) end
  end

  local batt = wezterm.battery_info()
  if batt and #batt > 0 then
    pill(ansi[4] or '#f1fa8c', ICON_BATT, string.format('%.0f%%', batt[1].state_of_charge * 100))
  end

  pill(bright[1] or '#6272a4', ICON_CLOCK, wezterm.strftime '%H:%M')

  window:set_right_status(wezterm.format(cells))

  -- Show the scrollbar only when there is scrollback to scroll and we're not inside a
  -- full-screen TUI (nvim, fzf, lazygit) — the alt screen has no scrollback of its own, so the
  -- bar there is both useless and a visual distraction. Only push overrides on an actual change;
  -- set_config_overrides reconfigures the window.
  local want_bar = false
  local ok_dims, dims = pcall(function() return pane:get_dimensions() end)
  if ok_dims and dims then
    want_bar = dims.scrollback_rows > dims.viewport_rows and not pane:is_alt_screen_active()
  end
  local overrides = window:get_config_overrides() or {}
  if overrides.enable_scroll_bar ~= want_bar then
    overrides.enable_scroll_bar = want_bar
    window:set_config_overrides(overrides)
  end
end)

-- ---------------------------------------------------------------------------
-- Smart hyperlinks + quick select
-- ---------------------------------------------------------------------------

-- Keep the built-in URL/email/path rules, then append optional ticket/commit links. The base
-- URLs come from env vars so no client ADO org or repo is committed to this public repo:
--   WEZTERM_GH_REPO  = 'owner/name'                        -> #123 opens the GitHub issue
--   WEZTERM_GIT_REPO = 'owner/name'                        -> a git hash opens the commit
--   WEZTERM_ADO_BASE = 'https://dev.azure.com/org/proj/_workitems/edit/'  -> AB#123 opens the work item
local hyperlink_rules = wezterm.default_hyperlink_rules()
local gh_repo = os.getenv 'WEZTERM_GH_REPO'
local git_repo = os.getenv 'WEZTERM_GIT_REPO'
local ado_base = os.getenv 'WEZTERM_ADO_BASE'

if ado_base then
  table.insert(hyperlink_rules, { regex = '\\bAB#(\\d+)\\b', format = ado_base .. '$1' })
end
if gh_repo then
  table.insert(hyperlink_rules, { regex = '(?:^|\\s)#(\\d+)\\b', format = 'https://github.com/' .. gh_repo .. '/issues/$1' })
end
if git_repo then
  table.insert(hyperlink_rules, { regex = '\\b[0-9a-f]{7,40}\\b', format = 'https://github.com/' .. git_repo .. '/commit/$0' })
end
config.hyperlink_rules = hyperlink_rules

-- ctrl+shift+space quick-select of git hashes and file:line locations (no link needed).
config.quick_select_patterns = {
  '[0-9a-f]{7,40}',
  '[^\\s]+:\\d+',
}

-- ---------------------------------------------------------------------------
-- Keybindings
-- ---------------------------------------------------------------------------

-- Pane keybindings mirror the Windows Terminal overlay (ctrl+shift / ctrl+alt) so they do
-- not collide with komorebi/whkd's global alt bindings.
config.keys = {
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'o', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = false } },
  { key = 'h', mods = 'CTRL|ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'CTRL|ALT', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'CTRL|ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'CTRL|ALT', action = act.ActivatePaneDirection 'Right' },
  -- Project switcher: fuzzy-pick a project dir and open/switch to a per-project workspace.
  { key = 'p', mods = 'CTRL|SHIFT', action = wezterm.action_callback(project_switcher) },
  -- Fuzzy-switch between already-open workspaces.
  { key = 's', mods = 'CTRL|SHIFT', action = act.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' } },
  -- The stock ctrl+shift+p palette binding is taken by the project switcher above.
  { key = 'k', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
  -- Jump between prompts in the scrollback. Needs the OSC 133 marks emitted by
  -- powershell/profile.d/47-wezterm.ps1; without shell integration these do nothing.
  { key = 'UpArrow', mods = 'SHIFT', action = act.ScrollToPrompt(-1) },
  { key = 'DownArrow', mods = 'SHIFT', action = act.ScrollToPrompt(1) },
}

-- Triple-click selects the whole semantic zone under the cursor — i.e. one command's entire
-- output, however many lines it wrapped to, instead of the single visual line. Also OSC 133.
config.mouse_bindings = {
  {
    event = { Down = { streak = 3, button = 'Left' } },
    mods = 'NONE',
    action = act.SelectTextAtMouseCursor 'SemanticZone',
  },
}

return config
