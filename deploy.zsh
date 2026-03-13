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

# Create required directories
print "Creating required directory tree..."
zf_mkdir -p $XDG_CONFIG_HOME/{ghostty,git/local,htop,ranger,gem,tig,gnupg,nvim/{plugin,after},yazi}
zf_mkdir -p $XDG_CACHE_HOME/{vim/{backup,swap,undo},zsh,tig}
zf_mkdir -p $XDG_DATA_HOME/{{goenv,jenv,luaenv,nodenv,phpenv,plenv,pyenv,rbenv}/plugins,zsh,man/man1,vim/spell,nvim/site/pack/plugins}
zf_mkdir -p $XDG_CONFIG_HOME/mise
zf_mkdir -p $XDG_STATE_HOME
zf_mkdir -p $HOME/.local/{bin,etc}
zf_chmod 700 $XDG_CONFIG_HOME/gnupg
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
zf_ln -sfn $SCRIPT_DIR/configs/gtk-3.0-bookmarks $XDG_CONFIG_HOME/gtk-3.0/bookmarks
zf_ln -sfn $SCRIPT_DIR/yazi/init.lua $XDG_CONFIG_HOME/yazi/init.lua
zf_ln -sfn $SCRIPT_DIR/yazi/keymap.toml $XDG_CONFIG_HOME/yazi/keymap.toml
zf_ln -sfn $SCRIPT_DIR/yazi/theme.toml $XDG_CONFIG_HOME/yazi/theme.toml
zf_ln -sfn $SCRIPT_DIR/yazi/yazi.toml $XDG_CONFIG_HOME/yazi/yazi.toml
zf_ln -sfn $SCRIPT_DIR/yazi/plugins $XDG_CONFIG_HOME/yazi/plugins
zf_ln -sfn $SCRIPT_DIR/gpg/gpg.conf $XDG_CONFIG_HOME/gnupg/gpg.conf
zf_ln -sfn $SCRIPT_DIR/gpg/gpg-agent.conf $XDG_CONFIG_HOME/gnupg/gpg-agent.conf
zf_ln -sfn $SCRIPT_DIR/tools/git-diff-pager $HOME/.local/bin/git-diff-pager
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

# Install hook to call deploy script after successful pull
print "Installing git hooks..."
zf_mkdir -p .git/hooks
zf_ln -sfn ../../deploy.zsh .git/hooks/post-merge
zf_ln -sfn ../../deploy.zsh .git/hooks/post-checkout
zf_ln -sfn $SCRIPT_DIR/scripts/pre-commit .git/hooks/pre-commit
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
    print "Installing wtp..."
    local wtp_arch=$(uname -m)
    local wtp_os=$(uname -s)
    if [[ $wtp_os == Linux && ($wtp_arch == x86_64 || $wtp_arch == aarch64) ]]; then
        [[ $wtp_arch == aarch64 ]] && wtp_arch=arm64
        local wtp_tmp=$(mktemp -d)
        if curl -fsSL "https://github.com/satococoa/wtp/releases/latest/download/wtp_${wtp_os}_${wtp_arch}.tar.gz" | tar xz -C $wtp_tmp; then
            zf_mv $wtp_tmp/wtp $HOME/.local/bin/wtp
            chmod +x $HOME/.local/bin/wtp
            print "  ...done"
        else
            print "  ...failed to download wtp, skipping"
        fi
        rm -rf $wtp_tmp
    else
        print "  ...unsupported platform for wtp auto-install, skipping"
    fi
fi

if (( ! ${+commands[glab]} )); then
    print "Installing glab..."
    local glab_arch=$(uname -m)
    local glab_os=$(uname -s)
    if [[ $glab_os == Linux && ($glab_arch == x86_64 || $glab_arch == aarch64) ]]; then
        [[ $glab_arch == aarch64 ]] && glab_arch=arm64
        local glab_version
        glab_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/gitlab-org/cli/releases/latest | sed 's|.*/tag/v||')
        if [[ -n $glab_version ]]; then
            local glab_tmp=$(mktemp -d)
            if curl -fsSL "https://github.com/gitlab-org/cli/releases/download/v${glab_version}/glab_${glab_version}_${glab_os}_${glab_arch}.tar.gz" | tar xz -C $glab_tmp; then
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
    else
        print "  ...unsupported platform for glab auto-install, skipping"
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
    local mise_arch=$(uname -m)
    local mise_os=$(uname -s | tr '[:upper:]' '[:lower:]')
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
    else
        print "  ...unsupported platform for mise auto-install, skipping"
    fi
