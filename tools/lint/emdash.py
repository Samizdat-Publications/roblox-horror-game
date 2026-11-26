"""No em dash (U+2014) in any tracked text file.

Skips the fishing-game copies (tools/critic, tools/audio, tools/blender, tools/studio/sync)
and any file with FISHING or fishing-reference in its name.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import read_text, repo_files, report  # noqa: E402

EMDASH = chr(0x2014)  # written as a code point so this file passes its own lint
EXTENSIONS = {".md", ".luau", ".lua", ".json", ".ps1", ".py", ".yml", ".yaml", ".toml", ".txt", ".html"}
SKIP_DIRS = ("tools/critic/", "tools/audio/", "tools/blender/", "tools/studio/sync/")


def skipped(rel: str) -> bool:
    name = rel.rsplit("/", 1)[-1]
    return rel.startswith(SKIP_DIRS) or "FISHING" in name or "fishing-reference" in name


def main() -> None:
    hits = []
    for rel in repo_files():
        if Path(rel).suffix.lower() not in EXTENSIONS or skipped(rel):
            continue
        for n, line in enumerate(read_text(rel).splitlines(), 1):
            if EMDASH in line:
                hits.append(f"{rel}:{n}: em dash")
    report("emdash", hits)


if __name__ == "__main__":
    main()
