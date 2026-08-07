# Desktop shell

The status bar, launcher, runtime window mods, and context menu — everything around the window
manager itself. See [window-manager.md](window-manager.md) for komorebi and [theming.md](theming.md)
for how the palette reaches these surfaces.

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
- **Workaround — workspace clicks die after the displays sleep.** Windows reissues HMONITOR handles
  on wake, but Yasb caches its bar's handle once at startup and never recomputes it, so the komorebi
  workspace widget can no longer resolve its screen and every click throws
  `TypeError: 'NoneType' object is not subscriptable` into `~/.config/yasb/yasb.log`. komorebi is
  fine here — only Yasb needs restarting. `tools/Reload-YasbOnWake.ps1 -Register` installs a
  scheduled task that runs `yasbc reload` on the wake edge (Kernel-Power 566 filtered to
  `NextSessionType=0`, plus 107 for a full resume); `-Status` shows recent reloads, `-Unregister`
  removes it. Confirmed against Yasb v2.0.5 and reported upstream as
  [amnweb/yasb#1053](https://github.com/amnweb/yasb/issues/1053) — drop the task once that ships.

## Launcher and desktop comfort

- [Flow Launcher](https://www.flowlauncher.com) is the launcher, on `Alt+Space` (replacing PowerToys Run, which `winsmooth` disables). Install it with winget (`Flow-Launcher.Flow.Launcher`, in `packages/winget.json`) or scoop (`Flow-Launcher`); `winsmooth -Apply` installs the theme, binds `Alt+Space`, sets the Nerd Font, and enables autostart. It's palette-themed in lock-step with the rest of the rice: `flowlauncher/win-dotfiles.xaml` carries a marked brush block the `theme` command rewrites from each theme's `YasbPalette` (see [Theming](theming.md)), and Flow hot-reloads its active theme file. Browse/install plugins from Flow's own store (`Ctrl+I` → Plugin Store). (`Win+Space` is not usable: Flow registers hotkeys via Win32 `RegisterHotKey`, and Windows permanently reserves `Win+Space` for the input-switcher. `Apply-FlowLauncher.ps1` also handles the scoop *portable* data root, not just `%APPDATA%\FlowLauncher`.)
- QuickLook owns file previews (`Space` on a selected file). Ditto starts with a conservative clipboard history profile: `Ctrl+Alt+V` activation, 300 entries, 14 days, multi-paste capture off, 5 MB max clip payload, and delete prompts on.

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
