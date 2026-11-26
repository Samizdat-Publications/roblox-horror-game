"""The house palette for every in-game model: flat sRGB colours (0 to 255), chunky low-poly
shapes, vertex-coloured, readable on a phone. Every new model script imports this so the
whole game keeps one look (see art/README.md, "House style").

Add a colour here before using it in a model; don't hard-code new colours in a script.
Fish colours come from FishData.luau (each species' `color`), so the journal, the catch on
the line and the fish models agree.
"""

# The house palette: flat colours, readable on a phone.
PALETTE = {
    "wood": (124, 92, 60),
    "darkWood": (88, 62, 40),
    "plank": (150, 112, 72),
    "rope": (196, 170, 120),
    "stone": (140, 140, 135),
    "darkStone": (105, 105, 102),
    "moss": (90, 120, 60),
    "leaf": (70, 130, 55),
    "pine": (45, 95, 50),
    "bark": (95, 70, 50),
    "sell": (230, 180, 60),
    "shop": (90, 160, 220),
    "white": (235, 235, 230),
    "red": (220, 60, 50),
    "lamp": (255, 230, 170),
    "metal": (60, 62, 70),
    "reed": (120, 140, 70),
    "lily": (70, 140, 70),
    "pinkFlower": (235, 150, 180),
    "tub": (70, 100, 150),
    "worm": (190, 110, 110),
}
