#!/usr/bin/env zsh

setopt extended_glob err_exit

# Parse arguments
local upgrade_mode=false
for arg in "$@"; do
    case $arg in
        --upgrade|-u)
            upgrade_mode=true
            ;;
    esac
done

zmodload -m -F zsh/files b:zf_\*

SCRIPT_DIR=${0:A:h}
# with systemd-homed `a`/`A` expands to storage location `/home/username.homedir` instead of mounted location `/home/username`
# therefore massage SCRIPT_DIR to expected home location by removing `.homedir` from it
if [[ $SCRIPT_DIR == $HOME.homedir* ]]; then
    SCRIPT_DIR=${SCRIPT_DIR/.homedir/}
fi
cd $SCRIPT_DIR

# Default XDG paths
XDG_CACHE_HOME=$HOME/.cache
XDG_CONFIG_HOME=$HOME/.config
XDG_DATA_HOME=$HOME/.local/share
XDG_STATE_HOME=$HOME/.local/state

local DOTFILES_OS=$(uname -s)
local DOTFILES_ARCH=$(uname -m)

ensure_homebrew_path() {
    if (( ${+commands[brew]} )); then
        return 0
    fi

    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
        if [[ -x $brew_bin ]]; then
            eval "$($brew_bin shellenv zsh)"
            rehash
            return 0
        fi
    done

    return 1
}

brew_install_or_upgrade() {
    local formula=$1
    local binary=${2:-$formula}

    if ! ensure_homebrew_path; then
        print "  ...Homebrew not available, skipping $formula"
        return 1
    fi

    if (( ! ${+commands[$binary]} )); then
        if brew install $formula > /dev/null 2>&1; then
            rehash
            print "  ...done"
            return 0
        fi
        print "  ...failed to install $formula"
        return 1
    elif $upgrade_mode; then
        if brew upgrade $formula > /dev/null 2>&1; then
            print "  ...done"
            return 0
        fi
        print "  ...$formula already at latest or upgrade failed"
        return 0
    fi
}

if [[ $DOTFILES_OS == Darwin ]]; then
    ensure_homebrew_path || true
fi

# Create required directories
print "Creating required directory tree..."
zf_mkdir -p $XDG_CONFIG_HOME/{ghostty,git/local,htop,ranger,gem,tig,gnupg,nvim/{plugin,after},yazi}
zf_mkdir -p $XDG_CACHE_HOME/{vim/{backup,swap,undo},zsh,tig}
zf_mkdir -p $XDG_DATA_HOME/{{goenv,jenv,luaenv,nodenv,phpenv,plenv,pyenv,rbenv}/plugins,zsh,man/man1,vim/spell,nvim/site/pack/plugins}
zf_mkdir -p $XDG_CONFIG_HOME/{mise,litellm,systemd/user,opencode,agent-orchestrator}
zf_mkdir -p $HOME/{.claude,.codex,.omx,.ssh,.agent-orchestrator,.worktrees}
zf_mkdir -p $XDG_STATE_HOME
zf_mkdir -p $HOME/.local/{bin,etc}
zf_chmod 700 $XDG_CONFIG_HOME/gnupg
zf_chmod 700 $HOME/.ssh
print "  ...done"

# Link zshenv if needed
print "Checking for ZDOTDIR env variable..."
if [[ $ZDOTDIR == $SCRIPT_DIR/zsh ]]; then
    print "  ...present and valid, skipping .zshenv symlink"
else
    print "  ...failed to match this script dir. ZDOTDIR is \"$ZDOTDIR\", which doesn't match expected value \"$SCRIPT_DIR/zsh\". Symlinking .zshenv"
    zf_ln -sfn $SCRIPT_DIR/zsh/.zshenv ${ZDOTDIR:-$HOME}/.zshenv
fi

