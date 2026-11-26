"""Rebuild every model, preview and the contact sheet, in one Blender (or bpy) process.

    blender -b -P art/scripts/build_all.py        (Blender 5.1)
    python art/scripts/build_all.py               (Python with `pip install bpy==5.1.2`)

The contact sheet needs Pillow; without it the models and previews are still built.
"""

import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
SCRIPTS = ["dock", "fish_buyer", "bait_shop", "pond_rim", "logs", "buoy", "reeds", "trees", "rocks", "fish", "rods", "boat"]

for name in SCRIPTS:
    print(f"== {name}", flush=True)
    sys.argv = [str(HERE / f"{name}.py")]
    runpy.run_path(str(HERE / f"{name}.py"), run_name="__main__")
try:
    sys.argv = [str(HERE / "contact_sheet.py")]
    runpy.run_path(str(HERE / "contact_sheet.py"), run_name="__main__")
except ImportError as e:
    print("contact sheet skipped (needs Pillow):", e)
