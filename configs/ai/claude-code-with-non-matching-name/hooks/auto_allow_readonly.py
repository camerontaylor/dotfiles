#!/usr/bin/env python3
"""
Auto-approve read-only tools and non-modifying bash commands.
Exit 0 with JSON = hook made a decision.
Exit 1 = no decision, fall through to normal permissions.
"""
import json
import sys
import shlex

# Tools that are always read-only
READONLY_TOOLS = {
    "Read", "Glob", "Grep", "LS", "NotebookRead",
    "TodoRead", "WebFetch", "WebSearch"
}

# Bash commands that don't modify anything
READONLY_COMMANDS = {
    "ls", "cat", "head", "tail", "less", "more",
    "grep", "rg", "ripgrep", "awk", "sed",  # sed is read-only without -i
    "find", "tree", "file", "stat", "wc",
    "sort", "uniq", "diff", "comm",
    "which", "type", "command", "whereis",
    "du", "df", "pwd", "echo", "printf",
    "readlink", "realpath", "basename", "dirname",
    "date", "whoami", "id", "env", "printenv",
    "jq", "yq", "xxd", "od", "hexdump",
    # Package info commands
    "yarn", "npm", "node", "npx",
    # Git read-only
    "git",
}

# These yarn/npm subcommands are read-only
READONLY_YARN_SUBS = {
    "list", "info", "why", "licenses", "outdated",
    "config", "audit", "policies", "workspaces",
}
READONLY_NPM_SUBS = {
    "list", "ls", "view", "info", "show", "explain",
    "outdated", "audit", "config", "fund", "query",
    "prefix", "root", "bin", "bugs", "docs", "repo",
    "search", "help",
}
READONLY_GIT_SUBS = {
    "status", "log", "diff", "show", "branch", "tag",
    "remote", "rev-parse", "ls-files", "ls-tree",
    "describe", "shortlog", "blame", "grep",
    "stash list", "config", "rev-list", "cat-file",
    "name-rev", "reflog",
}

# Bash commands that definitely modify things - deny list as safety net
DANGEROUS_PREFIXES = {"rm ", "rm\t", "rmdir ", "mv ", "cp ", "chmod ",
                      "chown ", "sudo ", "mkfs", "dd "}


def get_command_parts(cmd: str):
    """Extract the base command and first subcommand from a shell string."""
    cmd = cmd.strip()
    # Handle pipes/chains - check the first command
    for sep in ("&&", "||", ";", "|"):
        if sep in cmd:
            cmd = cmd.split(sep)[0].strip()
    try:
        parts = shlex.split(cmd)
    except (ValueError, AttributeError):
        # ValueError: unclosed quotes, AttributeError: non-string input
        parts = cmd.split()
    if not parts:
        return None, None
    base = parts[0].split("/")[-1]  # handle /usr/bin/grep -> grep
    sub = parts[1] if len(parts) > 1 else None
    return base, sub


def is_readonly_bash(command: str) -> bool:
    """Determine if a bash command is read-only."""
    if not command or not command.strip():
        return False

    # Quick dangerous check
    stripped = command.strip()
    for prefix in DANGEROUS_PREFIXES:
        if stripped.startswith(prefix):
            return False

    base, sub = get_command_parts(command)
    if base is None:
        return False

    # sed with -i is a write operation
    if base == "sed" and "-i" in command:
        return False

    # Check package managers - only allow read-only subcommands
    if base == "yarn":
        return sub in READONLY_YARN_SUBS if sub else False
    if base in ("npm", "npx"):
        if base == "npx":
            return False  # npx runs arbitrary code
        return sub in READONLY_NPM_SUBS if sub else False
    if base == "git":
        return sub in READONLY_GIT_SUBS if sub else False
    if base == "node":
        # node -e and node -p are evaluation, allow them
        # but node script.js could modify things
        return sub in ("-e", "-p", "--eval", "--print") if sub else False

    # Simple read-only commands
    if base in {"ls", "cat", "head", "tail", "less", "more",
                "grep", "rg", "awk", "find", "tree", "file",
                "stat", "wc", "sort", "uniq", "diff", "comm",
                "which", "type", "command", "whereis",
                "du", "df", "pwd", "echo", "printf",
                "readlink", "realpath", "basename", "dirname",
                "date", "whoami", "id", "env", "printenv",
                "jq", "yq", "xxd", "od", "hexdump"}:
        return True

    return False


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(1)

    event = data.get("hook_event_name", "")
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input")
    # Ensure tool_input is a dict (it can be a string or other type in some cases)
    if not isinstance(tool_input, dict):
        tool_input = {}

    should_allow = False

    if tool in READONLY_TOOLS:
        should_allow = True
    elif tool == "Bash":
        command = tool_input.get("command", "")
        # Ensure command is a string (it can be a list in some edge cases)
        if not isinstance(command, str):
            command = ""
        should_allow = is_readonly_bash(command)

    if not should_allow:
        print(json.dumps({"continue": True, "suppressOutput": True}))
        sys.exit(0)  # Fall through to normal permissions

    if event == "PreToolUse":
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": f"Auto-approved read-only: {tool}",
            }
        }))
        sys.exit(0)
    elif event == "PermissionRequest":
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }))
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(1)
