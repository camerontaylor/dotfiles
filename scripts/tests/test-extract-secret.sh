#!/usr/bin/env bash
set -euo pipefail

# test-extract-secret.sh
#
# Exercises the extract_secret() helper in scripts/generate-commit-msg.
# The helper is carved out of the real script with sed and sourced, so there is
# a single source of truth: rename or delete the helper and this test fails
# loudly instead of silently testing a stale copy.
#
# All fixtures are synthetic. No real secret file is ever read.

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$SOURCE_DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"

TARGET="$SCRIPT_DIR/../generate-commit-msg"
if [[ ! -r "$TARGET" ]]; then
  echo "FAIL: cannot read $TARGET" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d -t test-extract-secret.XXXXXX)"
cleanup() { rm -rf "$TMPDIR_TEST"; }
trap cleanup EXIT

sed -n '/^extract_secret() {/,/^}/p' "$TARGET" > "$TMPDIR_TEST/helper.sh"
if ! grep -q '^extract_secret() {' "$TMPDIR_TEST/helper.sh"; then
  echo "FAIL: extract_secret() not found in $TARGET (renamed or removed?)" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$TMPDIR_TEST/helper.sh"

FAILURES=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# check_value <label> <file> <key> <expected>
check_value() {
  local label="$1" file="$2" key="$3" expected="$4" got status
  set +e
  got="$(extract_secret "$file" "$key")"
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    fail "$label (helper returned $status, expected success)"
  elif [[ "$got" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (got [$got], want [$expected])"
  fi
}

# check_fails <label> <file> <key>
check_fails() {
  local label="$1" file="$2" key="$3" got status
  set +e
  got="$(extract_secret "$file" "$key")"
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    pass "$label"
  else
    fail "$label (expected nonzero exit, got 0 with [$got])"
  fi
}

FIXTURE="$TMPDIR_TEST/secrets.zsh"
{
  printf '# synthetic fixture — no real secrets\n'
  printf 'export BARE_KEY=plainvalue\n'
  printf 'export DQ_KEY="plainvalue"\n'
  printf 'export SQ_KEY=%s\n' "'plainvalue'"
  printf 'export APOS_KEY=%s\n' "'it'\\''s'"
  printf 'export SPACE_KEY=%s\n' "'two words here'"
  printf 'export DOLLAR_KEY=%s\n' "'a\$b\${c}d'"
} > "$FIXTURE"

check_value 'bare value       (K=v)'          "$FIXTURE" BARE_KEY   'plainvalue'
check_value 'double-quoted    (K="v")'        "$FIXTURE" DQ_KEY     'plainvalue'
check_value 'single-quoted    (K='"'"'v'"'"')' "$FIXTURE" SQ_KEY    'plainvalue'
check_value 'embedded apostrophe (qq form)'   "$FIXTURE" APOS_KEY   "it's"
check_value 'value with spaces'               "$FIXTURE" SPACE_KEY  'two words here'
check_value 'value with $ stays literal'      "$FIXTURE" DOLLAR_KEY 'a$b${c}d'

check_fails 'missing key returns nonzero'     "$FIXTURE" NO_SUCH_KEY
check_fails 'missing file returns nonzero'    "$TMPDIR_TEST/does-not-exist.zsh" BARE_KEY

# End-to-end: a fixture produced by zsh's own ${(qq)} quoting.
if command -v zsh >/dev/null 2>&1; then
  ZFIXTURE="$TMPDIR_TEST/zsh-rendered.zsh"
  zsh -c 'v="it'"'"'s a \$test value"; print -r -- "export FIXTURE_KEY=${(qq)v}"' > "$ZFIXTURE"
  check_value 'zsh ${(qq)} round-trip'        "$ZFIXTURE" FIXTURE_KEY 'it'"'"'s a $test value'
else
  printf 'SKIP: zsh not available for ${(qq)} round-trip\n'
fi

if [[ $FAILURES -ne 0 ]]; then
  printf '\n%d test(s) failed.\n' "$FAILURES"
  exit 1
fi

printf '\nAll tests passed.\n'
