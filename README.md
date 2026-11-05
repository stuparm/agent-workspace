# Agent Workspace

Developer tools: **Agent Cockpit** (tmux-based parallel AI agents) and **`wt`** (git worktree manager with IDE integration).

## Agent Cockpit

Run up to 4 Claude Code agents side-by-side in a tmux session with a status sidebar.

```
agent-cockpit              # Create/attach to default session
agent-cockpit [NAME]       # Create/attach to named session
agent-cockpit [NAME] --focus   # Enable focus dimming on inactive panes
agent-cockpit attach [NAME]    # Attach to existing session
agent-cockpit kill [NAME]      # Destroy a session
agent-cockpit prune            # Interactively delete sessions via fzf
agent-cockpit list             # List all active sessions
```

**Alias:** `ac` (available after install)

### Layout

```
┌─────────────┬─────────────┬──────────┐
│ Agent 1      │ Agent 2      │          │
│              │              │ Cockpit  │
├─────────────┼─────────────┤ (sidebar)│
│ Agent 3      │ Agent 4      │          │
│              │              │          │
└─────────────┴─────────────┴──────────┘
     80% agents                 20%
```

### Keyboard Shortcuts

| Key | Action |
|---|---|
| `prefix + F1-F4` | Focus Agent 1–4 |
| `prefix + F5` | Focus sidebar |

### Sidebar

Each agent's entry shows its folder and three options (`↑↓` to pick, `↵` to open):

- **GoLand** / **VS Code** — open the folder in the IDE.
- **Terminal** — a shell in a popup over the whole layout, started in that folder (or `~` if the
  sidebar has no folder for the agent). Typing `hide` hides it and keeps it running (while a command
  is still running, `prefix + d` does the same): reopening shows the same shell, scrollback and
  running commands. `exit` ends it, and the next open starts in the sidebar's folder again. Each
  agent has its own terminal; `cd` in it does not change the sidebar. `hide` comes from
  `shell/init.sh` and exists only in these terminals. Needs tmux 3.3+.

### Focus Mode (`--focus`)

Dims inactive panes so you can easily see which agent you're working with. Inactive panes get faded text (via tmux `dim` attribute) and a grey background overlay. The focused pane renders at full brightness with a solid background.

#### How it works

tmux doesn't support true pane opacity — focus mode uses two mechanisms:

- **Text fading** (`dim` / `nodim`) — the terminal renders inactive pane text at reduced intensity. How much fading you see depends on your terminal's "faint text" setting (e.g. iTerm2: Settings > Profiles > Colors > Faint text).
- **Background tint** — inactive panes get a slightly lighter background to visually separate them from the focused pane.

#### Terminal Configuration

Your terminal must **not** apply its own dimming on top of tmux's styling.

**iTerm2:**

| Setting | Location | Value |
|---|---|---|
| Dim inactive split panes | Settings > Appearance > Panes | **Off** |
| Dim background windows | Settings > Appearance > Panes | **Off** |
| Minimum Contrast | Settings > Profiles > Colors | **0** |
| Faint text | Settings > Profiles > Colors | **50** (adjust to taste) |

**Other terminals** (Alacritty, Kitty, WezTerm, etc.) generally don't have split-pane dimming features, so no extra configuration is needed.

#### Color Configuration

The text fading works universally with no configuration. The background colors may need tuning to match your terminal theme — the key is contrast between `AC_ACTIVE_BG` and `AC_INACTIVE_BG`.

| Variable | Description | Default | Hex |
|---|---|---|---|
| `AC_ACTIVE_BG` | Focused pane background | `#000000` | Pure black |
| `AC_INACTIVE_BG` | Inactive pane background | `colour236` | `#303030` |

Values can be any tmux color: `#rrggbb`, `colour0`–`colour255`, `black`, or `default`.

**Tuning for your theme:** set `AC_ACTIVE_BG` to match your terminal's background color, and `AC_INACTIVE_BG` to a slightly lighter shade.

| Terminal background | `AC_ACTIVE_BG` | `AC_INACTIVE_BG` |
|---|---|---|
| Pure black (`#000000`) | `#000000` (default) | `colour236`–`colour238` |
| Dark (`#1a1b26`, Tokyo Night) | `#1a1b26` | `#33344b` |
| Dark (`#282828`, Gruvbox) | `#282828` | `#3c3836` |
| Medium (`#3c3c3c`+) | Match your bg | A lighter shade |

