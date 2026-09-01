#!/usr/bin/env zsh
#
# secrets-render.zsh — render the sops-encrypted canonical material in
# ~/.local/secrets into this machine's plaintext targets.
#
# Ciphertext is canonical, plaintext is derived. Edits go through
# `sops edit` / `sops set` in ~/.local/secrets, never into a rendered target.
#
# STANDALONE-SAFE. This runs from two places with very different shell state:
#   1. scripts/deploy.d/65_secrets.zsh (deploy.zsh has exported SCRIPT_DIR,
#      XDG_*, DEPLOY_DRY_RUN, and zmodload'ed the zf_* builtins), and
#   2. ~/.local/secrets/.git/hooks/post-merge, which has none of that.
# So it self-locates $DOTFILES from $0, defaults every XDG variable itself,
# reads ${DEPLOY_DRY_RUN:-0} with an explicit default, and uses only plain
# mkdir/install/ln/mv/cp — no zf_* builtins.
#
# NEVER prints a secret value. Every diagnostic names files and keys only.
#
# Usage:
#   zsh ~/.local/dotfiles/scripts/secrets-render.zsh [--dry-run]
#   ... --convert-dotenv    filter: KEY=value on stdin -> export lines on stdout
#                           (used by ~/.local/secrets/scripts/verify-render.zsh
#                            so the harness tests this exact converter)
#
# Environment:
#   DEPLOY_DRY_RUN=1   print intentions, mutate nothing
#   SECRETS_DIR        override the secrets clone (default ~/.local/secrets)
#
# Exit status: 0 when every gated target rendered, 1 otherwise.

emulate -L zsh
# typeset_silent: a bare `local x` on a name that already holds a value makes
# zsh *print* `x='...'` (the bug that once sprayed leaked locals into a real
# deploy log — see deploy.zsh's own note). Nothing here holds a secret value in
# a variable, but a renderer must not print anything it was not asked to.
setopt extended_glob typeset_silent

