# Smoke-test that key CLI tools deployed via mise / brew / submodules actually
# run. Catches the silent-binary scenario where a tool ends up on PATH (e.g.
# via a mise shim) but the underlying install is broken or partial, which the
# rest of deploy.zsh has no way to detect.
#
# This fragment intentionally does NOT abort the deploy (deploy.zsh runs with
# `err_exit`, but every check here is guarded by `if`). Failures are surfaced
# as a final warning block with actionable next steps.

printf '%s\n' "Verifying deployed CLI tools respond..."

ensure_homebrew_path 2>/dev/null || true
hash -r

# Pairs: <display name> <binary on PATH>
# Listed roughly in order of "user-visible breakage if missing".
tool_checks=(
    zoxide:zoxide
    eza:eza
    bat:bat
    fd:fd
    sd:sd
    ripgrep:rg
    fzf:fzf
    delta:delta
    htop:htop
    mosh:mosh
    gh:gh
    git-restore-mtime:git-restore-mtime
    glab:glab
    ast-grep:sg
    tree-sitter:tree-sitter
    sops:sops
    age:age
    neovim:nvim
    mise:mise
    node:node
    npm:npm
    pnpm:pnpm
    corepack:corepack
    psql:psql
)

failed=()
entry= tool= bin_name=

for entry in "${tool_checks[@]}"; do
    tool=${entry%%:*}
    bin_name=${entry##*:}

    if ! have "$bin_name"; then
        failed+=("$tool ($bin_name): not on PATH")
        continue
    fi

    # A few tools don't support --version; try -V as fallback before giving up.
    if ! command $bin_name --version > /dev/null 2>&1 \
        && ! command $bin_name -V > /dev/null 2>&1; then
        failed+=("$tool ($bin_name): launches but --version/-V failed")
    fi
done

if (( ${#failed[@]} == 0 )); then
    printf '%s\n' "  ...all ${#tool_checks[@]} checked tools respond"
    return 0
fi

printf '%s\n' ""
printf '%s\n' "⚠ ${#failed[@]} tool(s) failed smoke test:"
line=
for line in "${failed[@]}"; do
    printf '%s\n' "    - $line"
done
printf '%s\n' ""
printf '%s\n' "Hints:"
printf '%s\n' "  - re-run with --upgrade to refresh mise installs:  ./deploy.zsh --upgrade"
printf '%s\n' "  - inspect the deploy log:                          $XDG_STATE_HOME/dotfiles-deploy.log"
printf '%s\n' "  - check mise health:                               mise doctor"
printf '%s\n' "  - if a binary is on PATH but doesn't launch, the install is corrupt — try:"
printf '%s\n' "      mise uninstall <tool> && mise install"
