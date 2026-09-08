# Consumer traces — agents carve-out groundwork (Task 2)

Date: 2026-09-08. Read-only groundwork for `plans/handover-agents-carveout.md`
Task 2. No moves were made; every citation below resolves against the
**committed baseline `fa5deb49` (HEAD of `agents-carveout`)**, which is what the
handover's own line references (e.g. `20_symlinks.zsh:133`) point at.

## 0. READ FIRST — an uncommitted prior attempt sits in this worktree

The working tree is **not clean**: 393 uncommitted entries (361 deletions,
30 modifications, 2 untracked) implementing most of Tasks 1–3, plus a
matching fresh repo at `~/.local/agents` (branch `agents-carveout`,
**zero commits**, everything staged). Summary of that state:

- Deleted from the worktree (uncommitted): all of `configs/ai/` +
  `configs/openclaw-mcp/`, `bin/cc*` + `bin/yolo`, `scripts/agent-aliases.zsh`,
  `scripts/{commit-conventional,generate-commit-msg,rewrite-commits-conventional}`,
  `scripts/{setup-paseo.sh,paseo-watchdog,paseo-config.mjs,paseo-providers.py}`,
  `scripts/deploy.d/81_paseo_providers.zsh`, `scripts/{setup-llm-quota.sh,codexbar-quota-cues.py}`,
  `scripts/{codex-config-clean.mjs,enforce-codex-defaults.zsh}`,
  `zsh/env.d/{07_claude,09_claude_code_aliases,10_opencode,11_ccr_default}.zsh`,
  `zsh/rc.d/{11_portkey,12_paseo,14_agent_orchestrator,23_webfront_wrappers}.zsh`,
  `bash/rc.d/10_paseo.bash`, `zsh/fpath/{_webfront_root,ccm,ccm-happy,ccz,ccz-happy}`,
  `docs/paseo.md`, `docs/llm-quota.md`, `scripts/tests/test-extract-secret.sh`,
  `.gitattributes`.
- Modified (uncommitted): `CLAUDE.md` (Task-1 placement section present),
  `AGENTS.md`, `README.md`, `20_symlinks.zsh` (all agent symlink blocks
  removed), `21_bash_symlinks.zsh`, `60_git_hooks.zsh`, `10_dirs.zsh`,
  `70_runtime_installs.zsh`, `75_brew_setup.zsh`, `lib/helpers.zsh`,
  `deploy.bash`, `bash/env.sh`, `scripts/pre-commit`, `scripts/post-merge`,
  `scripts/tests/shell-syntax-gate.sh`, `zsh/rc.d/04_autoload.zsh`,
  `configs/mise.toml`, `.gitignore`, `.github/workflows/shells.yml`, docs.
- Untracked: `scripts/deploy.d/67_agents.zsh` (104 lines, modeled on
  `66_infra.zsh`, passes `DOTFILES_DIR` explicitly to the sibling deploy),
  `scripts/tests/test-agents-chain.py` (70 lines).
- `bin/webfront-root` **kept** in dotfiles, comment repointed at "the agents
  sibling's zsh/fpath/_webfront_root".
- No `plans/agents-carveout-report.md` exists yet (Task 4 undone).

Consequences for the implementer: either reconcile/finish this attempt or
reset the worktree to HEAD and redo — but `~/.local/agents` has no commits
and no remote push, so nothing is durable yet. All traces below describe the
committed baseline the move starts from.

## 1. Consumer traces per move-list item

Line numbers are HEAD (`fa5deb49`) line numbers.

### 1.1 cc*/ccz alias layer — `zsh/env.d/09_claude_code_aliases.zsh`, `scripts/agent-aliases.zsh`, `bin/` cc*/yolo wrappers

Moved-file set at HEAD (bin/ side): `bin/cc`, `bin/ccd`, `bin/ccd-direct`,
`bin/ccd-direct-happy`, `bin/ccd-happy`, `bin/ccfw-direct`, `bin/ccm-direct`,
`bin/ccm-direct-happy`, `bin/ccz-direct`, `bin/ccz-direct-happy`, `bin/yolo`.
The handover's list misses the zsh-only twins, which belong to the same
class: `zsh/fpath/ccm`, `zsh/fpath/ccm-happy`, `zsh/fpath/ccz`,
`zsh/fpath/ccz-happy` (stateful Portkey-fallback wrappers,
`scripts/tests/shell-syntax-gate.sh:63-66` exempts them from the bash gate
leg as zsh-only).

Consumers:

- **Symlink install (bash/`~/.local/bin`)**: `scripts/deploy.d/21_bash_symlinks.zsh:23-28`
  links every wrapper by explicit list (`cc yolo p ccd ccd-happy ccm-direct
  ccm-direct-happy ccd-direct ccd-direct-happy ccfw-direct ccz-direct
  ccz-direct-happy lspath bag fgb fgd fgl psg`); `:22` links sibling
  `bin/webfront-root` first (wrappers resolve it via `$(dirname "$0")`).
- **zsh autoload**: `zsh/rc.d/04_autoload.zsh:47` —
  `autoload -Uz _webfront_root w ccm ccz ccm-happy ccz-happy`; `:45-46`
  documents that the non-direct wrappers keep their zsh-only Portkey
  fallback so they stay fpath functions.
- **env.d load order**: `bash/env.sh:44` names "09's portkey probe" among the
  fragments the shared bash env layer keys off `ZDOTDIR` for.
