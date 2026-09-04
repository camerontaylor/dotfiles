# Build a "fastbin" of direct symlinks to mise-managed static CLI binaries,
# bypassing the mise shim for the tools that never need per-project versions.
#
# WHY. env.d/08_mise.zsh puts ~/.local/share/mise/shims first on PATH for every
# shell, while `mise activate` runs only for interactive shells (rc.d/22_mise.zsh).
# So a human at a terminal resolves real binaries, and EVERYTHING ELSE — agent
# tool calls, git hooks, launchd jobs, cron, npm scripts, Makefiles — resolves
# shims. Each shim is a symlink to the 80MB mise binary, which re-resolves the
# whole toolset on every invocation. Measured 2026-09-04:
#
#   rg --version   real binary   ~5.6ms (neptune) / ~3.3ms (saturn)
#   rg --version   via shim     ~63.1ms (neptune) / ~51.6ms (saturn)
#
# ~23ms of that is mise's own startup: a 72MB __TEXT segment code-signed with
# 20,275 page hashes that macOS validates on demand-page-in at every exec. That
# cost is I/O and kernel hashing, not compute — which is why the M1 Max is only
# 1.28x faster through a shim while being 2.54x faster on the real binary. The
# shim's RELATIVE penalty gets worse on faster hardware (8x -> 15.9x).
#
# WHY NOT just run `mise activate` non-interactively: measured worse for this
# fleet's dominant workload. Activation pays ~60ms of hook-env per shell and only
# breaks even at >=2 tool calls; an agent's Bash call is usually one command in a
# fresh shell. At N=1: shims 67.0ms, activate 96.5ms, fastbin 14.0ms.
#
# THE TRADE. Tools listed here become globally pinned to the version mise
# resolves at deploy time — `mise activate` cannot shadow them, because `mise env`
# substitutes its dirs at the SHIMS dir's position, not at the front of PATH.
# That is correct for static CLI tools (nobody pins ripgrep per project) and
# WRONG for language runtimes, so node/python/bun/uv/cargo are deliberately
# absent and keep full per-project switching through the shims.
#
# FAILURE MODE is graceful: a symlink whose target vanished (e.g. after a `mise
# upgrade` before the next deploy) is skipped by the shell's PATH search and
# execution falls through to the shim behind it. Worst case is today's
# performance, never a broken command.

if ! have mise; then
    return 0
fi

mise_fastbin=${XDG_DATA_HOME:-$HOME/.local/share}/mise/fastbin

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "mise fastbin: [dry-run] would refresh direct binary symlinks in $mise_fastbin"
    return 0
fi

printf '%s\n' "Refreshing mise fastbin symlinks..."

mkdir -p $mise_fastbin

# Drop symlinks whose target no longer exists, so an upgraded/removed tool falls
# back to the shim cleanly instead of lingering as a dangling entry. POSIX
# -exec test -e; no GNU -xtype, which BSD find lacks. `|| true` because the
# drivers run under err_exit and an empty dir is not an error worth aborting on.
find $mise_fastbin -type l ! -exec test -e {} \; -exec rm -f {} \; 2>/dev/null || true

# Literal words, NOT a space-joined variable: `for x in $var` iterates ONCE under
# zsh (no word splitting on unquoted expansion) and N times under bash — the
# silent-divergence foot-gun in CLAUDE.md. Listing them inline splits identically
# in both shells.
#
# Static CLI tools only. Anything whose version a project might legitimately pin
# belongs on the shims, not here.
mise_fastbin_linked=0
for mise_fastbin_tool in \
    rg fd bat eza delta sd yq fzf zoxide \
    gh glab sops age nvim tree-sitter ast-grep
do
    mise_fastbin_target=$(mise which $mise_fastbin_tool 2>/dev/null) || mise_fastbin_target=
    if [[ -n $mise_fastbin_target && -x $mise_fastbin_target ]]; then
        ln -sfn $mise_fastbin_target $mise_fastbin/$mise_fastbin_tool
        mise_fastbin_linked=$((mise_fastbin_linked + 1))
    fi
done

printf '%s\n' "  ...linked $mise_fastbin_linked tools in $mise_fastbin"

unset mise_fastbin mise_fastbin_tool mise_fastbin_target mise_fastbin_linked
