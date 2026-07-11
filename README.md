# Windows Dotfiles

Personal Windows shell configuration.

## Screenshots

Not yet added — see `docs/screenshots/README.md` for the capture checklist. Once filled in, this
section will show the desktop (Yasb bars + komorebi tiling), a themed terminal, Flow Launcher, and the
Nilesoft Shell context menu.

<!--
![Desktop](docs/screenshots/desktop.png)
![Terminal](docs/screenshots/terminal.png)
![Flow Launcher](docs/screenshots/flow-launcher.png)
![Context menu](docs/screenshots/context-menu.png)
-->

Tracked:
- PowerShell profile loader and profile.d scripts
- Project registry and PowerShell config
- Starship config and shell helper functions/aliases
- Package manifests (`packages/scoop.json`, `packages/winget.json`) and `install.ps1`
- Terminal configs: Windows Terminal styling overlay and WezTerm config (`terminal/`)
- Window manager configs (`komorebi/`)
- Status bar config (`yasb/`, the primary bar) and the Windhawk mod list (`windhawk/`)
- App theming driven by the active palette: VSCode overlay (`vscode/`), the Spicetify Spotify theme (`spicetify/`), the Flow Launcher theme (`flowlauncher/`), and the Nilesoft Shell context-menu theme (`nilesoft-shell/`)
- Theme palettes (`themes/`), generated wallpapers (`wallpapers/`), and the fastfetch banner (`fastfetch/`)

Not tracked:
- Installed PowerShell Gallery modules
- Caches
- Generated reports
- Local secrets

## Setup / bootstrap

`install.ps1` rebuilds the environment from this repo. It is idempotent — safe to re-run.

- `./install.ps1` installs the Scoop and winget package sets, links the PowerShell profile,
  then runs `winsmooth -Apply` (which links the komorebi/terminal/WezTerm configs and tunes
  the host). Run it from an elevated PowerShell so the elevated-only tuning applies.
- Switches: `-SkipScoop`, `-SkipWinget`, `-SkipFonts`, `-SkipWinsmooth`.
- `packages/scoop.json` is the Scoop manifest (buckets + apps); `packages/winget.json` is a
  curated winget set (toolchain + the comfort apps `winsmooth` manages, minus machine-specific
  noise). `scoop import packages/scoop.json` / `winget import packages/winget.json` re-create them.
- `pkgsync` (alias `pkglist`) refreshes `packages/scoop.json` from what is currently installed,
  keeping the clean shape so diffs stay meaningful. `winget.json` is hand-curated and left alone.

## Terminal

- Windows Terminal styling lives in `terminal/windows-terminal/settings.json` (the `Ashes`
  scheme matching komorebi, `CaskaydiaCove NF`, padding, `copyOnSelect`, bell off, hidden
  scrollbar, and `ctrl+shift`/`ctrl+alt` pane keybindings). `winsmooth -Apply` deep-merges this
  overlay into the live `settings.json`, preserving machine-specific profiles/GUIDs — so the
  terminal look is version-controlled. Edit the overlay, not the live file.
- WezTerm is available to try alongside Windows Terminal: `terminal/wezterm/wezterm.lua`
  (same theme and font, via a built-in color scheme) is linked to `~/.config/wezterm/wezterm.lua`
  by `winsmooth`/`install.ps1`. `Alt+Enter` launches the terminal (WezTerm if installed, else
  Windows Terminal).
- Both terminals carry a **subtle acrylic frost** that echoes the frosted Yasb bars and komorebi
  borders, kept conservative so text stays crisp: Windows Terminal uses `useAcrylic` at `opacity`
  95; WezTerm uses `win32_system_backdrop = 'Acrylic'` at `window_background_opacity` 0.94.

## Project navigation

Project groups live in `powershell/projects.json` (a generic example). To keep private
group names out of the repo, create `powershell/projects.local.json` with the same shape —
it is gitignored and takes precedence over the committed example when present.

