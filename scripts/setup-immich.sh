#!/usr/bin/env bash
set -euo pipefail

# setup-immich.sh - lay down the Immich deploy tree and its systemd units.
#
# WHAT THIS EXISTS FOR: until 2026-09-03 ~/repos/deploy was not a git repo at
# all, so the compose file that defines the photo library and the units that
# drive its nightly backup existed on exactly one disk. Losing that box lost
# the ability to rebuild the thing doing the backing up. This script plus
# configs/immich/ is the reconstruction path.
#
# SOURCES OF TRUTH, and this script owns none of them:
#   configs/immich/docker-compose.yaml   this repo (public)     -> stack shape
#   configs/immich/example.env           this repo (public)     -> .env template
#   ~/repos/photo-steward/ops/*.sh       camerontaylor/photo-steward (private)
#                                                               -> backup/prune scripts
#   ~/repos/photo-steward/ops/hart-*     same                    -> systemd units
#   ~/.local/secrets/services/immich/    camerontaylor/dotfiles-secrets (private)
#                                                               -> restic + B2 creds
# The script INSTALLS those; it never generates a competing copy. Where a live
# file already differs from its source it reports the diff and leaves the live
# file alone (setup-caddy.sh learned that lesson the expensive way).
#
# WHAT IT WILL NOT DO, ever: touch a container. No up, no down, no restart, no
# recreate, no pull. The stack on ceres has been up for days and is snapshotted
# nightly; a config installer has no business interrupting that. Applying a
# changed compose file is a deliberate human `docker compose up -d`.
#
# Usage: setup-immich.sh [--check|--dry-run] [--force] [--prefix DIR]
#
#   --check / --dry-run  report what would change; mutate nothing. Exit 0 when
#                        already installed and consistent, 1 when work remains.
#   --force              overwrite a live docker-compose.yaml / example.env that
#                        has drifted from the tracked copy. Never touches .env.
#   --prefix DIR         install the deploy tree under DIR instead of
#                        ~/repos/deploy/immich, and skip the systemd stage.
#                        For proving a from-nothing install without going near
#                        the live one.
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
      sed -n '6,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1 (try --help)" >&2
      exit 2
      ;;
  esac
  shift
done

# macOS has no Immich stack anywhere on this fleet (saturn runs only the ML
# offload, which photo-steward's launchd plist installs). Refuse rather than
# scatter a half-tree. This script is NOT wired into deploy.d, so a Mac
# `./deploy.zsh` never reaches here regardless - the guard is for a hand-run.
if [[ "$OS" != "Linux" && -z "$PREFIX" ]]; then
  echo "setup-immich: the Immich stack is Linux-only on this fleet (host: $OS)."
  echo "  saturn/neptune run no Immich containers; saturn's ML offload is"
  echo "  installed by photo-steward's dev.hart.immich-ml.plist, not this script."
  echo "  Use --prefix DIR to lay down a tree here anyway (no systemd stage)."
  exit 0
fi

STANDALONE=0
if [[ -n "$PREFIX" ]]; then
  DEPLOY_DIR=$PREFIX
  STANDALONE=1
else
  DEPLOY_DIR="$HOME/repos/deploy/immich"
fi
BIN_DIR="$DEPLOY_DIR/bin"
UNIT_DIR="$HOME/.config/systemd/user"
OPS_DIR="$HOME/repos/photo-steward/ops"
SECRETS_DIR="${SECRETS_DIR:-$HOME/.local/secrets}"

TRACKED_COMPOSE="$REPO_ROOT/configs/immich/docker-compose.yaml"
TRACKED_EXAMPLE="$REPO_ROOT/configs/immich/example.env"

PENDING=0    # work this run would do (or did)
BLOCKED=0    # work it cannot do without a human

say()   { printf '  %s\n' "$*"; }
head2() { printf '\n== %s\n' "$*"; }
todo()  { PENDING=$((PENDING + 1)); printf '  [would] %s\n' "$*"; }
did()   { PENDING=$((PENDING + 1)); printf '  [done]  %s\n' "$*"; }
ok()    { printf '  [ok]    %s\n' "$*"; }
blok()  { BLOCKED=$((BLOCKED + 1)); printf '  [BLOCK] %s\n' "$*"; }

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
# Different -> show the diff and REFUSE unless --force, because on ceres these
# paths back a running stack and silent convergence is how you lose a working
# config to a stale one.
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

# Symlink that is a no-op when it already points where it should.
ensure_link() {
  local target=$1 link=$2 label=$3
  if [[ ! -e "$target" ]]; then
    blok "$label: link target missing: $target"
    return
  fi
  if [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$target")" ]]; then
    ok "$label -> $target"
    return
  fi
  if [[ -e "$link" && ! -L "$link" ]]; then
    blok "$label: $link exists and is not a symlink; move it aside first"
    return
  fi
  if (( DRY_RUN )); then todo "link $link -> $target"; return; fi
  ln -sfn "$target" "$link"
  did "linked $link -> $target"
}

