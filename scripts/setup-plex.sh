#!/usr/bin/env bash
set -euo pipefail

# setup-plex.sh - lay down the Plex deploy tree.
#
# WHAT THIS EXISTS FOR: ~/repos/deploy is not a git repo, and until this
# script the plex compose file - 150 lines of load-bearing decisions (host
# networking for GDM/remote access, read-only media binds with one writable
# "Plex Versions" hole, create_host_path:false against the unplugged-drive
# failure mode, tmpfs transcode scratch, /dev/dri + render-gid passthrough)
# - existed on exactly one disk. Losing makemake lost the ability to rebuild
# the media server. This script plus configs/plex/ is the reconstruction
# path; the same shape setup-immich.sh has had since 2026-09-03.
#
# SOURCES OF TRUTH, and this script owns none of them:
#   configs/plex/docker-compose.yaml   this repo (public) -> stack shape
#   configs/plex/example.env           this repo (public) -> .env template
#   ~/.local/infra/manifests/makemake.toml  camerontaylor/infra (private-ish)
#                                       -> as-built manifest: containers,
#                                          paths (path:media, path:plex/config),
#                                          the deep runbook notes. Manifest
#                                          edits are HUMAN-ONLY per its
#                                          AGENTS.md; this script never
#                                          touches that repo.
#   .env                                machine-local - holds the one-shot
#                                       PLEX_CLAIM token; NEVER committed.
# The script INSTALLS those; it never generates a competing copy. Where a live
# file already differs from its source it reports the diff and leaves the live
# file alone (setup-caddy.sh learned that lesson the expensive way).
#
# WHAT IT WILL NOT DO, ever: touch a container. No up, no down, no restart, no
# recreate, no pull. The stack on makemake has been up since 2026-09-11;
# applying a changed compose file is a deliberate human `docker compose up -d`.
# (One plex-specific sharp edge: PLEX_CLAIM from https://plex.tv/claim EXPIRES
# 4 MINUTES after issue, so on a fresh machine fetch it immediately before the
# first up, then blank it - the running server stays claimed either way.)
#
# Usage: setup-plex.sh [--check|--dry-run] [--force] [--prefix DIR]
#
#   --check / --dry-run  report what would change; mutate nothing. Exit 0 when
#                        already installed and consistent, 1 when work remains.
#   --force              overwrite a live docker-compose.yaml / example.env that
#                        has drifted from the tracked copy. Never touches .env.
#   --prefix DIR         install the deploy tree under DIR instead of
#                        ~/repos/deploy/plex. For proving a from-nothing
#                        install without going near the live one.
#
# Idempotent: a second run on a configured machine is a no-op and says so.

OS=$(uname -s)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

DRY_RUN=0
FORCE=0
PREFIX=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--dry-run) DRY_RUN=1 ;;
    --force)           FORCE=1 ;;
    --prefix)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "ERROR: --prefix requires a directory" >&2
        exit 2
      fi
      PREFIX=$2
      shift
      ;;
    --prefix=*) PREFIX=${1#--prefix=} ;;
    -h|--help)
      sed -n '6,44p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1 (try --help)" >&2
      exit 2
      ;;
  esac
  shift
done

# No Mac on this fleet runs Plex (only makemake does). Refuse rather than
# scatter a half-tree. Not wired into deploy.d, so a Mac ./deploy.zsh never
# reaches here regardless - the guard is for a hand-run.
if [[ "$OS" != "Linux" && -z "$PREFIX" ]]; then
  echo "setup-plex: the Plex stack is Linux-only on this fleet (host: $OS)."
  echo "  Use --prefix DIR to lay down a tree here anyway."
  exit 0
fi

if [[ -n "$PREFIX" ]]; then
  DEPLOY_DIR=$PREFIX
else
  DEPLOY_DIR="$HOME/repos/deploy/plex"
fi

TRACKED_COMPOSE="$REPO_ROOT/configs/plex/docker-compose.yaml"
TRACKED_EXAMPLE="$REPO_ROOT/configs/plex/example.env"

PENDING=0    # work this run would do (or did)

say()   { printf '  %s\n' "$*"; }
head2() { printf '\n== %s\n' "$*"; }
todo()  { PENDING=$((PENDING + 1)); printf '  [would] %s\n' "$*"; }
did()   { PENDING=$((PENDING + 1)); printf '  [done]  %s\n' "$*"; }
ok()    { printf '  [ok]    %s\n' "$*"; }
warn()  { printf '  [warn]  %s\n' "$*"; }
blok()  { printf '  [BLOCK] %s\n' "$*"; }

