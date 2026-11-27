"""Dead shoreline trees: pale bare trunks with crooked, forked branches, a broken top and a
root flare. Two variants (DeadTreeA, DeadTreeB), each 40 studs tall with the trunk base at
the origin; the game scales one per dead tree in Shore.luau to that tree's height and turns
it to a random yaw.

    blender -b -P tools/blender/dead_trees.py
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import dwb  # noqa: E402

H = 40.0


def lean(yaw, tilt):
    s = math.sin(tilt)
    return (s * math.cos(yaw), math.cos(tilt), s * math.sin(yaw))


def add(a, d, k):
    return (a[0] + d[0] * k, a[1] + d[1] * k, a[2] + d[2] * k)


def branch(name, start, yaw, tilt, length, r0, rng, mats, depth=0):
    """A crooked branch in 3 segments; may fork once at its middle."""
    pts, radii = [start], [r0]
    p = start
    for i in range(3):
        yaw += rng.uniform(-0.5, 0.5)
        tilt = min(max(tilt + rng.uniform(-0.25, 0.2), 0.2), 1.45)
        p = add(p, lean(yaw, tilt), length / 3)
        pts.append(p)
        radii.append(r0 * (1 - 0.3 * (i + 1)))
    radii[-1] = max(radii[-1], 0.06)
    dwb.tube(name, pts, radii, mats[depth % 2], verts=5)
    if depth == 0 and rng.random() < 0.75:
        mid = pts[2]
        branch(name + "F", mid, yaw + rng.choice((-1, 1)) * rng.uniform(0.6, 1.1), tilt * 0.8, length * 0.55, r0 * 0.45, rng, mats, 1)


def tree(seed, name):
    rng = random.Random(seed)
    wood = common.mat("deadWood")
    light = common.mat("deadWoodLight")
    mats = (wood, light)
    # Trunk: four crooked segments, tapering, a broken top.
    yaw = rng.uniform(0, math.tau)
    pts = [(0.0, -0.6, 0.0)]
    radii = [1.25]
    p = (0.0, 0.0, 0.0)
    segs = [0.3, 0.27, 0.23, 0.14]
    for i, f in enumerate(segs):
        yaw += rng.uniform(-1.6, 1.6)
        p = add(p, lean(yaw, math.radians(rng.uniform(3, 11))), H * f)
        pts.append(p)
        radii.append(1.1 * (1 - 0.2 * (i + 1)))
    dwb.tube("Trunk", pts, radii, wood, verts=7)
    # Broken top: a jagged stub.
    top = pts[-1]
    dwb.tube("Snag", [top, add(top, lean(yaw + 1.0, 0.5), 1.6)], [radii[-1] * 0.9, 0.08], light, verts=5)
    # Root flare.
    for k in range(5):
        a = k * math.tau / 5 + rng.uniform(-0.3, 0.3)
        dwb.tube(f"Root{k}", [(0, 1.3, 0), (math.cos(a) * 1.6, 0.25, math.sin(a) * 1.6), (math.cos(a) * 2.6, -0.4, math.sin(a) * 2.6)], [0.55, 0.35, 0.12], wood, verts=5)
    # Branches from the upper two thirds, angled up and out, all around.
    n = rng.randint(5, 6)
    for k in range(n):
        t = 0.35 + 0.55 * k / (n - 1)
        seg = min(int(t * 4), 3)
        u = t * 4 - seg
        a, b = pts[seg], pts[seg + 1]
        start = add(a, (b[0] - a[0], b[1] - a[1], b[2] - a[2]), u)
        by = k * 2.4 + rng.uniform(-0.4, 0.4)
        branch(f"Branch{k}", start, by, math.radians(rng.uniform(35, 70)), H * rng.uniform(0.16, 0.28) * (1.15 - 0.5 * t), 0.42 * (1.2 - t), rng, mats)
    common.finish(
        name,
        "Shore dead trees (Tree*Dead: Trunk, TrunkTop, Branch*), made see-through; one mesh per tree, scaled to its height",
        "40 studs tall, base at the origin.",
        view=(30, 14),
    )


def build():
    tree(7, "DeadTreeA")
    common.reset()
    tree(23, "DeadTreeB")


if __name__ == "__main__":
    common.main_guard(build)