- **Syntax-gate exemptions**: `scripts/tests/shell-syntax-gate.sh:56`
  (`zsh/rc.d/11_portkey.zsh`), `:57` (`zsh/rc.d/12_paseo.zsh`), `:63-66`
  (the four fpath cc wrappers) — the exemption list shrinks when these move.
- **Portkey coupling inside the layer**: `scripts/agent-aliases.zsh:14-15`
  pins `AGENT_ALIAS_PORTKEY_CONFIG_FILE` to
  `$HOME/.local/dotfiles/configs/ai/portkey/config.json` (hardcoded path;
  also `:448` comment); `:18-174` define the `agent_alias_portkey_*` helpers;
  `:304,458,498,537,581` call them from the ccm/ccfw/ccd/ccz/cc-fast cases.
- **Portkey rc.d coupling**: `zsh/env.d/09_claude_code_aliases.zsh:151-186`
  (`_cc_fast_portkey` sources `$ZDOTDIR/rc.d/11_portkey.zsh` at `:159-163`);
  `zsh/fpath/ccm:4` and `zsh/fpath/ccm-happy:4` fall back to
  `_portkey_run_ccm`; `bin/ccd:5,10` and `bin/ccd-happy:7` print errors
  naming `zsh rc.d/11_portkey.zsh` as the zsh-only fallback.
- **CCR coupling**: `zsh/env.d/09_claude_code_aliases.zsh:75,139` define
  `cc-ccr` via `eval "$(ccr activate)"`; rollback flags documented in
  `zsh/env.d/11_ccr_default.zsh:1-14` (`USE_CCR=0` default, per-alias
  overrides).
- **webfront dispatch**: every `bin/cc*` wrapper resolves the enclosing
  webfront repo via sibling `bin/webfront-root`
  (`bin/cc:7-8`, `bin/ccd-direct:7-8`, …) and, inside one, execs
  `zsh "$root/scripts/run-agent-alias.sh" <alias>` (`bin/cc:16`, `bin/yolo:15`,
  all cc\*-direct wrappers). `run-agent-alias.sh` is a **webfront-repo**
  file (dotfiles never had it — verified absent at HEAD, in the worktree,
  and in `~/.local/agents/scripts/`); outside a webfront repo the wrappers
  take the direct-provider `env -u …` fallback (`bin/cc:9-14`).
  `zsh/rc.d/23_webfront_wrappers.zsh:1-17` lists the same wrapper names +
  `w`; `:24-26` gates on `run-agent-alias.sh` + `wt-archive` in the repo
  root; `:37` compdefs `claude` completion onto the cc\* names.
  `zsh/fpath/_webfront_root:6` repeats the same two-file probe.
- **Hardcoded dotfiles paths (trace "Probe A" set)**:
  `configs/ai/claude-code/skills/agent-orchestration/scripts/cc-worker.sh:36`
  — `ALIASES_FILE="$HOME/.local/dotfiles/scripts/agent-aliases.zsh"` (the
  worst offender per `specs/split-infrastructure-out-of-dotfiles-trace.md:89`);
  `configs/ai/claude-code/skills/agent-orchestration/SKILL.md:28,32-33` and
  `reference/aliases.md:4-6,55-56` document the alias layer's dotfiles
  locations.
- **Docs**: `docs/cli-tools.md:121-130` ("Claude Code routing wrappers"
  section — table of routes, points at `bin/` and
  `configs/ai/claude-code/skills/agent-orchestration/reference/aliases.md`);
  `docs/bash-compatibility.md:72` (agent-aliases.zsh zsh-only constructs),
  `:313` ("the 179-line agent-alias set (`09_claude_code_aliases.zsh:5`)"),
  `:322` (`09_claude_code_aliases.zsh:28` stty restore);
  `configs/ai/opencode/opencode.json:4` references the alias file's model
  pins; `configs/ai/litellm/README.md:306,413,454,489` (retired doc, delete
  with litellm).
- **Censuses**: `docs/fleet-census-installers.md:40` (bin/\* wrappers in the
  repo→`~/.local/bin` row, cites `21_bash_symlinks.zsh:22,27`);
  `docs/fleet-consolidation.md:274` (move-table row);
  `specs/split-infrastructure-out-of-dotfiles-trace.md:82,89,183`.

### 1.2 LLM git workflow — `scripts/commit-conventional`, `scripts/generate-commit-msg`

- **Symlink install**: `scripts/deploy.d/20_symlinks.zsh:77-78` links both to
  `$HOME/.local/bin/`.
- **Git hooks (indirect, no direct exec)**: `scripts/deploy.d/60_git_hooks.zsh:6,10`
  symlink `scripts/post-merge` + `scripts/pre-commit` into `.git/hooks/`.
  Neither hook *runs* generate-commit-msg; both carry it as the canonical
  symlink-walk pattern citation — `scripts/pre-commit:18-19`,
  `scripts/post-merge:22-24` — as do `scripts/deploy.d/lib/helpers.zsh:11`,
  `scripts/enforce-codex-defaults.zsh:33`, `scripts/install-wtp.zsh:20`,
  `scripts/secrets-render.zsh:124`, `bash/env.sh:11`, `deploy.bash:96`.
  Those comment citations must be repointed (or the walker extracted) after
  the move.
