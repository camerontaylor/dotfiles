# Tailscale install + tailnet join — the dev fleet's mesh VPN. (ZeroTier, the
# previous mesh, was decommissioned 2026-06-07; see
# docs/tailscale-migration-runbook.md for the historical cutover.)
#
# Joins using a reusable, tagged pre-auth key from $TAILSCALE_AUTHKEY, rendered
# from the private secrets repo to
# $XDG_STATE_HOME/secrets/zsh/95_tailscale_secrets.zsh by
# scripts/secrets-render.zsh. Optional PER-BOX knobs:
#   $TAILSCALE_ADVERTISE_ROUTES  space/comma-separated CIDRs for a subnet router
#                                (e.g. "10.132.32.0/24" on the LAN-router host)
#   $TAILSCALE_EXTRA_ARGS        extra flags appended verbatim to `tailscale up`
#                                (e.g. "--advertise-tags=tag:fleet" if the key
#                                 is not already pre-tagged)
# These two are genuinely per-machine, so they do NOT belong in the
# fleet-shared secrets repo. Put them in a local, gitignored
# zsh/env.d/96_local_tailscale.zsh on the box that needs them; the loop below
# sources the rendered file first and the local override second, so the
# override wins.
# Always enables Tailscale SSH (--ssh) and --accept-routes so this host can
# reach subnet-router-advertised LAN ranges.

if [[ $DOTFILES_OS != Linux && $DOTFILES_OS != Darwin ]]; then
    return 0
fi

# Source secret env files since deploy.zsh runs in a fresh shell. Rendered
# values first, then any in-tree 9x tailscale file — that second glob matches
# both a deliberate per-box 96_local_tailscale.zsh (which therefore wins) and,
# on a box that has not completed the secrets bootstrap, the legacy
# 95_tailscale_secrets.zsh plaintext, so degraded boxes keep today's behaviour.
# Collect candidates with find (the (N) glob qualifiers were zsh-only; the
# zsh driver runs err_exit without null_glob, where a missed glob aborts the
# deploy). Rendered state dir first, in-tree env.d second — per-dir sort keeps
# the load order byte-identical to the old brace-glob concatenation, so a
# deliberate 96_local override still wins over the rendered 95 file.
secret_files=()
while IFS= read -r secret_file; do
    [[ -f $secret_file ]] || continue
    secret_files+=("$secret_file")
done < <(
    find "${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh" -maxdepth 1 -name '9[0-9]_tailscale_secrets.zsh' 2>/dev/null | sort
    find "$SCRIPT_DIR/zsh/env.d" -maxdepth 1 -name '9[0-9]_*tailscale*.zsh' 2>/dev/null | sort
)
secret_file=
for secret_file in "${secret_files[@]}"; do
    source "$secret_file"
done

# Install the client when missing; refresh under --upgrade on macOS.
if [[ $DOTFILES_OS == Darwin ]]; then
    if ! ensure_homebrew_path; then
        printf '%s\n' "Tailscale: Homebrew not available, skipping"
        return 0
    fi
    if ! brew list --cask tailscale > /dev/null 2>&1; then
        printf '%s\n' "Installing Tailscale..."
        if (( DEPLOY_DRY_RUN )); then
            printf '%s\n' "  [dry-run] would: brew install --cask tailscale"
        else
            if brew_cask_install_or_upgrade tailscale; then
                hash -r
                printf '%s\n' "  ...macOS may prompt to allow the Tailscale system extension"
                printf '%s\n' "     in System Settings -> Privacy & Security, and to open the app once."
            else
                return 0
            fi
        fi
    elif $upgrade_mode; then
        printf '%s\n' "Upgrading Tailscale..."
        if (( DEPLOY_DRY_RUN )); then
            printf '%s\n' "  [dry-run] would: brew upgrade --cask tailscale"
        else
            brew_cask_install_or_upgrade tailscale || true
        fi
    fi
