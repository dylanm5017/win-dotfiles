# Terminal

- Windows Terminal styling lives in `terminal/windows-terminal/settings.json` (the `Ashes`
  scheme matching komorebi, `CaskaydiaCove NF`, padding, `copyOnSelect`, bell off, hidden
  scrollbar, and `ctrl+shift`/`ctrl+alt` pane keybindings). `winsmooth -Apply` deep-merges this
  overlay into the live `settings.json`, preserving machine-specific profiles/GUIDs — so the
  terminal look is version-controlled. Edit the overlay, not the live file.
- WezTerm is available to try alongside Windows Terminal: `terminal/wezterm/wezterm.lua`
  (same theme and font, via a built-in color scheme) is linked to `~/.config/wezterm/wezterm.lua`
  by `winsmooth`/`install.ps1`. `Alt+Enter` launches the terminal (WezTerm if installed, else
  Windows Terminal). Its config is Lua, so it does more than the static overlay:
  - **Status bar** — the right side of the tab bar shows the active workspace, current project
    (cwd basename), git branch, battery, and clock, coloured from the live scheme so it tracks
    `theme`.
  - **Project switcher** — `ctrl+shift+p` fuzzy-picks a directory under `C:\Workspace\Projects`
    (plus any `projects.local.json` group roots) and opens/switches to a per-project **workspace**;
    `ctrl+shift+s` fuzzy-switches between already-open workspaces.
  - **Smart hyperlinks** — git hashes, `file:line`, and ticket IDs become clickable. The base URLs
    are read from env vars so nothing project-specific is committed: `WEZTERM_GH_REPO` (`#123` →
    GitHub issue), `WEZTERM_GIT_REPO` (hash → commit), `WEZTERM_ADO_BASE` (`AB#123` → ADO work
    item). `ctrl+shift+space` quick-selects hashes and `file:line` locations without a link.
  - **Shell integration** — `powershell/profile.d/47-wezterm.ps1` emits OSC 7 (cwd), OSC 133
    (prompt/output zones) and OSC 1337 user vars when the shell is running inside WezTerm, and
    no-ops everywhere else. That buys `shift+up`/`shift+down` to jump between prompts in the
    scrollback, triple-click to select a whole command's output however far it wrapped, exact cwd
    inheritance for new tabs/splits, and tab titles that name the command a tab is *running*
    (`git`, `npm`) instead of `pwsh`. Disable with `WINDOTFILES_WEZTERM_INTEGRATION=off`.
  - **OS auto light/dark** — when Windows switches to light mode, the theme-managed (dark) scheme
    is overridden with a light counterpart; dark mode leaves the `theme`-set scheme authoritative.
  - **Chrome that gets out of the way** — the scrollbar appears only when there is scrollback to
    scroll and you aren't inside a full-screen TUI, inactive panes dim, and `ctrl+shift+k` opens
    the command palette (its stock `ctrl+shift+p` binding belongs to the project switcher here).
- Both terminals carry a **subtle acrylic frost** that echoes the frosted Yasb bars and komorebi
  borders, kept conservative so text stays crisp: Windows Terminal uses `useAcrylic` at `opacity`
  95; WezTerm uses `win32_system_backdrop = 'Acrylic'` at `window_background_opacity` 0.94.
