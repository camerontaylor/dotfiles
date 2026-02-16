<!-- Parent: ../AGENTS.md -->

# zsh

## Loading Order
`.zshenv` (all shells) -> `env.d/01-07` -> `.zshrc` (interactive) -> `rc.d/00-31,zz`

## rc.d Numbering
- `00-09` — core: tmux auto-start, prompt, options, history, autoload, keybinds
- `10-19` — tools: file managers, colors, completion, fzf, z, env managers
- `20-29` — UI plugins: cursor, aliases, autosuggestions, syntax highlighting (24-27 use `zsh-defer`)
- `30-39` — language: nvm, wtp
- `90-99` — local overrides (gitignored)
- `zz_*` — final cleanup (PATH dedup)

## Non-obvious Things
- `env.d/` runs for ALL zsh (including scripts) — no interactive commands, keep fast
- `fpath/` files: filename IS the function name, no `.zsh` extension, add `# vim: ft=zsh` at bottom
- `evalcache`/`compdefcache` cache slow init commands for 20h — invalidate by deleting `~/.cache/zsh/evalcache/`
- Plugins dir is all submodules — don't edit
