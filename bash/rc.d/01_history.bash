# History — bash twin of zsh/rc.d/03_history.zsh, mapped per §C.
#   INC_APPEND_HISTORY  → shopt -s histappend + `history -a` per prompt
#   EXTENDED_HISTORY    → HISTTIMEFORMAT (non-empty = write timestamps)
#   HIST_IGNORE_DUPS + HIST_IGNORE_SPACE → HISTCONTROL=ignoreboth
#   HIST_EXPIRE_DUPS_FIRST → erasedups (stronger: drops ALL prior dups, not
#   just at trim time — closest sane equivalent)
export HISTFILE=${XDG_DATA_HOME:-$HOME/.local/share}/bash/history
mkdir -p "${HISTFILE%/*}" 2>/dev/null
export HISTSIZE=50000
export HISTFILESIZE=50000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT='%F %T '
shopt -s histappend

# `history -a` after each prompt = write-after-each-command (INC_APPEND).
# Prepend instead of assign so later fragments (and users) can add their own
# PROMPT_COMMAND hooks without this one clobbering theirs.
case ";${PROMPT_COMMAND:-};" in
    *";history -a;"*) ;;
    *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
