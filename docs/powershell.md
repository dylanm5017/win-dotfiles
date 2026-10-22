# PowerShell profile

`powershell/profile.ps1` is a thin loader; the real configuration is split into small,
single-concern modules under `powershell/profile.d/`, dot-sourced in the order listed in the
loader's `$ProfileScripts` array. The two-digit prefix encodes both order and rough grouping:

- **00–45 core**: environment/paths (`00-env`, `10-path`), module imports (`20-modules`),
  history (`30-history`), prompt (`40-prompt`), theme switcher (`45-theme`).
- **48 lib**: `48-fzf.ps1` — the shared fzf helper library (defaults, `New-FzfArgs`, preview
  commands, and the `Select-FromNumberedMenu` fallback). Loads before every consumer.
- **50–90 commands**: navigation + zoxide (`50-navigation`), aliases (`60-aliases`), alias tips
  (`65-alias-tips`), keybindings (`70-keybindings`), bootstrap (`80-bootstrap`), SQL helpers
  (`90-sql`).
- **100–170 workflow**: project marks/registry (`100`, `160`), dev + workflow tooling (`110`,
  `115`), completions (`130`), the reliability suite (`140`), workstation tuning (`150`), and the
  login greeting (`170`, numbered last).

Conventions, so new modules stay consistent:

- **Naming**: internal helpers are PowerShell `Verb-Noun` (`Get-`, `Set-`, `Test-`, `Invoke-`…);
  the short, CLI-style commands you actually type (`gs`, `ni`, `dev`, `mark`, `td`) are exposed as
  aliases onto those functions, never as the function name itself.
- **Tool checks**: use the single `Test-Command` helper (defined in `00-env.ps1`) to guard on a
  command's presence — `Test-Command git -Application` for external executables, `Test-Command
  Some-Function` for cmdlets/functions. Prefer it over inline `Get-Command … -ErrorAction
  SilentlyContinue` for existence checks.
- **Local / private additions**: machine-specific or project-specific helpers go in the
  gitignored `powershell/profile.local.ps1` (sourced last), and private project group names go in
  `powershell/projects.local.json` — neither is committed. Set `WINDOTFILES_PROFILE_DEBUG=1` to
  print per-module load timings, or run `profileperf` for a timing table.
- **Bundled load**: normal shells don't dot-source the modules one by one. The loader
  concatenates them into the gitignored `.cache/profile.bundle.ps1` and loads that, which saves
  about 100 ms per shell (each separate file carries ~6 ms of fixed overhead). The bundle's first
  line records every source's mtime and size, so any edit triggers a rebuild on the next shell. A
  module must not use a top-level `return`/`exit`, a `param` block, or `using` statements; these
  change meaning in a bundle, so the loader warns and falls back to per-file loading. Debug mode
  and `WINDOTFILES_PROFILE_BUNDLE=0` also load per file, and per-file loading gives accurate error
  line numbers.

## Alias tips

`65-alias-tips.ps1` is this profile's take on zsh's `you-should-use`: type the long form of
something that has a shortcut and the shortcut is printed under the line, so the muscle memory
builds itself.

```
❯ git status --short
  tip gs  →  git status