- **Tests**: `scripts/tests/test-extract-secret.sh:6,21` exercises
  `extract_secret()` **inside** `scripts/generate-commit-msg` by path — the
  test moves with the script (prior attempt deleted it from dotfiles).
- **Secrets data coupling (cross-repo)**: `generate-commit-msg` reads
  rendered secret state files at
  `${XDG_STATE_HOME:-…}/secrets/zsh/90_secrets.zsh` and `92_telemetry_secrets.zsh`
  and extracts `CEREBRAS_API_KEY` (quote-format-coupled sed — history in
  `plans/ralplan-secrets-repo-migration.md:41,63,179-181`). Moving the script
  to the agents repo preserves this only if the rendered state paths stay
  where the secrets repo's renderer puts them (`scripts/secrets-render.zsh`
  rows) — i.e. the agents repo's copy consumes secrets-repo output it does
  not own.
- **Docs**: `docs/cli-tools.md:65-67` (all three git-workflow tools incl.
  `rewrite-commits-conventional`); `CLAUDE.md:42,91,143,181-182` cites
  `generate-commit-msg` as the canonical portable symlink walk and
  `strip_fences` awk pattern; `docs/bash-compatibility.md:254,368,394`;
  `docs/bash-compat-plans.md:144`.
- **Sibling script**: `scripts/rewrite-commits-conventional` is the bulk
  twin (`docs/cli-tools.md:67`) — not on the handover's move list; the prior
  attempt moved it. Decide explicitly.
- **Censuses**: `docs/fleet-census-installers.md:40`;
  `docs/fleet-consolidation.md:275`.

### 1.3 paseo — `scripts/setup-paseo.sh`, `scripts/paseo-watchdog`

- **Deploy fragment (auto-runs on every fleet pull — highest-risk consumer)**:
  `scripts/deploy.d/81_paseo_providers.zsh:19-20` reads the template
  `$SCRIPT_DIR/configs/ai/paseo/providers.json` and merge tool
  `$SCRIPT_DIR/scripts/paseo-providers.py`; `:38` runs the merge. The
  fragment and its inputs must move (or be delegated to the agents repo's
  deploy) **together**, or the fragment breaks the whole fleet's next
  auto-deploy.
- **Watchdog coupling**: `scripts/setup-paseo.sh:608` installs the launchd
  job running `dotfiles/scripts/paseo-watchdog` directly (census:
  `docs/fleet-census-units.md:47`, heredoc `:618-679`, runs at `:608,627`);
  live Mac plists point at the dotfiles path — moving the script strands
  them (live-ops follow-up, like the litellm one).
- **Config tool**: `scripts/setup-paseo.sh:113` —
  `CONFIG_TOOL="$SCRIPT_DIR/paseo-config.mjs"` (sibling, not on the move
  list; `docs/paseo.md:732` documents it).
- **mise pin lockstep**: `configs/mise.toml:112-117` — comment says the mise
  `paseo` pin must stay in sync with the version `setup-paseo.sh` writes
  into the daemon unit. Splitting them across repos turns that comment into
  a cross-repo invariant (flag in both repos).
- **Shell helpers**: `zsh/rc.d/12_paseo.zsh:4,26` (paseo-at/paseo-ceres/
  paseo-hosts wrappers; version-lockstep comment); `bash/rc.d/10_paseo.bash:1`
  (bash twin). `scripts/setup-paseo.sh:12,848` references the rc.d helpers.
- **Docs**: `docs/paseo.md` is the 740-line runbook — `:72,113,139,146-148,
  220,259,269,322,331,423,436,446-448,486,613,627,648,659,693,731-739` all
  cite the dotfiles paths of `setup-paseo.sh`/`paseo-watchdog`/
  `paseo-config.mjs`; it moves or gets rewritten with the scripts (prior
  attempt moved it). `README.md:212` links both script and runbook;
  `AGENTS.md:36` names `setup-paseo.sh` a model service installer;
  `docs/cli-tools.md:119,213`; `docs/immich.md:139`;
  `scripts/deploy.d/75_brew_setup.zsh:425` (cross-ref comment);
  `configs/ai/paseo/providers.json:4` self-documents the merge pipeline.
- **Censuses**: `docs/fleet-census-units.md:45-47,114`;
  `docs/fleet-census-installers.md:41`;
  `docs/fleet-consolidation.md:276`.
- **Concurrent-edit warning (handover §Hard rules)**:
  `scripts/setup-paseo.sh` has **uncommitted changes in the main checkout**
  from another live session — the owner must reconcile before merge.

### 1.4 portkey — `configs/ai/portkey/` (incl. `portkey-gateway.service`)

- **Symlink install**: `scripts/deploy.d/20_symlinks.zsh:133` links the unit
  into `~/.config/systemd/user/` **unconditionally** (lands inert on the
  Macs — `docs/fleet-census-units.md:20`, trace `:46`).
- **Unit-internal hardcoded paths**: `configs/ai/portkey/portkey-gateway.service:9`
  (`WorkingDirectory=%h/.local/dotfiles/configs/ai/portkey`),
  `:24-25` (`ExecStartPre` guards + a `conf.json` symlink bootstrap pointing
  into the dotfiles checkout) — the unit **breaks on any path change**.
- **Alias-layer consumer**: `scripts/agent-aliases.zsh:14-15` (state dir +
  config-file default into the dotfiles checkout), `:18-174` portkey helper
  family, `:304,458,498,537,581` per-alias header injection;
  `configs/ai/claude-code/skills/agent-orchestration/reference/aliases.md:6,26`.
