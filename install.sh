#!/usr/bin/env bash
set -euo pipefail

# Install agent-workspace:
#   1. symlink bin/*, shell/init.sh and .env(.example) into PREFIX, so `git pull` updates them
#   2. source PREFIX/shell/init.sh from the shell rc file
#   3. merge the cockpit's Claude Code settings into the global settings.json: the hooks in
#      claude/settings.json, and statusLine wrapped by agent-cockpit-statusline (records
#      usage limits for the sidebar, then runs the user's own statusline command, which is
#      kept next to settings.json in agent-cockpit-statusline.cmd)
#
# Every step is idempotent, and --uninstall reverses all three.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PREFIX="$HOME/.local/share/agent-workspace"
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
RC_FILE="$HOME/.zshrc"
MODE="install"
FORCE=false

RC_MARKER="# agent-workspace (install.sh)"
STATUSLINE_NAME="agent-cockpit-statusline"
FRAGMENT="$REPO/claude/settings.json"
TS=$(date +%Y%m%d-%H%M%S)
SKIPPED=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [--uninstall] [--force] [--prefix DIR] [--claude-settings FILE] [--rc FILE]

Options:
  --uninstall             Reverse a previous install (settings, rc line, symlinks)
  --force                 Replace PREFIX files that differ from the repo (they are backed up)
  --prefix DIR            Install location     (default: ~/.local/share/agent-workspace)
  --claude-settings FILE  Claude settings file (default: ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json)
  --rc FILE               Shell rc file        (default: ~/.zshrc)
EOF
    exit "${1:-0}"
}

info() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

while (( $# )); do
    case "$1" in
        --uninstall)       MODE="uninstall" ;;
        --force)           FORCE=true ;;
        --prefix)          PREFIX="${2:?--prefix needs a directory}"; shift ;;
        --claude-settings) CLAUDE_SETTINGS="${2:?--claude-settings needs a file}"; shift ;;
        --rc)              RC_FILE="${2:?--rc needs a file}"; shift ;;
        -h|--help)         usage 0 ;;
        *)                 usage 1 ;;
    esac
    shift
done

BIN="$PREFIX/bin"
BACKUP_ROOT="$PREFIX/.install-backup"
# Next to settings.json, where agent-cockpit-statusline looks for it
SIDECAR="$(dirname "$CLAUDE_SETTINGS")/$STATUSLINE_NAME.cmd"

preflight() {
    command -v jq >/dev/null || die "jq is required (brew install jq / apt install jq)"
    command -v tmux >/dev/null || warn "tmux not found (agent-cockpit needs it)"
    command -v fzf >/dev/null || warn "fzf not found (needed by 'prune' commands)"
    # PREFIX ends up unquoted inside settings.json command strings
    case "$PREFIX" in
        *[[:space:]\'\"\\\$\`]*) die "PREFIX must not contain whitespace or quotes: $PREFIX" ;;
    esac
    # A linked worktree gets pruned, which would leave the global statusLine pointing at nothing
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        local git_dir common_dir
        git_dir=$(cd "$REPO" && cd "$(git rev-parse --git-dir)" && pwd -P)
        common_dir=$(cd "$REPO" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
        [[ "$git_dir" == "$common_dir" ]] || die "run install.sh from the main checkout, not a worktree ($REPO)"
    fi
}

# ── 1. Symlinks ──

# Paths, relative to the repo, that get linked into PREFIX
link_paths() {
    local f
    for f in "$REPO"/bin/*; do
        [[ -f "$f" ]] && printf '%s\n' "bin/${f##*/}"
    done
    printf '%s\n' shell/init.sh .env.example
    [[ -f "$REPO/.env" ]] && printf '%s\n' .env
    return 0
}

# True if the file equals a committed version of a repo path: an old installed copy,
# safe to replace. Anything else carries local edits.
is_repo_version() {
    local hash raw
    hash=$(git -C "$REPO" hash-object "$1" 2>/dev/null) || return 1
    raw=$(git -C "$REPO" log --all --format= --raw --no-abbrev -- "$2" 2>/dev/null) || return 1
    [[ "$raw" == *" $hash "* ]]
}

# Links into this repo whose file is gone (a script removed from bin/). link_paths only
# lists existing files, so nothing else would remove them.
remove_stale_links() {
    local dst
    for dst in "$PREFIX"/bin/*; do
        [[ -L "$dst" && ! -e "$dst" && "$(readlink "$dst")" == "$REPO/"* ]] || continue
        rm "$dst"
        info "removed bin/${dst##*/} (gone from the repo)"
    done
    return 0
}

