"""No gore words in UI text.

String literals in .luau files under src/client/ui must not contain the whole words
blood, gore, corpse or kill (any case).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, report  # noqa: E402

UI = ROOT / "src" / "client" / "ui"
WORDS = re.compile(r"\b(blood|gore|corpse|kill)\b", re.I)
# "..." and '...' (with escapes), `...` interpolated strings, and [[...]] / [=[...]=] long strings.
STRINGS = re.compile(
    r'"(?:\\.|[^"\\\n])*"' r"|'(?:\\.|[^'\\\n])*'" r"|`(?:\\.|[^`\\])*`" r"|\[(=*)\[.*?\]\1\]",
    re.S,
)


def main() -> None:
    hits: list[str] = []
    files = sorted(UI.rglob("*.luau")) if UI.exists() else []
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        src = path.read_text(encoding="utf-8", errors="replace")
        for m in STRINGS.finditer(src):
            # A long string right after "--" is a comment, not UI text.
            if src[max(0, m.start() - 2) : m.start()] == "--":
                continue
            for w in WORDS.finditer(m.group(0)):
                line = src.count("\n", 0, m.start() + w.start()) + 1
                hits.append(f"{rel}:{line}: banned word '{w.group(0)}' in a UI string")
    report("ui words", hits)


if __name__ == "__main__":
    main()
