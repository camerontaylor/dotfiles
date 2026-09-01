# Prune zero-byte evalcache files.
#
# zsh/fpath/evalcache memoizes the stdout of slow init commands like
# `zoxide init zsh` and `mise completion zsh` into $XDG_CACHE_HOME/zsh/eval
# for 20 hours. Historically, if the underlying command produced no output
# during a flaky moment (e.g. mise was mid-install and the binary was on
# PATH but not yet functional), evalcache wrote a 0-byte cache file and
# `source`d nothing on every subsequent shell start — silently disabling
# the integration until the 20h TTL expired.
#
# evalcache itself now refuses to lock in empty output, but any pre-existing
# poisoned files still need a sweep so users recover the next time they
# start a shell instead of waiting up to 20 hours.
#
# This fragment is fast (just a glob + rm) and is safe to run on every deploy.

cache_dir=$XDG_CACHE_HOME/zsh/eval

if [[ ! -d $cache_dir ]]; then
    return 0
fi

printf '%s\n' "Pruning empty evalcache entries..."

# Zero-byte regular *.zsh files. The old `*.zsh(N.L0)` glob qualifiers were
# zsh-only; find expresses N (silent empty result), . (regular file) and L0
# (exactly 0 bytes) as `-type f -size 0c` in both shells.
empty_caches=()
while IFS= read -r _cache_file; do
    empty_caches+=("$_cache_file")
done < <(find "$cache_dir" -maxdepth 1 -type f -name '*.zsh' -size 0c 2>/dev/null | sort)

if (( ${#empty_caches} == 0 )); then
    printf '%s\n' "  ...none found"
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    f=
    for f in $empty_caches; do
        printf '%s\n' "  [dry-run] would remove $f (and $f.zwc if present)"
    done
    return 0
fi

f=
for f in $empty_caches; do
    deploy_rm -f $f $f.zwc
done
printf '%s\n' "  ...removed ${#empty_caches} empty cache file(s)"
