# Wire .git/hooks/{post-merge,pre-commit} into scripts/. post-merge auto-runs
# this whole pipeline on every `git pull`, gated by GIT_REFLOG_ACTION.

printf '%s\n' "Installing git hooks..."
deploy_mkdir -p .git/hooks
deploy_ln -sfn ../../scripts/post-merge .git/hooks/post-merge
if [[ -L .git/hooks/post-checkout && "$(readlink .git/hooks/post-checkout)" == ../../deploy.zsh ]]; then
    rm .git/hooks/post-checkout
fi
deploy_ln -sfn ../../scripts/pre-commit .git/hooks/pre-commit
printf '%s\n' "  ...done"

