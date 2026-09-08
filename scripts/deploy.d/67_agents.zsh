# Agents sibling ensure: clone-if-absent, --ff-only pull, invoke the
# sibling's ./deploy (foundation C2 chain: dotfiles -> 65_secrets ->
# 66_infra -> agents).
#
# Modeled on 66_infra.zsh (clone/pull + run ./deploy, warn-not-fail,
# absent-sibling tolerated, dry-run pass-through). WARN-NOT-FAIL: nothing
# here may break a green dotfiles deploy — the fleet auto-deploys unattended
# on every `git pull`, so a box without network, without a GitHub key, or
# with a diverged checkout gets one notice/warning line and the deploy stays
# green (frozen C2 failure semantics). Sibling absent + cannot clone => one
# notice, zero mutations, exit 0.
#
# DOTFILES_DIR is passed EXPLICITLY to the sibling's deploy: its reserved
# 96-99 slot wiring is explicit-only by contract and never guesses a
# dotfiles checkout (tests can never touch a real one by default). DOTFILES
# carries the same value for tooling that still reads the older single-name
# variable (e.g. the snapshot source installer), so a deploy driven from a
# worktree uses THIS checkout, not the default clone. Dotfiles
# itself never sources the agents repo — its loaders glob the gitignored
# slot files the sibling's deploy links in (docs/fleet-consolidation.md
# "The agents-repo line").
#
# Ordering note (owner, 2026-09-08): fragment 67 runs BEFORE 70 (runtimes)
# and 75 (brew) — do not assume any agent CLI is on PATH here or in the
# sibling; the sibling's provider merge re-runs on a later deploy after
# installers/first launch create ~/.paseo/config.json on a fresh box.
# Until the agents repo is pushed, a locally-cloned checkout without a
# remote diverges loudly here on every deploy (66 semantics) — expected
# during the carve-out.

agents_repo=$HOME/.local/agents
agents_slug=camerontaylor/agents
agents_remote=git@github.com:camerontaylor/agents.git

if ! have git; then
    printf '%s\n' "  note: git not available; skipping agents sibling ensure."
    return 0
fi

# ── clone or pull the agents repo ───────────────────────────────────────────

if [[ ! -d $agents_repo/.git ]]; then
    if (( DEPLOY_DRY_RUN )); then
        # Never clone under dry-run: a clone is a mutation. With no checkout
        # there is no ./deploy to hand --dry-run to either, so this one line
        # is the whole story for this run.
        printf '%s\n' "  [dry-run] would clone $agents_slug -> $agents_repo (then run its ./deploy)"
        return 0
    fi
    printf '%s\n' "Agents repo not present; cloning $agents_slug..."
    if git clone -q "$agents_remote" "$agents_repo" > /dev/null 2>&1; then
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "  note: cannot clone $agents_slug (no network, no GitHub key, or repo not pushed yet); skipping agents deploy."
        return 0
    fi
else
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would: git -C $agents_repo pull --ff-only"
    else
        printf '%s\n' "Updating agents repo..."
        if git -C "$agents_repo" pull --ff-only -q > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            # Never merge or reset here (65_secrets/66_infra precedent):
            # deploy from the stale-but-valid checkout and make the
            # divergence loud.
            printf '%s\n' "  WARNING: $agents_repo diverged from origin (or is unreachable)." >&2
            printf '%s\n' "           Resolve manually in $agents_repo; deploying from the existing checkout." >&2
        fi
    fi
fi

# ── run the sibling's deploy entry ─────────────────────────────────────────

# Frozen C2 entry interface: ./deploy [--dry-run]; exit 0 ok / 1 warn /
# 2 fail; --dry-run mutates nothing and exits 0. Under the driver's dry-run
# the sibling entry still RUNS, with --dry-run passed through — the contract
# guarantees zero mutations — so a dotfiles dry-run previews the whole chain.

if [[ ! -x $agents_repo/deploy ]]; then
    printf '%s\n' "  WARNING: $agents_repo/deploy missing or not executable; agents deploy skipped." >&2
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "Running agents deploy (--dry-run)..."
    if DOTFILES=$SCRIPT_DIR DOTFILES_DIR=$SCRIPT_DIR "$agents_repo/deploy" --dry-run; then
        printf '%s\n' "  ...done"
    else
        agents_rc=$?
        printf '%s\n' "  WARNING: agents deploy --dry-run exited $agents_rc (warn-not-fail; deploy continues)." >&2
    fi
else
    printf '%s\n' "Running agents deploy..."
    if DOTFILES=$SCRIPT_DIR DOTFILES_DIR=$SCRIPT_DIR "$agents_repo/deploy"; then
        printf '%s\n' "  ...done"
    else
        agents_rc=$?
        printf '%s\n' "  WARNING: agents deploy exited $agents_rc (warn-not-fail; deploy continues)." >&2
    fi
fi

return 0
