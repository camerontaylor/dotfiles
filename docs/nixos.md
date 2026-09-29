# NixOS deployment on Pluto

The four repos retain the fleet deployment order: dotfiles → secrets → infra
→ agents. NixOS owns the system prerequisites; mise owns user runtimes and
agent CLIs. A NixOS rebuild is a setup operation, not part of the unattended
pull/deploy chain.

Normal deployment repairs missing or broken npm globals and restores exact
pins. Use `--upgrade` to refresh installed `@latest` packages. Repeated
deployments avoid the npm reinstall that nearly exhausted Pluto's
300-second post-merge hook limit.

The system definition lives in the infra repo at `nixos/`. Apply it before
bootstrapping the home layer:

```sh
sudo nixos-rebuild switch --flake "$HOME/.local/infra/nixos#pluto"
```

The system must provide bash, zsh, git, download/archive tools, and nix-ld
with the libraries needed by generic Linux binaries. NixOS has `/bin/sh`
and `/usr/bin/env`; scripts must discover other executables through PATH.
User services need an explicit PATH including Nix system/profile binaries
and mise shims, because their manager does not read interactive shell files.

Pluto's age identity and GitHub SSH identity must be seeded from an enrolled
machine before encrypted secrets can render. Follow the secrets repo's
`hosts/pluto` recovery instructions. Never copy rendered plaintext into a
Git checkout or Nix input. Missing credentials should produce a clear
degraded-mode notice, with no partially rendered readiness marker.

Run the home deployment from the intended checkout:

```sh
./deploy.bash --dry-run
./deploy.bash
```

Full deployment finalizes Codex API authentication after CLI installation.
On first bootstrap, it also renders the selected credential after the agents
checkout is created. To run the agents-owned synchronization separately:

```sh
bash "$HOME/.local/agents/scripts/setup-codex-auth.sh"
```

Existing ChatGPT logins are preserved. The agents deploy keeps API credentials
in sync on later deployments; the daemon's workers use Codex's private cache.

Both deploy drivers support NixOS. Native package-manager operations belong
in the infra NixOS definition; home deploy must not try apt, pacman, or
Homebrew on NixOS. The sibling deploys retain their placement-only service
contract. First activation or recovery of their timers is a one-time setup
step, after inspecting the deployed units.

Run the native acceptance check in a login shell after deployment:

```sh
bash -lc 'bash "$HOME/.local/dotfiles/scripts/tests/pluto-smoke.sh"'
```

It checks executable resolution, Python native modules, shell integration,
secret readiness and permissions, the three deployment timers, and Pluto's
core services. It prints names and status only. The local regression tests
use disposable homes and fake tools to cover portability and dry-run behavior.

Pluto uses the stock `@getpaseo/cli` at `0.9.1` on PATH and the fleet fork
`@camerontaylor/paseo-cli` at `0.9.1-fork.1` for the daemon. The daemon's
exact pin lives in the infra flake; the runtime installer reads it through
`scripts/tests/check-paseo-pins.py`. That checker requires the intended
package roles and matching base versions. Bump both declarations together;
channel tags are rejected. The fork installation does not become the bare CLI.

Caddy reads `$HOME/.local/state/caddy/env`, rendered only on Pluto from the
Cloudflare ciphertext. The renderer selects `CF_API_TOKEN`, writes mode 600,
and preserves the previous file and readiness marker if decryption or key
selection fails. Systemd reads the file before starting Caddy.

The implementation is being validated against the existing NixOS 25.05
closure. A release upgrade is separate from these deployment fixes.
