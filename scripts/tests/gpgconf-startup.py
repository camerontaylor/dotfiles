#!/usr/bin/env python3
"""Exercise SSH socket startup with isolated sockets and gpgconf stubs.

Run with python3 scripts/tests/gpgconf-startup.py. Never starts a real agent.
"""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
ZSH = shutil.which('zsh')
TIMEOUT = shutil.which('timeout') or shutil.which('gtimeout')
assert ZSH and TIMEOUT, 'tests require zsh and GNU timeout (or gtimeout)'
assert os.geteuid() != 0, 'socket setup intentionally skips root shells'


def check(name, stub=None, *, timer='timeout', fallback=False, forwarded=False,
          remote=False, expected=True, deadline=7):
    with tempfile.TemporaryDirectory(prefix='gpgconf-startup-') as directory:
        base = Path(directory)
        home = base / 'home'
        (home / '.ssh').mkdir(parents=True)
        bin_dir = base / 'bin'
        bin_dir.mkdir()
        gnupg = base / 'gnupg'
        gnupg.mkdir()
        agent_socket = gnupg / ('S.gpg-agent.ssh' if fallback else 'custom.sock')
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(agent_socket))
            if timer:
                (bin_dir / timer).symlink_to(TIMEOUT)
            if stub is not None:
                executable = bin_dir / 'gpgconf'
                executable.write_text('#!/bin/sh\n' + stub + '\n')
                executable.chmod(0o755)
            env = {
                'HOME': str(home), 'PATH': str(bin_dir),
                'GNUPGHOME': str(gnupg), 'XDG_RUNTIME_DIR': str(base / 'run'),
                'TEST_SOCKET': str(agent_socket), 'TEST_LOG': str(base / 'calls'),
                'TEST_FRAGMENT': str(ROOT / 'zsh/rc.d/19_ssh_auth_sock.zsh'),
            }
            if forwarded:
                env['SSH_AUTH_SOCK'] = str(agent_socket)
            if remote:
                env['SSH_CONNECTION'] = 'test'
            started = time.monotonic()
            result = subprocess.run(
                [ZSH, '-dfc', '''
                    zmodload -F zsh/files b:zf_ln
                    setopt extendedglob
                    source "$TEST_FRAGMENT"
                    if [[ -n ${SSH_AUTH_SOCK:-} ]]; then
                        [[ -S $SSH_AUTH_SOCK ]] || exit 2
                        [[ $SSH_AUTH_SOCK == $HOME/.ssh/ssh_auth_sock ]] || exit 3
                        print selected
                    else
                        print absent
                    fi
                '''], env=env, capture_output=True, text=True, timeout=8,
            )
            elapsed = time.monotonic() - started
            assert result.returncode == 0, (name, result.stderr)
            want = 'selected' if expected else 'absent'
            assert result.stdout.strip() == want, (name, result.stdout, result.stderr)
            assert elapsed < deadline, (name, elapsed)
            if forwarded or remote or not timer:
                assert not (base / 'calls').exists(), name
            print(f'{name}: PASS ({elapsed:.2f}s)')


NORMAL = '''echo "$1" >> "$TEST_LOG"
case "$1" in
    --launch) exit 0 ;;
    --list-dirs) printf '%s\\n' "$TEST_SOCKET" ;;
esac'''
HANG = '''trap '' TERM
exec /bin/sleep 30'''
check('normal', NORMAL)
check('gtimeout alias', NORMAL, timer='gtimeout')
check('missing gpgconf fallback', fallback=True)
check('missing gpgconf no socket', expected=False)
check('missing timeout fallback', NORMAL, timer=None, fallback=True)
check('launch failure fallback', 'exit 1', fallback=True)
check('hung launch fallback', HANG, fallback=True, deadline=7)
check('hung lookup fallback', '''case "$1" in
    --launch) exit 0 ;;
    *) trap '' TERM; exec /bin/sleep 30 ;;
esac''', fallback=True, deadline=7)
check('failed lookup discards output', '''case "$1" in
    --launch) exit 0 ;;
    *) printf '%s\\n' "$TEST_SOCKET"; exit 1 ;;
esac''', expected=False)
check('forwarded socket bypasses gpgconf', NORMAL, forwarded=True, remote=True)
check('remote shell bypasses gpgconf', NORMAL, remote=True, expected=False)
