# ~/.profile — POSIX sh login shells ONLY.
#
# zsh and bash do NOT read this file: zsh reads ~/.zshenv, and bash reads
# ~/.bash_profile (which shadows ~/.profile whenever it exists). Both of those
# converge on the shared env layer at zsh/env.d/ — see bash/env.sh, "one env
# layer, two shells". `sh -l` reads neither, so without this file a POSIX login
# shell gets none of it.
#
# This file therefore does not define anything itself. It sources the same
# shared files the other two shells use, so there is exactly one definition per
# variable rather than a third copy to drift.
#
# Constraint: anything sourced here must be POSIX-sh parseable, which is
# stricter than env.d's existing zsh+bash dual-parse rule. Source individual
# files you have checked, never the whole env.d glob — 03_paths.zsh and others
# are not sh-safe.

_dotfiles_envd="${DOTFILES:-$HOME/.local/dotfiles}/zsh/env.d"

# OpenClaw state dir: ~/.openclaw is a symlink into ~/repos/hart/openclaw and
# OpenClaw's config writer refuses a symlinked parent. See the sourced file.
[ -r "$_dotfiles_envd/12_openclaw.zsh" ] && . "$_dotfiles_envd/12_openclaw.zsh"

unset _dotfiles_envd
