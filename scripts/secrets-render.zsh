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
            print -r -- "export ${key}=\"${val}\""
        else
            print -r -- "export ${key}=${(qq)val}"
        fi
    done
}

# ── Argument parsing ───────────────────────────────────────────────────────

typeset _dry=${DEPLOY_DRY_RUN:-0}
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
            print "usage: secrets-render.zsh [--dry-run] [--convert-dotenv]"
            exit 0
            ;;
        *)
            print "secrets-render: unknown argument: $1 (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

# ── Self-location and environment defaults ─────────────────────────────────

typeset DOTFILES_DIR=${0:A:h:h}
# With systemd-homed, :A expands to the storage location /home/user.homedir
# rather than the mounted /home/user — massage it back (as save-secrets.zsh).
if [[ $DOTFILES_DIR == $HOME.homedir* ]]; then
    DOTFILES_DIR=${DOTFILES_DIR/.homedir/}
fi

typeset SECRETS_REPO=${SECRETS_DIR:-$HOME/.local/secrets}
typeset STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
typeset CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
typeset RENDER_STATE=$STATE_HOME/secrets
typeset LEGACY_DIR=$RENDER_STATE/legacy-removed
typeset MARKER=$STATE_HOME/secrets-render-ok

# sops looks for the age key at $XDG_CONFIG_HOME/sops/age/keys.txt, but cron
# and git hooks may run without XDG_CONFIG_HOME exported. Point sops at it.
if [[ -z ${SOPS_AGE_KEY_FILE:-} && -f $CONFIG_HOME/sops/age/keys.txt ]]; then
    export SOPS_AGE_KEY_FILE=$CONFIG_HOME/sops/age/keys.txt
fi

if [[ ! -d $SECRETS_REPO ]]; then
    print "secrets-render: $SECRETS_REPO not found — nothing to render." >&2
    print "  Bootstrap it with: ./deploy.zsh --only 65_secrets" >&2
    exit 1
fi

if ! command -v sops > /dev/null 2>&1; then
    print "secrets-render: sops not found in PATH; run 'mise install' first." >&2
    exit 1
fi

# A box that has never completed a render gets its pre-existing targets backed
# up before they are first overwritten (see _render_row). Captured up front so
# writing the marker at the end cannot change the answer mid-run.
typeset -i FIRST_RENDER=0
[[ -f $MARKER ]] || FIRST_RENDER=1

# ── Mapping table ──────────────────────────────────────────────────────────
#
# Parallel arrays, hardcoded here rather than in a manifest inside the secrets
# repo: target paths are machine concerns, and a manifest would need a portable
# parser in the bootstrap layer. Unknown files in the secrets repo are reported
# by name at the end instead (see the unmapped scan).
#
#   src   path inside $SECRETS_REPO
#   kind  shellenv | dotenv | blob | copy
#   dst   absolute target path
#   mode  chmod applied to the rendered file
#   gate  all | ceres | immich
#   post  (empty) | sshlink

typeset -a MAP_SRC MAP_KIND MAP_DST MAP_MODE MAP_GATE MAP_POST

_row() {
    MAP_SRC+=("$1"); MAP_KIND+=("$2"); MAP_DST+=("$3")
    MAP_MODE+=("$4"); MAP_GATE+=("$5"); MAP_POST+=("$6")
}

