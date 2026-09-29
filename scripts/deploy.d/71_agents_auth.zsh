# Post-tools Codex auth finalizer (first-bootstrap seam).
#
# WHY: the renderer's Codex env row ($XDG_STATE_HOME/codex/env) is gated on
# the agents checkout, but 65 renders before 67 creates it, and the agents
# config deploy runs before 70 installs Codex — a fresh full deploy ends
# with no env and no auth cache. This is the minimal post-70 seam: re-render
# if the env row is still missing, then dispatch the agents-owned
# setup-codex-auth.sh. 65 -> 66 -> 67 order untouched.
#
# Contract: --dry-run = zero writes/secret reads; absent agents/helper/codex
# = note + skip; renderer failure = warn-only and NO auth call; warm (env +
# auth, including a dangling owner auth symlink) = skip; helper failure =
# warn-only. CODEX_HOME / AGENTS_DIR / XDG_* overrides honored; owner
# symlinks resolved via abspath() (helpers).

agents_auth_dir=${AGENTS_DIR:-$HOME/.local/agents}
agents_auth_renderer=$SCRIPT_DIR/scripts/secrets-render.zsh
agents_auth_env=${XDG_STATE_HOME:-$HOME/.local/state}/codex/env
agents_auth_home=${CODEX_HOME:-$HOME/.codex}

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would: re-render secrets if $agents_auth_env is missing, then dispatch the agents repo's setup-codex-auth.sh (skip when both env and auth cache exist)"
    return 0
fi

# Absent pieces are notes, not failures: the next deploy picks them up.
if [[ ! -f $agents_auth_renderer ]]; then
    printf '%s\n' "  note: secrets renderer missing; no Codex env re-render possible"
    return 0
fi
if [[ ! -d $agents_auth_dir ]]; then
    printf '%s\n' "  note: agents checkout absent; skipping Codex auth finalizer"
    return 0
fi
# Owner symlinks are legitimate checkout locations; resolve once.
agents_auth_dir=$(abspath "$agents_auth_dir" 2>/dev/null) || agents_auth_dir=
if [[ -z $agents_auth_dir || ! -d $agents_auth_dir ]]; then
    printf '%s\n' "  note: agents checkout unresolvable; skipping Codex auth finalizer"
    return 0
fi
if ! have codex; then
    printf '%s\n' "  note: codex CLI not installed (70 ran before this); skipping auth finalizer"
    return 0
fi
if [[ ! -x $agents_auth_dir/scripts/setup-codex-auth.sh ]]; then
    printf '%s\n' "  note: agents setup-codex-auth.sh missing or not executable; skipping auth dispatch"
    return 0
fi

# Warm steady state: env rendered AND an auth cache exists (-e OR -L: even a
# dangling owner symlink means the helper would only preserve-and-exit, so
# dispatching would be duplicate work; preservation itself is helper-owned).
if [[ -f $agents_auth_env ]] && { [[ -e $agents_auth_home/auth.json ]] || [[ -L $agents_auth_home/auth.json ]]; }; then
    printf '%s\n' "Codex env + auth cache present; skipping auth finalizer"
    return 0
fi

if [[ ! -f $agents_auth_env ]]; then
    printf '%s\n' "Re-rendering secrets (agents checkout now present; Codex env row was gated on it)..."
    if ! DOTFILES_DIR="$SCRIPT_DIR" AGENTS_DIR="$agents_auth_dir" zsh "$agents_auth_renderer"; then
        # Warn-only, and NEVER dispatch auth off a failed render.
        printf '%s\n' "  WARNING: secrets re-render failed; Codex auth not finalized (rerun deploy)" >&2
        return 0
    fi
    printf '%s\n' "  ...done"
fi
if [[ ! -f $agents_auth_env ]]; then
    printf '%s\n' "  WARNING: $agents_auth_env still missing after re-render; skipping auth dispatch" >&2
    return 0
fi

printf '%s\n' "Finalizing Codex auth (agents setup-codex-auth.sh)..."
if DOTFILES_DIR="$SCRIPT_DIR" AGENTS_DIR="$agents_auth_dir" "$agents_auth_dir/scripts/setup-codex-auth.sh"; then
    printf '%s\n' "  ...done"
else
    printf '%s\n' "  WARNING: setup-codex-auth.sh failed (see its diagnostic); deploy continues" >&2
fi

unset agents_auth_dir agents_auth_renderer agents_auth_env agents_auth_home
return 0
