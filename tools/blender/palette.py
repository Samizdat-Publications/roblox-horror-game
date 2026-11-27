"""The Don't Wave Back palette for the hero models: flat sRGB colours (0 to 255). The first
block is copied from src/shared/Look.luau (Look.Palette) so a hero model sits in the same
tones as the part-built world it covers; docs/DESIGN.md "Look" is the source of the named
colours. Add a colour here before using it in a model; don't hard-code colours in a script.
"""

PALETTE = {
    # DESIGN.md
    "silhouette": (5, 6, 7),
    "pinEyes": (232, 244, 255),
    "lantern": (255, 180, 90),
    # Look.Palette world materials
    "trunk": (18, 16, 14),
    "dockWood": (58, 48, 38),
    "dockPost": (34, 29, 24),
    "shackWall": (44, 40, 34),
    "shackRoof": (28, 26, 24),
    "stone": (52, 54, 52),
    "spire": (30, 33, 34),
    "bell": (70, 60, 38),
    "boatWood": (82, 64, 46),
    "boatTrim": (52, 40, 30),
    "seat": (70, 56, 40),
    "metal": (46, 46, 44),
    # Hero-model shades (M9): small steps off the colours above, so planks, courses and
    # weathering read as separate pieces under the lantern without leaving the palette.
    "boatWoodLight": (94, 74, 54),
    "boatWoodDark": (66, 51, 37),
    "boatInside": (60, 47, 34),
    "stoneLight": (62, 64, 61),
    "stoneDark": (42, 44, 42),
    "moss": (34, 42, 30),
    "shackWallLight": (52, 47, 40),
    "deadWood": (30, 29, 27),
    "deadWoodLight": (40, 39, 36),
    "rust": (60, 40, 30),
    "glassDark": (20, 18, 14),
    "paperFaded": (150, 140, 118),
}
