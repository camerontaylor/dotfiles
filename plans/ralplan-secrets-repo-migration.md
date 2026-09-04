# Plan: Migrate secrets out of public dotfiles into a private sops-native secrets repo

Status: **approved** (confirmed 2026-08-25 by Claude, on the user's delegated authority) | Mode: deliberate | Iterations: 3 | Spec: `specs/secrets-repo-migration.md`
Date: 2026-08-25 | Final critic verdict: **APPROVE** (with mandatory amendment, merged below)

---

## RALPLAN-DR

### Principles

1. **Ciphertext is canonical, plaintext is derived — and superseded derived plaintext is quarantined, then destroyed.** No mtime guards; edits via `sops edit`/`sops set`; the renderer writes fresh targets and *moves* legacy plaintexts out of the load path (final purge only after fleet-wide verification).
2. **No plaintext secret value ever enters a repo commit, a log line, or a diagnostic.** Verification compares via `cmp` in 0700 tmpdirs and reports names only; triage of divergent legacy files is by key name, inspected locally.
3. **Every commit boundary is deploy-safe on all four boxes.** Auth readiness is verified mechanically — testing the *actual capability* (private-repo read) — before the cutover commit lands; degraded mode prints instructions and mutates nothing.
4. **Verify before destroy.** Round-trip verification before cutover; move-not-delete for anything the harness could not have verified on that box (all 21 targets, per the mandatory amendment); irreversible steps (purge, rotation) only behind the mechanical 4/4 marker-ancestry gate.
5. **Bootstrap-layer portability is binding** per CLAUDE.md; scripts that also run standalone (renderer via the secrets-repo hook, `generate-commit-msg` under cron) carry no dependency on deploy.zsh's shell state — they self-locate, self-default env vars, and use plain POSIX tools.

### Decision drivers

1. **Non-atomic safety**: the fleet auto-pulls dotfiles unattended (`scripts/post-merge`, periodic pull timer); every intermediate commit runs everywhere with nobody watching the log.
2. **Minimal residual machinery**: the mission is deleting the clobber-guard complexity, not porting it.
3. **Migration verifiability**: 1:1 script-checkable traceability — every old `.enc`, every new secrets-repo file (including unexpected ones), every render target, and every per-box divergence accounted for by name.

### Options

**Contested dimension 1 — cutover sequencing**

- **Option A: dual-path transitional fragment.** New fragment prefers `~/.local/secrets`, falling back to a guard-free ~15-line `.enc`-decrypt shim when the clone is absent (stated honestly: the fallback need not port the mtime guards). Pros: secret updates still propagate to unbootstrapped boxes mid-window. Cons that survive the steelman: two writers to the same targets during the window (a box that cloned successfully, then regressed to fallback on a transient auth failure, would overwrite fresh renders with stale `.enc` content — the exact clobber class being eliminated); and the legacy-plaintext quarantine logic becomes mode-dependent, since the fallback *recreates* the very files the new flow must remove.
- **Option B (chosen): hard cut in code, staged removal of data, with mechanical pre-flight and quarantine.** The fragment knows only the new flow. The iteration-1 weakness (freeze as policy; unverified auth to a *private* repo — today no box needs authenticated GitHub access to deploy, `scripts/deploy.d/50_mise.zsh:88-92` is opportunistic) is closed by Phase 2.5's capability-testing pre-flight before the Phase-3 commit exists. The iteration-2 weakness (irreversible `rm -f` of files the harness never verified on 3 of 4 boxes) is closed by move-to-quarantine with gated purge, extended by the mandatory amendment to a first-render backup of *all* pre-existing divergent targets. Boxes keep working meanwhile: rendered plaintexts persist on disk and degraded mode touches nothing.

**Chosen: B.** With pre-flight, B's distribution-gap con shrinks to a same-day verified-closable window; A's two-writers hazard and mode-dependent quarantine remain intrinsic. Driver 2 decides it.

**Contested dimension 2 — renderer mapping location**

- **Option C (chosen): hardcoded mapping arrays in `scripts/secrets-render.zsh` (dotfiles).** Pros: mirrors the proven `restore-secrets.zsh` pattern; pure-zsh, BSD-clean; target paths are machine concerns already public in current scripts. Con (unknown files silently ignored) is mitigated directly: the renderer diffs `git -C ~/.local/secrets ls-files` against its mapped-source array plus an allowlist and warns by name, so driver 3 holds for unknown files too.
- **Option D: manifest file in the secrets repo** parsed by the fragment. Pros: one-repo additions. Cons: invents a format plus a portable parser in the bootstrap layer (the word-splitting/quoting hazard class CLAUDE.md exists to prevent); moves machine-side target paths into the wrong repo; malformed manifest bricks rendering.
- **Chosen: C + unmapped-file detection.** Driver 2 and portability burden decide; secret additions are ~2/year.

### Pre-mortem (it's 6 months later and this failed because…)

1. **"…a quoting bug in the dotenv→zsh conversion — or a quote-format-coupled consumer — silently corrupted or lost a value."** Nearly shipped in iteration 1: `scripts/generate-commit-msg:157` extracts `CEREBRAS_API_KEY` with double-quote-only sed and `:183-184` strip only `"` — the renderer's `${(qq)}` single-quoted output would have broken both in hook/cron contexts the day legacy plaintexts left the tree. The plan: the Phase-3 commit rewrites both extractions quote-agnostic (BSD-sed portable), with unit fixtures in all three quoting styles and an e2e running the real extraction code against real renderer output.
2. **"…a box's local hand-edits were destroyed by the cutover."** The iteration-2 near-miss: `rm -f` of the seven legacy env.d plaintexts would have run on saturn/neptune/quaoar where the harness never verified anything — and divergence is not hypothetical: `scripts/deploy.d/65_sops.zsh:61-64` documents hand-edit clobbering (of `ssh/config`) as a real past bug, and `scripts/deploy.d/73_tailscale.zsh:5-12` documents per-box knobs (`TAILSCALE_ADVERTISE_ROUTES` on the LAN-router host) living in one of those seven files. The plan: the renderer **moves** the seven files to a 0700 quarantine dir instead of deleting; the mandatory amendment additionally backs up *every* pre-existing divergent target on a box's first render; Phase 4 triages any divergence per box into the secrets repo or a deliberate local override (`96_local_tailscale.zsh`); Phase 5 purges quarantine only after the 4/4 ancestry gate.
3. **"…a box's GitHub auth rotted post-migration and it exported eventually-revoked values forever, with only an unread log line."** The chronic-staleness antithesis: after cutover, a box whose `gh` keyring or ssh key stops working keeps rendering nothing while its last-rendered files age indefinitely. The plan: beyond the marker-ancestry audit at rotation time, a small interactive-only `zsh/rc.d` fragment prints a one-line warning in every new shell when `secrets-render-ok` is missing or older than 14 days — moving the signal from the unread deploy log to the user's face.

### Expanded test plan

- **Unit**: dotenv→zsh converter against a synthetic throwaway-age-key fixture YAML with hostile values (embedded `'`, `"`, `$`, spaces, `=`); assert `zsh -f -c 'source out; print -rn -- $KEY'` round-trips. Quote-agnostic extraction functions in `generate-commit-msg` tested against fixtures in all three quoting styles (`KEY=v`, `KEY="v"`, `KEY='v'`). `zsh -n`/`bash -n` on every changed script; word-splitting arg-count checks per CLAUDE.md.
- **Integration** (ceres, pre-cutover): Phase-2 harness runs the full mapping — decrypt/render into a 0700 tmpdir; byte-`cmp` for blobs/copies, env-set compare for the 7 shell files, decrypt+PEM-well-formedness for portless; a missing live target is a named failure, never a silent skip. Fragment `--dry-run` mutates nothing (including no quarantine moves, no backups).
- **E2E**: degraded simulation (clone and gh auth masked) → green deploy, instruction banner, zero mutation; clone-from-scratch with the gh→ssh fallback chain exercised (mask gh only); ff-only divergence → warn + render from stale checkout; age-key-absent; standalone renderer run via the secrets-repo post-merge hook path (no deploy shell state) → correct self-location and render; first-render backup case (marker absent + hand-modified `ssh/config` → old bytes deposited in `legacy-removed/`; marker present → no backups); fixture e2e for `generate-commit-msg` extraction against real renderer output plus a cron-env smoke run (`env -i …`); non-interactive-context check on one box per OS family: trigger the periodic/auto-pull path (systemd-run / launchd) and confirm `65_secrets` still pulls — surfaces both macOS locked-keychain `gh` false-failures and a missing `github.com` known_hosts entry stalling `ls-remote`.
- **Observability**: fragment logs `rendered N, quarantined M, unmapped U, failed K` (names only); `secrets-render-ok` records UTC timestamp + dotfiles HEAD + secrets HEAD for one-liner fleet audits; interactive staleness warning (pre-mortem 3); deploy log tees to `$XDG_STATE_HOME/dotfiles-deploy.log`. Production signals: env keys present in new shells, portkey/openclaw/immich units green after next timer, secrets-repo log advancing on all boxes.

---

## Plan

### Context

The public dotfiles repo tracks 21 sops whole-file `.enc` blobs restored by three overlapping mtime-guarded scripts. The spec (binding) moves secrets to a private sops-native repo `camerontaylor/dotfiles-secrets` cloned at `~/.local/secrets`, encrypted-canonical / rendered-derived. Grounding facts (all codebase-verified across the three review iterations):

- **Inventory (21 files)**: 7 shell env (`zsh/env.d/{90_secrets,91_cloudflare_secrets,92_telemetry_secrets,93_google_oauth_secrets,94_search_secrets,94_zerotier_secrets,95_tailscale_secrets}.zsh.enc`); 5 ssh (`ssh/{config,id_ed25519,id_ed25519.pub,webfront_claw,webfront_claw.pub}.enc`); 2 portkey (`configs/ai/portkey/state/{env,local-api-key}.enc`); 1 openclaw (`configs/openclaw-mcp/env.enc`); 2 immich (`configs/immich/{b2-env,restic-password}.enc`); 4 portless PEMs (`configs/portless/{ca,ca-key,server,server-key}.pem.enc`). No `zsh/rc.d`/`nvim/init` `.enc` exist.
- `configs/mise.toml` already pins `sops`, age, `gh` — **no mise.toml change needed** (spec constraint "new tools via mise.toml" satisfied by inspection).
- All four boxes hold registered age keys (4 recipients in `.sops.yaml`); per-box bootstrap is GitHub auth + first clone only. But today no box *requires* authenticated GitHub access to deploy (`scripts/deploy.d/50_mise.zsh:88-92` is opportunistic) — auth to the private repo is therefore capability-tested, not assumed (Phase 2.5).
- **Direct-path consumers of legacy plaintexts**: `scripts/deploy.d/73_tailscale.zsh:6,22,178` (sources `$SCRIPT_DIR/zsh/env.d/9[0-9]_tailscale_secrets.zsh`); `scripts/generate-commit-msg:155,181` (reads `90_secrets.zsh` / `92_telemetry_secrets.zsh` by path; quote-format-coupled sed at `:157`, `:183-184`).
- **Per-box divergence is documented, not hypothetical**: `65_sops.zsh:61-64` records hand-edit clobbering (of `ssh/config`) as a past bug class; `73_tailscale.zsh:5-12` documents `TAILSCALE_ADVERTISE_ROUTES` (LAN-router host only) and `TAILSCALE_EXTRA_ARGS` as per-box knobs read from a fleet-tracked secrets file — a box's local plaintext can legitimately be newer/different than the shared ciphertext.
- **Shadowing hazard**: `zsh/.zshenv:65-72` sources `env.d/*` lexically; stale gitignored `9[0-5]_*` plaintexts sort after the new `89_secrets_loader.zsh` and would shadow rotated values — they must leave `env.d/`.
- **Portless correction**: nothing currently decrypts `configs/portless/*.pem.enc`; plaintext PEMs live at `configs/portless/*.pem` (gitignored) behind the `~/.portless` symlink (`scripts/deploy.d/20_symlinks.zsh:105`) and may be absent on any box. The renderer automates this for the first time.
- `20_symlinks.zsh:129` symlinks non-`.enc` `$DOTFILES/ssh/` files into `~/.ssh/`; `65_sops.zsh:70-78` decrypts into `$DOTFILES/ssh/` with 600/644.
- Standalone self-location pattern: `scripts/generate-commit-msg:19-25` (symlink walk); zsh-native equivalent `${0:A:h:h}` + `.homedir` massage at `scripts/save-secrets.zsh:22-27`.
- Repo name: **`dotfiles-secrets`**. **Migration host: ceres** (only box holding every live plaintext — openclaw is ceres-only; portless falls back to `.enc` decryption).

### Objectives

1. Private repo `dotfiles-secrets` holds all secret material: flat sops-YAML for key=value files, sops blobs for opaque material, plaintext for public material and `ssh/config`.
2. Dotfiles deploy clones/pulls `~/.local/secrets`, renders all targets with identical paths/modes/gating, quarantines superseded legacy plaintexts (and backs up any pre-existing divergent target on first render), and detects unmapped files — or degrades to precise instructions mutating nothing.
3. All mtime-guard machinery, `.enc` files, `.sops.yaml`, legacy scripts, and quarantined plaintexts are gone after fleet-verified cutover; per-box knobs preserved as deliberate local overrides.
4. GitHub PAT and Tailscale authkey rotated behind a mechanical fleet-readiness gate; chronic post-migration staleness surfaced in interactive shells.

### Guardrails

**Must have**
- Round-trip verification passes on ceres for all migrated items before Phase 3 lands; missing live targets are named failures.
- Per-box auth pre-flight (actual private-repo read capability) passes and is recorded before the Phase-3 commit; every dotfiles commit leaves `deploy.zsh` green on all boxes.
- Atomic per-target rendering (`mktemp` → `chmod` → `mv`); mid-render failure leaves existing targets untouched and skips the quarantine step entirely.
- **Move-not-delete**: legacy plaintexts are quarantined (0700 dir), and every pre-existing target that differs from its first render is backed up there too (mandatory amendment); purged only in Phase 5 after the 4/4 ancestry gate. Quarantine/backup only on full render success paths, never under `${DEPLOY_DRY_RUN:-0}` == 1 or in degraded mode.
- CLAUDE.md portability on every bootstrap-layer change; renderer standalone-safe: no `zf_*` builtins (plain `install`/`ln -sfn`/`mkdir -p`), explicit `${XDG_STATE_HOME:-$HOME/.local/state}` defaults, self-locates `$DOTFILES` from `$0`.
- `sops-add-recipient.zsh` flow keeps working (relocated, YAML-aware).
- **Managed-shadow invariant (post-Phase-3)**: none of the seven managed basenames exists as plaintext in `$DOTFILES/zsh/env.d/` — enforced by the renderer (quarantines them) and checked by the harness. Deliberate local overrides with *other* basenames (e.g. `96_local_tailscale.zsh`) remain allowed: shadowing by intent is the 90–99 convention's feature; shadowing by staleness is the bug.

**Must NOT have**
- Plaintext secret values in any commit, log, or diagnostic. Implementation reads plaintexts from the deployed checkout on ceres, never a worktree; divergence triage is key-name-based, human-inspected locally.
- Ported mtime/clobber guards.
- New tools in deploy scripts (none needed).
- Public-history purge; merge driver (deferred); ceres bare remote.

### Phase 1 — Create and populate `dotfiles-secrets` (private repo; executed on ceres)

Actions:
1. `gh repo create camerontaylor/dotfiles-secrets --private`; clone to `~/.local/secrets`.
2. Layout and population:

   | New path in `~/.local/secrets` | Form | Source read from (on ceres) |
   |---|---|---|
   | `shell/90_secrets.yaml`, `shell/91_cloudflare_secrets.yaml`, `shell/92_telemetry_secrets.yaml`, `shell/93_google_oauth_secrets.yaml`, `shell/94_search_secrets.yaml`, `shell/94_zerotier_secrets.yaml`, `shell/95_tailscale_secrets.yaml` | sops flat YAML | `~/.local/dotfiles/zsh/env.d/<basename>.zsh` (parse `export KEY=value`, stripping one symmetric quote pair; comments dropped — load-bearing ones become README notes). **Per-box knobs are excluded from the shared YAML**: if ceres's `95_tailscale_secrets.zsh` contains `TAILSCALE_ADVERTISE_ROUTES`/`TAILSCALE_EXTRA_ARGS`, those keys go to a local `96_local_tailscale.zsh` on ceres, not into `shell/95_tailscale_secrets.yaml` (fleet-shared YAML must hold only fleet-shared values; other boxes' local copies are triaged in Phase 4) |
   | `services/portkey/env.yaml` | sops YAML | `~/.local/state/portkey/env` |
   | `services/portkey/local-api-key.enc` | sops blob | `~/.local/state/portkey/local-api-key` (byte-exactness) |
   | `services/openclaw/env.yaml` | sops YAML | `~/.config/openclaw-mcp/env` |
   | `services/immich/b2-env.yaml` | sops YAML | `~/repos/deploy/immich/.b2-env` |
   | `services/immich/restic-password.enc` | sops blob | `~/repos/deploy/immich/.restic-password` |
   | `ssh/config` | plaintext (Q2) | `~/.ssh/config` |
   | `ssh/id_ed25519.enc`, `ssh/webfront_claw.enc` | sops blobs | `~/.ssh/id_ed25519`, `~/.local/dotfiles/ssh/webfront_claw` |
   | `ssh/id_ed25519.pub`, `ssh/webfront_claw.pub` | plaintext | corresponding `.pub` files |
   | `portless/ca-key.pem.enc`, `portless/server-key.pem.enc` | sops blobs | `~/.local/dotfiles/configs/portless/*.pem` if present, else `sops -d` of the corresponding old `.enc` |
   | `portless/ca.pem`, `portless/server.pem` | plaintext | same present-else-decrypt rule |