# Link config files
print "Linking config files..."
zf_ln -sfn $SCRIPT_DIR/vim $XDG_CONFIG_HOME/vim
zf_ln -sfn $SCRIPT_DIR/nvim/init.lua $XDG_CONFIG_HOME/nvim/init.lua
zf_ln -sfn $SCRIPT_DIR/nvim/init $XDG_CONFIG_HOME/nvim/plugin/init
zf_ln -sfn $SCRIPT_DIR/nvim/lsp $XDG_CONFIG_HOME/nvim/after/lsp
zf_ln -sfn $SCRIPT_DIR/nvim/ftplugin $XDG_CONFIG_HOME/nvim/ftplugin
zf_ln -sfn $SCRIPT_DIR/nvim/plugins $XDG_DATA_HOME/nvim/site/pack/plugins/start
zf_ln -sfn $SCRIPT_DIR/tmux $XDG_CONFIG_HOME/tmux
zf_ln -sfn $SCRIPT_DIR/configs/ghostty $XDG_CONFIG_HOME/ghostty/config
zf_ln -sfn $SCRIPT_DIR/configs/gitconfig $XDG_CONFIG_HOME/git/config
zf_ln -sfn $SCRIPT_DIR/configs/gitattributes $XDG_CONFIG_HOME/git/attributes
zf_ln -sfn $SCRIPT_DIR/configs/gitignore $XDG_CONFIG_HOME/git/ignore
zf_ln -sfn $SCRIPT_DIR/configs/tigrc $XDG_CONFIG_HOME/tig/config
zf_ln -sfn $SCRIPT_DIR/configs/htoprc $XDG_CONFIG_HOME/htop/htoprc
zf_ln -sfn $SCRIPT_DIR/configs/ranger $XDG_CONFIG_HOME/ranger/rc.conf
zf_ln -sfn $SCRIPT_DIR/configs/gemrc $XDG_CONFIG_HOME/gem/gemrc
zf_ln -sfn $SCRIPT_DIR/configs/ranger-plugins $XDG_CONFIG_HOME/ranger/plugins
zf_ln -sfn $SCRIPT_DIR/configs/starship.toml $XDG_CONFIG_HOME/starship.toml
zf_ln -sfn $SCRIPT_DIR/configs/mise.toml $XDG_CONFIG_HOME/mise/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/agent-orchestrator/config.yaml $XDG_CONFIG_HOME/agent-orchestrator/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/agent-orchestrator/config.yaml $HOME/.agent-orchestrator/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/agent-orchestrator/config.yaml $HOME/.agent-orchestrator.yaml
zf_ln -sfn $SCRIPT_DIR/configs/litellm/config.yaml $XDG_CONFIG_HOME/litellm/config.yaml
zf_ln -sfn $SCRIPT_DIR/configs/litellm/litellm-proxy.service $XDG_CONFIG_HOME/systemd/user/litellm-proxy.service
zf_ln -sfn $SCRIPT_DIR/configs/litellm/proxy_wrapper.py $XDG_CONFIG_HOME/litellm/proxy_wrapper.py
zf_mkdir -p $XDG_CONFIG_HOME/waveterm
zf_ln -sfn $SCRIPT_DIR/configs/waveterm/settings.json $XDG_CONFIG_HOME/waveterm/settings.json
zf_mkdir -p $XDG_CONFIG_HOME/gtk-3.0
zf_ln -sfn $SCRIPT_DIR/configs/gtk-3.0-bookmarks $XDG_CONFIG_HOME/gtk-3.0/bookmarks
zf_ln -sfn $SCRIPT_DIR/yazi/init.lua $XDG_CONFIG_HOME/yazi/init.lua
zf_ln -sfn $SCRIPT_DIR/yazi/keymap.toml $XDG_CONFIG_HOME/yazi/keymap.toml
zf_ln -sfn $SCRIPT_DIR/yazi/theme.toml $XDG_CONFIG_HOME/yazi/theme.toml
zf_ln -sfn $SCRIPT_DIR/yazi/yazi.toml $XDG_CONFIG_HOME/yazi/yazi.toml
zf_ln -sfn $SCRIPT_DIR/yazi/plugins $XDG_CONFIG_HOME/yazi/plugins
zf_ln -sfn $SCRIPT_DIR/gpg/gpg.conf $XDG_CONFIG_HOME/gnupg/gpg.conf
zf_ln -sfn $SCRIPT_DIR/gpg/gpg-agent.conf $XDG_CONFIG_HOME/gnupg/gpg-agent.conf
zf_ln -sfn $SCRIPT_DIR/tools/git-diff-pager $HOME/.local/bin/git-diff-pager
zf_ln -sfn $SCRIPT_DIR/scripts/commit-conventional $HOME/.local/bin/commit-conventional
zf_ln -sfn $SCRIPT_DIR/scripts/generate-commit-msg $HOME/.local/bin/generate-commit-msg
# Claude Code + OMC
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/CLAUDE.md $HOME/.claude/CLAUDE.md
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/RTK.md $HOME/.claude/RTK.md
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/settings.json $HOME/.claude/settings.json
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/settings.local.json $HOME/.claude/settings.local.json
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/statusline-command.sh $HOME/.claude/statusline-command.sh
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/hooks $HOME/.claude/hooks
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/hud $HOME/.claude/hud
zf_ln -sfn $SCRIPT_DIR/configs/claude-code/skills $HOME/.claude/skills
# Codex CLI + OMX
zf_ln -sfn $SCRIPT_DIR/configs/codex/config.toml $HOME/.codex/config.toml
zf_ln -sfn $SCRIPT_DIR/configs/codex/AGENTS.md $HOME/.codex/AGENTS.md
zf_ln -sfn $SCRIPT_DIR/configs/codex/agents $HOME/.codex/agents
zf_ln -sfn $SCRIPT_DIR/configs/codex/prompts $HOME/.codex/prompts
zf_ln -sfn $SCRIPT_DIR/configs/codex/rules $HOME/.codex/rules
zf_ln -sfn $SCRIPT_DIR/configs/codex/skills $HOME/.codex/skills
# OpenCode
zf_ln -sfn $SCRIPT_DIR/configs/opencode/opencode.json $XDG_CONFIG_HOME/opencode/opencode.json
zf_ln -sfn $SCRIPT_DIR/configs/opencode/oh-my-openagent.json $XDG_CONFIG_HOME/opencode/oh-my-openagent.json
# OMX standalone agents
zf_ln -sfn $SCRIPT_DIR/configs/omx/agents $HOME/.omx/agents
# Portless
zf_ln -sfn $SCRIPT_DIR/configs/portless $HOME/.portless
for _ssh_file in $SCRIPT_DIR/ssh/*~$SCRIPT_DIR/ssh/*.enc(N.); do
    zf_ln -sfn $_ssh_file $HOME/.ssh/${_ssh_file:t}
done
print "  ...done"

# Make sure submodules are installed
print "Syncing submodules..."
git submodule sync > /dev/null
git submodule update --init --recursive > /dev/null
git submodule foreach --recursive git clean -ffd
print "  ...done"

print "Compiling zsh plugins..."
autoload -Uz zrecompile
for zsh_plugin_file in $SCRIPT_DIR/zsh/plugins/**/*.zsh{-theme,}(#q.); do
    zrecompile -pq $zsh_plugin_file
done
print "  ...done"

if (( ${+commands[make]} )); then
    # Make install git-extras
    print "Installing git-extras..."
    pushd tools/git-extras
    PREFIX=$HOME/.local make install > /dev/null
    popd
    print "  ...done"

    if (( ${+commands[which]} )); then
        print "Installing git-quick-stats..."
        pushd tools/git-quick-stats
        PREFIX=$HOME/.local make install > /dev/null
        popd
        print "  ...done"
    fi
fi

print "Installing fzf..."
pushd tools/fzf
if fzf_install_output=$(./install --bin); then
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/bin/fzf $HOME/.local/bin/fzf
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/bin/fzf-tmux $HOME/.local/bin/fzf-tmux
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/man/man1/fzf.1 $XDG_DATA_HOME/man/man1/fzf.1
    zf_ln -sfn $SCRIPT_DIR/tools/fzf/man/man1/fzf-tmux.1 $XDG_DATA_HOME/man/man1/fzf-tmux.1
    print "  ...done"
else
    print $fzf_install_output
    print "  ...error detected, ignoring, please check the fzf installation guide"
fi
popd

if (( ${+commands[perl]} )); then
    # Install diff-so-fancy
    print "Installing diff-so-fancy..."
    zf_ln -sfn $SCRIPT_DIR/tools/diff-so-fancy/diff-so-fancy $HOME/.local/bin/diff-so-fancy
    print "  ...done"
fi

# Install wtp if not present
if (( ! ${+commands[wtp]} )); then
    $SCRIPT_DIR/scripts/install-wtp.zsh || true
fi

if (( ! ${+commands[gh]} )); then
    print "Installing gh (GitHub CLI)..."
    local gh_arch=$DOTFILES_ARCH
    local gh_os=$DOTFILES_OS
    if [[ $gh_os == Linux && ($gh_arch == x86_64 || $gh_arch == aarch64) ]]; then
        [[ $gh_arch == x86_64 ]] && gh_arch=amd64
        [[ $gh_arch == aarch64 ]] && gh_arch=arm64
        local gh_version
        gh_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest | sed 's|.*/tag/v||')
        if [[ -n $gh_version ]]; then
            local gh_tmp=$(mktemp -d)
            local gh_os_lower=${gh_os:l}
            if curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_${gh_os_lower}_${gh_arch}.tar.gz" | tar xz -C $gh_tmp; then
                zf_mv $gh_tmp/gh_${gh_version}_${gh_os_lower}_${gh_arch}/bin/gh $HOME/.local/bin/gh
                chmod +x $HOME/.local/bin/gh
                print "  ...done"
            else
                print "  ...failed to download gh, skipping"
            fi
            rm -rf $gh_tmp
        else
            print "  ...failed to determine latest gh version, skipping"
        fi
    elif [[ $gh_os == Darwin && ($gh_arch == x86_64 || $gh_arch == arm64) ]]; then
        if ensure_homebrew_path 2>/dev/null; then
            brew_install_or_upgrade gh gh || true
        fi
        if (( ! ${+commands[gh]} )); then
            local gh_dl_arch=$gh_arch
            [[ $gh_dl_arch == x86_64 ]] && gh_dl_arch=amd64
            local gh_version
            gh_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest | sed 's|.*/tag/v||')
            if [[ -n $gh_version ]] && (( ${+commands[unzip]} )); then
                local gh_tmp=$(mktemp -d)
                if curl -fsSL "https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_macOS_${gh_dl_arch}.zip" -o $gh_tmp/gh.zip \
                    && unzip -q $gh_tmp/gh.zip -d $gh_tmp; then
                    zf_mv $gh_tmp/gh_${gh_version}_macOS_${gh_dl_arch}/bin/gh $HOME/.local/bin/gh
                    chmod +x $HOME/.local/bin/gh
                    print "  ...done (direct download)"
                else
                    print "  ...failed to download gh, try: brew install gh"
                fi
                rm -rf $gh_tmp
            else
                print "  ...need unzip + network, try: brew install gh"
            fi
        fi
    else
        print "  ...unsupported platform for gh auto-install, skipping"
    fi
