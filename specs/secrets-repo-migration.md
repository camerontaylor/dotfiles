# Spec: migrate secrets out of public dotfiles into a private sops-native secrets repo

Status: consolidated spec, input to /ralplan. Decisions below were made in discussion
with the user (Cameron Taylor) on 2026-08-25 and are settled unless marked "Open".

## Problem

The dotfiles repo (public fork, `camerontaylor/dotfiles`) currently tracks ~22
whole-file sops binary blobs (`*.enc`): 7 pure-`export KEY=value` zsh files under
`zsh/env.d/9[0-9]_*.zsh.enc`, 4 dotenv-shaped service env files (portkey, openclaw,
immich b2), ssh private keys + pubs + `ssh/config`, 4 portless PEMs, and a restic
password. Whole-file binary encryption wastes sops' per-value model: git shows
binary diffs, merges require manual decrypt-and-compare, and plaintext/ciphertext
are dual-canonical, guarded by fragile mtime checks in `scripts/save-secrets.zsh`,
`scripts/restore-secrets.zsh`, and `scripts/deploy.d/65_sops.zsh` (a historical
source of clobber bugs).

## Decision summary (settled)

1. **New private GitHub repo** under the user's account (suggested name:
   `dotfiles-secrets`; planner may propose better). GitHub is the canonical
   remote (offsite durability is a hard requirement — see the restic-password
   comment in `save-secrets.zsh`). A ceres bare remote is out of scope for now.
2. **Dotfiles stays public** (keyless https first-clone is load-bearing for
   bootstrap; GitHub forbids privatizing a fork anyway).
3. **Keep sops + age even in the private repo** (GitHub only ever holds
   ciphertext). The 4-recipient age setup, `.sops.yaml`, and
   `scripts/sops-add-recipient.zsh` flow move to / keep working with the new repo.
4. **Key=value secrets become sops-native flat YAML** (encrypted in place, key
   names cleartext, values `ENC[...]`). Verified empirically on sops 3.13.3:
   single-key edit changes only that line + the `mac` metadata line; `sops set`
   works on YAML (fails on dotenv); comments get encrypted in every format.
   Values are all flat single-line tokens. File granularity: Open question below.
5. **True binary/opaque material migrates as-is** (sops binary blobs): ssh
   private keys, portless PEMs (key material), restic password. Public material
   (`*.pub`, `ca.pem`, `server.pem`) needs no encryption inside a private repo —
   store plaintext.
6. **Encrypted files are canonical; plaintext is a derived artifact.** Deploy
   renders plaintext targets; edits go through `sops edit` / `sops set` (or a thin
   wrapper). All mtime clobber-guard machinery is deleted, not ported.
7. **Secrets repo location: sibling clone at `~/.local/secrets`** — NOT inside
   the dotfiles tree, so dotfiles worktrees/agents never see or conflict on it.
8. **Deploy integration** (in public dotfiles, replacing `65_sops.zsh`'s decrypt
   role): if the age key AND GitHub auth (`gh auth status` or working ssh remote)
   are present → clone or `git -C ~/.local/secrets pull --ff-only`, then render
   all targets. Otherwise print precise bootstrap instructions: where to put the
   age key (or how to register a fresh key via `sops-add-recipient.zsh` on an
   existing box), run `gh auth login` (device flow breaks the
   ssh-key-is-inside-the-secrets chicken-and-egg), re-run deploy.