3. `.sops.yaml`: same 4 age recipients; `creation_rules` `path_regex` covering `shell/.*\.yaml$`, `services/.*\.yaml$`, `.*\.enc$`.
4. `.gitattributes`: `*.yaml diff=sops`, `*.enc diff=sops`.
5. Move + adapt `scripts/sops-add-recipient.zsh` → `~/.local/secrets/scripts/` (re-encrypt list built as a zsh array over `shell/**/*.yaml services/**/*.yaml **/*.enc`; `sops updatekeys` handles YAML natively).
6. `README.md`: layout, edit workflow, new-machine registration, rotation checklist, per-box cutover checklist, **"Cutover pre-flight" dated section (the committed Phase-2.5 pass-record artifact)**, and migration notes including the per-box-knob triage rule (any key found only in a box's quarantined legacy file goes to either the secrets repo via `sops set` or a local `96_local_*.zsh` override).
7. Commit, push. No dotfiles changes this phase.

Acceptance criteria:
- Tracked files are exactly: sops-YAML (`grep -c 'ENC\['` > 0 per encrypted file), sops blobs, and the five deliberate plaintexts; `rg -l 'BEGIN (OPENSSH|EC|RSA) PRIVATE KEY'` over tracked files matches nothing.
- `sops -d` succeeds on every encrypted file with ceres's key; a `sops set` probe+revert changes only that line + `mac`.
- `shell/95_tailscale_secrets.yaml` contains no per-box knob keys (checked by key name).
- Other boxes unaffected (no dotfiles commit).

### Phase 2 — Round-trip verification harness (pinned to ceres)

Actions:
1. New `~/.local/secrets/scripts/verify-render.zsh` (written to bootstrap portability standard). Per mapping row:
   - **Blobs & plaintext copies**: `sops -d`/`cat` into `mktemp -d` (0700), `cmp -s` against the live source. A missing live target/source is a **named failure**, not a skip — ceres pinning guarantees all should exist.
   - **Portless PEMs (exception)**: exempt from mandatory live-`cmp` (nothing decrypts them today; live plaintext may be absent or drifted). Instead: decrypt-success + well-formedness (`openssl x509 -noout -in` for certs, `openssl pkey -noout -in` for keys — BSD/LibreSSL-compatible) + opportunistic `cmp` when a live plaintext exists (mismatch → named warning, human-adjudicated).
   - **Shell YAML**: render using the dotenv→zsh converter **from the migration machine's working (not-yet-committed) checkout of `scripts/secrets-render.zsh`** — stated explicitly to break the apparent circularity: the converter exists as code before it ships. Compare clean-`zsh -f` sourced export sets (old file vs rendered file) for exactly the keys defined, allowing for keys deliberately moved to `96_local_tailscale.zsh` (their union must equal the old file's key set); dumps in the 0700 tmpdir; `cmp -s`; mismatches report key names only.
   - **Dotenv services**: `sops -d --output-type dotenv` vs live file normalized of comments/blanks (`grep -v`, BSD-safe). Any value sops's dotenv output would alter demotes that file to a blob, decided by the harness.
   - Managed-shadow invariant check (post-Phase-3 mode flag): fail by name if any of the 7 managed basenames exists in `$DOTFILES/zsh/env.d/`.
   - Tmpdir cleaned via trap/`always`.