# ── stage 1: the deploy tree ───────────────────────────────────────────────

head2 "deploy tree: $DEPLOY_DIR"
ensure_dir "$DEPLOY_DIR"
ensure_dir "$BIN_DIR"
install_tracked "$TRACKED_COMPOSE" "$DEPLOY_DIR/docker-compose.yaml" "docker-compose.yaml"
install_tracked "$TRACKED_EXAMPLE" "$DEPLOY_DIR/example.env"          "example.env"

# ── stage 2: .env ──────────────────────────────────────────────────────────
#
# Seeded from the template, never overwritten, and never converged: a live .env
# holds this machine's real DB_PASSWORD, which is baked into the postgres data
# directory at first init. Overwriting it does not change the database - it
# just makes the stack unable to authenticate to its own data.

head2 ".env"
ENV_FILE="$DEPLOY_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  if (( DRY_RUN )); then
    todo "seed $ENV_FILE from example.env (then fill CHANGEME values)"
  elif [[ -f "$TRACKED_EXAMPLE" ]]; then
    install -m 600 "$TRACKED_EXAMPLE" "$ENV_FILE"
    did "seeded $ENV_FILE from example.env (mode 600)"
    blok ".env holds CHANGEME placeholders - fill DB_PASSWORD before first start"
  fi
else
  ok ".env present (not touched; it carries this machine's real values)"
  if grep -q 'CHANGEME' "$ENV_FILE" 2>/dev/null; then
    blok ".env still contains CHANGEME placeholders: $(grep -c CHANGEME "$ENV_FILE") line(s)"
  fi
  # Report keys the template knows about that this .env has never heard of,
  # without printing a single value from either side.
  missing=$(comm -23 \
    <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$TRACKED_EXAMPLE" | sort -u) \
    <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$ENV_FILE"        | sort -u) || true)
  if [[ -n "$missing" ]]; then
    say "note: keys in example.env absent from .env: $(echo "$missing" | tr '\n' ' ')"
  fi
fi

# ── stage 3: backup + prune scripts ────────────────────────────────────────
#
# Symlinks into photo-steward rather than copies: those scripts are versioned
# there, evolve with the captioning pipeline beside them, and the whole fleet's
# systemd convention on ceres is "unit and script live in their owning repo,
# ~/.config points at them". A copy here would fork on the first edit.

head2 "backup scripts"
if [[ ! -d "$OPS_DIR" ]]; then
  blok "photo-steward not present at ${OPS_DIR%/ops}"
  say  "      git clone git@github.com:camerontaylor/photo-steward.git ~/repos/photo-steward"
  say  "      then re-run this script"
else
  ensure_link "$OPS_DIR/immich-backup.sh" "$BIN_DIR/immich-backup.sh" "bin/immich-backup.sh"
  ensure_link "$OPS_DIR/immich-prune.sh"  "$BIN_DIR/immich-prune.sh"  "bin/immich-prune.sh"
fi

# ── stage 4: secrets ───────────────────────────────────────────────────────
#
# Reports presence only. This script never decrypts, never prompts for and
# never writes a credential - it says which are missing and who owns them.
#
#   .restic-password  } rendered from ~/.local/secrets by
#   .b2-env           } scripts/secrets-render.zsh, gated on this deploy dir
#                       EXISTING - which is why stage 1 runs before this one.
#   .api-key          Immich API key, used to trigger the pre-backup DB dump.
#                     Currently machine-local: not in dotfiles-secrets. Its
#                     absence degrades the backup (the script warns and falls
#                     back to the last scheduled dump) rather than failing it.

head2 "secrets"
check_secret() {
  local path=$1 label=$2 owner=$3 fatal=$4 mode
  if [[ -s "$path" ]]; then
    mode=$(stat -c '%a' "$path" 2>/dev/null || echo '?')
    ok "$label present (mode $mode, $(wc -c <"$path") bytes)"
    # A credential the group or world can read is a finding, not a fix: the
    # file is live and something unknown may depend on reading it. Say so.
    if [[ "$mode" =~ ^[0-7][1-7][0-7]$ || "$mode" =~ ^[0-7][0-7][1-7]$ ]]; then
      say "[warn]  $label is mode $mode - a credential should be 600."
      say "        Tighten with: chmod 600 $path"
    fi
    return
  fi
  if [[ "$fatal" == fatal ]]; then
    blok "$label MISSING - $owner"
  else
    say "[warn]  $label missing - $owner"
  fi
}
check_secret "$DEPLOY_DIR/.restic-password" ".restic-password" \
  "rendered from ~/.local/secrets/services/immich/restic-password.enc; run: ./deploy.zsh --only 65_secrets" fatal
check_secret "$DEPLOY_DIR/.b2-env" ".b2-env" \
  "rendered from ~/.local/secrets/services/immich/b2-env.yaml; run: ./deploy.zsh --only 65_secrets" fatal
