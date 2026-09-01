# Shell options — zsh/rc.d/02_setopt.zsh mapped to bash per
# docs/bash-compatibility.md §C. Rows with no bash equivalent are dropped,
# not approximated: HIST_REDUCE_BLANKS, CORRECT, HASH_LIST_ALL,
# LONG_LIST_JOBS, AUTO_RESUME, SHORT_LOOPS (zsh syntax lenience),
# RM_STAR_SILENT, RM_STAR_WAIT, PROMPT_EOL_MARK (prompt-level).
# Native-in-bash already (no action needed): MULTIOS, BRACE_CCL, NOMATCH
# (unsetopt → literal-pass is bash's default), COMPLETE_IN_WORD,
# ALWAYS_TO_END, INTERACTIVE_COMMENTS (pinned below anyway).
# Completion-side options (AUTO_PARAM_SLASH, LIST_TYPES, BEEP) live in
# bash/inputrc.

set -b                          # NOTIFY — background-job status immediately
set +o noclobber                # setopt CLOBBER
shopt -s histverify             # HIST_VERIFY
shopt -s extglob                # EXTENDED_GLOB analog
shopt -s interactive_comments   # INTERACTIVE_COMMENTS — default, pinned
# autocd/globstar are bash ≥ 4.0 — the interactive layer targets brew bash
# 5.x, but /bin/bash 3.2 login shells must start clean, not with shopt
# errors (BASH_VERSINFO[0] is 3.2-safe).
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
    shopt -s autocd             # AUTO_CD
    shopt -s globstar           # ** recursive globs (bash-native bonus)
fi

# unsetopt FLOW_CONTROL — free ^S/^Q for incremental search. Needs a tty;
# silently skipped under `bash -c` and other non-terminal contexts (`if`, not
# `&&`, so a skipped check doesn't make the fragment report as failed).
if [ -t 0 ]; then
    stty -ixon 2>/dev/null
fi
