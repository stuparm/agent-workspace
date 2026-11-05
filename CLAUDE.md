# agent-workspace

Developer tools: Agent Cockpit (tmux-based parallel AI agents) and `wt` (git worktree manager with IDE integration).

## Project Structure

```
bin/
  agent-cockpit          # Main CLI script (bash) — session creation, attachment, lifecycle
  agent-cockpit-sidebar  # Sidebar display — shows CWD of each agent pane (event-driven via tail -f)
  agent-cockpit-notify-hook  # Claude Code Notification hook — writes agent status to state files
  agent-cockpit-clear-notif  # tmux pane-focus-in hook — clears notification when pane is focused
  agent-cockpit-statusline   # Claude Code statusLine wrapper — records rate_limits, then runs the user's statusline
  agent-cockpit-usage-write  # Only writer of the usage cache (~/.cache/agent-cockpit/usage/<harness>.tsv) — atomic, merges stale reports
  agent-cockpit-usage-codex  # Codex usage producer — reads rate_limits from ~/.codex/sessions logs
  wt-core                # Git worktree manager — create, list, prune subcommands
claude/
  settings.json          # Claude Code settings fragment (hooks) merged by install.sh; @BIN@ = PREFIX/bin
shell/
  init.sh                # Shell init (sourced in .zshrc) — PATH setup, ac alias, wt function
install.sh               # Installer — symlinks into PREFIX, rc line, merges Claude settings; --uninstall
```

## Usage limits (sidebar)

`AC_USAGE=claude[,codex]` enables a bottom block in the sidebar with each harness's limit windows.
Producers write normalized rows (`label<TAB>used_pct<TAB>resets_at<TAB>reported_at`) through
`agent-cockpit-usage-write`; the sidebar only reads those files, so it has no harness-specific parsing.
Claude data comes from statusLine stdin (`rate_limits.five_hour/seven_day`), captured by the wrapper that
`install.sh` puts in the global `statusLine`; the user's original command is kept in
`${CLAUDE_CONFIG_DIR:-~/.claude}/agent-cockpit-statusline.cmd`. All scripts must run on macOS `/bin/bash` 3.2
(no `declare -A`, guard empty arrays under `set -u`, write `${var}█` — never `$var` directly followed by a
multibyte character). The sidebar measures itself with `stty size` (`tput` with silenced stderr reports 80x24).

## `kb` — Personal Knowledge Base helper

Project-agnostic CLI for a markdown "second brain" inspired by Karpathy's LLM Wiki pattern. Target KB is resolved via the `KB_PATH` env var (no default; export it in your shell rc). All mutations of shared files (`MEMORY.md`, `log.md`, `index.md`) go through `kb` so they are mkdir-lock serialized — safe under 4 parallel agent sessions.

```
kb init [path]                Scaffold a KB (folders + CLAUDE.md + MEMORY.md + git init)
kb path                       Print resolved $KB_PATH
kb note <slug>                Create inbox/<ts>-<session>-<slug>.md
kb meeting <topic>            Create meetings/<YYYY-MM-DD>-<topic>.md
kb log <kind> <title...>      Append a flock-protected line to log.md
kb memory add <type> <name>   Create memory/<type>_<name>.md + add MEMORY.md pointer
kb memory list                List memory entries
kb inbox                      List inbox entries (sorted chronologically)
kb decision <slug>            Create decisions/<date>-<slug>.md (ADR-lite)
kb digest <slug>              Create sessions/<date>-<repo>-<slug>.md (repo resolved through worktrees)
kb repo [dir]                 Print "<repo><TAB><branch>" for dir (worktree -> main repo)
kb queue {add|remove|bump|list|count|clear|path}
                              Pending session digests, one line per session id (fed by a SessionEnd hook)
kb sessions prune [days]      Move digests older than <days> (default 14) to sessions-archive/
kb sync                       pull --rebase, commit all, push to origin
kb lint                       Regenerate index.md from wiki/, meetings/, memory/, decisions/
```

`kb queue` is only the storage half of automatic session digests. The producer is meant to be a
Claude Code `SessionEnd` (and `PreCompact`) hook that reads `session_id`, `transcript_path` and `cwd`
from its stdin JSON and runs `kb queue add`; the consumer is a scheduled job that summarizes each queued
transcript (e.g. with `claude -p`) and then runs `kb queue remove` (or `kb queue bump` on failure).
Neither ships in this repo. `kb sessions prune` is what such a job runs to keep `sessions/` short.

Session identification (used in inbox filenames): `$TMUX_PANE` if inside tmux, else `$(hostname -s)-$$`.

Locking: mkdir-based (POSIX atomic). No `flock` dependency.

## CLI Commands

Main command: `agent-cockpit` (alias: `ac` after install)

```
agent-cockpit              # Create/attach to default session (ac-default)
agent-cockpit [NAME]       # Create/attach to named session (ac-[NAME])
agent-cockpit attach [NAME]    # Attach to existing session
agent-cockpit kill [NAME]      # Destroy a session
agent-cockpit list             # List all active cockpit sessions
agent-cockpit --help           # Show help
```

## Keyboard Shortcuts (inside tmux session)

- `prefix + F1-F4` — Focus Agent 1–4
- `prefix + F5` — Focus the sidebar (`↑↓` + `↵` opens GoLand / VS Code / Terminal for an agent's folder)

## Session Architecture

Each session has one window ("Main"): a 2x2 grid of agents (Agent 1 top-left, 2 top-right, 3 bottom-left,
4 bottom-right) and the sidebar. Pane IDs are kept in the session environment (`AGENT_PANE_<n>`, `SIDEBAR_PANE`).

The sidebar's Terminal option keeps one hidden tmux session per agent, `_ac-<name>-t<n>` (the `_` keeps it out of
`agent-cockpit list/prune`), created in the agent's sidebar folder and shown with `display-popup` running
`tmux attach-session`. Detaching (`hide`, or `prefix + d`) closes the popup and keeps the shell; `exit` ends it.
`hide` is a function in `shell/init.sh`, defined only when `AC_TERMINAL` is set (the sidebar creates the sessions
with `-e AC_TERMINAL=1`).
`agent-cockpit kill/prune` remove these sessions too.

## `wt` — Git Worktree Manager

Manages git worktrees with full IntelliJ/GoLand IDE integration.

Architecture: thin shell function (in `shell/init.sh`) wraps `bin/wt-core`. The shell function handles `cd` into new worktrees (can't change parent shell CWD from a subprocess).

```
wt <name>       # Create worktree under <repo>-wt/<name> and cd into it
wt <name> --town # Use git-town (hack from main, append from feature)
wt <name> --copy # Copy all gitignored files instead of symlinking predefined list
wt list         # List all worktrees (branch, path, commit)
wt prune        # Interactive deletion via fzf (multi-select)
wt --help       # Show help
```

Create does: git worktree add, copies `.idea` config (iml, modules.xml, vcs.xml, .name), symlinks env/config files (or copies all gitignored files with `--copy`), copies `.run/*.xml` with path substitution, runs `mise trust`.

## Installation

```bash
./install.sh            # symlinks into ~/.local/share/agent-workspace, adds the .zshrc source line, merges Claude settings
./install.sh --uninstall
```

## Dev Environment

- Terminal emulator: iTerm2 (macOS)

## Tech Stack

- Bash shell scripting
- tmux (terminal multiplexer)
- Targets macOS and Linux
