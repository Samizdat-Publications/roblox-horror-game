"""Rank the 2 takes of each tape line with Gemini Hydrogen; winners to audio/final/<tape-id>.mp3,
report docs/critic/11-26-2026-tapes.md."""
import hashlib, json, random, shutil, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "critic"))
import critic, gemini  # noqa: E402
V = ROOT / "audio" / "variants"; F = ROOT / "audio" / "final"
CRIT = ("an older tired kind dry rural man speaking quietly into a cheap recorder late at night; deadpan, unhurried, "
        "natural; no theatrical menace; every word intelligible")

def once(t, files):
    up = []
    try:
        parts = [{"text": critic.CONTEXT}, {"text": (
            f"These are {len(files)} takes of one spoken tape line, '{t['id']}'. Spoken text: \"{t['text']}\"\n"
            f"Criteria: {CRIT}. Also penalise robotic delivery, mispronounced words and artifacts. Rank best first. "
            "If all are poor, say so in the summary starting with 'ALL POOR:'. Use each file's name exactly as given.")}]
        parts += critic.media_parts(files, up)
        return gemini.generate(gemini.MODELS["hydrogen"], parts, critic.RANK_SCHEMA)
    finally:
        for n in up: gemini.delete(n)

rows = []; fails = []
for t in json.loads((ROOT / "audio" / "tapes.json").read_text(encoding="utf-8"))["tapes"]:
    sid = t["id"]
    files = sorted(V.glob(f"{sid}-*.mp3"))
    sh = files[:]; random.Random(int(hashlib.sha256(sid.encode()).hexdigest(), 16)).shuffle(sh)
    v = None
    for a in range(6):
        try: v = once(t, sh); break
        except (SystemExit, Exception) as e:
            print("retry", str(e)[:200], flush=True); time.sleep(25)
    if not v: fails.append(sid); continue
    b = v["ranking"][0]
    src = next((f for f in files if f.name == b["file"]), sh[0])
    shutil.copyfile(src, F / f"{sid}.mp3")
    rows.append((sid, src.name, sh.index(src) + 1, b["score"], str(b["note"]).replace("|", "/"), v["summary"]))
    print(sid, src.name, sh.index(src) + 1, flush=True)
tally = {}
for r in rows: tally[r[2]] = tally.get(r[2], 0) + 1
L = ["# Critic: tapes (rank, gemini-4-hydrogen)", "", f"Criteria: {CRIT}.", "",
     "| Tape | Winner | Shuffled position | Score | Why |", "|---|---|---|---|---|",
     *[f"| {r[0]} | `{r[1]}` | {r[2]} of 2 | {r[3]} | {r[4]} |" for r in rows], "", "Summaries:",
     *[f"- {r[0]}: {r[5]}" for r in rows if r[5]], "",
     "Tally: " + ", ".join(f"position {k}: {v}" for k, v in sorted(tally.items())), ""]
if fails: L += ["Failures: " + ", ".join(fails), ""]
(ROOT / "docs" / "critic" / "11-26-2026-tapes.md").write_text("\n".join(L).replace("—", " - "), encoding="utf-8")
