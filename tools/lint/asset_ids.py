"""No invented asset ids.

- Every `rbxassetid://<digits>` and every nonzero `id = <digits>` in
  src/shared/SoundRegistry.luau or src/shared/AssetRegistry.luau must appear in
  audio/ids.json or art/ids.json.
- `rbxassetid://` literals anywhere else under src are an error: ids live in the registries.
- SoundRegistry derived sounds: an entry may carry a `derive` table only with id 0, and every
  `from = "<name>"` inside it (the source and each layer's) must name an entry with a real
  (nonzero) id. Effect classes must be ones SoundRegistry.EFFECT_PROPS allows.

ids.json shape: { "assets": [ { "name", "id", "source", "operation" } ] }.
Both files are created as { "assets": [] } if missing.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, read_text, repo_files, report  # noqa: E402

REGISTRIES = ("src/shared/SoundRegistry.luau", "src/shared/AssetRegistry.luau")
ID_FILES = ("audio/ids.json", "art/ids.json")
ASSET_URI = re.compile(r"rbxassetid://(\d+)")
ID_FIELD = re.compile(r"\bid\s*=\s*(\d+)")


def known_ids(hits: list[str]) -> set[str]:
    ids: set[str] = set()
    for rel in ID_FILES:
        path = ROOT / rel
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{ "assets": [] }\n', encoding="utf-8")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            assets = data["assets"]
            assert isinstance(assets, list)
        except (ValueError, KeyError, TypeError, AssertionError) as e:
            hits.append(f"{rel}:1: not valid ids.json ({e})")
            continue
        for i, rec in enumerate(assets):
            if not isinstance(rec, dict) or "id" not in rec:
                hits.append(f"{rel}:1: asset record {i} has no id")
                continue
            for field in ("name", "source", "operation"):
                if field not in rec:
                    hits.append(f"{rel}:1: asset {rec.get('id')} is missing '{field}'")
            ids.add(str(rec["id"]).strip())
    return ids


def strip_comment(line: str) -> str:
    i = line.find("--")
    return line if i < 0 else line[:i]


SOUND_REGISTRY = "src/shared/SoundRegistry.luau"
ENTRY_START = re.compile(r'^\t\["([^"]+)"\]\s*=\s*\{')
FROM_FIELD = re.compile(r'\bfrom\s*=\s*"([^"]*)"')
CLASS_FIELD = re.compile(r'\bclass\s*=\s*"([^"]*)"')
EFFECT_CLASSES = {
    "EqualizerSoundEffect",
    "ReverbSoundEffect",
    "EchoSoundEffect",
    "DistortionSoundEffect",
    "PitchShiftSoundEffect",
    "ChorusSoundEffect",
    "TremoloSoundEffect",
}


def registry_entries(text: str) -> list[tuple[str, int, str]]:
    """(name, line, entry text without comments) for every top-level `["name"] = { ... }`."""
    lines = text.splitlines()
    out: list[tuple[str, int, str]] = []
    i = 0
    while i < len(lines):
        m = ENTRY_START.match(lines[i])
        if not m:
            i += 1
            continue
        start = i
        body = strip_comment(lines[i])[m.end() - 1 :]
        depth = body.count("{") - body.count("}")
        while depth > 0 and i + 1 < len(lines):
            i += 1
            code = strip_comment(lines[i])
            body += "\n" + code
            depth += code.count("{") - code.count("}")
        out.append((m.group(1), start + 1, body))
        i += 1
    return out


def check_derived(hits: list[str]) -> None:
    entries = registry_entries(read_text(SOUND_REGISTRY))
    real: dict[str, bool] = {}
    for name, _, body in entries:
        m = ID_FIELD.search(body)
        real[name] = m is not None and int(m.group(1)) != 0
    for name, line, body in entries:
        has_derive = re.search(r"\bderive\s*=\s*\{", body) is not None
        sources = FROM_FIELD.findall(body)
        if has_derive and real[name]:
            hits.append(f"{SOUND_REGISTRY}:{line}: '{name}' has a real id and a derive table (remove the derive)")
        if sources and not has_derive:
            hits.append(f"{SOUND_REGISTRY}:{line}: '{name}' has `from` outside a derive table")
        if has_derive and not sources:
            hits.append(f"{SOUND_REGISTRY}:{line}: '{name}' has a derive table with no `from`")
        for src in sources:
            if src not in real:
                hits.append(f"{SOUND_REGISTRY}:{line}: '{name}' derives from '{src}', which is not in the registry")
            elif not real[src]:
                hits.append(f"{SOUND_REGISTRY}:{line}: '{name}' derives from '{src}', which has no real id")
        for cls in CLASS_FIELD.findall(body):
            if cls not in EFFECT_CLASSES:
                hits.append(f"{SOUND_REGISTRY}:{line}: '{name}' uses effect class '{cls}', not an allowed SoundEffect")


def main() -> None:
    hits: list[str] = []
    ids = known_ids(hits)
    check_derived(hits)
    for rel in repo_files():
        if not rel.startswith("src/") or not rel.endswith((".luau", ".lua")):
            continue
        is_registry = rel in REGISTRIES
        for n, line in enumerate(read_text(rel).splitlines(), 1):
            code = strip_comment(line)
            if not is_registry:
                if ASSET_URI.search(code):
                    hits.append(f"{rel}:{n}: rbxassetid:// literal outside the registries")
                continue
            found = [m.group(1) for m in ASSET_URI.finditer(code)]
            found += [m.group(1) for m in ID_FIELD.finditer(code) if int(m.group(1)) != 0]
            for asset_id in found:
                if asset_id not in ids:
                    hits.append(f"{rel}:{n}: asset id {asset_id} is not in audio/ids.json or art/ids.json")
    report("asset ids", hits)


if __name__ == "__main__":
    main()
