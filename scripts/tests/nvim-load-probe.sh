#!/bin/sh
# Headless Neovim config-load probe.
#
# Loads the REAL user config headlessly and asserts three things:
#   1. nvim exits with the exit code nvim itself reports (startup chunk errors
#      are printed by init.lua but do NOT set the exit code — qa/0 masks them,
#      which is why a plain `nvim --headless +qa` is not a smoke test);
#   2. no runtime error report on stderr ("Error in <file>", E5113, …);
#   3. blink.cmp was not merely loadable but actually configured — asserted
#     via vim.g.blink_cmp_configured, set by nvim/init/16_lsp.lua AFTER
#     require('blink.cmp').setup() returns. A require failure aborts the
#     chunk, leaving the flag false.
#
# Exit 0 = clean; exit 1 = startup error, config error, or blink unconfigured.
# POSIX sh; must parse under both `zsh -n` and `/bin/bash -n` (bootstrap gate).
set -u

NVIM_BIN=${NVIM_BIN:-nvim}
have() { command -v "$1" >/dev/null 2>&1; }

if ! have "$NVIM_BIN"; then
  echo "nvim-load-probe: FAIL: $NVIM_BIN not found on PATH" >&2
  exit 1
fi

err_file=$(mktemp)
status_file=$(mktemp)
trap 'rm -f "$err_file" "$status_file"' EXIT

# All probe logic in one Lua chunk; stderr is reserved for nvim's own startup
# error reports plus our explicit PROBE-FAIL markers. `cq 1` propagates a
# nonzero exit through nvim itself (qa would mask it).
"$NVIM_BIN" --headless \
  '+lua local ok, err = pcall(require, "blink.cmp")
     if not ok then
       io.stderr:write("PROBE-FAIL blink.cmp require: " .. tostring(err) .. "\n")
       vim.cmd("cq 1")
       return
     end
     if not vim.g.blink_cmp_configured then
       io.stderr:write("PROBE-FAIL blink.cmp loaded but not configured (16_lsp.lua did not complete)\n")
       vim.cmd("cq 1")
       return
     end
     io.stderr:write("PROBE-OK blink.cmp configured\n")
     vim.cmd("qa")' \
  </dev/null >"$status_file" 2>"$err_file"
nvim_rc=$?

# 1: nvim's own exit code (nonzero on `cq 1` above or any fatal startup error)
if [ "$nvim_rc" -ne 0 ]; then
  echo "nvim-load-probe: FAIL: nvim exited $nvim_rc" >&2
  sed 's/^/  stderr: /' "$err_file" >&2
  exit 1
fi

# 2: startup/runtime error reports nvim prints to stderr WITHOUT a nonzero exit
if grep -qE 'Error in|E[0-9]{3,4}:' "$err_file"; then
  echo "nvim-load-probe: FAIL: startup error report on stderr (exit was masked by qa)" >&2
  grep -E 'Error in|E[0-9]{3,4}:' "$err_file" | sed 's/^/  /' >&2
  exit 1
fi

# 3: the positive marker must have been printed (guards against the Lua chunk
# itself failing to run at all)
if ! grep -q 'PROBE-OK blink.cmp configured' "$err_file"; then
  echo "nvim-load-probe: FAIL: probe chunk did not complete" >&2
  sed 's/^/  stderr: /' "$err_file" >&2
  exit 1
fi

echo "nvim-load-probe: PASS (blink.cmp configured, startup clean)"
exit 0