# Shell environment. Rendered out of every git worktree, into
# $XDG_STATE_HOME/secrets/zsh/, and sourced by zsh/env.d/89_secrets_loader.zsh.
# Basenames are preserved so local 90-99 overrides still win by load order.
local _shell_file
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
# gjc (gajae-code) is ceres-only. config.yml carries the Discord bot token
# (gjc has no env indirection for it); .env carries provider API keys. The
# secret-free gjc files (models.yml, AGENTS.md) live in the public repo under
# configs/ai/gjc/ and are symlinked by deploy.d/20_symlinks.zsh.
# NOTE: `gjc config set` writes ~/.gjc/agent/config.yml directly; a render
# clobbers that. Mirror persistent config edits into services/gjc/config.enc
# (`sops -e -i --input-type binary --output-type binary`) or they are transient.
_row services/gjc/env.yaml                dotenv "$HOME/.gjc/agent/.env"                   600 ceres  ''
_row services/gjc/config.enc              blob   "$HOME/.gjc/agent/config.yml"             600 ceres  ''
_row services/immich/b2-env.yaml          dotenv "$HOME/repos/deploy/immich/.b2-env"       600 immich ''
_row services/immich/restic-password.enc  blob   "$HOME/repos/deploy/immich/.restic-password" 600 immich ''

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
typeset -a LEGACY_PLAINTEXTS
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
typeset -a UNMAPPED_ALLOW
UNMAPPED_ALLOW=(README.md .sops.yaml .gitattributes .gitignore)

# ── Helpers ────────────────────────────────────────────────────────────────

_gate_open() {
    case $1 in
        all)    return 0 ;;
        ceres)  [[ $(hostname -s 2>/dev/null) == ceres ]] ;;
        immich) [[ -d $HOME/repos/deploy/immich ]] ;;
        *)      return 1 ;;
    esac
}

