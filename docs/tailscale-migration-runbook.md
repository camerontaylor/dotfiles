# ZeroTier → Tailscale migration runbook

Migrate the dev fleet from ZeroTier to Tailscale **drop-in** (keep the
`*.webfront.app` names; re-point their A records) using a
**coexist-then-cut-over** rollout. Integrations: MagicDNS (alongside
webfront.app), a subnet router for LAN-only boxes, and Tailscale SSH + ACLs.

Spec: `.omc/specs/deep-dive-migrate-from-zerotier-to.md`
Trace evidence: `.omc/specs/deep-dive-trace-migrate-from-zerotier-to.md`

> **Legend:** 🔒 = OUT-OF-REPO manual gate (admin console / Cloudflare / live host —
> `deploy.zsh` cannot do it). 📝 = repo edit. ✅ = verification gate.
> 💥 = destructive / decommission — only after the cutover is verified.

The in-repo automation lives in `scripts/deploy.d/73_tailscale.zsh`. It is
**coexistence-safe**: it installs Tailscale and joins the tailnet but never
touches ZeroTier. ZeroTier removal is a separate, gated phase at the end.

---

## Phase 1 — Probe & inventory (do this FIRST)

1. 🔒✅ **Live topology probe** on a representative host (e.g. `ceres`):
   ```sh
   zerotier-cli listnetworks      # confirm which network ID owns 10.132.32.0/24
   ip -4 addr | grep 10.132.32    # (Linux) confirm this host's ZeroTier IP
   ```
   Reconcile the result against the deploy default `2873fd00f25ac35e` and the
   secret network ID `743993800fe3d723` (in `94_zerotier_secrets.zsh`). Record
   which network is the DNS-plane network (`10.132.32.0/24`). **Do not change any
   DNS until this is confirmed** — the spec only *assumes* this mapping.
2. 🔒 **Create the tailnet auth key** (admin console → Settings → Keys):
   reusable, non-ephemeral, tagged `tag:fleet`. Copy the `tskey-auth-…` value.
3. 🔒 **Enable MagicDNS** (admin console → DNS → enable MagicDNS). This is
   additive; it does not affect the public `*.webfront.app` zone.
4. 🔒 **Author the ACL policy** (admin console → Access controls). Minimal start:
   ```jsonc
   {
     "tagOwners": { "tag:fleet": ["autogroup:admin"] },
     "ssh": [
       {
         "action": "check",            // forces periodic SSO re-auth; use "accept" for no prompt
         "src":    ["autogroup:member"],
         "dst":    ["tag:fleet"],
         "users":  ["ctaylor", "webfront"]
       }
     ],
     "acls": [ { "action": "accept", "src": ["*"], "dst": ["*:*"] } ]
   }
   ```
   Tighten `acls` later; this keeps connectivity open during coexistence.

## Phase 2 — Pilot one host (coexisting with ZeroTier)

5. 📝 **Create the secret** on the pilot host and encrypt it:
   ```sh
   cat > zsh/env.d/93_tailscale_secrets.zsh <<'EOF'
   export TAILSCALE_AUTHKEY="tskey-auth-…"   # the reusable tagged key from step 2
   EOF
   ./scripts/save-secrets.zsh        # encrypts 9[0-9]_* plaintext → .enc (commit the .enc)
   ```
   The plaintext `93_tailscale_secrets.zsh` is gitignored; only the `.enc` is
   committed. `.sops.yaml`'s `9[0-9]_` rule already covers it — no config change.
   > ⚠️ The plaintext file exists unencrypted in the working tree until
   > `save-secrets.zsh` succeeds. If it fails partway, **delete
   > `zsh/env.d/93_tailscale_secrets.zsh` manually** and regenerate the key in
   > the admin console before retrying — the reusable `tag:fleet` key grants
   > tailnet access to anyone who obtains it.
6. **Deploy** on the pilot (e.g. `ceres`):
   ```sh
   ./deploy.zsh --only 73_tailscale         # or a full deploy
   ```
   The fragment installs Tailscale (macOS cask / Linux install.sh), starts the
   daemon, and runs `tailscale up --ssh --accept-routes --authkey=…`.
   - macOS first run: approve the system extension in **System Settings →
     Privacy & Security** and open the app once (same class of step as ZeroTier).
7. ✅ **Verify the pilot** (ZeroTier still up the whole time):
   ```sh
   tailscale status                         # this host shows 100.x, BackendState=Running
   tailscale ip -4                          # capture this host's 100.x address
   tailscale ssh ceres                      # keyless SSH over the tailnet works
   ```

## Phase 3 — Roll out to the rest of the fleet (still coexisting)

