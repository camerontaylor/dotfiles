# curl/cargo installs for CLIs without a mise backend (rustup/cargo,
# linear-cli, CodeRabbit) and npm globals through the mise-managed node (pinned
# in configs/mise.toml, installed by 50_mise.zsh). Claude Code / moor /
# wtp-Linux moved to mise backends (configs/mise.toml) — the drift-correctors
# below retire what this fragment used to install by hand.
#
# Dry-run contract (AGENTS.md): same story as 50_mise.zsh — the npm
# block below had a per-step gate, but the curl/rustup/cargo blocks did not,
# and on a provisioned box every install is a quiet `have`-skipped no-op, so
# nothing looked wrong until a fresh HOME (CI) got a real rust toolchain
# mid-"dry-run". The fragment is 100% mutation, so preview at fragment scope.
if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "Runtime installs skipped in dry-run (would: npm globals, coderabbit, rustup, linear-cli, claude + retired-tool drift cleanup)"
    return 0
fi

# Claude Code is mise-managed (aqua:anthropics/claude-code). Drift-correct
# hosts that still carry the native installer's layout (claude.ai/install.sh
# era): a ~/.local/bin/claude symlink into ~/.local/share/claude plus its
# versions dir. mise shims precede ~/.local/bin on PATH, so the drift never
# wins interactively — this is hygiene plus reclaiming the duplicate bytes.
# Only remove the symlink when it really points into the native install,
# never a real binary someone put there; ~/.claude (config) is a different
# tree and untouched.
if [[ -L $HOME/.local/bin/claude ]]; then
    _claude_target=$(readlink $HOME/.local/bin/claude)
    case $_claude_target in
        "$HOME"/.local/share/claude/*)
            printf '%s\n' "Removing native-install Claude Code (mise owns claude now)..."
            rm -f $HOME/.local/bin/claude
            rm -rf $HOME/.local/share/claude
            hash -r
            printf '%s\n' "  ...done"
            ;;
    esac
fi
unset _claude_target

npm_packages_file="$SCRIPT_DIR/.default-npm-packages"

# npm filters an optional platform dependency (t3's @t3code/t3-linux-x64, …)
# by os/arch AND libc, and on pluto that binary package was observed missing
# while the CLI died with "no build available for this platform" (audit
# 2026-09-29, F1). The libc override is official npm config (`--libc`,
# docs.npmjs.com/cli/v11/using-npm/config#libc) — NOT --target_libc, which is
# the old node-pre-gyp spelling. NixOS is glibc-based, so key off /etc/NIXOS
# (ldd's banner wording varies: "GLIBC"/"GNU libc"); other Linux keeps npm's
# own detection unless ldd reports a glibc runtime.
npm_libc_flag=
if [[ -e /etc/NIXOS ]] || { [[ $DOTFILES_OS == Linux ]] && ldd --version 2>/dev/null | grep -qi glibc; }; then
    npm_libc_flag=--libc=glibc
fi

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would install npm globals through mise node's npm"
elif have mise; then
    # Drop mise installs that other installers own now. NOTE: node/npm, the
    # npm: backend tools that systemd units resolve through mise (npm:t3 for
    # t3-serve.service), and npm:portless (retained in mise.toml as generic
    # dev tooling — its webfront-runner consumer was retired 2026-09-08) must
    # NEVER be listed here — a previous version of this list uninstalled node
    # itself on every deploy, which severed every unit that execs through mise
    # and crash-looped them for a week (2026-07).
    obsolete_mise_tools=(
        # Old npm: backend installs replaced by the npm globals below.
        npm:happy
        npm:@biomejs/biome
        npm:@openai/codex
        npm:oh-my-codex
        npm:@google/gemini-cli
        npm:oh-my-claude-sisyphus
        npm:pnpm
        npm:vite-plus
        npm:tsx
        npm:agent-browser
        npm:@ast-grep/cli
        npm:@ast-grep/napi
        npm:oxlint
        npm:not-claude-code-emulator
        npm:@oh-my-pi/pi-coding-agent
        npm:@aoagents/ao
        npm:@code-yeongyu/comment-checker
        github:usewhale/DeepSeek-COde-Whale
        github:usewhale/DeepSeek-Code-Whale
    )

    printf '%s\n' "Removing stale mise installs..."
    mise uninstall -y --all "${obsolete_mise_tools[@]}" > /dev/null 2>&1 || true
    printf '%s\n' "  ...done"

    # Retired npm GLOBALS. Dropping a line from .default-npm-packages only
    # stops future installs — it does not uninstall anything, so without this
    # sweep a retired CLI stays on every box that ever deployed it and keeps
    # resolving on PATH through the mise shims. That is the whole difference
    # between "the repo no longer installs X" and "the fleet no longer has X".
    #
    # Same hard rule as obsolete_mise_tools above: node, npm, corepack, pnpm
    # and anything a systemd unit execs through the shims must NEVER appear
    # here.
    obsolete_npm_globals=(
        "@google/gemini-cli"   # retired 2026-09-18, no longer in use
    )

    # npm globals install into the active mise node's prefix through its own
    # npm; `mise reshim` then exposes them via ~/.local/share/mise/shims to
    # every shell AND to systemd units. (mise also auto-installs this list
    # when it installs a new node version, via the ~/.default-npm-packages
    # symlink planted by 20_symlinks.zsh.)
    mise_node_ok=false
    if mise exec node -- node --version > /dev/null 2>&1; then
        mise_node_ok=true
    else
        printf '%s\n' "  ...mise node unavailable (mise install node); skipping npm globals"
    fi

    # Sweep the retired globals declared above, across EVERY installed node —
    # not just the active one.
    #
    # `mise exec node -- npm uninstall -g` only reaches the active version's
    # prefix. mise generates shims from every INSTALLED version, so a leftover
    # node (neptune still carried 22.20.0 long after mise.toml pinned 24) keeps
    # the package, and `mise reshim` faithfully recreates the shim from it. The
    # visible result is the worst kind: `gemini` still on PATH, but running it
    # gives "No version is set for shim" — a half-dead tool that looks like a
    # mise fault rather than a retired package.
    #
    # Iterating the install dirs also covers versions that are not currently
    # resolvable. The alias dirs (22, 22.20, latest, lts-*) symlink onto the
    # same real installs, so some passes are redundant no-ops; npm is
    # idempotent here and the clarity is worth more than the microseconds.
    if [[ $mise_node_ok == true && ${#obsolete_npm_globals[@]} -gt 0 ]]; then
        printf '%s\n' "Removing retired npm globals (all installed node versions)..."
        _node_installs="${XDG_DATA_HOME:-$HOME/.local/share}/mise/installs/node"
        for _node_prefix in "$_node_installs"/*/; do
            [ -x "${_node_prefix}bin/npm" ] || continue
            "${_node_prefix}bin/npm" uninstall -g "${obsolete_npm_globals[@]}" > /dev/null 2>&1 || true
        done
        unset _node_installs _node_prefix
        printf '%s\n' "  ...done"
    fi

    if [[ $mise_node_ok == true && -f $npm_packages_file ]]; then
        npm_packages=()
        npm_package=
        while IFS= read -r npm_package || [[ -n $npm_package ]]; do
            [[ -z $npm_package || $npm_package == \#* ]] && continue
            npm_packages+=("$npm_package")
        done < $npm_packages_file

        if (( ${#npm_packages[@]} > 0 )); then
            # Heal interrupted-reify damage BEFORE installing. An install pass
            # that dies mid-flight (the post-merge hook's `timeout 300` landing
            # on a genuinely slow npm night, OOM, Ctrl-C) leaves the packages
            # present but their bin links removed — npm unlinks before
            # relinking — and every one of them then dies through the mise
            # shims with "No version is set for shim" while node_modules looks
            # perfectly intact (makemake 2026-10-02 00:00: the entire globals
            # layer died this way, taking codex/t3/dsh/pnpm with it). rebuild
            # -g re-derives the bin links from what is already installed:
            # local, idempotent, no network. It cannot repair a truncated
            # package tree — the per-package retry below reinstalls those.
            printf '%s\n' "Relinking npm global bins (npm rebuild -g)..."
            mise exec node -- npm rebuild -g "${npm_packages[@]}" > /dev/null 2>&1 || true
            printf '%s\n' "  ...done"

            # Warm deploys install only globals that are missing, broken or
            # pin-mismatched, decided from one LOCAL inventory (npm prefix -g
            # + npm ls -g --depth 0 --json; no registry traffic). --upgrade
            # additionally refreshes @latest/unversioned entries. Uncertainty
            # always installs, never skips.

            # Standalone node script; tests extract the text between the two
            # marker comment lines inside the heredoc and run it under a real
            # node. Usage:
            #   node parser.js <inventory.json> <global-prefix> <spec>...
            # inventory.json is the raw `npm ls -g --depth 0 --json` output.
            # stdout, space-separated per spec (no field contains spaces):
            #   <spec> <name> <installedVersion|->
            #   <verdict: satisfied|missing|pinmismatch|broken|uncertain>
            npm_parser=$(mktemp "${TMPDIR:-/tmp}/npm-inventory-parser.XXXXXX") || npm_parser=
            if [[ -n $npm_parser ]]; then
                cat > "$npm_parser" <<'NPM_INVENTORY_PARSER_EOF'
// --- npm-inventory-parser BEGIN ---
var fs = require('fs');
var invPath = process.argv[2], prefix = process.argv[3];
var specs = process.argv.slice(4);
var deps;
try { deps = JSON.parse(fs.readFileSync(invPath, 'utf8')).dependencies || {}; }
catch (e) { deps = null; }
function emit(spec, name, ver, verdict) {
    process.stdout.write(spec + ' ' + name + ' ' + ver + ' ' + verdict + '\n');
}
for (var i = 0; i < specs.length; i++) {
    var spec = specs[i];
    var at = spec.lastIndexOf('@');
    var name = at > 0 ? spec.slice(0, at) : spec;
    var want = at > 0 ? spec.slice(at + 1) : 'latest';
    if (want === '') want = 'latest';
    if (deps === null || !name) { emit(spec, name || spec, '-', 'uncertain'); continue; }
    var dep = deps[name];
    var installed = dep && typeof dep.version === 'string' ? dep.version : null;
    if (!installed) { emit(spec, name, '-', 'missing'); continue; }
    // Selector classes: '' / 'latest' -> channel (any version satisfies);
    // strict exact semver (1 / 2 / 3 components + optional prerelease, no
    // build metadata) -> pin compare; anything else (tags, ranges, *) ->
    // 'uncertain' so the caller conservatively reinstalls.
    var exact = want.match(/^[0-9]+(\.[0-9]+){0,2}(-[0-9A-Za-z.]+)?$/);
    if (exact) {
        if (installed.replace(/^v/, '') !== want.replace(/^v/, '')) {
            emit(spec, name, installed, 'pinmismatch'); continue;
        }
    } else if (want !== 'latest') {
        emit(spec, name, installed, 'uncertain'); continue;
    }
    // Local integrity: a readable package.json with a version is required;
    // a bin map, when declared, must resolve to an EXECUTABLE REGULAR FILE
    // (through the <prefix>/bin link) — existsSync alone passes directories
    // and non-executable scripts, which are broken CLIs, not installed ones.
    // Library globals with NO bin are valid (happy-dom, @ast-grep/napi).
    var pkgJson = prefix + '/lib/node_modules/' + name + '/package.json';
    var pkg = null;
    try { pkg = JSON.parse(fs.readFileSync(pkgJson, 'utf8')); } catch (e) {}
    var bins = pkg && typeof pkg.bin !== 'undefined' ? pkg.bin : null;
    var broken = !pkg || typeof pkg.version !== 'string';
    if (!broken && bins) {
        var binNames = typeof bins === 'string' ? [name.split('/').pop()] : Object.keys(bins);
        for (var b = 0; b < binNames.length; b++) {
            var binPath = prefix + '/bin/' + binNames[b];
            var ok = false;
            try {
                ok = fs.statSync(binPath).isFile() &&
                     fs.accessSync(binPath, fs.constants.X_OK) === undefined;
            } catch (e) { ok = false; }
            if (!ok) { broken = true; break; }
        }
    }
    if (broken) { emit(spec, name, installed, 'broken'); continue; }
    emit(spec, name, installed, 'satisfied');
}
// --- npm-inventory-parser END ---
NPM_INVENTORY_PARSER_EOF
            fi

            npm_inv=$(mktemp "${TMPDIR:-/tmp}/npm-inventory.XXXXXX") || npm_inv=
            npm_decisions=$(mktemp "${TMPDIR:-/tmp}/npm-decisions.XXXXXX") || npm_decisions=
            npm_prefix=
            npm_ls_ok=true
            if [[ -n $npm_inv && -n $npm_decisions ]]; then
                npm_prefix=$(mise exec node -- npm prefix -g 2>/dev/null) || npm_prefix=
                # npm ls exits non-zero on problems while still printing
                # (partial) JSON — a non-zero status means the inventory is
                # NOT trusted even when the stdout looks valid; uncertainty
                # falls back to installing everything below.
                mise exec node -- npm ls -g --depth 0 --json > "$npm_inv" 2>/dev/null || npm_ls_ok=false
            fi

            npm_install=()
            if [[ $npm_ls_ok == false || -z $npm_parser || -z $npm_prefix ||
                  -z $npm_inv || -z $npm_decisions || ! -s $npm_inv ]]; then
                # Inventory unavailable — conservative: install everything.
                printf '%s\n' "  ...npm inventory unavailable; installing all declared globals" >&2
                npm_install=("${npm_packages[@]}")
            elif ! mise exec node -- node "$npm_parser" "$npm_inv" "$npm_prefix" \
                    "${npm_packages[@]}" > "$npm_decisions" 2>/dev/null; then
                printf '%s\n' "  ...npm inventory parse failed; installing all declared globals" >&2
                npm_install=("${npm_packages[@]}")
            else
                while read -r _npm_spec _npm_name _npm_inst _npm_verdict; do
                    [ -z "$_npm_spec" ] && continue
                    case $_npm_verdict in
                        satisfied)
                            # Skip in default mode. Under --upgrade, refresh
                            # @latest/unversioned channels ONLY; an exact pin
                            # already at its desired version is never bumped.
                            if $upgrade_mode; then
                                # Classify the selector exactly like the
                                # parser does: strip a LEADING scope @ first,
                                # else '@scope/pkg' would read 'pkg' as a
                                # version suffix and never refresh.
                                _npm_chk=${_npm_spec#@}
                                case $_npm_chk in
                                    *@*) _npm_want=${_npm_chk##*@} ;;
                                    *)   _npm_want=latest ;;
                                esac
                                if [[ -z $_npm_want || $_npm_want == latest ]]; then
                                    npm_install+=("$_npm_name@latest")
                                fi
                            fi
                            ;;
                        missing|broken|pinmismatch|uncertain)
                            # Reinstall with the ORIGINAL spec so an exact
                            # pin is restored as name@pin, never name@latest.
                            npm_install+=("$_npm_spec")
                            ;;
                    esac
                done < "$npm_decisions"
            fi

            # D6 gap the inventory cannot see: the bin link exists but the
            # CLI dies (t3's absent platform-optional).
            # A failing --version probe queues the DECLARED spec for
            # reinstall — the original entry, so an exact pin is repaired as
            # name@pin, never silently bumped to latest. A CLI that breaks
            # but is not declared here is only warned about, never repaired.
            for _rt in t3 pi; do
                if have "$_rt" && ! "$_rt" --version > /dev/null 2>&1; then
                    case $_rt in
                        t3) _rt_pkg=t3 ;;
                        pi) _rt_pkg=@earendil-works/pi-coding-agent ;;
                    esac
                    _rt_decl=
                    for _rt_q in "${npm_packages[@]}"; do
                        case $_rt_q in
                            "$_rt_pkg"|"$_rt_pkg"@*) _rt_decl=$_rt_q; break ;;
                        esac
                    done
                    if [[ -n $_rt_decl ]]; then
                        npm_install+=("$_rt_decl")
                        printf '%s\n' "  ...$_rt is on PATH but --version fails; queuing $_rt_decl for reinstall" >&2
                    else
                        printf '%s\n' "  WARNING: $_rt is on PATH but --version fails and it is not declared in $npm_packages_file" >&2
                    fi
                fi
                unset _rt_pkg _rt_decl _rt_q
            done
            unset _rt _npm_spec _npm_name _npm_inst _npm_verdict _npm_want _npm_chk

            # Dedup the queue preserving order: a package the inventory
            # already queued (e.g. broken) AND a failing t3/pi probe queue
            # must install/retry once, not twice.
            npm_queued=()
            for _npm_q in "${npm_install[@]}"; do
                _npm_seen=false
                for _npm_u in "${npm_queued[@]}"; do
                    if [[ $_npm_q == "$_npm_u" ]]; then
                        _npm_seen=true
                        break
                    fi
                done
                if [[ $_npm_seen == false ]]; then
                    npm_queued+=("$_npm_q")
                fi
            done
            npm_install=("${npm_queued[@]}")
            unset npm_queued _npm_q _npm_u

            if (( ${#npm_install[@]} == 0 )); then
                printf '%s\n' "  ...all npm globals satisfied; nothing to install (refresh @latest with --upgrade)"
            else
                # ONE batch install for the unsatisfied set (single npm
                # resolution pass, official --libc override, captured
                # output). On batch failure: warn once with an excerpt,
                # then retry EACH queued package individually — a bad
                # package never takes the others down, and nothing is
                # skipped.
                printf '%s\n' "Installing npm globals through mise node's npm (${#npm_install[@]} of ${#npm_packages[@]})..."
                npm_failed=()
                npm_batch_ok=false
                npm_log=$(mktemp "${TMPDIR:-/tmp}/npm-global-batch.XXXXXX") || npm_log=
                if [[ -z $npm_log ]]; then
                    printf '%s\n' "  ...batch log tempfile unavailable; falling back to per-package installs" >&2
                elif mise exec node -- npm install -g ${npm_libc_flag:-} "${npm_install[@]}" > "$npm_log" 2>&1; then
                    npm_batch_ok=true
                    rm -f "$npm_log"
                    printf '%s\n' "  ...done"
                else
                    printf '%s\n' "  ...batch install failed; retrying each package individually. Last lines of batch output:" >&2
                    tail -n 5 "$npm_log" | sed 's/^/    | /' >&2
                    rm -f "$npm_log"
                fi
                if [[ $npm_batch_ok == false ]]; then
                    for npm_package in "${npm_install[@]}"; do
                        npm_log=$(mktemp "${TMPDIR:-/tmp}/npm-global.XXXXXX") || npm_log=
                        if [[ -z $npm_log ]]; then
                            npm_failed+=("$npm_package")
                            continue
                        fi
                        if mise exec node -- npm install -g ${npm_libc_flag:-} "$npm_package" > "$npm_log" 2>&1; then
                            rm -f "$npm_log"
                        else
                            npm_failed+=("$npm_package")
                            printf '%s\n' "  ...$npm_package failed; last lines of output:"
                            tail -n 5 "$npm_log" | sed 's/^/    | /'
                            rm -f "$npm_log"
                        fi
                    done
                fi
                if (( ${#npm_failed[@]} == 0 )); then
                    if [[ $npm_batch_ok == false ]]; then
                        printf '%s\n' "  ...done (per-package retry: all packages installed)"
                    fi
                else
                    printf '%s\n' "  ...${#npm_failed[@]} package(s) failed: ${npm_failed[*]}" >&2
                fi
                unset npm_failed npm_batch_ok npm_log
            fi
            rm -f "$npm_parser" "$npm_inv" "$npm_decisions"
            unset npm_parser npm_inv npm_decisions npm_prefix npm_install
        fi

        # corepack is in the npm globals list AFTER pnpm, so its bin shim wins
        # the `pnpm` name (pnpm's own binary is demoted to `pn`). corepack then
        # serves pnpm from its OWN cache under $XDG_CACHE_HOME/node/corepack,
        # which npm never touches — so `pnpm@latest` in .default-npm-packages
        # updates `pn` while `pnpm` silently stays pinned to whatever corepack
        # last cached (it sat on 11.5.1 for months this way). Point corepack at
        # the current pnpm too so both names agree.
        printf '%s\n' "Pointing corepack's pnpm shim at the current release..."
        if mise exec node -- corepack install -g pnpm@latest > /dev/null 2>&1; then
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to refresh corepack pnpm (non-fatal)"
        fi
    fi

    mise reshim --force -y > /dev/null 2>&1 || true
    hash -r

    # Declared-but-broken CLIs slipped through the quiet install path on
    # pluto (audit 2026-09-29): t3 resolved but died without its platform
    # optional, pi was observed absent. Verify loudly on every deploy —
    # warn only; a missing CLI must not fail the fleet's unattended
    # pull-deploy (warn-not-fail, 66_infra precedent). linear-cli is checked
    # separately, AFTER the cargo leg later in this fragment (on a fresh box
    # that leg runs below this block — checking here would false-warn).
    for rt_check in t3 pi; do
        if have "$rt_check"; then
            if ! "$rt_check" --version > /dev/null 2>&1; then
                printf '%s\n' "  WARNING: $rt_check is on PATH but --version fails; check its optional platform package" >&2
            fi
        else
            printf '%s\n' "  WARNING: $rt_check is declared but not on PATH; install it and re-run deploy" >&2
        fi
    done
    unset rt_check

    # One-shot teardown of the abandoned Vite+ node manager. vp hijacked
    # node/npm/pnpm through ~/.vite-plus/bin shims that only interactive
    # shells had on PATH, while systemd units kept resolving node through
    # mise — a split-brain that made service breakage invisible from a
    # terminal. Only remove once the mise node demonstrably works, so a
    # botched deploy can't leave the machine with no node at all.
    if [[ $mise_node_ok == true && -d $HOME/.vite-plus ]]; then
        printf '%s\n' "Removing Vite+ (node/npm are mise-managed; see configs/mise.toml)..."
        rm -rf -- $HOME/.vite-plus
        printf '%s\n' "  ...done"
    fi
fi

# gjc (gajae-code) — RETIRED 2026-09-18. It used to be installed here as a bun
# global (a bun-ONLY package: `engines: { bun: ">=1.4.0" }`, bin/gjc.js under
# `#!/usr/bin/env bun`) and bridged onto PATH with a ~/.local/bin/gjc symlink,
# because bun's global bin dir is on no PATH here.
#
# Both are drift-corrected away rather than merely un-installed, for the same
# reason as obsolete_npm_globals above: a box that already deployed gjc keeps
# both the bun global and the hand-made symlink forever otherwise, and the
# symlink is what put it on PATH for systemd units and paseo dispatch.
#
# NOTE for whoever removes this block later: bun itself stays. gjc was its only
# REQUIRED consumer (docs/cli-tools.md said as much), but bun is still a pinned
# runtime in configs/mise.toml, still offered as an alternative runner for
# configs/karabiner/karabiner.ts, and still has a completion row in
# 82_zsh_completions.zsh. Retiring bun is a separate decision.
deploy_rm -f "$HOME/.local/bin/gjc"
if have bun && [[ -z ${DEPLOY_DRY_RUN:+x} || $DEPLOY_DRY_RUN -eq 0 ]]; then
    if bun pm ls -g 2>/dev/null | grep -q gajae-code; then
        printf '%s\n' "Removing retired gjc (gajae-code) bun global..."
        bun remove -g gajae-code > /dev/null 2>&1 || true
        printf '%s\n' "  ...done"
    fi
fi

# CodeRabbit ships native macOS/Linux binaries through its official installer.
# Download completely before running; CI suppresses its browser-login prompt.
# Supply the managed bin directory on PATH so it never edits shell profiles.
if ! have coderabbit || $upgrade_mode; then
    printf '%s\n' "Installing/upgrading CodeRabbit CLI..."
    _coderabbit_installer=
    # The official installer (#!/usr/bin/env sh — dash-safe) hard-requires
    # `unzip` to extract the release archive (checked before it downloads
    # anything). On NixOS unzip is a system-profile package, not something
    # this fragment may install — so skip LOUDLY with the prerequisite named
    # instead of re-running a guaranteed-failure install every deploy
    # (pluto 2026-09-29: every deploy logged a bare "failed to install" with
    # the real error swallowed by the /dev/null). Coordinate the system
    # package with the NixOS config owner; this block self-heals the moment
    # unzip is present.
    if ! have unzip; then
        printf '%s\n' "  ...skipped CodeRabbit install: prerequisite 'unzip' not on PATH (system package; NixOS module owner to add)" >&2
    elif _coderabbit_installer=$(mktemp "${TMPDIR:-/tmp}/coderabbit-install.XXXXXX") \
        && _coderabbit_log=$(mktemp "${TMPDIR:-/tmp}/coderabbit-install-log.XXXXXX"); then
        _cr_rc=0
        curl --proto '=https' --tlsv1.2 -fsSL https://cli.coderabbit.ai/install.sh -o "$_coderabbit_installer" || _cr_rc=$?
        if (( _cr_rc == 0 )); then
            CI=1 CODERABBIT_INSTALL_DIR="$HOME/.local/bin" PATH="$HOME/.local/bin:$PATH" \
                sh "$_coderabbit_installer" > "$_coderabbit_log" 2>&1 || _cr_rc=$?
        fi
        if (( _cr_rc == 0 )) && have coderabbit; then
            hash -r
            printf '%s\n' "  ...done ($(coderabbit --version 2>/dev/null | head -1))"
        else
            # Named diagnostics: which stage failed and the installer's own
            # last lines, instead of a bare failure with /dev/null'd cause.
            _cr_tail=$(tail -2 "$_coderabbit_log" 2>/dev/null | tr -d '\033' | tr '\n' ' ' | cut -c1-160)
            printf '%s\n' "  ...failed to install CodeRabbit (non-fatal; rc=$_cr_rc${_cr_tail:+; tail: $_cr_tail})" >&2
        fi
        rm -f "$_coderabbit_installer" "$_coderabbit_log"
    else
        printf '%s\n' "  ...failed to create CodeRabbit installer tempfile (non-fatal)" >&2
    fi
    unset _coderabbit_installer _coderabbit_log _cr_rc _cr_tail
fi

if ! have cargo; then
    printf '%s\n' "Installing rustup and cargo..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path > /dev/null 2>&1; then
        export PATH=$HOME/.cargo/bin:$PATH
        printf '%s\n' "  ...done"
    else
        printf '%s\n' "  ...failed to install rustup, skipping"
    fi
fi

# linear-cli: git-only upstream, no mise/aqua/ubi backend exists (the crates
# release is stale; only the git master branch builds) — the one deliberate
# cargo-of-git install left (documented exception, docs/cli-tools.md).
#
# ~/.cargo/bin must be on the deploy shell's PATH BEFORE the probes: cargo
# drops the binary there, but a post-merge/cron deploy shell carries no
# interactive PATH wiring, so `have linear-cli` stayed false forever, the
# install re-ran every deploy, and the CLI never resolved for the user
# (pluto audit 2026-09-29, F3).
if [[ -d $HOME/.cargo/bin ]]; then
    case ":$PATH:" in
        *":$HOME/.cargo/bin:"*) ;;
        *) export PATH="$HOME/.cargo/bin:$PATH" ;;
    esac
fi
# linear-cli build failures must be diagnosable: a cargo-of-git install is a
# SOURCE build (C toolchain, openssl headers, …), and swallowing the output
# into /dev/null left pluto failing with zero evidence. Capture to a bounded
# persistent log, print an excerpt, keep the log for root to inspect.
_linear_log_dir=${XDG_STATE_HOME:-$HOME/.local/state}
_linear_log=$_linear_log_dir/linear-cli-install.log
if have cargo; then
    deploy_mkdir -p "$_linear_log_dir"
    if ! have linear-cli && [[ ! -x $HOME/.cargo/bin/linear-cli ]]; then
        printf '%s\n' "Installing linear-cli via cargo..."
        if cargo install --git https://github.com/Finesssee/linear-cli.git --branch master --locked > "$_linear_log" 2>&1; then
            rm -f "$_linear_log"
            printf '%s\n' "  ...done"
        else
            # A cargo-of-git build needs a C toolchain to link, which a stock
            # NixOS host does not ship (nix-ld only covers prebuilt binaries).
            if ! have cc && ! have gcc && ! have clang; then
                printf '%s\n' "  ...failed to install linear-cli (no C toolchain found; on NixOS add gcc to the host's systemPackages)"
            else
                printf '%s\n' "  ...failed to install linear-cli"
            fi
            printf '%s\n' "  last lines of the build log:"
            tail -n 15 "$_linear_log" | sed 's/^/    | /'
            printf '%s\n' "  full log: $_linear_log"
        fi
    fi
    # Post-cargo-leg verify (fresh boxes install linear-cli above; see the
    # t3/pi verify note for why this runs after, not before).
    if have linear-cli && ! linear-cli --version > /dev/null 2>&1; then
        printf '%s\n' "  WARNING: linear-cli is on PATH but --version fails" >&2
    fi
    if $upgrade_mode; then
        printf '%s\n' "Upgrading linear-cli via cargo..."
        if cargo install --git https://github.com/Finesssee/linear-cli.git --branch master --locked --force > "$_linear_log" 2>&1; then
            rm -f "$_linear_log"
            printf '%s\n' "  ...done"
        else
            printf '%s\n' "  ...failed to upgrade linear-cli; last lines:"
            tail -n 15 "$_linear_log" | sed 's/^/    | /'
            printf '%s\n' "  full log: $_linear_log"
        fi
    fi
fi
unset _linear_log _linear_log_dir

# Pluto (NixOS) daemon runtime: the bare `paseo` on PATH stays the STOCK CLI
# pinned in configs/mise.toml; the paseo-daemon unit runs the FORK package
# (npm:@camerontaylor/paseo-cli) at the exact version the infra repo
# declares. Materialize the fork here with a direct `mise install <ref>` —
# never via mise.toml/use — so there is exactly one fork channel and no
# duplicate third pin (the checker asserts base-version agreement). NixOS
# only: the Macs run the daemon from the app bundle. 66_infra runs before
# this fragment, so a fresh machine has the infra checkout here. Warn-not-
# fail throughout: named failure lines, deploy stays green.
#
# The typed bracket option is the official per-tool npm-backend setting
# (mise docs, dev-tools/backends/npm): the fork package was first published
# 2026-09-13 — 16 days before the 2026-09-29 first install — which is inside
# mise's 30-day minimumPackageAge threshold (43200 minutes), so the gate
# rejects it without allow_low_downloads=true — approved for THIS selector
# only, no global trust loosening. Exec/ref syntax stays plain. Scope is
# pluto only: a NixOS host whose short hostname is pluto (uname -n is
# portable across BSD/GNU; no `hostname` dependency).
paseo_host=$(uname -n 2>/dev/null) || paseo_host=
paseo_host=${paseo_host%%.*}
if [[ -e /etc/NIXOS && $paseo_host == pluto ]] && have mise && have python3; then
    paseo_infra_dir=${INFRA_DIR:-$HOME/.local/infra}
    if [[ ! -d $paseo_infra_dir ]]; then
        printf '%s\n' "  WARNING: INFRA_DIR $paseo_infra_dir missing; cannot resolve the pinned fork paseo daemon ref" >&2
    # The checker's stdout IS the validated ref (a failed check exits
    # non-zero and prints its own named diagnostic on stderr, passed
    # through) — a failed checker NEVER installs anything.
    elif paseo_ref=$(python3 "$SCRIPT_DIR/scripts/tests/check-paseo-pins.py" \
            --dotfiles "$SCRIPT_DIR" --infra "$paseo_infra_dir" --print-daemon-tool); then
        paseo_install_ref="${paseo_ref%@*}[allow_low_downloads=true]@${paseo_ref##*@}"
        paseo_install_log=${XDG_STATE_HOME:-$HOME/.local/state}/paseo-fork-install.log
        deploy_mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}"
        printf '%s\n' "Materializing fork paseo daemon runtime ($paseo_ref)..."
        if mise install "$paseo_install_ref" > "$paseo_install_log" 2>&1; then
            rm -f "$paseo_install_log"
            if paseo_ver=$(mise exec "$paseo_ref" -- paseo --version 2>/dev/null); then
                printf '%s\n' "  ...done (fork paseo --version: ${paseo_ver:-unknown})"
            else
                printf '%s\n' "  WARNING: fork install ok but 'mise exec $paseo_ref -- paseo --version' failed" >&2
            fi
        else
            printf '%s\n' "  WARNING: mise install '$paseo_install_ref' failed; last lines:"
            tail -n 15 "$paseo_install_log" | sed 's/^/    | /'
            printf '%s\n' "  full log: $paseo_install_log"
        fi
        unset paseo_install_ref paseo_install_log paseo_ver
    else
        printf '%s\n' "  WARNING: check-paseo-pins.py rejected the pins; fork daemon NOT materialized (see its diagnostic above)" >&2
    fi
    unset paseo_infra_dir paseo_ref
fi
unset paseo_host

# ghx (GitHub CLI caching layer) retired 2026-08: gh is mise-managed again
# (configs/mise.toml). Drift-correct hosts that still carry ghx's curl install:
# its install.sh planted ghx/ghxd plus a `gh` shim in ~/.local/bin, which would
# shadow mise's real gh on PATH. Only delete ~/.local/bin/gh when it is
# actually the shim (mentions ghx), never a real binary someone put there.
# ~/.ghx holds the cache and ghx's auto-managed gh binary. Brew hosts get the
# equivalent cleanup in 75_brew_setup.zsh.
if [[ -e $HOME/.local/bin/ghx || -d $HOME/.ghx ]]; then
    printf '%s\n' "Removing ghx (gh is mise-managed again)..."
    # ghxd self-daemonizes (reparents to PID 1) and ignores SIGTERM; KILL it.
    pkill -9 -u "$USER" -x ghxd 2>/dev/null || true
    rm -f "$HOME/.local/bin/ghx" "$HOME/.local/bin/ghxd"
    if [[ -f $HOME/.local/bin/gh ]] && grep -q ghx "$HOME/.local/bin/gh" 2>/dev/null; then
        rm -f "$HOME/.local/bin/gh"
    fi
    rm -rf "$HOME/.ghx"
    hash -r
    printf '%s\n' "  ...done"
fi
