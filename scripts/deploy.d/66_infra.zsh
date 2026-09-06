# Infra sibling ensure: clone-if-absent, --ff-only pull, invoke the sibling's
# ./deploy (foundation C2 chain: dotfiles -> 65_secrets -> infra).
#
# Landed early under domain plan 1 by the owner's D3 ruling (2026-09-06,
# ESCALATE option (a): "Move in to dotfiles.") rather than waiting for
# sequencing rows 2/4 — see plans/ralplan-infra-repo.md §O3/A7.
#
# Modeled on 65_secrets.zsh. WARN-NOT-FAIL: nothing here may break a green
# dotfiles deploy — the fleet auto-deploys unattended on every `git pull`, so
# a box without network, without a GitHub key, or with a diverged checkout
# gets one notice/warning line and the deploy stays green (frozen C2 failure
# semantics). Sibling absent + cannot clone => one notice, zero mutations,
# exit 0.
#
# The infra repo's own converge timer also pulls --ff-only every run; that
# path survives as defense-in-depth. Both writers are --ff-only + idempotent,
# so they can never fight (domain plan 1 §O3 coexistence decision).

infra_repo=$HOME/.local/infra
infra_slug=camerontaylor/infra
infra_remote=git@github.com:camerontaylor/infra.git

if ! have git; then
    printf '%s\n' "  note: git not available; skipping infra sibling ensure."
    return 0
fi

# ── clone or pull the infra repo ───────────────────────────────────────────

if [[ ! -d $infra_repo/.git ]]; then
    if (( DEPLOY_DRY_RUN )); then
        # Never clone under dry-run: a clone is a mutation. With no checkout
        # there is no ./deploy to hand --dry-run to either, so this one line
        # is the whole story for this run.
        printf '%s\n' "  [dry-run] would clone $infra_slug -> $infra_repo (then run its ./deploy)"
        return 0
    fi
    printf '%s\n' "Infra repo not present; cloning $infra_slug..."
    if git clone -q "$infra_remote" "$infra_repo" > /dev/null 2>&1; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "  note: cannot clone $infra_slug (no network or no GitHub key); skipping infra deploy."
        return 0
    fi
else
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would: git -C $infra_repo pull --ff-only"
    else
        printf '%s\n' "Updating infra repo..."
        if git -C "$infra_repo" pull --ff-only -q > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            # Never merge or reset here (65_secrets precedent): deploy from
            # the stale-but-valid checkout and make the divergence loud.
            printf '%s\n' "  WARNING: $infra_repo diverged from origin (or is unreachable)." >&2
            printf '%s\n' "           Resolve manually in $infra_repo; deploying from the existing checkout." >&2
        fi
    fi
fi

# ── run the sibling's deploy entry ─────────────────────────────────────────

# Frozen C2 entry interface: ./deploy [--dry-run]; exit 0 ok / 1 warn /
# 2 fail; --dry-run mutates nothing and exits 0. Under the driver's dry-run
# the sibling entry still RUNS, with --dry-run passed through — the checkout
# exists and the contract guarantees zero mutations — so a dotfiles dry-run
# previews the whole chain.

if [[ ! -x $infra_repo/deploy ]]; then
    printf '%s\n' "  WARNING: $infra_repo/deploy missing or not executable; infra deploy skipped." >&2
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "Running infra deploy (--dry-run)..."
    if "$infra_repo/deploy" --dry-run; then
        printf '%s\n' "  ...done"
    else
        infra_rc=$?
        printf '%s\n' "  WARNING: infra deploy --dry-run exited $infra_rc (warn-not-fail; deploy continues)." >&2
    fi
else
    printf '%s\n' "Running infra deploy..."
    if "$infra_repo/deploy"; then
        printf '%s\n' "  ...done"
    else
        infra_rc=$?
        printf '%s\n' "  WARNING: infra deploy exited $infra_rc (warn-not-fail; deploy continues)." >&2
    fi
fi

return 0
