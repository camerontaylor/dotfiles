#!/usr/bin/env python3
"""Offline deploy contracts with a disposable HOME and a non-FHS tool PATH.

Runs on macOS and Linux with Python's standard library, bash and zsh. This
does not emulate ELF loading or remove the host's /bin/bash: pluto-smoke.sh
supplies native NixOS acceptance. No sibling checkout or secret is read.
"""
from pathlib import Path
import os
import shlex
import shutil
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHELLS = [str(Path("/bin/bash")) if Path("/bin/bash").is_file() else shutil.which("bash"),
          shutil.which("zsh")]
if not all(SHELLS):
    raise SystemExit("NixOS integration tests require bash and zsh on PATH")


class NixosIntegration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nixos-integration-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.repo = self.base / "dotfiles"
        self.bin = self.base / "profile/bin"
        self.bin.mkdir(parents=True)
        (self.home / ".nix-profile").mkdir()
        (self.home / ".nix-profile/bin").symlink_to(self.bin, target_is_directory=True)
        (self.home / ".local/share/mise").mkdir(parents=True)
        (self.home / ".local/share/mise/shims").symlink_to(self.bin, target_is_directory=True)
        (self.home / ".local/bin").symlink_to(self.bin, target_is_directory=True)
        self.calls = self.base / "calls"
        for tool in ("bash", "zsh", "sh", "head", "dirname", "basename",
                     "readlink", "mkdir", "tee", "date", "find", "sort",
                     "grep", "sed", "cat", "tail", "chmod", "ln", "rm",
                     "cp", "mv", "stat", "mktemp", "wc", "cut", "tr"):
            source = shutil.which(tool)
            if source:
                (self.bin / tool).symlink_to(source)
        self.env = {
            "HOME": str(self.home), "USER": "synthetic", "PATH": str(self.bin),
            "BASH_ENV": "/dev/null", "ZDOTDIR": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "SCRIPT_DIR": str(self.repo), "DOTFILES_OS": "Linux",
            "DOTFILES_ARCH": "x86_64", "DOTFILES_SKIP_BREW": "1",
            "DEPLOY_DRY_RUN": "1", "CALLS": str(self.calls),
            "PULL_RC": "0", "DEPLOY_RC": "0", "TMPDIR": str(self.base),
        }
        self.fake("uname", 'case "$1" in -m) echo x86_64;; *) echo Linux;; esac')
        self.fake("hostname", "echo pluto")
        self.fake("git", 'printf "git %s\\n" "$*" >> "$CALLS"; exit "$PULL_RC"')
        for tool in ("systemctl", "sudo", "curl", "mise", "npm", "cargo",
                     "sops", "age-keygen", "keyd"):
            self.fake(tool, f'printf "{tool} %s\\n" "$*" >> "$CALLS"; exit 99')

    def fake(self, name, body):
        target = self.bin / name
        if target.is_symlink():
            target.unlink()
        target.write_text("#!/bin/sh\n" + body + "\n")
        target.chmod(0o755)

    def copy(self, relative):
        target = self.repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
        return target

    def run_shell(self, shell, code, *args):
        result = subprocess.run([shell, "-c", code, "integration", *map(str, args)],
                                env=self.env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def log(self):
        return self.calls.read_text() if self.calls.exists() else ""

    def snapshot_home(self):
        return {str(path.relative_to(self.home)):
                (path.lstat().st_mode,
                 str(path.readlink()) if path.is_symlink() else
                 path.read_bytes() if path.is_file() else None)
                for path in self.home.rglob("*")}

    def fixture_siblings(self, existing=True):
        for name in ("secrets", "infra", "agents"):
            sibling = self.home / ".local" / name
            if not existing:
                continue
            (sibling / ".git").mkdir(parents=True)
            if name != "secrets":
                deploy = sibling / "deploy"
                deploy.write_text('#!/usr/bin/env zsh\n'
                    f'printf "{name} %s DOTFILES_DIR=%s\\n" "$*" '
                    '"${DOTFILES_DIR:-}" >> "$CALLS"\nexit "$DEPLOY_RC"\n')
                deploy.chmod(0o755)
        key = self.home / ".config/sops/age/keys.txt"
        key.parent.mkdir(parents=True)
        key.write_text("synthetic test fixture, not an age key\n")
        renderer = self.repo / "scripts/secrets-render.zsh"
        renderer.parent.mkdir(parents=True, exist_ok=True)
        renderer.write_text('printf "render dry=%s\\n" "$DEPLOY_DRY_RUN" >> "$CALLS"\n')

    def chain(self, shell):
        helpers = self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragments = [self.copy(f"scripts/deploy.d/{name}.zsh") for name in
                     ("65_secrets", "66_infra", "67_agents")]
        return self.run_shell(shell, '. "$1"; shift; for fragment in "$@"; '
                              'do . "$fragment" || exit; done', helpers, *fragments)

    def test_existing_chain_dry_run_order_and_explicit_dotfiles(self):
        self.fixture_siblings()
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                self.chain(shell)
                self.assertEqual(self.log().splitlines(), ["render dry=1",
                    "infra --dry-run DOTFILES_DIR=",
                    f"agents --dry-run DOTFILES_DIR={self.repo}"])

    def test_missing_siblings_dry_run_never_contacts_network(self):
        self.fixture_siblings(existing=False)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                output = self.chain(shell)
                self.assertEqual(self.log(), "render dry=1\n")
                self.assertIn("would clone", output)

    def test_failed_pulls_and_sibling_deploys_do_not_stop_chain(self):
        self.fixture_siblings()
        self.env.update(DEPLOY_DRY_RUN="0", PULL_RC="1", DEPLOY_RC="2")
        self.fake("systemctl", 'printf "systemctl %s\\n" "$*" >> "$CALLS"; exit 0')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                output = self.chain(shell)
                calls = self.log()
                self.assertIn("pull --ff-only", calls)
                self.assertLess(calls.index("render dry=0"), calls.index("infra  "))
                self.assertLess(calls.index("infra  "), calls.index("agents  "))
                self.assertIn("WARNING", output)

    def test_worktree_overrides_are_used_without_cloning(self):
        self.fixture_siblings()
        overrides = {}
        for name in ("secrets", "infra", "agents"):
            source = self.home / ".local" / name
            target = self.base / "worktrees" / name
            target.parent.mkdir(exist_ok=True)
            source.rename(target)
            (target / ".git").rmdir()
            (target / ".git").write_text("gitdir: synthetic-common-directory\n")
            overrides[f"{name.upper()}_DIR"] = str(target)
        self.env.update(overrides, DEPLOY_DRY_RUN="0")
        # A worktree's hooks belong to its resolved gitdir, not .git/hooks.
        scripts = Path(overrides["SECRETS_DIR"]) / "scripts"
        scripts.mkdir()
        (scripts / "post-merge").write_text("#!/bin/sh\nexit 0\n")
        hooks = self.base / "common-gitdir/hooks"
        self.env["HOOKS_DIR"] = str(hooks)
        self.fake("git", 'printf "git %s\\n" "$*" >> "$CALLS"\n'
                  'case "$*" in *rev-parse*--git-path*hooks*) printf "%s\\n" "$HOOKS_DIR";; esac\n'
                  'exit "$PULL_RC"')
        self.fake("systemctl", "exit 0")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                output = self.chain(shell)
                self.assertNotIn("clone", self.log())
                self.assertIn(f"git -C {overrides['SECRETS_DIR']} pull --ff-only", self.log())
                self.assertIn(f"git -C {overrides['INFRA_DIR']} pull --ff-only", self.log())
                self.assertIn(f"git -C {overrides['AGENTS_DIR']} pull --ff-only", self.log())
                self.assertNotIn("Not a directory", output)
                self.assertTrue((hooks / "post-merge").is_symlink())
                self.assertEqual((hooks / "post-merge").resolve(), scripts / "post-merge")
                self.assertIn("agents  ", self.log())

    def test_install_dry_run_avoids_installers_and_privilege_probes(self):
        helpers = self.copy("scripts/deploy.d/lib/helpers.zsh")
        for name in ("50_mise", "70_runtime_installs", "79_keyd", "99_periodic"):
            fragment = self.copy(f"scripts/deploy.d/{name}.zsh")
            for shell in SHELLS:
                with self.subTest(fragment=name, shell=shell):
                    self.calls.unlink(missing_ok=True)
                    self.run_shell(shell, 'upgrade_mode=false; . "$1"; . "$2"',
                                   helpers, fragment)
                    self.assertEqual(self.log(), "")

    def test_renderer_metadata_without_secrets_checkout_or_sops(self):
        renderer = self.copy("scripts/secrets-render.zsh")
        (self.bin / "sops").unlink()
        before = self.snapshot_home()
        output = self.run_shell(SHELLS[1], '"$1" "$2" --print-map', SHELLS[1], renderer)
        self.assertIn("dotenv-select:CF_API_TOKEN", output)
        self.assertIn(str(self.home / ".local/state/caddy/env"), output)
        self.assertEqual(self.log(), "")
        self.assertEqual(before, self.snapshot_home())

    def test_renderer_selector_preserves_values_and_requires_keys(self):
        renderer = self.copy("scripts/secrets-render.zsh")
        for source, expected, status in (
            ("OTHER=ignored\nCF_API_TOKEN=synthetic=fixture\nCF_API_TOKEN=duplicate\n",
             "CF_API_TOKEN=synthetic=fixture\n", 0),
            ("CF_API_TOKEN=synthetic fixture", "CF_API_TOKEN=synthetic fixture\n", 0),
            ("OTHER=ignored\n", "", 1),
        ):
            with self.subTest(source=source):
                result = subprocess.run([SHELLS[1], str(renderer), "--select-dotenv", "CF_API_TOKEN"],
                    input=source, env=self.env, text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stdout, expected)
        self.assertEqual(self.log(), "")

    def test_real_renderer_dry_run_never_decrypts_or_writes(self):
        renderer = self.copy("scripts/secrets-render.zsh")
        sources = self.home / ".local/secrets/shell"
        sources.mkdir(parents=True)
        names = [f"shell/{name}.yaml" for name in (
            "90_secrets", "91_cloudflare_secrets", "92_telemetry_secrets",
            "93_google_oauth_secrets", "94_search_secrets", "94_zerotier_secrets",
            "95_tailscale_secrets")]
        names += re.findall(r'^_row\s+["\']?([\w/.-]+)', renderer.read_text(), re.M)
        for name in names:
            source = sources.parent / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("synthetic encrypted-file placeholder\n")
        target = self.home / ".local/state/secrets/zsh/90_secrets.zsh"
        target.parent.mkdir(parents=True)
        target.write_text("synthetic existing rendered sentinel\n")
        marker = self.home / ".local/state/secrets-render-ok"
        marker.write_text("synthetic existing marker sentinel\n")
        before = self.snapshot_home()
        # Both deploy drivers invoke this zsh entry through zsh; bash is a
        # syntax-gate target, not a supported renderer runtime.
        for shell in [SHELLS[1]]:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                output = self.run_shell(shell, '"$1" "$2" --dry-run', shell, renderer)
                self.assertIn("would render", output)
                self.assertEqual(self.log(), f"git -C {sources.parent} ls-files\n")
                self.assertEqual(before, self.snapshot_home())

    def test_real_drivers_dispatch_chain_with_non_fhs_path(self):
        self.fixture_siblings()
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        for name in ("65_secrets", "66_infra", "67_agents"):
            self.copy(f"scripts/deploy.d/{name}.zsh")
        for shell, driver in zip(SHELLS, ("deploy.bash", "deploy.zsh")):
            with self.subTest(driver=driver):
                entry = self.copy(driver)
                self.calls.unlink(missing_ok=True)
                before = self.snapshot_home()
                output = self.run_shell(shell, '"$1" "$2" --dry-run', shell, entry)
                self.assertIn("deploy finished", output)
                self.assertEqual(before, self.snapshot_home(), "driver dry-run changed HOME")
                self.assertEqual(self.log().splitlines(), ["render dry=1",
                    "infra --dry-run DOTFILES_DIR=",
                    f"agents --dry-run DOTFILES_DIR={self.repo}"])

    def test_real_drivers_honor_explicit_xdg_state_home(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        custom_state = self.home / "custom-state"
        self.env["XDG_STATE_HOME"] = str(custom_state)
        for shell, driver in zip(SHELLS, ("deploy.bash", "deploy.zsh")):
            with self.subTest(driver=driver):
                entry = self.copy(driver)
                self.run_shell(shell, '"$1" "$2" --only nonexistent', shell, entry)
                self.assertTrue((custom_state / "dotfiles-deploy.log").is_file(),
                                "driver ignored provided XDG_STATE_HOME")
                self.assertFalse((self.home / ".local/state/dotfiles-deploy.log").exists())

    @unittest.skipIf(os.geteuid() == 0, "real fragment chooses /etc for root; HOME isolation requires non-root")
    def test_periodic_unit_executes_git_from_non_fhs_path(self):
        self.fixture_siblings()
        helpers = self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragment = self.copy("scripts/deploy.d/99_periodic.zsh")
        hook = self.copy("scripts/post-merge")
        for name in ("deploy.bash", "deploy.zsh"):
            self.copy(name)
        for name in ("65_secrets", "66_infra", "67_agents"):
            self.copy(f"scripts/deploy.d/{name}.zsh")
        self.fake("git", 'printf "git %s\\n" "$*" >> "$CALLS"\n'
                  'case "$*" in -c*pull*) GIT_REFLOG_ACTION=pull /bin/sh "$FAKE_PULL_HOOK";; esac\n'
                  'exit "$PULL_RC"')
        self.env["DEPLOY_DRY_RUN"] = "0"
        self.env["FAKE_PULL_HOOK"] = str(hook)
        self.fake("systemctl", "exit 0")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.run_shell(shell, '. "$1"; . "$2"', helpers, fragment)
                unit = self.home / ".config/systemd/user/pull-dotfiles.service"
                self.assertTrue(unit.exists(), "periodic user unit was not placed")
                lines = unit.read_text().splitlines()
                command = next(line.removeprefix("ExecStart=") for line in lines
                               if line.startswith("ExecStart="))
                self.assertNotIn("/usr/bin/git", command)
                self.calls.unlink(missing_ok=True)
                argv = shlex.split(command.replace("%h", str(self.home)).replace("%%", "%"))
                unit_env = self.env.copy()
                unit_env["PATH"] = str(self.base / "manager-systemd-only")
                for line in lines:
                    if line.startswith("Environment="):
                        for setting in shlex.split(line.removeprefix("Environment=")):
                            key, value = setting.split("=", 1)
                            unit_env[key] = value.replace("%h", str(self.home)).replace("%%", "%")
                self.assertIn(str(self.home / ".local/share/mise/shims"), unit_env["PATH"])
                result = subprocess.run(argv, env=unit_env, cwd=self.repo,
                                        text=True, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("git ", self.log())
                self.assertIn("render dry=0", self.log())
                self.assertIn("infra  ", self.log())
                self.assertIn("agents  ", self.log())


if __name__ == "__main__":
    unittest.main()