fi

if (( ${+commands[mise]} )); then
    print "Installing mise tools (node, bun, ruby, etc.)..."
    mise install > /dev/null 2>&1
    if $upgrade_mode && mise upgrade > /dev/null 2>&1; then
        print "  ...done"
    else
        print "  ...done (run with --upgrade to also upgrade existing tools)"
    fi
fi

# Ensure age key exists for secrets encryption/decryption
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
    fi
fi

# Configure .sops.yaml with age public key
if [[ -f $age_key_dir/keys.txt ]] && (( ${+commands[age-keygen]} )); then
    age_public_key=$(age-keygen -y $age_key_dir/keys.txt 2>/dev/null)
    if [[ -n $age_public_key ]]; then
        print "Configuring .sops.yaml..."
        cat > $SCRIPT_DIR/.sops.yaml << EOF
creation_rules:
  - path_regex: \.enc$
    age: $age_public_key
EOF
        print "  ...done"
    fi
fi

# Decrypt secrets — find all .enc files in gitignored ranges and decrypt
if (( ${+commands[sops]} )); then
    # Safety check: warn if plaintext is newer than .enc (uncommitted changes)
    local has_uncommitted_secrets=false
    local enc_file plaintext
    for enc_file in {zsh/env.d,zsh/rc.d,nvim/init}/9[0-9]_*.enc(N); do
        plaintext=${enc_file%.enc}
        if [[ -f $plaintext && $plaintext -nt $enc_file ]]; then
            has_uncommitted_secrets=true
            print "WARNING: $plaintext has uncommitted changes (newer than .enc)"
        fi
    done

    if $has_uncommitted_secrets; then
        print ""
        print "ERROR: Uncommitted secret changes detected!"
        print "  Your plaintext changes would be overwritten by decryption."
        print ""
        print "To fix:"
        print "  1. Commit your changes: git commit -am 'update secrets'"
        print "     (pre-commit hook will encrypt them automatically)"
        print "  2. Or discard changes: rm zsh/*/9[0-9]_* nvim/init/9[0-9]_*"
        print "  3. Then re-run: ./deploy.zsh"
        print ""
        exit 1
    fi

    for enc_file in {zsh/env.d,zsh/rc.d,nvim/init}/9[0-9]_*.enc(N); do
        local target=${enc_file%.enc}
        if [[ ! -f $target || $enc_file -nt $target ]]; then
            print "Decrypting ${enc_file}..."
            local temp_file=$(mktemp)
            if sops --decrypt $enc_file > $temp_file 2>/dev/null; then
                chmod 600 $temp_file
                # Only update if content differs (preserves mtime if identical)
                if [[ ! -f $target ]] || ! cmp -s $temp_file $target; then
                    mv $temp_file $target
                else
                    rm $temp_file
                    # Touch target to match .enc mtime
                    touch -r $enc_file $target
                fi
                print "  ...done"
            else
                rm -f $temp_file
                print "  ...failed to decrypt $enc_file (missing age key?)"
            fi
        fi
    done
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
    local -a rust_tools=(git-delta bat eza fd-find zoxide)
    for tool_pkg in $rust_tools[@]; do
        # Map package name to binary name
        local tool_bin=$tool_pkg
        case $tool_pkg in
            git-delta) tool_bin=delta ;;
            fd-find) tool_bin=fd ;;
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
zsh -is <<< '' &> /dev/null
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
ExecStart=/usr/bin/git -c user.name=systemd.update -c user.email=systemd@localhost pull
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
elif (( ${+commands[crontab]} )); then
    print "  ...cron detected, installing job for periodic updates..."
    cron_task="cd $SCRIPT_DIR && git -c user.name=cron.update -c user.email=cron@localhost pull"
    cron_schedule="0 0 * * * $cron_task"
    if cat <(grep --ignore-case --invert-match --fixed-strings $cron_task <(crontab -l)) <(echo $cron_schedule) | crontab -; then
        print "  ...done"
    else
        print "Please add \`cd $SCRIPT_DIR && git pull\` to your crontab or just ignore this, you can always update dotfiles manually"
    fi
else
    print "  ...no systemd or cron detected, skipping"
fi
