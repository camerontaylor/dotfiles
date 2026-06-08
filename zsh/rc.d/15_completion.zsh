# Completion tweaks
zstyle ':completion:*'              list-colors         ${(s.:.)LS_COLORS}
zstyle ':completion:*'              list-dirs-first     true
zstyle ':completion:*:*:-command-:*' list-dirs-first     false
zstyle ':completion:*'              verbose             true
zstyle ':completion:*'              menu                no
zstyle ':completion:*'              matcher-list        'm:{[:lower:]}={[:upper:]}'
zstyle ':completion::complete:*'    use-cache           true
zstyle ':completion::complete:*'    cache-path          $XDG_CACHE_HOME/zsh/compcache
zstyle ':completion:*:descriptions' format              [%d]
zstyle ':completion:*:manuals'      separate-sections   true

# Enable cached completions, if present
if [[ -d $XDG_CACHE_HOME/zsh/fpath ]]; then
    fpath=($XDG_CACHE_HOME/zsh/fpath $fpath)
fi

# Additional completions
fpath=($ZDOTDIR/plugins/completions/src $ZDOTDIR/plugins/git-completion/src $fpath)

# Enable git-extras completions. git-extras is installed via the system package
# manager now (brew / paru), so source its completion from wherever the package
# placed it; skip silently when git-extras isn't installed.
for _ge_comp in \
    $HOMEBREW_PREFIX/share/zsh/site-functions/_git_extras \
    /opt/homebrew/share/zsh/site-functions/_git_extras \
    /usr/local/share/zsh/site-functions/_git_extras \
    /usr/share/zsh/site-functions/_git_extras \
    /usr/share/git-extras/etc/git-extras-completion.zsh; do
    if [[ -r $_ge_comp ]]; then
        source $_ge_comp
        break
    fi
done
unset _ge_comp

# Make sure complist is loaded
zmodload zsh/complist

# Init completions, but regenerate compdump only once a day.
# The globbing is a little complicated here:
# - '#q' is an explicit glob qualifier that makes globbing work within zsh's [[ ]] construct.
# - 'N' makes the glob pattern evaluate to nothing when it doesn't match (rather than throw a globbing error)
# - '.' matches "regular files"
# - 'mh+20' matches files (or directories or whatever) that are older than 20 hours.
autoload -Uz compinit
if [[ -n $XDG_CACHE_HOME/zsh/compdump(#qN.mh+20) ]]; then
    compinit -i -u -d $XDG_CACHE_HOME/zsh/compdump
    # zrecompile fresh compdump in background
    {
        autoload -Uz zrecompile
        zrecompile -pq $XDG_CACHE_HOME/zsh/compdump
    } &!
else
    compinit -i -u -C -d $XDG_CACHE_HOME/zsh/compdump
fi

# Enable bash completions too
autoload -Uz bashcompinit
bashcompinit

# wrap-sudo (aliased from sudo in 08_aliases.zsh) needs sudo's completion
compdef wrap-sudo=sudo