# ── dotenv -> zsh converter ────────────────────────────────────────────────
#
# Reads `KEY=value` lines (sops' dotenv output is verbatim: no quoting, no
# escaping, values may contain spaces/quotes/$/#/=) and emits `export` lines.
#
# Values are machine-quoted with ${(qq)} (single quotes) so nothing in a secret
# is ever re-interpreted by the shell. The one exception is a value that is
# exactly a reference to another variable — today `PORTKEY_API_KEY` is stored
# as `$PORTKEY_LOCAL_API_KEY`, an alias whose whole point is to follow the
# other key. Single-quoting that would turn a live alias into the literal
# string. Such values are emitted double-quoted so the reference still resolves
# at source time, preserving today's behaviour exactly.
secrets_convert_dotenv() {
    local line key val
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        [[ $line == \#* ]] && continue
        key=${line%%=*}
        val=${line#*=}
        if [[ $val == \$[A-Za-z_]##[A-Za-z_0-9]# ]]; then
            printf '%s\n' "export ${key}=\"${val}\""
        else
            printf '%s\n' "export ${key}=${(qq)val}"
        fi
    done
}

# ── Argument parsing ───────────────────────────────────────────────────────

_dry=${DEPLOY_DRY_RUN:-0}
while (( $# > 0 )); do
    case $1 in
        --convert-dotenv)
            secrets_convert_dotenv
            exit 0
            ;;
        --dry-run|-n)
            _dry=1
            ;;
        --help|-h)
            printf '%s\n' "usage: secrets-render.zsh [--dry-run] [--convert-dotenv]"
            exit 0
            ;;
        *)
            printf '%s\n' "secrets-render: unknown argument: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# ── Self-location and environment defaults ─────────────────────────────────

DOTFILES_DIR=${0:A:h:h}
# With systemd-homed, :A expands to the storage location /home/user.homedir
# rather than the mounted /home/user — massage it back (as save-secrets.zsh).
if [[ $DOTFILES_DIR == $HOME.homedir* ]]; then
    DOTFILES_DIR=${DOTFILES_DIR/.homedir/}
fi

SECRETS_REPO=${SECRETS_DIR:-$HOME/.local/secrets}
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
RENDER_STATE=$STATE_HOME/secrets
LEGACY_DIR=$RENDER_STATE/legacy-removed
MARKER=$STATE_HOME/secrets-render-ok

# sops looks for the age key at $XDG_CONFIG_HOME/sops/age/keys.txt, but cron
# and git hooks may run without XDG_CONFIG_HOME exported. Point sops at it.
if [[ -z ${SOPS_AGE_KEY_FILE:-} && -f $CONFIG_HOME/sops/age/keys.txt ]]; then
    export SOPS_AGE_KEY_FILE=$CONFIG_HOME/sops/age/keys.txt
fi

if [[ ! -d $SECRETS_REPO ]]; then
    printf '%s\n' "secrets-render: $SECRETS_REPO not found — nothing to render." >&2
    printf '%s\n' "  Bootstrap it with: ./deploy.zsh --only 65_secrets" >&2
    exit 1
fi

if ! command -v sops > /dev/null 2>&1; then
    printf '%s\n' "secrets-render: sops not found in PATH; run 'mise install' first." >&2
    exit 1
fi

# A box that has never completed a render gets its pre-existing targets backed
# up before they are first overwritten (see _render_row). Captured up front so
# writing the marker at the end cannot change the answer mid-run.
FIRST_RENDER=0
[[ -f $MARKER ]] || FIRST_RENDER=1

# ── Mapping table ──────────────────────────────────────────────────────────
#
# One row per target, hardcoded here rather than in a manifest inside the
# secrets repo: target paths are machine concerns, and a manifest would need a
# portable parser in the bootstrap layer. Unknown files in the secrets repo are
# reported by name at the end instead (see the unmapped scan).
#
# Rows are `|`-delimited records rather than parallel arrays: zsh arrays are
# 1-based and bash's are 0-based, so an index loop over six aligned arrays has
# no spelling that is correct in both shells. Records unpack field-by-field
# with ${rec%%|*}/${rec#*|}, identical in both.
#
#   field 1  src   path inside $SECRETS_REPO
#   field 2  kind  shellenv | dotenv | blob | copy
#   field 3  dst   absolute target path
#   field 4  mode  chmod applied to the rendered file
#   field 5  gate  all | ceres | immich | libris
#   field 6  post  (empty) | sshlink

MAP_ROWS=()

_row() {
    # The delimiter must never appear in a field; assert that here so a future
    # row with a `|` in a path fails loudly instead of truncating silently.
    case "$1$2$3$4$5$6" in
        *'|'*)
            printf '%s\n' "secrets-render: MAP row uses the '|' record delimiter in a field: $1" >&2
            exit 2
            ;;
    esac
    MAP_ROWS+=("$1|$2|$3|$4|$5|$6")
}

# Shell environment. Rendered out of every git worktree, into
# $XDG_STATE_HOME/secrets/zsh/, and sourced by zsh/env.d/89_secrets_loader.zsh.
# Basenames are preserved so local 90-99 overrides still win by load order.
_shell_file=
for _shell_file in 90_secrets 91_cloudflare_secrets 92_telemetry_secrets \
                   93_google_oauth_secrets 94_search_secrets \
                   94_zerotier_secrets 95_tailscale_secrets; do
    _row "shell/${_shell_file}.yaml" shellenv "$RENDER_STATE/zsh/${_shell_file}.zsh" 600 all ''
done

# Services. openclaw is ceres-only (server-side config for a bridge that runs
# on exactly one box); the immich rows are gated on the deploy dir already
# existing so live B2 credentials never land on a box that has no immich.
_row services/portkey/env.yaml            dotenv "$STATE_HOME/portkey/env"                 600 all    ''
_row services/portkey/local-api-key.enc   blob   "$STATE_HOME/portkey/local-api-key"       600 all    ''
_row services/openclaw/env.yaml           dotenv "$CONFIG_HOME/openclaw-mcp/env"           600 ceres  ''
# gjc (gajae-code): only .env is a secret (ZAI_API_KEY, OPENROUTER_API_KEY).
# Gated `all`, not ceres: config.yml's modelRoles.default is zai/glm-5.3, so a
# box without these keys starts gjc with a default model it cannot authenticate.
# The secret-free gjc files (models.yml, AGENTS.md, config.yml) live in the
# public repo under configs/ai/gjc/ and are symlinked onto every box by
# deploy.d/20_symlinks.zsh. config.yml was rendered here until the Discord
# notifications block (bot token, no env indirection) was dropped.
_row services/gjc/env.yaml                dotenv "$HOME/.gjc/agent/.env"                   600 all    ''
_row services/immich/b2-env.yaml          dotenv "$HOME/repos/deploy/immich/.b2-env"       600 immich ''
_row services/immich/restic-password.enc  blob   "$HOME/repos/deploy/immich/.restic-password" 600 immich ''
# libris (book/serial archiver on ceres) backs up to its own restic repo on
# saturn; same deploy-dir gate so the password lands only where libris lives.
_row services/libris/restic-password.enc   blob   "$HOME/repos/deploy/libris/.restic-password" 600 libris ''

# ssh. Rendered into $DOTFILES/ssh/ with the historical 600/644 modes, then
# symlinked into ~/.ssh/ (matching scripts/deploy.d/20_symlinks.zsh).
_row ssh/config             copy "$DOTFILES_DIR/ssh/config"           600 all sshlink
_row ssh/id_ed25519.enc     blob "$DOTFILES_DIR/ssh/id_ed25519"       600 all sshlink
_row ssh/id_ed25519.pub     copy "$DOTFILES_DIR/ssh/id_ed25519.pub"   644 all sshlink
_row ssh/webfront_claw.enc  blob "$DOTFILES_DIR/ssh/webfront_claw"    600 all sshlink
_row ssh/webfront_claw.pub  copy "$DOTFILES_DIR/ssh/webfront_claw.pub" 644 all sshlink

# portless local CA + server cert, behind the ~/.portless symlink.
_row portless/ca.pem              copy "$DOTFILES_DIR/configs/portless/ca.pem"         644 all ''
_row portless/ca-key.pem.enc      blob "$DOTFILES_DIR/configs/portless/ca-key.pem"     600 all ''
_row portless/server.pem          copy "$DOTFILES_DIR/configs/portless/server.pem"     644 all ''
_row portless/server-key.pem.enc  blob "$DOTFILES_DIR/configs/portless/server-key.pem" 600 all ''

# Legacy in-tree plaintexts superseded by the shell/ rows above. They must
# leave zsh/env.d/ or they shadow rendered (and rotated) values: .zshenv
# sources env.d/* lexically and 9x sorts after the 89_ loader. Moved, never
# deleted — a box's hand-edit is triaged from legacy-removed/, not destroyed.
LEGACY_PLAINTEXTS=()
LEGACY_PLAINTEXTS=(
    "$DOTFILES_DIR/zsh/env.d/90_secrets.zsh"
    "$DOTFILES_DIR/zsh/env.d/91_cloudflare_secrets.zsh"
    "$DOTFILES_DIR/zsh/env.d/92_telemetry_secrets.zsh"
    "$DOTFILES_DIR/zsh/env.d/93_google_oauth_secrets.zsh"
    "$DOTFILES_DIR/zsh/env.d/94_search_secrets.zsh"
    "$DOTFILES_DIR/zsh/env.d/94_zerotier_secrets.zsh"
    "$DOTFILES_DIR/zsh/env.d/95_tailscale_secrets.zsh"
)

# Tracked files that are deliberately not render sources.
UNMAPPED_ALLOW=()
UNMAPPED_ALLOW=(README.md .sops.yaml .gitattributes .gitignore)

# ── Helpers ────────────────────────────────────────────────────────────────

_gate_open() {
    case $1 in
        all)    return 0 ;;
        ceres)  [[ $(hostname -s 2>/dev/null) == ceres ]] ;;
        immich) [[ -d $HOME/repos/deploy/immich ]] ;;
        libris) [[ -d $HOME/repos/deploy/libris ]] ;;
        *)      return 1 ;;
    esac
}

