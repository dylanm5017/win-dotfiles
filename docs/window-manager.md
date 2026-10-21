# Window manager (komorebi)

- Komorebi config lives in `komorebi/komorebi.json`; whkd keybindings live in `komorebi/whkdrc`.
- Popup handling keeps common dialogs, PowerToys overlays, browser PiP, and Teams call/notification overlays out of the tiling graph.
- Depth: focused windows wear a rounded accent border (`border_style: Rounded`, width 3, themed by `theme`) with a smooth easing animation on movement. Transparency is configured but left off — it breaks tiling for layered apps (Firefox, Windows Terminal).

## Workspaces

Ten named workspaces, six on the ultrawide and four on the secondary (a 1080x1920 portrait panel to the right of the ultrawide). `Alt+<digit>` is
**monitor-agnostic**: komorebi focuses the owning monitor first, so one keypress crosses displays and
there is no separate "switch monitor" step in normal use.

| Key | Workspace | Monitor | Layout | Visible tiles |
| --- | --- | --- | --- | --- |
| `Alt+1` | DEV | ultrawide | ultrawide main-stack | 5 |
| `Alt+2` | CODE | ultrawide | ultrawide main-stack | 5 |
| `Alt+3` | AGENT | ultrawide | columns | 4 |
| `Alt+4` | DEBUG | ultrawide | ultrawide main-stack | 5 |
| `Alt+5` | BROWSER | ultrawide | columns | 4 |
| `Alt+6` | MISC | ultrawide | scrolling | 4 at a time |
| `Alt+7` | COMMS | secondary | rows | 3 |
| `Alt+8` | MEDIA | secondary | horizontal stack | 2 |
| `Alt+9` | MAIL | secondary | horizontal stack | 2 |
| `Alt+0` | OFFICE | secondary | rows | 2 |

- `Alt+Shift+<digit>` moves the focused window there and follows it; `Ctrl+Alt+<digit>` shoves it
  there and stays put — that second one is the "this workspace is getting crowded" gesture.
- `Alt+` `` ` `` jumps to the last workspace, `Alt+Shift+` `` ` `` moves a window to it.
- Tile counts are ceilings derived from minimum usable width on a 5120x1440 panel (and minimum
  usable height on the portrait secondary, which only ever splits top-to-bottom). Past the ceiling
  komorebi appends into a stack rather than slicing thinner; `Alt+;` unstacks one, `Alt+Shift+;`
  unstacks all, and `Alt+[` / `Alt+]` cycle within a stack.
- MISC uses the **scrolling** layout instead of a ceiling: a fixed number of columns stays
  visible and the rest scroll off-screen, so an overflow workspace never degenerates into slivers or
  a wall of tabs. `Alt+Shift+N` switches any workspace to it.
- Monocle is deliberately unbound — one window on a 32:9 panel wastes it. `wmfocus` promotes the
  focused window to the primary tile instead.
- Positional fallbacks: `Alt+,` / `Alt+.` focus a monitor directly, `Alt+←` / `Alt+→` cycle monitors,
  `Alt+↑` / `Alt+↓` cycle workspaces.

## App routing

Apps land on the right workspace on their own. There are two rule types and the difference matters:

- **Pinned** (`workspace_rules`) — komorebi sends the window back every time it sees it. You cannot
  keep it elsewhere. For single-home apps you never deliberately relocate.
- **Seeded** (`initial_workspace_rules`) — fires once, the first time the window appears. After that
  the window is yours: move it anywhere and it stays. For anything whose content you might sometimes
  want on the big screen.

| Workspace | Pinned | Seeded |
| --- | --- | --- |
| DEV | — | WezTerm, Windows Terminal, VS Code, Visual Studio |
| AGENT | — | Codex |
| DEBUG | — | MySQL Workbench, DBeaver, MongoDB Compass, SSMS, Postman, Citrix Workspace, Docker Desktop |
| BROWSER | — | Firefox, Chrome, Edge, Vivaldi |
| MISC | Elgato Wave Link | Notion, Notepad++, WinMerge, WinSCP |
| COMMS | Slack, Discord | Teams, Zoom |
| MEDIA | Spotify, YouTube Music | — |
| MAIL | — | Outlook (classic and new) |
| OFFICE | — | Word, Excel, PowerPoint, OneNote, Visio |

Teams and Zoom are seeded rather than pinned on purpose: meetings and screen-share often want the
ultrawide, and a pinned rule would drag them back mid-call. Meeting/call popups are separately kept
out of the tiling graph by `ignore_rules`.

