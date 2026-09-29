#!/usr/bin/env python3
"""Dotfiles-lane Pluto contracts, offline in a disposable HOME.

Complements test-nixos-integration.py (Sol's suite) with the contracts this
lane owns: driver dry-run zero-mutation (incl. a caller-supplied XDG_STATE_HOME
with spaces), sibling env overrides + worktree `.git`-file detection, mise
upgrade gating, per-package npm installs with the --libc override, and the
Pluto fork installer consuming the real pin checker's validated selector. No
network, no host mutations; runs on macOS and Linux with bash + zsh.
"""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHELLS = [str(Path("/bin/bash")) if Path("/bin/bash").is_file() else shutil.which("bash"),
          shutil.which("zsh")]
if not all(SHELLS):
    raise SystemExit("these tests require bash and zsh on PATH")


class LaneContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-lane-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.repo = self.base / "repo"          # fake dotfiles checkout (SCRIPT_DIR)
        self.bin = self.base / "bin"
        self.bin.mkdir(parents=True)
        self.calls = self.base / "calls"
        self.mise_args = self.base / "mise-argv"
        for tool in ("bash", "zsh", "sh", "uname", "date", "cat", "sed", "tail",
                     "head", "tee", "xargs",
                     "grep", "find", "sort", "mktemp", "mkdir", "ln", "rm",
                     "cp", "mv", "readlink", "basename", "dirname", "ldd",
                     "chmod", "git", "systemctl"):
            source = shutil.which(tool)
            if source:
                (self.bin / tool).symlink_to(source)
        self.env = {
            "HOME": str(self.home), "USER": "lane", "PATH": str(self.bin),
            "CALLS": str(self.calls), "TMPDIR": str(self.base),
            "MISE_ARGS": str(self.mise_args),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "SCRIPT_DIR": str(self.repo), "DOTFILES_OS": "Linux",
            "DOTFILES_ARCH": "x86_64", "DOTFILES_SKIP_BREW": "1",
            "DEPLOY_DRY_RUN": "0", "DEPLOY_FORCE": "0",
            "upgrade_mode": "false", "BASH_ENV": "/dev/null",
            "ZDOTDIR": str(self.home), "FAKE_HOST": "fixture",
            "PULL_RC": "0", "DEPLOY_RC": "0",
            "FAKE_GIT_HOOKS_DIR": str(self.base / "hooks"),
        }
        self.fake("uname", 'case "$1" in -s) echo Linux;; -m) echo x86_64;; '
                           '-n) echo "$FAKE_HOST";; esac')
        self.fake("git", 'printf "git %s\\n" "$*" >> "$CALLS"; '
                         'if [ "$1" = -C ]; then shift 2; fi; '
                         'case $1 in rev-parse) echo "$FAKE_GIT_HOOKS_DIR";; esac; exit "$PULL_RC"')
        self.fake("systemctl", 'printf "systemctl %s\\n" "$*" >> "$CALLS"; exit 0')
        self.fake("ldd", 'echo "ldd (GNU GLIBC) 2.40"')
        # Keep every installer offline, even if a fragment takes an unexpected
        # branch. These are executable fixtures, never the host's installers.
        self.fake("curl", 'printf "FORBIDDEN curl %s\\n" "$*" >> "$CALLS"; exit 99')
        for tool in ("coderabbit", "cargo", "linear-cli", "node", "corepack"):
            self.fake(tool, f'printf "{tool} %s\\n" "$*" >> "$CALLS"; exit 0')

    def tearDown(self):
        self.assertNotIn("FORBIDDEN", self.log(), "unexpected download attempt")

    def fake(self, name, body):
        target = self.bin / name
        if target.is_symlink():
            target.unlink()
        target.write_text("#!/bin/sh\n" + body + "\n")
        target.chmod(0o755)

    def copy(self, relative, dest=None):
        target = (self.repo / relative) if dest is None else Path(dest)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
        return target

    def run_shell(self, shell, code, *args, **kw):
        result = subprocess.run([shell, "-c", code, "lane", *map(str, args)],
                                env=self.env, text=True, capture_output=True, timeout=30)
        if kw.get("allow_fail"):
            return result
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def log(self):
        return self.calls.read_text() if self.calls.exists() else ""

    def fake_mise(self):
        # Model the CLI boundary, not mise internals: exec forwards argv after
        # -- verbatim and propagates its status (including an npm failure).
        self.fake("mise", '''printf "mise %s\\n" "$*" >> "$CALLS"
printf '%s\\0' "$@" >> "$MISE_ARGS"
printf '\\n' >> "$MISE_ARGS"
case "$1" in
    install)
        if [ "${MISE_INSTALL_RC:-0}" != 0 ]; then
            echo "synthetic install failure"
            exit "$MISE_INSTALL_RC"
        fi
        ;;
    exec)
        shift
        while [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done
        [ "$#" -gt 0 ] || exit 98
        shift
        exec "$@"
        ;;
esac
exit 0''')

    def xdg_with_spaces(self):
        xdg = self.base / "state dir with spaces"
        self.env["XDG_STATE_HOME"] = str(xdg)
        return xdg

    # ── drivers ───────────────────────────────────────────────────────────

    def test_driver_dry_run_never_touches_state_home(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        self.copy("deploy.zsh", self.repo / "deploy.zsh")
        self.copy("deploy.bash", self.repo / "deploy.bash")
        xdg = self.xdg_with_spaces()
        self.env["DEPLOY_DRY_RUN"] = "1"
        for shell, driver in zip(SHELLS, ("deploy.bash", "deploy.zsh")):
            with self.subTest(shell=shell, driver=driver):
                self.run_shell(shell, '"$1" --dry-run', self.repo / driver)
                self.assertFalse(xdg.exists(),
                                "dry-run created $XDG_STATE_HOME (log setup ran)")
                self.assertFalse((xdg / "dotfiles-deploy.log").exists())

    def test_driver_real_run_logs_into_supplied_xdg_with_spaces(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        self.copy("deploy.zsh", self.repo / "deploy.zsh")
        self.copy("deploy.bash", self.repo / "deploy.bash")
        xdg = self.xdg_with_spaces()
        for shell, driver in zip(SHELLS, ("deploy.bash", "deploy.zsh")):
            with self.subTest(shell=shell, driver=driver):
                (xdg / "dotfiles-deploy.log").unlink(missing_ok=True)
                self.run_shell(shell, '"$1"', self.repo / driver)
                self.assertTrue((xdg / "dotfiles-deploy.log").is_file(),
                                "real run must still tee the deploy log (quoted path)")
                self.assertIn("deploy started", (xdg / "dotfiles-deploy.log").read_text())

    # ── sibling overrides + worktree .git-file ────────────────────────────

    def test_sibling_env_overrides_and_worktree_git_file(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        for name in ("65_secrets", "66_infra", "67_agents"):
            self.copy(f"scripts/deploy.d/{name}.zsh")
        # Siblings at overridden paths, each a WORKTREE (`.git` is a file).
        secrets = self.base / "over rides/secrets"
        infra = self.base / "over rides/infra"
        agents = self.base / "over rides/agents"
        for sibling in (secrets, infra, agents):
            sibling.mkdir(parents=True)
            (sibling / ".git").write_text("gitdir: /main/repo/.git/worktrees/x\n")
        for name, sibling in (("infra", infra), ("agents", agents)):
            deploy = sibling / "deploy"
            deploy.write_text('#!/bin/sh\n'
                              f'printf "{name} %s DOTFILES_DIR=%s\\n" "$*" '
                              '"${DOTFILES_DIR:-}" >> "$CALLS"\nexit "$DEPLOY_RC"\n')
            deploy.chmod(0o755)
        key = self.home / ".config/sops/age/keys.txt"
        key.parent.mkdir(parents=True)
        key.write_text("synthetic lane fixture, not a key\n")
        (self.repo / "scripts").mkdir(parents=True, exist_ok=True)
        renderer = self.repo / "scripts/secrets-render.zsh"
        renderer.write_text('printf "render dry=%s\\n" "$DEPLOY_DRY_RUN" >> "$CALLS"\n')
        self.env.update(SECRETS_DIR=str(secrets), INFRA_DIR=str(infra),
                        AGENTS_DIR=str(agents))
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                hooks = self.base / "hooks"
                hooks.mkdir(exist_ok=True)
                # scripts/post-merge must exist in the (worktree) secrets repo
                # for the hook leg; verify the symlink lands in the
                # --git-path hooks dir the fake git reports.
                pm = secrets / "scripts" / "post-merge"
                pm.parent.mkdir(parents=True, exist_ok=True)
                pm.write_text("#!/bin/sh\nexit 0\n")
                pm.chmod(0o755)
                self.run_shell(shell, 'for f in "$@"; do . "$f" || exit; done',
                               self.repo / "scripts/deploy.d/lib/helpers.zsh",
                               self.repo / "scripts/deploy.d/65_secrets.zsh",
                               self.repo / "scripts/deploy.d/66_infra.zsh",
                               self.repo / "scripts/deploy.d/67_agents.zsh")
                calls = self.log()
                self.assertIn("render dry=0", calls)
                self.assertIn(f"git -C {secrets} pull --ff-only", calls)
                self.assertIn(f"git -C {infra} pull --ff-only", calls)
                self.assertIn(f"git -C {agents} pull --ff-only", calls)
                self.assertNotIn("clone", calls,
                                 "a present worktree must never be re-cloned")
                self.assertTrue((hooks / "post-merge").is_symlink(),
                                "post-merge hook must land in the --git-path hooks dir")
                self.assertIn("infra ", calls)
                self.assertIn("agents ", calls)
                self.assertIn("systemctl --user daemon-reload", calls)

    def test_siblings_dry_run_still_zero_mutation(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        for name in ("65_secrets", "66_infra", "67_agents"):
            self.copy(f"scripts/deploy.d/{name}.zsh")
        self.env["DEPLOY_DRY_RUN"] = "1"
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                self.run_shell(shell, 'for f in "$@"; do . "$f" || exit; done',
                               self.repo / "scripts/deploy.d/lib/helpers.zsh",
                               self.repo / "scripts/deploy.d/65_secrets.zsh",
                               self.repo / "scripts/deploy.d/66_infra.zsh",
                               self.repo / "scripts/deploy.d/67_agents.zsh")
                self.assertEqual(self.log(), "",
                                 "dry-run chain must invoke no fake tool at all")

    # ── mise upgrade gating ───────────────────────────────────────────────

    def test_mise_upgrade_only_under_upgrade_mode(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragment = self.copy("scripts/deploy.d/50_mise.zsh")
        self.fake("mise", 'printf "mise %s\\n" "$*" >> "$CALLS"; exit 0')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                self.run_shell(shell, '. "$1"; upgrade_mode=false; . "$2"',
                               self.repo / "scripts/deploy.d/lib/helpers.zsh", fragment)
                calls = self.log()
                self.assertIn("mise install", calls)
                self.assertNotIn("mise upgrade", calls,
                                 "plain deploy must not upgrade pinned tools")
                self.calls.unlink(missing_ok=True)
                self.run_shell(shell, '. "$1"; upgrade_mode=true; . "$2"',
                               self.repo / "scripts/deploy.d/lib/helpers.zsh", fragment)
                self.assertIn("mise upgrade --yes", self.log())

    # ── npm globals: batch fast path, failure isolation, --libc ────────────

    def test_npm_batch_success_and_per_package_retries_with_libc_flag(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragment = self.copy("scripts/deploy.d/70_runtime_installs.zsh")
        packages = self.repo / ".default-npm-packages"
        packages.write_text("t3\npi\noxlint\n")
        self.fake_mise()
        installed = self.base / "npm installed"
        self.env["NPM_FIXTURE_INSTALLS"] = str(installed)
        # Simulate the npm process boundary, not the fragment's retry policy.
        # A failed invocation materializes nothing; successful invocations
        # record their packages, making survivor installation observable.
        self.fake("npm", '''printf "npm %s\\n" "$*" >> "$CALLS"
[ "$1" = install ] || exit 0
shift
for package do
    if [ "${FAKE_NPM_FAIL_PI:-0}" = 1 ] && [ "$package" = pi ]; then
        echo "synthetic npm failure for pi" >&2
        exit 1
    fi
done
for package do
    case "$package" in -*) continue;; esac
    printf 'installed %s\\n' "$package" > "$NPM_FIXTURE_INSTALLS/$package"
done''')
        # A successful `mise exec node` represents an installed node prefix.
        # Supply it so the retired-global sweep sees a realistic install tree
        # rather than an unmatched zsh glob from an inconsistent fake mise.
        node_bin = self.home / ".local/share/mise/installs/node/24.0.0/bin"
        node_bin.mkdir(parents=True)
        (node_bin / "npm").symlink_to(self.bin / "npm")
        self.env["NPM_CONFIG_USERCONFIG"] = "/dev/null"
        for fail_pi in (False, True):
            self.env["FAKE_NPM_FAIL_PI"] = "1" if fail_pi else "0"
            for shell in SHELLS:
                with self.subTest(shell=shell, fail_pi=fail_pi):
                    self.calls.unlink(missing_ok=True)
                    if installed.exists():
                        shutil.rmtree(installed)
                    installed.mkdir()
                    result = self.run_shell(shell, '. "$1"; upgrade_mode=false; . "$2"',
                                            self.repo / "scripts/deploy.d/lib/helpers.zsh",
                                            fragment)
                    installs = [line for line in self.log().splitlines()
                                if line.startswith("npm install ")]
                    expected = ["npm install -g --libc=glibc t3 pi oxlint"]
                    if fail_pi:
                        expected += [f"npm install -g --libc=glibc {p}"
                                     for p in ("t3", "pi", "oxlint")]
                    self.assertEqual(installs, expected,
                                     "successful batches need one install; failed batches isolate retries")
                    survivors = {"t3", "oxlint"} if fail_pi else {"t3", "pi", "oxlint"}
                    self.assertEqual({p.name for p in installed.iterdir()}, survivors)
                    if fail_pi:
                        self.assertIn("pi failed", result)
                        self.assertIn("synthetic npm failure for pi", result)
                        self.assertIn("package(s) failed: pi", result)
                    else:
                        self.assertNotIn("pi failed", result)

    # ── Pluto fork runtime ────────────────────────────────────────────────

    def fork_fixture(self, cli="0.9.1", daemon="0.9.1-fork.1",
                     package="@camerontaylor/paseo-cli"):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        checker = self.copy("scripts/tests/check-paseo-pins.py")
        (self.bin / "python3").symlink_to(sys.executable)
        self.fake_mise()
        self.fake("paseo", 'printf "paseo %s\\n" "$*" >> "$CALLS"; '
                           'echo fixture-fork; exit "${PASEO_VERSION_RC:-0}"')
        infra = self.base / "infra with spaces"
        (infra / "nixos/hosts").mkdir(parents=True)
        (self.repo / "configs").mkdir()
        self.cli_declaration = self.repo / "configs/mise.toml"
        self.cli_declaration.write_text(
            '[tools]\n"npm:@getpaseo/cli" = '
            f'{{version="{cli}", os=["linux"]}}\n')
        self.daemon_declaration = infra / "nixos/hosts/pluto.nix"
        self.daemon_declaration.write_text(
            'systemd.services.paseo-daemon = { serviceConfig = {\n'
            f'ExecStart = "/fixture/mise exec npm:{package}@{daemon} -- "\n'
            '+ "paseo daemon run --home /fixture/home";\n}; };\n')
        self.marker = self.base / "synthetic NIXOS"
        self.marker.touch()
        self.env.update(INFRA_DIR=str(infra), FAKE_HOST="pluto.example.test",
                        NIXOS_FIXTURE_MARKER=str(self.marker))
        self.xdg_with_spaces()

        # Portable seam: run the CURRENT production host/runtime block, not
        # a Python reimplementation. Only its literal /etc/NIXOS operand is
        # redirected to a disposable file. Never create /etc/NIXOS or change
        # the hostname gate, checker, ref transformation, or mise operations.
        # Isolating the block excludes unrelated npm mise exec calls, so a
        # rejected checker can assert zero install/exec calls unambiguously.
        source = (ROOT / "scripts/deploy.d/70_runtime_installs.zsh").read_text()
        start = source.index("paseo_host=$(uname -n")
        end = source.index("\nunset paseo_host", start) + len("\nunset paseo_host")
        block = source[start:end]
        self.assertEqual(block.count("/etc/NIXOS"), 1,
                         "update the documented fixture seam if the host gate changes")
        block = block.replace("/etc/NIXOS", '"$NIXOS_FIXTURE_MARKER"')
        fragment = self.repo / "fork-runtime-fixture.zsh"
        fragment.write_text(block + "\n")
        return fragment, checker

    def run_fork(self, shell, fragment):
        self.calls.unlink(missing_ok=True)
        self.mise_args.unlink(missing_ok=True)
        return self.run_shell(shell, '. "$1"; upgrade_mode=false; . "$2"',
                              self.repo / "scripts/deploy.d/lib/helpers.zsh", fragment)

    def test_pluto_valid_pins_install_exact_scoped_selector_then_exec_plain_ref(self):
        fragment, _ = self.fork_fixture(cli="2.4.6", daemon="2.4.6-fork.7")
        ref = "npm:@camerontaylor/paseo-cli@2.4.6-fork.7"
        stock_shim = self.home / ".local/bin/paseo"
        stock_shim.parent.mkdir(parents=True)
        stock_shim.write_text("synthetic stock shim; must survive\n")
        declarations = (self.cli_declaration.read_bytes(),
                        self.daemon_declaration.read_bytes())
        for shell in SHELLS:
            with self.subTest(shell=shell):
                output = self.run_fork(shell, fragment)
                self.assertEqual(self.log().splitlines(), [
                    "mise install npm:@camerontaylor/paseo-cli"
                    "[allow_low_downloads=true]@2.4.6-fork.7",
                    f"mise exec {ref} -- paseo --version", "paseo --version"])
                self.assertEqual(self.mise_args.read_bytes(), (
                    "install\0npm:@camerontaylor/paseo-cli"
                    "[allow_low_downloads=true]@2.4.6-fork.7\0\n"
                    f"exec\0{ref}\0--\0paseo\0--version\0\n").encode())
                self.assertIn("fixture-fork", output,
                              "mise exec must actually run the version probe")
                self.assertEqual(declarations, (self.cli_declaration.read_bytes(),
                                               self.daemon_declaration.read_bytes()))
                self.assertEqual(stock_shim.read_text(),
                                 "synthetic stock shim; must survive\n")
                self.assertFalse((self.home / ".config/mise").exists())
                self.assertFalse((Path(self.env["XDG_STATE_HOME"]) /
                                  "paseo-fork-install.log").exists())

    def test_pluto_failed_checker_with_valid_looking_stdout_never_calls_mise(self):
        fragment, checker = self.fork_fixture()
        # Exercise the subprocess exit-status boundary, including partial
        # output that could trick a caller trusting stdout alone.
        checker.write_text('import sys\n'
                           'print("npm:@camerontaylor/paseo-cli@0.9.1-fork.1")\n'
                           'print("synthetic checker rejection", file=sys.stderr)\n'
                           'sys.exit(1)\n')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                output = self.run_fork(shell, fragment)
                self.assertEqual(self.log(), "")
                self.assertIn("synthetic checker rejection", output)
                self.assertIn("NOT materialized", output)
                self.assertFalse(Path(self.env["XDG_STATE_HOME"]).exists())

    def test_pluto_real_checker_rejects_pin_mismatch_and_wrong_role(self):
        fragment, _ = self.fork_fixture()
        valid = self.daemon_declaration.read_text()
        for invalid, diagnostic in (
            (valid.replace("0.9.1-fork.1", "0.9.2-fork.1"), "mismatch"),
            (valid.replace("@camerontaylor/paseo-cli", "@getpaseo/cli"), "daemon role"),
        ):
            self.daemon_declaration.write_text(invalid)
            for shell in SHELLS:
                with self.subTest(shell=shell, diagnostic=diagnostic):
                    output = self.run_fork(shell, fragment)
                    self.assertEqual(self.log(), "")
                    self.assertIn(diagnostic, output)
                    self.assertIn("NOT materialized", output)
                    self.assertFalse(Path(self.env["XDG_STATE_HOME"]).exists())

    def test_pluto_missing_infra_warns_without_install(self):
        fragment, _ = self.fork_fixture()
        self.env["INFRA_DIR"] = str(self.base / "absent infra")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                output = self.run_fork(shell, fragment)
                self.assertIn("missing", output)
                self.assertEqual(self.log(), "")
                self.assertFalse(Path(self.env["INFRA_DIR"]).exists())
                self.assertFalse(Path(self.env["XDG_STATE_HOME"]).exists())

    def test_fork_runtime_skips_other_nixos_hosts_and_non_nixos_pluto(self):
        fragment, checker = self.fork_fixture()
        # Make an accidental checker invocation observable, even if mise is
        # subsequently skipped. Valid declarations alone would hide it.
        checker.write_text('import os\nfrom pathlib import Path\n'
                           'Path(os.environ["CALLS"]).write_text("unexpected checker\\n")\n'
                           'raise SystemExit(1)\n')
        for host, nixos in (("ceres.example.test", True), ("pluto", False)):
            self.env["FAKE_HOST"] = host
            if not nixos:
                self.marker.unlink()
            for shell in SHELLS:
                with self.subTest(shell=shell, host=host, nixos=nixos):
                    self.assertEqual(self.run_fork(shell, fragment), "")
                    self.assertEqual(self.log(), "")
                    self.assertFalse(Path(self.env["XDG_STATE_HOME"]).exists())

    def test_pluto_install_failure_keeps_diagnostics_and_never_executes_fork(self):
        fragment, _ = self.fork_fixture()
        self.env["MISE_INSTALL_RC"] = "17"
        for shell in SHELLS:
            with self.subTest(shell=shell):
                output = self.run_fork(shell, fragment)
                self.assertEqual(self.log().splitlines(), [
                    "mise install npm:@camerontaylor/paseo-cli"
                    "[allow_low_downloads=true]@0.9.1-fork.1"])
                self.assertIn("synthetic install failure", output)
                self.assertIn("WARNING", output)
                log = Path(self.env["XDG_STATE_HOME"]) / "paseo-fork-install.log"
                self.assertIn("synthetic install failure", log.read_text())

    def test_runtime_dry_run_never_calls_installers(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragment = self.copy("scripts/deploy.d/70_runtime_installs.zsh")
        self.fake_mise()
        self.env["DEPLOY_DRY_RUN"] = "1"
        before = list(self.home.rglob("*"))
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.calls.unlink(missing_ok=True)
                self.run_shell(shell, '. "$1"; upgrade_mode=true; . "$2"',
                               self.repo / "scripts/deploy.d/lib/helpers.zsh", fragment)
                self.assertEqual(self.log(), "")
                self.assertEqual(list(self.home.rglob("*")), before)

    def test_karabiner_dry_run_never_executes_bun_or_changes_config(self):
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragment = self.copy("scripts/deploy.d/78_karabiner.zsh")
        source = self.repo / "configs/karabiner/karabiner.ts"
        source.parent.mkdir(parents=True)
        source.write_text("// synthetic generator input; never executed\n")
        config_home = self.home / "configuration with spaces"
        target = config_home / "karabiner/karabiner.json"
        self.env.update(DOTFILES_OS="Darwin", DEPLOY_DRY_RUN="1",
                        XDG_CONFIG_HOME=str(config_home))
        # If the production dry-run guard regresses, this fake generator both
        # records the call and writes only inside our disposable HOME. No real
        # bun or macOS configuration tools are reachable through this fixture.
        self.fake("bun", 'printf "bun %s\\n" "$*" >> "$CALLS"; '
                         'mkdir -p "$XDG_CONFIG_HOME/karabiner"; '
                         'echo unexpected-generation > "$XDG_CONFIG_HOME/karabiner/karabiner.json"')
        for existing in (False, True):
            for shell in SHELLS:
                with self.subTest(shell=shell, existing=existing):
                    if config_home.exists():
                        shutil.rmtree(config_home)
                    if existing:
                        target.parent.mkdir(parents=True)
                        target.write_text('{"synthetic": "live GUI preference"}\n')
                        target.with_suffix(".json.bak").write_text("prior backup\n")
                        # Force the normal regeneration condition, so skipping
                        # bun cannot be explained by an up-to-date target.
                        os.utime(target, (100, 100))
                        os.utime(source, (200, 200))
                    before = {p.relative_to(self.home): p.read_bytes() if p.is_file() else None
                              for p in self.home.rglob("*")}
                    self.calls.unlink(missing_ok=True)
                    self.run_shell(shell, '. "$1"; upgrade_mode=false; . "$2"',
                                   self.repo / "scripts/deploy.d/lib/helpers.zsh", fragment)
                    self.assertEqual(self.log(), "", "dry-run executed the TypeScript runtime")
                    self.assertEqual(before, {
                        p.relative_to(self.home): p.read_bytes() if p.is_file() else None
                        for p in self.home.rglob("*")})

    # ── pinned plugin submodules ──────────────────────────────────────────

    def plugin_fixture(self):
        self.repo = self.base / "plugin repo with spaces"
        self.env["SCRIPT_DIR"] = str(self.repo)
        self.copy("scripts/deploy.d/lib/helpers.zsh")
        fragment = self.copy("scripts/deploy.d/30_plugins.zsh")
        (self.repo / "zsh/plugins").mkdir(parents=True)
        pin = "a" * 40
        plugin = self.repo / "plugins/fixture"
        (self.repo / "plugins.lock").write_text(
            f"{pin} plugins/fixture https://invalid.example/fixture.git\n")
        self.env.update(PLUGIN_PIN=pin, SUBMODULE_RC="0")
        # A minimal repository boundary: HEAD is stored in a file, cloning
        # materializes a synthetic tree, checkout changes HEAD. Submodule
        # content is independent of the parent HEAD, just like real gitlinks.
        self.fake("git", '''printf "git %s\\n" "$*" >> "$CALLS"
repo=.
if [ "$1" = -C ]; then repo=$2; shift 2; fi
case "$1" in
    rev-parse)
        [ -f "$repo/.fixture-head" ] || exit 1
        case "$2" in
            HEAD) cat "$repo/.fixture-head";;
            --git-dir) echo .git;;
            *) exit 97;;
        esac
        ;;
    clone)
        for target do :; done
        mkdir -p "$target"
        echo cloned-head > "$target/.fixture-head"
        echo '[submodule "fixture-dependency"]' > "$target/.gitmodules"
        ;;
    fetch) :;;
    checkout)
        for revision do :; done
        printf '%s\\n' "$revision" > "$repo/.fixture-head"
        ;;
    submodule)
        [ "$SUBMODULE_RC" = 0 ] || exit "$SUBMODULE_RC"
        echo materialized > "$repo/.fixture-submodules"
        ;;
    *) exit 96;;
esac''')
        return fragment, plugin, pin

    def run_plugin(self, shell, fragment):
        self.calls.unlink(missing_ok=True)
        return self.run_shell(shell, '. "$1"; upgrade_mode=false; . "$2"',
                              self.repo / "scripts/deploy.d/lib/helpers.zsh", fragment)

    def test_plugin_at_pin_still_materializes_missing_submodules(self):
        fragment, plugin, pin = self.plugin_fixture()
        plugin.mkdir(parents=True)
        (plugin / ".fixture-head").write_text(pin + "\n")
        (plugin / ".gitmodules").write_text('[submodule "fixture-dependency"]\n')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                (plugin / ".fixture-submodules").unlink(missing_ok=True)
                self.run_plugin(shell, fragment)
                self.assertEqual(self.log().splitlines(), [
                    f"git -C {plugin} rev-parse HEAD",
                    f"git -C {plugin} submodule update --init --recursive --quiet"])
                self.assertEqual((plugin / ".fixture-submodules").read_text(), "materialized\n")

    def test_plugin_new_clone_and_off_pin_both_update_submodules(self):
        fragment, plugin, pin = self.plugin_fixture()
        for state in ("missing", "off-pin"):
            for shell in SHELLS:
                with self.subTest(shell=shell, state=state):
                    if plugin.exists():
                        shutil.rmtree(plugin)
                    if state == "off-pin":
                        plugin.mkdir(parents=True)
                        (plugin / ".fixture-head").write_text("b" * 40 + "\n")
                        (plugin / ".gitmodules").write_text('[submodule "fixture-dependency"]\n')
                    self.run_plugin(shell, fragment)
                    calls = self.log().splitlines()
                    checkout = f"git -C {plugin} checkout --quiet --detach {pin}"
                    submodule = f"git -C {plugin} submodule update --init --recursive --quiet"
                    self.assertIn(checkout, calls)
                    self.assertIn(submodule, calls)
                    self.assertLess(calls.index(checkout), calls.index(submodule))
                    self.assertEqual(any(line.startswith("git clone ") for line in calls),
                                     state == "missing")
                    self.assertEqual((plugin / ".fixture-head").read_text(), pin + "\n")
                    self.assertEqual((plugin / ".fixture-submodules").read_text(), "materialized\n")

    def test_plugin_dry_run_never_updates_submodules_or_checkouts(self):
        fragment, plugin, pin = self.plugin_fixture()
        self.env["DEPLOY_DRY_RUN"] = "1"
        for state in ("at-pin", "off-pin", "missing"):
            for shell in SHELLS:
                with self.subTest(shell=shell, state=state):
                    if plugin.exists():
                        shutil.rmtree(plugin)
                    if state != "missing":
                        plugin.mkdir(parents=True)
                        (plugin / ".fixture-head").write_text(pin if state == "at-pin" else "b" * 40)
                        (plugin / ".gitmodules").write_text('[submodule "fixture-dependency"]\n')
                    before = {p.relative_to(self.repo): p.read_bytes()
                              for p in self.repo.rglob("*") if p.is_file()}
                    self.run_plugin(shell, fragment)
                    self.assertTrue(all(line.endswith("rev-parse HEAD")
                                        for line in self.log().splitlines()))
                    self.assertEqual(before, {p.relative_to(self.repo): p.read_bytes()
                                              for p in self.repo.rglob("*") if p.is_file()})
                    self.assertEqual(plugin.exists(), state != "missing")

    def test_plugin_submodule_failure_warns_and_deploy_continues(self):
        fragment, plugin, pin = self.plugin_fixture()
        plugin.mkdir(parents=True)
        (plugin / ".fixture-head").write_text(pin + "\n")
        (plugin / ".gitmodules").write_text('[submodule "fixture-dependency"]\n')
        self.env["SUBMODULE_RC"] = "19"
        for shell in SHELLS:
            with self.subTest(shell=shell):
                output = self.run_plugin(shell, fragment)
                self.assertIn("WARNING: submodule sync failed", output)
                self.assertIn("plugins/fixture", output)
                self.assertFalse((plugin / ".fixture-submodules").exists())


if __name__ == "__main__":
    unittest.main()
