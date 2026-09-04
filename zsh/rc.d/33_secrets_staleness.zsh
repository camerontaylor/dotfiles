# Secrets staleness sentinel — surfaces a box whose secrets stopped rendering.
#
# Since the secrets-repo migration, plaintext secrets are DERIVED: every deploy
# re-renders them from ~/.local/secrets via scripts/secrets-render.zsh. If this
# box's read access to that private repo rots (expired PAT, locked macOS
# keychain, revoked ssh key), scripts/deploy.d/65_secrets.zsh takes its
# degraded path — it mutates nothing and deploy.zsh stays green. The only
# signal is then a line in an unattended deploy log nobody reads, while the
# last-rendered plaintexts age indefinitely and can outlive a key rotation.
# This puts the signal in front of the user instead.
#
# Two portability notes, both binding (CLAUDE.md):
#   * The age test is `find -mtime +14`: POSIX, and identical on BSD and GNU.
#     Do NOT reach for `date -d` (GNU-only) or `stat -c`/`stat -f` (the flags
#     differ per OS).
#   * The message is deferred to a one-shot precmd rather than printed inline.
#     POWERLEVEL9K_INSTANT_PROMPT is `verbose` (zsh/.p10k.zsh:1704), so console
#     output during initialization would replace this line with p10k's own
#     warning banner about console output during initialization.

_secrets_staleness_check() {
    add-zsh-hook -d precmd _secrets_staleness_check

    local marker=${XDG_STATE_HOME:-$HOME/.local/state}/secrets-render-ok
    if [[ ! -e $marker ]]; then
        printf '%s\n' "secrets: never rendered on this box — run ./deploy.zsh (see scripts/deploy.d/65_secrets.zsh)" >&2
    elif [[ -n $(find "$marker" -mtime +14 -print 2>/dev/null) ]]; then
        printf '%s\n' "secrets: last rendered over 14 days ago — run ./deploy.zsh --only 65_secrets" >&2
    fi

    unfunction _secrets_staleness_check
}

add-zsh-hook precmd _secrets_staleness_check