else
    if ! have tailscale; then
        printf '%s\n' "Installing Tailscale..."
        # Distro-aware install. Tailscale's install.sh handles most families
        # (apt/dnf/zypper) well, but on Arch it shells out to `pacman -S` against
        # the LOCAL db, which fails when that db is stale (404 on a dropped
        # package/sig). So on Arch-family we install natively with a db refresh.
        # NOTE: stdout/stderr is intentionally NOT suppressed — a failed install
        # must show why (an earlier version hid a stale-mirror 404).
        # os-release is designed to be sourced; do it in a subshell so its vars
        # don't leak. Absent file / missing keys => empty, which falls through to
        # the install.sh default (safe).
        distro_id="" distro_like=""
        if [[ -r /etc/os-release ]]; then
            distro_id=$(. /etc/os-release 2>/dev/null && printf '%s\n' "${ID:-}")
            distro_like=$(. /etc/os-release 2>/dev/null && printf '%s\n' "${ID_LIKE:-}")
        fi

        # Match the token "arch" (Arch + all derivatives set ID or ID_LIKE to it:
        # cachyos, manjaro, endeavouros, garuda, artix, ...). Surrounding spaces
        # anchor on whole words so we don't match "monarch"/"starch".
        install_ok=0
        case " $distro_id $distro_like " in
            *" arch "*)
                # -Sy refreshes the sync db so a stale entry doesn't 404; --needed
                # makes it a no-op if already present. NOTE: -Sy without -u leaves
                # the local db synced ahead of installed packages — a partial-
                # upgrade state. Fine for adding this near-static leaf here; on an
                # existing daily-driver run `sudo pacman -Syu` soon after.
                if (( DEPLOY_DRY_RUN )); then
                    printf '%s\n' "  [dry-run] would: sudo pacman -Sy --needed --noconfirm tailscale"
                    install_ok=1
                elif sudo pacman -Sy --needed --noconfirm tailscale; then
                    install_ok=1
                fi
                ;;
            *)
                if ! have curl; then
                    printf '%s\n' "Tailscale: curl not available for install.sh, skipping install and join"
                    return 0
                fi
                if (( DEPLOY_DRY_RUN )); then
                    printf '%s\n' "  [dry-run] would: curl -fsSL https://tailscale.com/install.sh | sh"
                    install_ok=1
                elif curl -fsSL https://tailscale.com/install.sh | sh; then
                    install_ok=1
                fi
                ;;
        esac

        if (( install_ok )); then
            (( DEPLOY_DRY_RUN )) || { hash -r; printf '%s\n' "  ...done"; }
        else
            printf '%s\n' "  ...failed to install Tailscale (see output above)"
            return 0
        fi
    fi
fi

# Ensure the daemon is running. On Linux this is the tailscaled systemd unit.
# There is no Darwin daemon-start branch here: the macOS Tailscale daemon is a
# system extension managed by macOS and bundled in the cask .app — opening the
# app once (runbook Phase 2) activates it; there is no plist for us to load.
if [[ $DOTFILES_OS == Linux ]]; then
    if have systemctl && ! systemctl is-active --quiet tailscaled 2>/dev/null; then
        if (( DEPLOY_DRY_RUN )); then
            printf '%s\n' "  [dry-run] would: sudo systemctl enable --now tailscaled"
        else
            sudo systemctl enable --now tailscaled > /dev/null 2>&1 || true
        fi
    fi
fi

# Locate the tailscale CLI. On macOS the cask drops the binary inside the app
# bundle (and may symlink to the legacy Intel prefix /usr/local/bin), neither of
# which is guaranteed on deploy.zsh's PATH. Probe known locations.
ts_cli=""
if have tailscale; then
    ts_cli=$(command -v tailscale)
else
    candidate=
    for candidate in \
        /Applications/Tailscale.app/Contents/MacOS/Tailscale \
        /usr/local/bin/tailscale \
        /opt/homebrew/bin/tailscale; do
        if [[ -x $candidate ]]; then
            ts_cli=$candidate
            break
        fi
    done
fi

if [[ -z $ts_cli ]]; then
    printf '%s\n' "Tailscale: tailscale CLI not found, skipping join"
    return 0
fi

# macOS: the cask CLI lives in /usr/local/bin (legacy Intel prefix) or inside the
# app bundle — neither is on the interactive PATH on Apple Silicon, where
# env.d/03_paths.zsh deliberately omits /usr/local/bin. Surface the binary via
# ~/.local/bin (already on PATH, user-owned) so bare `tailscale` resolves in a
# shell, without exposing all of /usr/local/bin. Idempotent.
if [[ $DOTFILES_OS == Darwin ]]; then
    ts_link=$HOME/.local/bin/tailscale
    # abspath (lib/helpers.zsh) replaces zsh's ${var:A} symlink resolution;
    # a not-yet-existing link resolves empty, which differs from any real
    # path — the same "create the link" outcome as before.
    if [[ $(abspath "$ts_link" 2>/dev/null) != $(abspath "$ts_cli" 2>/dev/null) ]]; then
        if (( DEPLOY_DRY_RUN )); then
            printf '%s\n' "  [dry-run] would: ln -sfn $ts_cli ~/.local/bin/tailscale"
        else
            mkdir -p $HOME/.local/bin
            ln -sfn $ts_cli $ts_link && printf '%s\n' "Tailscale: linked CLI into ~/.local/bin (PATH-visible)"
        fi
    fi