# mkdir that reports, honours --check, and is silent when already right.
ensure_dir() {
  local d=$1 mode=${2:-755}
  if [[ -d "$d" ]]; then
    ok "dir exists: $d"
    return
  fi
  if (( DRY_RUN )); then todo "mkdir -m $mode -p $d"; return; fi
  install -d -m "$mode" "$d"
  did "created $d (mode $mode)"
}

# Install a tracked file to a live path. Absent -> copy. Identical -> no-op.
# Different -> show the diff and REFUSE unless --force, because on makemake
# these paths back a running stack and silent convergence is how you lose a
# working config to a stale one.
install_tracked() {
  local src=$1 dst=$2 label=$3
  if [[ ! -f "$src" ]]; then
    blok "$label: tracked source missing: $src"
    return
  fi
  if [[ ! -f "$dst" ]]; then
    if (( DRY_RUN )); then todo "install $label -> $dst"; return; fi
    install -m 644 "$src" "$dst"
    did "installed $label -> $dst"
    return
  fi
  if cmp -s "$src" "$dst"; then
    ok "$label matches tracked copy"
    return
  fi
  printf '  [DRIFT] %s differs from %s\n' "$dst" "$src"
  diff -u "$dst" "$src" | sed 's/^/          /' || true
  if (( ! FORCE )); then
    blok "$label: live file has drifted; re-run with --force to overwrite, or"
    say  "        copy the live file back into the repo if IT is the newer truth"
    return
  fi
  if (( DRY_RUN )); then todo "OVERWRITE $dst from tracked copy (--force)"; return; fi
  install -m 644 "$src" "$dst"
  did "overwrote $dst from tracked copy (--force)"
}

# ── stage 1: the deploy tree ───────────────────────────────────────────────

head2 "deploy tree: $DEPLOY_DIR"
ensure_dir "$DEPLOY_DIR"
install_tracked "$TRACKED_COMPOSE" "$DEPLOY_DIR/docker-compose.yaml" "docker-compose.yaml"
install_tracked "$TRACKED_EXAMPLE" "$DEPLOY_DIR/example.env"          "example.env"

# ── stage 2: .env ──────────────────────────────────────────────────────────
#
# Seeded from the template, never overwritten, and never converged: a live .env
# holds this machine's PLEX_CLAIM (one-shot; blank it after first start) and
# the ADVERTISE_IP that survived plex.tv's CGNAT 403 minefield - see the
# manifest notes in ~/.local/infra/manifests/makemake.toml for why that value
# must be exactly https://plex.wedrifid.dev:443/ and nothing else.

head2 ".env"
ENV_FILE="$DEPLOY_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  if (( DRY_RUN )); then
    todo "seed $ENV_FILE from example.env (mode 600)"
  elif [[ -f "$TRACKED_EXAMPLE" ]]; then
    install -m 600 "$TRACKED_EXAMPLE" "$ENV_FILE"
    did "seeded $ENV_FILE from example.env (mode 600)"
  fi
else
  ok ".env present (not touched; it carries this machine's real values)"
fi

# The one thing worth blocking on: hardware transcode depends on the render
# group existing on the host, and the compose hard-codes its gid (992). If
# this host's render gid differs, the passthrough silently fails at runtime.
# Report, don't fix: choosing a different gid is a compose edit.
RENDER_GID=$(stat -c '%g' /dev/dri/renderD128 2>/dev/null || true)
if [[ -n "$RENDER_GID" && "$RENDER_GID" != 992 ]]; then
  warn "this host's render gid is $RENDER_GID but the compose pins group_add 992"
  say  "      (makemake's); hardware transcode will fail to open the device here."
  say  "      Edit the compose (and the tracked copy) if deploying to this host."
fi

# Report keys the template knows about that this .env has never heard of,
# without printing a single value from either side.
if [[ -f "$ENV_FILE" && -f "$TRACKED_EXAMPLE" ]]; then
  missing=$(comm -23 \
    <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$TRACKED_EXAMPLE" | sort -u) \
    <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$ENV_FILE"        | sort -u) || true)
  if [[ -n "$missing" ]]; then
    warn "keys in example.env absent from .env: $(echo "$missing" | tr '\n' ' ')"
  fi
fi

# ── summary ────────────────────────────────────────────────────────────────

head2 "summary"
if (( DRY_RUN )); then
  if (( PENDING == 0 )); then
    say "already installed and consistent - a real run would change nothing."
    exit 0
  fi
  printf '  %d change(s) pending.\n' "$PENDING"
  exit 1
fi

printf '  %d change(s) applied.\n' "$PENDING"
say "no container was started, stopped or recreated by this script."
say "first start on a fresh machine: fetch https://plex.tv/claim LAST (4-min"
say "expiry), fill PLEX_CLAIM in $DEPLOY_DIR/.env, then docker compose up -d."
exit 0
