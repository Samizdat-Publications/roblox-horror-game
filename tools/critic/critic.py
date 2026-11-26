"""The playtest critic: sends stills, clips (with audio) and docs to a Gemini 4 model with a
rubric and writes the verdict to docs/critic/<date>-<step>-<model>.md.

    review  (Neon by default)    score out of 10, strengths, top 3 fixes, anything broken
    rank    (Hydrogen by default) order many variants (sounds, model previews) best first
    consult (Carbon by default)  open design questions over the docs, stills and clips

Examples (from the repo root):
    python tools/critic/critic.py review --step beauty-lake --rubric look docs/making-of/stills/x.jpg clip.mp4
    python tools/critic/critic.py rank --step bite-sfx --criteria "a tense, quiet bobber tap" audio/variants/*.mp3
    python tools/critic/critic.py consult --step milestone-1 --question "What would make waiting for a bite more tense?" clip.mp4

The critics inform; the playtest and Stewart decide. Every verdict is logged, acted on or not.
"""
import argparse
import datetime as dt
import glob
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gemini  # noqa: E402

ROOT = gemini.ROOT
RUBRICS = Path(__file__).resolve().parent / "rubrics"
OUT = ROOT / "docs" / "critic"
CONTEXT = (
    "The game is \"Don't Wave Back\": 1 to 4 players in a rowboat on a foggy lake at night, fishing a quota while "
    "following a rulebook of Lake Rules. Sound is the most important part of the game: the frog chorus is the "
    "players' only danger meter. Sounds must be natural, clean, free of voices and music (unless the entry is "
    "music), not harsh or shrill, and loops must loop without an obvious seam or a recognisable repeating event. "
    "Roblox, blocky low-detail visuals, heavy fog, lantern light, ages 10 and up: scary but never gory or disturbing. "
    "Be specific and honest; name exact things you see or hear, with timestamps for clips."
)

REVIEW_SCHEMA = {
    "type": "object",
    "properties": {
        "score": {"type": "number", "description": "0 to 10 overall"},
        "scores": {
            "type": "array",
            "description": "0 to 10 for each rubric point you could judge",
            "items": {
                "type": "object",
                "properties": {"point": {"type": "string"}, "score": {"type": "number"}},
                "required": ["point", "score"],
            },
        },
        "summary": {"type": "string"},
        "strengths": {"type": "array", "items": {"type": "string"}},
        "top_fixes": {"type": "array", "items": {"type": "string"}, "description": "the 3 changes that would help most, most important first"},
        "broken": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["score", "summary", "strengths", "top_fixes", "broken"],
}

RANK_SCHEMA = {
    "type": "object",
    "properties": {
        "ranking": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"file": {"type": "string"}, "score": {"type": "number"}, "note": {"type": "string"}},
                "required": ["file", "score", "note"],
            },
        },
        "summary": {"type": "string"},
    },
    "required": ["ranking", "summary"],
}

