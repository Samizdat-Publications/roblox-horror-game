"""Compare script checksums from Studio against src/.

In Studio (execute_luau, Edit) run tools/sync/checksums.luau and paste its output into
build/studio_sums.json, then run: python tools/sync/verify.py
Checksum = length and a 32-bit rolling sum, computed the same way on both sides.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_manifest import ROOT, SRC, classify  # noqa: E402


def checksum(text: str) -> str:
    data = text.replace("\r\n", "\n").encode("utf-8")
    h = 0
    for b in data:
        h = (h * 31 + b) % 4294967296
    return f"{len(data)}:{h}"


def local_sums():
    out = {}
    for dirpath, _d, files in os.walk(SRC):
        for f in files:
            name, cls = classify(f)
            if not cls:
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), SRC).replace("\\", "/")
            key = ".".join(rel.split("/")[:-1] + [name])
            with open(os.path.join(dirpath, f), encoding="utf-8") as fh:
                out[key] = checksum(fh.read())
    return out


def main():
    studio = json.load(open(os.path.join(ROOT, "build", "studio_sums.json"), encoding="utf-8"))
    local = local_sums()
    bad = 0
    for k, v in sorted(local.items()):
        s = studio.get(k)
        if s != v:
            bad += 1
            print(f"MISMATCH {k}: src {v} studio {s}")
    for k in sorted(set(studio) - set(local)):
        print(f"EXTRA IN STUDIO {k}")
        bad += 1
    print("all match" if bad == 0 else f"{bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