- **rc.d runtime glue**: `zsh/rc.d/11_portkey.zsh:3,7` (fleet alias
  substrate), `:19-21` (service start/stop glue; census cites `:301,761` for
  runtime control), `:18` hostname gate (trace `:39`).
- **Secrets render rows (stays in dotfiles)**: `scripts/secrets-render.zsh:215-216`
  — `services/portkey/env.yaml` → `$STATE_HOME/portkey/env`,
  `services/portkey/local-api-key.enc` → `$STATE_HOME/portkey/local-api-key`
  (state, not repo paths — safe under a move, but the *consumers* of those
  tokens move).
- **Docs**: `README.md:87`; `AGENTS.md:32`;
  `docs/bash-compat-plans.md:125`; `docs/fleet-census-units.md:20`;
  `specs/secrets-repo-migration.md:58,83`; litellm README's portkey
  comparisons (`configs/ai/litellm/README.md:489` — deleted with litellm).
- **SPEC CONFLICT (must be resolved by owner, flagged per handover §4)**:
  `specs/split-infrastructure-out-of-dotfiles-spec.md:54` (constraint 14)
  rules portkey **two-homed**: zsh CLI + aliases + fleet wiring → agents
  repo, but "`portkey-gateway.service` + `config.json` + state → **infra
  repo**, manifest-gated to ceres". Acceptance criterion `:75` repeats it.
  The handover's move table instead sends all of `configs/ai/portkey/`
  (incl. its `.service`) to the agents repo, and
  `docs/fleet-consolidation.md:277` says "configs + unit" move. The
  handover's own instruction: where it conflicts with the spec, follow the
  spec and flag. Either ruling works, but `fleet-consolidation.md`
  (2026-09-08, owner-decided) postdates the spec (2026-09-04) — likely the
  newer ruling stands; get it in writing in the report.
- Also note: spec `:54` and trace `:39,46` cite the unit symlink at
  `20_symlinks.zsh:126`; at HEAD it is `:133` (doc drift, fix opportunistically).

### 1.5 openclaw-mcp — `configs/openclaw-mcp/`

- **Symlink install (ceres-gated)**: `scripts/deploy.d/20_symlinks.zsh:142-144`
  (`hostname -s == ceres`), with the rationale comment `:134-141`.
- **Secrets coupling (rendered EnvFile — never moves)**:
  `scripts/deploy.d/20_symlinks.zsh:138-141` documents it;
  `scripts/secrets-render.zsh:212,217` — `services/openclaw/env.yaml` →
  `~/.config/openclaw-mcp/env`, gate `ceres`. The render row itself belongs
  to dotfiles/secrets-repo seam and must keep working when the unit moves.
- **Unit-internal path**: `configs/openclaw-mcp/openclaw-mcp.service:3` —
  `Documentation=file:%h/.local/dotfiles/docs/caddy-ingress.md` (dangling
  doc link after the move).
- **Caddy coupling (stays in dotfiles)**: `configs/caddy/Caddyfile:49,59`
  routes `mcp.ceres.webfront.app` → `localhost:3111`;
  `docs/caddy-ingress.md:39` documents the route and its owner.
- **Docs**: `docs/immich.md:141` lists the dir among ceres-served configs;
  `docs/fleet-census-units.md:21`;
  `docs/fleet-consolidation.md:278`.
- **Unrelated same-name items (do NOT move)**: `bash/rc.d/05_aliases.bash:52`
  `openclaw` docker alias, `.default-npm-packages:24-43` openclaw
  exclusion comment, `configs/mise.toml:15-20`, `scripts/deploy.d/50_mise.zsh:118-157`
  openclaw-gateway restart logic — all refer to the hart-owned
  `openclaw-gateway` on ceres, not the MCP bridge.

### 1.6 codexbar / llm-quota — `configs/ai/codexbar/`, `scripts/setup-llm-quota.sh`

- **Symlink install (ceres-gated)**: `scripts/deploy.d/20_symlinks.zsh:152-158`
  (four units: `codexbar-serve.service`, `ntfy-server.service`,
  `codexbar-quota-cues.service`, `codexbar-quota-cues.timer`), rationale
  comment `:145-151`.
- **Second install mechanism (double-wiring!)**:
  `scripts/setup-llm-quota.sh:100-106` re-links and `enable --now`s the same
  units — `docs/fleet-census-units.md:22-24` flags "two independent
  mechanisms for the same units". The hand-run installer moves with the
  units; the deploy-side symlink line moves to the agents repo deploy; they
  must stay consistent.
- **Unit-internal hardcoded path**:
  `configs/ai/codexbar/codexbar-quota-cues.service:8` —
  `ExecStart=/usr/bin/python3 %h/.local/dotfiles/scripts/codexbar-quota-cues.py`.
  The **live ceres timer execs the dotfiles path**; moving the script
  without updating + re-linking the unit breaks quota cues (live-ops
  follow-up: `systemctl --user daemon-reload` + unit refresh on ceres —
  human-run).
- **Installer path bindings**: `scripts/setup-llm-quota.sh:18-19`
  (`DOTFILES=…`, `UNITS_SRC="$DOTFILES/configs/ai/codexbar"`), `:8,117`
  (self-documenting usage lines), `:51` reads the z.ai key from
  `~/.openclaw/.env` (openclaw coupling), `:62-69` generates state secrets.
