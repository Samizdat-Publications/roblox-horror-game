"""Shared helpers for the lint scripts in tools/lint. Standard library only."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def repo_files() -> list[str]:
    """Tracked files plus new files git would pick up (not ignored), as POSIX paths.

    Falls back to walking the tree when git is not available.
    """
    try:
        out = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        ).stdout.decode("utf-8", "replace")
        files = [f for f in out.split("\0") if f]
    except (OSError, subprocess.CalledProcessError):
        files = []
        for p in ROOT.rglob("*"):
            rel = p.relative_to(ROOT).as_posix()
            if p.is_file() and not rel.startswith(".git/") and rel != ".env":
                files.append(rel)
    return sorted(f for f in files if (ROOT / f).is_file())


def read_text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def report(name: str, hits: list[str]) -> None:
    """Print hits as `path:line: message` and exit 1 if any, else print OK and exit 0."""
    for h in hits:
        print(h)
    if hits:
        print(f"{name}: {len(hits)} problem(s)")
        sys.exit(1)
    print(f"{name}: ok")
    sys.exit(0)
