# Wire .git/hooks/pre-commit into scripts/, and retire the old auto-deploy
# post-merge hook. Deploy no longer rides on `git pull`: the scheduled
# scripts/pull-and-deploy job (99_periodic.zsh) runs it explicitly, and a hand
# pull deploys nothing.

printf '%s\n' "Installing git hooks..."
deploy_mkdir -p .git/hooks
# Remove only OUR post-merge hook: the ../../scripts/post-merge symlink every
# earlier deploy placed (dangling now that the script is gone), or a copy whose
# body carries the old hook's opt-out knob. A foreign hook is left alone.
if [[ -L .git/hooks/post-merge ]]; then
    case "$(readlink .git/hooks/post-merge)" in
        ../../scripts/post-merge|"$SCRIPT_DIR"/scripts/post-merge)
            deploy_rm -f .git/hooks/post-merge
            printf '%s\n' "  ...removed retired post-merge auto-deploy hook"
            ;;
    esac
elif [[ -f .git/hooks/post-merge ]] && grep -q DOTFILES_SKIP_POSTMERGE .git/hooks/post-merge 2>/dev/null; then
    deploy_rm -f .git/hooks/post-merge
    printf '%s\n' "  ...removed retired post-merge auto-deploy hook"
fi
if [[ -L .git/hooks/post-checkout && "$(readlink .git/hooks/post-checkout)" == ../../deploy.zsh ]]; then
    rm .git/hooks/post-checkout
fi
deploy_ln -sfn ../../scripts/pre-commit .git/hooks/pre-commit
printf '%s\n' "  ...done"