fi

if (( ${+commands[gh]} )); then
    gh extension list 2>/dev/null | grep -q chmouel/gh-prreview \
        || gh extension install chmouel/gh-prreview 2>/dev/null \
        || true
fi

if (( ! ${+commands[glab]} )); then
    print "Installing glab..."
    local glab_arch=$DOTFILES_ARCH
    local glab_os=$DOTFILES_OS
    if [[ $glab_os == Linux && ($glab_arch == x86_64 || $glab_arch == aarch64) ]]; then
        [[ $glab_arch == aarch64 ]] && glab_arch=arm64
        [[ $glab_arch == x86_64 ]] && glab_arch=amd64
        local glab_version
        glab_version=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['tag_name'].lstrip('v'))" 2>/dev/null)
        if [[ -n $glab_version ]]; then
            local glab_tmp=$(mktemp -d)
            local glab_os_lower=${glab_os:l}
            if curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${glab_version}/downloads/glab_${glab_version}_${glab_os_lower}_${glab_arch}.tar.gz" | tar xz -C $glab_tmp; then
                zf_mv $glab_tmp/bin/glab $HOME/.local/bin/glab
                chmod +x $HOME/.local/bin/glab
                print "  ...done"
            else
                print "  ...failed to download glab, skipping"
            fi
            rm -rf $glab_tmp
        else
            print "  ...failed to determine latest glab version, skipping"
        fi
    elif [[ $glab_os == Darwin && ($glab_arch == x86_64 || $glab_arch == arm64) ]]; then
        if ensure_homebrew_path 2>/dev/null; then
            brew_install_or_upgrade glab glab || true
        fi
        if (( ! ${+commands[glab]} )); then
            local glab_dl_arch=$glab_arch
            [[ $glab_dl_arch == x86_64 ]] && glab_dl_arch=amd64
            local glab_version
            glab_version=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases" | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['tag_name'].lstrip('v'))" 2>/dev/null)
            if [[ -n $glab_version ]]; then
                local glab_tmp=$(mktemp -d)
                if curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${glab_version}/downloads/glab_${glab_version}_darwin_${glab_dl_arch}.tar.gz" | tar xz -C $glab_tmp; then
                    zf_mv $glab_tmp/bin/glab $HOME/.local/bin/glab
                    chmod +x $HOME/.local/bin/glab
                    print "  ...done (direct download)"
                else
                    print "  ...failed to download glab, try: brew install glab"
                fi
                rm -rf $glab_tmp
            else
                print "  ...failed to determine latest glab version, try: brew install glab"
            fi
        fi
    else
        print "  ...unsupported platform for glab auto-install, skipping"
    fi
