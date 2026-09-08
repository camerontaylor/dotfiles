#!/usr/bin/env python3
"""ownership-gate — mechanical single-owner enforcement (fleet-consolidation M2).

docs/fleet-consolidation.md invariant: "One declared owner per artifact;
duplicates are CI failures, not runtime arbitration." This gate makes that
literal. Two failure classes:

  A. DUPLICATE INSTALL OWNERSHIP — the same tool reachable through two or
     more install mechanisms (mise / brew / npm-global / cargo / bun /
     curl-of-binary / pacman / apt / AUR) without an explicit declared
     exception in ownership-declared.toml.
  B. UNDECLARED SERVICE ARTIFACT — a unit/plist/compose file shipped
     (tracked) or written (generated) by this repo that is neither attested
     in an infra host manifest nor recorded as a declared exception.

Local/CI split (by design): GitHub CI checks out ONLY this repo, so the
infra manifests (~/.local/infra/manifests/*.toml) are absent there. When
INFRA_DIR (default ~/.local/infra) exists, the gate runs in FULL mode —
attested manifest ids are verified against the real manifests. When it does
not, check B's manifest verification degrades to SKIP-WITH-NOTICE while
everything else (mechanism extraction, declaration consistency, undeclared
artifacts) still fails hard. Run the full mode from a fleet box or the infra
repo side; CI is the floor, not the ceiling.

Declared exceptions live in ownership-declared.toml next to this script.
Stale declarations FAIL — an entry whose artifact is no longer multi-mechanism
(or whose artifact vanished) means the registry rots silently otherwise. That
is deliberate: M3/M4 removals must delete their declarations in the same
commit, and the gate enforces it.

Extraction is line-oriented and heuristic, tuned to this repo's idioms
(helper functions, `recipes+=( "tool|cmd" )` strings, for-loop fallbacks,
heredoc-written units, `x_label=…` composed plist names). A missed site is a
coverage gap; a false site invents a phantom duplicate — both surface as a
checker failure someone then reconciles, which is the point.

Usage: ownership-gate.py [--root REPO] [--infra-dir DIR] [--list]
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path

# ── canonical names ────────────────────────────────────────────────────────
# The same tool wears different names per mechanism (brew formula git-delta
# vs mise tool delta vs binary delta). Dual-install detection needs one
# canonical identity per tool; this table merges the aliases used in this
# repo. Backend-prefixed mise keys ("npm:@getpaseo/cli") canonicalize to the
# package name first (last one path segment for plain names, last two for
# @scoped ones).
ALIASES = {
    "rg": "ripgrep",
    "git-delta": "delta",
    "sg": "ast-grep",
    "@ast-grep/cli": "ast-grep",
    "@ast-grep/napi": "ast-grep",
    "aws": "awscli",
    "nvim": "neovim",
    "@getpaseo/cli": "paseo",
    "pn": "pnpm",
    "linear": "linear-cli",
    "testssl": "testssl.sh",
    "rustup": "rust",  # mise's rust = "1" resolves THROUGH rustup — one system
    "satococoa/tap/wtp": "wtp",  # brew tap name vs release-asset name
}
# Tokens that look like package names to a regex but are shell punctuation or
# prose leaked out of an echo/comment. Closed set — extend only with evidence.
STOPWORDS = {"then", "else", "fi", "done", "do", "esac", "true", "exit", "install"}

# ── install-mechanism extraction ───────────────────────────────────────────
BREW_CALL = re.compile(
    r"\b(?:brew_install_or_upgrade|brew_formula_install_or_upgrade|"
    r"brew_cask_install_or_upgrade|brew\s+install|brew\s+tap\s+install)\s+"
    r"([\w@/.-]+)"
)
PACMAN_INSTALL = re.compile(
    r"\bpacman\s+(?:-\S+\s+)*--needed\s+(?:--noconfirm\s+)?([\w.\-]+)"
)
APT_INSTALL = re.compile(r"\bapt(?:-get)?\s+install\s+(?:-y\s+)?([\w.\-]+)")
AUR_INSTALL = re.compile(
    r"(?:\bparu|\byay|\$aur)\s+-S\s+(?:--needed\s+)?(?:--noconfirm\s+)?([\w.\-]+)"
)
CARGO_INSTALL = re.compile(
    r"\bcargo\s+install\s+(?:--git\s+\S+\s+)?(?:--branch\s+\S+\s+)?"
    r"(?:(?:--locked|--force)\s+)*([A-Za-z0-9][\w\-]*)"
)
BUN_GLOBAL = re.compile(r"\bbun\s+install\s+-g\s+([\w@/\-]+?)(?:@[\w.\-]+)?\s")
COREPACK = re.compile(r"\bcorepack\s+(?:--\S+\s+)*(?:enable|install)\s+([\w@/\-]+)")
CURL_INSTALL = re.compile(r"\bcurl\b[^\n]*https?://(\S+?)(?:[\"'\s]|$)")
# Only install-script / release-asset fetches count as a curl install
# mechanism, not every curl in the tree.
CURL_URL_TOOL = [
    (re.compile(r"claude\.ai/install\.sh"), "claude-code"),
    (re.compile(r"sh\.rustup\.rs"), "rustup"),
    (re.compile(r"github\.com/jdx/mise/releases"), "mise"),
    (re.compile(r"github\.com/satococoa/wtp/releases"), "wtp"),
    (re.compile(r"github\.com/walles/moor/releases"), "moor"),
    (re.compile(r"tailscale\.com/install\.sh"), "tailscale"),
    (re.compile(r"caddyserver\.com/api/download"), "caddy"),
]
# Variable-driven brew fallback: `for VAR in a b c; do` whose body (next ~12
# lines) calls brew_install_or_upgrade with $VAR (50_mise.zsh, 75_brew_setup).
FOR_LOOP = re.compile(r"^\s*for\s+(\w+)\s+in\s+([\w.\- ]+);")

# ── service-artifact extraction ────────────────────────────────────────────
# .target units are excluded from write-site extraction: WantedBy=/After=
# lines inside unit content (heredoc bodies or multi-line quoted strings)
# name systemd's own targets, never an artifact this repo ships. A tracked
# *.target file would still be caught by the tracked-file scan.
UNIT_NAME = re.compile(r"(?<![$.])\b([A-Za-z0-9@_.\-]+\.(?:service|timer|socket|slice))\b")
PLIST_NAME = re.compile(r"(?<![$}])\b([A-Za-z0-9_.\-]+\.plist)\b")
COMPOSE_NAME = re.compile(r"\b(docker-compose[\w.\-]*\.ya?ml)\b")
DROPIN_NAME = re.compile(r"\b([A-Za-z0-9@_.\-]+\.service\.d/[A-Za-z0-9_.\-]+\.conf)\b")
WRITE_VERB = re.compile(r"\b(?:tee|install|cp|mv|ln|render|write)\b|>\s*\S")
ASSIGNMENT = re.compile(r"^\s*\w+=.*\S")
HEREDOC_OPEN = re.compile(r"<<-?\s*[\"']?([A-Za-z_]+)[\"']?")
NOISE_REDIRECT = re.compile(r"\d?>\s*/dev/null|2>&1")
ECHO_LINE = re.compile(r"\b(?:printf|echo)\b")
QUOTED_SPAN = re.compile(r'''("[^"]*"|'[^']*')''')
LABEL_ASSIGN = re.compile(r"^\s*(\w*label\w*)\s*=\s*([\w.\-]+)\s*$")
# Plist paths under these prefixes are app-owned preference state this repo
# reads/edits via defaults(1), not service artifacts it ships.
PLIST_PATH_EXCLUDE = ("/Library/Preferences/", "/Applications/")

SERVICE_EXTS = (".service", ".timer", ".socket", ".slice", ".target", ".plist")
SCAN_ROOTS = ("scripts", "bin")
SCAN_SKIP = ("scripts/tests",)


def canonical(name: str) -> str:
    name = name.strip().strip('"').strip("'")
    # npm version suffix: an "@" AFTER the last "/" (pkg@ver, @scope/pkg@ver —
    # but not the backend-prefix "@", which always precedes its "/").
    slash = name.rfind("/")
    if "@" in name[slash + 1 :]:
        name = name[: slash + 1] + name[slash + 1 :].split("@", 1)[0]
    if ":" in name:  # mise backend prefix: npm:@getpaseo/cli -> @getpaseo/cli
        backend_pkg = name.split(":", 1)[1]
        name = (
            "/".join(backend_pkg.rsplit("/", 2)[-2:])
            if backend_pkg.startswith("@")
            else backend_pkg.rsplit("/", 1)[-1]
        )
    return ALIASES.get(name, name)


def clean_mechanism_line(line: str) -> str:
    """Blank prose strings and trailing noise so regexes see real commands."""
    if ECHO_LINE.search(line):
        line = QUOTED_SPAN.sub('""', line)
    return line


def is_real_token(tok: str) -> bool:
    return bool(re.match(r"^[A-Za-z0-9@]", tok)) and tok not in STOPWORDS


class Gate:
    def __init__(self, root: Path, infra_dir: Path | None):
        self.root = root
        self.infra_dir = infra_dir
        self.failures: list[str] = []
        self.notices: list[str] = []

    def fail(self, msg: str) -> None:
        self.failures.append(msg)

    def note(self, msg: str) -> None:
        self.notices.append(msg)

    # ── file plumbing ──────────────────────────────────────────────────────
    def _shell_files(self) -> list[str]:
        out = []
        for root_dir in SCAN_ROOTS:
            base = self.root / root_dir
            if not base.is_dir():
                continue
            for path in sorted(base.rglob("*")):
                if not path.is_file():
                    continue
                rel = path.relative_to(self.root).as_posix()
                if any(rel.startswith(skip) for skip in SCAN_SKIP):
                    continue
                if path.suffix in (".zsh", ".sh", ".bash") or rel in (
                    "scripts/pre-commit",
                    "scripts/post-merge",
                ):
                    out.append(rel)
        for extra in ("deploy.zsh", "deploy.bash"):
            if (self.root / extra).is_file():
                out.append(extra)
        return out

    @staticmethod
    def _iter_code_lines(text: str):
        """Yield (lineno, line, in_heredoc) skipping comments and heredoc
        bodies. Heredoc bodies are unit CONTENT (WantedBy=multi-user.target
        etc.), not shell writing an artifact — the tee/install line that opens
        them already named the artifact."""
        heredoc_delim = None
        for i, raw in enumerate(text.splitlines(), 1):
            if heredoc_delim is not None:
                if raw.strip() == heredoc_delim:
                    heredoc_delim = None
                continue
            if raw.lstrip().startswith("#"):
                continue
            m = HEREDOC_OPEN.search(raw)
            if m and m.group(1) not in ("EOF",):  # EOF handled below
                heredoc_delim = m.group(1)
                yield i, raw, False
                continue
            if m:  # <<EOF — delimiter is EOF itself
                heredoc_delim = "EOF"
            yield i, raw, False

    # ── mechanism map ──────────────────────────────────────────────────────
    def scan_mechanisms(self) -> dict[str, dict[str, set[str]]]:
        """{canonical: {mechanism: {file:line provenance}}}"""
        mechs: dict[str, dict[str, set[str]]] = {}

        def add(tool: str, mechanism: str, where: str) -> None:
            tool = canonical(tool)
            if tool and is_real_token(tool):
                mechs.setdefault(tool, {}).setdefault(mechanism, set()).add(where)

        mise = self.root / "configs" / "mise.toml"
        if mise.is_file():
            with mise.open("rb") as fh:
                cfg = tomllib.load(fh)
            for tool in cfg.get("tools", {}):
                add(tool, "mise", "configs/mise.toml")

        npm_file = self.root / ".default-npm-packages"
        if npm_file.is_file():
            for line in npm_file.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    add(line, "npm-global", ".default-npm-packages")

        for rel in self._shell_files():
            lines = (self.root / rel).read_text(errors="replace").splitlines()
            for i, raw in enumerate(lines, 1):
                if raw.lstrip().startswith("#"):
                    continue
                where = f"{rel}:{i}"
                line = clean_mechanism_line(raw)
                for m in BREW_CALL.finditer(line):
                    pkg = re.sub(r"\s*\|\|\s*true\s*$", "", m.group(1)).strip()
                    mech = "brew-cask" if "cask" in line else "brew"
                    add(pkg, mech, where)
                for m in PACMAN_INSTALL.finditer(line):
                    add(m.group(1), "pacman", where)
                for m in APT_INSTALL.finditer(line):
                    add(m.group(1), "apt", where)
                for m in AUR_INSTALL.finditer(line):
                    add(m.group(1), "aur", where)
                for m in CARGO_INSTALL.finditer(line):
                    add(m.group(1), "cargo", where)
                for m in BUN_GLOBAL.finditer(line):
                    add(m.group(1), "bun-global", where)
                for m in COREPACK.finditer(line):
                    add(m.group(1), "corepack", where)
                for m in CURL_INSTALL.finditer(line):
                    url = m.group(1)
                    if any(p.search(url) for p, _ in CURL_URL_TOOL):
                        tool = next(t for p, t in CURL_URL_TOOL if p.search(url))
                        add(tool, "curl", where)
            # variable-driven brew fallback loops
            for i, raw in enumerate(lines):
                m = FOR_LOOP.match(raw)
                if not m:
                    continue
                var, words = m.group(1), m.group(2).split()
                window = lines[i + 1 : i + 13]
                if any("brew_install" in w for w in window) and any(
                    f"${var}" in w or f"${{{var}}}" in w for w in window
                ):
                    for word in words:
                        add(word, "brew", f"{rel}:{i + 1}")
        return mechs

    # ── service artifact map ───────────────────────────────────────────────
    def scan_service_artifacts(self) -> dict[str, set[str]]:
        """{artifact (repo-relative path for tracked files, else the
        unit/plist/compose basename): {provenance}}"""
        arts: dict[str, set[str]] = {}

        def add(name: str, where: str) -> None:
            arts.setdefault(name, set()).add(where)

        tracked = subprocess.run(
            ["git", "-C", str(self.root), "ls-files"],
            capture_output=True, text=True, check=True,
        ).stdout.splitlines()
        for rel in tracked:
            base = rel.rsplit("/", 1)[-1]
            if base.endswith(SERVICE_EXTS) or COMPOSE_NAME.search(base):
                add(rel, "tracked")

        for rel in self._shell_files():
            text = (self.root / rel).read_text(errors="replace")
            lines = text.splitlines()
            for i, raw, _ in self._iter_code_lines(text):
                where = f"{rel}:{i}"
                context = (
                    WRITE_VERB.search(NOISE_REDIRECT.sub("", raw)) is not None
                    or ASSIGNMENT.match(raw) is not None
                    or raw.lstrip().startswith("for ")
                )
                for m in DROPIN_NAME.finditer(raw):
                    parent = m.group(1).split(".service.d/")[0] + ".service"
                    if context:
                        add(parent, where)
                for m in UNIT_NAME.finditer(raw):
                    if context:
                        add(m.group(1), where)
                for m in PLIST_NAME.finditer(raw):
                    if context and not any(p in raw for p in PLIST_PATH_EXCLUDE):
                        add(m.group(1), where)
                for m in COMPOSE_NAME.finditer(raw):
                    if context:
                        add(m.group(1), where)
            # x_label=<label> composed into a `$x_label.plist` path elsewhere
            # in the same file — the real plist name never appears literally
            # (99_periodic / 56_tmpdir_prune / 77_maxfiles_limit).
            for i, raw in enumerate(lines, 1):
                m = LABEL_ASSIGN.match(raw)
                if m and f"${m.group(1)}.plist" in text or m and f"${{{m.group(1)}}}.plist" in text:
                    add(f"{m.group(2)}.plist", f"{rel}:{i}")

        # Merge bare basenames into their tracked-path key when both exist
        # (e.g. `caddy.service` write sites vs tracked configs/caddy/caddy.service).
        for bare in [a for a in arts if "/" not in a]:
            for tracked_key in [a for a in arts if "/" in a]:
                if tracked_key.rsplit("/", 1)[-1] == bare:
                    arts[tracked_key] |= arts.pop(bare)
                    break
        return arts

    # ── declarations ───────────────────────────────────────────────────────
    def load_declarations(self) -> dict:
        decl_path = self.root / "scripts" / "tests" / "ownership-declared.toml"
        with decl_path.open("rb") as fh:
            return tomllib.load(fh)

    # ── checks ─────────────────────────────────────────────────────────────
    def check_duplicates(self, mechs: dict, decl: dict) -> None:
        declared = decl.get("dual_install", {})
        for tool in sorted(mechs):
            mechanisms = mechs[tool]
            entry = declared.get(tool)
            if len(mechanisms) < 2:
                continue
            if entry is None:
                self.fail(
                    f"duplicate ownership: '{tool}' installed by "
                    f"{sorted(mechanisms)} "
                    f"({'; '.join(sorted(set().union(*mechanisms.values())))}) "
                    f"with no [dual_install.{tool}] declaration"
                )
                continue
            declared_mechs = set(entry.get("mechanisms", []))
            observed = set(mechanisms)
            if not declared_mechs <= observed:
                self.fail(
                    f"stale declaration: [dual_install.{tool}] claims "
                    f"mechanisms {sorted(declared_mechs)} but only "
                    f"{sorted(observed)} are present"
                )
            if "reason" not in entry:
                self.fail(f"[dual_install.{tool}] missing required 'reason'")
        for tool in sorted(declared):
            if tool not in mechs:
                self.fail(f"stale declaration: [dual_install.{tool}] matches no install surface")
            elif len(mechs[tool]) < 2:
                self.fail(
                    f"stale declaration: [dual_install.{tool}] declared dual but now "
                    f"single-mechanism ({sorted(mechs[tool])}) — remove the entry"
                )

    def check_service_artifacts(self, arts: dict, decl: dict) -> None:
        declared = decl.get("service_artifact", {})
        for art in sorted(arts):
            base = art.rsplit("/", 1)[-1]
            entry = declared.get(art) or declared.get(base)
            if entry is None:
                self.fail(
                    f"undeclared service artifact: '{art}' "
                    f"(shipped/written by {sorted(arts[art])}) — attest it in "
                    f"[service_artifact] with manifest_ids, or record an exception reason"
                )
                continue
            if not entry.get("manifest_ids") and not entry.get("reason"):
                self.fail(
                    f"[service_artifact.{art}] needs manifest_ids (verified in "
                    f"full mode) and/or a reason"
                )
            writers = entry.get("writers", [])
            if writers:
                files = {w.split(":")[0] for w in arts[art] if w != "tracked"}
                unknown = files - set(writers)
                if unknown:
                    self.fail(
                        f"[service_artifact.{art}] writers {sorted(writers)} do not "
                        f"cover actual write sites {sorted(files)}"
                    )
        for key in sorted(declared):
            base = key.rsplit("/", 1)[-1]
            if key not in arts and base not in arts:
                self.fail(f"stale declaration: [service_artifact.{key}] matches no shipped/written artifact")

    def check_manifest_attestations(self, decl: dict) -> None:
        if self.infra_dir is None:
            self.note(
                "infra repo not present (CI mode) — manifest attestation skipped; "
                "run from a fleet box or the infra repo for the cross-repo check"
            )
            return
        manifest_ids: set[str] = set()
        for mf in sorted((self.infra_dir / "manifests").glob("*.toml")):
            with mf.open("rb") as fh:
                data = tomllib.load(fh)
            for art in data.get("artifact", []):
                manifest_ids.add(art["id"])
        for key, entry in decl.get("service_artifact", {}).items():
            for mid in entry.get("manifest_ids", []):
                if mid not in manifest_ids:
                    self.fail(
                        f"[service_artifact.{key}] attests '{mid}' but no infra "
                        f"manifest carries that artifact id"
                    )


def main() -> int:
    args = sys.argv[1:]
    list_mode = "--list" in args
    root = (
        Path(args[args.index("--root") + 1]).resolve()
        if "--root" in args
        else Path(__file__).resolve().parents[2]
    )
    infra_env = os.environ.get("INFRA_DIR")
    if "--infra-dir" in args:
        infra_dir = Path(args[args.index("--infra-dir") + 1])
    elif infra_env:
        infra_dir = Path(infra_env)
    else:
        infra_dir = Path.home() / ".local" / "infra"
    infra_dir = infra_dir if (infra_dir / "manifests").is_dir() else None

    gate = Gate(root, infra_dir)
    mechs = gate.scan_mechanisms()
    arts = gate.scan_service_artifacts()

    if list_mode:
        print("== install mechanisms ==")
        for tool in sorted(mechs):
            for m, where in sorted(mechs[tool].items()):
                print(f"{tool:28} {m:12} {', '.join(sorted(where))}")
        print("\n== service artifacts ==")
        for art in sorted(arts):
            print(f"{art:60} {sorted(arts[art])}")
        return 0

    decl = gate.load_declarations()
    gate.check_duplicates(mechs, decl)
    gate.check_service_artifacts(arts, decl)
    gate.check_manifest_attestations(decl)

    for n in gate.notices:
        print(f"notice: {n}")
    if gate.failures:
        for f in gate.failures:
            print(f"FAIL: {f}", file=sys.stderr)
        print(
            "ownership gate: FAILED — every failure is either a real duplicate "
            "or a missing/stale declaration in scripts/tests/ownership-declared.toml",
            file=sys.stderr,
        )
        return 1
    print(
        "ownership gate: PASS "
        f"({len(mechs)} tools mapped, {len(arts)} service artifacts declared, "
        f"mode={'full' if infra_dir else 'ci'})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