9. **Render targets are preserved exactly** (same paths, same modes, same
   per-host gating):
   - zsh env exports (today's `zsh/env.d/90–95_*.zsh` content) — rendered file(s)
     stay gitignored in dotfiles or land outside the repo; a small checked-in
     loader sources them. `sops -d --output-type dotenv` is the approved
     extraction mechanism; rendering to zsh must handle quoting.
   - `~/.ssh/config`, `~/.ssh/id_ed25519(.pub)`, `ssh/webfront_claw(.pub)` with
     current symlink + chmod 600/644 behavior (see `65_sops.zsh`).
   - `~/.local/state/portkey/{env,local-api-key}` (0600, dir 0700).
   - `~/.config/openclaw-mcp/env` — **ceres-only** gate preserved.
   - `~/repos/deploy/immich/.restic-password`, `.b2-env`.
   - portless certs at their current restore location.
10. **Renderer/deploy code is bootstrap-layer**: must obey CLAUDE.md portability
    rules (BSD userland clean, zsh word-splitting rules, no GNU-only flags).
11. **Git ergonomics in the secrets repo**: wire `diff.sops.textconv = sops -d`
    via gitattributes + a config-setting deploy step (git config isn't tracked).
    A decrypt-merge-reencrypt merge driver is optional/nice-to-have (single-branch
    repo makes conflicts rare).
12. **Rotation**: rotate the high-value tokens as they migrate (GitHub PAT,
    Tailscale authkey); everything else keeps its value (accepted risk). Rotation
    is a human step — collect into a checklist or `wizard`-style script, do not
    block implementation on it.
13. **Public-history purge: explicitly NOT doing.** Old ciphertext stays in
    public git history; accepted risk given rotation of the high-value pair.
14. **Dotfiles cleanup at the end**: delete `.enc` files, `.sops.yaml` (moves to
    secrets repo), shrink/remove `save-secrets.zsh` + `restore-secrets.zsh`,
    rewrite `65_sops.zsh` into the new clone/pull/render fragment, update
    `.gitignore`, docs, and README bootstrap instructions.

## Hard constraints

- **Never commit plaintext secret values to either repo; never print secret
  values into logs/transcripts.** Implementation reads plaintexts from the
  deployed checkout (`~/.local/dotfiles`, `~/.ssh`, `~/.local/state/portkey`,
  `~/.config/openclaw-mcp`, `~/repos/deploy/immich`) and encrypts them into the
  new repo locally. Redact values in any diagnostic output.
- The age key on this machine (`~/.config/sops/age/keys.txt`) must be able to
  decrypt everything before any `.enc` is deleted from dotfiles. Verify
  round-trip (decrypt-from-new-repo == current plaintext) per file before
  cleanup.
- Migration must be non-atomic-safe: dotfiles must keep deploying correctly on
  the other 3 machines mid-migration (they pull dotfiles before the secrets repo
  exists there). Sequence the cutover so `deploy.zsh` never hard-fails on a box
  that hasn't done the two-credential bootstrap yet — degrade to instructions.
- New tools (if any) go in `configs/mise.toml`, not deploy scripts. sops + age
  are already mise-managed.

## Open questions for the planner

- File granularity for the YAML: single `shell.yaml` vs topical files mirroring
  today's 90–95 split, plus per-service files (portkey/openclaw/immich).
  Leaning: keep topical split for shell env; one file per service consumer.
- `ssh/config` in the private repo: plaintext (max mergeability; it's config,
  not credentials — the repo is private) vs sops-encrypted (uniformity).
  Leaning: plaintext.
- Whether rendered shell exports collapse to one gitignored file + loader, or
  keep the 9x-numbered-per-topic layout for load-order compatibility.
- Secrets-repo-side post-merge hook to re-render on manual pulls (deploy already
  covers the normal path).

## Context pointers

- `scripts/save-secrets.zsh`, `scripts/restore-secrets.zsh`,
  `scripts/deploy.d/65_sops.zsh` — current flow to be replaced.
- `.sops.yaml` — current recipients + path_regex (4 age recipients = 4 machines).
- `CLAUDE.md` — bootstrap-layer portability rules (binding).
- `.gitignore` — current plaintext-ignore / `.enc`-unignore dance to unwind.
- Existing plaintexts live only on deployed machines; git worktrees contain only
  `.enc` files (ignored files don't propagate to worktrees).
