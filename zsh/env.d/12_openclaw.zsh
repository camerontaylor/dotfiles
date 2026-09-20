# OpenClaw state dir — must be the REAL path, not the ~/.openclaw symlink.
#
# ~/.openclaw is a symlink into ~/repos/hart/openclaw (hart commit 02880050,
# "Move live OpenClaw home into repo"). OpenClaw's config writer does an
# atomic temp-file + rename() and refuses a symlinked parent, failing with
# "Atomic replace parent must be a real directory: /home/ctaylor/.openclaw".
# Without this, every interactive/agent `openclaw config set` fails while the
# gateway service (which sets this in its unit) works fine.
#
# Do NOT "fix" this by deleting the symlink: openclaw.json hardcodes three
# literal /home/ctaylor/.openclaw/... agent paths that no env var can reach,
# and the cron store is keyed by path STRING — a different path silently
# yields an empty job partition rather than an error.
export OPENCLAW_STATE_DIR=/home/ctaylor/repos/hart/openclaw
