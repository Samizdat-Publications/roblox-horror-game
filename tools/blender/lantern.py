"""The bow lantern, in BoatHull's frame: a hurricane lantern hanging from an iron arm on a
post at the bow. It covers LanternPost, LanternArm and LanternCap. The glowing ball
(LanternGlow, Neon, coloured by the lantern cosmetic) and its light stay parts at
(0, 2.85, -8.55): the cage is built around that ball, open, so the glow shows through.

    blender -b -P tools/blender/lantern.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import dwb  # noqa: E402

CX, CY, CZ = 0.0, 2.85, -8.55  # the glow ball's centre (radius 0.375)


def lantern_parts():
    post = common.mat("boatTrim")
    metal = common.mat("metal")
    rust = common.mat("rust")

    # The post: a slightly tapered square timber from the bow floor to the arm.
    dwb.tube("Post", [(0, 0.2, -7.4), (0, 1.9, -7.42), (0, 3.62, -7.44)], [0.2, 0.19, 0.17], post, verts=4)
    dwb.rbox((0.42, 0.22, 0.42), (0, 2.2, -7.4), metal, "PostBand")
    dwb.rbox((0.4, 0.16, 0.4), (0, 3.7, -7.44), post, "PostCap")
    # The iron arm, with a little drop at the end and a hook.
    dwb.tube("Arm", [(0, 3.5, -7.3), (0, 3.56, -7.9), (0, 3.52, -8.4), (0, 3.44, -8.6)], [0.09, 0.09, 0.08, 0.07], metal, verts=6)
    dwb.tube("Brace", [(0, 2.9, -7.44), (0, 3.25, -7.72), (0, 3.52, -8.0)], [0.05, 0.05, 0.05], metal, verts=4)

    # The bail: a wire loop from the hook down to the lantern's top plate.
    bail = []
    for i in range(9):
        a = math.pi * i / 8
        bail.append((CX - 0.34 * math.cos(a), 3.28 + 0.2 * math.sin(a), CZ))
    dwb.tube("Bail", bail, [0.035] * len(bail), metal, verts=4)
    # Top plate and the chimney vent.
    common.cyl(0.44, 0.07, dwb.rb(CX, 3.27, CZ), metal, "TopPlate", verts=10)
    common.cyl(0.3, 0.16, dwb.rb(CX, 3.38, CZ), metal, "Vent", verts=10, radius2=0.14)
    common.cyl(0.17, 0.05, dwb.rb(CX, 3.48, CZ), rust, "VentCap", verts=10)
    # Four bowed wire guards around the glow ball.
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        pts = []
        for y, r in ((2.47, 0.43), (2.85, 0.5), (3.24, 0.42)):
            pts.append((CX + r * math.cos(a), y, CZ + r * math.sin(a)))
        dwb.tube(f"Guard{k}", pts, [0.03] * 3, metal, verts=4)
    # Two hoops holding the guards.
    for y, r in ((2.62, 0.47), (3.08, 0.47)):
        ring = [(CX + r * math.cos(t * math.pi / 6), y, CZ + r * math.sin(t * math.pi / 6)) for t in range(13)]
        dwb.tube(f"Hoop{y}", ring, [0.025] * 13, metal, verts=4, cap=False)
    # The fount (fuel tank) under the ball, a burner collar and a rust ring.
    common.cyl(0.46, 0.24, dwb.rb(CX, 2.3, CZ), metal, "Fount", verts=10)
    common.cyl(0.4, 0.06, dwb.rb(CX, 2.15, CZ), rust, "FountFoot", verts=10)
    common.cyl(0.24, 0.07, dwb.rb(CX, 2.45, CZ), rust, "Collar", verts=8)
    # The wick knob, on the side facing the helm.
    common.cyl(0.06, 0.18, dwb.rb(CX + 0.5, 2.32, CZ), metal, "Knob", verts=6, rot=(0, math.pi / 2, 0))


def build():
    lantern_parts()
    common.finish(
        "Lantern",
        "Boat: LanternPost, LanternArm, LanternCap (made see-through); LanternGlow and its light stay",
        "Cast no shadow (the post threw a black wedge down the boat, 11/26/2026).",
        view=(120, 18),
    )


if __name__ == "__main__":
    common.main_guard(build)