install_links() {
    echo "Linking $PREFIX → $REPO"
    remove_stale_links
    local rel src dst current
    while IFS= read -r rel; do
        src="$REPO/$rel"
        dst="$PREFIX/$rel"
        if [[ -L "$dst" ]]; then
            current=$(readlink "$dst")
            if [[ "$current" == "$src" ]]; then
                continue
            elif [[ "$current" == "$REPO/"* ]]; then
                ln -sfn "$src" "$dst"
                info "relinked $rel"
            else
                # e.g. bin/kb linked to another checkout on purpose
                info "skipped $rel (links to $current, not this repo)"
            fi
        elif [[ -e "$dst" ]]; then
            if ! cmp -s "$dst" "$src" && ! is_repo_version "$dst" "$rel" && ! $FORCE; then
                warn "skipped $rel: the installed file has local changes (port them into the repo, or rerun with --force):"
                diff -u "$src" "$dst" | sed 's/^/      /' | head -40 >&2 || true
                SKIPPED=$(( SKIPPED + 1 ))
                continue
            fi
            mkdir -p "$BACKUP_ROOT/$TS/$(dirname "$rel")"
            mv "$dst" "$BACKUP_ROOT/$TS/$rel"
            ln -s "$src" "$dst"
            info "linked $rel (previous file kept in .install-backup/$TS)"
        else
            mkdir -p "$(dirname "$dst")"
            ln -s "$src" "$dst"
            info "linked $rel"
        fi
    done < <(link_paths)
}

# Newest backup of a linked path, if any
newest_backup() {
    local d
    for d in $(ls -r "$BACKUP_ROOT" 2>/dev/null); do
        if [[ -e "$BACKUP_ROOT/$d/$1" ]]; then
            printf '%s' "$BACKUP_ROOT/$d/$1"
            return 0
        fi
    done
    return 0
}

uninstall_links() {
    echo "Unlinking $PREFIX"
    local rel dst backup
    while IFS= read -r rel; do
        dst="$PREFIX/$rel"
        [[ -L "$dst" && "$(readlink "$dst")" == "$REPO/"* ]] || continue
        rm "$dst"
        backup=$(newest_backup "$rel")
        if [[ -n "$backup" ]]; then
            mv "$backup" "$dst"
            info "restored $rel from .install-backup"
        else
            info "removed $rel"
        fi
    done < <(link_paths)
    remove_stale_links
    [[ -d "$BACKUP_ROOT" ]] && find "$BACKUP_ROOT" -depth -type d -empty -delete 2>/dev/null
    # Directories install created; rmdir leaves any that still hold other files
    rmdir "$PREFIX/bin" "$PREFIX/shell" "$PREFIX" 2>/dev/null
    return 0
}

# ── 2. Shell rc ──

rc_sources_prefix() {
    local forms=("$PREFIX/shell/init.sh") rest args=() f lines
    if [[ "$PREFIX" == "$HOME/"* ]]; then
        rest="${PREFIX#"$HOME"/}"
        forms+=("~/$rest/shell/init.sh" "\$HOME/$rest/shell/init.sh" "\${HOME}/$rest/shell/init.sh")
    fi
    for f in "${forms[@]}"; do
        args+=(-e "$f")
    done
    lines=$(grep -F "${args[@]}" "$RC_FILE" 2>/dev/null) || return 1
    grep -qv '^[[:space:]]*#' <<<"$lines"
}

