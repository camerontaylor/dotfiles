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
#   engram, oxlint, biome, happy, gemini — no upstream completion
#   moreutils binaries (sponge/ts/chronic/vipe), flock — trivial CLI surface

cache_fpath="$XDG_CACHE_HOME/zsh/fpath"

if (( DEPLOY_DRY_RUN )); then
    printf '%s\n' "  [dry-run] would: mkdir -p $cache_fpath"
    printf '%s\n' "  [dry-run] would: generate _bun, _uv, _sops, _codex, _opencode, _sg"
    return 0
fi

mkdir -p $cache_fpath

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
for entry in $generators; do
    tool=${entry%%:*}
    rest=${entry#*:}
    subcmd=${rest%:*}
    dest_name=${rest##*:}
    dest_path="$cache_fpath/$dest_name"

    if ! have "$tool"; then
        printf '%s\n' "  ...skip $tool (not installed)"
        (( skipped_count++ ))
        continue
    fi

    # Word-split subcmd at invocation; capture into a tmp file so a partial
    # failure mid-stream doesn't leave a half-broken completion installed.
    # NB: `local tmp` standalone at script-source level (no enclosing
    # function) acts as a typeset *query* and prints `tmp=<previous value>`
    # on the second loop iteration onward. Combining declaration with
    # assignment (`local tmp=$(…)`) avoids the query path.
    #
    # Strip leading blank lines via `sed '/./,$!d'` (portable BSD+GNU):
    # some generators (notably `sops completion zsh`) emit a leading blank,
    # which puts `#compdef sops` on line 2 — but compinit's autoload-on-tag
    # mechanism requires `#compdef NAME` on line 1.
    tmp=$(mktemp "${TMPDIR:-/tmp}/zsh-comp-${tool}.XXXXXX")
    if ${=tool} ${=subcmd} 2>/dev/null | sed '/./,$!d' > $tmp \
        && [[ -s $tmp ]] \
        && head -1 $tmp | grep -q "^#compdef\b"; then
        mv $tmp $dest_path
        printf '%s\n' "  ...wrote $dest_name"
        (( generated_count++ ))
    else
        rm -f $tmp
        printf '%s\n' "  ...failed to generate $dest_name from \`$tool $subcmd\`"
    fi
done

# `sg` is the binary name of ast-grep. The native generator emits a
# `#compdef ast-grep` script, so reuse that completion under the sg name
# via a 2-line shim rather than regenerating identical content.
if have sg; then
    cat > $cache_fpath/_sg <<'COMPDEF'
#compdef sg
(( $+functions[_ast-grep] )) || autoload -Uz _ast-grep
_ast-grep "$@"
COMPDEF
    printf '%s\n' "  ...wrote _sg (shim -> _ast-grep)"
    (( generated_count++ ))
fi

# Invalidate the compinit cache so the next interactive shell picks up the
# newly-written completions. The compdump regen path in 15_completion.zsh
# triggers when compdump is older than 20 hours, so without this the new
# files would sit unused until the cache naturally aged out.
compdump="$XDG_CACHE_HOME/zsh/compdump"
if [[ -f $compdump ]]; then
    rm -f $compdump $compdump.zwc
    printf '%s\n' "  ...invalidated compdump (next shell will regenerate)"
fi

printf '%s\n' "  ...$generated_count generated, $skipped_count skipped"
