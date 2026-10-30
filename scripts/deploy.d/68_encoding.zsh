# Encoding sibling ensure: clone-if-absent, --ff-only pull, invoke the sibling's
# ./deploy (foundation C2 chain: dotfiles -> 65_secrets -> encoding).
#
# Landed early under domain plan 1 by the owner's D3 ruling (2026-09-06,
# ESCALATE option (a): "Move in to dotfiles.") rather than waiting for
# sequencing rows 2/4 — see plans/ralplan-encoding-repo.md §O3/A7.
#
# Modeled on 65_secrets.zsh. WARN-NOT-FAIL: nothing here may break a green
# dotfiles deploy — the fleet auto-deploys unattended on every `git pull`, so
# a box without network, without a GitHub key, or with a diverged checkout
# gets one notice/warning line and the deploy stays green (frozen C2 failure
# semantics). Sibling absent + cannot clone => one notice, zero mutations,
# exit 0.
#
# The encoding repo's own converge timer also pulls --ff-only every run; that
# path survives as defense-in-depth. Both writers are --ff-only + idempotent,
# so they can never fight (domain plan 1 §O3 coexistence decision).

# ENCODING_DIR overrides the checkout location (sandboxed runs, worktrees).
# Presence is tested with `-e .git`: a worktree keeps `.git` as a FILE
# pointing at the common dir, so `-d` would misread a healthy worktree as
# absent and try to clone over it (or pull the wrong target).
encoding_repo=${ENCODING_DIR:-$HOME/.local/encoding}
encoding_slug=camerontaylor/encoding
encoding_remote=git@github.com:camerontaylor/encoding.git

if ! have git; then
    printf '%s\n' "  note: git not available; skipping encoding sibling ensure."
    return 0
fi

# ── clone or pull the encoding repo ───────────────────────────────────────────

if [[ ! -e $encoding_repo/.git ]]; then
    if (( DEPLOY_DRY_RUN )); then
        # Never clone under dry-run: a clone is a mutation. With no checkout
        # there is no ./deploy to hand --dry-run to either, so this one line
        # is the whole story for this run.
        printf '%s\n' "  [dry-run] would clone $encoding_slug -> $encoding_repo (then run its ./deploy)"
        return 0
    fi
    printf '%s\n' "Encoding repo not present; cloning $encoding_slug..."
    if git clone -q "$encoding_remote" "$encoding_repo" > /dev/null 2>&1; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "  note: cannot clone $encoding_slug (no network or no GitHub key); skipping encoding deploy."
        return 0
    fi
else
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would: git -C $encoding_repo pull --ff-only"
    else
        printf '%s\n' "Updating encoding repo..."
        if git -C "$encoding_repo" pull --ff-only -q > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            # Never merge or reset here (65_secrets precedent): deploy from
            # the stale-but-valid checkout and make the divergence loud.
            printf '%s\n' "  WARNING: $encoding_repo diverged from origin (or is unreachable)." >&2
            printf '%s\n' "           Resolve manually in $encoding_repo; deploying from the existing checkout." >&2
        fi
    fi
fi

# ── run the sibling's deploy entry ─────────────────────────────────────────

# Frozen C2 entry interface: ./deploy [--dry-run]; exit 0 ok / 1 warn /
# 2 fail; --dry-run mutates nothing and exits 0. Under the driver's dry-run
# the sibling entry still RUNS, with --dry-run passed through — the checkout
# exists and the contract guarantees zero mutations — so a dotfiles dry-run
# previews the whole chain.

if [[ ! -x $encoding_repo/deploy ]]; then
    printf '%s\n' "  WARNING: $encoding_repo/deploy missing or not executable; encoding deploy skipped." >&2
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "Running encoding deploy (--dry-run)..."
    if "$encoding_repo/deploy" --dry-run; then
        printf '%s\n' "  ...done"
    else
        encoding_rc=$?
        printf '%s\n' "  WARNING: encoding deploy --dry-run exited $encoding_rc (warn-not-fail; deploy continues)." >&2
    fi
else
    printf '%s\n' "Running encoding deploy..."
    if "$encoding_repo/deploy"; then
        printf '%s\n' "  ...done"
    else
        encoding_rc=$?
        printf '%s\n' "  WARNING: encoding deploy exited $encoding_rc (warn-not-fail; deploy continues)." >&2
    fi
fi

return 0