8. Repeat steps 5–7 for `pluto, make/makemake, neptune, saturn, eris`. Capture
   each host's `tailscale ip -4` (`100.x`) — you need these for the DNS cutover.
9. 📝🔒 **Stand up the subnet router** for LAN-only boxes (e.g. `beedee`
   `10.132.32.29`). On the ONE fleet host that shares `beedee`'s LAN, set in its
   secret file:
   ```sh
   export TAILSCALE_ADVERTISE_ROUTES="10.132.32.0/24"
   ```
   redeploy `73_tailscale`, then 🔒 **approve the route** in the admin console
   (Machines → that host → Edit route settings). ✅ Verify another tailnet host
   can `ping 10.132.32.29` via the router.

## Phase 4 — Cut over (the switch; still reversible until Phase 5)

10. 🔒 **Re-point Cloudflare A records** for
    `{pluto,make,neptune,saturn,ceres,eris}.webfront.app` from their ZeroTier
    `10.132.32.x` to the captured Tailscale `100.x` addresses. Lower TTL first
    (e.g. 60s) a day ahead so propagation is quick and reversible.
11. ✅ Verify name-based access end to end:
    ```sh
    dig +short ceres.webfront.app            # → 100.x
    ssh ceres                                # key-based SSH over the new IP still works
    curl -fsS https://ceres.webfront.app:8787/…   # Portkey/CCR gateway reachable
    ```
    Confirm Caddy TLS (`scripts/setup-caddy.sh`) and `wake-peers`
    (`76_wake_peers.zsh`) still function — both follow DNS, so the re-point is
    transparent.
12. 📝 **Update the one hardcoded ZeroTier literal** in `ssh/config`:
    ```
    Host beedee*
        HostName 10.132.32.29     →   HostName <beedee 100.x or MagicDNS name>
    ```
    On a fresh clone, **decrypt first** (`./scripts/restore-secrets.zsh`) so you
    edit the real `ssh/config`, not a stale copy; then re-encrypt with
    `./scripts/save-secrets.zsh` (ssh/config is sops-managed). ✅ Verify
    `ssh beedeeapp`.
    - Out of scope (do NOT change): `beedeebags` (10.102.181.29),
      `flagstaff*` (10.243.119.116), and public-internet hosts.

## Phase 5 — Decommission ZeroTier (destructive — only after Phase 4 verified)

13. ✅ **Soak.** Run the fleet on Tailscale for an agreed window (e.g. 1 week)
    with ZeroTier still installed but unused, so you can fall back instantly.
14. 💥 **Remove the in-repo ZeroTier integration:**
    ```sh
    git rm scripts/deploy.d/72_zerotier.zsh
    git rm zsh/env.d/94_zerotier_secrets.zsh.enc
    rm -f zsh/env.d/94_zerotier_secrets.zsh        # gitignored plaintext
    # prune any ZEROTIER_* leftovers; .sops.yaml needs no change (regex-based)
    ```
15. 💥🔒 **Uninstall ZeroTier per host:**
    - macOS: `brew uninstall --cask zerotier-one`
    - Linux: stop/disable `zerotier-one`, then the distro's uninstall
16. 🔒 Leave the ZeroTier network/controller in place until you are certain, then
    delete it. ✅ Final check: a FRESH host running `./deploy.zsh` joins the
    tailnet, `tailscale ssh ceres` works, every `*.webfront.app` fleet name
    resolves to `100.x`, and `./deploy.zsh --only 85_verify_tools` stays green.

---

## Rollback

- **Before Phase 4:** nothing to roll back — ZeroTier is untouched; just stop
  using Tailscale (`tailscale down`).
- **During/after Phase 4:** revert the Cloudflare A records to the ZeroTier
  `10.132.32.x` addresses (low TTL makes this fast) and revert the `ssh/config`
  `beedee*` edit. ZeroTier is still installed and joined, so connectivity returns.
- **After Phase 5:** rollback means reinstalling ZeroTier — avoid starting Phase 5
  until the soak in step 13 gives you confidence.

> Note: `73_tailscale.zsh` re-ups a node whose backend is not Running, so a host
> you have deliberately taken offline with `tailscale down` will silently rejoin
> on the next `deploy.zsh`. During a maintenance window, skip the fragment
> (`--only` without it) or re-run `tailscale down` afterward.

## Why these steps can't be automated by `deploy.zsh`

The repo can install clients and bring up the tailnet (steps 5–9 via
`73_tailscale.zsh`), but it cannot — and must not — touch the Cloudflare zone
(step 10), the admin-console ACL/route/MagicDNS settings (steps 2–4, 9), or read
live ZeroTier controller state (step 1). Those are the human gates; everything
else is `git` + `deploy.zsh`.
