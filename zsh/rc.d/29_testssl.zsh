# testssl is installed via the system package manager (brew on macOS, pacman on
# Linux) now that the 140M submodule is gone. brew names the binary `testssl`;
# Arch's package names it `testssl.sh`. Normalise to a `testssl` command.
if (( ! ${+commands[testssl]} )) && (( ${+commands[testssl.sh]} )); then
    alias testssl=testssl.sh
fi