check_secret "$DEPLOY_DIR/.api-key" ".api-key" \
  "machine-local; mint one in Immich (Account Settings > API Keys) and write it here, mode 600" warn

if [[ ! -d "$SECRETS_DIR" ]]; then
  say "note: $SECRETS_DIR absent - the render step has nothing to read from."
  say "      Bootstrap it with: ./deploy.zsh --only 65_secrets"
fi

if (( STANDALONE )); then
  head2 "summary (standalone prefix: systemd stage skipped)"
  printf '  pending=%d blocked=%d\n' "$PENDING" "$BLOCKED"
  (( DRY_RUN && (PENDING || BLOCKED) )) && exit 1
  (( BLOCKED )) && exit 1
  exit 0
fi

# ── stage 5: systemd user units ────────────────────────────────────────────
#
# The timer and the prune service are secret-free and installed verbatim from
# photo-steward. The backup SERVICE is not: it carries IMMICH_API_KEY inline,
# so it is rendered from a .template with the key substituted at install time
# and written 600. That is why this one unit is a real file on ceres while
# every other unit in ~/.config/systemd/user is a symlink into its repo - a
# symlink would publish the key into a git repo.
#
# Timers are ENABLED but never STARTED, and no service is ever started here.
# Enabling a timer schedules the next run; starting the service would fire a
# 42 GiB backup because a config script ran.

head2 "systemd user units"
if [[ ! -d "$OPS_DIR" ]]; then
  blok "photo-steward absent; cannot install units"
else
  ensure_dir "$UNIT_DIR"

  for u in hart-immich-backup.timer hart-immich-prune.service hart-immich-prune.timer; do
    install_tracked "$OPS_DIR/$u" "$UNIT_DIR/$u" "$u"
  done

  TPL="$OPS_DIR/hart-immich-backup.service.template"
  DST="$UNIT_DIR/hart-immich-backup.service"
  if [[ ! -f "$TPL" ]]; then
    blok "missing template: $TPL"
  elif [[ ! -s "$DEPLOY_DIR/.api-key" ]]; then
    if [[ -f "$DST" ]]; then
      ok "hart-immich-backup.service present (leaving intact; no .api-key to re-render from)"
    else
      blok "cannot render hart-immich-backup.service: $DEPLOY_DIR/.api-key is missing"
    fi
  else
    rendered=$(mktemp); chmod 600 "$rendered"
    trap 'rm -f "$rendered"' EXIT
    # awk, not sed: an API key can contain characters sed's s/// would treat as
    # delimiters or backreferences. Read the key from the file, never from argv
    # (argv is world-readable in /proc).
    awk -v keyfile="$DEPLOY_DIR/.api-key" '
      BEGIN { getline key < keyfile; sub(/[ \t\r\n]+$/, "", key) }
      /^Environment=IMMICH_API_KEY=/ { print "Environment=IMMICH_API_KEY=" key; next }
      { print }
    ' "$TPL" > "$rendered"

    if [[ -f "$DST" ]] && cmp -s "$rendered" "$DST"; then
      ok "hart-immich-backup.service matches rendered template"
    elif (( DRY_RUN )); then
      todo "render hart-immich-backup.service from template (mode 600)"
    else
      install -m 600 "$rendered" "$DST"
      did "rendered $DST (mode 600, API key substituted)"
    fi
    rm -f "$rendered"; trap - EXIT
  fi

  # daemon-reload only when something actually changed on disk. In --check the
  # reload itself is not reportable work: reporting it unconditionally would
  # mean a fully-installed machine could never come back clean, which is the
  # one answer this mode exists to give.
  if (( DRY_RUN )); then
    for t in hart-immich-backup.timer hart-immich-prune.timer; do
      if systemctl --user is-enabled --quiet "$t" 2>/dev/null; then
        ok "$t already enabled"
      else
        todo "systemctl --user enable $t"
      fi
    done
  else
    systemctl --user daemon-reload
    for t in hart-immich-backup.timer hart-immich-prune.timer; do
      if systemctl --user is-enabled --quiet "$t" 2>/dev/null; then
        ok "$t already enabled"
      else
        systemctl --user enable "$t" >/dev/null
        did "enabled $t"
      fi
    done
  fi
fi

# ── summary ────────────────────────────────────────────────────────────────

head2 "summary"
if (( DRY_RUN )); then
  if (( PENDING == 0 && BLOCKED == 0 )); then
    say "already installed and consistent - a real run would change nothing."
    exit 0
  fi
  printf '  %d change(s) pending, %d blocked on a human.\n' "$PENDING" "$BLOCKED"
  exit 1
fi

printf '  %d change(s) applied, %d blocked on a human.\n' "$PENDING" "$BLOCKED"
say "no container was started, stopped or recreated by this script."
if (( BLOCKED )); then
  say "resolve the [BLOCK] lines above, then re-run."
  exit 1
fi
say "next scheduled backup:"
systemctl --user list-timers --all 2>/dev/null \
  | awk 'NR==1 || /hart-immich/' | sed 's/^/    /' || true
exit 0