# Absolute target path -> flat backup filename (slashes become __).
_backup_name() {
    local p=${1#/}
    printf '%s\n' "${p//\//__}"
}

# ── Render ─────────────────────────────────────────────────────────────────

N_RENDERED=0 N_SKIPPED=0 N_FAILED=0 N_BACKED_UP=0
FAILED_NAMES=() SSH_LINKS=()

_row_rec=
for _row_rec in "${MAP_ROWS[@]}"; do
    src_name=${_row_rec%%|*}
    _rest=${_row_rec#*|}
    src=$SECRETS_REPO/$src_name
    kind=${_rest%%|*}; _rest=${_rest#*|}
    dst=${_rest%%|*}; _rest=${_rest#*|}
    mode=${_rest%%|*}; _rest=${_rest#*|}
    gate=${_rest%%|*}
    post=${_rest#*|}

    if ! _gate_open $gate; then
        (( N_SKIPPED++ ))
        continue
    fi

    if [[ ! -f $src ]]; then
        printf '%s\n' "  FAILED $src_name: missing from $SECRETS_REPO" >&2
        FAILED_NAMES+=("$src_name")
        (( N_FAILED++ ))
        continue
    fi

    if (( _dry )); then
        printf '%s\n' "  [dry-run] would render $src_name -> $dst (mode $mode)"
        (( N_RENDERED++ ))
        [[ $post == sshlink ]] && SSH_LINKS+=("$dst")
        continue
    fi

    # The target's directory has to exist before mktemp, because the temp file
    # is created THERE and not in $TMPDIR: a rename is only atomic within one
    # filesystem, and $TMPDIR is routinely a different one (tmpfs). A
    # cross-device `mv` degrades to copy-then-unlink, which can leave a
    # half-written private key if the box dies mid-render.
    dstdir=${dst:h}
    if [[ ! -d $dstdir ]]; then
        if [[ $mode == 600 ]]; then
            install -m 700 -d $dstdir
        else
            mkdir -p $dstdir
        fi
    fi

    # Every write is mktemp -> chmod -> mv, so a mid-render failure leaves the
    # existing target byte-for-byte untouched.
    tmp=
    tmp=$(mktemp "${dst}.render.XXXXXX") || {
        printf '%s\n' "  FAILED $src_name: mktemp in $dstdir" >&2
        FAILED_NAMES+=("$src_name"); (( N_FAILED++ )); continue
    }
    chmod 600 $tmp

    ok=1
    case $kind in
        shellenv)
            {
                printf '%s\n' "# MANAGED BY ~/.local/secrets ($src_name) — edit via sops, not here."
                printf '%s\n' "# Rendered by ~/.local/dotfiles/scripts/secrets-render.zsh; changes here are lost."
                sops -d --output-type dotenv $src | secrets_convert_dotenv
            } > $tmp 2>/dev/null || ok=0
            # A failed sops leaves a header-only file; treat that as failure.
            (( ok )) && [[ $(grep -c '^export ' $tmp) -gt 0 ]] || ok=0
            ;;
        dotenv)
            sops -d --output-type dotenv $src > $tmp 2>/dev/null || ok=0
            ;;
        blob)
            sops -d --input-type binary --output-type binary $src > $tmp 2>/dev/null || ok=0
            ;;
        copy)
            cat $src > $tmp 2>/dev/null || ok=0
            ;;
        *)
            ok=0
            ;;
    esac

    if (( ! ok )); then
        rm -f $tmp
        printf '%s\n' "  FAILED $src_name: decrypt/render error (age key registered?)" >&2
        FAILED_NAMES+=("$src_name")
        (( N_FAILED++ ))
        continue
    fi

    # First-render cutover backup: on a box that has never completed a render,
    # any pre-existing target whose bytes differ from what we are about to
    # write is copied aside first. First-write-wins, so a retry after a K>0 run
    # can never overwrite a genuine pre-cutover backup with rendered bytes.
    if (( FIRST_RENDER )) && [[ -f $dst ]] && ! cmp -s $tmp $dst; then
        [[ -d $LEGACY_DIR ]] || install -m 700 -d $LEGACY_DIR
        backup="$LEGACY_DIR/$(_backup_name "$dst")"
        if [[ ! -e $backup ]]; then
            cp $dst $backup && (( N_BACKED_UP++ ))
            printf '%s\n' "  backed up pre-existing $dst -> legacy-removed/${backup:t}"
        fi
    fi

    chmod $mode $tmp
    mv -f $tmp $dst
    (( N_RENDERED++ ))
    [[ $post == sshlink ]] && SSH_LINKS+=("$dst")
done

# ~/.ssh symlinks into the rendered dotfiles copies.
_link=
for _link in $SSH_LINKS; do
    if (( _dry )); then
        printf '%s\n' "  [dry-run] would link $HOME/.ssh/${_link:t} -> $_link"
    else
        [[ -d $HOME/.ssh ]] || install -m 700 -d $HOME/.ssh
        ln -sfn $_link $HOME/.ssh/${_link:t}
    fi
done

# ── Legacy-plaintext quarantine ────────────────────────────────────────────

N_QUARANTINED=0
STILL_SHADOWING=()
_legacy=
if (( N_FAILED == 0 && ! _dry )); then
    for _legacy in $LEGACY_PLAINTEXTS; do
        [[ -f $_legacy ]] || continue
        [[ -d $LEGACY_DIR ]] || install -m 700 -d $LEGACY_DIR
        q="$LEGACY_DIR/$(_backup_name "$_legacy")"
        if [[ -e $q ]]; then
            # A previous run already banked these bytes; keep the older copy
            # and park this one beside it rather than losing either.
            q=$q.$(date -u '+%Y%m%dT%H%M%SZ')
        fi
        mv -f $_legacy $q && (( N_QUARANTINED++ ))
    done
elif (( N_FAILED > 0 )); then
    # A failed render skips the quarantine entirely, so say plainly which
    # stale basenames are still in the load path shadowing rendered values.
    for _legacy in $LEGACY_PLAINTEXTS; do
        [[ -f $_legacy ]] && STILL_SHADOWING+=("${_legacy:t}")
    done
fi

# ── Unmapped-file detection ────────────────────────────────────────────────

# Membership without zsh's [(I)] reverse-index subscripts (which are a bad
# substitution under bash): a linear scan of tiny arrays is identical in both
# shells. The needle is quoted on the RHS of == so a `*` in a filename can
# never glob-match.
_in_list() {
    _needle=$1
    shift
    for _hay in "$@"; do
        [[ $_hay == "$_needle" ]] && return 0
    done
    return 1
}

_is_mapped() {
    for _rec in "${MAP_ROWS[@]}"; do
        [[ ${_rec%%|*} == "$1" ]] && return 0
    done
    return 1
}

UNMAPPED=()
while IFS= read -r _tracked; do
    [[ -z $_tracked ]] && continue
    [[ $_tracked == scripts/* ]] && continue
    _in_list "$_tracked" "${UNMAPPED_ALLOW[@]}" && continue
    _is_mapped "$_tracked" && continue
    UNMAPPED+=("$_tracked")
done < <(git -C $SECRETS_REPO ls-files 2>/dev/null)

# ── Summary + marker ───────────────────────────────────────────────────────

printf '%s\n' "  rendered ${N_RENDERED}, quarantined ${N_QUARANTINED}, backed-up ${N_BACKED_UP}, unmapped ${#UNMAPPED[@]}, gated-out ${N_SKIPPED}, failed ${N_FAILED}"
(( ${#UNMAPPED[@]} )) && printf '%s\n' "  UNMAPPED (in secrets repo, never rendered): ${(j:, :)UNMAPPED}"
(( ${#FAILED_NAMES[@]} )) && printf '%s\n' "  FAILED: ${(j:, :)FAILED_NAMES}" >&2
if (( ${#STILL_SHADOWING[@]} )); then
    printf '%s\n' "  WARNING: stale legacy plaintexts still in zsh/env.d/ and will shadow rendered values until a full render succeeds: ${(j:, :)STILL_SHADOWING}" >&2
fi

if (( N_FAILED > 0 )); then
    exit 1
fi

if (( ! _dry )); then
    dot_head= sec_head=
    dot_head=$(git -C $DOTFILES_DIR rev-parse HEAD 2>/dev/null || printf '%s\n' unknown)
    sec_head=$(git -C $SECRETS_REPO rev-parse HEAD 2>/dev/null || printf '%s\n' unknown)
    [[ -d ${MARKER:h} ]] || mkdir -p ${MARKER:h}
    {
        printf '%s\n' "rendered_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '%s\n' "dotfiles_head=$dot_head"
        printf '%s\n' "secrets_head=$sec_head"
        printf '%s\n' "host=$(hostname -s 2>/dev/null || printf '%s\n' unknown)"
    } > $MARKER
    chmod 644 $MARKER
fi

exit 0
