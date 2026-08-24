# Smoke-test that key CLI tools deployed via mise / brew / submodules actually
# run. Catches the silent-binary scenario where a tool ends up on PATH (e.g.
# via a mise shim) but the underlying install is broken or partial, which the
# rest of deploy.zsh has no way to detect.
#
# This fragment intentionally does NOT abort the deploy (deploy.zsh runs with
# `err_exit`, but every check here is guarded by `if`). Failures are surfaced
# as a final warning block with actionable next steps.

print "Verifying deployed CLI tools respond..."

ensure_homebrew_path 2>/dev/null || true
rehash

# Pairs: <display name> <binary on PATH>
# Listed roughly in order of "user-visible breakage if missing".
local -a tool_checks=(
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
    wget:wget
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

typeset -a failed=()
local entry tool bin_name

for entry in $tool_checks; do
    tool=${entry%%:*}
    bin_name=${entry##*:}

    if (( ! ${+commands[$bin_name]} )); then
        failed+=("$tool ($bin_name): not on PATH")
        continue
    fi

    # A few tools don't support --version; try -V as fallback before giving up.
    if ! command $bin_name --version > /dev/null 2>&1 \
        && ! command $bin_name -V > /dev/null 2>&1; then
        failed+=("$tool ($bin_name): launches but --version/-V failed")
    fi
done

if (( ${#failed} == 0 )); then
    print "  ...all ${#tool_checks} checked tools respond"
    return 0
fi

print ""
print "⚠ ${#failed} tool(s) failed smoke test:"
local line
for line in $failed; do
    print "    - $line"
done
print ""
print "Hints:"
print "  - re-run with --upgrade to refresh mise installs:  ./deploy.zsh --upgrade"
print "  - inspect the deploy log:                          $XDG_STATE_HOME/dotfiles-deploy.log"
print "  - check mise health:                               mise doctor"
print "  - if a binary is on PATH but doesn't launch, the install is corrupt — try:"
print "      mise uninstall <tool> && mise install"