2. Run on ceres until exit 0.

Acceptance criteria:
- Exit 0 on ceres covering all 21 inventory items (17 via `cmp`/env-set, 4 portless via decrypt+well-formedness±opportunistic-cmp); forced corruption of one YAML value → nonzero naming only file/key; forced missing-target → nonzero naming the target.
- `zsh -n` clean; forced-failure output inspected for zero secret values.

### Phase 2.5 — Fleet auth pre-flight (from ceres; before any dotfiles commit)

Actions:
1. From ceres, for each other box, run **both** probes (no short-circuit) and record pass/fail per probe:
   - gh capability: `ssh <box> 'gh api repos/camerontaylor/dotfiles-secrets --silent'` — tests actual private-repo read, not just login state.
   - ssh capability: `ssh <box> 'git ls-remote git@github.com:camerontaylor/dotfiles-secrets.git HEAD'` (output discarded; exit code recorded).
   A box passes if **either** probe succeeds. Note: `gh` over non-TTY ssh may false-fail on macOS locked keychains — the failure direction is safe (it causes fixing/reliance on the ssh probe, never a false pass).
2. Fix any box with both probes failing (interactive `gh auth login`, or grant its ssh key repo access) and re-run. ceres passes by construction.
3. Record results in the secrets-repo README's **"Cutover pre-flight"** dated section (per-box, per-probe) and commit — this is the named pass-record artifact.
4. Only then proceed to Phase 3; residual edit-freeze window (Phase-3 land → Phase-4 sign-off) bounded at **same-day**.

