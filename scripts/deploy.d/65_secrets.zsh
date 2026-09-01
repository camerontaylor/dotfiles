# Secrets bootstrap: age key, private secrets-repo clone/pull, render.
#
# Replaces 65_sops.zsh's decrypt role. Ciphertext now lives in the PRIVATE repo
# camerontaylor/dotfiles-secrets, cloned to ~/.local/secrets; every plaintext
# target on this box is rendered from it by scripts/secrets-render.zsh.
#
# There are deliberately NO mtime/clobber guards. The encrypted side is
# canonical and the plaintext is derived, so re-rendering is always the correct
# answer — that asymmetry is the whole point of the migration. Edits go through
# `sops edit` / `sops set` in ~/.local/secrets, never into a rendered file.
#
# DEGRADED MODE: a box missing either credential (age key, GitHub read access
# to the private repo) gets a precise instruction block and this fragment
# MUTATES NOTHING — no clone, no render, no quarantine, no backup. deploy.zsh
# stays green, because the fleet auto-deploys unattended on every `git pull`.

local secrets_repo=$HOME/.local/secrets
local secrets_slug=camerontaylor/dotfiles-secrets
local secrets_remote=git@github.com:camerontaylor/dotfiles-secrets.git
local age_key_dir=$XDG_CONFIG_HOME/sops/age
local age_public_key

secrets_bootstrap_help() {
    print ""
    print "  Secrets are not available on this machine yet. Two credentials are needed:"
    print ""
    print "    1. An age private key at $age_key_dir/keys.txt"
    print "       - restore it from your password manager, OR"
    print "       - let this deploy generate one, then register it from an"
    print "         already-registered box:"
    print "           ~/.local/secrets/scripts/sops-add-recipient.zsh <this box's public key>"
    print "         (print it here with: age-keygen -y $age_key_dir/keys.txt)"
    print ""
    print "    2. Read access to the private repo $secrets_slug — either"
    print "         gh auth login          # device flow; the ssh key lives INSIDE"
    print "                                # the secrets, so this breaks the"
    print "                                # chicken-and-egg on a fresh box"
    print "       or an ssh key on this box that GitHub already accepts."
    print ""
    print "  Then re-run:  ./deploy.zsh --only 65_secrets"
    print ""
}

# ── age key bootstrap ──────────────────────────────────────────────────────

if [[ ! -f $age_key_dir/keys.txt ]]; then
    if have age-keygen; then
        print "Generating age key for secrets..."
        zf_mkdir -p $age_key_dir
        age-keygen -o $age_key_dir/keys.txt 2>/dev/null
        chmod 600 $age_key_dir/keys.txt
        print "  ...done"
        print "  IMPORTANT: Back up $age_key_dir/keys.txt to your password manager!"
        print "  This key is NOT yet registered — no secret can be decrypted until it is."
    else
        print ""
        print "WARNING: age key not found and age-keygen not available."
        print "  Install age (mise install) and re-run deploy.zsh."
        print ""
    fi
fi

if [[ ! -f $age_key_dir/keys.txt ]]; then
    secrets_bootstrap_help
    unfunction secrets_bootstrap_help 2>/dev/null || true
    return 0
fi

# Warn when this box's key is not among the secrets repo's recipients. Only
# checkable once the clone exists; before that, the clone itself is the gate.
if have age-keygen && [[ -f $secrets_repo/.sops.yaml ]]; then
    age_public_key=$(age-keygen -y $age_key_dir/keys.txt 2>/dev/null)
    if [[ -n $age_public_key ]] && ! grep -Fq "$age_public_key" $secrets_repo/.sops.yaml; then
        print ""
        print "WARNING: this machine's age key is not registered for sops decryption."
        print "  Nothing in ~/.local/secrets can be decrypted here."
        print ""
        print "  This machine's public key:"
        print "    $age_public_key"
        print ""
        print "  To register, on an already-registered machine run:"
        print "    ~/.local/secrets/scripts/sops-add-recipient.zsh $age_public_key"
        print "  then commit and push there, and re-run deploy here."
        print ""
    fi
fi

# ── clone or pull the secrets repo ─────────────────────────────────────────

