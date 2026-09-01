# bash-completion — the system/brew script that defines the completion
# loaders. Order: brew prefix (HOMEBREW_PREFIX when shellenv ran, else the
# two stock prefixes), then the Linux distro path.
_bash_completion=
for _bc in \
    "${HOMEBREW_PREFIX:-/usr/local}/etc/profile.d/bash_completion.sh" \
    /opt/homebrew/etc/profile.d/bash_completion.sh \
    /usr/local/etc/profile.d/bash_completion.sh \
    /usr/share/bash-completion/bash_completion
do
    if [ -r "$_bc" ]; then
        _bash_completion=$_bc
        break
    fi
done
if [ -n "$_bash_completion" ]; then
    . "$_bash_completion"
fi
unset _bash_completion _bc
