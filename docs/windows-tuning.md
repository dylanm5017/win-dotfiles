# Windows tuning

Host-level changes: responsiveness and shell defaults (`winsmooth`), the built-in AI opt-out, and
diagnostics/debloat. Everything here is reversible — `winsmooth` backs up what it touches, and the
`windows/` scripts each ship a matching restore.

## Workstation tuning

- `wincheck` reports Windows friction across profile timing, project cache lookup, startup apps, Defender, search/indexing, services, launcher roles, comfort tools, PowerToys, Terminal profiles, WSL/Docker-adjacent processes, and komorebi/whkd.
- `wincheck -Detailed` includes slower profile scripts, enabled PowerToys modules, and top memory users.
- `winsmooth` previews reversible host tuning; `winsmooth -Apply` backs up touched settings under `C:\Workspace\Dev\Cache\win-dotfiles\workstation-backups` before applying them.
- `winsmooth -RestoreLast` restores the most recent workstation tuning backup.
- `winsmooth -Apply` trims PowerToys so komorebi owns tiling, disables PowerToys Run in favor of Flow Launcher on `Alt+Space` (themed + autostarted), makes Everything the primary file search path, limits duplicate Windows Search/folder result volume, starts/autostarts QuickLook/EarTrumpet/Ditto, applies bounded Ditto history, cleans Windows Terminal profiles, links repo-managed komorebi/whkd config, marks dev roots as not content indexed, and tries to add Defender path exclusions.
- Run `winsmooth -Apply` from an elevated shell when you want Defender exclusions to be added; Defender stays enabled and only path exclusions are used.
- `winsmooth -Apply` also tunes OS responsiveness: kills shell animations (menu/window/taskbar), sets a raw 1:1 pointer and the fastest key repeat, and activates a high-performance power plan (Ultimate Performance, no USB suspend or core parking). Skip it with `winsmooth -Apply -SkipResponsiveness`; window animations fully clear after an `explorer.exe` restart or sign-out, and the `wincheck` `Responsiveness` row reports the current state.
- `winsmooth -Apply` declutters Windows shell defaults: shows file extensions and hidden files, cleans the taskbar (hides Widgets, Chat, Task View, and the search box), disables Start menu web results, opens Explorer to This PC, and enables long-path support. It restarts `explorer.exe` to apply them; skip with `winsmooth -Apply -SkipShellDefaults`. The `wincheck` `Desktop` row reports shell-default and Yasb bar state. (Light/dark mode is set separately, by the active theme — see [Theming](theming.md).)
- `winsmooth -Apply` links the repo `yasb/` status bar config (`config.yaml` + `styles.css`) to `~/.config/yasb`, enables Yasb autostart, and starts the bar; komorebi autostarts with `--whkd` only (Yasb is the bar now, so no `--bar`). The Yasb island shows per-monitor komorebi workspaces, the active layout, the focused window, now-playing media, CPU/memory, and a centered clock, themed to match the active theme (see [Theming](theming.md)) with `CaskaydiaCove NF` glyphs. After applying, run `wmstop; wmstart` once (or reboot) so komorebi + Yasb relaunch together. It also auto-hides the Windows taskbar (Yasb is primary; the tray reveals on hover). Skip the bar step with `-SkipYasb`. The previous komorebi built-in bar (`komorebi/komorebi.bar.json`) stays in the repo as an unlinked fallback.
- `winsmooth -Apply` also extends the active theme to two app surfaces: it deep-merges the VSCode overlay (`vscode/settings.json`) into the live editor settings (palette-driven workbench chrome; `-SkipVSCode`) and themes Spotify via Spicetify from the active palette (`-SkipSpicetify`, no-op when Spicetify is absent). See [Theming](theming.md).
- `winsmooth -Apply -DeepWork` also disables Teams and Slack startup entries; the default balanced profile leaves work comms alone.
- `winsmooth -Apply` applies the active desktop theme (window accent color, Windows light/dark mode from the theme's `IsLight` flag, and generated wallpaper) and links the fastfetch banner config. Skip with `winsmooth -Apply -SkipDesktopTheme`. The accent on title bars fully applies after sign-out.

## Disable built-in AI

- `windows\disable-ai.ps1` turns off Windows 11's built-in AI: removes the Copilot app and taskbar button, and disables Windows Recall, Click to Do, Windows Copilot, Edge Copilot (sidebar, page context, Compose), and AI in Search/Notepad. It self-elevates (machine policies live under HKLM); add `-RemoveRecallFeature` to also strip Recall as a Windows optional feature.
- `windows\enable-ai.ps1` reverses it: clears the policies and restores the per-user toggles to their AI-on defaults. It does not reinstall the Copilot app (use the Microsoft Store) and does not re-add the Recall feature if it was removed.
- Sign out or restart for the policy changes to take full effect. App-level generative features (Paint Cocreator, Photos generative fill) have no clean policy and are not covered.

## Diagnostics and debloat

- `windows\debloat.ps1` reduces diagnostics to a practical floor: sets `AllowTelemetry=1` (the lowest a Home/Pro SKU honors), disables the DiagTrack and dmwappushservice telemetry services, turns off Windows Error Reporting and the CEIP/feedback scheduled tasks, disables suggested content, and removes a few unwanted Store apps (GetHelp, Xbox overlays, Media Player). It self-elevates.
- `windows\rebloat.ps1` reverses everything except app removal: clears the policies, restores service start types, re-enables the scheduled tasks, and turns suggested content back on. Removed apps must be reinstalled from the Microsoft Store.
- Most privacy toggles (advertising ID, tailored experiences, Start/Settings suggestions) are already handled by `winsmooth`.
- `winharden` re-applies both hardening scripts in one pass (`disable-ai.ps1` + `debloat.ps1`); `winharden -Restore` runs the matching restores (`enable-ai.ps1` + `rebloat.ps1`). It opens a single elevated window when not already running as admin. Re-run it after a major Windows feature update, which can quietly re-enable some of these.