CONSULT_SCHEMA = {
    "type": "object",
    "properties": {
        "answer": {"type": "string"},
        "suggestions": {"type": "array", "items": {"type": "string"}},
        "missing_vs_best_horror_games": {"type": "array", "items": {"type": "string"}},
        "looks_broken": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["answer", "suggestions"],
}


def expand(paths: list[str]) -> list[Path]:
    out = []
    for p in paths:
        hits = glob.glob(p) or [p]
        out += [Path(h) for h in hits]
    missing = [str(p) for p in out if not p.exists()]
    if missing:
        raise SystemExit("Not found: " + ", ".join(missing))
    return out


def media_parts(files: list[Path], uploaded: list) -> list:
    parts = []
    for f in files:
        parts.append({"text": f"File: {f.name}"})
        parts.append(gemini.part_for(f, uploaded))
    return parts


def write_report(step: str, model: str, mode: str, files: list[Path], prompt_note: str, verdict: dict) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    day = dt.date.today().isoformat()
    path = OUT / f"{day}-{step}-{model.removeprefix('gemini-4-')}.md"
    n = 2
    while path.exists():
        path = OUT / f"{day}-{step}-{model.removeprefix('gemini-4-')}-{n}.md"
        n += 1
    lines = [
        f"# Critic: {step} ({mode}, {model})",
        "",
        f"Date: {dt.datetime.now().strftime('%Y-%m-%d %H:%M')}. {prompt_note}",
        "",
        "Files shown:",
        *[f"- `{f.relative_to(ROOT) if f.is_relative_to(ROOT) else f.name}`" for f in files],
        "",
    ]
    if mode == "review":
        lines += [f"**Score: {verdict['score']}/10**", "", verdict["summary"], ""]
        if verdict.get("scores"):
            lines += ["| Point | Score |", "|---|---|", *[f"| {x['point']} | {x['score']} |" for x in verdict["scores"]], ""]
        lines += ["Top fixes:", *[f"{i}. {x}" for i, x in enumerate(verdict["top_fixes"], 1)], ""]
        lines += ["Strengths:", *[f"- {x}" for x in verdict["strengths"]], ""]
        if verdict.get("broken"):
            lines += ["Broken or ugly:", *[f"- {x}" for x in verdict["broken"]], ""]
    elif mode == "rank":
        lines += [verdict["summary"], "", "| Rank | File | Score | Note |", "|---|---|---|---|"]
        lines += [f"| {i} | `{r['file']}` | {r['score']} | {r['note']} |" for i, r in enumerate(verdict["ranking"], 1)]
        lines += [""]
    else:
        lines += [verdict["answer"], "", "Suggestions:", *[f"- {x}" for x in verdict["suggestions"]], ""]
        for key, title in (("missing_vs_best_horror_games", "Missing compared with the best horror games"), ("looks_broken", "Looks broken")):
            if verdict.get(key):
                lines += [f"{title}:", *[f"- {x}" for x in verdict[key]], ""]
    lines += ["Action taken: (fill in: what we changed, or why we didn't)", ""]
    # House rule: no em dashes in anything a person reads; models like to write them.
    text = "\n".join(lines).replace(" — ", " - ").replace("—", " - ")
    path.write_text(text, encoding="utf-8")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["review", "rank", "consult"])
    ap.add_argument("files", nargs="*")
    ap.add_argument("--step", required=True, help="short slug for the file name, like beauty-lake")
    ap.add_argument("--model", choices=list(gemini.MODELS), help="defaults: review neon, rank hydrogen, consult carbon")
    ap.add_argument("--rubric", default="look", help="tools/critic/rubrics/<name>.md (review mode)")
    ap.add_argument("--criteria", default="", help="what 'best' means (rank mode)")
    ap.add_argument("--question", default="", help="the open question (consult mode)")
    ap.add_argument("--note", default="", help="extra context for the critic, like what changed in this step")
    args = ap.parse_args()

    model = gemini.MODELS[args.model or {"review": "neon", "rank": "hydrogen", "consult": "carbon"}[args.mode]]
    files = expand(args.files)
    uploaded: list[str] = []
    try:
        parts = [{"text": CONTEXT}]
        if args.note:
            parts.append({"text": "What changed in this step: " + args.note})
        if args.mode == "review":
            rubric = (RUBRICS / f"{args.rubric}.md").read_text(encoding="utf-8")
            parts.append({"text": "Rubric:\n" + rubric})
            parts += media_parts(files, uploaded)
            verdict = gemini.generate(model, parts, REVIEW_SCHEMA)
            note = f"Rubric: `{args.rubric}`."
        elif args.mode == "rank":
            parts.append({"text": f"Rank these variants best first for: {args.criteria}. Use each file's name as given."})
            parts += media_parts(files, uploaded)
            verdict = gemini.generate(model, parts, RANK_SCHEMA)
            note = f"Criteria: {args.criteria}"
        else:
            for doc in ("docs/DESIGN.md", "docs/ARCHITECTURE.md", "PROGRESS.md"):
                parts.append({"text": f"--- {doc} ---\n" + (ROOT / doc).read_text(encoding="utf-8")})
            parts.append({"text": "Open question: " + (args.question or "What would make this more fun, more beautiful or more tense? What is missing compared with the best horror games? What looks broken?")})
            parts += media_parts(files, uploaded)
            verdict = gemini.generate(model, parts, CONSULT_SCHEMA)
            note = f"Question: {args.question or '(default open questions)'}"
    finally:
        for name in uploaded:
            gemini.delete(name)
    path = write_report(args.step, model, args.mode, files, note, verdict)
    print(json.dumps(verdict, indent=2)[:3000])
    print(f"\nWrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
