"""Generate style-board concept images with Gemini (stdlib only, resumable).
Usage: python gen.py [--force id-scene ...]. Optional "overrides" in styles.json maps
"style-scene" to a replacement full prompt."""
import base64, json, sys, time, urllib.request, urllib.error
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "art" / "style-board"
API = "https://generativelanguage.googleapis.com/v1beta/models/"
MODELS = ["gemini-nano-banana-2.1", "gemini-3.1-flash-image"]  # tried in order, first that works is kept

def key():
    for l in (ROOT / ".env").read_text(encoding="utf-8").splitlines():
        if l.startswith("GEMINI_API_KEY="):
            return l.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("no key")

def call(model, prompt):
    body = {"contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "16:9"}}}
    for attempt in range(6):
        req = urllib.request.Request(API + model + ":generateContent", data=json.dumps(body).encode(),
              headers={"x-goog-api-key": key(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                d = json.load(r)
            for c in d.get("candidates", []):
                for p in c.get("content", {}).get("parts", []):
                    inl = p.get("inlineData") or p.get("inline_data")
                    if inl:
                        mime = inl.get("mimeType") or inl.get("mime_type", "image/png")
                        return base64.b64decode(inl["data"]), ("jpg" if "jpeg" in mime else "png")
            raise RuntimeError("no image in response: " + json.dumps(d)[:300])
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:300]
            if e.code in (400, 403, 404):
                raise RuntimeError(f"HTTP {e.code} {msg}")
            print(f"  HTTP {e.code}, retry in 25s", flush=True); time.sleep(25)
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            print(f"  net error {e!r}, retry in 25s", flush=True); time.sleep(25)
        except RuntimeError as e:
            print(f"  {e}; retry in 25s", flush=True); time.sleep(25)
    raise RuntimeError("gave up after 6 tries")

def main():
    cfg = json.loads((HERE / "styles.json").read_text(encoding="utf-8"))
    force = set(a for a in sys.argv[1:] if a != "--force")
    OUT.mkdir(parents=True, exist_ok=True)
    mpath = OUT / "manifest.json"
    manifest = {e["file"]: e for e in json.loads(mpath.read_text())} if mpath.exists() else {}
    models = list(MODELS)
    for s in cfg["styles"]:
        for sc in cfg["scenes"]:
            tag = f'{s["id"]}-{sc["id"]}'
            prompt = cfg["overrides"].get(tag) or f'{cfg["shared"]} {sc["text"]} {s["text"]}'
            have = [p for p in OUT.glob(tag + ".*") if p.suffix in (".png", ".jpg") and p.stat().st_size > 20480]
            if have and tag not in force:
                print("skip", tag); continue
            print("gen", tag, flush=True)
            while True:
                try:
                    data, ext = call(models[0], prompt); break
                except RuntimeError as e:
                    if len(models) > 1 and "HTTP" in str(e):
                        print("  model failed:", e, "; falling back", flush=True); models.pop(0); continue
                    print("FAILED", tag, e); data = None; break
            if data is None: continue
            for p in OUT.glob(tag + ".*"):
                if p.suffix in (".png", ".jpg"): p.unlink()
            f = f"{tag}.{ext}"
            (OUT / f).write_bytes(data)
            manifest[f] = {"file": f, "style_id": s["id"], "style_name": s["name"], "scene_id": sc["id"],
                           "model": models[0], "prompt": prompt}
            mpath.write_text(json.dumps(list(manifest.values()), indent=2), encoding="utf-8")
            time.sleep(3)
main()
