# Highlighting plugin (deferred - not needed until user types)
zsh-defer source $ZDOTDIR/plugins/syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets cursor)
# The regexp highlighter needs zsh/regex, which normally loads lazily on the
# first keystroke. Load it eagerly instead: a zsh package upgrade replaces
# /usr/lib/zsh/<ver>/ and long-running shells would otherwise fail the lazy
# zmodload on every keystroke. If the module is unavailable, skip the
# highlighter rather than spam errors.
if zmodload zsh/regex 2>/dev/null; then
  ZSH_HIGHLIGHT_HIGHLIGHTERS+=(regexp)
  # Highlight known abbreviations
  typeset -A ZSH_HIGHLIGHT_REGEXP
  ZSH_HIGHLIGHT_REGEXP+=('^[[:blank:][:space:]]*('${(j:|:)${(Qk)ABBR_REGULAR_USER_ABBREVIATIONS}}')$' 'fg=blue')
fi
