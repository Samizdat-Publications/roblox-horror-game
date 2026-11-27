"""The bait shack, in Dock.luau's shack frame: origin at the floor top centre, the lake side
(door and window) toward +z. Same box as the part-built shack (16 x 9 x 12, a 28 degree gable
roof along x): board-and-batten walls, corner posts, stilts, a sagging roof with roll-roofing
seams, a stovepipe, a ledged door with a Z brace, a window frame with a cross bar (the lit
Neon window part stays and shows through), and a painted BAIT board over the door.

    blender -b -P tools/blender/shack.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import dwb  # noqa: E402
from dwb import rb  # noqa: E402

SW, SD, SH = 16.0, 12.0, 9.0
WZ = SD / 2
PITCH = math.radians(28)
HALF = SD / 2 + 1
RISE = math.tan(PITCH) * HALF

# 3 x 5 pixel letters for the sign.
FONT = {
    "B": ["XX.", "X.X", "XX.", "X.X", "XX."],
    "A": [".X.", "X.X", "XXX", "X.X", "X.X"],
    "I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
    "T": ["XXX", ".X.", ".X.", ".X.", ".X."],
}


def wall_x(name, x0, x1, y0, y1, z, mats, battens=True):
    """A north or south wall piece between x0..x1, y0..y1 at depth z, with battens."""
    wall, batten = mats
    dwb.rbox((x1 - x0, y1 - y0, 0.6), ((x0 + x1) / 2, (y0 + y1) / 2, z), wall, name)
    if battens:
        x = x0 + 0.6
        out = 0.36 if z > 0 else -0.36
        while x < x1 - 0.3:
            dwb.rbox((0.22, y1 - y0, 0.14), (x, (y0 + y1) / 2, z + out), batten, f"{name}B{x:.1f}")
            x += 1.3


def roof_slope(name, sign, mat):
    """One slope (sign +1 north, -1 south) as a sagging grid, solidified."""
    xs = [-SW / 2 - 1, -SW / 4, 0, SW / 4, SW / 2 + 1]
    sag = [0.0, 0.22, 0.34, 0.22, 0.0]
    verts = []
    for t in (0.0, 1.0):  # 0 at the ridge, 1 at the eave
        for x, s in zip(xs, sag):
            z = sign * HALF * t
            y = SH + RISE * (1 - t) + 0.3 - s * (1.0 if t == 0 else 0.6)
            verts.append(rb(x, y, z))
    n = len(xs)
    faces = [(k, k + 1, n + k + 1, n + k) for k in range(n - 1)]
    o = dwb.mesh_object(name, verts, faces, mat)
    dwb.solidify(o, 0.45, offset=1.0)
    # Roll-roofing seams across the slope.
    for x in (-6.0, -2.0, 2.0, 6.0):
        k = min(range(n), key=lambda i: abs(xs[i] - x))
        s = sag[k]
        a = (x, SH + RISE + 0.3 - s + 0.42, 0.0)
        b = (x, SH + 0.3 - s * 0.6 + 0.42, sign * HALF)
        dwb.tube(f"{name}Seam{x}", [a, b], [0.09, 0.09], mat, verts=4)


def build():
    wall = common.mat("shackWall")
    batten = common.mat("shackWallLight")
    roof = common.mat("shackRoof")
    post = common.mat("dockPost")
    metal = common.mat("metal")
    rust = common.mat("rust")
    paper = common.mat("paperFaded")
    mats = (wall, batten)

    # Floor deck and stilts down toward the water.
    dwb.rbox((SW + 0.4, 1, SD + 0.4), (0, -0.5, 0), post, "Floor")
    for x in (-SW / 2 + 0.5, 0, SW / 2 - 0.5):
        for z in (-WZ + 0.5, WZ - 0.5):
            dwb.rbox((0.7, 2.6, 0.7), (x, -2.2, z), post, f"Stilt{x}{z}")

    # South wall, east and west walls (battens on the outside).
    wall_x("WallSouth", -SW / 2, SW / 2, 0, SH, -WZ, mats)
    for side in (-1, 1):
        x = side * SW / 2
        dwb.rbox((0.6, SH, SD), (x, SH / 2, 0), wall, f"WallSide{side}")
        z = -WZ + 0.6
        while z < WZ - 0.3:
            dwb.rbox((0.14, SH, 0.22), (x + side * 0.36, SH / 2, z), batten, f"SideB{side}{z:.1f}")
            z += 1.3
        # Gable triangle.
        dwb.mesh_object(
            f"Gable{side}",
            [rb(x - 0.3, SH, -WZ), rb(x - 0.3, SH, WZ), rb(x - 0.3, SH + RISE * (WZ / HALF), 0), rb(x + 0.3, SH, -WZ), rb(x + 0.3, SH, WZ), rb(x + 0.3, SH + RISE * (WZ / HALF), 0)],
            [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)],
            wall,
        )
    # North wall around the door (x -5..-2, y 0..7) and the window (x 0..4, y 3.5..6.5).
    wall_x("WallNorthA", -SW / 2, -5, 0, SH, WZ, mats)
    wall_x("WallNorthB", -5, -2, 7, SH, WZ, mats, battens=False)
    wall_x("WallNorthC", -2, 0, 0, SH, WZ, mats)
    wall_x("WallNorthBelow", 0, 4, 0, 3.5, WZ, mats)
    wall_x("WallNorthAbove", 0, 4, 6.5, SH, WZ, mats, battens=False)
    wall_x("WallNorthD", 4, SW / 2, 0, SH, WZ, mats)
    # Corner posts.
    for x in (-SW / 2, SW / 2):
        for z in (-WZ, WZ):
            dwb.rbox((0.8, SH + 0.3, 0.8), (x, (SH + 0.3) / 2, z), post, f"Corner{x}{z}")

    # The door: vertical ledged planks with a Z brace, a latch, a little ajar-dark gap.
    for i, x in enumerate((-4.55, -3.85, -3.15, -2.45)):
        dwb.rbox((0.66, 6.9, 0.3), (x, 3.47, WZ + 0.12), post if i % 2 == 0 else wall, f"DoorPlank{i}")
    for y in (1.2, 5.8):
        dwb.rbox((2.9, 0.4, 0.16), (-3.5, y, WZ + 0.33), batten, f"DoorLedge{y}")
    dwb.rbox((0.35, 4.9, 0.16), (-3.5, 3.5, WZ + 0.33), batten, "DoorBrace", rot_z=math.atan2(4.6, 2.5) - math.pi / 2)
    dwb.rbox((0.4, 0.2, 0.2), (-2.4, 3.6, WZ + 0.45), metal, "Latch")
    # Window frame and cross bar around the lit window part (x 0..4, y 3.5..6.5).
    for y in (3.35, 6.65):
        dwb.rbox((4.6, 0.32, 0.4), (2, y, WZ + 0.2), batten, f"WinRail{y}")
    for x in (-0.15, 4.15):
        dwb.rbox((0.32, 3.6, 0.4), (x, 5, WZ + 0.2), batten, f"WinStile{x}")
    dwb.rbox((0.18, 3.0, 0.2), (2, 5, WZ + 0.18), post, "WinBarV")
    dwb.rbox((4.0, 0.18, 0.2), (2, 5, WZ + 0.18), post, "WinBarH")
    dwb.rbox((4.8, 0.3, 0.8), (2, 3.15, WZ + 0.45), batten, "WinSill")

    # Roof, ridge cap, fascia boards.
    roof_slope("RoofNorth", 1, roof)
    roof_slope("RoofSouth", -1, roof)
    dwb.tube("Ridge", [(-SW / 2 - 1.1, SH + RISE + 0.65, 0), (0, SH + RISE + 0.35, 0), (SW / 2 + 1.1, SH + RISE + 0.65, 0)], [0.3, 0.3, 0.3], roof, verts=4)
    # Stovepipe through the south slope, with a cap and a rust collar.
    sx, sz = 4.5, -3.0
    base_y = SH + RISE * (1 - abs(sz) / HALF)
    dwb.tube("Stovepipe", [(sx, base_y - 0.2, sz), (sx, base_y + 2.6, sz), (sx + 0.15, base_y + 3.4, sz)], [0.32, 0.32, 0.3], metal, verts=8)
    common.cyl(0.62, 0.12, rb(sx + 0.17, base_y + 3.65, sz), metal, "PipeCap", verts=8, radius2=0.2)
    common.cyl(0.5, 0.25, rb(sx, base_y + 0.15, sz), rust, "PipeCollar", verts=8)

    # Step and the painted sign over the door.
    dwb.rbox((4, 0.6, 2), (-3.5, -1.2, WZ + 1.3), post, "Step")
    dwb.rbox((5.4, 1.5, 0.25), (-3.5, 7.95, WZ + 0.45), post, "SignBoard")
    px = 0.19
    word = "BAIT"
    x0 = -3.5 - (len(word) * 4 - 1) * px / 2
    for li, ch in enumerate(word):
        for r, row in enumerate(FONT[ch]):
            for c, cell in enumerate(row):
                if cell == "X":
                    dwb.rbox((px, px, 0.1), (x0 + (li * 4 + c) * px + px / 2, 7.95 + (2 - r) * px, WZ + 0.6), paper, f"L{li}{r}{c}")
    common.finish(
        "Shack",
        "Dock Shack folder: Floor, Walls*, Door, Roof*, Gable*, Step (made see-through); Window, Shelf, ShackRadio, RadioDial, ShackLightHolder stay",
        "Origin of the authoring frame is the floor top centre; the lake side is +z.",
        view=(25, 18),
    )


if __name__ == "__main__":
    common.main_guard(build)
