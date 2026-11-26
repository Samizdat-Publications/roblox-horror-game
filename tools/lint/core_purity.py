"""Core stays pure (docs/ARCHITECTURE.md, Core rules).

Every .luau file under src/shared/Core must start with --!strict and, outside comments,
must not use game, workspace, task, os.clock, tick(, math.random, Random.new,
Instance.new or wait(.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, report  # noqa: E402

CORE = ROOT / "src" / "shared" / "Core"
BANNED = [
    (re.compile(r"\bgame\s*[:.]"), "game"),
    (re.compile(r"\bworkspace\b"), "workspace"),
    (re.compile(r"\btask\s*\."), "task."),
    (re.compile(r"\bos\s*\.\s*clock\b"), "os.clock"),
    (re.compile(r"\btick\s*\("), "tick("),
    (re.compile(r"\bmath\s*\.\s*random\b"), "math.random"),
    (re.compile(r"\bRandom\s*\.\s*new\b"), "Random.new"),
    (re.compile(r"\bInstance\s*\.\s*new\b"), "Instance.new"),
    (re.compile(r"\bwait\s*\("), "wait("),
]
BLOCK_COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]", re.S)


def strip_comments(src: str) -> str:
    # Blank out block comments but keep their newlines so line numbers stay right.
    src = BLOCK_COMMENT.sub(lambda m: "\n" * m.group(0).count("\n"), src)
    return "\n".join(line.split("--", 1)[0] for line in src.split("\n"))


def main() -> None:
    hits: list[str] = []
    files = sorted(CORE.rglob("*.luau")) if CORE.exists() else []
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        src = path.read_text(encoding="utf-8-sig", errors="replace")
        first = src.split("\n", 1)[0].strip()
        if first != "--!strict":
            hits.append(f"{rel}:1: must start with --!strict")
        for n, line in enumerate(strip_comments(src).split("\n"), 1):
            for pattern, label in BANNED:
                if pattern.search(line):
                    hits.append(f"{rel}:{n}: {label} is not allowed in Core")
    report("core purity", hits)


if __name__ == "__main__":
    main()
