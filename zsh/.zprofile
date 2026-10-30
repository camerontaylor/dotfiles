# Taken from Arch, most of default zsh configurations don't do this
# Skip it on macOS to disallow path_helper run
if [[ -r /etc/profile && $OSTYPE != darwin* ]]; then
    emulate sh -c 'source /etc/profile'
fi

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
