"""The player's rowboat, in BoatHull's frame (origin: hull centre at the waterline, bow along
-z, port -x). Two meshes:

  BoatShell     the outer planking (sides, transom, bow), no vertex colours, so the game
                colours it with MeshPart.Color and the boat paint cosmetic still works.
  BoatInterior  keel, gunwale caps, ribs, floorboards, thwarts and oarlocks, vertex coloured.

The Seat parts, the hold box, the motor, the oars and the lantern stay parts (they move,
glow or get painted at runtime). The thwart tops sit at y = 1.15, the seat tops of the parts.

    blender -b -P tools/blender/boat.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import dwb  # noqa: E402
from dwb import rb  # noqa: E402

# Stations stern to bow: (z, half beam at the sheer, sheer height, bottom height).
STATIONS = [
    (6.25, 2.45, 1.86, -0.12),
    (4.4, 2.68, 1.80, -0.30),
    (1.6, 2.76, 1.76, -0.36),
    (-1.4, 2.72, 1.78, -0.36),
    (-4.0, 2.50, 1.86, -0.30),
    (-6.0, 1.95, 1.98, -0.16),
    (-7.6, 1.15, 2.14, 0.06),
    (-8.7, 0.40, 2.30, 0.32),
    (-9.25, 0.06, 2.42, 0.55),
]
# Cross-section, keel to sheer, as (fraction of half beam, fraction of depth up).
PROFILE = [(0.0, 0.0), (0.42, 0.02), (0.74, 0.12), (0.92, 0.38), (0.99, 0.68), (1.0, 1.0)]
T = 0.24  # plank thickness


def section(st, inset=0.0, flare=1.0):
    """Points across one station, port sheer to starboard sheer (Roblox axes)."""
    z, hb, sheer, bot = st
    hb = max(hb - inset, 0.02)
    bot = bot + inset
    pts = []
    for fx, fy in reversed(PROFILE[1:]):
        pts.append((-hb * fx * flare, bot + (sheer - bot) * fy, z))
    pts.append((0.0, bot, z))
    for fx, fy in PROFILE[1:]:
        pts.append((hb * fx * flare, bot + (sheer - bot) * fy, z))
    return pts


def shell_parts():
    wood = common.mat("boatWood")
    rows = [section(s) for s in STATIONS]
    n = len(rows[0])
    verts = [rb(*p) for row in rows for p in row]
    faces = []
    for i in range(len(rows) - 1):
        for k in range(n - 1):
            faces.append((i * n + k, i * n + k + 1, (i + 1) * n + k + 1, (i + 1) * n + k))
    faces.append(tuple(range(n)))  # the transom closes the stern
    shell = dwb.mesh_object("Planking", verts, faces, wood)
    dwb.solidify(shell, T, offset=-1.0)

    # Clinker strakes: three lapped plank edges a side, raised ribbons along the hull.
    for side in (-1, 1):
        for fy_i, k in enumerate((2, 3, 4)):
            pts, radii = [], []
            for s in STATIONS[:-1]:
                p = section(s)[n // 2 + side * k]
                pts.append((p[0] + side * 0.05, p[1], p[2]))
                radii.append(0.09)
            dwb.tube(f"Strake{side}{fy_i}", pts, radii, wood, verts=4)
    # A stem post up the bow and a transom cap board.
    dwb.tube("Stem", [(0, -0.05, -8.4), (0, 0.6, -9.1), (0, 1.6, -9.35), (0, 2.6, -9.4)], [0.16, 0.16, 0.15, 0.14], wood, verts=6)
    dwb.rbox((4.3, 0.32, 0.3), (0, 0.9, 6.3), wood, "TransomBrace")


def build_shell():
    shell_parts()
    return common.finish(
        "BoatShell",
        "Boat: SidePort, SideStarboard, Transom, BowPort, BowStarboard, BowFloor, Hull (made see-through, still collide)",
        "No vertex colours: the game sets MeshPart.Color from the boat paint (Cosmetics).",
        view=(140, 24),
        vertex_colors=False,
    )


def interior_parts():
    trim = common.mat("boatTrim")
    inside = common.mat("boatInside")
    seat = common.mat("seat")
    metal = common.mat("metal")
    light = common.mat("boatWoodLight")
    n = len(section(STATIONS[0]))

    # Gunwale caps: a rail on each sheer, wrapping the bow and the transom top.
    for side in (-1, 1):
        pts = []
        for s in STATIONS[:-1]:
            p = section(s)[0 if side < 0 else n - 1]
            pts.append((p[0] - side * 0.08, p[1] + 0.08, p[2]))
        tip = STATIONS[-1]
        pts.append((0, tip[2] + 0.08, tip[0] + 0.1))
        dwb.tube(f"Gunwale{side}", pts, [0.2] * len(pts), trim, verts=4)
    dwb.rbox((5.0, 0.3, 0.55), (0, 1.98, 6.15), trim, "TransomCap")
    # Breasthook: the bow's triangular deck piece.
    dwb.mesh_object(
        "Breasthook",
        [rb(-0.9, 2.08, -7.7), rb(0.9, 2.08, -7.7), rb(0, 2.32, -9.0), rb(-0.9, 2.3, -7.7), rb(0.9, 2.3, -7.7), rb(0, 2.54, -9.0)],
        [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)],
        trim,
    )

    # Keel under the centreline, following the bottom.
    keel = [(0, s[3] - 0.16, s[0]) for s in STATIONS[1:-1]]
    keel.insert(0, (0, STATIONS[0][3] - 0.12, 6.0))
    dwb.tube("Keel", keel, [0.22] * len(keel), trim, verts=4)

    # Ribs: U-shaped frames on the inside of the planking.
    for i, s in enumerate(STATIONS[1:-2]):
        pts = section(s, inset=T + 0.06)
        dwb.tube(f"Rib{i}", pts[1:-1], [0.08] * (len(pts) - 2), inside, verts=4)

    # Floorboards: three slats down the middle.
    for x in (-0.95, 0.0, 0.95):
        dwb.rbox((0.78, 0.12, 10.2), (x, 0.0, -0.4), light if x == 0 else inside, f"Floor{x}")

    # Thwarts: plank tops at y = 1.15 (the Seat parts' tops), knees and a post under each.
    for z, w in ((4.4, 4.9), (-1.4, 5.0), (-5.2, 4.2)):
        dwb.rbox((w, 0.3, 1.45), (0, 1.0, z), seat, f"Thwart{z}")
        dwb.rbox((0.32, 0.85, 0.32), (0, 0.45, z), trim, f"ThwartPost{z}")
        for side in (-1, 1):
            dwb.rbox((0.3, 0.55, 1.1), (side * (w / 2 - 0.2), 0.58, z), trim, f"Knee{z}{side}")

    # Oarlocks on the gunwales by the middle thwart.
    for side in (-1, 1):
        x = side * 2.72
        dwb.rbox((0.12, 0.42, 0.12), (x, 2.18, -0.95), metal, f"OarlockA{side}")
        dwb.rbox((0.12, 0.42, 0.12), (x, 2.18, -1.45), metal, f"OarlockB{side}")
        dwb.rbox((0.14, 0.12, 0.62), (x, 1.98, -1.2), metal, f"OarlockBase{side}")
    # A bow ring for the mooring line.
    ring = dwb.tube(
        "BowRing",
        [(0, 1.62 + 0.28 * math.sin(a), -9.52 - 0.28 * math.cos(a)) for a in [i * math.pi / 4 for i in range(9)]],
        [0.05] * 9,
        metal,
        verts=4,
    )
    ring.name = "BowRing"


def build_interior():
    interior_parts()
    return common.finish(
        "BoatInterior",
        "Boat: GunwalePort, GunwaleStarboard, Keel, ThwartStern, ThwartMid, ThwartBow and the four Seat parts (made see-through)",
        "Thwart tops at y = 1.15 so seated characters sit on them.",
        view=(150, 38),
    )


def build():
    build_shell()
    common.reset()
    build_interior()
    common.reset()
    shell_parts()
    interior_parts()
    import lantern

    lantern.lantern_parts()
    common.preview_only("Boat", view=(145, 32))


if __name__ == "__main__":
    common.main_guard(build)