fi

# Install AWS CLI v2 if not present
if (( ! ${+commands[aws]} )); then
    print "Installing AWS CLI v2..."
    local aws_arch=$DOTFILES_ARCH
    local aws_os=$DOTFILES_OS
    if [[ $aws_os == Darwin ]]; then
        if ensure_homebrew_path 2>/dev/null; then
            brew_install_or_upgrade awscli aws || true
        fi
        if (( ! ${+commands[aws]} )); then
            local aws_tmp=$(mktemp -d)
            if curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o $aws_tmp/AWSCLIV2.pkg; then
                print "  ...downloaded AWSCLIV2.pkg; installing requires sudo"
                if sudo installer -pkg $aws_tmp/AWSCLIV2.pkg -target / > /dev/null 2>&1; then
                    print "  ...done (pkg installer)"
                else
                    print "  ...sudo installer failed; install manually: sudo installer -pkg $aws_tmp/AWSCLIV2.pkg -target / (or: brew install awscli)"
                fi
            else
                print "  ...failed to download AWSCLIV2.pkg, try: brew install awscli"
            fi
            rm -rf $aws_tmp
        fi
    elif [[ $aws_os != Linux || ($aws_arch != x86_64 && $aws_arch != aarch64) ]]; then
        print "  ...unsupported platform for AWS CLI auto-install, skipping"
    elif (( ! ${+commands[unzip]} )); then
        print "  ...unzip not available, skipping (install via build-deps)"
    else
        local aws_tmp=$(mktemp -d)
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o $aws_tmp/awscliv2.zip \
            && unzip -q $aws_tmp/awscliv2.zip -d $aws_tmp \
            && $aws_tmp/aws/install -i $HOME/.local/aws-cli -b $HOME/.local/bin > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...failed to install AWS CLI, skipping"
        fi
        rm -rf $aws_tmp
    fi