- `project` / `proj` opens the fuzzy project picker.
- `project Sandbox` opens the configured group picker.
- `project win-dotfiles` jumps directly when a unique repo match exists.
- Group shortcuts such as `play`, `sbx`, and `clients` are generated from the registry.
- `addproj Sandbox` adds a new group to the registry, deriving the command and relative path by default.
- `apg Clients` creates/registers a project group under `C:\Workspace\Projects`.
- `ap -Group Clients -Mode empty -Name app` creates an empty project inside a group.
- `ap -Group Clients -Mode clone -GitUrl <url>` clones a repo into a group.
- `projcache` shows the persistent project directory cache; `projcache -Refresh` rebuilds it after adding or moving repos.

## Reliability

- `dotdoctor` runs the win-dotfiles health check.
- `powershell/Test-WinDotfiles.ps1` runs the same checks from a clean PowerShell process.
- Set `WINDOTFILES_PROFILE_DEBUG=1` before loading the profile to print per-script load times.
- The prompt defaults to Starship when it is installed (language-aware: shows git branch/status
  and Node/.NET/Python versions in context) and falls back to the fast native prompt otherwise.
  Force either with `WINDOTFILES_PROMPT=starship` or `WINDOTFILES_PROMPT=native`. The Starship
  prompt uses a **transient prompt** — once a command runs, its prompt collapses to a bare `❯`
  so scrollback stays focused on output.
- `profileperf` reports profile script timing, Starship prompt timing, and cached project lookup timing; add `-RefreshProjects` to include a full project scan.
- Codex shells prefer `C:\tmp\codex` when it supports create/delete; otherwise they fall back to repo-local `.tmp\codex` for `TEMP`/`TMP`/`TMPDIR`, `DOTNET_CLI_HOME`, .NET artifacts, and NuGet transient caches, with MSBuild node reuse disabled so sandboxed .NET builds avoid user-profile temp/state permission issues where possible.
- Add machine-specific settings to `powershell/profile.local.ps1`; it is ignored by git.

## Workstation tuning

