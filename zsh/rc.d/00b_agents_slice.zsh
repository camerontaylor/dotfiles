# 00b_agents_slice.zsh — join agents.slice on every interactive shell startup.
#
# Why this slot: this must run before 01_instant_prompt.zsh. The hook re-execs
# zsh through systemd-run on first startup, and p10k instant prompt must not draw
# a fake prompt in the pre-exec shell.
#
# Verified on this host under the user's actual login locale (en_AU.UTF-8):
#
#   $ LANG=en_AU.UTF-8 zsh -c 'echo $ZDOTDIR/rc.d/*(N)' | grep -E '00|01'
#   .../00_tmux.zsh
#   .../00b_agents_slice.zsh   ← here
#   .../01_instant_prompt.zsh
#
# Why a precmd-style hook (runs once at shell init, not chpwd):
#   The user's interactive zsh joins agents.slice once per tab. Worktree-level
#   nesting is handled by 04c_worktree_scope.zsh (chpwd hook).
#
# Why exec systemd-run --scope (and not just `set --slice` somehow):
#   moving an existing process between cgroups via API requires write to
#   cgroup.procs, which is not user-writable. The supported mechanism is to
#   exec into a new transient scope. The exec replaces this shell's PID with
#   a new shell wrapped in the scope.
#
# env.d/06_resmon.zsh ordering note:
#   06_resmon.zsh is in env.d (sourced by .zshenv before .zshrc/rc.d) and calls
#   `resmon-session start` in the pre-exec PID. The exec systemd-run below
#   replaces that PID. The new shell re-sources .zshenv (zsh always does), so
#   resmon-session start fires again with the post-exec PID. This is harmless:
#   resmon-session early-returns at lines 85-89 (is_slice_active guard) before
#   reaching state-file writes (lines 116-117, 145), and INIT_UNIT="resmon-init"
#   (line 12) is a named systemd unit, not PID-based, so registration survives
#   the exec. Documented: do not "fix" the double-fire — it's correct.

# Idempotency: do nothing if already in agents.slice. This guard MUST come first;
# without it, the exec systemd-run below recurses infinitely.
if [[ -r /proc/self/cgroup ]] && grep -q '/agents\.slice' /proc/self/cgroup; then
  return 0
fi

# Only apply to interactive shells.
[[ -o interactive ]] || return 0

# `zsh -ic '...'` is technically interactive, but it is still a command-string
# shell whose caller expects the command to return. Re-execing it into a fresh
# prompt makes script-style checks look frozen.
[[ -z "${ZSH_EXECUTION_STRING:-}" ]] || return 0

# Bare SSH login shells are transport/bootstrap shells in this setup: .zshrc
# attaches or creates tmux before the normal rc.d loop. Keep that path free of
# systemd-run so SSH remains reliable even when the remote user manager is in a
# bad state. New tmux panes still run this hook inside TMUX and join agents.slice.
if [[ -n "${SSH_TTY:-}" && -z "${TMUX:-}" ]]; then
  return 0
fi

# Need systemd user tools for the scope handoff. SSH or early-login shells can
# lack a reachable user manager; in that case, keep the shell usable.
if (( ! ${+commands[systemctl]} || ! ${+commands[systemd-run]} )); then
  return 0
fi

# If agents.slice is not active, attempt to start it once. Guards against the
# hook running in early-init contexts (e.g., before the user's default.target
# has fully come up after login). If the start fails, degrade gracefully —
# do NOT exec systemd-run (would fail loudly), do NOT lock out the tab.
if ! systemctl --user is-active agents.slice >/dev/null 2>&1; then
  systemctl --user start agents.slice >/dev/null 2>&1 || true
  if ! systemctl --user is-active agents.slice >/dev/null 2>&1; then
    print -u2 "[agents.slice] WARNING: agents.slice not active and start failed; skipping membership."
    print -u2 "[agents.slice] Run ~/.local/dotfiles/bin/install-agents-slice.sh to (re)install."
    return 0
  fi
fi

# Validate transient scope creation before replacing this shell. This is
# especially important for SSH sessions where the user manager can be active
# but still unable to accept a new interactive scope from this environment.
if ! systemd-run --user --scope --slice=agents.slice --quiet --collect -- true >/dev/null 2>&1; then
  print -u2 "[agents.slice] WARNING: systemd-run scope handoff failed; skipping membership."
  return 0
fi

# Join the slice by re-execing zsh inside a transient scope under agents.slice.
# --quiet suppresses systemd-run's "Running as unit:" chatter.
# Exec into $SHELL preserves interactive login semantics.
exec systemd-run --user --scope --slice=agents.slice --same-dir --quiet --collect -- "$SHELL" -i