elif $upgrade_mode; then
    print "Upgrading AWS CLI v2..."
    local aws_arch=$DOTFILES_ARCH
    if [[ $DOTFILES_OS == Darwin ]]; then
        if ensure_homebrew_path 2>/dev/null; then
            brew_install_or_upgrade awscli aws || true
        else
            local aws_tmp=$(mktemp -d)
            if curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o $aws_tmp/AWSCLIV2.pkg \
                && sudo installer -pkg $aws_tmp/AWSCLIV2.pkg -target / > /dev/null 2>&1; then
                print "  ...done (pkg installer)"
            else
                print "  ...AWS CLI upgrade failed"
            fi
            rm -rf $aws_tmp
        fi
    elif [[ $DOTFILES_OS == Linux && ($aws_arch == x86_64 || $aws_arch == aarch64) ]] && (( ${+commands[unzip]} )); then
        local aws_tmp=$(mktemp -d)
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o $aws_tmp/awscliv2.zip \
            && unzip -q $aws_tmp/awscliv2.zip -d $aws_tmp \
            && $aws_tmp/aws/install --update -i $HOME/.local/aws-cli -b $HOME/.local/bin > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...AWS CLI upgrade failed"
        fi
        rm -rf $aws_tmp
    fi
fi

# Install moor (modern terminal pager) if not present
if (( ! ${+commands[moor]} )); then
    print "Installing moor..."
    if bash $SCRIPT_DIR/scripts/install-moor.sh > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install moor, skipping"
    fi
fi

if (( ! ${+commands[mise]} )); then
    print "Installing mise..."
    local mise_arch=$DOTFILES_ARCH
    local mise_os=${DOTFILES_OS:l}
    if [[ $mise_os == linux && ($mise_arch == x86_64 || $mise_arch == aarch64) ]]; then
        [[ $mise_arch == x86_64 ]] && mise_arch=x64
        [[ $mise_arch == aarch64 ]] && mise_arch=arm64
        local mise_version
        mise_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/jdx/mise/releases/latest | sed 's|.*/tag/v||')
        if [[ -n $mise_version ]]; then
            if curl -fsSL "https://github.com/jdx/mise/releases/download/v${mise_version}/mise-v${mise_version}-${mise_os}-${mise_arch}" -o $HOME/.local/bin/mise; then
                chmod +x $HOME/.local/bin/mise
                export PATH=$HOME/.local/bin:$PATH
                print "  ...done"
            else
                print "  ...failed to download mise, skipping"
            fi
        else
            print "  ...failed to determine latest mise version, skipping"
        fi
    elif [[ $mise_os == darwin && ($mise_arch == x86_64 || $mise_arch == arm64) ]]; then
        if ensure_homebrew_path 2>/dev/null; then
            brew_install_or_upgrade mise mise || true
        fi
        if (( ! ${+commands[mise]} )); then
            local mise_dl_arch=$mise_arch
            [[ $mise_dl_arch == x86_64 ]] && mise_dl_arch=x64
            local mise_version
            mise_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/jdx/mise/releases/latest | sed 's|.*/tag/v||')
            if [[ -n $mise_version ]]; then
                if curl -fsSL "https://github.com/jdx/mise/releases/download/v${mise_version}/mise-v${mise_version}-macos-${mise_dl_arch}" -o $HOME/.local/bin/mise; then
                    chmod +x $HOME/.local/bin/mise
                    export PATH=$HOME/.local/bin:$PATH
                    print "  ...done (direct download)"
                else
                    print "  ...failed to download mise, try: brew install mise"
                fi
            else
                print "  ...failed to determine latest mise version, try: brew install mise"
            fi
        else
            export PATH=$HOME/.local/bin:$PATH
        fi
    else
        print "  ...unsupported platform for mise auto-install, skipping"
    fi