fi

# Idempotency: if the backend is already up AND authenticated, leave it alone so
# re-running deploy.zsh stays a no-op (and avoids a sudo prompt on Linux).
# We do NOT rely on `tailscale status`'s exit code: depending on the version it
# can exit 0 while in NeedsLogin (e.g. after a key rotation), which would wrongly
# skip the re-auth. The status table only prints a self/peer line beginning with
# a 100.x CGNAT address when the node is actually Running, so grep for that.
# The producer is `{ … || true }`-guarded: `tailscale status` streams slowly, so
# `grep -q`'s early exit SIGPIPEs it (141) — under the bash driver's `pipefail`
# that would invert this gate and re-run `tailscale up` on every deploy.
if { "$ts_cli" status 2>/dev/null || true; } | grep -q '^100\.'; then
    return 0
fi

if [[ -z ${TAILSCALE_AUTHKEY:-} ]]; then
    printf '%s\n' "Tailscale: \$TAILSCALE_AUTHKEY not set; skipping join."
    printf '%s\n' "  Expected at \$XDG_STATE_HOME/secrets/zsh/95_tailscale_secrets.zsh —"
    printf '%s\n' "  run ./deploy.zsh --only 65_secrets to render it (see ~/.local/secrets/README.md)."
    return 0
fi

# Assemble `tailscale up` arguments. The auth key is kept in its own array
# element so it is never word-split and never printed.
up_args=()
up_args=(--accept-routes "--authkey=$TAILSCALE_AUTHKEY")

# Tailscale SSH server runs on Linux tailscaled but NOT on the sandboxed macOS
# GUI (cask) build — `--ssh` there fails with a 500 "does not run in sandboxed
# Tailscale GUI builds". Enable it on Linux only; reach macOS fleet nodes via
# regular SSH over the tailnet. (A Mac running the open-source tailscaled can
# opt in with TAILSCALE_EXTRA_ARGS="--ssh".)
ssh_label="accept-routes"
if [[ $DOTFILES_OS == Linux ]]; then
    up_args=(--ssh "${up_args[@]}")
    ssh_label="ssh, accept-routes"
fi

routes_csv=""
if [[ -n ${TAILSCALE_ADVERTISE_ROUTES:-} ]]; then
    # tailscale wants comma-separated CIDRs; accept whitespace-separated too.
    # Split on whitespace then rejoin with commas so repeated/leading/trailing
    # spaces don't produce empty (",,") fields. An unquoted $(…) command
    # substitution is the one word-splitter both shells perform — it replaces
    # zsh's ${(z)}+${(j:,)} pair.
    for _route in $(printf '%s\n' "$TAILSCALE_ADVERTISE_ROUTES"); do
        routes_csv="${routes_csv:+$routes_csv,}$_route"
    done
    up_args+=("--advertise-routes=$routes_csv")
fi

if [[ -n ${TAILSCALE_EXTRA_ARGS:-} ]]; then
    # Whitespace word-split (replaces zsh's ${(z)}); values must be shell-clean
    # (no unbalanced quotes or shell operators). Use --flag=value form for
    # anything containing spaces.
    for _extra in $(printf '%s\n' "$TAILSCALE_EXTRA_ARGS"); do
        up_args+=("$_extra")
    done
fi

printf '%s\n' "Tailscale: bringing up tailnet (${ssh_label})..."
if (( DEPLOY_DRY_RUN )); then
    # Show the real non-secret args but NEVER echo the auth key.
    dry_ssh=""
    [[ $DOTFILES_OS == Linux ]] && dry_ssh=" --ssh"
    dry_extra=""
    [[ -n $routes_csv ]] && dry_extra+=" --advertise-routes=$routes_csv"
    [[ -n ${TAILSCALE_EXTRA_ARGS:-} ]] && dry_extra+=" $TAILSCALE_EXTRA_ARGS"
    printf '%s\n' "  [dry-run] would: $ts_cli up${dry_ssh} --accept-routes --authkey=***${dry_extra}"
else
    ts_cmd=()
    if [[ $DOTFILES_OS == Linux ]]; then
        ts_cmd=(sudo "$ts_cli" up "${up_args[@]}")
    else
        ts_cmd=("$ts_cli" up "${up_args[@]}")
    fi
    if "${ts_cmd[@]}" > /dev/null 2>&1; then
        printf '%s\n' "  ...connected"
    else
        printf '%s\n' "  ...tailscale up failed (key expired/invalid, or daemon not ready)"
        printf '%s\n' "     check the admin console and docs/tailscale-migration-runbook.md"
    fi
fi
