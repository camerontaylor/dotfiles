#!/usr/bin/env python3
"""Offline contracts for scripts/deploy.d/71_agents_auth.zsh (synthetic only).

Bash 3.2 + zsh, paths WITH SPACES throughout. No real agents checkout, no
real secrets, no network; all writes stay inside the disposable HOME.

Cases: fresh bootstrap (render THEN auth, exact order), warm zero calls,
dry-run zero calls/writes, missing CLI / missing agents zero calls,
renderer failure (warn-only, zero auth calls), helper failure (warn-only,
exit 0), CODEX_HOME override in the warm check, owner-symlink agents
checkout.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHELLS = [str(Path("/bin/bash")) if Path("/bin/bash").is_file() else shutil.which("bash"),
          shutil.which("zsh")]
if not all(SHELLS):
    raise SystemExit("these tests require bash and zsh on PATH")


class AgentsAuthFinalizer(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agents-auth-finalizer-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        # Spaces in every sandbox root the fragment resolves.
        self.home = self.base / "home dir"
        self.home.mkdir()
        self.repo = self.base / "dot files repo"          # SCRIPT_DIR
        self.agents = self.base / "agent checkouts" / "agents"
        self.agents.mkdir(parents=True)
        self.state = self.home / ".local" / "state"
        self.bin = self.base / "bin dir"
        self.bin.mkdir(parents=True)
        self.calls = self.base / "calls log"
        for tool in ("bash", "zsh", "sh", "cat", "sed", "tail", "grep", "find",
                     "sort", "mktemp", "mkdir", "ln", "rm", "cp", "mv",
                     "readlink", "basename", "dirname", "chmod", "pwd", "uname"):
            source = shutil.which(tool)
            if source:
                (self.bin / tool).symlink_to(source)
        codex = self.bin / "codex"
        codex.write_text("#!/bin/sh\nexit 0\n")
        codex.chmod(0o755)
        (self.repo / "scripts/deploy.d/lib").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/deploy.d/lib/helpers.zsh",
                     self.repo / "scripts/deploy.d/lib/helpers.zsh")
        shutil.copy2(ROOT / "scripts/deploy.d/71_agents_auth.zsh",
                     self.repo / "scripts/deploy.d/71_agents_auth.zsh")
        # Fake renderer: records; renders the env row unless RENDER_FAIL exists.
        (self.repo / "scripts/secrets-render.zsh").write_text(
            'printf "render\\n" >> "$CALLS"\n'
            'if [ -f "$RENDER_FAIL" ]; then exit 1; fi\n'
            'mkdir -p "$(dirname "$XDG_STATE_HOME/codex/env")"\n'
            'printf "OPENAI_API_KEY=synthetic-not-a-secret\\n" > "$XDG_STATE_HOME/codex/env"\n')
        # Fake agents-owned helper: records; fails if HELPER_FAIL exists.
        (self.agents / "scripts/setup-codex-auth.sh").parent.mkdir(parents=True, exist_ok=True)
        (self.agents / "scripts/setup-codex-auth.sh").write_text(
            '#!/bin/sh\nprintf "auth\\n" >> "$CALLS"\n'
            'if [ -f "$HELPER_FAIL" ]; then exit 1; fi\nexit 0\n')
        (self.agents / "scripts/setup-codex-auth.sh").chmod(0o755)
        self.common_env = {
            "HOME": str(self.home), "PATH": str(self.bin),
            "CALLS": str(self.calls), "TMPDIR": str(self.base),
            "XDG_STATE_HOME": str(self.state),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "SCRIPT_DIR": str(self.repo), "AGENTS_DIR": str(self.agents),
            "DOTFILES_OS": "Linux", "DOTFILES_ARCH": "x86_64",
            "DEPLOY_DRY_RUN": "0", "DEPLOY_FORCE": "0",
            "RENDER_FAIL": str(self.base / "no-render-fail"),
            "HELPER_FAIL": str(self.base / "no-helper-fail"),
        }

    def run_fragment(self, shell, env_overrides=None, allow_fail=False):
        env = dict(self.common_env)
        env.update(env_overrides or {})
        result = subprocess.run(
            [shell, "-c", '. "$1"; . "$2"', "finalizer",
             self.repo / "scripts/deploy.d/lib/helpers.zsh",
             self.repo / "scripts/deploy.d/71_agents_auth.zsh"],
            env=env, text=True, capture_output=True, timeout=30)
        if not allow_fail:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def log(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def reset_sandbox(self):
        """Fresh state per shell leg: no rendered env, no auth, no call log."""
        shutil.rmtree(self.home / ".codex", ignore_errors=True)
        shutil.rmtree(self.state, ignore_errors=True)
        self.calls.unlink(missing_ok=True)

    def make_env_and_auth(self, codex_home=None):
        (self.state / "codex").mkdir(parents=True, exist_ok=True)
        (self.state / "codex/env").write_text("OPENAI_API_KEY=synthetic-not-a-secret\n")
        auth_dir = Path(codex_home) if codex_home else (self.home / ".codex")
        auth_dir.mkdir(parents=True, exist_ok=True)
        (auth_dir / "auth.json").write_text("{}\n")

    # 1 ── fresh bootstrap: renderer -> helper, exact ordering ─────────────

    def test_fresh_bootstrap_renders_then_auths(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                out = self.run_fragment(shell)
                self.assertEqual(self.log(), ["render", "auth"],
                                 f"ordering/output wrong: {self.log()} {out}")

    # 2 ── warm steady state: zero calls ────────────────────────────────────

    def test_warm_skips_entirely(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.make_env_and_auth()
                self.run_fragment(shell)
                self.assertEqual(self.log(), [])

    def test_auth_cache_without_env_skips(self):
        # ChatGPT OAuth host (2026-10-02): auth.json present, no rendered
        # codex/env. Must not re-render or dispatch on every deploy.
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.make_env_and_auth()
                (self.state / "codex/env").unlink()
                self.run_fragment(shell)
                self.assertEqual(self.log(), [])

    def test_warm_dangling_owner_symlink_skips(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.make_env_and_auth()
                # Owner symlink whose target is gone: still "present" — the
                # helper would only preserve-and-exit, so never dispatch.
                (self.home / ".codex/auth.json").unlink()
                (self.home / ".codex/auth.json").symlink_to(self.base / "gone-target")
                self.run_fragment(shell)
                self.assertEqual(self.log(), [])

    # 3 ── dry-run: zero calls, zero writes ─────────────────────────────────

    def test_dry_run_never_calls_or_writes(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.run_fragment(shell, {"DEPLOY_DRY_RUN": "1"})
                self.assertEqual(self.log(), [])
                self.assertFalse((self.state / "codex/env").exists(),
                                 "dry-run must not render the env file")

    # 4 ── missing pieces: zero calls ───────────────────────────────────────

    def test_missing_cli_zero_calls(self):
        codex = self.bin / "codex"
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                codex.unlink(missing_ok=True)
                try:
                    self.run_fragment(shell)
                finally:
                    codex.write_text("#!/bin/sh\nexit 0\n")
                    codex.chmod(0o755)
                self.assertEqual(self.log(), [])

    def test_missing_agents_checkout_zero_calls(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.run_fragment(shell, {"AGENTS_DIR": str(self.base / "no agents here")})
                self.assertEqual(self.log(), [])

    # 5 ── renderer failure: warn-only, NO auth call ────────────────────────

    def test_renderer_failure_no_auth(self):
        marker = self.base / "render fails"
        marker.write_text("")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                result = self.run_fragment(shell, {"RENDER_FAIL": str(marker)},
                                           allow_fail=True)
                self.assertEqual(result.returncode, 0, "warn-only: deploy stays green")
                self.assertEqual(self.log(), ["render"],
                                 "auth must never run off a failed render")
                self.assertIn("WARNING", result.stderr)

    # 6 ── helper failure: warn-only, exit 0 ────────────────────────────────

    def test_helper_failure_warn_only(self):
        marker = self.base / "helper fails"
        marker.write_text("")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                result = self.run_fragment(shell, {"HELPER_FAIL": str(marker)},
                                           allow_fail=True)
                self.assertEqual(result.returncode, 0, "warn-only: deploy stays green")
                self.assertEqual(self.log(), ["render", "auth"])
                self.assertIn("WARNING", result.stderr)

    # 7 ── overrides: CODEX_HOME warm check + owner-symlink checkout ───────

    def test_codex_home_override_warm(self):
        alt = self.base / "codex home dir"
        self.make_env_and_auth(codex_home=alt)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.make_env_and_auth(codex_home=alt)
                self.calls.unlink(missing_ok=True)
                self.run_fragment(shell, {"CODEX_HOME": str(alt)})
                self.assertEqual(self.log(), [], "CODEX_HOME override must be honored")

    def test_symlink_agents_checkout_proceeds(self):
        link = self.base / "agents link"
        link.symlink_to(self.agents, target_is_directory=True)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.reset_sandbox()
                self.run_fragment(shell, {"AGENTS_DIR": str(link)})
                self.assertEqual(self.log(), ["render", "auth"])


if __name__ == "__main__":
    unittest.main()