if [[ ! -d $secrets_repo/.git ]]; then
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] would clone $secrets_slug -> $secrets_repo"
    else
        # Probe BOTH capabilities, no short-circuit, so the deploy log records
        # what this box can actually do. `gh auth status` is not enough: it
        # reports login state, which diverges from repo-read capability when a
        # token's scopes are wrong or a macOS keychain is locked.
        local -i gh_ok=0 ssh_ok=0
        if have gh; then
            if gh api repos/$secrets_slug --silent > /dev/null 2>&1; then
                gh_ok=1
            fi
        fi
        if git ls-remote $secrets_remote HEAD > /dev/null 2>&1; then
            ssh_ok=1
        fi
        print "Secrets repo not present. GitHub read capability: gh=$gh_ok ssh=$ssh_ok"

        if (( gh_ok == 0 && ssh_ok == 0 )); then
            secrets_bootstrap_help
            unfunction secrets_bootstrap_help 2>/dev/null || true
            return 0
        fi

        # Clone with a re-test at clone time and a gh -> ssh fallback. A `gh
        # api` pass does not guarantee `gh repo clone` works (git credential
        # helper vs API token are separate paths), so never trust the probe.
        local -i cloned=0
        if (( gh_ok )); then
            print "Cloning $secrets_slug via gh..."
            if gh repo clone $secrets_slug $secrets_repo -- -q > /dev/null 2>&1; then
                cloned=1
                print "  ...done"
            else
                print "  gh clone failed; falling back to ssh"
            fi
        fi
        if (( cloned == 0 )); then
            print "Cloning $secrets_slug via ssh..."
            if git clone -q $secrets_remote $secrets_repo > /dev/null 2>&1; then
                cloned=1
                print "  ...done"
            else
                print "  ssh clone failed"
            fi
        fi
        if (( cloned == 0 )); then
            secrets_bootstrap_help
            unfunction secrets_bootstrap_help 2>/dev/null || true
            return 0
        fi
    fi
else
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] would: git -C $secrets_repo pull --ff-only"
    else
        print "Updating secrets repo..."
        if git -C $secrets_repo pull --ff-only -q > /dev/null 2>&1; then
            print "  ...done"
        else
            # Never merge or reset here — a wrong resolution in this repo means
            # wrong credentials fleet-wide. Render from the stale-but-valid
            # checkout and make the divergence loud.
            print "  WARNING: $secrets_repo diverged from origin (or is unreachable)." >&2
            print "           Resolve manually in $secrets_repo; rendering from the" >&2
            print "           existing checkout, which may be stale." >&2
        fi
    fi
fi

# ── git ergonomics + the secrets-repo's own post-merge hook ────────────────

if [[ -d $secrets_repo/.git ]]; then
    if (( DEPLOY_DRY_RUN )); then
        print "  [dry-run] git -C $secrets_repo config diff.sops.textconv 'sops -d'"
    else
        # Per-clone config is not tracked, so it has to be re-asserted here
        # (same pattern as the codex-clean filter in 60_git_hooks.zsh).
        git -C $secrets_repo config diff.sops.textconv "sops -d" \
            || print "  WARNING: could not set diff.sops.textconv in $secrets_repo" >&2

        # Re-render after a manual `git pull` in the secrets repo, closing the
        # "pulled by hand, forgot to render" gap. The renderer is
        # standalone-safe precisely so this hook path works.
        if [[ -f $secrets_repo/scripts/post-merge ]]; then
            zf_mkdir -p $secrets_repo/.git/hooks
            zf_ln -sfn ../../scripts/post-merge $secrets_repo/.git/hooks/post-merge
        else
            print "  note: $secrets_repo/scripts/post-merge missing; no re-render hook installed"
        fi
    fi
fi

# ── render ─────────────────────────────────────────────────────────────────

if [[ -r $SCRIPT_DIR/scripts/secrets-render.zsh ]]; then
    print "Rendering secrets..."
    # DEPLOY_DRY_RUN is exported by deploy.zsh, so --dry-run needs no plumbing.
    # A render failure warns but does NOT fail the deploy: the fleet pulls
    # unattended, and a transient sops/network problem must not leave every box
    # aborting mid-deploy. Staleness is caught by the render marker instead.
    if ! zsh $SCRIPT_DIR/scripts/secrets-render.zsh; then
        print "  WARNING: secrets render reported failures (named above)." >&2
        print "           Rendered targets already on disk are untouched." >&2
    fi
else
    print "  WARNING: scripts/secrets-render.zsh missing; nothing rendered." >&2
fi

unfunction secrets_bootstrap_help 2>/dev/null || true

# Reload systemd to pick up any user units whose EnvironmentFile just changed.
if have systemctl; then
    systemctl --user daemon-reload 2>/dev/null
fi
