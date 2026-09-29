# Generate zsh completion files for mise/brew-installed tools whose own
# completion ships only via `<tool> completion zsh` (or similar). Output
# lands in $XDG_CACHE_HOME/zsh/fpath, which zsh/rc.d/15_completion.zsh
# already prepends to fpath — so compinit picks them up on next shell.
#
# Tools intentionally not generated here:
#   wtp     — has its own integration in zsh/rc.d/31_wtp.zsh
#   npm     — bash-format output requires `eval "$(npm completion)"` via
#             bashcompinit, can't be cached as a static `_npm` file
#   python  — completion is per-script via argcomplete, not global
#   fzf     — fzf-tab plugin handles the interactive UX
#   engram, oxlint, biome, happy — no upstream completion
#   moreutils binaries (sponge/ts/chronic/vipe), flock — trivial CLI surface
#
# SHELL matters: bun and opencode pick their completion language from $SHELL,
# NOT from a positional argument (opencode ignores the trailing "zsh"; bun's
# positional-less `bun completions` follows suit). Deploy fragments run under
# a native bash login, so without the explicit SHELL=zsh below both emit
# bash-format output that can never pass #compdef validation — the source of
# the "failed to generate" lines on every pluto deploy (2026-09-29). With
# SHELL=zsh, `bun completions` prints proper `#compdef bun` zsh to stdout and
# writes nothing to ~/.zshrc (destination is stdout-only here).

cache_fpath="$XDG_CACHE_HOME/zsh/fpath"

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would: mkdir -p $cache_fpath"
    printf '%s\n' "  [dry-run] would: generate _bun, _uv, _sops, _codex, _opencode, _sg"
    return 0
fi

mkdir -p "$cache_fpath"

# Generators run with SHELL forced to a real zsh so language-by-SHELL tools
# emit zsh. `command -v zsh` covers mise/NixOS zsh; the /bin/zsh fallback
# only names the language for tools that merely basename $SHELL.
zsh_bin=$(command -v zsh 2>/dev/null || printf '/bin/zsh')

# Each entry: <binary>:<subcommand-and-args producing #compdef output>:<dest filename>
# Subcommand string is split on whitespace at invocation time.
generators=(
    "bun:completions:_bun"
    "uv:generate-shell-completion zsh:_uv"
    "sops:completion zsh:_sops"
    "codex:completion zsh:_codex"
    "opencode:completion zsh:_opencode"
)

printf '%s\n' "Generating zsh completion files into $cache_fpath..."

entry= tool= subcmd= dest_name= dest_path= generated_count=0 skipped_count=0
for entry in "${generators[@]}"; do
    tool=${entry%%:*}
    rest=${entry#*:}
    subcmd=${rest%:*}
    dest_name=${rest##*:}
    dest_path="$cache_fpath/$dest_name"

    if ! have "$tool"; then
        printf '%s\n' "  ...skip $tool (not installed)"
        skipped_count=$((skipped_count+1))
        continue
    fi

    # Capture to tmp, validate, then atomically mv — a partial failure
    # mid-stream never leaves a half-broken completion installed. Leading
    # blanks are stripped (sed '/./,$!d', BSD+GNU): compinit requires
    # `#compdef NAME` on line 1 and some generators (sops) emit one.
    tmp_raw=$(mktemp "${TMPDIR:-/tmp}/zsh-comp-${tool}-raw.XXXXXX")
    tmp=$(mktemp "$cache_fpath/.zsh-comp-${tool}.XXXXXX")
    # ${=var} forced word-split is zsh-only; an unquoted $(…) command
    # substitution splits in both shells.
    subcmd_words=()
    for _w in $(printf '%s\n' "$subcmd"); do
        subcmd_words+=("$_w")
    done
    # Two-stage, no pipeline: capture the generator to tmp_raw and check ITS
    # exit status directly — under `tool | sed > tmp && …` a generator that
    # dies mid-stream can still leave sed-exiting-0 partial output, and
    # without pipefail the pipeline status would mask the failure. The dest
    # is replaced ONLY on rc=0 + non-empty + `#compdef` on line 1; any other
    # outcome leaves the previous completion untouched.
    gen_rc=0
    SHELL="$zsh_bin" "$tool" "${subcmd_words[@]}" > "$tmp_raw" 2>/dev/null || gen_rc=$?
    if (( gen_rc == 0 )) \
        && sed '/./,$!d' "$tmp_raw" > "$tmp" \
        && [[ -s $tmp ]] \
        && head -1 "$tmp" | grep -q "^#compdef\b"; then
        mv -f "$tmp" "$dest_path"
        printf '%s\n' "  ...wrote $dest_name"
        generated_count=$((generated_count+1))
    else
        first_line=$(head -1 "$tmp_raw" 2>/dev/null | cut -c1-60)
        rm -f "$tmp"
        printf '%s\n' "  ...failed to generate $dest_name from \`$tool $subcmd\` (rc=$gen_rc, first line: $first_line)"
    fi
    # tmp_raw survives the success path (mv consumed only tmp): remove it on
    # every outcome.
    rm -f "$tmp_raw"
done

# `sg` is the binary name of ast-grep. The native generator emits a
# `#compdef ast-grep` script, so reuse that completion under the sg name
# via a 2-line shim rather than regenerating identical content.
if have sg; then
    cat > "$cache_fpath/_sg" <<'COMPDEF'
#compdef sg
(( $+functions[_ast-grep] )) || autoload -Uz _ast-grep
_ast-grep "$@"
COMPDEF
    printf '%s\n' "  ...wrote _sg (shim -> _ast-grep)"
    generated_count=$((generated_count+1))
fi

# Invalidate the compinit cache so the next interactive shell picks up the
# newly-written completions. The compdump regen path in 15_completion.zsh
# triggers when compdump is older than 20 hours, so without this the new
# files would sit unused until the cache naturally aged out.
compdump="$XDG_CACHE_HOME/zsh/compdump"
if [[ -f $compdump ]]; then
    rm -f "$compdump" "$compdump.zwc"
    printf '%s\n' "  ...invalidated compdump (next shell will regenerate)"
fi

printf '%s\n' "  ...$generated_count generated, $skipped_count skipped"
