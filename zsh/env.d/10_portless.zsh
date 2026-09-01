# Portless dev proxy
# TLS handled by Caddy on *.webfront.app — portless stays HTTP-only
export PORTLESS_STATE_DIR="$HOME/.portless"
export PORTLESS_LAN=1
export PORTLESS_HTTPS=0
# `${${$(hostname)}%%.*}` (nested zsh expansion) → command substitution +
# suffix strip, identical in both shells
_hostname_short=$(hostname)
export PORTLESS_TLD="${_hostname_short%%.*}"
unset _hostname_short
export PORTLESS_NAME="$(hostname)"