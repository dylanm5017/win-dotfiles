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
config.enable_scroll_bar = false
config.scrollback_lines = 10000
config.audible_bell = 'Disabled'
config.default_cursor_style = 'SteadyBlock'

-- Tabs: the bar stays visible even with one tab so the right-status line (workspace, project,
-- git branch, battery, clock) is always shown. The fancy tab bar is used for its built-in
-- vertical padding, so tabs + status aren't crammed against the window's top edge.
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.tab_max_width = 28

-- Color scheme: a WezTerm built-in, rewritten by `theme set <name>` (themes/<name>.psd1
-- WeztermScheme). Keep the trailing marker comment intact so the switcher can find this line.
config.color_scheme = 'rose-pine' -- win-dotfiles:theme

-- OS auto light/dark: when Windows is in light mode, override the theme-managed (dark) scheme
-- with a light counterpart. Dark mode leaves the marker scheme untouched, so `theme set` stays
-- authoritative. WezTerm re-evaluates this whole file when the OS appearance changes, so no
-- extra event wiring is needed. The candidate is only applied if it's a real built-in scheme,
-- so a bad mapping falls back to the dark scheme instead of erroring on load.
local light_for = {
  ['Dracula'] = 'Catppuccin Latte',
  ['Catppuccin Mocha'] = 'Catppuccin Latte',
  ['nord'] = 'Catppuccin Latte',
  ['rose-pine'] = 'rose-pine-dawn',
  ['Gruvbox dark, medium (base16)'] = 'Gruvbox light, medium (base16)',
  ['Gruvbox Material (Gogh)'] = 'Gruvbox light, medium (base16)',
  ['Ashes (base16)'] = 'Catppuccin Latte',
}
do
  local ok, appearance = pcall(function() return wezterm.gui.get_appearance() end)
  if ok and appearance and appearance:find 'Light' then
    local candidate = light_for[config.color_scheme]
    if candidate and wezterm.color.get_builtin_schemes()[candidate] then
      config.color_scheme = candidate
    end
  end
end

-- Resolve the active scheme's colors at load time so the tab bar chrome matches it. (The status
-- bar reads the live palette at render time below, so it also re-tints on `theme set` reloads.)
local scheme = wezterm.color.get_builtin_schemes()[config.color_scheme] or {}
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

-- Current git branch, cached by cwd and refreshed periodically so the status bar doesn't shell
-- out on every repaint. Fails silently to '' when cwd isn't a repo.
local branch_state = { cwd = nil, branch = '', n = 0 }
local function git_branch(cwd)
  branch_state.n = branch_state.n + 1
  if cwd ~= branch_state.cwd or branch_state.n % 15 == 0 then
    branch_state.cwd = cwd
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
-- Tab titles: clean, padded, index + process/cwd (retro tab bar).
-- ---------------------------------------------------------------------------

wezterm.on('format-tab-title', function(tab, _tabs, _panes, _cfg, _hover, _max_width)
  local title = tab.tab_title
  if not title or title == '' then
    title = tab.active_pane and tab.active_pane.title or 'shell'
  end
  title = title:gsub('%.exe$', ''):gsub('%s+$', '')
  return ' ' .. (tab.tab_index + 1) .. '  ' .. title .. ' '
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
}

return config
