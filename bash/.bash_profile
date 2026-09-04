# Login shells. bash reads only this file for logins (never .bashrc), so
# delegate to the interactive file — the classic pattern — and keep env
# handling in exactly one place (bash/env.sh, which .bashrc sources).
# zsh stays the interactive default; this tree is the opt-in bash twin
# (DOTFILES_SHELL knob, scripts/deploy.d/75_brew_setup.zsh).

# Env layer FIRST, unconditionally — NOT only via .bashrc. A non-interactive
# login shell (`bash -l -c '…'`, the shape ssh/cron/CI use) returns out of
# .bashrc at its `case $-` guard, so delegating alone leaves env.sh unreached
# and breaks the contract env.sh itself documents ("reached from
# ~/.bash_profile (login shells)").
#
# This has to happen HERE, not in env.d, and for the mirror-image of the
# reason zsh's gnubin prepends live in rc.d: bash has no `unsetopt
# GLOBAL_RCS`. zsh/.zshenv switches /etc/zprofile off so path_helper never
# runs at all, but EVERY `bash -l` reads /etc/profile and gets path_helper's
# rewrite — /etc/paths entries (incl. /usr/bin) hoisted to the head, then
# /etc/paths.d, then whatever PATH already held appended behind both. On
# Apple silicon that demotes $HOMEBREW_PREFIX/bin: /opt/homebrew/bin is
# reachable only through /etc/paths.d, which lands AFTER /usr/bin, so brew's
# binaries silently lose to Apple's. Concretely, /usr/bin/rsync is openrsync
# (protocol 29, "rsync version 2.6.9 compatible") not samba rsync, and
# mishandles --info=progress2 / --link-dest / --delete-excluded / --chmod.
# .bash_profile runs after /etc/profile, so env.d's prepends stick.
# Intel Macs are only accidentally immune: there /usr/local/bin IS the brew
# prefix and is line 1 of /etc/paths.
_bash_profile_env=$HOME/.config/bash/env.sh
[ -r "$_bash_profile_env" ] || _bash_profile_env=${BASH_SOURCE[0]%/*}/env.sh
[ -r "$_bash_profile_env" ] && . "$_bash_profile_env"
unset _bash_profile_env

[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