install_rc() {
    echo "Shell rc: $RC_FILE"
    if rc_sources_prefix; then
        info "already sources $PREFIX/shell/init.sh"
        return 0
    fi
    # Keep the line on its own; uninstall leaves this newline in place
    if [[ -s "$RC_FILE" && -n "$(tail -c 1 "$RC_FILE")" ]]; then
        printf '\n' >> "$RC_FILE"
        info "added the missing final newline"
    fi
    printf 'source "%s/shell/init.sh"  %s\n' "$PREFIX" "$RC_MARKER" >> "$RC_FILE"
    info "added: source \"$PREFIX/shell/init.sh\""
}

uninstall_rc() {
    echo "Shell rc: $RC_FILE"
    if [[ ! -f "$RC_FILE" ]] || ! grep -qF "$RC_MARKER" "$RC_FILE"; then
        info "no line added by install.sh"
        return 0
    fi
    # grep -v into a temp file, then cat back: keeps a symlinked rc file and its mode
    local tmp
    tmp=$(mktemp)
    grep -vF "$RC_MARKER" "$RC_FILE" > "$tmp" || true
    cat "$tmp" > "$RC_FILE"
    rm -f "$tmp"
    info "removed the line added by install.sh"
}

# ── 3. Claude Code settings ──

# Fragment hooks are matched to existing ones by command name: a match is rewritten in
# place to the absolute path (no duplicate), anything else is appended.
# shellcheck disable=SC2016
INSTALL_FILTER='
def mentions($name): (.command // "") | test("(^|[/ ])" + $name + "( |$)");
reduce (($frag[0].hooks // {}) | to_entries[]) as $ev (.;
  reduce ($ev.value[]) as $group (.;
    reduce ($group.hooks[]) as $h (.;
      ($h.command | gsub("@BIN@"; $bin)) as $cmd
      | ($h.command | split("/") | last) as $name
      | if ([.hooks[$ev.key][]?.hooks[]? | select(mentions($name))] | length) > 0
        then .hooks[$ev.key] |= map(if .hooks then .hooks |= map(if mentions($name) then .command = $cmd else . end) else . end)
        else .hooks[$ev.key] += [$group | .hooks = [$h | .command = $cmd]]
        end)))
| if (.statusLine.command // null) == null
  then .statusLine = {"type": "command", "command": $statusline}
  else .statusLine.command = $statusline
  end'

# shellcheck disable=SC2016
UNINSTALL_FILTER='
def mentions($name): (.command // "") | test("(^|[/ ])" + $name + "( |$)");
((.hooks // {}) | length > 0) as $had_hooks
| reduce (($frag[0].hooks // {}) | to_entries[]) as $ev (.;
    reduce ([$ev.value[].hooks[]?.command | split("/") | last][]) as $name (.;
      if .hooks[$ev.key] then
        .hooks[$ev.key] |= (map(if .hooks then .hooks |= map(select(mentions($name) | not)) else . end)
                            | map(select((.hooks // [0]) | length > 0)))
        | if .hooks[$ev.key] == [] then del(.hooks[$ev.key]) else . end
      else . end))
| if $had_hooks and .hooks == {} then del(.hooks) else . end
| if (.statusLine.command // "") | contains($statusline_name)
  then (if $has_orig == "1" then .statusLine.command = $orig else del(.statusLine) end)
  else . end'

resolve_symlink() {
    local f="$1" link
    while [[ -L "$f" ]]; do
        link=$(readlink "$f")
        if [[ "$link" == /* ]]; then
            f="$link"
        else
            f="$(dirname "$f")/$link"
        fi
    done
    printf '%s' "$f"
}

file_mode() {
    stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"
}

write_atomic() {
    local tmp
    tmp=$(mktemp "$(dirname "$1")/.ac-tmp.XXXXXX")
    printf '%s' "$2" > "$tmp"
    mv -f "$tmp" "$1"
}

# Apply a jq filter to the settings file (extra args go to jq). Writes only on change,
# after a backup, and aborts if the file changed meanwhile: running Claude sessions write
# it too (model, effort, ...).
update_settings() {
    local filter="$1"
    shift
    local target snapshot new
    target=$(resolve_symlink "$CLAUDE_SETTINGS")
    mkdir -p "$(dirname "$target")"
    snapshot=$(mktemp)
    if [[ -f "$target" ]]; then
        cp "$target" "$snapshot"
    else
        printf '{}\n' > "$snapshot"
    fi
    new=$(mktemp "$(dirname "$target")/.settings.XXXXXX")
    if ! jq "$@" "$filter" "$snapshot" > "$new"; then
        rm -f "$new" "$snapshot"
        die "could not update $CLAUDE_SETTINGS (is it valid JSON?)"
    fi
    if cmp -s "$new" "$snapshot"; then
        rm -f "$new" "$snapshot"
        info "settings already up to date"
        return 0
    fi
    diff -u -L "settings.json (before)" -L "settings.json (after)" "$snapshot" "$new" | sed 's/^/    /' || true
    if [[ -f "$target" ]]; then
        if ! cmp -s "$target" "$snapshot"; then
            rm -f "$new" "$snapshot"
            die "$CLAUDE_SETTINGS changed while install.sh ran, rerun it"
        fi
        cp -p "$target" "$target.ac-backup-$TS"
        chmod "$(file_mode "$target")" "$new"
        info "backup: $target.ac-backup-$TS"
    fi
    mv -f "$new" "$target"
    rm -f "$snapshot"
    info "settings updated"
}

install_claude() {
    echo "Claude Code settings: $CLAUDE_SETTINGS"
    [[ -x "$BIN/$STATUSLINE_NAME" ]] || die "$BIN/$STATUSLINE_NAME is missing, cannot wrap the statusLine"
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    local current=""
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        current=$(jq -r '.statusLine.command // empty' "$CLAUDE_SETTINGS") \
            || die "could not read $CLAUDE_SETTINGS (is it valid JSON?)"
    fi
    if [[ -z "$current" ]]; then
        rm -f "$SIDECAR"
    elif [[ "$current" != *"$STATUSLINE_NAME"* ]]; then
        # Written before the switch, so the wrapper finds its delegate from the first refresh
        write_atomic "$SIDECAR" "$current"
        info "your statusline command is kept in $SIDECAR"
    fi
    update_settings "$INSTALL_FILTER" --slurpfile frag "$FRAGMENT" \
        --arg bin "$BIN" --arg statusline "$BIN/$STATUSLINE_NAME"
}

uninstall_claude() {
    echo "Claude Code settings: $CLAUDE_SETTINGS"
    if [[ -f "$CLAUDE_SETTINGS" ]]; then
        local has_orig=0 orig=""
        if [[ -s "$SIDECAR" ]]; then
            has_orig=1
            orig=$(<"$SIDECAR")
        fi
        # Settings first: the wrapper must not lose its delegate while still installed
        update_settings "$UNINSTALL_FILTER" --slurpfile frag "$FRAGMENT" \
            --arg statusline_name "$STATUSLINE_NAME" --arg has_orig "$has_orig" --arg orig "$orig"
    fi
    rm -f "$SIDECAR"
}

# ── Main ──

if [[ "$MODE" == "install" ]]; then
    preflight
    install_links
    install_rc
    install_claude
    echo
    if (( SKIPPED )); then
        warn "$SKIPPED file(s) skipped, see above"
    fi
    echo "Done. To show usage limits in the cockpit sidebar, add to $RC_FILE:"
    echo "  export AC_USAGE=claude"
else
    command -v jq >/dev/null || die "jq is required"
    uninstall_claude
    uninstall_rc
    uninstall_links
    echo
    echo "Done. Settings backups (*.ac-backup-*) are left next to $CLAUDE_SETTINGS."
fi
