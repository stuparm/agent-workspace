# agent-workspace — source this in .zshrc
# Provides: agent-cockpit (ac), wt, kb

# Add binaries to PATH
_tp_bin="${0:a:h:h}/bin"
[[ -d "$_tp_bin" ]] && export PATH="$_tp_bin:$PATH"
unset _tp_bin

# ac alias
alias ac='agent-cockpit'

# `hide` closes a sidebar Terminal popup and keeps its shell running (same as prefix + d).
# Defined only in those shells: agent-cockpit-sidebar starts them with AC_TERMINAL set.
if [[ -n "${AC_TERMINAL:-}" ]]; then
  hide() { tmux detach-client; }
fi

# `kb` reads its knowledge base location from KB_PATH (no default): export it in
# your shell rc, or per project via direnv.

# wt shell function (needs cd in parent shell)
wt() {
  case "${1:-}" in
    list|prune|--help|-h) wt-core "$@" ;;
    "") wt-core --help; return 0 ;;
    *)
      local target_dir
      target_dir=$(wt-core create "$@") || return $?
      cd "$target_dir" || return $?
      ;;
  esac
}