fi

if (( ${+commands[mise]} )); then
    if $upgrade_mode; then
        print "Upgrading mise..."
        if mise self-update --yes --no-plugins > /dev/null 2>&1; then
            print "  ...done"
        else
            print "  ...mise self-update had issues"
        fi
    fi

    print "Installing mise tools (node, bun, ruby, etc.)..."
    if mise install > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...mise install had issues"
    fi

    print "Upgrading mise tools..."
    if mise upgrade --yes > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...mise upgrade had issues"
    fi
fi

# Install hook to call deploy script after successful pull
print "Installing git hooks..."
zf_mkdir -p .git/hooks
zf_ln -sfn ../../deploy.zsh .git/hooks/post-merge
zf_ln -sfn ../../deploy.zsh .git/hooks/post-checkout
zf_ln -sfn ../../scripts/pre-commit .git/hooks/pre-commit
print "  ...done"

# Ensure age key exists for secrets encryption
local age_key_dir=$XDG_CONFIG_HOME/sops/age
local age_public_key
if [[ ! -f $age_key_dir/keys.txt ]]; then
    if (( ${+commands[age-keygen]} )); then
        print "Generating age key for secrets..."
        zf_mkdir -p $age_key_dir
        age-keygen -o $age_key_dir/keys.txt 2>/dev/null
        chmod 600 $age_key_dir/keys.txt
        print "  ...done"
        print "  IMPORTANT: Back up $age_key_dir/keys.txt to your password manager!"
    else
        print ""
        print "WARNING: age key not found and age-keygen not available."
        print "  Encrypted secrets (zsh/env.d/90_secrets.zsh etc.) cannot be decrypted."
        print ""
        print "  To restore secrets on this machine, either:"
        print "    1. Copy your existing keys.txt from your password manager to:"
        print "         $age_key_dir/keys.txt"
        print "    2. Or install age (mise install) and re-run deploy.zsh to generate a new key."
        print "       (A new key cannot decrypt existing .enc files — you must re-encrypt them.)"
        print ""
    fi
fi

# Verify this machine's age public key is registered in the committed .sops.yaml.
# .sops.yaml is the source of truth for which keys can decrypt; deploy.zsh never
# rewrites it. If this machine isn't registered, print actionable instructions.
if [[ -f $age_key_dir/keys.txt ]] && (( ${+commands[age-keygen]} )); then
    age_public_key=$(age-keygen -y $age_key_dir/keys.txt 2>/dev/null)
    if [[ -n $age_public_key ]]; then
        if [[ ! -f $SCRIPT_DIR/.sops.yaml ]]; then
            print ""
            print "WARNING: .sops.yaml not found in repo root."
            print "  This machine's age public key:"
            print "    $age_public_key"
            print "  Add it to .sops.yaml on a registered machine and re-encrypt secrets."
            print ""
        elif ! grep -Fq "$age_public_key" $SCRIPT_DIR/.sops.yaml; then
            print ""
            print "WARNING: this machine's age key is not registered for sops decryption."
            print "  Encrypted secrets (zsh/env.d/9*.zsh.enc, ssh/*.enc, configs/portless/*.pem.enc) cannot be read."
            print ""
            print "  This machine's public key:"
            print "    $age_public_key"
            print ""
            print "  To register, on an already-registered machine run:"
            print "    scripts/sops-add-recipient.zsh $age_public_key"
            print "  then commit and push. Pull here to pick up the re-encrypted secrets."
            print ""
        fi
    fi
fi

