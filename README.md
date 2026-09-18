# Windows Dotfiles

Personal Windows 11 desktop, version-controlled end to end — tiling window manager, status bar,
PowerShell profile, and a single palette that themes all of it in lock-step.

One command rebuilds the machine; one command (`theme mocha`) recolors the terminal, prompt, window
borders, status bar, editor chrome, Spotify, launcher, context menu, and desktop wallpaper together.

## The stack

| Layer | What | Config |
| --- | --- | --- |
| Window manager | [komorebi](https://github.com/LGUG2Z/komorebi) + whkd — 10 named workspaces, monitor-agnostic binds | `komorebi/` |
| Status bar | [Yasb](https://github.com/amnweb/yasb) — two asymmetric frosted-glass bars | `yasb/` |
| Shell | PowerShell 7, modular `profile.d/` loader, [Starship](https://starship.rs) prompt | `powershell/`, `starship.toml` |
| Terminal | Windows Terminal (overlay-merged) + WezTerm (workspaces, shell integration) | `terminal/` |
| Launcher | [Flow Launcher](https://www.flowlauncher.com) on `Alt+Space`, palette-themed | `flowlauncher/` |
| Theming | 10 palettes driving every surface from one `.psd1` | `themes/`, `wallpapers/` |
| Windows itself | Runtime mods, re-skinned context menu, host tuning + debloat | `windhawk/`, `nilesoft-shell/`, `windows/` |
| Packages | Scoop + winget manifests, idempotent bootstrap | `packages/`, `install.ps1` |

## Quick start

```powershell
git clone git@github.com:dylanm5017/win-dotfiles.git
cd win-dotfiles
./install.ps1        # run elevated so the elevated-only tuning applies
```

`install.ps1` is idempotent — safe to re-run. It installs the Scoop and winget package sets, links
the PowerShell profile, then runs `winsmooth -Apply` (which links the komorebi/terminal/WezTerm/Yasb
configs and tunes the host).

- Switches: `-SkipScoop`, `-SkipWinget`, `-SkipFonts`, `-SkipWinsmooth`.
- `packages/scoop.json` is the Scoop manifest (buckets + apps); `packages/winget.json` is a curated
  winget set (toolchain + the comfort apps `winsmooth` manages, minus machine-specific noise).
  `scoop import packages/scoop.json` / `winget import packages/winget.json` re-create them.
- **Scope**: the manifests declare the toolchain, the desktop shell stack, and the apps this repo
  actually drives — Spotify (themed via Spicetify) and the raise-or-launch targets in
  `powershell/apps.json`. Everything else is installed by hand and merely *routed*: komorebi has
  workspace rules for DBeaver, Postman, SSMS, Teams, Zoom, Citrix and friends, and a rule for an
  app that isn't installed is a harmless no-op. Don't read the komorebi rules as an install list.
- Each app belongs to exactly one manager. Flow Launcher and Nilesoft Shell are scoop, not winget,
  even though both publish to winget — declaring an app twice means `install.ps1` installs it twice
  from two sources.
- `pkgsync` (alias `pkglist`) refreshes `packages/scoop.json` from what is currently installed,
  keeping the clean shape so diffs stay meaningful. `winget.json` is hand-curated and left alone.
  A couple of scoop entries (`CascadiaCode-NF`, `spicetify-cli`) are the documented bootstrap path
  but happen to be installed outside scoop on the current machine, so `pkgsync` will not list them —
  keep them.

Health check afterwards: `dotdoctor` (repo health) and `wincheck` (Windows friction).

## Documentation

| Doc | Covers |
| --- | --- |
| [PowerShell profile](docs/powershell.md) | `profile.d/` layout and conventions, alias tips + `aliasdoctor`, keybindings, project navigation, workflow helpers, reliability |
| [Window manager](docs/window-manager.md) | Workspace map, pinned vs. seeded app routing, layout commands, raise-or-launch |
| [Desktop shell](docs/desktop.md) | Yasb bars and widgets, Flow Launcher, Windhawk mods, Nilesoft Shell context menu |
| [Terminal](docs/terminal.md) | Windows Terminal overlay, WezTerm workspaces + shell integration |
| [Theming](docs/theming.md) | How one palette reaches every surface, shipped themes, wallpaper generation |
| [Windows tuning](docs/windows-tuning.md) | `winsmooth` host tuning, built-in AI opt-out, diagnostics/debloat |

## Highlights

- **Monitor-agnostic workspaces** — `Alt+1`–`Alt+0` focus the owning monitor first, so one keypress
  crosses displays. Tile counts are ceilings tuned for a 5120x1440 panel; overflow workspaces use a
  scrolling layout rather than degenerating into slivers. → [details](docs/window-manager.md#workspaces)
- **Raise or launch** — the Hyprland habit ported to Windows. `Win+B` focuses the browser you already
  have instead of opening a second one; press again to cycle its windows. Discovery goes through
  `komorebic state`, so it reaches windows on inactive workspaces and inside stacks that
  `SetForegroundWindow` cannot. → [details](docs/window-manager.md#raise-or-launch)
- **Alias tips** — zsh's `you-should-use`, derived from the live session's AST rather than a
  hand-maintained list. `aliasdoctor` points it the other way: it mines your history for the commands
  you retype with *no* shortcut and emits paste-ready definitions.
  → [details](docs/powershell.md#alias-tips)
- **One palette, everything** — `theme dracula` repaints terminal, prompt, komorebi borders, both Yasb
  bars, VSCode chrome, Spotify, Flow Launcher, the context menu, the Windows accent, and the
  wallpaper. Most of it live. → [details](docs/theming.md)

## What's tracked

PowerShell profile + project registry, Starship config, package manifests and `install.ps1`, terminal
configs, komorebi/whkd config, Yasb config, the Windhawk mod list, palette-driven app theming (VSCode,
Spicetify, Flow Launcher, Nilesoft Shell), theme palettes, generated wallpapers, and the fastfetch
banner.

Not tracked: installed PowerShell Gallery modules, caches, generated reports, and local secrets.
Machine-specific and private config lives in gitignored siblings — `powershell/profile.local.ps1`,
`projects.local.json`, `apps.local.json` — which are merged over the committed defaults.

## License

[MIT](LICENSE)
