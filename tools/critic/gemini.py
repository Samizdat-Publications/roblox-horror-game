"""Minimal Gemini API client (standard library only): read the key from the local .env,
upload files with the Files API, and ask a model for a JSON verdict.

The key is read from GEMINI_API_KEY in the repo's .env (never committed) or the
environment. It is sent only in the x-goog-api-key header and never printed.
"""
import base64
import json
import mimetypes
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
API = "https://generativelanguage.googleapis.com"

# Short names used by critic.py, mapped to the Gemini 4 model ids (docs/DIRECTION.md).
MODELS = {
    "hydrogen": "gemini-4-hydrogen",  # cheap screener
    "neon": "gemini-4-neon",  # everyday critic
    "carbon": "gemini-4-carbon",  # milestone design consultant
}

INLINE_LIMIT = 4 * 1024 * 1024  # small images go inline; video and audio go through the Files API


def api_key() -> str:
    key = os.environ.get("GEMINI_API_KEY", "")
    env = ROOT / ".env"
    if not key and env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("GEMINI_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        raise SystemExit("GEMINI_API_KEY is missing: put it in the repo's .env (see .env.example).")
    return key


def _request(method: str, url: str, body: bytes | None = None, headers: dict | None = None):
    h = {"x-goog-api-key": api_key()}
    h.update(headers or {})
    req = urllib.request.Request(url, data=body, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:800]
        raise SystemExit(f"Gemini API error {e.code} on {method} {url.split('?')[0]}: {detail}")


def list_models() -> list[str]:
    _, _, data = _request("GET", f"{API}/v1beta/models?pageSize=200")
    return [m["name"].removeprefix("models/") for m in json.loads(data).get("models", [])]


def _mime(path: Path) -> str:
    m, _ = mimetypes.guess_type(str(path))
    return m or "application/octet-stream"


def upload(path: Path) -> dict:
    """Upload a file (video, audio, large image) and wait until Gemini has processed it."""
    data = path.read_bytes()
    mime = _mime(path)
    _, headers, _ = _request(
        "POST",
        f"{API}/upload/v1beta/files",
        json.dumps({"file": {"display_name": path.name}}).encode(),
        {
            "X-Goog-Upload-Protocol": "resumable",
            "X-Goog-Upload-Command": "start",
            "X-Goog-Upload-Header-Content-Length": str(len(data)),
            "X-Goog-Upload-Header-Content-Type": mime,
            "Content-Type": "application/json",
        },
    )
    upload_url = next(v for k, v in headers.items() if k.lower() == "x-goog-upload-url")
    _, _, body = _request(
        "POST",
        upload_url,
        data,
        {"X-Goog-Upload-Offset": "0", "X-Goog-Upload-Command": "upload, finalize", "Content-Length": str(len(data))},
    )
    f = json.loads(body)["file"]
    while f.get("state") == "PROCESSING":
        time.sleep(3)
        _, _, body = _request("GET", f"{API}/v1beta/{f['name']}")
        f = json.loads(body)
    if f.get("state") == "FAILED":
        raise SystemExit(f"Gemini could not process {path.name}")
    return f


def delete(file_name: str) -> None:
    try:
        _request("DELETE", f"{API}/v1beta/{file_name}")
    except SystemExit:
        pass  # files expire on their own after 48 hours


def part_for(path: Path, uploaded: list) -> dict:
    """A content part for a file: inline for small images, an uploaded file otherwise."""
    mime = _mime(path)
    if mime.startswith("image/") and path.stat().st_size <= INLINE_LIMIT:
        return {"inline_data": {"mime_type": mime, "data": base64.b64encode(path.read_bytes()).decode()}}
    f = upload(path)
    uploaded.append(f["name"])
    return {"file_data": {"mime_type": f.get("mimeType", mime), "file_uri": f["uri"]}}


def generate(model: str, parts: list, schema: dict | None = None) -> dict:
    body = {"contents": [{"role": "user", "parts": parts}], "generationConfig": {"temperature": 0.4}}
    if schema:
        body["generationConfig"]["responseMimeType"] = "application/json"
        body["generationConfig"]["responseSchema"] = schema
    _, _, data = _request(
        "POST",
        f"{API}/v1beta/models/{model}:generateContent",
        json.dumps(body).encode(),
        {"Content-Type": "application/json"},
    )
    out = json.loads(data)
    text = "".join(p.get("text", "") for p in out["candidates"][0]["content"]["parts"])
    return json.loads(text) if schema else {"text": text}
