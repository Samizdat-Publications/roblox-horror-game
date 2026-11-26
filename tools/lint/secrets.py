"""No API keys in the repo.

- No line matching (ELEVENLABS_API_KEY|GEMINI_API_KEY|MESHY_API_KEY)\\s*=\\s*\\S+ in any
  file git would see, except .env itself. A key name inside a string literal that is
  immediately closed ("GEMINI_API_KEY=" in a .env parser) is not an assignment and is allowed.
- .env must not be tracked or staged.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, read_text, repo_files, report  # noqa: E402

PATTERN = re.compile(r"(ELEVENLABS_API_KEY|GEMINI_API_KEY|MESHY_API_KEY)\s*=\s*(\S+)")
BINARY = {".png", ".jpg", ".jpeg", ".ogg", ".mp3", ".wav", ".rbxl", ".rbxm", ".fbx", ".blend", ".zip", ".exe"}


def is_parser_literal(line: str, m: re.Match[str]) -> bool:
    before = line[: m.start()]
    value = m.group(2)
    return bool(before) and before[-1] in "\"'" and value[0] == before[-1]


def main() -> None:
    hits: list[str] = []
    for rel in repo_files():
        if rel == ".env" or Path(rel).suffix.lower() in BINARY:
            continue
        for n, line in enumerate(read_text(rel).splitlines(), 1):
            for m in PATTERN.finditer(line):
                if not is_parser_literal(line, m):
                    hits.append(f"{rel}:{n}: {m.group(1)} is assigned a value")
    try:
        tracked = subprocess.run(
            ["git", "ls-files", "--cached", "--", ".env"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.split()
        if ".env" in tracked:
            hits.append(".env:1: .env is tracked or staged (git rm --cached .env)")
    except (OSError, subprocess.CalledProcessError):
        pass
    report("secrets", hits)


if __name__ == "__main__":
    main()
