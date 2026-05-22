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