# Absolute target path -> flat backup filename (slashes become __).
_backup_name() {
    local p=${1#/}
    print -r -- "${p//\//__}"
}

# ── Render ─────────────────────────────────────────────────────────────────

typeset -i N_RENDERED=0 N_SKIPPED=0 N_FAILED=0 N_BACKED_UP=0
typeset -a FAILED_NAMES SSH_LINKS

typeset -i i
for (( i = 1; i <= ${#MAP_SRC}; i++ )); do
    local src=$SECRETS_REPO/${MAP_SRC[i]}
    local kind=${MAP_KIND[i]} dst=${MAP_DST[i]} mode=${MAP_MODE[i]}
    local gate=${MAP_GATE[i]} post=${MAP_POST[i]}

    if ! _gate_open $gate; then
        (( N_SKIPPED++ ))
        continue
    fi

    if [[ ! -f $src ]]; then
        print "  FAILED ${MAP_SRC[i]}: missing from $SECRETS_REPO" >&2
        FAILED_NAMES+=("${MAP_SRC[i]}")
        (( N_FAILED++ ))
        continue
    fi

    if (( _dry )); then
        print "  [dry-run] would render ${MAP_SRC[i]} -> $dst (mode $mode)"
        (( N_RENDERED++ ))
        [[ $post == sshlink ]] && SSH_LINKS+=("$dst")
        continue
    fi

    # The target's directory has to exist before mktemp, because the temp file
    # is created THERE and not in $TMPDIR: a rename is only atomic within one
    # filesystem, and $TMPDIR is routinely a different one (tmpfs). A
    # cross-device `mv` degrades to copy-then-unlink, which can leave a
    # half-written private key if the box dies mid-render.
    local dstdir=${dst:h}
    if [[ ! -d $dstdir ]]; then
        if [[ $mode == 600 ]]; then
            install -m 700 -d $dstdir
        else
            mkdir -p $dstdir
        fi
    fi

    # Every write is mktemp -> chmod -> mv, so a mid-render failure leaves the
    # existing target byte-for-byte untouched.
    local tmp
    tmp=$(mktemp "${dst}.render.XXXXXX") || {
        print "  FAILED ${MAP_SRC[i]}: mktemp in $dstdir" >&2
        FAILED_NAMES+=("${MAP_SRC[i]}"); (( N_FAILED++ )); continue
    }
    chmod 600 $tmp

    local ok=1
    case $kind in
        shellenv)
            {
                print -r -- "# MANAGED BY ~/.local/secrets (${MAP_SRC[i]}) — edit via sops, not here."
                print -r -- "# Rendered by ~/.local/dotfiles/scripts/secrets-render.zsh; changes here are lost."
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
        print "  FAILED ${MAP_SRC[i]}: decrypt/render error (age key registered?)" >&2
        FAILED_NAMES+=("${MAP_SRC[i]}")
        (( N_FAILED++ ))
        continue
    fi

    # First-render cutover backup: on a box that has never completed a render,
    # any pre-existing target whose bytes differ from what we are about to
    # write is copied aside first. First-write-wins, so a retry after a K>0 run
    # can never overwrite a genuine pre-cutover backup with rendered bytes.
    if (( FIRST_RENDER )) && [[ -f $dst ]] && ! cmp -s $tmp $dst; then
        [[ -d $LEGACY_DIR ]] || install -m 700 -d $LEGACY_DIR
        local backup="$LEGACY_DIR/$(_backup_name "$dst")"
        if [[ ! -e $backup ]]; then
            cp $dst $backup && (( N_BACKED_UP++ ))
            print "  backed up pre-existing $dst -> legacy-removed/${backup:t}"
        fi
    fi

    chmod $mode $tmp
    mv -f $tmp $dst
    (( N_RENDERED++ ))
    [[ $post == sshlink ]] && SSH_LINKS+=("$dst")
done

# ~/.ssh symlinks into the rendered dotfiles copies.
local _link
for _link in $SSH_LINKS; do
    if (( _dry )); then
        print "  [dry-run] would link $HOME/.ssh/${_link:t} -> $_link"
    else
        [[ -d $HOME/.ssh ]] || install -m 700 -d $HOME/.ssh
        ln -sfn $_link $HOME/.ssh/${_link:t}
    fi
done

# ── Legacy-plaintext quarantine ────────────────────────────────────────────

typeset -i N_QUARANTINED=0
typeset -a STILL_SHADOWING
local _legacy
if (( N_FAILED == 0 && ! _dry )); then
    for _legacy in $LEGACY_PLAINTEXTS; do
        [[ -f $_legacy ]] || continue
        [[ -d $LEGACY_DIR ]] || install -m 700 -d $LEGACY_DIR
        local q="$LEGACY_DIR/$(_backup_name "$_legacy")"
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

typeset -a UNMAPPED
local _tracked
for _tracked in ${(f)"$(git -C $SECRETS_REPO ls-files 2>/dev/null)"}; do
    [[ -z $_tracked ]] && continue
    [[ $_tracked == scripts/* ]] && continue
    (( ${UNMAPPED_ALLOW[(I)$_tracked]} )) && continue
    (( ${MAP_SRC[(I)$_tracked]} )) && continue
    UNMAPPED+=("$_tracked")
done

# ── Summary + marker ───────────────────────────────────────────────────────

print "  rendered ${N_RENDERED}, quarantined ${N_QUARANTINED}, backed-up ${N_BACKED_UP}, unmapped ${#UNMAPPED}, gated-out ${N_SKIPPED}, failed ${N_FAILED}"
(( ${#UNMAPPED} )) && print "  UNMAPPED (in secrets repo, never rendered): ${(j:, :)UNMAPPED}"
(( ${#FAILED_NAMES} )) && print "  FAILED: ${(j:, :)FAILED_NAMES}" >&2
if (( ${#STILL_SHADOWING} )); then
    print "  WARNING: stale legacy plaintexts still in zsh/env.d/ and will shadow rendered values until a full render succeeds: ${(j:, :)STILL_SHADOWING}" >&2
fi

if (( N_FAILED > 0 )); then
    exit 1
fi

if (( ! _dry )); then
    local dot_head sec_head
    dot_head=$(git -C $DOTFILES_DIR rev-parse HEAD 2>/dev/null || print unknown)
    sec_head=$(git -C $SECRETS_REPO rev-parse HEAD 2>/dev/null || print unknown)
    [[ -d ${MARKER:h} ]] || mkdir -p ${MARKER:h}
    {
        print -r -- "rendered_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        print -r -- "dotfiles_head=$dot_head"
        print -r -- "secrets_head=$sec_head"
        print -r -- "host=$(hostname -s 2>/dev/null || print unknown)"
    } > $MARKER
    chmod 644 $MARKER
fi

exit 0
