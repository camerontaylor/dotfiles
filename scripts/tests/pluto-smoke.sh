#!/usr/bin/env bash
# Native acceptance checks after the four-repo NixOS deploy.
# The converge wrapper may repair its derived virtual environment.
# Run from a login shell: bash -lc 'bash <dotfiles>/scripts/tests/pluto-smoke.sh'
set -u

failures=0
check() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'ok: %s\n' "$label"
    else
        printf 'FAIL: %s\n' "$label" >&2
        failures=$((failures + 1))
    fi
}

if [[ ! -e /etc/NIXOS ]]; then
    printf '%s\n' 'This check requires the deployed NixOS host.' >&2
    exit 2
fi

dotfiles_root=${DOTFILES_DIR:-${DOTFILES:-$HOME/.local/dotfiles}}
agents_root=${AGENTS_DIR:-$HOME/.local/agents}
infra_root=${INFRA_DIR:-$HOME/.local/infra}
secrets_root=${SECRETS_DIR:-$HOME/.local/secrets}
state_root=${XDG_STATE_HOME:-$HOME/.local/state}

check 'dotfiles checkout' test -f "$dotfiles_root/deploy.bash"
check 'agents checkout' test -f "$agents_root/deploy"
check 'infra checkout' test -f "$infra_root/deploy"
check 'secrets checkout' test -e "$secrets_root/.git"

for tool in bash zsh git mise node python uv sops age nvim claude codex paseo t3 pi linear-cli htop mosh git-extras git-restore-mtime psql iotop bpftrace nvtop coderabbit cc make pkg-config; do
    check "$tool executes" "$tool" --version
done
check 'atop executes' atop -V
check 'netcat connects to the local HTTPS listener' nc -z -w 5 127.0.0.1 443
check 'socat executes' socat -V
check 'testssl executes' bash -c 'tool=$(command -v testssl || command -v testssl.sh) && "$tool" --version'
for completion in _bun _opencode; do
    completion_path=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fpath/$completion
    check "$completion generated" test -s "$completion_path"
    check "$completion parses" zsh -n "$completion_path"
done

check 'Python native standard-library modules' python -c 'import ctypes, ssl, sqlite3, lzma, bz2; ssl.create_default_context(); sqlite3.connect(":memory:")'
check 'Neovim starts with configured completion' sh "$dotfiles_root/scripts/tests/nvim-load-probe.sh"
check 'Node can spawn a PATH-resolved child' node -e 'require("node:child_process").execFileSync("bash", ["-c", "command -v git >/dev/null"]);'
check 'zsh login resolves mise and agent tools' zsh -lc 'for tool in mise node codex claude; do command -v "$tool" >/dev/null || exit 1; done'
check 'bash login resolves mise and agent tools' bash -lc 'for tool in mise node codex claude; do command -v "$tool" >/dev/null || exit 1; done'
check 'agents reserved env slot' test -L "$dotfiles_root/zsh/env.d/96_agents.zsh"
check 'secrets render readiness marker' test -s "$state_root/secrets-render-ok"
check 'secrets marker matches deployed checkouts' bash -c 'grep -Fxq "dotfiles_head=$(git -C "$1" rev-parse HEAD)" "$3" && grep -Fxq "secrets_head=$(git -C "$2" rev-parse HEAD)" "$3"' smoke "$dotfiles_root" "$secrets_root" "$state_root/secrets-render-ok"
check 'Caddy environment is private' bash -c 'file=$1; [[ -s $file && $(stat -c %a "$file") == 600 ]]' smoke "$state_root/caddy/env"
check 'Codex selected credential is private' bash -c 'file=$1; [[ -s $file && $(stat -L -c %a "$file") == 600 ]]' smoke "$state_root/codex/env"
check 'Codex auth cache is private' bash -c 'file=$1; [[ -s $file && $(stat -L -c %a "$file") == 600 ]]' smoke "${CODEX_HOME:-$HOME/.codex}/auth.json"
check 'rendered secrets are private' bash -c 'file=$1; [[ -s $file && $(stat -c %a "$file") == 600 ]]' smoke "$state_root/secrets/zsh/90_secrets.zsh"

for timer in pull-dotfiles.timer agents-check.timer converge-check.timer; do
    check "$timer enabled" systemctl --user is-enabled "$timer"
    check "$timer active" systemctl --user is-active "$timer"
done
for service in pull-dotfiles.service agents-check.service converge-check.service; do
    check "$service last run succeeded" bash -c '[[ $(systemctl --user show "$1" -p Result --value) == success && $(systemctl --user show "$1" -p ExecMainStatus --value) == 0 && $(systemctl --user show "$1" -p ExecMainStartTimestampMonotonic --value) -gt 0 ]]' smoke "$service"
done
for service in caddy portless-proxy tailscaled paseo-daemon atop atopacct keyd; do
    check "$service active" systemctl is-active "$service"
done
check 'atop rotation timer active' systemctl is-active atop-rotate.timer
check 'Paseo watchdog timer enabled' systemctl is-enabled paseo-watchdog.timer
check 'Paseo watchdog timer active' systemctl is-active paseo-watchdog.timer
check 'Paseo watchdog last run succeeded' bash -c '[[ $(systemctl show paseo-watchdog.service -p Result --value) == success && $(systemctl show paseo-watchdog.service -p ExecMainStatus --value) == 0 && $(systemctl show paseo-watchdog.service -p ExecMainStartTimestampMonotonic --value) -gt 0 ]]'
check 'Caddy serves verified HTTPS locally' bash -c '[[ $(curl -fsS --max-time 15 --resolve pluto.webfront.app:443:127.0.0.1 -o /dev/null -w "%{http_code}" https://pluto.webfront.app) == 200 ]]'
check 'Python verifies HTTPS with the default CA bundle' python -c 'import socket,ssl; connection=socket.create_connection(("127.0.0.1",443),timeout=15); ssl.create_default_context().wrap_socket(connection,server_hostname="pluto.webfront.app").close()'
check 'Paseo CLI and daemon pins agree' python "$dotfiles_root/scripts/tests/check-paseo-pins.py" --dotfiles "$dotfiles_root" --infra "$infra_root"
check 'running Paseo daemon has the declared version' bash -o pipefail -c 'expected=$(python "$1/scripts/tests/check-paseo-pins.py" --dotfiles "$1" --infra "$2" --print-daemon-tool) || exit; paseo daemon status | grep -Fx "daemonVersion: ${expected##*@}"' smoke "$dotfiles_root" "$infra_root"
check 'Paseo codex policy plugin is running' bash -o pipefail -c 'paseo plugin ls --json | python -c '\''import json,sys; rows=json.load(sys.stdin); sys.exit(0 if any(r.get("id")=="codex-policy" and r.get("enabled") and r.get("status")=="running" for r in rows) else 1)'\'''
check 'converge CLI executes' "$infra_root/bin/converge" --help

if (( failures )); then
    printf '%s\n' "$failures native acceptance check(s) failed." >&2
    exit 1
fi
printf '%s\n' 'All native acceptance checks passed.'
