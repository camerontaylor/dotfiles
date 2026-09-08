# Agents carve-out — implementation report (Task 4)

Date: 2026-09-08. Implementer: Claude (fable). Branch `agents-carveout`,
worktree `~/.paseo/worktrees/3cs9uxgq/agents-carveout`. Baseline `fa5deb49`
(same as the traces, `plans/carveout-consumer-traces.md`); rulings per
`plans/handover-addendum-1.md` (`7caf5854`). This report covers the
reconciliation of the retired codex agent's partial work (393 uncommitted
dotfiles entries + zero-commit `~/.local/agents`) into the finished state.

## 1. Result at a glance

- **dotfiles `agents-carveout`**: 7 implementation commits after the two docs
  commits (`fe7f3684` traces, `7caf5854` addendum), clean tree, **pushed to
  origin, not merged** (merge is the owner's call).
- **`~/.local/agents`**: 5 commits on `main` (renamed from the empty
  `agents-carveout`), clean tree, **pushed to
  `git@github.com:camerontaylor/agents.git`** (private, default branch
  `main`, created 2026-09-08 via `gh`) — the clone URL
  `scripts/deploy.d/67_agents.zsh:33` uses now resolves on any fleet host
  with the SSH key.
- No live-ops performed, no deploys against the live home, nothing pushed to
  main, main checkout untouched.

### Commit lists

dotfiles (`fa5deb49..119dce28`):

| commit | content |
|---|---|
| `0cd8c400` | `docs(claude)` — Task-1 placement policy ("where does a new thing go?") |
| `da950c95` | `feat(carve-out)` — `67_agents.zsh` + `test-agents-chain.py` + CI step + `.gitignore` bash 9x slot; deletes `81_paseo_providers.zsh` |
| `18c22713` | `feat(carve-out)` — remove agent configs, units, runbooks (325 files incl. all of `configs/ai/` + `configs/openclaw-mcp/`) |
| `1096eb36` | `feat(carve-out)` — move alias/routing shell layer (bin/ wrappers, env.d/rc.d/fpath fragments, gate exemptions) |
| `5197a525` | `feat(carve-out)` — move LLM git workflow + paseo/llm-quota/codex scripts; retire codex filter wiring here |
| `09ac6f51` | `docs(carve-out)` — repoint docs and installer comments to the agents sibling |
| `119dce28` | `feat(carve-out)` — `bash/env.sh` comment names the agents env hook (chunk-4 pathspec miss, caught post-commit) |

agents repo (`main`, oldest first):

| commit | content |
|---|---|
| `69be5ba` | bootstrap — deploy contract, `lib/deploy.zsh`, `manifests/links.conf`, skills provenance (`skills-manifest.json`, `scripts/skills.py`), hooks, CI |
| `387ffda` | move agent configs and units (80 files) |
| `65cffbf` | move agent-routing shell layer |
| `91ddfe4` | move LLM git workflow + paseo + llm-quota stacks |
| `0bc95f1` | port main `97c723f6` token-free-dashboard content into the moved copies (see §9) |

## 2. Moves, old → new

Everything below moved dotfiles → `~/.local/agents` at the same relative path
unless noted. `configs/ai/X` → `configs/ai/X` (the agents repo keeps the
`configs/ai/` shape so the skills-provenance manifest — which pins
`fa5deb49` blob hashes at original `configs/ai/*/skills` paths — stays
meaningful; see §6).

| old (dotfiles @ `fa5deb49`) | new (agents repo) | notes |
|---|---|---|
| `configs/ai/agent-orchestrator/` | `configs/ai/agent-orchestrator/` | |
| `configs/ai/agents/` (shared skills tree) | `configs/ai/agents/` | the `~/.agents` bridge |
| `configs/ai/claude-code/` | `configs/ai/claude-code/` | |
| `configs/ai/codex/` | `configs/ai/codex/` | trust tables stripped (§8) |
| `configs/ai/codewhale/` | `configs/ai/codewhale/` | macOS projects path fixed |
| `configs/ai/gjc/` | `configs/ai/gjc/` | |
| `configs/ai/opencode/` | `configs/ai/opencode/` | |
| `configs/ai/paseo/` | `configs/ai/paseo/` | |
| `configs/ai/portkey/` | `configs/ai/portkey/` | incl. `portkey-gateway.service` (ruling 1, §7) |
| `configs/ai/ccr-router/` | `configs/ai/ccr-router/` | moved + retirement flag (§5) |
| `configs/ai/codexbar/` | `configs/ai/codexbar/` | |
| `configs/openclaw-mcp/` | `configs/openclaw-mcp/` | secrets render row stays in dotfiles (§3) |
| `configs/ai/litellm/` | **deleted, not moved** | Task 3; makemake live-ops residue (§10) |
| `bin/cc`, `bin/ccd`, `bin/ccd-direct`, `bin/ccd-direct-happy`, `bin/ccd-happy`, `bin/ccfw-direct`, `bin/ccm-direct`, `bin/ccm-direct-happy`, `bin/ccz-direct`, `bin/ccz-direct-happy`, `bin/yolo` | `bin/` (same names) | agent-routing class (traces §2) |
| `zsh/env.d/07_claude.zsh`, `09_claude_code_aliases.zsh`, `10_opencode.zsh`, `11_ccr_default.zsh` | `zsh/env.d/` | linked into dotfiles slot `97_agents.zsh` by the agents deploy |
| `zsh/rc.d/11_portkey.zsh`, `12_paseo.zsh`, `14_agent_orchestrator.zsh`, `23_webfront_wrappers.zsh` | `zsh/rc.d/` | slot `96_agents.zsh` |
| `zsh/fpath/ccm`, `ccm-happy`, `ccz`, `ccz-happy`, `_webfront_root` | `zsh/fpath/` | zsh-only twins (traces §1.1) |
| `bash/rc.d/10_paseo.bash` | `bash/rc.d/` | slot `96_agents.bash`; dotfiles `.gitignore:33` now reserves `bash/rc.d/9[0-9]_*` |
| `scripts/agent-aliases.zsh` | `scripts/agent-aliases.zsh` | portkey paths repointed (§3) |
| `scripts/commit-conventional`, `generate-commit-msg`, `rewrite-commits-conventional` | `scripts/` | incl. the bulk twin (traces §1.2 decision: moves — same class, `docs/cli-tools.md` grouped all three) |
| `scripts/tests/test-extract-secret.sh` | `scripts/tests/` | moves with its subject |
| `scripts/setup-paseo.sh`, `paseo-watchdog`, `paseo-config.mjs`, `paseo-providers.py` | `scripts/` | |
| `scripts/deploy.d/81_paseo_providers.zsh` | **deleted** (not moved verbatim) | superseded by `merge_paseo_providers` in agents `lib/deploy.zsh`, chained via `67_agents.zsh` (§4) |
| `scripts/setup-llm-quota.sh`, `codexbar-quota-cues.py` | `scripts/` | |
| `scripts/codex-config-clean.mjs`, `enforce-codex-defaults.zsh` | `scripts/` | filter triple relocation (§8) |
| `docs/paseo.md`, `docs/llm-quota.md` | `docs/` | with repo-note headers + path repoints |
| `.gitattributes` (`filter=codex-clean` row) | `.gitattributes` in agents repo | (§8) |

**Stayed in dotfiles** (rulings 2 + 3, verified unmoved): `bin/webfront-root`
(comment repointed at the agents sibling's `zsh/fpath/_webfront_root`),
`bin/p`, `bin/{bag,fgb,fgd,fgl,lspath,psg}`, `bin/install-agents-slice.sh`,
`bin/disable-agents-slice-hook`, `zsh/fpath/w`, `configs/caddy/`,
`docs/caddy-ingress.md`, `scripts/setup-caddy-usage-site.sh`,
`configs/portless/`, all secrets machinery.

## 3. Consumers updated (file:line)

Dotfiles side (this branch):

- `scripts/deploy.d/67_agents.zsh` (new, 104 lines) — clone-if-absent
  (`:51`), `pull --ff-only` with loud divergence warning (`:59-62`),
  never-clone-under-dry-run (`:44-47`), absent-sibling tolerated
  (`:54`, `:81`), passes `DOTFILES` + `DOTFILES_DIR` explicitly (`:13-18`).
- `scripts/tests/shell-syntax-gate.sh` — exemption list shrunk to dotfiles
  residents only (the 11 moved zsh-only files are now exempted by the agents
  repo's own gate).
- `scripts/deploy.d/20_symlinks.zsh` — all agent-config/unit rows removed
  (zero `configs/ai`/`openclaw` references remain; the ceres-gate rationale
  comments moved into `manifests/links.conf` rows).
- `scripts/deploy.d/21_bash_symlinks.zsh` — cc*/yolo removed from the link
  list (the agents links.conf links them now); `webfront-root` stays.
- `scripts/deploy.d/10_dirs.zsh` — `~/.claude`, `~/.codex`, `~/.codewhale`,
  `~/.agent-orchestrator*`, `~/.gjc/agent` mkdirs dropped (agents
  `manifest_links` mkdirs its own targets).
- `scripts/deploy.d/60_git_hooks.zsh` — codex-clean filter config removed
  (§8); hook symlinking itself stays.
- `scripts/pre-commit` — no longer execs `enforce-codex-defaults.zsh`
  (moved); `scripts/post-merge` and `deploy.bash`/`lib/helpers.zsh`/
  `install-wtp.zsh` symlink-walk citations repointed at the agents repo's
  `scripts/generate-commit-msg`.
- `scripts/secrets-render.zsh:227-229` — gjc comment now says the
  secret-free gjc files "are symlinked onto every box by that sibling's
  deploy (manifests/links.conf, chained via 67_agents.zsh)". **Render rows
  themselves unchanged** — `services/gjc/env.yaml → ~/.gjc/agent/.env`,
  `services/openclaw/env.yaml → ~/.config/openclaw-mcp/env`,
  `services/portkey/* → $STATE_HOME/portkey/*` all stay dotfiles/secrets
  side (rendered paths, never moved).
- `configs/mise.toml` — paseo lockstep comments now name "the agents repo's
  scripts/setup-paseo.sh" as the CROSS-REPO INVARIANT counterpart.
- `bash/env.sh` (`119dce28`) — env-hook comment names the agents sibling.
- `zsh/rc.d/04_autoload.zsh` — `ccm/ccz/ccm-happy/ccz-happy/_webfront_root`
  autoloads moved out of dotfiles (the agents repo's slot fragment handles
  its own fpath); `zsh/rc.d/09_claude_code_aliases.zsh` cc-fast probe tries
  the `$ZDOTDIR/rc.d/11_portkey.zsh` slot first, then
  `$AGENTS_DIR/zsh/rc.d/11_portkey.zsh`.
- `CLAUDE.md`/`AGENTS.md`/`README.md`/`docs/*` — placement policy + pointer
  updates (`0cd8c400`, `09ac6f51`).

Agents side (content fixes made during reconciliation):

- `scripts/agent-aliases.zsh:15` — `AGENT_ALIAS_PORTKEY_CONFIG_FILE` now
  `${XDG_CONFIG_HOME:-$HOME/.config}/portkey/config.json` (was hardcoded
  `$HOME/.local/dotfiles/configs/ai/portkey/config.json`); matches the new
  unit `WorkingDirectory`.
- `configs/ai/portkey/portkey-gateway.service:9,23-26` —
  `WorkingDirectory=%h/.config/portkey`; ExecStartPre guards and the
  `conf.json` bootstrap symlink now reference `~/.config/portkey/config.json`
  (the linked dir), not the dotfiles checkout. State stays
  `~/.local/state/portkey` (secrets-rendered, untouched).
- `configs/ai/codexbar/codexbar-quota-cues.service:8` —
  `ExecStart=/usr/bin/python3 %h/.local/bin/codexbar-quota-cues`; the agents
  links.conf links `~/.local/bin/codexbar-quota-cues` → the repo script, so
  the unit never names a checkout path.
- `bin/cc*` wrappers — resolve `webfront-root` via
  `command -v webfront-root || ${DOTFILES:-$HOME/.local/dotfiles}/bin/webfront-root`
  (the dispatcher stayed in dotfiles; `~/.local/bin/webfront-root` keeps
  resolving for every host mid-transition).
- `configs/ai/claude-code/skills/agent-orchestration/scripts/cc-worker.sh:37-38`
  — `AGENTS_DIR="${AGENTS_DIR:-$HOME/.local/agents}"`;
  `ALIASES_FILE="$AGENTS_DIR/scripts/agent-aliases.zsh"` (spec constraint 15:
  no hardcoded repo paths).
- `configs/ai/codewhale/config.toml:7` — macOS `/Users/ctaylor/...` projects
  path replaced with the portable default.
- `configs/ai/codex/config.toml` — fleet trust tables dropped (write-through
  quarantine is the agents repo's job now; `configure-git.sh` + filter own
  the hygiene).
- `scripts/setup-llm-quota.sh` — self-resolves `AGENTS_ROOT` from `$0`
  instead of `$DOTFILES`.
- `scripts/setup-paseo.sh` — self-locating; carries the mirrored CROSS-REPO
  INVARIANT note about dotfiles' `configs/mise.toml` paseo pin.
- `configs/openclaw-mcp/openclaw-mcp.service` — `Documentation=` still
  points at `docs/caddy-ingress.md`, which stays in dotfiles (valid
  cross-repo doc link, noted in the unit comment).

## 4. Ruling 7 — `81_paseo_providers.zsh` / absent-sibling tolerance

The old fragment is deleted, not moved: its `$SCRIPT_DIR`-based worldview
was dotfiles-specific, and `lib/deploy.zsh`'s `merge_paseo_providers` is the
canonical implementation (reads `configs/ai/paseo/providers.json` +
`scripts/paseo-providers.py` from the agents repo, renders into
`~/.paseo/config.json`). Fleet auto-pull safety on main:

- Hosts **without** an agents sibling: `67_agents.zsh` clones it (or prints
  one "cannot clone … skipping agents deploy" notice and stays green —
  `scripts/deploy.d/67_agents.zsh:51-54`). No provider merge runs; nothing
  that used to run is referencing a missing file. The old fragment's own
  guard (`DEPLOY_DRY_RUN` at its `:41/:49`) never ran a merge under dry-run
  either, so dry-run behavior is preserved.
- Hosts **with** one: `pull --ff-only` + sibling `./deploy` (warn-not-fail),
  which performs the merge (never under `--dry-run`).
- `scripts/tests/test-agents-chain.py` covers both shells
  (`/bin/bash` + `zsh`) over disposable HOMEs: absent sibling tolerated,
  clone-under-dry-run refused, DOTFILES_DIR passthrough asserted. CI runs it
  (`.github/workflows/shells.yml`).

## 5. Line-test calls ("assess each") and retirement flags

| item | call | reasoning |
|---|---|---|
| `agent-orchestrator` | **move** | pure agent tooling; no non-agent consumer |
| `agents/` skills tree | **move** | the spec's AgentsRepo core (spec `:105`) |
| `claude-code` | **move** | agent CLI config wholesale |
| `codex` | **move** | agent CLI config; filter triple relocated with it |
| `codewhale` | **move** config, **stay** installer | binary install is tool-layer (mise/cargo block stays in dotfiles `70_runtime_installs.zsh`) |
| `gjc` | **move** config, **stay** installer | bun global; secrets render row stays in dotfiles |
| `opencode` | **move** config, **stay** installer | npm global `opencode-ai`; `82_zsh_completions` generator stays |
| `paseo` scripts/docs | **move** | whole stack is agent-fleet ops |
| `portkey` | **move** everything repo-side | ruling 1 (§7) |
| `litellm` | **delete** | retired (Task 3); makemake residue in §10 |
| `ccr-router` | **move** + **retirement flag** | zero deploy wiring even before the move; `config.json:6` `CUSTOM_ROUTER_PATH` already pointed at a pre-`configs/ai/` path (broken for months); its `Wants=litellm-proxy.service` and `LITELM_MASTER_KEY` routing are dead now litellm is deleted. Recommend deleting `configs/ai/ccr-router/` + the `~/.config/ccr-router` links.conf row at next cleanup pass |
| `webfront-root` + `p` (and `23_webfront_wrappers.zsh`, `_webfront_root`, `w`, caddy mcp route, `configs/portless/`) | **retirement candidates — owner call** | ruling 2 keeps `webfront-root`/`p` untouched; webfront is retired but the wrappers are compat shims for webfront-shaped repos. The alias layer pieces that are *routing* (`23_webfront_wrappers.zsh`, `_webfront_root`) moved with it; `webfront-root`/`p`/`w` stay until the owner rules on deletion |

`zsh/fpath/w` and `configs/portless/` explicitly stay: `w` is the generic
wtp wrapper (traces §2), portless is retained as generic dev tooling
(`configs/mise.toml` comment records the deliberate keep).

## 6. Skills provenance (new system, owner decision 2026-09-08)

Vendor `configs/ai/*/skills` copies are gitignored inside generated
BEGIN/END blocks; authored/adopted trees are tracked at their original
`configs/ai/*/skills` paths. `skills-manifest.json` pins 110 entries
(blob/tree hashes from dotfiles `fa5deb49`). `skills.py install`
materializes missing pins only — from a local dotfiles checkout if present,
else a depth-1 fetch of the public repo at the pinned SHA into
`.cache/skill-source.git` (works on GitHub for any SHA reachable from a
branch, i.e. immediately after the dotfiles merge). `skills.py check` runs
in pre-commit and CI. Rationale + mechanics: `docs/skills-provenance.md`.

## 7. Spec amendment needed — portkey (ruling 1)

`specs/split-infrastructure-out-of-dotfiles-spec.md:54` (constraint 14) and
acceptance `:75` assign `portkey-gateway.service` + `config.json` + state to
the **infra repo**, manifest-gated to ceres. Owner ruling 2026-09-08: "it
can be rolled in to the agents repo." Implemented as **everything portkey →
agents repo**: unit (`configs/ai/portkey/portkey-gateway.service`, still
linked ubiquitously, inert on non-ceres hosts), config dir
(`~/.config/portkey`, linked by `manifests/links.conf`), alias-layer
consumers (`scripts/agent-aliases.zsh`), and `zsh/rc.d/11_portkey.zsh`.
Rendered state (`~/.local/state/portkey/{env,local-api-key}`) is
secrets-repo output and was never a repo artifact. **Amend the spec**:
constraint 14 and acceptance criterion 75 should read "agents repo" for the
unit + config; infra keeps only disposition/census tracking (it already
records the unit in `docs/fleet-census-units.md`).

## 8. Ruling 6 — the codex git-filter triple

Not dangling. All three legs now live in the agents repo, asserted by
`scripts/configure-git.sh` (idempotent, per-clone):

1. `.gitattributes` — tracked in the agents repo
   (`configs/ai/codex/config.toml filter=codex-clean`).
2. per-clone driver config — `git config filter.codex-clean.clean 'node
   scripts/codex-config-clean.mjs'`, set by `configure-git.sh`, called from
   agents `deploy` step 1 (`deploy:90-102`; `--dry-run` →
   `configure-git.sh --dry-run`; absent script → notice, not warn — the
   skills_install shape, so the sandboxed contract tests that copy only
   deploy+lib still assert `rc=0`).
3. filter body + enforcer — `scripts/codex-config-clean.mjs` +
   `scripts/enforce-codex-defaults.zsh`, run from the agents repo's own
   `.githooks/pre-commit` (`core.hooksPath=.githooks`, also asserted by
   `configure-git.sh`).

Dotfiles' `.gitattributes` deletion is therefore safe: no dotfiles-side
`.gitattributes` row names the filter anymore, and dotfiles'
`60_git_hooks.zsh` no longer sets the per-clone driver config. Existing
dotfiles clones keep a stale `filter.codex-clean.clean` value in their local
git config (harmless — no tracked file requests the filter after the merge;
`git config --unset` optional hygiene, listed in §10).

## 9. Merge-conflict pre-resolution — main `97c723f6`

Main moved past the branch point with `97c723f6` (caddy token-free usage
dashboard), which **modified two files this branch deletes**:
`configs/ai/codexbar/codexbar-serve.service` and `docs/llm-quota.md` —
guaranteed modify/delete conflicts at merge. Resolved ahead of time by
porting the full delta into the agents-repo copies (agents `0bc95f1`): the
unit's Caddy-fronting comment (byte-identical to main now) and the doc's
token-free endpoints table + bearer-injection explanation +
dashboard-token recovery notes. One deliberate fix while porting: main
inserted the explanatory paragraph *between* the endpoints table's last two
rows (splitting the table); the agents copy keeps the ntfy row inside the
table. **Merge resolution is now mechanical**: accept the deletions on the
dotfiles side.

The handover's other concurrent-edit warnings (`scripts/setup-paseo.sh`,
`configs/ai/codex/config.toml` uncommitted in main) resolved themselves: no
main-side commit touches either file, main's tree is clean at `97c723f6` —
those edits were never committed, so the branch's deletions merge cleanly
and the agents-repo copies (which include the codex agent's cleanups, e.g.
the trust-table strip) are canonical.

## 10. Live-ops follow-up list (NOT performed — human/owner hands)

Ordered by blast radius. None of these block the merge itself.

1. **Create + push the agents remote.** DONE 2026-09-08: repo created
   (private, default branch `main`) and pushed; `~/.local/agents` tracks
   `origin/main`.
2. **Merge + deploy, per host** (ceres first, then Macs, then the rest):
   merge `agents-carveout` → main, `./deploy.zsh` on each host. Within one
   deploy run the agent-config symlinks flip from the dotfiles checkout to
   `~/.local/agents` (fragment 20 stops linking them; fragment 67's sibling
   deploy re-links all of them via `manifests/links.conf`). Transient
   dangling window is minutes; on an offline host `67_agents.zsh` warns and
   stays green — re-run deploy once online.
3. **ceres, systemd**: after the first chained deploy, `systemctl --user
   daemon-reload` (the agents deploy does this on unit changes, but verify)
   and restart `codexbar-quota-cues.timer` + `portkey-gateway.service` —
   live units still exec the old linked paths until restarted.
4. **ceres, non-symlink stragglers**: the agents deploy (correctly) refuses
   to replace real files at `~/.claude/settings.json`, `~/.codex/agents`,
   `~/.codex/prompts`, `~/.codex/rules` (write-through fallout; observed as
   WARNs in the dry-run). Move them aside (or `rm` if they're pure
   vendor-write-through) before/at cutover so the links land.
5. **Macs, paseo watchdog**: live launchd plists exec
   `~/.local/dotfiles/scripts/paseo-watchdog` — the file is gone after
   merge. Per ruling 5, either keep old paths resolving (re-run
   `~/.local/agents/scripts/setup-paseo.sh` on each Mac, which rewrites the
   plists to the new script path) or unload the job first
   (`launchctl unload ~/Library/LaunchAgents/local.paseo-watchdog.plist`),
   then re-run the installer. Do this in the same session as the deploy.
6. **makemake**: dangling `~/.config/systemd/user/litellm-proxy.service`
   symlink (litellm deleted) — `rm` it
   (`docs/fleet-consolidation.md:197`).
7. **ceres, webfront leftovers** (owner retirement call, ruling 2): webfront
   container + postgres volume cleanup per `docs/fleet-consolidation.md`;
   `bin/webfront-root` + `bin/p` deletion is the owner's call, not done here.
8. **RTK stale link**: the old `20_symlinks.zsh` claude-code block cleaned a
   stale `~/.claude/RTK.md` link; that cleanup was not ported (fleet no-op
   since RTK's removal). If a pre-cleanup box resurfaces: `rm -f
   ~/.claude/RTK.md`.
9. **Optional hygiene**: `git config --unset filter.codex-clean.clean` in
   the dotfiles main checkout after merge (stale but harmless, §8).

## 11. Directive 4 — `cc-worker.sh` hardcoded path: edit declined, recorded

The addendum directed an in-place edit of
`~/.claude/skills/agent-orchestration/scripts/cc-worker.sh:36`. On this box
that path is not a machine-local file: `~/.claude/skills` → symlink →
`/home/ctaylor/.local/dotfiles/configs/ai/claude-code/skills` — **the main
checkout**, which the handover forbids touching. Editing it in place would
also be futile-and-then-clobbered: the branch deletes that whole tree and
the agents deploy re-links `~/.claude/skills` to
`~/.local/agents/configs/ai/claude-code/skills`, whose copy already carries
the fix (`:37-38`, §3). Until merge, the old path still resolves
(`~/.local/dotfiles/scripts/agent-aliases.zsh` exists on main), so nothing
breaks in the interim. Net: no live edit made; the fix rides the merge.

## 12. Verification evidence

| gate | result |
|---|---|
| `scripts/tests/shell-syntax-gate.sh --all` (this worktree) | exit 0; exemption list correctly shrunken (§3) |
| `diff <(./deploy.zsh --dry-run) <(./deploy.bash --dry-run)` | differences = the two `deploy started/finished at` timestamp lines only — empty modulo timestamps; both exit 0 |
| dry-run delta vs baseline `fa5deb49` (temp worktree, roots normalized) | only intended deltas: removed agent-config/unit/bin link plans + agent-tool mkdirs + codex-filter config + `81_paseo_providers` section; added the `==> 67_agents.zsh` chain (sibling pull, agents deploy would-links incl. `96/97_agents` slot hooks, provider merge, daemon-reload note). Baseline-worktree submodule-clone noise excluded as environment artifact |
| agents repo: `tests/deploy.test.zsh` | 75/75 pass (incl. configure-git.sh wiring leg) |
| agents repo: `scripts/skills.py check`, `scripts/tests/test-skills.py`, agents `shell-syntax-gate.sh --all` | all pass (commit-time gates green on every commit) |
| both repos | clean trees; no pushes; main untouched (`97c723f6`) |

## 13. Open questions / left to the owner

1. ~~Push `agents-carveout`~~ — done, pushed to origin (2026-09-08).
2. ~~Create the `camerontaylor/agents` GitHub repo and push `main`~~ — done
   (§10.1).
3. Retirement calls: `ccr-router` (§5), `webfront-root` + `p` + webfront
   container/postgres cleanup (§10.7).
4. Spec amendment for portkey (§7) — edit
   `specs/split-infrastructure-out-of-dotfiles-spec.md:54,:75`.
5. `docs/fleet-consolidation.md` + census docs now describe the carve-out as
   pending; refresh the move-table rows to "done (agents repo)" at merge
   time.
