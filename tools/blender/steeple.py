"""The sunken steeple, in the tower frame Landmarks.luau builds it in: origin at the tower's
foot (14 studs under the water), +y up the leaning tower axis. Same footprint and heights as
the part-built tower (W = 12, every height x1.3): stone shaft with coursed bands and corner
quoins, the belfry with pointed louvred openings and corner buttresses, a cornice, an
octagonal spire with a slight kink, and a bent iron cross. The bell stays a part inside.

    blender -b -P tools/blender/steeple.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import dwb  # noqa: E402

W = 12.0
S = 1.3
SHAFT_H = 8 * S
BELFRY_LO = SHAFT_H + 0.6
BELFRY_H = 7 * S
BELFRY_MID = BELFRY_LO + BELFRY_H / 2
CORNICE_Y = BELFRY_LO + BELFRY_H + 0.5
SPIRE_LO = CORNICE_Y + 2
SPIRE_H = 4 * 6 * S


def build():
    stone = common.mat("stone")
    light = common.mat("stoneLight")
    dark = common.mat("stoneDark")
    spire = common.mat("spire")
    black = common.mat("silhouette")
    metal = common.mat("metal")
    moss = common.mat("moss")

    # Shaft with courses every 1.3 studs, alternating a hair proud.
    y = 0.0
    i = 0
    while y < SHAFT_H - 0.01:
        h = min(S, SHAFT_H - y)
        w = W if i % 2 == 0 else W + 0.16
        dwb.rbox((w, h, w), (0, y + h / 2, 0), stone if i % 2 == 0 else dark, f"Course{i}")
        y += h
        i += 1
    # Corner quoins up the shaft and the belfry: long and short blocks.
    for cx in (-1, 1):
        for cz in (-1, 1):
            yy, k = 0.4, 0
            while yy < BELFRY_LO + BELFRY_H - 1:
                long = k % 2 == 0
                sx = 2.2 if long else 1.3
                sz = 1.3 if long else 2.2
                half = W / 2 if yy < SHAFT_H else W / 2 - 0.6
                dwb.rbox((sx, 0.9, sz), (cx * (half - sx / 2 + 0.12), yy + 0.45, cz * (half - sz / 2 + 0.12)), light, f"Quoin{cx}{cz}{k}")
                yy += 1.3
                k += 1
    # String course (belfry floor).
    dwb.rbox((W + 0.6, 0.6, W + 0.6), (0, SHAFT_H + 0.3, 0), light, "StringCourse")
    # Belfry body and buttress posts.
    dwb.rbox((W - 1.2, BELFRY_H, W - 1.2), (0, BELFRY_MID, 0), stone, "Belfry")
    for cx in (-1, 1):
        for cz in (-1, 1):
            dwb.rbox((1.7, BELFRY_H, 1.7), (cx * (W / 2 - 0.85), BELFRY_MID, cz * (W / 2 - 0.85)), dark, f"Buttress{cx}{cz}")
    # Pointed openings with louvres, one on each face.
    face = (W - 1.2) / 2
    open_y = BELFRY_MID + 0.6
    for k in range(4):
        ang = k * math.pi / 2
        fx, fz = math.sin(ang), -math.cos(ang)  # face normal (k = 0 is the front, -z)
        rot = -ang

        def at(u, v, d):
            # u across the face, v up, d out from the face
            return (fx * (face + d) + math.cos(ang) * u, v, fz * (face + d) + math.sin(ang) * u)

        dwb.rbox((4.2, 6.6, 0.3), at(0, open_y - 0.2, 0.05), light, f"Surround{k}", rot_y=rot)
        dwb.rbox((3.4, 5.6, 0.3), at(0, open_y - 0.4, 0.12), black, f"Opening{k}", rot_y=rot)
        # The pointed head of the arch: two tilted blocks meeting at the top.
        for side in (-1, 1):
            dwb.rbox((2.2, 0.6, 0.32), at(side * 0.8, open_y + 2.85, 0.12), black, f"Arch{k}{side}", rot_y=rot, rot_z=side * -0.6)
        for j in range(4):
            dwb.rbox((3.5, 0.26, 0.42), at(0, open_y - 2.6 + j * 1.3, 0.2), spire, f"Louvre{k}{j}", rot_x=0.0, rot_y=rot)
        # A sill.
        dwb.rbox((4.4, 0.35, 0.7), at(0, open_y - 3.35, 0.25), light, f"Sill{k}", rot_y=rot)
    # Cornice and roof base, with moss gathered on the cornice.
    dwb.rbox((W + 1, 1, W + 1), (0, CORNICE_Y, 0), light, "Cornice")
    dwb.rbox((W - 1, 1.5, W - 1), (0, CORNICE_Y + 1.25, 0), spire, "RoofBase")
    for k, (mx, mz, ms) in enumerate(((-4.2, -5.6, 2.6), (3.1, -5.7, 1.6), (5.6, 1.8, 2.2), (-5.7, 3.4, 1.4))):
        dwb.rbox((ms if abs(mz) > 5 else 0.9, 0.35, ms if abs(mx) > 5 else 0.9), (mx, CORNICE_Y + 0.62, mz), moss, f"Moss{k}")
    # Octagonal spire in two segments with a slight kink, and little gabled vents at its foot.
    kink = SPIRE_LO + SPIRE_H * 0.55
    bend = math.radians(4)
    top = (math.sin(bend) * (SPIRE_H * 0.45), SPIRE_LO + SPIRE_H - 1.0, 0.0)
    dwb.tube("Spire", [(0, SPIRE_LO, 0), (0, kink, 0), top], [4.3, 2.0, 0.3], spire, verts=8)
    for k in range(4):
        ang = k * math.pi / 2 + math.pi / 4
        r = 3.9
        cx, cz = math.sin(ang) * r, -math.cos(ang) * r
        dwb.rbox((1.6, 2.2, 1.6), (cx, SPIRE_LO + 1.3, cz), spire, f"Lucarne{k}", rot_y=-ang)
        dwb.rbox((0.8, 1.0, 0.2), (cx * 1.21, SPIRE_LO + 1.2, cz * 1.21), black, f"LucarneHole{k}", rot_y=-ang)
    # The iron cross, bent over.
    cross_base = top
    tilt = math.radians(14)
    up = (math.sin(tilt) * 4.4, math.cos(tilt) * 4.4)
    dwb.tube("CrossUp", [cross_base, (cross_base[0] + up[0], cross_base[1] + up[1], 0)], [0.28, 0.25], metal, verts=4)
    bar_c = (cross_base[0] + up[0] * 0.7, cross_base[1] + up[1] * 0.7, 0)
    dwb.rbox((2.8, 0.5, 0.5), bar_c, metal, "CrossBar", rot_z=-tilt)
    common.finish(
        "Steeple",
        "Landmarks Steeple folder: Shaft, Belfry*, Cornice, RoofBase, Spire1-4, CrossUp, CrossBar (made see-through); Bell and BellLip stay",
        "Origin of the authoring frame is the tower's foot; +y runs up the leaning axis.",
        view=(30, 12),
        max_tris=20000,
    )


if __name__ == "__main__":
    common.main_guard(build)
