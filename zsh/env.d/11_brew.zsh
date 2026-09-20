# Homebrew package manager
#
# ORDER MATTERS. `brew shellenv` PREPENDS its bin dirs, so on a Linux box with
# Linuxbrew those land AHEAD of the mise shims prepended by 08_mise.zsh (08 runs
# first, so 11 wins) and brew's `node` shadows mise's pinned one. Measured on
# ceres 2026-09-20: `node` was the brew formula (v26.4.0) in both login and
# non-interactive shells, while every mise shim and every systemd unit resolved
# v24.21.0 — exactly the interactive-vs-service split-brain AGENTS.md forbids
# ("never reintroduce a second node manager").
#
# So re-assert the mise paths AFTER brew has had its say: mise owns runtimes,
# and brew tools mise does not manage still resolve normally. This cannot live
# in rc.d/22_mise.zsh's `mise activate` — that only runs for interactive
# shells, while the shadow was present in scripts, agents and login shells too.
#
# Do NOT "fix" this by uninstalling brew's node: `summarize`'s shebang
# hardcodes /home/linuxbrew/.linuxbrew/opt/node/bin/node, so the formula has to
# stay installed even though summarize never consults PATH for it.
#
# The shims/fastbin pair below mirrors 08_mise.zsh, including its order —
# fastbin is prepended last so it lands ahead of the shims.
[[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)" || true

if [[ -n ${MISE_DATA_DIR:-} && -d $MISE_DATA_DIR/shims ]]; then
    path_prepend "$MISE_DATA_DIR/shims"
fi
if [[ -n ${MISE_DATA_DIR:-} && -d $MISE_DATA_DIR/fastbin ]]; then
    path_prepend "$MISE_DATA_DIR/fastbin"
fi
