autoload -U compinit && compinit
autoload -U bashcompinit && bashcompinit
update-repo() {
  for source in "$@"; do
    sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/${source}" \
      -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"    
  done
}

_ppa_lists(){
  local cur
#  _init_completion || return

  COMPREPLY=( $( find /etc/apt/sources.list.d/ -name "*$cur*.list" \
    -exec basename {} \; 2> /dev/null ) )
  return 0
} &&
  complete -F _ppa_lists update-repo
