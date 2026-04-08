# zsh fzf-tab Completion Debugging

## The Insight

When zsh tab completion fails for `./path/` prefixed commands, the bug is almost certainly in the **Tab widget wrapper** (fzf-tab), NOT in zsh's completion functions (`_command_names`, `_normal`, `_autocd`). The underlying completion system and fzf-tab use different widget types (`.complete-word` vs `.expand-or-complete`) and may produce different results for the same input.

The critical mental model: zsh completion has THREE layers, and bugs can live in any of them:
1. **Completion functions** (`_command_names`, `_autocd`, `_path_files`) — generate candidates
2. **Completion widgets** (`.complete-word`, `.expand-or-complete`) — invoke the functions
3. **Widget wrappers** (fzf-tab, zsh-autocomplete) — intercept Tab and process results

Most debugging effort is wasted on layer 1 when the bug is in layer 3.

## Why This Matters

Without this insight, you will:
- Spend hours patching `_command_names` (adding IPREFIX checks, modifying conditions) when those functions work correctly
- Add debug logging to completion functions that NEVER fires (because fzf-tab bypasses them on subsequent Tabs)
- Misattribute the bug to mise removing `.` from PATH, when that's a red herring for `./` prefixed paths

## Recognition Pattern

- Tab completion works for the FIRST segment (`./scr` → `./scripts/`) but fails AFTER the slash
- `Ctrl+X ?` (`_complete_debug`) shows correct results but normal Tab does not
- Debug logging added to `_command_names` or `_normal` produces EMPTY log files
- The user has fzf-tab (or similar Tab-intercepting plugin) active

## The Approach

### Debugging Methodology (in order)

1. **Start with `_complete_debug`** — press `Ctrl+X ?` instead of Tab. This uses `.complete-word` which bypasses fzf-tab entirely. If this shows correct results, the completion system is fine and the bug is in the Tab wrapper.

2. **Check the Tab binding** — `bindkey "^I"`. If it shows `fzf-tab-complete` (not `expand-or-complete`), fzf-tab is intercepting.

3. **Verify `$_comps[-command-]`** — run `zsh -ic 'echo $_comps[-command-]'`. This shows what function handles command-position completion. Common values: `_autocd` (when `setopt autocd`), `_command_names` (default).

4. **Test without fzf-tab** — run `disable-fzf-tab`, then Tab. If it works, fzf-tab is the culprit.

5. **Read the trace** — `/tmp/zsh*` trace from `_complete_debug` shows the FULL call chain: `_normal` → `_autocd` → `_command_names` → `_alternative` → `_files`. Grep for `PREFIX`, `IPREFIX`, `executab` to find key decision points.

### Key Facts About PREFIX/IPREFIX in Command Position

- For `./scripts/` in command position: `PREFIX=./scripts/`, `IPREFIX=` (empty)
- PREFIX contains the FULL word — the splitting into IPREFIX only happens INSIDE `_path_files`
- The condition `$PREFIX = */*` in `_command_names` line 19 ALREADY matches `./scripts/`
- The IPREFIX-based fix (`$IPREFIX = ./*`) is unnecessary for this case

### fzf-tab Specifics

- fzf-tab wraps `.expand-or-complete`, not `.complete-word` — different widget behavior
- Single-match auto-insertion: when only one match exists, fzf-tab inserts without showing fzf menu
- Continuous trigger: pressing `/` inside fzf menu triggers directory descent, but normal Tab after a `/` starts a fresh `fzf-tab-complete` invocation
- The `_ftb_compcap` mechanism captures completions via a wrapped `compadd` — check if it's filtering file-type completions (`-f` flag, `disabled-on files` zstyle)
- fzf-tab's "unambiguous prefix" optimization (line ~166) can exit early without showing the full menu

## Environment Context

- This user runs: fzf-tab + mise (removes `.` from PATH) + `setopt autocd` + `setopt completeinword`
- Tab is bound to `fzf-tab-complete`, not zsh's default `expand-or-complete`
- `$_comps[-command-]` = `_autocd` (because `autocd` is set), which calls `_command_names` then `_cd`
- fpath override directory: `~/.local/dotfiles/zsh/fpath/` (position 17 in $fpath, before system at 36)
- zcompdump: `~/.local/dotfiles/zsh/.zcompdump`
- fzf-tab config: `~/.local/dotfiles/zsh/rc.d/17_fzf_tab.zsh`
