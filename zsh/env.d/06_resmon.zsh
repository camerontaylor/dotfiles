# Legacy resmon-session manages the old resmon-agents.slice hierarchy. The
# active cgroup design is now the persistent agents.slice plus rc.d hooks, so
# starting resmon-session from .zshenv makes every zsh subprocess pay a
# systemd-run/systemctl cost. That is especially bad for mise env evaluation on
# cd, where a blocked user manager can freeze directory entry.
#
# Keep this as an explicit compatibility escape hatch for old monitoring flows,
# but do not auto-start it during normal shell or mise activation.
if [[ "${RESMON_SESSION_AUTO_START:-0}" == "1" ]]; then
  case $- in *i*) ;; *) return 0 ;; esac
  if command -v timeout >/dev/null 2>&1 && command -v resmon-session >/dev/null 2>&1; then
    timeout 2s resmon-session start > /dev/null 2>&1 || true
  elif command -v resmon-session >/dev/null 2>&1; then
    resmon-session start > /dev/null 2>&1 || true
  fi
fi