# Decrypt encrypted dotfiles into their ignored plaintext locations.
if (( ${+commands[sops]} )) && [[ -f $age_key_dir/keys.txt ]]; then
    print "Restoring ssh files..."
    local _ssh_enc _ssh_target _ssh_tmp
    for _ssh_enc in $SCRIPT_DIR/ssh/*.enc(N); do
        _ssh_target=$SCRIPT_DIR/ssh/${${_ssh_enc:t}%.enc}
        _ssh_tmp=$(mktemp)
        if sops --decrypt $_ssh_enc > $_ssh_tmp 2>/dev/null; then
            if [[ $_ssh_target == *.pub ]]; then
                chmod 644 $_ssh_tmp
            else
                chmod 600 $_ssh_tmp
            fi
            mv $_ssh_tmp $_ssh_target
            zf_ln -sfn $_ssh_target $HOME/.ssh/${_ssh_target:t}
        else
            rm -f $_ssh_tmp
            print "  WARNING: failed to decrypt ${_ssh_enc:t}"
        fi
    done
    print "  ...done"

    print "Restoring portless certs..."
    local _pless_enc _pless_target _pless_tmp
    for _pless_enc in $SCRIPT_DIR/configs/portless/*.pem.enc(N); do
        _pless_target=$SCRIPT_DIR/configs/portless/${${_pless_enc:t}%.enc}
        _pless_tmp=$(mktemp)
        if sops --decrypt $_pless_enc > $_pless_tmp 2>/dev/null; then
            chmod 600 $_pless_tmp
            mv $_pless_tmp $_pless_target
        else
            rm -f $_pless_tmp
            print "  WARNING: failed to decrypt ${_pless_enc:t}"
        fi
    done
    print "  ...done"
fi

# Install LiteLLM proxy via uv tool
if (( ${+commands[uv]} )) && (( ! ${+commands[litellm]} )); then
    print "Installing litellm proxy..."
    if uv tool install 'litellm[proxy]' > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install litellm, skipping"
    fi
elif (( ${+commands[uv]} )) && $upgrade_mode; then
    print "Upgrading litellm proxy..."
    if uv tool upgrade litellm > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...litellm already at latest or upgrade failed"
    fi
fi

# Reload systemd to pick up litellm-proxy.service
if (( ${+commands[systemctl]} )); then
    systemctl --user daemon-reload 2>/dev/null
fi

# Install Claude Code via official installer
if (( ! ${+commands[claude]} )); then
    print "Installing Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install Claude Code"
    fi
fi

# Install vite-plus (vp) if not present
if (( ! ${+commands[vp]} )); then
    print "Installing vite-plus..."
    if curl -fsSL https://vite.plus | bash > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install vite-plus"
    fi
fi

# Install rustup/cargo if not present
if (( ! ${+commands[cargo]} )); then
    print "Installing rustup and cargo..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path > /dev/null 2>&1; then
        export PATH=$HOME/.cargo/bin:$PATH
        print "  ...done"
    else
        print "  ...failed to install rustup, skipping"
    fi
fi

# Install/upgrade Rust CLI tools if cargo is available
if (( ${+commands[cargo]} )); then
    local -a rust_tools=(git-delta bat eza fd-find sd zoxide tree-sitter-cli)
    for tool_pkg in $rust_tools[@]; do
        # Map package name to binary name
        local tool_bin=$tool_pkg
        case $tool_pkg in
            git-delta) tool_bin=delta ;;
            fd-find) tool_bin=fd ;;
            tree-sitter-cli) tool_bin=tree-sitter ;;
        esac
        if (( ! ${+commands[$tool_bin]} )); then
            print "Installing $tool_pkg via cargo..."
            if cargo install $tool_pkg > /dev/null 2>&1; then
                print "  ...done"
            else
                print "  ...failed to install $tool_pkg"
            fi
        elif $upgrade_mode; then
            print "Upgrading $tool_pkg via cargo..."
            if cargo install $tool_pkg --force > /dev/null 2>&1; then
                print "  ...done"
            else
                print "  ...failed to upgrade $tool_pkg"
            fi
        fi
    done
fi

# Update/upgrade Homebrew packages if brew is available (upgrade mode only)
if (( ${+commands[brew]} )) && $upgrade_mode; then
    print "Updating Homebrew..."
    if brew update > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...brew update failed"
    fi
    print "Upgrading Homebrew packages..."
    if brew upgrade > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...brew upgrade had issues (may be normal if no updates)"
    fi
fi

# Install engram via brew if not present
if (( ${+commands[brew]} )) && (( ! ${+commands[engram]} )); then
    print "Installing engram via brew..."
    if brew install gentleman-programming/tap/engram > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...failed to install engram"
    fi
elif (( ${+commands[brew]} )) && $upgrade_mode; then
    print "Upgrading engram via brew..."
    if brew upgrade gentleman-programming/tap/engram > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...engram already at latest or upgrade failed"
    fi
fi

if (( ${+commands[vim]} )); then
    # Generate vim help tags
    print "Generating vim helptags..."
    command vim --not-a-term -i "NONE" -c "helptags ALL" -c "qall" &> /dev/null
    print "  ...done"
fi

if (( ${+commands[nvim]} )); then
    # Generate nvim help tags
    print "Generating nvim helptags..."
    command nvim --headless -c "helptags ALL" -c "qall" &> /dev/null
    print "  ...done"
    # Update treesitter config
    print "Updating tree-sitter parsers..."
    command nvim --headless -c "TSUpdate" -c "qall" &> /dev/null
    print "  ...done"
    # Update mason registries
    print "Updating mason registries..."
    command nvim --headless -c "MasonUpdate" -c "qall" &> /dev/null
    print "  ...done"
fi

# For each env-wrapper link its plugins
print "Linking env-wrappers' plugins..."
    for env_wrapper in $SCRIPT_DIR/env-wrappers/*; do
        # 'plugin' here is a directory with name which doesn't match env-wrapper's name
        for env_wrapper_plugin in $env_wrapper/^${env_wrapper:t}$*(#qN/); do
            zf_ln -sfn $env_wrapper_plugin $XDG_DATA_HOME/${env_wrapper:t}/plugins/${env_wrapper_plugin:t}
        done
    done
    zf_ln -sfn $SCRIPT_DIR/env-wrappers/goenv/goenv/plugins/go-build $XDG_DATA_HOME/goenv/plugins/go-build
    zf_ln -sfn $SCRIPT_DIR/env-wrappers/jenv/jenv/available-plugins/export $XDG_DATA_HOME/jenv/plugins/export
    zf_ln -sfn $SCRIPT_DIR/env-wrappers/pyenv/default-packages $XDG_DATA_HOME/pyenv/default-packages
print "  ...done"

# Trigger zsh run with powerlevel10k prompt to download gitstatusd
print "Downloading gitstatusd for powerlevel10k..."
zsh -is <<< '' &> /dev/null || true
print "  ...done"

# Install task to pull updates every midnight
print "Installing periodic update task..."
if (( ${+commands[systemctl]} )); then
    print "  ...systemd detected, installing timer for periodic updates..."

    if (( EUID == 0 )); then
        systemd_unit_dir=/etc/systemd/system
        systemctl_cmd=(systemctl)
        print "  ...running as root, installing system-wide timer..."
    else
        systemd_unit_dir=$XDG_CONFIG_HOME/systemd/user
        systemctl_cmd=(systemctl --user)
        print "  ...running as regular user, installing user timer..."
    fi
    zf_mkdir -p $systemd_unit_dir

    service_name=pull-dotfiles.service
    service_content="[Unit]
Description=Pull dotfiles update
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/git -c user.name=systemd.update -c user.email=systemd@localhost pull --force
WorkingDirectory=$SCRIPT_DIR"
    print -r -- $service_content > $systemd_unit_dir/$service_name

    timer_name=pull-dotfiles.timer
    timer_content="[Unit]
Description=Pull dotfiles update daily

[Timer]
OnCalendar=daily
RandomizedDelaySec=120s
Persistent=true

[Install]
WantedBy=timers.target"
    print -r -- $timer_content > $systemd_unit_dir/$timer_name

    if ${systemctl_cmd[@]} daemon-reload > /dev/null && ${systemctl_cmd[@]} enable --now $timer_name > /dev/null; then
       print "  ...done"
    else
       print "Failed to install systemd timer. Check permissions and systemd setup"
    fi
elif [[ $DOTFILES_OS == Darwin ]] && (( ${+commands[launchctl]} )) && (( EUID != 0 )); then
    print "  ...launchd detected, installing user LaunchAgent..."

    local launchd_dir=$HOME/Library/LaunchAgents
    local launchd_label=com.ctaylor.dotfiles.pull
    local launchd_plist=$launchd_dir/$launchd_label.plist
    zf_mkdir -p $launchd_dir

    local launchd_command="cd ${(q)SCRIPT_DIR} && git -c user.name=launchd.update -c user.email=launchd@localhost pull --force"
    local launchd_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>$launchd_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-lc</string>
        <string>$launchd_command</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>0</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$XDG_STATE_HOME/dotfiles-pull.log</string>
    <key>StandardErrorPath</key>
    <string>$XDG_STATE_HOME/dotfiles-pull.err</string>
</dict>
</plist>"
    print -r -- $launchd_content > $launchd_plist

    launchctl bootout gui/$EUID $launchd_plist > /dev/null 2>&1 || true
    if launchctl bootstrap gui/$EUID $launchd_plist > /dev/null 2>&1 \
        && launchctl enable gui/$EUID/$launchd_label > /dev/null 2>&1; then
       print "  ...done"
    else
       print "Failed to install launchd task. Check $launchd_plist"
    fi
elif (( ${+commands[crontab]} )); then
    print "  ...cron detected, installing job for periodic updates..."
    cron_task="cd $SCRIPT_DIR && git -c user.name=cron.update -c user.email=cron@localhost pull --force"
    cron_schedule="0 0 * * * $cron_task"
    if cat <(grep --ignore-case --invert-match --fixed-strings $cron_task <(crontab -l)) <(echo $cron_schedule) | crontab -; then
        print "  ...done"
    else
        print "Please add \`cd $SCRIPT_DIR && git pull\` to your crontab or just ignore this, you can always update dotfiles manually"
    fi
else
    print "  ...no systemd or cron detected, skipping"
fi