Acceptance criteria: committed README section shows 4/4 boxes passing at least one probe, dated the same day Phase 3 lands; no secret edits from now until Phase-4 sign-off.

### Phase 3 — New render fragment + renderer + consumer repointing (dotfiles; the one mid-window commit)

Actions:
1. New `scripts/secrets-render.zsh` (bootstrap layer, **standalone-safe**):
   - **Self-location**: derives `$DOTFILES` from `${0:A:h:h}` with the systemd-homed `.homedir` massage (as `save-secrets.zsh:22-27`; zsh's `:A` modifier is the built-in equivalent of the bash symlink walk at `generate-commit-msg:19-25`) — no reliance on deploy.zsh's exported `SCRIPT_DIR`, since the secrets-repo post-merge hook invokes this with no deploy/zshenv shell state.
   - No `zf_*` builtins — plain `mkdir -p`, `install -m`, `ln -sfn` as in `restore-secrets.zsh`; expands `${XDG_STATE_HOME:-$HOME/.local/state}` itself; reads `${DEPLOY_DRY_RUN:-0}` **with explicit default** (unset ≡ real run outside deploy).
   - Hardcoded parallel zsh arrays: source (relative to `~/.local/secrets`), target, mode, gate (`all`|`ceres`).
   - **Shell env**: each `shell/*.yaml` → `sops -d --output-type dotenv` → per line `key=${line%%=*}; val=${line#*=}; print -r -- "export ${key}=${(qq)val}"` → header `# MANAGED BY ~/.local/secrets (<source>) — edit via sops, not here` → `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh/<basename>.zsh`, mode 600, dir 700. Rendered basenames, enumerated: `90_secrets.zsh`, `91_cloudflare_secrets.zsh`, `92_telemetry_secrets.zsh`, `93_google_oauth_secrets.zsh`, `94_search_secrets.zsh`, `94_zerotier_secrets.zsh`, `95_tailscale_secrets.zsh`.
   - **Services**: raw dotenv to `~/.local/state/portkey/env`, `~/.config/openclaw-mcp/env` (gate: `$(hostname -s) == ceres`, preserving `restore-secrets.zsh:155`), `~/repos/deploy/immich/.b2-env`; blobs to `~/.local/state/portkey/local-api-key`, `~/repos/deploy/immich/.restic-password`; dirs `install -m 700 -d`. **Refinement (adopted from review):** the two immich rows are gated on `~/repos/deploy/immich` already existing, so live B2 credentials are not materialized on boxes that never ran the immich deploy.
   - **ssh**: `ssh/config` copy + `id_ed25519(.pub)`/`webfront_claw(.pub)` decrypt into `$DOTFILES/ssh/` with 600/644 per `65_sops.zsh:70-78`, then `ln -sfn` into `~/.ssh/`.
   - **portless**: certs copy (644), keys decrypt (600) into `$DOTFILES/configs/portless/`.
   - Atomicity: every write `mktemp` → `chmod` → `mv`; failures collected; summary `rendered N, quarantined M, unmapped U, failed K` (names only); marker `${XDG_STATE_HOME:-$HOME/.local/state}/secrets-render-ok` written on K==0 containing UTC timestamp + dotfiles HEAD + secrets HEAD.
   - **First-render cutover backup (all non-env.d targets — MANDATORY AMENDMENT, merged verbatim)**: when `${XDG_STATE_HOME:-$HOME/.local/state}/secrets-render-ok` is absent (no successful render has ever completed on this box), then for every mapping row whose target already exists on disk, `cmp -s` the freshly rendered temp file against the existing target before the `mv`; on difference, copy the existing bytes to `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/legacy-removed/<target-path-with-slashes-as-double-underscores>` (e.g. `ssh__config`, `home__.local__state__portkey__env`) **first-write-wins**: `[[ -e $backup ]] || cp $target $backup` — a K>0 retry after a secrets-repo push must never overwrite a genuine pre-cutover backup with rendered bytes. The backup never blocks, skips, or reorders a render; it does not run under `${DEPLOY_DRY_RUN:-0}` == 1 or in degraded mode (no render occurs there). ~5 lines; makes Principle 4 true for all 21 targets, not 7.
   - **Legacy-plaintext quarantine (move-not-delete)**: on K==0 only, and never under `${DEPLOY_DRY_RUN:-0}` == 1, **move** (`mv`, not `rm`) each of the enumerated seven legacy paths `$DOTFILES/zsh/env.d/{90_secrets,91_cloudflare_secrets,92_telemetry_secrets,93_google_oauth_secrets,94_search_secrets,94_zerotier_secrets,95_tailscale_secrets}.zsh`, when present, into `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/legacy-removed/` (dir 0700, `install -m 700 -d`). No guard logic; the managed-shadow invariant holds (files leave `env.d/`), and a divergent hand-edit — e.g. the LAN-router host's `TAILSCALE_ADVERTISE_ROUTES` — survives for Phase-4 triage instead of being destroyed on the first unattended post-cutover deploy. **Refinement (adopted):** when K>0 forces the quarantine to be skipped, print one line naming any managed basenames still present in `env.d/` ("stale, will shadow until next full render").
   - **Unmapped-file detection**: diff `git -C ~/.local/secrets ls-files` against mapped sources + allowlist (`README.md`, `.sops.yaml`, `.gitattributes`, `scripts/*`); warn by name (`U` count).
2. Rewrite `scripts/deploy.d/65_sops.zsh` → `scripts/deploy.d/65_secrets.zsh`:
   - Keep age-keygen bootstrap + registration warning (`65_sops.zsh:4-53`), retargeted at `~/.local/secrets/.sops.yaml` and `~/.local/secrets/scripts/sops-add-recipient.zsh`.
   - Bootstrap check: age key AND (gh capability OR ssh capability, probed as in Phase 2.5). Else print the precise instruction block and `return 0` — zero mutation.
   - **Clone with re-test + fallback chain**: at clone time, re-probe and attempt in order — `gh repo clone camerontaylor/dotfiles-secrets ~/.local/secrets`; on failure (even if `gh auth status` had passed — keychain/token scope can diverge from login state), fall back to `git clone git@github.com:camerontaylor/dotfiles-secrets.git ~/.local/secrets`; only if both fail, print instructions and return. Existing clone → `git -C ~/.local/secrets pull --ff-only`; ff-failure → warn "diverged; resolve manually in ~/.local/secrets" and render from the existing checkout.
   - Idempotently set `git -C ~/.local/secrets config diff.sops.textconv "sops -d"` (with `DEPLOY_DRY_RUN` guard, per the `60_git_hooks.zsh` pattern) and `ln -sfn` the secrets-repo post-merge hook (Q4): checked-in `~/.local/secrets/scripts/post-merge` → `exec zsh ~/.local/dotfiles/scripts/secrets-render.zsh`, no-op with a note if that path is missing.
   - Invoke the renderer; keep the `systemctl --user daemon-reload` tail (`65_sops.zsh:88-90`).
3. New loader `zsh/env.d/89_secrets_loader.zsh`: sources `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh/*.zsh(N)` — explicit default expansion (XDG_STATE_HOME may not be exported that early in `.zshenv`'s env.d loop). Silent no-op when absent. (`89_` escapes the `.gitignore` `zsh/env.d/9[0-9]_*` ignore, so the loader is trackable; lexical order 89 → rendered values → local 90–99 overrides still win by design.)
4. **Repoint direct-path consumers, same commit**:
   - `scripts/deploy.d/73_tailscale.zsh:22`: source `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh/9[0-9]_tailscale_secrets.zsh(N)` **then** `$SCRIPT_DIR/zsh/env.d/9[0-9]_*tailscale*.zsh(N)` (verified: the second glob matches both `96_local_tailscale.zsh` — local overrides win by sourcing later — and, on a degraded box, the legacy `95_tailscale_secrets.zsh`, preserving today's behavior). Update the comment at `:5-12` (document the `96_local_tailscale.zsh` convention for per-box knobs) and the message at `:178`.
   - `scripts/generate-commit-msg:155` → `SECRETS_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh/90_secrets.zsh"`; `:181` → `…/92_telemetry_secrets.zsh`; update the `:12` comment.
5. **Quote-agnostic extraction rewrite, same commit** in `scripts/generate-commit-msg` (bash, BSD-sed portable): replace `:157`'s double-quote-coupled sed and `:183-184`'s `tr -d '"'` with `sed -n 's/^export KEY=//p' | head -n1` into a var, then strip exactly one symmetric quote pair via `case` on `\"*\"` / `\'*\'` patterns with `${var#?}`/`${var%?}` parameter expansion (pure POSIX-sh). Bound: `${(qq)}` emits `'…'\''…'` only for values containing `'` — API keys don't; the fixture e2e catches any such drift loudly.
6. **Fixture e2e**: test beside the harness in the secrets repo — renders a synthetic throwaway-key YAML through the real converter and runs `generate-commit-msg`'s extraction against the output (three quoting styles in unit fixtures; real `${(qq)}` output in the e2e).
7. Do **not** touch `.enc` files, `.sops.yaml`, `save/restore-secrets.zsh`, or `.gitignore` yet. Commit, push.

Acceptance criteria:
- On ceres: `./deploy.zsh --only 65_secrets` renders all targets, quarantines the legacy plaintexts (files present in `legacy-removed/`, absent from `env.d/`), harness (post-Phase-3 mode) exits 0 including the invariant; new shell exports intact (presence-by-name checks); `73_tailscale.zsh` resolves `TAILSCALE_AUTHKEY` from the rendered path and per-box knobs from `96_local_tailscale.zsh` on ceres; `generate-commit-msg` produces a message end-to-end under a cron-like env (`env -i HOME=$HOME PATH=… bash scripts/generate-commit-msg`).
- **Amendment AC**: on a box with the marker absent and a deliberately hand-modified `ssh/config`, first render deposits the old bytes in `legacy-removed/` before overwriting; with the marker present, no backups are written.
- Standalone renderer run (invoked by absolute path with a minimal env, as the hook would) self-locates and renders correctly.
- Degraded simulation: deploy green, banner printed, zero mutation **including zero quarantine moves and zero backups**; `--dry-run` likewise; gh-masked clone exercises the ssh fallback.
- `zsh -n`/`bash -n` clean; no `-nt` guards.

### Phase 4 — Fleet cutover + divergence triage (per-box, same day as Phase 3; no dotfiles commits)

Actions, ceres first, then the other three:
1. `git -C ~/.local/dotfiles pull` (post-merge auto-deploys) — expect full render (pre-flight guarantees auth); degraded banner = stop and fix before proceeding.
2. **Triage quarantined files and backups**: on each box, triage covers **every** file in `legacy-removed/` — shell/dotenv files by key-name diff (e.g. diff of `sed -n 's/^export \([A-Z_0-9]*\)=.*/\1/p'` outputs; values inspected only locally, never pasted); `ssh/config` by local diff (config, not credentials); binary key/blob backups by `cmp` against the rendered target (differing = investigate locally). Every backup is dispositioned before Phase 5: fleet-shared → `sops set` into the secrets repo (after Phase-4 sign-off, since edits are frozen — record it in the README checklist); per-box (e.g. `TAILSCALE_ADVERTISE_ROUTES` on the LAN-router host) → new local `zsh/env.d/96_local_tailscale.zsh` (or analogous `96_local_*.zsh`); or confirmed-stale. Empty diff = nothing to do (expected on most boxes).
3. Verify per box: `secrets-render-ok` records the Phase-3 (or later) dotfiles HEAD; the seven managed basenames absent from `env.d/`; target modes correct (600 keys/env, 644 pubs/certs); ceres-only: `~/.config/openclaw-mcp/env` present, absent elsewhere; relevant user units green.
4. **Non-interactive check (one box per OS family)**: trigger the periodic/auto-pull path (systemd-run / launchd) and confirm `65_secrets` still pulls. This surfaces the two known environment hazards: macOS locked-keychain `gh` false-failures (ssh-remote fallback with the rendered `~/.ssh/id_ed25519` must carry it) and a missing `github.com` entry in `known_hosts` stalling `ls-remote` (fix by seeding known_hosts; the rendered `ssh/config` likely already handles it).
5. Record pass + triage outcome per box in the secrets-repo README checklist.

Acceptance criteria: 4/4 markers recording ≥ Phase-3 HEAD; invariant holds on all boxes; every quarantined-file/backup divergence explicitly dispositioned (secrets repo, local override, or confirmed-stale); units green; non-interactive pull verified per OS family.

### Phase 5 — Dotfiles cleanup + gated purge + gated rotation (one dotfiles commit + human rotation)

Actions:
1. **Mechanical gate**: from ceres, `ssh <box> 'cat ~/.local/state/secrets-render-ok'` for each box; check each recorded dotfiles sha is the Phase-3 commit or a descendant (`git merge-base --is-ancestor <phase3-sha> <recorded-sha>` locally). 4/4 pass → purge and rotation may proceed; any fail → fix that box first. Nothing irreversible executes before this gate.
2. Apply any deferred fleet-shared triage edits from Phase 4 (`sops set` → renderer → push) — the freeze ends at the Phase-4 sign-off this gate confirms.
3. Rotate GitHub PAT and Tailscale authkey (checklist in secrets-repo README), **using `sops set` + direct renderer invocation** (`zsh ~/.local/dotfiles/scripts/secrets-render.zsh`) so rotation does not depend on the `secrets-edit` convenience wrapper landing first: provider console → `sops set` into the owning `shell/*.yaml` → render → verify consumers (`gh`, `mise`, tailscale) → revoke old values. Push; boxes pick it up on next pull/deploy (no stale plaintexts remain in the load path to shadow it).
4. **Purge quarantine**: on each box, `rm -rf ~/.local/state/secrets/legacy-removed/` (post-gate, post-triage — the only deletion of these bytes, covering both quarantined env.d files and first-render backups, and it happens after fleet-wide verification).
5. Dotfiles deletions: all 21 `.enc`, `.sops.yaml`, `scripts/save-secrets.zsh`, `scripts/restore-secrets.zsh`, `scripts/sops-add-recipient.zsh`, `zsh/fpath/dotfiles-encrypt`. Add `zsh/fpath/secrets-edit` (thin wrapper: `sops edit` in `~/.local/secrets` → render → commit/push reminder).
6. **Staleness sentinel**: add a small interactive-only fragment `zsh/rc.d/33_secrets_staleness.zsh` (33 — the 31 slot is occupied by `31_wtp.zsh`) — prints one line per shell when `${XDG_STATE_HOME:-$HOME/.local/state}/secrets-render-ok` is missing or older than 14 days (portable age check via `find "$marker" -mtime +14 -print` — POSIX, BSD-clean; no GNU `date -d`). Closes the chronic-staleness gap: a box whose GitHub auth rots gets an in-your-face signal instead of an unread log line.
7. `.gitignore`: drop `!ssh/*.enc`, `!zsh/env.d/9[0-9]_*.enc`, and the dead lines 9 (`!nvim/init/9[0-9]_*.enc`) and 12 (`!zsh/rc.d/9[0-9]_*.enc`); keep `ssh/*` and the 9x local-override ignores. Optionally drop the dead `*.enc` skip lines at `zsh/.zshenv:67` and `zsh/.zshrc:46`.
8. Docs: README "Secrets" section, `deploy.zsh:38-41,70-71` `--force` wording, `scripts/deploy.d/20_symlinks.zsh:112` and `scripts/pre-commit:5-9` stale references; fix the stale CLAUDE.md symlink-walk cite (`generate-commit-msg:14-19` → `:19-25`).
9. Commit, push; one more green fleet deploy cycle.

Acceptance criteria:
- Gate transcript shows 4/4 ancestor checks before any purge/rotation action; old PAT/authkey revoked at providers; `legacy-removed/` absent on all boxes.
- `git ls-files '*.enc'` empty; no live-code references to `save-secrets|restore-secrets|\.sops\.yaml` in dotfiles (historical docs/spec excepted).
- Fleet deploy green post-cleanup; env intact; units green; staleness sentinel silent on healthy boxes and firing when the marker is artificially aged.

Scope estimate: **6 phases (incl. 2.5), ~16 files created/changed in dotfiles + new ~28-file private repo, complexity MEDIUM-HIGH.**

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| Local hand-edits destroyed at cutover (documented: `65_sops.zsh:61-64`, per-box tailscale knobs `73_tailscale.zsh:5-12`) | Move-not-delete quarantine **plus first-render cutover backup of all pre-existing divergent targets**; per-box key-name triage in Phase 4; `96_local_*.zsh` override convention; purge only post-gate |
| Stale legacy plaintexts shadow rotated values | Renderer quarantines the 7 enumerated basenames on full success; harness invariant; K>0 shadow-warning line; rotation gated on 4/4 markers |
| Quote-coupled consumers break on `${(qq)}` output | Quote-agnostic rewrite in the same Phase-3 commit; 3-style unit fixtures + e2e on real renderer output |
| A box lacks auth to the private repo at cutover | Phase-2.5 capability probes (gh api + ssh ls-remote, both always run) recorded in a committed artifact; clone-time re-test with gh→ssh fallback |
| gh login state diverges from actual capability (scopes, locked keychain) | Probes test the capability (`gh api repos/…`), not login state; false-fail direction is safe |
| Degraded banner unread under unattended periodic pulls | Pre-flight makes fleet degradation unexpected; marker-ancestry audit pre-rotation; interactive staleness sentinel post-migration |
| Quoting corruption in dotenv→zsh conversion | `${(qq)}` machine quoting + semantic env-set verification + hostile-value fixtures |
| sops dotenv output incompatible with a systemd EnvironmentFile value | Harness compares rendered dotenv vs live file; incompatible file demoted to blob pre-cutover |
| ff-only pull failure leaves stale secrets silently | Explicit warn + render from stale-but-valid checkout; staleness sentinel bounds the silence |
| Renderer misbehaves when run standalone via the secrets-repo hook | Self-location from `${0:A}`, explicit env defaults, no `zf_*` builtins; standalone run is an explicit Phase-3 AC |
| Half-rendered state on sops failure | Per-target mktemp→mv; failure skips quarantine entirely |
| Unknown file added to secrets repo but never rendered | Renderer unmapped-file warning by name |
| Plaintext leakage in tooling output | Names-only reporting; 0700 tmpdirs + trap cleanup; key-name-based triage; forced-failure output inspected |
| known_hosts missing github.com stalls non-interactive `ls-remote` | Surfaced by the Phase-4 per-OS non-interactive check; seed known_hosts / rendered ssh config |
| Live credentials spread to boxes that never used them | openclaw ceres gate preserved; immich rows gated on `~/repos/deploy/immich` preexistence |

### Verification (overall)

1. Harness exit 0 on ceres (21 items; portless via decrypt+well-formedness) before Phase 3; re-run post-Phase-3 (adds invariant check).
2. Phase-2.5 committed pre-flight record: 4/4 boxes, both probes run, same-day.
3. Degraded and dry-run simulations: zero mutation, zero quarantine moves, zero backups, green deploy; gh-masked clone exercises ssh fallback; standalone renderer run correct; first-render backup AC exercised.
4. Fixture e2e for `generate-commit-msg` extraction; cron-env smoke run; per-OS non-interactive pull check.
5. Mechanical 4/4 marker-ancestry gate before purge and rotation; per-box triage dispositions recorded; provider-side revocation confirmed after.
6. `zsh -n`/`bash -n` + word-splitting arg-count checks on every changed script (CLAUDE.md protocol).

---

## Traceability

The spec has no FR-###/SC-### identifiers; coverage is keyed to its 14 settled decisions, 4 open questions, and hard constraints (critic-verified 14/14, 4/4, all constraints).

| Spec item | Covered by | Notes |
|---|---|---|
| Decisions 1–7 (private repo, public dotfiles, sops+age, YAML form, blobs/plaintext split, encrypted-canonical, `~/.local/secrets`) | Phase 1; Principle 1 | |
| Decision 8 (deploy integration, degrade to instructions) | Phase 3 step 2; Phase 2.5 | Probe upgraded beyond spec's `gh auth status` to actual repo-read capability |
| Decision 9 (render targets/modes/gating preserved) | Phase 3 step 1 | openclaw ceres gate preserved (`restore-secrets.zsh:155`); immich dir-preexistence refinement |
| Decision 10 (bootstrap-layer portability) | Guardrails; Verification 6 | BSD `find -mtime` sentinel, no `zf_*`, `${(qq)}` |
| Decision 11 (textconv; merge driver optional) | Phase 3 step 2 | Merge driver deferred as follow-up per spec |
| Decision 12 (rotation as human checklist) | Phase 5 steps 1–3 | Mechanically gated |
| Decision 13 (no public-history purge) | Must-NOT-haves; ADR consequences | |
| Decision 14 (dotfiles cleanup) | Phase 5 steps 5–8 | |
| Open questions 1–4 | Resolutions section below | |
| Hard constraint: no plaintext in commits/logs | Principle 2; guardrails; names-only reporting throughout | |
| Hard constraint: round-trip verify before `.enc` deletion | Phase 2 before Phase 3; deletions only in Phase 5 post-gate | |
| Hard constraint: non-atomic-safe fleet deploys | Principle 3; Phase 2.5; degraded mode mutation-free | |
| Hard constraint: new tools via mise.toml | No new tools needed (sops/age/gh already pinned) | |

---

## Intent Reconciliation

This plan was produced by a non-interactive agent; the open assumptions below could not be confirmed live and are surfaced for the user at approval time. None blocks the plan's structure; each has a defensible default the plan proceeds on.

| # | Assumption (source) | Default taken | User may override by |
|---|---|---|---|
| 1 | The GitHub PAT lives in `shell/90_secrets.yaml` (planner assumption) | Locate by key name during Phase-5 rotation | Naming the file at rotation time |
| 2 | Fleet hostnames are ceres/saturn/neptune/quaoar (code comments) | Plan is hostname-agnostic except the ceres gate | Correcting checklist labels |
| 3 | `verify-render.zsh` stays permanently as an audit tool | Keep (it's free) | Deleting post-migration |
| 4 | Portless live-vs-`.enc` drift: live plaintext wins if the proxy currently serves with it | Human adjudicates during Phase 1 if the opportunistic `cmp` flags drift | Choosing the `.enc` side |
| 5 | LAN-router host for `TAILSCALE_ADVERTISE_ROUTES` unknown | Phase-4 triage discovers it mechanically; `96_local_tailscale.zsh` created there | Naming the box up front |
| 6 | Secrets repo name `dotfiles-secrets` (spec's suggestion, planner concurred) | Keep | Renaming before Phase 1 |
| 7 | Staleness threshold 14 days for the sentinel | 14 days | Any other `-mtime` value |

---

## ADR

- **Decision**: Migrate all 21 encrypted dotfiles secrets to private repo `camerontaylor/dotfiles-secrets` at `~/.local/secrets`; hard-cut deploy to `65_secrets.zsh` + a standalone-safe, self-locating `scripts/secrets-render.zsh` (hardcoded mapping + unmapped-file detection), preceded by a capability-testing per-box auth pre-flight recorded in a committed artifact; the renderer quarantines (moves, never deletes) the seven legacy env.d plaintexts on full render success and backs up every pre-existing divergent target on a box's first render; the cutover commit simultaneously repoints and quote-hardens the two direct-path consumers (`73_tailscale.zsh`, `generate-commit-msg`); per-box knobs move to `96_local_*.zsh` overrides; quarantine purge, `.enc`/legacy-script deletion, and PAT/Tailscale rotation execute only behind a mechanical 4/4 render-marker ancestry gate; an interactive staleness sentinel guards against chronic post-migration auth rot.
- **Drivers**: unattended fleet auto-deploys demand every-commit safety with verified (not assumed) auth; the mission is deleting clobber-guard complexity; migration must be script-verifiable per file — including unknown files, legacy residue, and per-box divergence.
- **Alternatives considered**: dual-path transitional fragment incl. the honest guard-free-shim variant (rejected: two writers to the same targets; mode-dependent quarantine logic); manifest-driven renderer (rejected: portable-parser burden, machine paths in the wrong repo); render into `zsh/env.d/` or one concatenated file (rejected: plaintext-in-tree / verification granularity); single-key YAML for opaque tokens (rejected: byte-exactness); `rm -f` of legacy plaintexts (rejected: destroys unverified per-box hand-edits — documented hazard, data-loss class); unconditional overwrite of non-env.d targets (rejected via mandatory amendment: same data-loss class for `ssh/config` and service env files).
- **Why chosen**: satisfies all five hard constraints at every commit boundary with the smallest persistent code surface; iterations 2–3 converted every policy-shaped safety into a mechanism — freeze → pre-flight, checklist → marker-ancestry gate, delete → quarantine-triage-purge (extended to all targets), log line → interactive sentinel.
- **Consequences**: `deploy.zsh --force` loses its secrets meaning; new machines need `gh auth login` (or a registered ssh key) before secrets appear; `git diff` in the secrets repo shows plaintext via textconv locally (accepted, spec #11); public history retains old ciphertext (accepted, spec #13, mitigated by rotation); `generate-commit-msg` and `73_tailscale.zsh` depend on the rendered state dir (degraded boxes retain last-rendered files and, for tailscale, the legacy-glob fallback — no regression vs today); per-box knobs now have an explicit home (`96_local_*.zsh`); post-cutover, per-box secret freshness depends on per-box GitHub credential health (the priced cost of the settled private-repo decision — sentinel mitigates for interactive use).
- **Follow-ups**: optional decrypt-merge-reencrypt merge driver (spec #11); ceres bare mirror (out of scope); prune stale portless memory note; periodic `verify-render.zsh` audit; consider alerting beyond the interactive sentinel for headless boxes.

---

## Resolutions of the spec's open questions

1. **YAML file granularity → topical split, basenames preserved**: seven `shell/9x_*.yaml` files mirroring today's env.d split, plus one YAML per service consumer file (`services/portkey/env.yaml`, `services/openclaw/env.yaml`, `services/immich/b2-env.yaml`). 1:1 traceability for the harness; per-consumer files are forced anyway (a rendered env file must contain exactly its consumer's keys). Opaque single-value tokens (`local-api-key`, `restic-password`) stay **sops blobs**, not single-key YAML: `--extract` can't guarantee byte-exact round-trip (trailing-newline semantics) and byte-exactness is what verification demands. Refinement: fleet-shared YAML holds only fleet-shared values — per-box knobs (`TAILSCALE_ADVERTISE_ROUTES`, `TAILSCALE_EXTRA_ARGS`) live in per-box `96_local_*.zsh` overrides, not the secrets repo.
2. **`ssh/config` → plaintext** in the private repo. Configuration, not credential; the repo is private; plaintext restores real diffs/merges for the one file with documented merge pain (`scripts/pre-commit:5-9`) and hand-edit history. Hostname/IP disclosure bounded by repo privacy.
3. **Rendered shell exports → per-topic files under `${XDG_STATE_HOME:-$HOME/.local/state}/secrets/zsh/` (basenames `90_…`–`95_…` enumerated) + one checked-in loader `zsh/env.d/89_secrets_loader.zsh`** — a hybrid: per-topic files give per-file atomic rendering/verification and sidestep the `94_` prefix collision; out-of-tree placement removes plaintext from every git worktree. Completed by the quarantine of the seven legacy in-tree plaintexts, the repointing of the two direct-path consumers, and the `96_local_*.zsh` convention so deliberate per-box overrides survive (load order: loader at 89 → rendered values; local 90–99 files still override by design).
4. **Secrets-repo post-merge hook → yes.** Checked-in `scripts/post-merge` in the secrets repo exec-ing `~/.local/dotfiles/scripts/secrets-render.zsh` — which self-locates and self-defaults precisely so this hook path works with no deploy shell state — symlinked idempotently by `65_secrets.zsh`; no-ops with a note if the dotfiles path is missing. ~5 lines to close the "pulled by hand, forgot to render" drift gap.

---

## Consensus trail

- **Iteration 1** — Planner drafted (Option B hard cut + Option C hardcoded mapping, 5 phases). Architect: antithesis that Option B severs distribution on policy-only freeze with unverified private-repo auth; found HIGH stale-env.d-plaintext shadowing (`.zshenv` lexical loop) and unaddressed direct-path consumers (`73_tailscale.zsh`, `generate-commit-msg`). Critic: **ITERATE** — upgraded shadowing to CRITICAL (Principle-1 conflict); added own HIGH: `generate-commit-msg` extraction is quote-format-coupled and breaks on `${(qq)}` output; required auth pre-flight, ceres-pinned harness, unmapped-file detection, standalone-safe renderer, mechanical rotation gate.
- **Iteration 2** — Planner adopted all deltas (stale-plaintext deletion on full render success, consumer repointing + quote-agnostic rewrite, Phase 2.5 pre-flight, marker-ancestry gate, enumerated basenames, portless PEM exemption). Architect: verified all fixes real; new findings — `rm -f` deletes unverified files on 3 boxes (MEDIUM), pre-flight tests token validity not repo readability, `$DOTFILES`/`DEPLOY_DRY_RUN` standalone gaps, stale cite. Critic: **ITERATE** — upgraded the unverified `rm -f` to CRITICAL (data-loss class, documented per-box tailscale knobs), plus mediums (capability probe, self-location, clone fallback chain).
- **Iteration 3** — Planner adopted everything: move-to-quarantine + gated purge, `96_local_tailscale.zsh` convention + Phase-4 key-name triage, `gh api` capability probes + clone-time gh→ssh fallback, `${0:A:h:h}` self-location, `${DEPLOY_DRY_RUN:-0}`, committed pre-flight record, sops-set rotation ordering, staleness sentinel. Architect: all claims verified; one BLOCKING delta — quarantine covered only 7 of 21 targets while `ssh/config`/service files were overwritten unverified; proposed first-render cutover backup; "with delta 1 absorbed … I would support consensus." Critic: **APPROVE** with the first-render cutover backup as a fully-specified MANDATORY AMENDMENT (merged verbatim into this file, including the critic's first-write-wins refinement), explicitly judging that no fourth iteration was warranted ("a fourth iteration would reproduce this document verbatim plus five lines"). Non-blocking refinements also merged: immich dir-preexistence gate, `33_` sentinel slot, K>0 shadow-warning line, CLAUDE.md cite fix.
- **Unresolved objections**: none. The architect's surviving antithesis (post-cutover per-box GitHub-auth liveness dependency; machinery moved rather than deleted) is recorded as a priced consequence in the ADR, not an objection to the plan.

---

## Phase-5 gate attempts

### 2026-09-04 — attempt 1: **BLOCKED, 3/4**

`ssh <box> 'cat ~/.local/state/secrets-render-ok'`, ancestry checked with
`git merge-base --is-ancestor 1923532a <recorded-sha>`:

| Box | Recorded dotfiles sha | Rendered at | Descendant of Phase-3 `1923532a`? |
|---|---|---|---|
| ceres | `1edd6555` | 2026-08-29T04:18:20Z | yes |
| saturn | `05509ab2` | 2026-09-02T14:00:36Z | yes |
| neptune | `c8bb896b` | 2026-08-31T05:02:28Z | yes |
| quaoar | — (unreachable) | — | **unknown** |

quaoar is offline: `tailscale status` reports `offline, last seen 27d ago`
(≈2026-08-08, i.e. **before** the Phase-3 cutover on 2026-08-25), and
`ssh quaoar` (`quaoar.webfront.app`) and the tailnet IP `100.93.28.15` both
time out. It has therefore almost certainly never run `65_secrets.zsh`, still
holds the seven legacy `env.d/9*_secrets.zsh` plaintexts, and still depends on
the tracked `.enc` files for a from-scratch restore.

**Nothing irreversible executed.** No `.enc` deletion, no `.sops.yaml` move, no
`legacy-removed/` purge, no rotation. The only Phase-5 work landed is step 8's
safely-independent slice: the stale `--force` / `65_sops.zsh` wording in
`deploy.zsh`, `deploy.bash`, and `AGENTS.md`.

**Next human action**: bring quaoar online, `git -C ~/.local/dotfiles pull`
(post-merge auto-deploys), confirm a non-degraded render, triage its
`legacy-removed/` per Phase 4 step 2, then re-run this gate.

### 2026-09-04 — attempt 2: **CLEARED 3/4 by owner decision**

Cameron waived the fourth marker: quaoar is written off as a gate participant,
and if it is ever resurrected it re-onboards as a fresh box (register its age
key, first render). Phase-5 **dotfiles cleanup** executed on that authority.

Executed: all 21 `.enc` deleted; `.sops.yaml` + `.sops.yaml.example` retired
(the live recipient list is `~/.local/secrets/.sops.yaml`);
`save-secrets.zsh`, `restore-secrets.zsh`, `sops-add-recipient.zsh` (the live
copy is `~/.local/secrets/scripts/`) and `zsh/fpath/dotfiles-encrypt` removed;
`zsh/fpath/secrets-edit` and `zsh/rc.d/33_secrets_staleness.zsh` added;
`.gitignore` negations and the dead `*.enc` loader skips dropped; docs swept.

**NOT executed, still open:**

- **Step 3 — key rotation (human).** GitHub PAT and Tailscale authkey. The
  Tailscale key is recorded as leaked, so it is the priority. Old ciphertext
  remains in this repo's public history by explicit decision (spec #13) —
  rotation *is* the mitigation.
- **Step 4 — quarantine purge (deferred, deliberately).** `legacy-removed/`
  still holds ~6 files each on ceres, saturn and neptune. Phase-4 step 2 triage
  was never signed off per box, so these are the last copies of any pre-cutover
  hand-edit. Triage first, then `rm -rf`.