- **Cue engine**: `scripts/codexbar-quota-cues.py` — companion script not on
  the handover's move list but referenced by the unit ExecStart and
  `docs/llm-quota.md:7,39`; moves with the stack (prior attempt moved it).
- **Docs**: `docs/llm-quota.md` — the whole runbook (`:7,38-46,129,146,
  155-158,179,206`); prior attempt moved it. `README.md:213`;
  `docs/cli-tools.md:215`; `docs/caddy-ingress.md:41-42` +
  `configs/caddy/Caddyfile:94` (usage/ntfy DNS → ceres backends);
  `docs/fleet-census-units.md:22-25`.
- **Censuses**: `docs/fleet-census-installers.md:41`;
  `docs/fleet-consolidation.md:279`.

### 1.7 codex config — `configs/ai/codex/`

- **Symlink install**: `scripts/deploy.d/20_symlinks.zsh:100-104` (config.toml,
  agents, prompts, rules, skills → `~/.codex/`).
- **git clean-filter triple (the risky coupling)**:
  `.gitattributes:1` — `configs/ai/codex/config.toml filter=codex-clean`;
  `scripts/deploy.d/60_git_hooks.zsh:13-23` —
  `git config filter.codex-clean.clean 'node scripts/codex-config-clean.mjs'`
  (per-clone, reasserted on every deploy);
  `scripts/codex-config-clean.mjs` — the filter body. Split spec acceptance
  (`specs/split-infrastructure-out-of-dotfiles-spec.md:82`) names this seam:
  "60_git_hooks.zsh:13-23 (codex filter moves to agents repo)". The
  `.gitattributes` entry, the mjs, and the new repo's own hook wiring must
  move **as a set** or the config's vendor-write-through churn
  (trace `:84`: #1 churn file, 45 touches/12mo) lands as unfiltered diffs.
- **pre-commit exec**: `scripts/pre-commit:42` —
  `exec "$SCRIPT_DIR/enforce-codex-defaults.zsh" --git-add`; the enforcer
  exists to fight the Codex CLI writing into tracked config
  (`specs/split-infrastructure-out-of-dotfiles-trace.md:84`). Moving
  `configs/ai/codex/` out of dotfiles removes the *reason* for the dotfiles
  hook leg — the check belongs in the agents repo's pre-commit (prior
  attempt moved both the enforcer and rewrote `scripts/pre-commit`).
- **Dirs**: `scripts/deploy.d/10_dirs.zsh:12` mkdirs `~/.codex` (plus
  `.claude`, `.codewhale`, `.agent-orchestrator`, `.gjc/agent`) — spec
  acceptance `:82` names `10_dirs.zsh:11-12` as a seam to cut.
- **Unit-internal path**: `configs/ai/codex/rules/default.rules:2` allowlists
  `/home/ctaylor/.local/dotfiles/.claude/skills/skill-builder/...` (stale
  host-specific path; fix during move per spec constraint 15,
  `specs/split-infrastructure-out-of-dotfiles-spec.md:55`).
- **Docs**: `README.md:82`; `AGENTS.md:32`;
  `docs/llm-quota.md:22` (`~/.codex/auth.json` consumer);
  `configs/ai/agents/skills/resolve-conflicts/SKILL.md:318` (~/.codex/skills
  symlink AC).
- **Concurrent-edit warning (handover)**: `configs/ai/codex/config.toml` has
  uncommitted changes in the main checkout — owner reconciles before merge.

### 1.8 ccr-router — `configs/ai/ccr-router/` (move + retirement-candidate flag)

- **No deploy wiring at all**: no `20_symlinks` line, no fragment —
  "unreferenced by any fragment" (`specs/split-infrastructure-out-of-dotfiles-trace.md:46`,
  census `docs/fleet-census-units.md:121`).
- **Stale internal path**: `configs/ai/ccr-router/config.json:6` —
  `CUSTOM_ROUTER_PATH: /home/ctaylor/.local/dotfiles/configs/ccr-router/custom-router.js`
  (pre-`configs/ai/` path; already broken — evidence for the retirement
  flag).
- **Shell-side legacy flag**: `zsh/env.d/11_ccr_default.zsh:1-14` (`USE_CCR=0`
  rollback default; per-alias overrides). Part of the alias layer's story.
- **litellm entanglement**: `configs/ai/ccr-router/ccr-router.service:3-4`
  (`Wants=litellm-proxy.service`), `config.json:7,10-36` +
  `custom-router.js:14-21` route through LiteLLM (`LITELLM_MASTER_KEY`).
  With litellm retired (Task 3) the router's default config is dead weight —
  the retirement candidate flag is well-founded.
- **Docs**: `README.md:88`; `AGENTS.md:32`;
  `docs/fleet-census-units.md:121`;
  `docs/fleet-consolidation.md:277`.

### 1.9 "Assess each" — remaining `configs/ai/*` at HEAD

`configs/ai/` at HEAD contains 12 subdirs; explicit rows above cover
ccr-router, codex, codexbar, litellm (delete), paseo, portkey. Remaining six
(+ the `agents/` dir), with their consumers for the line-test call:

