---
name: repo-research
description: Research an external GitHub repository — library internals, SDK behavior, "how does X implement Y", dependency evaluation, debugging into a vendored package. Use whenever answering requires reading a third-party repo. Shallow-clones to a scratch area and works from source; never page through github.com web UI.
---

# repo-research — tiered GitHub repo research

Goal: source-grounded answers at minimum context cost. **Summary layers locate; source verifies.** No claim reaches a conclusion without a `path:line` citation from real file content — wiki-layer prose is a lead, never a citation.

## Clone area

All research clones live in `~/.cache/repo-research/<owner>/<repo>`. Disposable, read-only — never edit or build in them, safe to delete anytime.

- **Reuse first:** if the dir exists, use it. Refresh only when the question depends on latest state:
  `git -C <dir> fetch --depth 1 origin HEAD && git -C <dir> reset --hard FETCH_HEAD`
- **Standard clone:** `git clone --depth 1 --single-branch https://github.com/<o>/<r> ~/.cache/repo-research/<o>/<r>`
- **Huge repo / monorepo:** blobless + sparse, then cone in only what's needed:
  `git clone --depth 1 --filter=blob:none --sparse <url> <dir> && git -C <dir> sparse-checkout set <subdir>...`
- **History questions** ("when/why did X change"): don't deepen the clone speculatively — use `gh api repos/<o>/<r>/commits?path=<file>` first; `git fetch --deepen=50` only if you must blame locally.

## Tiered strategy — spend context in this order

**Tier 0 — maybe you don't need the repo.** `gh api repos/<o>/<r>/readme`, official docs, or the specific file you already know via `gh api repos/<o>/<r>/contents/<path>`. One known file never justifies a clone.

**Tier 1 — orientation (summary layer).** For "where does X live / what's the architecture":
- **DeepWiki** (default; free, no auth): MCP `ask_question` if the server is configured, else `WebFetch https://deepwiki.com/<o>/<r>`. Ask one targeted question phrased to return **file paths, symbol names, and key identifiers (dependency/library names, config keys)** — not explanations. The WebFetch fallback often can't see paths but reliably yields identifiers; one good grep string is a successful Tier 1.
- **zread** (`zread.ai/<o>/<r>`) as alternate lens — more tutorial-shaped; its MCP `read_file` is a citable raw read, but only available in GLM-plan sessions.
- Output of this tier is a list of candidate paths/symbols to grep. Discard the prose.

**Tier 2 — source of truth.** Shallow clone (above), then:
- `rg -n <symbol>` for the Tier-1 leads; Read only around hits (offset/limit). Never Read whole large files; never load repomix/gitingest whole-repo digests into context.
- Pin the version once — `git -C <dir> rev-parse --short HEAD` — and cite findings as `path:line @ <o>/<r>@<sha>`.

**No-clone fallback** (no git/network to github.com, or repo won't fit): per-file `gh api repos/<o>/<r>/contents/<path>` or WebFetch `raw.githubusercontent.com/<o>/<r>/HEAD/<path>` — still exact content, still citable. Summary layer alone is never a substitute for this.

## Context budget rules

- Broad sweeps ("map the plugin system", "find every implementation of the trait") → delegate to a **subagent pointed at the clone, instructed to work read-only and return conclusions only** (Claude Code: the Explore agent type; OpenClaw: `sessions_spawn` with that discipline in the prompt). Keep only its conclusions in the main context.
- Clone only repos the question names; don't chase transitive dependencies until a citation forces you to.
- Anything carried into the final answer needs `path:line @ sha`. Can't cite → say so explicitly.