Matching is on executable name and is **case-sensitive** (`matching_strategy: Equals`) — there is no
case-insensitive option, so a rule with the wrong casing silently never fires. Office ships its
classic executables in **upper case** (`WINWORD.EXE`, `EXCEL.EXE`, `POWERPNT.EXE`, `ONENOTE.EXE`,
`VISIO.EXE`, `OUTLOOK.EXE`) and the rules must match that exactly. A `Regex` rule with `(?i)` looks
like it should paper over this but was tested and **does not fire** for `Exe` rules on v0.1.41 —
use `Equals` with the on-disk casing (check with `Get-ChildItem 'C:\Program
Files\Microsoft Office\root\Office16\*.exe'`). New Outlook is separately routed as `olk.exe`, which
really is lower case.

Monitors are pinned in `display_index_preferences` by **`device_id`**, not serial number. The ASUS
reports its `serial_number_id` intermittently — when it comes back `null`, a serial-keyed mapping
stops resolving and that monitor silently falls back to unnamed default workspaces, which breaks the
`Alt+7`–`Alt+0` binds. `device_id` is tied to the physical port and does not have this problem.
Check with `komorebic monitor-information` if a monitor's workspaces ever come up unnamed.

## Shell and layout commands

- `wmcheck` runs komorebi's config check; `wmreset` reloads `komorebi.json` and retiles.
- `wmdev`, `wmbrowse`, and `wmfocus` apply common intents; `wmws <NAME>` jumps to a workspace by name.
- `wmstart` starts `komorebi` with `whkd` using a clean state, and starts the Yasb bar alongside it.
- `wmstop` stops `komorebi` and `whkd` (restoring hidden windows) and stops the Yasb bar.
- Layout hotkeys: `Alt+Shift+U` ultrawide main-stack, `Alt+Shift+C` columns, `Alt+Shift+G` grid,
  `Alt+Shift+V` vertical stack, `Alt+Shift+N` scrolling, `Alt+Shift+B` BSP. Stackbars show only on
  stacks, with compact title labels.
- `Alt+Shift+O` reloads `komorebi.json` — this is also the **undo for layout experiments**: it resets
  every workspace to its configured layout, so trying `Alt+Shift+C`/`N`/`V` on a workspace is always
  one keypress from reversible. `wmreset` does the same from the shell. Note komorebi's
  `reload-configuration` only handles legacy `.ahk`/`.ps1` configs — a static `komorebi.json` needs
  `replace-configuration`.
- The `Alt+Shift+<layout>` keys act on the **focused** workspace only. If a layout key seems to do
  nothing, focus is elsewhere — komorebi changed that workspace instead, silently. To retarget a
  specific workspace regardless of focus, use `komorebic named-workspace-layout <NAME> <layout>`.

## Raise or launch

The Hyprland habit of "focus it if it's already open, otherwise start it", ported to Windows.
`Win+B` goes to the browser you already have rather than opening a second one; press it again to
cycle that app's other windows. `raise browser` does the same thing from the shell.

| Key | App |
| --- | --- |
| `Win+B` | browser (Chrome) |
| `Win+C` | VS Code |
| `Win+T` | terminal (WezTerm, else Windows Terminal) |
| `Win+M` | Teams |
| `Win+Y` | YouTube Music |
| `Win+E` | File Explorer |

- The apps and their launch commands live in `powershell/apps.json`; add machine-specific ones to
  the gitignored `powershell/apps.local.json`, which is merged over the committed set so it only
  has to carry what it changes. `apps` lists what's registered. Entries match on executable name
  and can add a `title` regex when one exe serves several apps; packaged apps that reinstall into
  versioned directories (Slack, YouTube Music) launch via a stable `shell:AppsFolder\…` ID.
- `raise <name>` accepts a name, an alias, or an unambiguous prefix (`raise brow`), and falls back
  to treating an unknown `something.exe` as an ad-hoc match. `-NoLaunch` raises without ever
  starting the app, `-NoCycle` pins to the first match, and `-Exe`/`-Title` match windows directly
  without a registry entry.
- Window discovery goes through `komorebic state`, so a match on an inactive workspace is reached
  by focusing that workspace first, and a window buried in a stack is surfaced with
  `focus-stack-window` rather than by handle — both cases a plain `SetForegroundWindow` cannot
  reach, because komorebi hides those windows. Without komorebi running it degrades to
  `Get-Process` main windows, which only sees one window per process.
- `Win+<letter>` rather than `Alt+<letter>` because whkd grabs a combo globally: an `Alt+F`
  binding would shadow the File menu in every app. These do override the Windows defaults for the
  same keys (`Win+E` still opens Explorer, just via raise-or-launch).
- The hotkeys and the shell command run the same `tools/Raise-App.ps1`, so they can't disagree
  about what `browser` means. whkd pipes bindings into one long-lived PowerShell session rather
  than spawning a process per keypress, so the script's interop type is compiled once per whkd
  session and a warm press costs about 70 ms. That is also why it stays Windows PowerShell 5.1
  compatible and never touches the profile.
- Editing `komorebi/whkdrc` needs a whkd reload (`Alt+O`) before new bindings take effect.
