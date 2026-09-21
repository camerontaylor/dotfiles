# POSIX sh login layer — the third shell.
# zsh (.zshenv) and bash (.bash_profile) both reach the shared zsh/env.d layer
# on their own; `sh -l` reads neither entrypoint, so it needs ~/.profile to get
# there. The file sources shared env.d members rather than redefining anything.
# 3.2 floor: mirrors 21_bash_symlinks' constructs exactly.

printf '%s\n' "Linking sh login profile..."

# bash only reads ~/.profile when ~/.bash_profile is absent, and ours is not —
# so this link serves POSIX sh alone and cannot change bash's behaviour.
deploy_ln -sfn $SCRIPT_DIR/sh/.profile $HOME/.profile

printf '%s\n' "  ...done"
