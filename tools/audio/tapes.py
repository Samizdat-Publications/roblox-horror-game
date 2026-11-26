"""Owner cassette tapes: design (or reuse) one ElevenLabs voice, then speak each tape line, 2 takes each.

    python tools/audio/tapes.py [--takes 2] [--only tape-night-1]

Voice: audio/tapes.json voice.voice_id is reused if present. Otherwise POST /v1/text-to-voice/design then
POST /v1/text-to-voice (saved as "Tull (Dont Wave Back)"). On a non-transient error the error is recorded in
tapes.json voice.design_error and the best existing library voice is used (voice.fallback = true).
Speech model: eleven_multilingual_v2. Output: audio/variants/<tape-id>-<n>.mp3 (resumable).
"""
import argparse, json, sys, time, urllib.request, urllib.error
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import eleven

ROOT = eleven.ROOT
TAPES = ROOT / "audio" / "tapes.json"
MODEL = "eleven_multilingual_v2"
NAME = "Tull (Dont Wave Back)"


def call(method, path, body=None):
    last = ""
    for attempt in range(1, 7):
        req = urllib.request.Request(eleven.API + path, method=method,
                                     data=json.dumps(body).encode() if body is not None else None,
                                     headers={"xi-api-key": eleven.api_key(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            last = f"ElevenLabs error {e.code} on {path}: {e.read().decode('utf-8','replace')[:500]}"
            if not (e.code == 429 or e.code >= 500):
                raise eleven.ApiError(last)
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            last = f"network error on {path}: {e}"
        print(f"    retry {attempt}/6 after: {last[:160]}", flush=True)
        time.sleep(25)
    raise eleven.ApiError(last)


def save_cfg(cfg):
    TAPES.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def ensure_voice(cfg):
    v = cfg["voice"]
    if v.get("voice_id"):
        return v["voice_id"]
    try:
        d = json.loads(call("POST", "/v1/text-to-voice/design", {
            "voice_description": v["description"], "model_id": "eleven_ttv_v3",
            "auto_generate_text": True}))
        gid = d["previews"][0]["generated_voice_id"]
        s = json.loads(call("POST", "/v1/text-to-voice", {
            "voice_name": NAME, "voice_description": v["description"], "generated_voice_id": gid}))
        v.update(voice_id=s["voice_id"], voice_name=NAME, method="voice design (eleven_ttv_v3, preview 1 of %d)" % len(d["previews"]))
        v.pop("design_error", None)
    except eleven.ApiError as e:
        v["design_error"] = str(e)
        print("voice design failed:", e)
        lst = json.loads(call("GET", "/v1/voices?page_size=100"))["voices"]
        def score(x):
            l = x.get("labels") or {}
            t = " ".join(str(z) for z in l.values()).lower() + " " + (x.get("description") or "").lower()
            return sum(k in t for k in ["american", "male", "old", "middle", "low", "deep", "calm", "raspy", "gravel", "dry", "narrat"]) - 3 * ("female" in t)
        best = max(lst, key=score)
        v.update(voice_id=best["voice_id"], voice_name=best["name"], method="fallback: existing voice", fallback=True)
    save_cfg(cfg)
    return v["voice_id"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--takes", type=int, default=2)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    cfg = json.loads(TAPES.read_text(encoding="utf-8"))
    vid = ensure_voice(cfg)
    cfg["voice"]["speech_model"] = MODEL
    save_cfg(cfg)
    only = set(filter(None, a.only.split(",")))
    fails = []
    for t in cfg["tapes"]:
        if only and t["id"] not in only:
            continue
        for n in range(1, a.takes + 1):
            p = eleven.OUT / f"{t['id']}-{n}.mp3"
            if p.exists() and p.stat().st_size > 2048:
                continue
            try:
                data = call("POST", f"/v1/text-to-speech/{vid}?output_format=mp3_44100_128", {
                    "text": t["text"], "model_id": MODEL,
                    "voice_settings": {"stability": 0.6, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": True, "speed": 0.92}})
                eleven.save(t["id"], n, data)
                print(f"{p.name} ({len(data)//1024} KB)", flush=True)
            except eleven.ApiError as e:
                fails.append((p.name, str(e))); print("FAILED", p.name, e)
    if fails:
        sys.exit(1)

if __name__ == "__main__":
    main()