**Example — persistent config in `.zshrc`:**

```bash
export AC_ACTIVE_BG='#1a1b26'
export AC_INACTIVE_BG='#33344b'
```

**Example — one-off:**

```bash
AC_INACTIVE_BG=colour238 agent-cockpit --focus
```

## `wt` — Git Worktree Manager

Manages git worktrees with IntelliJ/GoLand IDE integration.

```
wt <name>          # Create worktree and cd into it
wt <name> --town   # Use git-town (hack from main, append from feature)
wt <name> --copy   # Copy all gitignored files instead of symlinking
wt list            # List all worktrees
wt prune           # Interactive deletion via fzf
```

## Installation

### Prerequisites

- **tmux** — `brew install tmux` (macOS) or `apt install tmux` (Linux)
- **bash** 3.2+ (macOS `/bin/bash` works)
- **jq** — `brew install jq` / `apt install jq`; required by `install.sh` and the usage block
- **fzf** — required for `prune` commands
- **zsh** — `shell/init.sh` is zsh-only
- **python3** — only for `kb queue bump`

### Setup

```bash
./install.sh
```

Run it from the main checkout (not a `wt` worktree). It:

1. Symlinks `bin/*`, `shell/init.sh` and `.env(.example)` into `~/.local/share/agent-workspace`
   (`--prefix DIR` to change), so `git pull` updates the installed tools. Symlinks there that point
   somewhere else are left alone; installed files with local edits are skipped with a diff
   (`--force` replaces them, keeping a copy in `.install-backup/`).
2. Adds `source ~/.local/share/agent-workspace/shell/init.sh` to `~/.zshrc` unless it is already
   there. This puts `bin/` on your `PATH` and sets up the `ac` alias and `wt` shell function.
3. Merges `claude/settings.json` (the cockpit's Notification hook) into
   `~/.claude/settings.json` and wraps `statusLine` with `agent-cockpit-statusline` (see below).
   It prints the diff and keeps a `settings.json.ac-backup-<timestamp>` copy.

Running it again is a no-op. `./install.sh --uninstall` reverses all three steps.

## Usage limits in the sidebar

```bash
export AC_USAGE=claude          # or claude,codex
```

The sidebar then shows each harness's limits at the bottom: a bar per window (Claude: `5h` and
`week`) with the time until it resets, and how long ago the numbers were reported.

```
├─ claude · 2m ago ──┤
 5h   ██████▊░░░  68%
      ↻ 1h12m
 week ██░░░░░░░░  21%
      ↻ Fri 20:00
└── ↑↓ nav · ↵ open ─┘
```

- **Claude** — Claude Code passes `rate_limits` to the statusLine command. `install.sh` points
  `statusLine` at `agent-cockpit-statusline`, which records them and then runs your own statusline
  command, so your bar does not change. Your command is kept in
  `~/.claude/agent-cockpit-statusline.cmd`. Numbers update after each response in any Claude
  session; until the first one, the block shows "no data".
- **Codex** — read from the newest session log in `~/.codex/sessions` (last 7 days), every 30s.

Values are cached in `~/.cache/agent-cockpit/usage/<harness>.tsv`. A window whose reset time has
passed shows as 0% until new data arrives. The block is hidden when the pane is too short for it.

`AC_USAGE` is read when the sidebar starts (session creation). For a running session, focus the
sidebar (`prefix + F5`), press `Ctrl-C`, and run `AC_USAGE=claude agent-cockpit-sidebar ac-<name>`.

Caveats:

- If Claude's `/statusline` setup rewrites `statusLine`, the wrapper is dropped and the numbers stop
  updating (the age keeps growing). Re-run `./install.sh`.
- The global `statusLine` points into this checkout: switching it to a branch without
  `bin/agent-cockpit-statusline` blanks the statusline in every Claude session until you switch back.
- A project-level `.claude/settings.json` with its own `statusLine` overrides the wrapper for that
  project; other sessions still keep the shared numbers fresh.

## License

[MIT](LICENSE)