```

The index is derived from the live session rather than a hand-maintained list — every `Alias:`
entry, plus every single-statement passthrough function (`function gs { git status @args }`) whose
body is parsed out of its AST. Adding a wrapper to `60-aliases.ps1` or `profile.local.ps1` is
enough to start getting tips for it; when two shortcuts tie, the shortest wins.

- `aliastips` lists everything the index knows, `aliastips git` filters it.
- Tips fire from the PSReadLine accept-line hook in `30-history.ps1`, so they land between the
  command and its output, and a failure there can never take out the prompt.
- `$env:WINDOTFILES_ALIAS_TIPS = 'off'` mutes them; `WINDOTFILES_ALIAS_TIPS_MIN` sets how many
  characters a shortcut has to save before it's worth mentioning (default `4`).

`aliasdoctor` is the same idea pointed the other way: it reads the PSReadLine history file, finds
the command prefixes you retype constantly that have *no* shortcut, and ranks them by the typing an
alias would have saved. `aliasdoctor -AsSnippet` emits paste-ready definitions for `60-aliases.ps1`:

```
function gch { git checkout @args }   # 1305x, saves 11745 chars
```

Proposed names are initials, Verb-Noun aware, and checked against the live session — when `gc` is
taken the last word grows a letter (`gch`) rather than falling back to a useless `gc2`. Flags and
paths don't contribute letters, single-letter names are refused, and `cd`-style navigation is
skipped entirely because the project registry (`p`, `goto`, `mark`, `workon`) already covers it.
Tune with `-Top`, `-MinCount`. It pairs with `histdoctor`, which reports the opposite failure: the
commands you run often that no longer resolve.

Savings are scored against the shortest form you can *already* type, not the raw text: once `gch`
exists, `git checkout -b` is really `gch -b`, so it stops claiming a ten-character win for two.

The `CoveredBy` column names an existing wrapper that already speaks to the command — `fbemu` for
`firebase emulators:start …`, `gpub` for `git push --set-upstream origin`. Those wrappers are full
commands with param blocks and guards, so the tip index can't see them; a second pass
(`aliastips -Wrapped`) digs the tool invocations out of their bodies. It flags rather than hides,
because `gpub` really does replace that push while `gprune` only touches part of `git branch` —
and it can't help where a wrapper builds its arguments dynamically, as `fbdeploy` does, so a
suggestion with an empty `CoveredBy` still deserves a glance. That coverage deliberately never
feeds the tips themselves: `gsync` runs several git commands, and "you typed `git fetch`, use
`gsync`" would be wrong.

## Keybindings

`70-keybindings.ps1` fills in what `EditMode Windows` leaves unbound, in `bash`/`zsh` order:

| Key | Does |
| --- | --- |
| `↑` / `↓` | History search filtered by what's typed — `git` + `↑` walks only git commands |
| `Alt+.` | Yank the last argument of the previous command |
| `Ctrl+w` / `Ctrl+Backspace` | Delete the word behind the cursor |
| `Alt+d` | Delete the word ahead of the cursor |
| `Ctrl+u` / `Ctrl+k` | Delete to start / end of line |
| `Shift+Enter` | Add a line without submitting |
| `Tab` / `Shift+Tab` | Completion menu; `Ctrl+r` / `Ctrl+t` are the fzf pickers |

Brackets and quotes auto-pair the way an editor does: an opening delimiter brings its partner,
typing the closing one steps over it instead of doubling it, a selection gets wrapped, and
Backspace between an empty pair removes both. Disable with `$env:WINDOTFILES_AUTOPAIR = 'off'`.

`keys` lists what's actually bound (`keys history` filters), the same way `cmds` lists the
profile's commands and `aliastips` lists its shortcuts.

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

## Reliability

- `dotdoctor` runs the win-dotfiles health check.
- `powershell/Test-WinDotfiles.ps1` runs the same checks from a clean PowerShell process.
- `-ConfigOnly` runs just the repo-side gates (config syntax, PowerShell parse, theme graph) with no dependency on host state. The `hooks/pre-commit` hook and CI both call it; the hook is wired up by `install.ps1` via `core.hooksPath`, and `dotdoctor` checks that wiring is still in place — an unset `core.hooksPath` leaves the gate inert without any sign.
- Set `WINDOTFILES_PROFILE_DEBUG=1` before loading the profile to print per-script load times.
- The prompt defaults to Starship when it is installed (language-aware: shows git branch/status
  and Node/.NET/Python versions in context) and falls back to the fast native prompt otherwise.
  Force either with `WINDOTFILES_PROMPT=starship` or `WINDOTFILES_PROMPT=native`. The Starship
  prompt uses a **transient prompt** — once a command runs, its prompt collapses to a bare `❯`
  so scrollback stays focused on output.
- `profileperf` reports the bundled load time (what new shells pay), per-script timing, Starship prompt timing, and cached project lookup timing; add `-RefreshProjects` to include a full project scan.
- Codex shells prefer `C:\tmp\codex` when it supports create/delete; otherwise they fall back to repo-local `.tmp\codex` for `TEMP`/`TMP`/`TMPDIR`, `DOTNET_CLI_HOME`, .NET artifacts, and NuGet transient caches, with MSBuild node reuse disabled so sandboxed .NET builds avoid user-profile temp/state permission issues where possible.
- Add machine-specific settings to `powershell/profile.local.ps1`; it is ignored by git.
