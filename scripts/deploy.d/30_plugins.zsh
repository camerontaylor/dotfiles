# Converge pinned plugin checkouts (plugins.lock) + compile zsh .zwc files.
#
# Replaces the submodule era (fleet-consolidation M3): the vendored plugin
# dirs are plain gitignored clones, and plugins.lock — one
# `<sha> <repo-relative-path> <clone-url>` row per dir — is the committed
# source of truth. SHAs were lifted verbatim from the gitlinks they
# replaced, so a box deployed under submodules converges as a no-op (dir
# present, HEAD == pin) and a fresh clone converges by network fetch.
# Pinned means pinned: --upgrade never floats a SHA; bump the lockfile row
# after testing on a dev box.
#
# Dual-shell (docs/bash-compatibility.md): parses and runs under zsh 5.x
# and bash 3.2. Row parsing uses `read -r sha path url` (IFS splitting,
# identical in both shells) — never an unquoted $line, which zsh passes as
# a single word.

printf '%s\n' "Converging pinned plugins..."
_pl_lock=$SCRIPT_DIR/plugins.lock
_pl_at_pin=0
_pl_moved=0
while read -r _pl_sha _pl_path _pl_url; do
    case $_pl_sha in ''|'#'*) continue ;; esac
    _pl_dir=$SCRIPT_DIR/$_pl_path
    if [[ -d $_pl_dir ]] && _pl_head=$(git -C $_pl_dir rev-parse HEAD 2>/dev/null) && [[ $_pl_head == "$_pl_sha" ]]; then
        _pl_at_pin=$((_pl_at_pin + 1))
        continue
    fi
    if (( DEPLOY_DRY_RUN )); then
        printf '%s\n' "  [dry-run] would converge $_pl_path -> $_pl_sha"
        continue
    fi
    if [[ -e $_pl_dir ]]; then
        if git -C $_pl_dir rev-parse --git-dir > /dev/null 2>&1; then
            # Working repo, off-pin: refresh its refs so the checkout below
            # can see the pinned rev (old shallow checkouts fetch new tips).
            printf '%s\n' "  ...moving $_pl_path to pinned rev"
            git -C $_pl_dir fetch --quiet origin || true
        else
            # Legacy gitfile pointing at a pruned .git/modules (or a
            # half-written clone) — re-clone, mirroring the old fragment's
            # broken-checkout repair.
            printf '%s\n' "  ...repairing broken checkout: $_pl_path"
            rm -rf $_pl_dir
        fi
    else
        printf '%s\n' "  ...fetching $_pl_path"
    fi
    if ! git -C $_pl_dir rev-parse --git-dir > /dev/null 2>&1; then
        # --filter=blob:none keeps the fetch light where the server supports
        # partial clone (GitHub does); full clone is the fallback.
        git clone --quiet --filter=blob:none --no-checkout $_pl_url $_pl_dir 2> /dev/null \
            || git clone --quiet --no-checkout $_pl_url $_pl_dir
    fi
    # A pin that is not reachable from any branch tip (history rewrite,
    # deleted branch) is fetched by SHA — allowed for reachable commits on
    # GitHub — before the deploy gives up loud.
    git -C $_pl_dir checkout --quiet --detach $_pl_sha 2> /dev/null \
        || { git -C $_pl_dir fetch --quiet origin $_pl_sha --depth 1 \
             && git -C $_pl_dir checkout --quiet --detach $_pl_sha; }
    _pl_moved=$((_pl_moved + 1))
done < "$_pl_lock"
printf '%s\n' "  ...done ($_pl_at_pin at pin, $_pl_moved converged)"
unset _pl_lock _pl_at_pin _pl_moved _pl_sha _pl_path _pl_url _pl_dir _pl_head

printf '%s\n' "Compiling zsh plugins..."
# zrecompile is an autoloadable zsh function (bash has neither autoload nor
# zsh bytecode), and `**` recursive globbing does not exist on bash 3.2 — so
# walk with find and compile in a zsh child under either driver. Output .zwc
# files are identical to compiling in-process. BSD xargs skips the command on
# empty input, so an empty plugins tree is a clean no-op.
if have zsh; then
    find "$SCRIPT_DIR/zsh/plugins" -type f \
        \( -name '*.zsh' -o -name '*.zsh-theme' \) -print0 \
        | xargs -0 zsh -c 'autoload -Uz zrecompile; for f; do zrecompile -pq "$f"; done' zsh
fi
printf '%s\n' "  ...done"
