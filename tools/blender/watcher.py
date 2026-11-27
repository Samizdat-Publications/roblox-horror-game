"""The Watcher on the Shore: too tall (13 studs) and too narrow (1.25 at the shoulders). In the
figure's root frame from client/fx/Common.figure: feet at the origin, facing -z. A long
narrow coat with a ragged hem, thin legs, arms that hang past the knees with long fingers, a
small elongated head. All silhouette black. The two pin eyes stay Neon parts at
(+-0.1375, 11.66, -0.35), so the head's front face sits just behind them at z = -0.3.

    blender -b -P tools/blender/watcher.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import dwb  # noqa: E402

H = 13.0


def squash_depth(o, k):
    """Flatten a part front to back (Roblox z = Blender -y) around its own centre."""
    ys = [v.co.y for v in o.data.vertices]
    mid = (min(ys) + max(ys)) / 2
    for v in o.data.vertices:
        v.co.y = mid + (v.co.y - mid) * k


def watcher_parts():
    black = common.mat("silhouette")
    # Legs: thin, a hair apart, the knees a touch back.
    for side in (-1, 1):
        x = side * 0.22
        dwb.tube(f"Leg{side}", [(x, 0.05, -0.05), (x, 2.9, 0.06), (x, 5.9, 0.0)], [0.15, 0.14, 0.19], black, verts=6)
        dwb.rbox((0.3, 0.14, 0.62), (x, 0.07, -0.18), black, f"Foot{side}")
    # The coat: shoulders to below the knee, narrow at the waist, a ragged hem.
    coat = dwb.tube(
        "Coat",
        [(0, 3.6, 0.02), (0, 5.2, 0.02), (0, 7.4, 0.0), (0, 9.6, 0.0), (0, 10.45, 0.0)],
        [0.5, 0.44, 0.38, 0.6, 0.62],
        black,
        verts=10,
    )
    squash_depth(coat, 0.62)
    # Ragged hem: drop every other bottom vertex.
    for i, v in enumerate(coat.data.vertices[:10]):
        if i % 2 == 0:
            v.co.z -= 0.45 + 0.15 * math.sin(i * 1.7)
    # Shoulders: a bony bar, a little hunched forward.
    dwb.tube("Shoulders", [(-0.66, 10.25, 0.02), (0, 10.5, -0.04), (0.66, 10.25, 0.02)], [0.16, 0.2, 0.16], black, verts=6)
    # Neck and head, the head a touch forward of the shoulders.
    dwb.tube("Neck", [(0, 10.4, 0.0), (0, 10.95, -0.02)], [0.13, 0.11], black, verts=6)
    dwb.rbox((0.58, 1.56, 0.6), (0, 11.5, 0.0), black, "Head", bevel=0.08)
    dwb.rbox((0.5, 0.3, 0.5), (0, 10.85, 0.02), black, "Jaw")
    # Arms: hang straight, past the knees, with three long fingers each.
    for side in (-1, 1):
        sx = side * 0.7
        dwb.tube(f"Arm{side}", [(sx, 10.25, 0.0), (sx + side * 0.06, 7.6, 0.03), (sx + side * 0.04, 4.75, -0.02)], [0.12, 0.1, 0.09], black, verts=6)
        for k, dz in enumerate((-0.09, 0.0, 0.09)):
            dwb.tube(
                f"Finger{side}{k}",
                [(sx + side * 0.04, 4.8, dz * 0.6), (sx + side * 0.05, 4.05, dz), (sx + side * 0.03, 3.35 + 0.08 * k, dz * 1.3)],
                [0.05, 0.04, 0.025],
                black,
                verts=4,
            )


def build():
    watcher_parts()
    common.finish(
        "Watcher",
        "client/fx/Watcher figure: Legs, Torso, Head, Arms (made see-through); the Neon pin eyes stay",
        "13 studs tall, 1.25 wide at the shoulders, feet at the model base.",
        view=(200, 12),
    )


def build_all():
    build()
    # A second preview with the game's pin eyes in place (they ship as Neon parts, not mesh).
    common.reset()
    watcher_parts()
    eye = common.mat("pinEyes", emit=6.0)
    for sx in (-1, 1):
        common.sphere(0.0875, dwb.rb(sx * 0.1375, 11.66, -0.35), eye, f"Eye{sx}", subdiv=2)
    common.preview_only("WatcherEyes", view=(180, 4))


if __name__ == "__main__":
    common.main_guard(build_all)
