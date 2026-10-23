# iap Tab 補全（bash / zsh 都可 source）
# zsh 需要先啟用 bash 相容補全
if [[ -n "${ZSH_VERSION:-}" ]]; then
  autoload -U +X bashcompinit && bashcompinit
fi

_iap_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local cmds="help export ls show edit import to-yaml version update setup new remove reset uninstall"
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W "$cmds $(iap names 2>/dev/null)" -- "$cur") )
  elif (( COMP_CWORD == 2 )) && [[ "${COMP_WORDS[1]}" == show || "${COMP_WORDS[1]}" == edit || "${COMP_WORDS[1]}" == remove ]]; then
    COMPREPLY=( $(compgen -W "$(iap names 2>/dev/null)" -- "$cur") )
  fi
}
complete -F _iap_complete iap