- **`configs/ai/agent-orchestrator/`** — links:
  `scripts/deploy.d/20_symlinks.zsh:43-45` (config.yaml → XDG + two
  `$HOME/.agent-orchestrator*` paths); completions autoloaded by
  `zsh/rc.d/14_agent_orchestrator.zsh:6` (`$DOTFILES/configs/ai/agent-orchestrator/completions`
  — hardcoded `$DOTFILES`), `:3` exports `AO_GLOBAL_CONFIG`; dirs mkdir'd at
  `scripts/deploy.d/10_dirs.zsh:11-12`; docs `README.md:86`, `AGENTS.md:32`,
  `docs/cli-tools.md` (tool list), census installers `:41`. Line test: fails
  (pure agent tooling) → move.
- **`configs/ai/agents/`** (shared skills tree) — linked wholesale to
  `$HOME/.agents` at `scripts/deploy.d/20_symlinks.zsh:46`. Coupled to gjc:
  `configs/ai/gjc/config.yml`'s `skills.customDirectories` points at
  `~/.agents/skills` (`20_symlinks.zsh:120-130` comment block explains the
  bridge + the do-not-shadow rule); `configs/ai/agents/skills/gjc-orchestration/SKILL.md:10`
  names its canonical dotfiles path. Spec constraint 6
  (`specs/split-infrastructure-out-of-dotfiles-spec.md:46`) explicitly lists
  `~/.agents` as agents-repo symlink territory (write-through quarantine).
  Line test: fails → move (this is the spec's AgentsRepo core,
  `specs/split-infrastructure-out-of-dotfiles-spec.md:105`).
- **`configs/ai/claude-code/`** — nine links at
  `scripts/deploy.d/20_symlinks.zsh:80-98` (CLAUDE.md, settings.json,
  settings.local.json, statusline, hooks, skills, commands, agents,
  .mcp.json → `~/.claude/`); stale-link cleanup `:82-90`; dir mkdir
  `10_dirs.zsh:12`; consumers of the alias layer live inside it
  (cc-worker.sh, agent-orchestration skill — §1.1); `README.md:81`;
  `docs/cli-tools.md:126`. Line test: fails → move. (`.claude/` is also
  gitignored at HEAD `.gitignore:23` — repo hygiene note.)
- **`configs/ai/codewhale/`** — links `20_symlinks.zsh:106-108`;
  `configs/ai/codewhale/config.toml:7` embeds a macOS
  `/Users/ctaylor/.local/dotfiles` projects path (fix on move);
  installer stays: cargo block
  `scripts/deploy.d/70_runtime_installs.zsh:209-238`; `configs/mise.toml:42,102`
  comments. Line test: fails → move config.
- **`configs/ai/gjc/`** — links `20_symlinks.zsh:118-124` (+ the `:111-117`
  write-through comment); secrets row
  `scripts/secrets-render.zsh:224-231` (`services/gjc/env.yaml` →
  `~/.gjc/agent/.env` — render row stays in dotfiles); installer stays:
  bun global `scripts/deploy.d/70_runtime_installs.zsh:123-175`;
  provider merge consumer: `scripts/deploy.d/81_paseo_providers.zsh:1-14,38`
  (reads `~/.gjc/agent/.env`); skills coupling via `~/.agents` (above);
  `README.md` (gjc row), `docs/cli-tools.md`. Line test: fails → move config.
- **`configs/ai/opencode/`** — link `20_symlinks.zsh:110`; env fragment
  `zsh/env.d/10_opencode.zsh:1-2`; completion generator
  `scripts/deploy.d/82_zsh_completions.zsh:32` (installer-layer, stays);
  `configs/ai/opencode/opencode.json:4` references the alias layer's model
  pins; npm global `opencode-ai` in `.default-npm-packages:8` (stays);
  `README.md:85`. Line test: fails → move config.
- **`configs/ai/paseo/`** — providers.json template consumed by
  `scripts/deploy.d/81_paseo_providers.zsh:19` (§1.3); moves with the paseo
  stack.
- **`configs/ai/litellm/`** — Task 3 **delete, do not move**. Consumers of
  the deletion: `README.md:52,88` (prose), `AGENTS.md:32` (placement-table
  list), census rows `docs/fleet-census-units.md:27,121`,
  `docs/fleet-census-installers.md` (unreferenced-class note);
  `configs/ai/litellm/README.md:22-25` falsely claims deploy.zsh symlinks it
  (dies with the dir); ccr-router references (§1.8) become dead config —
  part of the retirement case. Live-ops (NOT ours): makemake dangling
  `~/.config/systemd/user/litellm-proxy.service` symlink
  (`docs/fleet-consolidation.md:197`; trace `:46,57`;
  `plans/ralplan-infra-repo.md:46`).

Also webfront-class dotfiles leftovers for Task 3's "list what you find":
`bin/webfront-root`, `bin/p` (webfront plan/worktree shortcut,
`bin/p:7-12`), `zsh/fpath/_webfront_root`, `zsh/fpath/w` (wtp wrapper,
generic), `zsh/rc.d/23_webfront_wrappers.zsh`, `configs/caddy/Caddyfile:49-68`
(mcp.ceres.webfront.app route), `docs/caddy-ingress.md:39`,
`bin/ccd:10`/`bin/ccd-happy:7` error strings, `configs/portless/`
(webfront-adjacent proxy, `scripts/deploy.d/70_runtime_installs.zsh:32`
npm:portless note), `docs/fleet-declarability-options.md:150` (webfront
postgres mention). None is a live webfront *deployment* in dotfiles; the
wrappers are compat shims for webfront-shaped repos.

