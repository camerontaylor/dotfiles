#!/usr/bin/env python3
"""Check the fixed Linux CLI/Pluto daemon pins offline (Python 3.11+).

Usage: check-paseo-pins.py --dotfiles REPO --infra REPO
Defaults: ~/.local/dotfiles and ~/.local/infra. Run --self-test for disposable
synthetic fixtures. Agents' setup beta channel is deliberately not a pin.
The stock @getpaseo/cli must use a stable version; the daemon must use
@camerontaylor/paseo-cli at that exact base plus -fork.POSITIVEINTEGER.
The daemon command must use `paseo daemon run`, without --foreground.
--print-daemon-tool prints only the validated npm selector for installers.
Only declaration files are read; no shell, Nix, mise or network is invoked.
Unknown declaration shapes fail rather than guessing their effective version.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
import tempfile
import tomllib
import unittest


STABLE_BASE = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
VERSION = re.compile(STABLE_BASE)
FORK_VERSION = re.compile(r"(" + STABLE_BASE + r")-fork\.[1-9][0-9]*")
CLI_TOOL = "npm:@getpaseo/cli"
DAEMON_TOOL = "npm:@camerontaylor/paseo-cli"
NIX_STRING = r'"(?:\\.|[^"\\])*"'
# Preserve strings while removing comments, so a commented pin never passes.
NIX_TOKEN = re.compile(r'#[^\n]*|/\*[\s\S]*?\*/|' + NIX_STRING + r"|''[\s\S]*?''|[{}]")


def exact_version(value: object, source: str) -> str:
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError(f"{source}: missing or unknown exact stable version pin")
    return value


def cli_pin(path: Path) -> str:
    data = tomllib.loads(path.read_text())
    tools = data.get("tools", {})
    tool = tools.get(CLI_TOOL) if isinstance(tools, dict) else None
    if not isinstance(tool, dict) or tool.get("os") != ["linux"]:
        raise ValueError(f"{path}: expected Linux-only npm:@getpaseo/cli declaration")
    return exact_version(tool.get("version"), str(path))


def daemon_pin(path: Path) -> str:
    text = path.read_text()
    # Recognize only the current explicit attribute block, not evaluated Nix.
    text = NIX_TOKEN.sub(
        lambda m: " " if m[0].startswith(("#", "/*")) else m[0], text
    )
    blocks = list(re.finditer(r"\bsystemd\.services\.paseo-daemon\s*=\s*\{", text))
    if len(blocks) != 1:
        raise ValueError(f"{path}: expected one explicit paseo-daemon service block")
    start = blocks[0].end()
    depth = 1
    end = None
    for token in NIX_TOKEN.finditer(text, start):
        if token[0] == "{":
            depth += 1
        elif token[0] == "}":
            depth -= 1
            if depth == 0:
                end = token.start()
                break
    if end is None:
        raise ValueError(f"{path}: unclosed paseo-daemon service block")
    body = text[start:end]
    declarations = list(re.finditer(r"\bExecStart\s*=", body))
    if len(declarations) != 1:
        raise ValueError(f"{path}: expected one daemon ExecStart")
    expression = body[declarations[0].end():]
    literal = re.match(
        r"\s*(" + NIX_STRING + r"(?:\s*\+\s*" + NIX_STRING + r")*)\s*;",
        expression,
    )
    if literal is None:
        raise ValueError(f"{path}: unknown daemon ExecStart expression; use literal strings")
    command = "".join(m[0][1:-1] for m in re.finditer(NIX_STRING, literal[1]))
    selectors = re.findall(r"\bnpm:[^\s]+", command)
    if len(selectors) != 1:
        raise ValueError(f"{path}: missing or ambiguous Paseo daemon CLI pin")
    if (
        not re.search(r"(?:^|\s)paseo\s+daemon\s+run(?=\s|$)", command)
        or re.search(r"(?:^|\s)--foreground(?=\s|$)", command)
    ):
        raise ValueError(f"{path}: daemon command must use paseo daemon run without --foreground")
    if not selectors[0].startswith(DAEMON_TOOL + "@"):
        raise ValueError(f"{path}: daemon role requires {DAEMON_TOOL}")
    pin = selectors[0][len(DAEMON_TOOL) + 1:]
    if not FORK_VERSION.fullmatch(pin):
        raise ValueError(f"{path}: daemon pin requires stable base plus -fork.POSITIVEINTEGER")
    return pin


def check(dotfiles: Path, infra: Path) -> tuple[str, str]:
    cli_path = dotfiles / "configs/mise.toml"
    daemon_path = infra / "nixos/hosts/pluto.nix"
    cli = cli_pin(cli_path)
    daemon = daemon_pin(daemon_path)
    if cli != FORK_VERSION.fullmatch(daemon)[1]:
        raise ValueError(f"Paseo pin mismatch: {cli_path}={cli}; {daemon_path}={daemon}")
    return cli, daemon


class PinTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory(prefix="paseo-pins-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.cli = self.root / "configs/mise.toml"
        self.daemon = self.root / "nixos/hosts/pluto.nix"
        self.cli.parent.mkdir(parents=True)
        self.daemon.parent.mkdir(parents=True)
        self.cli.write_text('[tools]\n"npm:@getpaseo/cli" = {version="0.9.1", os=["linux"]}\n')
        self.daemon.write_text('''# ExecStart = "npm:@getpaseo/cli@wrong";
systemd.services.unrelated = { serviceConfig.ExecStart = "ignore"; };
systemd.services.paseo-daemon = {
  serviceConfig = {
    ExecStart = "/bin/mise exec npm:@camerontaylor/paseo-cli@0.9.1-fork.1 -- "
      + "paseo daemon run --home /home/test/.paseo";
  };
};
''')

    def test_matching_split_daemon_command(self) -> None:
        self.assertEqual(check(self.root, self.root), ("0.9.1", "0.9.1-fork.1"))

    def test_mismatch(self) -> None:
        self.daemon.write_text(self.daemon.read_text().replace("0.9.1-fork.1", "0.9.2-fork.1"))
        with self.assertRaisesRegex(ValueError, "mismatch"):
            check(self.root, self.root)

    def test_missing_and_unknown_pins(self) -> None:
        original_cli = self.cli.read_text()
        for value in ("beta", "latest", "0.9", "${VERSION}", "0.9.1-beta.1", "0.9.1-fork.1", ""):
            with self.subTest(value=value):
                self.cli.write_text(original_cli.replace("0.9.1", value))
                with self.assertRaisesRegex(ValueError, "unknown exact stable"):
                    check(self.root, self.root)
        self.cli.write_text("[tools]\n")
        with self.assertRaises(ValueError):
            check(self.root, self.root)
        self.cli.unlink()
        with self.assertRaises(OSError):
            check(self.root, self.root)

    def test_non_linux_declaration(self) -> None:
        self.cli.write_text(self.cli.read_text().replace('"linux"', '"macos"'))
        with self.assertRaisesRegex(ValueError, "Linux-only"):
            check(self.root, self.root)

    def test_missing_commented_dynamic_and_channel_daemon_pins(self) -> None:
        original = self.daemon.read_text()
        for text in (
            original.replace("0.9.1-fork.1", "beta"),
            original.replace("systemd.services.paseo-daemon", "systemd.services.other"),
            "\n".join("# " + line for line in original.splitlines()),
            "/* " + original + " */",
            original.replace('ExecStart = "/bin/mise', 'ExecStart = variable + "/bin/mise'),
            original.replace("paseo daemon run", "paseo ls"),
            original.replace("paseo daemon run", "paseo daemon start --foreground"),
            original.replace("paseo daemon run", "paseo daemon start"),
            original.replace("paseo daemon run", "paseo daemon run --foreground"),
            original.replace("paseo daemon run", "paseo daemon runtime"),
            original + original,
        ):
            with self.subTest(text=text):
                self.daemon.write_text(text)
                with self.assertRaises(ValueError):
                    check(self.root, self.root)
        self.daemon.unlink()
        with self.assertRaises(OSError):
            check(self.root, self.root)

    def test_wrong_package_roles(self) -> None:
        self.daemon.write_text(self.daemon.read_text().replace(DAEMON_TOOL, CLI_TOOL))
        with self.assertRaisesRegex(ValueError, "daemon role"):
            check(self.root, self.root)
        self.cli.write_text(self.cli.read_text().replace(CLI_TOOL, DAEMON_TOOL))
        with self.assertRaisesRegex(ValueError, "Linux-only"):
            check(self.root, self.root)

    def test_invalid_fork_suffix(self) -> None:
        original = self.daemon.read_text()
        for pin in ("0.9.1", "0.9.1-fork.0", "0.9.1-fork.-1", "0.9.1-fork.01",
                    "0.9.1-fork.x", "0.9.1-fork.1.extra", "0.9.1-beta.1-fork.1",
                    "0.9.1-fork.1+build", "${VERSION}-fork.1"):
            with self.subTest(pin=pin):
                self.daemon.write_text(original.replace("0.9.1-fork.1", pin))
                with self.assertRaisesRegex(ValueError, "POSITIVEINTEGER"):
                    check(self.root, self.root)

    def test_installer_output_is_only_validated_selector(self) -> None:
        from contextlib import redirect_stdout, redirect_stderr
        import io
        from unittest.mock import patch

        args = ["checker", "--dotfiles", str(self.root), "--infra", str(self.root),
                "--print-daemon-tool"]
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", args), redirect_stdout(output), redirect_stderr(errors):
            self.assertEqual(main(), 0)
        self.assertEqual(output.getvalue(), DAEMON_TOOL + "@0.9.1-fork.1\n")
        self.assertEqual(errors.getvalue(), "")
        self.daemon.write_text(self.daemon.read_text().replace("0.9.1-fork.1", "0.9.2-fork.1"))
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", args), redirect_stdout(output), redirect_stderr(errors):
            self.assertEqual(main(), 1)
        self.assertEqual(output.getvalue(), "")
        self.assertIn("mismatch", errors.getvalue())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dotfiles", type=Path, default=Path.home() / ".local/dotfiles")
    parser.add_argument("--infra", type=Path, default=Path.home() / ".local/infra")
    parser.add_argument("--self-test", action="store_true", help="run synthetic offline tests")
    parser.add_argument("--print-daemon-tool", action="store_true", help="print only the validated daemon npm selector")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PinTests))
        return 0 if result.wasSuccessful() else 1
    try:
        cli, daemon = check(args.dotfiles.expanduser(), args.infra.expanduser())
    except (OSError, ValueError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    if args.print_daemon_tool:
        print(f"{DAEMON_TOOL}@{daemon}")
    else:
        print(f"OK Paseo pins: CLI {CLI_TOOL}@{cli}; Pluto daemon {DAEMON_TOOL}@{daemon}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
