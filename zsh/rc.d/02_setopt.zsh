setopt HIST_IGNORE_ALL_DUPS # remove all earlier duplicate lines
setopt APPEND_HISTORY # history appends to existing file
setopt INC_APPEND_HISTORY # write after each command, not on exit
setopt SHARE_HISTORY # share between sessions (implies inc_append)
setopt EXTENDED_HISTORY # save each commands beginning timestamp and the duration to the history file
setopt HIST_REDUCE_BLANKS # trim multiple insignificant blanks in history
setopt HIST_IGNORE_SPACE # don’t store lines starting with space
setopt EXTENDED_GLOB # treat special characters as part of patterns
setopt CORRECT # try to correct the spelling of commands only
unsetopt FLOW_CONTROL # disable stupid annoying keys
setopt MULTIOS # allows multiple input and output redirections
setopt AUTO_CD # if the command is directory and cannot be executed, perfort cd to this directory
setopt CLOBBER # allow > redirection to truncate existing files
setopt BRACE_CCL # allow brace character class list expansion
unsetopt BEEP # do not beep on errors
unsetopt NOMATCH # try to avoid the 'zsh: no matches found...'
setopt INTERACTIVE_COMMENTS # allow use of comments in interactive code
setopt AUTO_PARAM_SLASH # complete folders with / at end
setopt LIST_TYPES # mark type of completion suggestions
setopt HASH_LIST_ALL # whenever a command completion is attempted, make sure the entire command path is hashed first
setopt COMPLETE_IN_WORD # allow completion from within a word/phrase
setopt ALWAYS_TO_END # move cursor to the end of a completed word
setopt LONG_LIST_JOBS # list jobs in the long format by default
setopt AUTO_RESUME # attempt to resume existing job before creating a new process
setopt NOTIFY # report status of background jobs immediately
unsetopt SHORT_LOOPS # disable short loop forms, can be confusing
unsetopt RM_STAR_SILENT # notify when rm is running with *
setopt RM_STAR_WAIT # wait for 10 seconds confirmation when running rm with *

# a bit fancy than default
PROMPT_EOL_MARK='%K{red} %k'
