"""Plain-text consult with a Gemini model, streamed so a slow connection cannot time it out.

    python tools/critic/ask.py --step design-consult --model neon --question-file q.txt docs/DESIGN.md [clip.mp4 ...]
    python tools/critic/ask.py --step x --question "..." docs/DESIGN.md

Text files (.md, .txt, .luau, .json) are pasted into the prompt. Images, audio and video are
attached (video and audio through the Files API). Writes docs/critic/<MM-DD-YYYY>-<step>-<model>.md
ending in an "Action taken" section for the orchestrator to fill in. Standard library only.
The critic informs; the orchestrator decides.
"""
import argparse
import datetime
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gemini  # noqa: E402

ROOT = gemini.ROOT
TEXT_EXT = {".md", ".txt", ".luau", ".lua", ".json", ".toml", ".py"}


def stream(model: str, parts: list, max_tokens: int, temperature: float) -> tuple[str, str]:
    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens},
    }
    req = urllib.request.Request(
        f"{gemini.API}/v1beta/models/{model}:streamGenerateContent?alt=sse",
        data=json.dumps(body).encode(),
        method="POST",
        headers={"x-goog-api-key": gemini.api_key(), "Content-Type": "application/json"},
    )
    text, finish = [], ""
    with urllib.request.urlopen(req, timeout=180) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            try:
                chunk = json.loads(line[5:].strip())
            except json.JSONDecodeError:
                continue
            for cand in chunk.get("candidates", []):
                for p in cand.get("content", {}).get("parts", []):
                    if p.get("text") and not p.get("thought"):
                        text.append(p["text"])
                finish = cand.get("finishReason", finish)
    return "".join(text), finish


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--step", required=True)
    ap.add_argument("--model", default="neon", choices=list(gemini.MODELS))
    ap.add_argument("--question")
    ap.add_argument("--question-file")
    ap.add_argument("--max-tokens", type=int, default=6000)
    ap.add_argument("--temperature", type=float, default=0.5)
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()

    question = a.question or ""
    if a.question_file:
        question = Path(a.question_file).read_text(encoding="utf-8")
    if not question.strip():
        raise SystemExit("Give --question or --question-file.")

    parts, uploaded, shown = [{"text": question}], [], []
    try:
        for f in a.files:
            p = Path(f)
            if not p.is_absolute():
                p = ROOT / p
            shown.append(p.name)
            if p.suffix.lower() in TEXT_EXT:
                parts.append({"text": f"\n--- {p.name} ---\n" + p.read_text(encoding="utf-8")})
            else:
                parts.append(gemini.part_for(p, uploaded))

        text, finish, err = "", "", ""
        for attempt in range(1, 7):
            try:
                text, finish = stream(gemini.MODELS[a.model], parts, a.max_tokens, a.temperature)
                if text.strip():
                    break
                err = f"empty answer (finish {finish})"
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                err = f"{type(e).__name__}: {e}"
            print(f"attempt {attempt} failed: {err}; retrying in 25 s", flush=True)
            time.sleep(25)
        if not text.strip():
            raise SystemExit(f"No answer after 6 attempts: {err}")
    finally:
        for name in uploaded:
            gemini.delete(name)

    text = text.replace("—", ", ").replace("–", "-")
    stamp = datetime.date.today().strftime("%m-%d-%Y")
    out = ROOT / "docs" / "critic" / f"{stamp}-{a.step}-{a.model}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        f"# Critic consult: {a.step} ({gemini.MODELS[a.model]})\n\n"
        f"Date: {datetime.date.today().strftime('%m/%d/%Y')}. Files shown: {', '.join(shown) or 'none'}. Finish: {finish}.\n\n"
        f"## Question\n\n{question.strip()}\n\n## Answer\n\n{text.strip()}\n\n"
        "## Action taken\n\n(fill in: what we changed, or why we did not)\n",
        encoding="utf-8",
    )
    print(f"Wrote {out.relative_to(ROOT)} ({len(text)} chars, finish {finish})")


if __name__ == "__main__":
    main()
