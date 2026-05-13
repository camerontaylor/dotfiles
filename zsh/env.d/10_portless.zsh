# Portless dev proxy
# TLS handled by Caddy on *.webfront.app — portless stays HTTP-only
export PORTLESS_STATE_DIR="$HOME/.portless"
export PORTLESS_LAN=1
export PORTLESS_HTTPS=0
export PORTLESS_TLD=ceres
export PORTLESS_NAME="$(hostname)"