## 2. bin/ classification (all 21 entries at HEAD)

| Entry | Class | Justification |
|---|---|---|
| `bag` | **generic** | rg/ag → fzf → `$EDITOR` source-search QoL; no agent involvement (`bin/bag:1-5`). |
| `cc` | **agent-routing** | plain-Anthropic `claude` launcher; fleet env-unset fallback + webfront dispatch (`bin/cc:9-16`). |
| `ccd` | **agent-routing** | DeepSeek `claude` route with zsh-only Portkey fallback (`bin/ccd:5-13`). |
| `ccd-direct` | **agent-routing** | direct DeepSeek route, execs `run-agent-alias.sh ccd-direct` (`bin/ccd-direct:16`). |
| `ccd-direct-happy` | **agent-routing** | ditto, happy runtime (`bin/ccd-direct-happy:16`). |
| `ccd-happy` | **agent-routing** | DeepSeek happy route, Portkey-fallback error string (`bin/ccd-happy:7-10`). |
| `ccfw-direct` | **agent-routing** | Fireworks direct route via portkey headers (`bin/ccfw-direct:4,19`). |
| `ccm-direct` | **agent-routing** | MiniMax direct route (`bin/ccm-direct:4,15`). |
| `ccm-direct-happy` | **agent-routing** | ditto (`bin/ccm-direct-happy:16`). |
| `ccz-direct` | **agent-routing** | Z.AI GLM direct route (`bin/ccz-direct:4,16`). |
| `ccz-direct-happy` | **agent-routing** | ditto (`bin/ccz-direct-happy:17`). |
| `yolo` | **agent-routing** | unguarded agent invocation, execs `run-agent-alias.sh yolo` (`bin/yolo:4,15`). |
| `disable-agents-slice-hook` | **generic** | cgroup-slice recovery shim; "agents.slice" is a systemd cgroup, not the AI layer — spec constraint 7 keeps the cluster in dotfiles (`specs/…spec.md:47`). |
| `fgb` | **generic** | fzf git-branch selector (`bin/fgb:1-3`). |
| `fgd` | **generic** | fzf git-diff browser (`bin/fgd:1-3`). |
| `fgl` | **generic** | fzf git-log browser (`bin/fgl:1-3`). |
| `install-agents-slice.sh` | **generic** | generates `agents.slice` (MemoryMax); cgroup cluster, stays (`specs/…spec.md:47`; `docs/cli-tools.md:218`). |
| `lspath` | **generic** | path-permission listing QoL (`bin/lspath:1-4`). |
| `p` | **webfront-class, not agent-routing** | plan/worktree shortcut requiring a webfront-shaped repo (`bin/p:7-12`); webfront is retired → explicit keep/move/retire call needed. |
| `psg` | **generic** | ps grep pager (`bin/psg:1-3`). |
| `webfront-root` | **shared dispatcher** | repo-class probe used by BOTH moving `cc*` and staying `p` (`bin/webfront-root:6-8`); webfront-retired but the compat shim outlives the retirement — the prior attempt kept it and repointed its comment at the agents sibling. |

zsh-only twins of the same routing class (fpath, move with the layer):
`zsh/fpath/ccm`, `ccm-happy`, `ccz`, `ccz-happy` (autoloaded at
`zsh/rc.d/04_autoload.zsh:47`); `_webfront_root` is the dispatcher twin.

## 3. Reserved slot convention — documented quotes (90–99 / 96–99)

The handover cites "AGENTS.md:134-149"; at HEAD that range has drifted —
the relevant content is:

- `AGENTS.md:127-142` (TODO: infra carve-out) — the **triple convention**:
  "keep new infra to the `configs/<service>/` + `scripts/setup-<service>.sh`
  + `docs/<service>.md` triple so the eventual move is a `git mv`, not a
  rewrite" (`:140-141`); the placement table row repeating it: `AGENTS.md:36`.
- `AGENTS.md:39` — "`zsh/env.d/89_secrets_loader.zsh` — which is numbered 89
  so a deliberate local `90-99` override still sorts after it and wins."
- `AGENTS.md:73` — "Local overrides: 90-99 prefix files are gitignored
  (zsh/env.d/, zsh/rc.d/, nvim/init/)".
- `AGENTS.md:83` — numbering table row: "| 90-99 | Local overrides
  (gitignored, can be encrypted) |".
- `zsh/AGENTS.md:13` — "`90-99` — local overrides (gitignored)".
- `.gitignore:10-11` — the enforcement: `zsh/rc.d/9[0-9]_*`,
  `zsh/env.d/9[0-9]_*` (and `nvim/init/9[0-9]_*` at `:8`).
- `zsh/env.d/89_secrets_loader.zsh:10` — "first, then any deliberate local
  90-99 override still wins by sorting after".
- `specs/split-infrastructure-out-of-dotfiles-spec.md:51` (constraint 11) —
  "the agents repo integrates via symlinked fragments in the existing
  gitignored 90–99 `rc.d`/`env.d` slots; all hooks no-op gracefully when
  siblings are absent."
- `specs/split-infrastructure-out-of-dotfiles-spec.md:105` — AgentsRepo
  entity: "symlink-deployed; receives write-through; hooks into Dotfiles
  90–99 slots".
