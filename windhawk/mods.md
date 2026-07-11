# Windhawk mods

[Windhawk](https://windhawk.net) ("the customization marketplace for Windows") runs small mods that
patch Windows UI/behavior at runtime. It is installed declaratively via winget
(`RamenSoftware.Windhawk`, in `packages/winget.json`), but **its mod settings live in the registry and
`%ProgramData%\Windhawk`, with no official export** — so this file is the source of truth: the curated
mod list + recommended settings, applied once from the Windhawk UI.

## How to apply

1. Install Windhawk: `winget install RamenSoftware.Windhawk` (or run `install.ps1` / `winget import`).
2. Open **Windhawk → Explore**, search each mod by name below, click **Install**.
3. Open the mod's **Settings** tab and set the recommended options.
4. **Restart Explorer to see the changes** — most mods (context menus, dark menus, title-bar/DWM)
   apply to *newly drawn* windows only. Run `Stop-Process -Name explorer -Force` (it relaunches) and
   reopen affected windows, or just reboot. If you enabled a mod and "nothing happened", this is why.
5. `wincheck` shows a **Customization / Windhawk** row once it's installed.

## Capturing & restoring your setup (scripted)

Windhawk settings live in the registry + `%ProgramData%\Windhawk` with no official export, so the repo
captures the mod-relevant state into `windhawk/state/` via two helper scripts (both self-elevate):

- **`windhawk\Export-Windhawk.ps1`** — after configuring mods in the UI, run this to snapshot the
  enabled mods, their per-mod settings (registry), and the mod sources into `windhawk/state/`
  (`registry/*.reg`, `ModsSource/*.wh.cpp`, `manifest.json`). Review the diff and commit it. Add
  `-IncludeCompiled` to also capture the compiled DLLs for an exact, no-recompile same-machine restore
  (larger + architecture/version specific; off by default).
- **`windhawk\Import-Windhawk.ps1`** — restores `windhawk/state/` onto a machine (sources + enable
  state + settings), backing up the current state to `%LOCALAPPDATA%\win-dotfiles\windhawk-backups`
  first, then restarting Explorer. `winsmooth -Apply` runs this automatically when `windhawk/state/`
  exists (skip with `-SkipWindhawk`). Without captured binaries, Windhawk recompiles each mod from its
  source on first launch — open Windhawk once (or reboot) to let it finish.

> Best-effort by design: mod settings schemas can change across mod/Windhawk updates, so re-run
> `Export-Windhawk.ps1` after you change your mod set. The curated list below is still the human-readable
> source of truth for *which* mods and *why*.

## Theme alignment

The win-dotfiles `theme` command already applies the active palette's **accent color to title bars**
(DWM `ColorPrevalence`), so window chrome tracks `theme <name>` for free. The mods below either ride
that system accent (no per-theme work) or take explicit colors — for those, use the active theme's
`Accent` hex (see `themes/<name>.psd1`): mocha `#CBA6F7`, ashes `#95AEC7`, dracula `#BD93F9`,
nord `#88C0D0`. Windhawk has no palette concept, so explicit-color mods are not auto-switched; prefer
the accent-riding mods if you want zero maintenance across theme switches.

> **Light theme (`latte`) caveat:** a couple of mods below are dark-specific and will look wrong (or
> outright fight the OS) once `theme latte` puts Windows in light mode — see the "Immersive Dark Mode"
> and "Dark mode context menus" rows. Windhawk mod state isn't part of the automated theme-switch
> pipeline (no live-reapply hook, same limitation as everything else in this file), so reconsider/disable
> those two manually from the Windhawk UI when switching to a light theme.

---

## Window / title-bar styling

| Mod | id | Why | Recommended |
|-----|----|-----|-------------|
| **Windows 11 Accent Window Border** | `win11-accent-border` | Puts the accent on the window border only. Rides the system accent, so it follows `theme` automatically. | Install as-is. Pairs cleanly with komorebi's own focus border. |
| **Windows 11 Custom Title Bar Colours** | `win11-custom-title-bar-colours` | Explicit active/inactive title-bar colors + Immersive Dark Mode toggle, for finer control than the OS accent. | Enable Immersive Dark Mode. If setting colors, use the active theme `Accent` hex (update on theme switch). **On `latte`:** disable Immersive Dark Mode. |
| **Center Titlebar** | `center-titlebar` | Centers title-bar text — subtle polish that matches the centered Yasb clock. | Install as-is. |
| **Window Border Customizer** *(optional)* | `window-border-customizer` | Replaces DWM borders with custom ARGB translucent borders. Use only if `win11-accent-border` isn't enough. | Thin border; translucent alpha to match the Yasb island feel. Manual color. |
| **Disable rounded corners** *(optional)* | `disable-rounded-corners` | Squares off Win11 corners for a sharper tiling look. Taste-dependent. | Off by default — enable only if you prefer hard corners. |

> Note: the desktop already auto-hides the taskbar (Yasb is primary), so taskbar-styling mods
> (`windows-11-taskbar-styler`, etc.) are intentionally **not** used here.

## Explorer + context menus

| Mod | id | Why | Recommended |
|-----|----|-----|-------------|
| **Disable Immersive Context Menus** | `disable-immersive-context-menus` | Restores the fast classic (Win10-style) right-click menu in File Explorer — no "Show more options" second hop. | Install as-is. |
| **Dark mode context menus** | `dark-menus` | Forces dark mode on all win32 menus, so the classic menus above match the dark desktop. | Install as-is. **On `latte`:** disable it — it'll force-darken menus against a light desktop otherwise. |
| **Remove Context Menu Items** *(optional)* | `remove-context-menu-items` | Trims unwanted entries from file context menus (configurable). | Remove only noise you don't use (e.g. vendor "Share"/cloud entries). |
| **Windows 11 File Explorer Styler** *(optional)* | `windows-11-file-explorer-styler` | Theme File Explorer chrome via community themes or your own rules. Most involved — opt in if you want Explorer to match the palette. | Start from a dark community theme; adjust accents to the active theme `Accent`. |
| **Classic Explorer Treeview** *(optional)* | `classic-explorer-treeview` | Makes the Explorer folder treeview look more classic. | Taste-dependent. |

---

## Notes

- Settings are not version-controlled by design (Windhawk has no official export). This list is the
  source of truth; re-apply from the UI after a clean install or a major Windows feature update.
- A scripted registry import (`HKLM\SOFTWARE\Windhawk` + `%ProgramData%\Windhawk`) was considered and
  declined — it's brittle when mods change their settings schema across updates.
