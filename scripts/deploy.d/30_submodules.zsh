# Sync git submodules + compile zsh plugin .zwc files.

print "Syncing submodules..."
git submodule sync > /dev/null
# Parallel + shallow clone cuts fresh-clone time ~70%.
git submodule update --init --recursive --jobs 8 --depth 1 > /dev/null
# Destructive clean only on --upgrade; otherwise dry-run report only.
# `clean -ffd` will silently delete any untracked work inside submodules, so
# never default-on after every `git pull`.
if $upgrade_mode; then
    git submodule foreach --recursive git clean -ffd
else
    pending=$(git submodule foreach --recursive --quiet 'git clean -n -d' 2>&1 | grep -v '^$' || true)
    if [[ -n $pending ]]; then
        print "  ...untracked files in submodules (would be removed with --upgrade):"
        print -- "$pending" | sed 's/^/    /'
    fi
fi
print "  ...done"

print "Compiling zsh plugins..."
autoload -Uz zrecompile
for zsh_plugin_file in $SCRIPT_DIR/zsh/plugins/**/*.zsh{-theme,}(#q.); do
    zrecompile -pq $zsh_plugin_file
done
print "  ...done"
