"""Rank every sound's variants with the cheap critic (Gemini 4 Hydrogen), copy each winner to
audio/final/<id>.mp3 and write a report to docs/critic/11-26-2026-sound-variants-<batch>.md.

    python tools/audio/rank_all.py --batch m1 [--only id1,id2] [--force]

Variant order is shuffled (seeded from the sound id) before the ranker hears it, because the ranker
favours whichever file it hears first; results are mapped back to the real file names.
Resumable: ids that already have audio/final/<id>.mp3 are skipped unless --force.
"""
import argparse
import hashlib
import json
import random
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "critic"))
import critic  # noqa: E402
import gemini  # noqa: E402

VARIANTS = ROOT / "audio" / "variants"
FINAL = ROOT / "audio" / "final"
SPOS = ROOT / "audio" / "ranked"  # per-id result cache so a report can be rebuilt after a resume


def rank_once(spec, shuffled):
    uploaded: list[str] = []
    try:
        loop_rule = " It must loop cleanly: the end joins the start with no click, fade or recognisable repeating event." if spec.get("loop") else ""
        iso_rule = (" This must be ONE ISOLATED single animal calling: any variant with more than one animal, a chorus, crickets or other insects, or audible background hiss is a FAIL and must rank last."
                    if spec.get("batch") == "m1b" else "")
        kind = "music" if spec.get("kind") == "music" else "sound effect"
        parts = [
            {"text": critic.CONTEXT},
            {
                "text": (
                    f"These are {len(shuffled)} variants of one game {kind}, '{spec['id']}'. What it should be: "
                    f"{spec['prompt']}\nCriteria: fits that description; natural and clean (no artifacts, clicks, voices"
                    + ("" if spec.get("kind") == "music" else ", music") +
                    " where none belongs); not harsh or shrill; right length and loudness."
                    + loop_rule + iso_rule +
                    " Rank them best first. If all of them are poor, say so in the summary starting with 'ALL POOR:'. "
                    "Use each file's name exactly as given."
                )
            },
        ]
        parts += critic.media_parts(shuffled, uploaded)
        return gemini.generate(gemini.MODELS["hydrogen"], parts, critic.RANK_SCHEMA)
    finally:
        for name in uploaded:
            gemini.delete(name)


def rank_retry(spec, shuffled):
    last = ""
    for attempt in range(1, 7):
        try:
            return rank_once(spec, shuffled)
        except (SystemExit, Exception) as e:  # gemini._request raises SystemExit on HTTP errors
            last = str(e)[:300]
            print(f"    retry {attempt}/6 after: {last}", flush=True)
            time.sleep(25)
    raise RuntimeError(last)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--batch", default="")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    specs = json.loads((ROOT / "audio" / "sounds.json").read_text(encoding="utf-8"))["sounds"]
    FINAL.mkdir(parents=True, exist_ok=True)
    SPOS.mkdir(parents=True, exist_ok=True)
    rows = []
    failures = []
    for spec in specs:
        sid = spec["id"]
        if only and sid not in only:
            continue
        if args.batch and spec.get("batch") != args.batch:
            continue
        cache = SPOS / f"{sid}.json"
        if (FINAL / f"{sid}.mp3").exists() and not args.force:
            if cache.exists():
                rows.append(json.loads(cache.read_text(encoding="utf-8")))
            print(f"{sid}: skip (final exists)")
            continue
        files = sorted(f for f in VARIANTS.glob(f"{sid}-*.mp3") if f.stat().st_size > 2048)
        if not files:
            print(f"{sid}: no variants")
            failures.append((sid, "no variants"))
            continue
        shuffled = files[:]
        random.Random(int(hashlib.sha256(sid.encode()).hexdigest(), 16)).shuffle(shuffled)
        try:
            verdict = rank_retry(spec, shuffled) if len(files) > 1 else {"ranking": [{"file": files[0].name, "score": 0, "note": "only one variant"}], "summary": ""}
        except RuntimeError as e:
            failures.append((sid, str(e)))
            print(f"{sid}: FAILED {e}")
            continue
        best = verdict["ranking"][0]
        src = next((f for f in files if f.name == best["file"]), None)
        if src is None:  # ranker returned a name we did not send; fall back to first listed
            src = next((f for f in files if best["file"] in f.name or f.name in best["file"]), shuffled[0])
        shutil.copyfile(src, FINAL / f"{sid}.mp3")
        row = {"id": sid, "winner": src.name, "score": best["score"], "note": best["note"], "pos": shuffled.index(src) + 1, "n": len(shuffled), "summary": verdict["summary"]}
        cache.write_text(json.dumps(row), encoding="utf-8")
        rows.append(row)
        print(f"{sid}: {src.name} (shuffled position {row['pos']}/{row['n']}, score {best['score']})", flush=True)
    out = ROOT / "docs" / "critic" / f"11-26-2026-sound-variants-{args.batch or 'all'}.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    tally: dict[int, int] = {}
    for r in rows:
        tally[r["pos"]] = tally.get(r["pos"], 0) + 1
    lines = [
        f"# Critic: sound variants {args.batch or 'all'} (rank, gemini-4-hydrogen)",
        "",
        "Variants were shuffled (seeded by sound id) before ranking so file order cannot bias the ranker; the position column is the winner's place in that shuffled order.",
        "",
        "| Sound | Winner | Shuffled position | Score | Why |",
        "|---|---|---|---|---|",
        *[f"| {r['id']} | `{r['winner']}` | {r['pos']} of {r['n']} | {r['score']} | {str(r['note']).replace('|', '/')} |" for r in rows],
        "",
        "Ranker summaries:",
        *[f"- {r['id']}: {r['summary']}" for r in rows if r["summary"]],
        "",
        "Tally of winning shuffled positions: " + ", ".join(f"position {k}: {v}" for k, v in sorted(tally.items())),
        "",
    ]
    if failures:
        lines += ["Failures:", *[f"- {i}: {e}" for i, e in failures], ""]
    text = "\n".join(lines).replace(" \u2014 ", " - ").replace("\u2014", " - ")
    out.write_text(text, encoding="utf-8")
    print(f"Wrote {out.relative_to(ROOT)}")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
