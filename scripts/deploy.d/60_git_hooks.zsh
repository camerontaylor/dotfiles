# Wire .git/hooks/{post-merge,pre-commit} into scripts/. post-merge auto-runs
# this whole pipeline on every `git pull`, gated by GIT_REFLOG_ACTION.

print "Installing git hooks..."
zf_mkdir -p .git/hooks
zf_ln -sfn ../../scripts/post-merge .git/hooks/post-merge
if [[ -L .git/hooks/post-checkout && "$(readlink .git/hooks/post-checkout)" == ../../deploy.zsh ]]; then
    rm .git/hooks/post-checkout
fi
zf_ln -sfn ../../scripts/pre-commit .git/hooks/pre-commit
print "  ...done"

# Clean filter for the Codex config. Keeps Codex's per-session runtime trust
# state ([projects.*]/[hooks.state.*]) in the working tree while stripping it
# from the committed blob (see scripts/codex-config-clean.mjs + .gitattributes).
# Filter config is per-clone (.git/config), so it must be (re)asserted here.
print "Configuring codex-clean git filter..."
if (( DEPLOY_DRY_RUN )); then
    print "  [dry-run] git config filter.codex-clean.clean 'node scripts/codex-config-clean.mjs'"
else
    git config filter.codex-clean.clean "node scripts/codex-config-clean.mjs" \
        && print "  ...done" \
        || print "  WARNING: could not set filter.codex-clean.clean" >&2
fi
