# path_prepend DIR... — prepend each directory to PATH.
#
# The dual-shell replacement for zsh's tied-array idiom
# (`typeset -U path PATH` + `path=(new $path)`), which bash parses as a plain
# scalar assignment and silently ignores (docs/bash-compatibility.md §C —
# ~10 no-op sites). Semantics deliberately match the zsh idiom, not merely
# "skip if present":
#
#   * argument order is preserved — path_prepend A B yields A:B:<rest>,
#     exactly like `path=(A B $path)` (NOT B:A like two sequential prepends);
#   * dirs already on PATH are MOVED to the front, like zsh's unique tied
#     array keeping the first (newest) occurrence — not left in place;
#   * NO existence check — `path=(…)` never had one either. Call sites that
#     guarded with `[[ -d $dir ]] && path=($dir $path)` keep that guard on
#     the path_prepend call; dropping it here would silently remove
#     never-checked-but-declared dirs (e.g. $GOPATH/bin before `go install`)
#     and change zsh's PATH.
#
# Runs identically under zsh (where the assignment syncs the tied path array
# and -U keeps it unique) and bash 3.2. Defined in env.d/00_ so both the zsh
# .zshenv loop and the bash env loader have it before any 03+/rc.d use site;
# single source of truth for both shells.
path_prepend() {
    local d prefix= suffix=$PATH entry head
    for d in "$@"; do
        # Same dir twice in one call collapses, like zsh's unique array.
        case ":$prefix:" in
            *":$d:"*) continue ;;
        esac
        # Drop any existing occurrence of $d from the tail so it ends up at
        # the front (zsh `typeset -U` move-to-front semantics).
        case ":$suffix:" in
            *":$d:"*)
                head=$suffix
                suffix=
                while :; do
                    case $head in
                        *:*) entry=${head%%:*}; head=${head#*:} ;;
                        *)   entry=$head; head= ;;
                    esac
                    [ "$entry" = "$d" ] || suffix=${suffix:+$suffix:}$entry
                    if [ -z "$head" ]; then break; fi
                done
                ;;
        esac
        prefix=${prefix:+$prefix:}$d
    done
    # No prepends (every arg missing/nonexistent) must leave PATH untouched —
    # not with a leading colon.
    if [ -n "$prefix" ]; then
        PATH=$prefix${suffix:+:$suffix}
    else
        PATH=$suffix
    fi
    export PATH
}
