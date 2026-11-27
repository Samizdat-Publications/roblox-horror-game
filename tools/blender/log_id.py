"""Record an upload in art/ids.json the moment it returns.

    python tools/blender/log_id.py <name> <operationId> [assetId] [note]
An entry with no asset id yet is kept under "pending"; logging the asset id moves it to
"assets" (the list the asset-id lint reads).
"""
import json
import sys
from datetime import date
from pathlib import Path

IDS = Path(__file__).resolve().parents[2] / "art" / "ids.json"
name, op = sys.argv[1], sys.argv[2]
asset = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
note = sys.argv[4] if len(sys.argv) > 4 else ""
data = json.loads(IDS.read_text(encoding="utf-8"))
data.setdefault("assets", [])
pending = data.setdefault("pending", [])
pending[:] = [p for p in pending if p.get("operation") != op]
if asset:
    data["assets"] = [a for a in data["assets"] if a.get("operation") != op or a.get("name") != name]
    data["assets"].append({
        "name": name, "id": int(asset), "kind": "Model" if not name.endswith("Mesh") else "Mesh",
        "source": f"Open Cloud upload (private, Stewart's account) of art/models/roblox/{name.removesuffix('Mesh')}.glb, {date.today().strftime('%m/%d/%Y')}",
        "operation": op, "note": note,
    })
else:
    pending.append({"name": name, "operation": op, "note": note})
if not data["pending"]:
    del data["pending"]
IDS.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("logged", name, op, asset)