- `wincheck` reports Windows friction across profile timing, project cache lookup, startup apps, Defender, search/indexing, services, launcher roles, comfort tools, PowerToys, Terminal profiles, WSL/Docker-adjacent processes, and komorebi/whkd.
- `wincheck -Detailed` includes slower profile scripts, enabled PowerToys modules, and top memory users.
- `winsmooth` previews reversible host tuning; `winsmooth -Apply` backs up touched settings under `C:\Workspace\Dev\Cache\win-dotfiles\workstation-backups` before applying them.
- `winsmooth -RestoreLast` restores the most recent workstation tuning backup.
- `winsmooth -Apply` trims PowerToys so komorebi owns tiling, disables PowerToys Run in favor of Flow Launcher on `Alt+Space` (themed + autostarted), makes Everything the primary file search path, limits duplicate Windows Search/folder result volume, starts/autostarts QuickLook/EarTrumpet/Ditto, applies bounded Ditto history, cleans Windows Terminal profiles, links repo-managed komorebi/whkd config, marks dev roots as not content indexed, and tries to add Defender path exclusions.
- Run `winsmooth -Apply` from an elevated shell when you want Defender exclusions to be added; Defender stays enabled and only path exclusions are used.
- `winsmooth -Apply` also tunes OS responsiveness: kills shell animations (menu/window/taskbar), sets a raw 1:1 pointer and the fastest key repeat, and activates a high-performance power plan (Ultimate Performance, no USB suspend or core parking). Skip it with `winsmooth -Apply -SkipResponsiveness`; window animations fully clear after an `explorer.exe` restart or sign-out, and the `wincheck` `Responsiveness` row reports the current state.
- `winsmooth -Apply` declutters Windows shell defaults: shows file extensions and hidden files, cleans the taskbar (hides Widgets, Chat, Task View, and the search box), disables Start menu web results, opens Explorer to This PC, and enables long-path support. It restarts `explorer.exe` to apply them; skip with `winsmooth -Apply -SkipShellDefaults`. The `wincheck` `Desktop` row reports shell-default and Yasb bar state. (Light/dark mode is set separately, by the active theme — see [Theming](#theming).)
- `winsmooth -Apply` links the repo `yasb/` status bar config (`config.yaml` + `styles.css`) to `~/.config/yasb`, enables Yasb autostart, and starts the bar; komorebi autostarts with `--whkd` only (Yasb is the bar now, so no `--bar`). The Yasb island shows per-monitor komorebi workspaces, the active layout, the focused window, now-playing media, CPU/memory, and a centered clock, themed to match the active theme (see [Theming](#theming)) with `CaskaydiaCove NF` glyphs. After applying, run `wmstop; wmstart` once (or reboot) so komorebi + Yasb relaunch together. It also auto-hides the Windows taskbar (Yasb is primary; the tray reveals on hover). Skip the bar step with `-SkipYasb`. The previous komorebi built-in bar (`komorebi/komorebi.bar.json`) stays in the repo as an unlinked fallback.
- `winsmooth -Apply` also extends the active theme to two app surfaces: it deep-merges the VSCode overlay (`vscode/settings.json`) into the live editor settings (palette-driven workbench chrome; `-SkipVSCode`) and themes Spotify via Spicetify from the active palette (`-SkipSpicetify`, no-op when Spicetify is absent). See [Theming](#theming).
- `winsmooth -Apply -DeepWork` also disables Teams and Slack startup entries; the default balanced profile leaves work comms alone.
- `winsmooth -Apply` applies the active desktop theme (window accent color, Windows light/dark mode from the theme's `IsLight` flag, and generated wallpaper) and links the fastfetch banner config. Skip with `winsmooth -Apply -SkipDesktopTheme`. The accent on title bars fully applies after sign-out.

## Theming

The whole system is themed from a single palette so the terminal, prompt, window manager, editor, music player, and Windows desktop stay in lock-step. Themes are defined once in `themes/<name>.psd1`; the active choice is recorded in `themes/active.txt`.

- `theme` shows the active theme and the available ones; `theme list` lists them.
- `theme dracula` switches everything live: Windows Terminal colors, WezTerm color scheme, the Starship palette, komorebi borders, the Yasb status bar, VSCode's workbench chrome, Spotify (via Spicetify), Flow Launcher, the Nilesoft Shell context menu, and the Windows accent color + wallpaper. komorebi reloads in place and Yasb hot-reloads (its `styles.css` `:root` block is rewritten from the theme's `YasbPalette`); Windows Terminal/WezTerm/Starship pick up on save / next prompt.
- `theme nord -NoApply` rewrites the config files without touching the running system (useful in setup/CI).
- Shipped themes: **ashes** (default, the muted Base16 look), **dracula**, **nord**, **mocha** (Catppuccin Mocha), **gruvbox** (warm retro amber/orange), **gruvbox-material** (Gruvbox Material Dark Soft — a lower-contrast, single cream-accent variant of **gruvbox**), **rosepine** (Rosé Pine — warm plum/rose/gold), and **latte** (Catppuccin Latte — the one light theme; sets a theme's optional `IsLight` key so `theme latte` also flips Windows into light mode, not just the app palette).
- **VSCode**: the `vscode/settings.json` overlay carries a marked `workbench.colorCustomizations` block that `theme` rewrites from the palette's `YasbPalette` (no theme extension required — only the editor *chrome* is recolored; syntax highlighting stays on whatever color theme you pick). `winsmooth -Apply` deep-merges the overlay into the live `%APPDATA%\Code\User\settings.json`, preserving your other settings; VSCode watches the file, so the chrome repaints instantly. Skip with `-SkipVSCode`.
- **Spotify**: `spicetify/win-dotfiles/` is a Spicetify theme with a `color.ini` section per palette plus a minimal `user.css`. `theme` (and `winsmooth -Apply`) point Spotify at the matching scheme via `tools/Apply-Spicetify.ps1` and run `spicetify apply`. Install Spicetify with `scoop install spicetify-cli` (in `packages/scoop.json`); the first time, run `spicetify backup apply` once (or `tools/Apply-Spicetify.ps1 -FirstRun`). It's a safe no-op when Spicetify/Spotify aren't installed. Skip with `-SkipSpicetify`.
- Desktop accent + wallpaper changes are captured in the `winsmooth` backup manifest, so `winsmooth -RestoreLast` reverts them.
- Wallpapers are committed under `wallpapers/`. Regenerate them after a palette change with `tools/Build-Wallpapers.ps1` (renders a gradient-from-palette image per theme; pass `-Width/-Height` to match a monitor).
- A `fastfetch` system banner with a custom `>_` logo and a rotating tip prints on interactive login (`powershell/profile.d/170-greeting.ps1`). Its key colors use ANSI names so the banner tracks the active theme. Suppress it with `$env:WINDOTFILES_GREETING = 'off'`.

## Disable built-in AI

- `windows\disable-ai.ps1` turns off Windows 11's built-in AI: removes the Copilot app and taskbar button, and disables Windows Recall, Click to Do, Windows Copilot, Edge Copilot (sidebar, page context, Compose), and AI in Search/Notepad. It self-elevates (machine policies live under HKLM); add `-RemoveRecallFeature` to also strip Recall as a Windows optional feature.
- `windows\enable-ai.ps1` reverses it: clears the policies and restores the per-user toggles to their AI-on defaults. It does not reinstall the Copilot app (use the Microsoft Store) and does not re-add the Recall feature if it was removed.
- Sign out or restart for the policy changes to take full effect. App-level generative features (Paint Cocreator, Photos generative fill) have no clean policy and are not covered.

## Diagnostics and debloat

- `windows\debloat.ps1` reduces diagnostics to a practical floor: sets `AllowTelemetry=1` (the lowest a Home/Pro SKU honors), disables the DiagTrack and dmwappushservice telemetry services, turns off Windows Error Reporting and the CEIP/feedback scheduled tasks, disables suggested content, and removes a few unwanted Store apps (GetHelp, Xbox overlays, Media Player). It self-elevates.
- `windows\rebloat.ps1` reverses everything except app removal: clears the policies, restores service start types, re-enables the scheduled tasks, and turns suggested content back on. Removed apps must be reinstalled from the Microsoft Store.
- Most privacy toggles (advertising ID, tailored experiences, Start/Settings suggestions) are already handled by `winsmooth`.
- `winharden` re-applies both hardening scripts in one pass (`disable-ai.ps1` + `debloat.ps1`); `winharden -Restore` runs the matching restores (`enable-ai.ps1` + `rebloat.ps1`). It opens a single elevated window when not already running as admin. Re-run it after a major Windows feature update, which can quietly re-enable some of these.

## Launcher and desktop comfort

- [Flow Launcher](https://www.flowlauncher.com) is the launcher, on `Alt+Space` (replacing PowerToys Run, which `winsmooth` disables). Install it with winget (`Flow-Launcher.Flow.Launcher`, in `packages/winget.json`) or scoop (`Flow-Launcher`); `winsmooth -Apply` installs the theme, binds `Alt+Space`, sets the Nerd Font, and enables autostart. It's palette-themed in lock-step with the rest of the rice: `flowlauncher/win-dotfiles.xaml` carries a marked brush block the `theme` command rewrites from each theme's `YasbPalette` (see [Theming](#theming)), and Flow hot-reloads its active theme file. Browse/install plugins from Flow's own store (`Ctrl+I` → Plugin Store). (`Win+Space` is not usable: Flow registers hotkeys via Win32 `RegisterHotKey`, and Windows permanently reserves `Win+Space` for the input-switcher. `Apply-FlowLauncher.ps1` also handles the scoop *portable* data root, not just `%APPDATA%\FlowLauncher`.)
- QuickLook owns file previews (`Space` on a selected file). Ditto starts with a conservative clipboard history profile: `Ctrl+Alt+V` activation, 300 entries, 14 days, multi-paste capture off, 5 MB max clip payload, and delete prompts on.

## Window manager

- Komorebi config lives in `komorebi/komorebi.json`; whkd keybindings live in `komorebi/whkdrc`.
- Default layouts favor ultrawide main-stack workspaces for DEV/CODE, columns for browser work, and append-to-stack rules once a workspace gets crowded.
- Popup handling keeps common dialogs, PowerToys overlays, browser PiP, and Teams call/notification overlays out of the tiling graph.
- Depth: focused windows wear a rounded accent border (`border_style: Rounded`, width 3, themed by `theme`); unfocused windows fade slightly translucent (`transparency`, alpha 220) with a smooth easing animation, echoing the frosted bars.
- `wmcheck` runs komorebi's config check.
- `wmdev`, `wmbrowse`, `wmfocus`, and `wmreset` apply common window-manager intents from the shell.
- `wmstart` starts `komorebi` with `whkd` using a clean state, and starts the Yasb bar alongside it.
- `wmstop` stops `komorebi` and `whkd` (restoring hidden windows) and stops the Yasb bar.
- Intent hotkeys: `Alt+Shift+D` DEV, `Alt+Shift+W` browser columns, `Alt+Shift+F` focus/monocle, `Alt+Shift+Z` reset config and retile.
- Layout hotkeys: `Alt+Shift+U` main-stack, `Alt+Shift+C` columns, `Alt+Shift+G` grid, `Alt+Shift+B` BSP, `Alt+Shift+S` stack all. Stackbars show only on stacks with compact title labels.

## Status bar (Yasb)

[Yasb](https://github.com/amnweb/yasb) is the primary status bar, replacing komorebi's built-in bar.

- Config lives in `yasb/config.yaml` (layout/widgets) and `yasb/styles.css` (look). `winsmooth -Apply`
  links both to `~/.config/yasb/` and enables Yasb autostart; `wmstart`/`wmstop` start/stop it with the
  window manager. Install it with winget (`AmN.yasb`, in `packages/winget.json`).
- Two asymmetric **frosted-glass** bars (real acrylic blur + slide animation), with running app icons
  on the komorebi workspace buttons. komorebi reserves the bar strip via `global_work_area_offset`
  (in `komorebi/komorebi.json`) so tiled windows never sit under the bar — the bars themselves don't
  register as Windows AppBars (one reservation, not two):
  - **Light bar** on the primary screen (`screens: ['primary']`, the Samsung ultrawide) — an ambient
    glance: workspaces, active layout, a centered clock, media (scrolling title + album-art popup), a
    Cava audio visualizer, volume, an on-brand active-theme indicator, and the date.
  - **Rich bar** on the other monitor (`screens: ['*']`, the smaller ASUS detail screen) — workspaces,
    layout, komorebi control, focused window; centered clock; then weather (°F), a collapsible system
    island (CPU / memory / GPU / disk / network traffic, color-coded by load), update counts,
    notifications, a do-not-disturb toggle, a power menu, and the date.
- Widgets are interactive: click **CPU / memory / GPU** for a usage-history graph popup, **disk** for a
  volumes list, **media** for transport controls, **volume** scrolls to change / clicks to mute. The
  **active-theme indicator** is a Custom widget that reads `themes/active.txt` (hard-codes the repo path)
  and updates within ~5 s of a `theme` switch.
- Colors are theme-driven: `styles.css` references CSS variables in a marked `:root` block that the
  `theme` command rewrites from each theme's `YasbPalette` (`themes/<name>.psd1`); Yasb hot-reloads, so
  switching themes repaints both bars live (CPU/mem/GPU/disk also use the `ok/warn/err` roles for load
  thresholds). Edit layout/shape in `config.yaml`/`styles.css`, edit colors in the themes.
- One-time setup: click the **weather** widget and search your location once (keyless Open-Meteo stores
  it locally — it can't be pre-seeded from config). If the **GPU** widget reads 0%, install/run Libre
  Hardware Monitor. The **Cava** visualizer needs the `cava` binary (`karlstav.cava`, in
  `packages/winget.json`); after installing it, fully **stop and start** Yasb (not reload) so it picks
  up `cava` on PATH.
- Komorebi workspace widgets need komorebi ≥ v0.18.0. Control the bar directly with
  `yasbc start|stop|reload`. The komorebi built-in bar (`komorebi/komorebi.bar.json`) is kept as an
  unlinked fallback — relink it and re-add `--bar` to komorebi autostart to switch back.

## Windhawk

[Windhawk](https://windhawk.net) applies runtime mods for window/title-bar styling and Explorer/context
menus. Install it with winget (`RamenSoftware.Windhawk`, in `packages/winget.json`).

- Windhawk mod settings live in the registry with no official export, so the repo tracks a documented
  mod list in `windhawk/mods.md` (curated mods + recommended settings) plus a scripted capture/restore:
  `windhawk/Export-Windhawk.ps1` snapshots your enabled mods, per-mod settings, and sources into
  `windhawk/state/`; `windhawk/Import-Windhawk.ps1` restores them (and `winsmooth -Apply` runs the
  import when `windhawk/state/` exists, skippable with `-SkipWindhawk`). Both self-elevate; import backs
  up the prior state under `%LOCALAPPDATA%\win-dotfiles\windhawk-backups` first. It's best-effort —
  re-run the export after changing your mod set. `wincheck` reports whether Windhawk is installed.
- Most mods apply to newly drawn windows, so restart Explorer (or reboot) after enabling them.
- The mods either ride the Windows accent that `theme` already sets on title bars (so they follow theme
  switches for free) or take explicit colors — see `windhawk/mods.md` for which and the per-theme hex.

## Context menu (Nilesoft Shell)

[Nilesoft Shell](https://nilesoft.org) re-skins the Windows right-click context menu. Install it with winget
(`Nilesoft.Shell`, in `packages/winget.json`), then run `shell -register -restart` once from an elevated prompt.

- It's palette-themed in lock-step with the rest of the rice: `nilesoft-shell/theme.nss` carries a marked
  `theme{}` block the `theme` command rewrites from each theme's `YasbPalette` (same pattern as Flow Launcher's
  XAML brushes). `winsmooth -Apply` (and every `theme <name>` switch) runs `tools/Apply-NileSoftShell.ps1`,
  which stages the rewritten file into the installed Shell's `imports\theme.nss`. It's a safe no-op when
  Nilesoft Shell isn't installed. Skip with `-SkipNileSoftShell`.
- Unlike Yasb, Nilesoft Shell doesn't hot-reload `shell.nss` on save: reload it by holding right-click then
  left-click on the desktop, or restart Explorer (`tools/Apply-NileSoftShell.ps1 -Restart` does the latter for
  you — used sparingly, since it's disruptive if run on every theme switch).

## Workflow helpers

- `cmds` / `mycmds` shows a grouped catalog of custom commands; use `cmds git` or `cmds -Search deploy` to filter it.
- `nr` fuzzy-picks or runs npm scripts from the nearest `package.json`.
- `verify` runs the best available project check: npm `verify`/`test`/`build`, then .NET test/build.
- `gmain`, `gnew`, `gsync`, `gpub`, and `gprune` cover common Git branch chores.
- `gitlocks` shows Git `index.lock` files; `gunlock` clears a stale current-repo lock, and `gunlock -All` scans known project roots. In Codex, `gunlock` will call out when the sandbox requires an escalated rerun for `.git` metadata writes.
- `td` calculates one or more time ranges, with clock and decimal-hour output.
- `awslambda`, `awslogs`, `fbdeploy`, `fbemu`, `stripelisten`, and `stripetrigger` wrap common cloud CLI commands with visible context.
- `histdoctor` summarizes unavailable commands from PowerShell history without printing raw history lines.
- `workon` jumps to a project, records the last selection, and runs `git status`.
- Native tab completion is wired for `gh`, `winget`, `dotnet`, and `rustup` (plus `scoop`/`git` when `scoop-completion`/`posh-git` are installed). `gh` and `rustup` completion scripts are cached under the cache root; run `Update-WinDotfilesCompletions` after upgrading those tools. (`npm` has no native PowerShell completion — use `nr`.)
- `gitdefaults` sets friction-reducing global Git defaults only when unset: `rebase.autostash`, `push.autoSetupRemote`, `fetch.prune`, `help.autocorrect=prompt`.
- `mkcd <dir>` creates a directory and enters it; `touch <file>` creates or bumps a file.
- `proj-audit` reports, per registered project, whether it has a README, `.gitignore`, `.editorconfig`, `.nvmrc` (Node), and a `verify`/`test`/`build` script (Node). `scaffold <editorconfig|gitignore|readme>` copies the matching template from `templates/` into the current (or `-Path`) project on demand.

## License

[MIT](LICENSE)
