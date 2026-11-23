# Window manager (komorebi)

- Komorebi config lives in `komorebi/komorebi.json`; whkd keybindings live in `komorebi/whkdrc`.
- Popup handling keeps common dialogs, PowerToys overlays, browser PiP, and Teams call/notification overlays out of the tiling graph.
- Depth: focused windows wear a rounded accent border (`border_style: Rounded`, width 2, themed by `theme`) with a smooth easing animation on movement. Transparency is configured but left off — it breaks tiling for layered apps (Firefox, Windows Terminal).

## Workspaces

Nine named workspaces across two monitors. The **AOC** (2560x1440 OLED, Windows primary, straight ahead) is
the focus screen and holds the six work workspaces. The **Samsung ultrawide** (5120x1440, on an arm to the
left and slightly behind) is a side screen for things you glance at while they run in the background.
`Alt+<digit>` is **monitor-agnostic**: komorebi focuses the owning monitor first, so one keypress crosses
displays and there is no separate "switch monitor" step in normal use.

| Key | Workspace | Monitor | Layout | Visible tiles |
| --- | --- | --- | --- | --- |
| `Alt+1` | DEV | AOC | vertical stack (0.55 main) | 3 |
| `Alt+2` | CODE | AOC | vertical stack (0.55 main) | 3 |
| `Alt+3` | AGENT | AOC | columns | 3 |
| `Alt+4` | DEBUG | AOC | vertical stack (0.55 main) | 3 |
| `Alt+5` | BROWSER | AOC | columns | 2 |
| `Alt+6` | MISC | AOC | scrolling | 2 at a time |
| `Alt+7` | COMMS | ultrawide | columns | 3 |
| `Alt+9` | MAIL | ultrawide | right-main stack (0.5 main) | 3 |
| `Alt+0` | OFFICE | ultrawide | right-main stack (0.5 main) | 3 |

The ultrawide sits to your left, so its right edge is closest to your line of sight. MAIL and OFFICE
put their main tile on the **right** (`RightMainVerticalStack`) so the window you read is nearest
the AOC.

**Side dock.** The ultrawide's far-left 2304px is reserved for apps you want up all the time but
rarely look at. They stay visible on every workspace without being tiled. Furthest out (the hardest
spot to look at) is a 1280px column with YouTube Music on top (60%) and Elgato Wave Link below.
Keeping Wave Link open also avoids the "only system audio" fault, where app audio goes silent until
its window is opened. Next to that, closer to the middle, is a 1024px **watch terminal** for dev
servers, log tails and long builds: a WezTerm window started with `--class wezterm-watch`.

Three pieces work together: `ignore_rules` keeps komorebi away from these windows (so it never
hides them on a workspace switch); the ultrawide's `work_area_offset` (`left`/`right` 2304) keeps
tiles out of the strip; and `tools/Set-SideDock.ps1` puts each window in its slot. A logon task
(registered by `winsmooth -Apply`) and `wmstart` run it with `-Launch`, which starts any that are missing. `Win+Y` docks and focuses music, and `Alt+8`
(which used to be MEDIA) docks and focuses the watch terminal. If you change a width, change it in both
`komorebi.json` and the script's `-MediaWidth`/`-WatchWidth`.

Windows places the ultrawide left of the AOC in the display arrangement too (X=-5120),
so the cursor crosses on the physical edge. If a driver reset puts it back on the right, drag it
back in Settings > Display.

- `Alt+Shift+<digit>` moves the focused window there and follows it; `Ctrl+Alt+<digit>` shoves it
  there and stays put — that second one is the "this workspace is getting crowded" gesture.
- `Alt+` `` ` `` jumps to the last workspace, `Alt+Shift+` `` ` `` moves a window to it.
- Tile counts are ceilings derived from minimum usable width on each panel. Past the ceiling
  komorebi appends into a stack rather than slicing thinner; `Alt+;` unstacks one, `Alt+Shift+;`
  unstacks all, and `Alt+[` / `Alt+]` cycle within a stack.
- MISC uses the **scrolling** layout instead of a ceiling: a fixed number of columns stays
  visible and the rest scroll off-screen, so an overflow workspace never degenerates into slivers or
  a wall of tabs. `Alt+Shift+N` switches any workspace to it.
- Monocle is deliberately unbound. `wmfocus` promotes the focused window to the primary tile
  instead, so the rest of the workspace stays visible.
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
| MISC | — | Notion, Notepad++, WinMerge, WinSCP |
| COMMS | Slack, Discord | Teams, Zoom |
| MAIL | — | Outlook (classic and new) |
| OFFICE | — | Word, Excel, PowerPoint, OneNote, Visio |

Teams and Zoom are seeded rather than pinned on purpose: meetings and screen-share often want the
AOC in front of you, and a pinned rule would drag them back mid-call. Meeting/call popups are separately kept
out of the tiling graph by `ignore_rules`.

Matching is on executable name and is **case-sensitive** (`matching_strategy: Equals`) — there is no
case-insensitive option, so a rule with the wrong casing silently never fires. Office ships its
classic executables in **upper case** (`WINWORD.EXE`, `EXCEL.EXE`, `POWERPNT.EXE`, `ONENOTE.EXE`,
`VISIO.EXE`, `OUTLOOK.EXE`) and the rules must match that exactly. A `Regex` rule with `(?i)` looks
like it should paper over this but was tested and **does not fire** for `Exe` rules on v0.1.41 —
use `Equals` with the on-disk casing (check with `Get-ChildItem 'C:\Program
Files\Microsoft Office\root\Office16\*.exe'`). New Outlook is separately routed as `olk.exe`, which
really is lower case.

Monitors are pinned in `display_index_preferences` by **`device_id`**, not serial number. Some panels
report its `serial_number_id` intermittently — when it comes back `null`, a serial-keyed mapping
stops resolving and that monitor silently falls back to unnamed default workspaces, which breaks the
`Alt+7`–`Alt+0` binds. `device_id` is tied to the physical port and does not have this problem.
Check with `komorebic monitor-information` if a monitor's workspaces ever come up unnamed.

## Shell and layout commands

- `wmcheck` runs komorebi's config check, then reports whether komorebi/whkd run elevated and whether each
  `display_index_preferences` ID is connected with its workspaces; `wmreset` reloads `komorebi.json` and retiles.
- `agentboard` lists the Claude Code sessions on this machine: needs you, done, or working, and for how long.
  `agentboard -Dock` opens it as a strip at the top of the watch terminal, which the side dock does by itself
  whenever it starts that terminal (sign-in, `Alt+8`, `wmstart`). It reads `~/.claude/sessions`, an
  internal format, so a state it doesn't recognise shows as `unknown`; `claude agents --json` is the supported view.
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
| `Win+Y` | YouTube Music (docks into the side dock instead of raising — see Workspaces) |
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