- `specs/split-infrastructure-out-of-dotfiles-spec.md:159` — "Dotfiles
  bootstraps + 90–99 drop-in slots".
- `docs/fleet-consolidation.md:282-285` — the operative 96–99 refinement:
  "dotfiles keeps its gitignored numbered slots (rc.d/env.d 90–99 local,
  **96–99 agents hooks**), and the agents repo's deploy drops fragments into
  them — dotfiles never sources the agents repo directly."

Net contract for the implementer: the agents repo's deploy **links** its env
fragment (the alias layer) into a `9[6-9]_*` slot under `zsh/env.d/` (and
rc.d if needed); dotfiles' existing glob loaders pick it up with zero
dotfiles-side sourcing; loaders must no-op when absent (they already do —
the loaders glob, they don't hardcode). Note the prior attempt's
`67_agents.zsh` passes `DOTFILES_DIR` explicitly to the sibling deploy for
exactly this slot wiring.

## 4. Risk couplings (move-list items whose consumers make the move risky)

1. **portkey (spec conflict + unit paths)** — spec constraint 14
   (`specs/…spec.md:54`) sends the service + config.json + state to the
   *infra* repo; handover/fleet-consolidation send them to agents. Owner
   must rule. Independently: `portkey-gateway.service:9,24-25` hardcode
   `%h/.local/dotfiles/…` paths — any move rewrites the unit and the alias
   layer's config default (`scripts/agent-aliases.zsh:15`).
2. **codex config (git-filter triple)** — `.gitattributes:1` +
   `60_git_hooks.zsh:13-23` + `scripts/codex-config-clean.mjs` +
   `scripts/pre-commit:42`/`enforce-codex-defaults.zsh` form one mechanism;
   partial moves leave dotfiles' per-clone git config pointing at a missing
   filter script, or the agents repo absorbing vendor write-through without
   the filter.
3. **paseo (`81_paseo_providers.zsh` runs on every fleet auto-deploy)** —
   the fragment + `configs/ai/paseo/providers.json` +
   `scripts/paseo-providers.py` must move/delegate atomically or the next
   fleet pull breaks; plus the live watchdog plists exec
   `dotfiles/scripts/paseo-watchdog` (`docs/fleet-census-units.md:47`),
   `configs/mise.toml:112-117` version lockstep crosses repos, and
   `setup-paseo.sh` itself has uncommitted edits in the main checkout
   (handover §Concurrent-edit warning).
4. **codexbar (live unit exec path + double install)** —
   `codexbar-quota-cues.service:8` ExecStarts the dotfiles script path on
   ceres today; `20_symlinks.zsh:152-158` and `setup-llm-quota.sh:100-106`
   both install/enable the same units; `setup-llm-quota.sh:18-19` resolves
   units via `$DOTFILES`. Move must update unit + installer together and
   list a ceres live-ops step (daemon-reload, human-run).
5. **`~/.agents` skills tree (three-way gjc coupling)** —
   `20_symlinks.zsh:46` link + gjc `config.yml` `skills.customDirectories`
   (`20_symlinks.zsh:120-130`) + claude-code skills/commands — gjc's
   write-through behavior (`:115-117`) and the do-not-shadow rule move with
   it; a mismatch silently hides skills (gjc precedence diagnostic).
6. **alias layer (many-headed shell wiring)** — `21_bash_symlinks.zsh:23-28`
   list, `04_autoload.zsh:47`, `bash/env.sh:44`, gate exemptions
   `shell-syntax-gate.sh:56-66`, `23_webfront_wrappers.zsh` compdef list,
   and the cc-worker/agent-orchestration hardcoded paths
   (`cc-worker.sh:36` et al.) all change in one commit or interactive
   shells lose routes on both shell families.
7. **openclaw-mcp (secrets seam)** — the EnvFile is rendered by
   `secrets-render.zsh:217` into `~/.config/openclaw-mcp/env`; the unit
   moves but the render row and its ceres gate stay with dotfiles —
   documented linkage at `20_symlinks.zsh:138-141` must survive the move or
   the next render/report misleads.
8. **generate-commit-msg (cross-repo data dependency)** — reads rendered
   secrets state (`plans/ralplan-secrets-repo-migration.md:63,179-181`);
   after the move the agents repo consumes files whose renderer and gate
   table live in dotfiles. Keep the extraction quote-agnostic contract.
9. **`bin/webfront-root` + `p` (shared dispatcher, retirement ambiguity)** —
   webfront is retired (Task 3) but `p` (staying per this classification)
   depends on `webfront-root` (and webfront-shaped repos' scripts). Any
   split of the pair across repos breaks `$(dirname "$0")` sibling
   resolution (`21_bash_symlinks.zsh:20-22` documents the pairing
   invariant).

## 5. Verification hooks the implementer must re-run (from CLAUDE.md)

- `scripts/tests/shell-syntax-gate.sh --all` (exemption list shrinks —
  `:56-66` entries move out).
- `diff <(./deploy.zsh --dry-run) <(./deploy.bash --dry-run)` empty modulo
  timestamps; dry-run delta vs pre-change shows only intended deltas.
- The `--staged` gate replay + CI legs (`.github/workflows/shells.yml`).
- Word-list expansion rules (CLAUDE.md dual-shell tables) for any edited
  fragment — the moved symlink lists are array loops
  (`21_bash_symlinks.zsh:23-28` pattern).
