#!/usr/bin/env python3
"""Exercise sibling failure semantics with a disposable HOME and fake git."""
from pathlib import Path
import subprocess
import tempfile
import unittest

FRAGMENT = Path(__file__).resolve().parents[1] / 'deploy.d/67_agents.zsh'


class AgentsChain(unittest.TestCase):
    def run_case(self, shell, *, existing=False, dry=False, pull_rc=0, deploy_rc=0):
        with tempfile.TemporaryDirectory(prefix='agents-chain-') as directory:
            home = Path(directory)
            repo = home / '.local/agents'
            guard = home / 'bin'
            guard.mkdir()
            calls = home / 'calls'
            git = guard / 'git'
            git.write_text('#!/bin/sh\nprintf "git %s\\n" "$*" >> "$CALLS"\n'
                           'exit "$PULL_RC"\n')
            git.chmod(0o755)
            if existing:
                (repo / '.git').mkdir(parents=True)
                deploy = repo / 'deploy'
                deploy.write_text('#!/bin/sh\nprintf "deploy %s\\n" "$*" >> "$CALLS"\n'
                                  'exit "$DEPLOY_RC"\n')
                deploy.chmod(0o755)
            env = {'HOME': str(home), 'AGENTS_DIR': str(repo),
                   'PATH': str(guard) + ':/usr/bin:/bin', 'CALLS': str(calls),
                   'PULL_RC': str(pull_rc), 'DEPLOY_RC': str(deploy_rc),
                   'DEPLOY_DRY_RUN': str(int(dry)), 'BASH_ENV': '/dev/null',
                   'ZDOTDIR': str(home)}
            result = subprocess.run([shell, '-c',
                'have() { command -v "$1" >/dev/null 2>&1; }; . "$1"',
                'chain-test', str(FRAGMENT)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            return calls.read_text() if calls.exists() else '', result.stdout + result.stderr

    def test_absent_dry_run_does_not_clone(self):
        for shell in ['/bin/bash', 'zsh']:
            with self.subTest(shell=shell):
                calls, output = self.run_case(shell, dry=True)
                self.assertEqual(calls, '')
                self.assertIn('clone', output)

    def test_clone_failure_is_nonfatal(self):
        for shell in ['/bin/bash', 'zsh']:
            with self.subTest(shell=shell):
                calls, _ = self.run_case(shell, pull_rc=1)
                self.assertIn('git clone', calls)
                self.assertNotIn('deploy ', calls)

    def test_dry_run_is_forwarded_without_pull(self):
        for shell in ['/bin/bash', 'zsh']:
            with self.subTest(shell=shell):
                calls, _ = self.run_case(shell, existing=True, dry=True, deploy_rc=2)
                self.assertEqual(calls, 'deploy --dry-run\n')

    def test_divergence_and_deploy_failure_are_nonfatal(self):
        for shell in ['/bin/bash', 'zsh']:
            with self.subTest(shell=shell):
                calls, output = self.run_case(shell, existing=True, pull_rc=1, deploy_rc=2)
                self.assertIn('pull --ff-only', calls)
                self.assertIn('deploy ', calls)
                self.assertIn('WARNING', output)


if __name__ == '__main__':
    unittest.main()
