"""Make Roblox-ready copies of the models: art/models/<Name>.glb -> art/models/roblox/<Name>.glb.

Blender writes vertex colours (COLOR_0) in linear light, as glTF asks. Roblox's importer shows
them as if they were already display (sRGB) colours, so every model came in far too dark
(found on the first import, 2026-11-26). This converts each COLOR_0 value linear -> sRGB and
changes nothing else, so the Blender scripts and previews stay correct.

    python art/scripts/roblox_colors.py            (every model)
    python art/scripts/roblox_colors.py Dock Bluegill
"""
import json
import struct
import sys
from pathlib import Path

MODELS = Path(__file__).resolve().parents[1] / "models"
OUT = MODELS / "roblox"
FLOAT = 5126
SIZES = {"VEC3": 3, "VEC4": 4}


def to_srgb(c: float) -> float:
    c = min(max(c, 0.0), 1.0)
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def convert(src: Path, dst: Path) -> int:
    data = bytearray(src.read_bytes())
    magic, _version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise SystemExit(f"{src.name} is not a GLB file")
    json_len, json_type = struct.unpack_from("<I4s", data, 12)
    assert json_type == b"JSON"
    gltf = json.loads(data[20 : 20 + json_len])
    bin_start = 20 + json_len + 8  # the BIN chunk header follows the JSON chunk
    done = set()
    changed = 0
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            index = prim["attributes"].get("COLOR_0")
            if index is None or index in done:
                continue
            done.add(index)
            acc = gltf["accessors"][index]
            if acc["componentType"] != FLOAT or acc["type"] not in SIZES:
                raise SystemExit(f"{src.name}: COLOR_0 is not float VEC3/VEC4, convert by hand")
            view = gltf["bufferViews"][acc["bufferView"]]
            n = SIZES[acc["type"]]
            stride = view.get("byteStride", 4 * n)
            base = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            for i in range(acc["count"]):
                at = base + i * stride
                rgb = struct.unpack_from("<3f", data, at)
                struct.pack_into("<3f", data, at, *(to_srgb(c) for c in rgb))  # alpha stays
                changed += 1
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(bytes(data))
    return changed


def main():
    names = sys.argv[1:] or [p.stem for p in sorted(MODELS.glob("*.glb"))]
    for name in names:
        n = convert(MODELS / f"{name}.glb", OUT / f"{name}.glb")
        print(f"{name}: {n} vertex colours converted -> art/models/roblox/{name}.glb")


if __name__ == "__main__":
    main()
