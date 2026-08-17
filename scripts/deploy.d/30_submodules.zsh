# Sync git submodules + compile zsh plugin .zwc files.

print "Syncing submodules..."
git submodule sync > /dev/null
# Update only paths that are BOTH declared in .gitmodules AND gitlinks in the
# index: a declaration without a gitlink (or a legacy gitlink without a URL)
# makes the batched update fatal with "No url found" and silently skip every
# submodule that sorts after it. A checkout whose .git file points at a lost
# gitdir also wedges `git stash`/`--autostash` repo-wide, so re-clone those.
submodule_paths=()
while IFS= read -r _sm_path; do
    git ls-files --stage -- $_sm_path 2> /dev/null | grep -q '^160000' || continue
    if [[ -e $_sm_path/.git ]] && ! git -C $_sm_path rev-parse --git-dir > /dev/null 2>&1; then
        print "  ...repairing broken submodule checkout: $_sm_path"
        rm -rf $_sm_path
    fi
    submodule_paths+=($_sm_path)
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
# Parallel + shallow clone cuts fresh-clone time ~70%.
git submodule update --init --recursive --jobs 8 --depth 1 -- $submodule_paths > /dev/null
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
