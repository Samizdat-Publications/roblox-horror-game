"""Build build/manifest.json from src/ so a Luau snippet in Studio can pull every script.

Mapping (Rojo-like):
  src/<Service>/<Folder...>/Name.server.luau -> Script
  src/<Service>/<Folder...>/Name.client.luau -> LocalScript
  src/<Service>/<Folder...>/Name.luau        -> ModuleScript
StarterPlayer/StarterPlayerScripts is a nested service path.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src")
OUT_DIR = os.path.join(ROOT, "build")


def classify(name):
    if name.endswith(".server.luau"):
        return name[: -len(".server.luau")], "Script"
    if name.endswith(".client.luau"):
        return name[: -len(".client.luau")], "LocalScript"
    if name.endswith(".luau"):
        return name[: -len(".luau")], "ModuleScript"
    return None, None


def main():
    entries = []
    for dirpath, _dirs, files in os.walk(SRC):
        for f in sorted(files):
            inst_name, cls = classify(f)
            if not cls:
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), SRC).replace("\\", "/")
            parts = rel.split("/")[:-1] + [inst_name]
            with open(os.path.join(dirpath, f), "r", encoding="utf-8") as fh:
                source = fh.read()
            entries.append({"path": parts, "className": cls, "source": source})
    entries.sort(key=lambda e: "/".join(e["path"]))
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump({"entries": entries}, fh)
    print(f"manifest: {len(entries)} scripts")
    for e in entries:
        print("  " + ".".join(e["path"]) + "  (" + e["className"] + ")")


if __name__ == "__main__":
    sys.exit(main())
