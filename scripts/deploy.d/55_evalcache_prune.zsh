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

local cache_dir=$XDG_CACHE_HOME/zsh/eval

if [[ ! -d $cache_dir ]]; then
    return 0
fi

print "Pruning empty evalcache entries..."

# Glob qualifiers: N=nullglob, .=regular file, L0=size exactly 0 bytes
local -a empty_caches=($cache_dir/*.zsh(N.L0))

if (( ${#empty_caches} == 0 )); then
    print "  ...none found"
    return 0
fi

if (( DEPLOY_DRY_RUN )); then
    local f
    for f in $empty_caches; do
        print "  [dry-run] would remove $f (and $f.zwc if present)"
    done
    return 0
fi

local f
for f in $empty_caches; do
    zf_rm -f $f $f.zwc
done
print "  ...removed ${#empty_caches} empty cache file(s)"
