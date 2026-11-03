#!/usr/bin/env python3
"""Generate the D02 café date background art for Leila-chan.

Output:
    game/assets/bg/cafe.png (384x688, pixel art, strictly within palette.json)

Deterministic: running twice produces identical bytes.
"""

from __future__ import annotations

import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PALETTE_PATH = ROOT / "game" / "assets" / "sprites" / "leila" / "palette.json"
OUTPUT_PATH = ROOT / "game" / "assets" / "bg" / "cafe.png"

W, H = 384, 688


def load_palette() -> dict[str, tuple[int, int, int]]:
    pal_data = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    colors = {}
    for group, hexes in pal_data.items():
        for h in hexes:
            h_clean = h.lower().strip()
            r = int(h_clean[0:2], 16)
            g = int(h_clean[2:4], 16)
            b = int(h_clean[4:6], 16)
            colors[h_clean] = (r, g, b)
    return colors


def build_cafe_image() -> Image.Image:
    canvas = np.zeros((H, W, 3), dtype=np.uint8)

    # Palette colors (strictly from palette.json)
    C_BLACK = (7, 4, 10)         # 07040a line
    C_DARKEST = (11, 8, 12)       # 0b080c hair
    C_NIGHT_1 = (21, 16, 23)      # 151017 hair
    C_NIGHT_2 = (31, 21, 29)      # 1f151d hair
    C_NIGHT_3 = (44, 24, 32)      # 2c1820 hair
    C_NIGHT_4 = (68, 25, 42)      # 44192a hair

    C_WOOD_DARK = (36, 18, 26)    # 24121a shade
    C_WOOD_MID = (58, 34, 40)     # 3a2228 shade
    C_WOOD_WARM = (85, 54, 64)    # 553640 shade
    C_WOOD_LIGHT = (114, 80, 90)  # 72505a shade

    C_WALL_DARK = (58, 34, 40)    # 3a2228 shade
    C_WALL_MID = (85, 54, 64)     # 553640 shade
    C_WALL_LIGHT = (110, 90, 104) # 6e5a68 pale
    C_WALL_PALE = (148, 128, 142) # 94808e pale

    C_WINE_DEEP = (29, 5, 9)      # 1d0509 dress
    C_WINE_DARK = (51, 10, 18)    # 330a12 dress
    C_WINE_MID = (77, 15, 26)     # 4d0f1a dress
    C_WINE_LIGHT = (108, 21, 34)  # 6c1522 dress
    C_WINE_BRIGHT = (143, 31, 44) # 8f1f2c dress
    C_WINE_HIGHLIGHT = (179, 49, 58) # b3313a dress

    C_STEEL_DARK = (28, 28, 34)   # 1c1c22 steel
    C_STEEL_MID = (58, 58, 68)    # 3a3a44 steel
    C_STEEL_LIGHT = (106, 106, 120) # 6a6a78 steel
    C_STEEL_BRIGHT = (168, 168, 184) # a8a8b8 steel
    C_STEEL_WHITE = (232, 232, 240)  # e8e8f0 steel

    C_CERAMIC_WHITE = (230, 214, 220) # e6d6dc white
    C_CERAMIC_SHADE = (185, 167, 176) # b9a7b0 white
    C_CREAM = (251, 233, 224)         # fbe9e0 white

    C_SKIN_PEACH = (239, 210, 198)    # efd2c6 skin
    C_CORAL_GLOW = (255, 122, 110)    # ff7a6e eye
    C_CYAN_GLOW = (127, 216, 224)     # 7fd8e0 fx
    C_RED_ACCENT = (216, 50, 58)      # d8323a eye

    def rect(x: int, y: int, w: int, h: int, col: tuple[int, int, int]) -> None:
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(W, x + w), min(H, y + h)
        if x1 > x0 and y1 > y0:
            canvas[y0:y1, x0:x1] = col

    def hline(y: int, x0: int, x1: int, col: tuple[int, int, int]) -> None:
        if 0 <= y < H:
            xa, xb = max(0, min(x0, x1)), min(W, max(x0, x1) + 1)
            if xb > xa:
                canvas[y, xa:xb] = col

    def vline(x: int, y0: int, y1: int, col: tuple[int, int, int]) -> None:
        if 0 <= x < W:
            ya, yb = max(0, min(y0, y1)), min(H, max(y0, y1) + 1)
            if yb > ya:
                canvas[ya:yb, x] = col

    def dither_rect(x: int, y: int, w: int, h: int, c1: tuple[int, int, int], c2: tuple[int, int, int], step: int = 2) -> None:
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(W, x + w), min(H, y + h)
        for cy in range(y0, y1):
            for cx in range(x0, x1):
                if ((cx + cy) // step) % 2 == 0:
                    canvas[cy, cx] = c1
                else:
                    canvas[cy, cx] = c2

    # 1. Base Wall (Warm textured café wall)
    rect(0, 0, W, H, C_WALL_MID)
    # Subtle horizontal wallpaper / brick bands
    for y in range(40, 360, 16):
        hline(y, 0, W - 1, C_WALL_DARK)
        hline(y + 1, 0, W - 1, C_WOOD_DARK)
        # Vertical brick mortar accents
        offset = 0 if (y // 16) % 2 == 0 else 16
        for x in range(offset, W, 32):
            vline(x, y + 2, y + 15, C_WALL_DARK)

    # 2. Ceiling & Beams (y: 0 to 45)
    rect(0, 0, W, 24, C_WOOD_DARK)
    for x in range(0, W, 48):
        rect(x, 0, 44, 20, C_NIGHT_3)
        vline(x, 0, 20, C_WOOD_LIGHT)
        vline(x + 43, 0, 20, C_BLACK)
    # Main horizontal crossbeam
    rect(0, 22, W, 14, C_WOOD_MID)
    hline(22, 0, W - 1, C_WOOD_LIGHT)
    hline(35, 0, W - 1, C_BLACK)
    hline(36, 0, W - 1, C_WOOD_DARK)

    # 3. Café Window (x: 20 to 160, y: 55 to 330)
    # Outer frame
    rect(18, 53, 146, 276, C_BLACK)
    rect(20, 55, 142, 272, C_STEEL_DARK)
    # Night sky inside window
    rect(24, 59, 134, 264, C_DARKEST)
    for ny in range(120, 320, 20):
        # Gradual atmospheric night bands
        col = C_NIGHT_1 if ny < 180 else (C_NIGHT_2 if ny < 240 else C_NIGHT_3)
        rect(24, ny, 134, 20, col)

    # Distant city skyline silhouette outside window
    skyline = [
        (24, 240, 14, 80), (38, 220, 18, 100), (56, 250, 16, 70),
        (72, 210, 22, 110), (94, 230, 20, 90), (114, 245, 18, 75),
        (132, 225, 26, 95)
    ]
    for sx, sy, sw, sh in skyline:
        rect(sx, sy, sw, sh, C_NIGHT_4)
        vline(sx, sy, sy + sh, C_NIGHT_3)
        # Distant warm windows in buildings
        for wy in range(sy + 8, sy + sh - 8, 12):
            for wx in range(sx + 3, sx + sw - 4, 6):
                col_w = C_CORAL_GLOW if (wx + wy) % 5 == 0 else C_CERAMIC_SHADE
                rect(wx, wy, 2, 3, col_w)

    # Stars & soft moon in window sky
    stars = [(42, 75), (78, 68), (110, 85), (135, 72), (65, 105), (120, 115), (92, 90)]
    for stx, sty in stars:
        rect(stx, sty, 2, 2, C_CREAM)
    # Crescent moon
    rect(128, 66, 8, 8, C_CREAM)
    rect(126, 64, 7, 7, C_DARKEST)

    # Window Mullions / Panes (cross bars)
    rect(90, 55, 4, 268, C_STEEL_MID)
    vline(90, 55, 323, C_STEEL_LIGHT)
    vline(93, 55, 323, C_BLACK)
    rect(24, 140, 134, 4, C_STEEL_MID)
    hline(140, 24, 157, C_STEEL_LIGHT)
    hline(143, 24, 157, C_BLACK)
    rect(24, 225, 134, 4, C_STEEL_MID)
    hline(225, 24, 157, C_STEEL_LIGHT)
    hline(228, 24, 157, C_BLACK)

    # Wooden Window Sill (y: 323 to 335)
    rect(14, 323, 154, 12, C_WOOD_MID)
    hline(323, 14, 167, C_WOOD_LIGHT)
    hline(324, 14, 167, C_WOOD_WARM)
    hline(334, 14, 167, C_BLACK)

    # Velvet Window Curtains (left and right drapes)
    # Left drape
    rect(14, 50, 18, 275, C_WINE_MID)
    rect(14, 50, 8, 275, C_WINE_DARK)
    for cy in range(50, 325, 8):
        hline(cy, 18, 30, C_WINE_LIGHT)
        hline(cy + 4, 22, 32, C_WINE_BRIGHT)
    # Right drape
    rect(148, 50, 20, 275, C_WINE_MID)
    rect(160, 50, 8, 275, C_WINE_DARK)
    for cy in range(50, 325, 8):
        hline(cy, 150, 164, C_WINE_LIGHT)
        hline(cy + 4, 152, 166, C_WINE_BRIGHT)
    # Curtain tie-backs
    rect(16, 215, 16, 5, C_CREAM)
    rect(148, 215, 16, 5, C_CREAM)

    # 4. Right Wall Décor (Chalkboard Menu, Shelves, Clock)
    # Wall clock at x: 178, y: 62
    rect(176, 60, 16, 16, C_STEEL_MID)
    rect(178, 62, 12, 12, C_CREAM)
    rect(183, 65, 2, 4, C_BLACK)
    rect(183, 67, 4, 2, C_BLACK)

    # Chalkboard Menu (x: 202 to 348, y: 62 to 170)
    rect(200, 60, 150, 112, C_BLACK)
    rect(202, 62, 146, 108, C_WOOD_DARK)
    rect(206, 66, 138, 100, C_STEEL_DARK)
    # Chalkboard header
    rect(240, 72, 70, 3, C_CERAMIC_WHITE)
    # Chalk text simulated rows
    menu_lines = [
        (216, 82, 118), (216, 92, 105), (216, 102, 112),
        (216, 114, 98), (216, 124, 115), (216, 134, 108), (216, 144, 95)
    ]
    for lx, ly, lw in menu_lines:
        for seg in range(lx, lx + lw, 6):
            rect(seg, ly, 4, 2, C_CERAMIC_SHADE)
        # Price dot
        rect(lx + lw + 6, ly, 4, 2, C_CREAM)
    # Cute chalk heart doodle on menu
    rect(320, 70, 3, 3, C_CORAL_GLOW)
    rect(324, 70, 3, 3, C_CORAL_GLOW)
    rect(319, 73, 9, 3, C_CORAL_GLOW)
    rect(321, 76, 5, 3, C_CORAL_GLOW)
    rect(323, 79, 1, 2, C_CORAL_GLOW)

    # Shelf 1 (y: 185 to 192)
    rect(190, 185, 168, 7, C_WOOD_MID)
    hline(185, 190, 357, C_WOOD_LIGHT)
    hline(191, 190, 357, C_BLACK)
    # Shelf 1 Brackets
    rect(205, 192, 4, 8, C_STEEL_MID)
    rect(340, 192, 4, 8, C_STEEL_MID)
    # Items on Shelf 1: Canisters & jars
    rect(212, 165, 14, 20, C_WINE_DARK)
    rect(214, 162, 10, 3, C_STEEL_BRIGHT)
    rect(232, 168, 12, 17, C_STEEL_DARK)
    rect(234, 165, 8, 3, C_WOOD_LIGHT)
    # Coffee cups stacked
    rect(252, 174, 14, 11, C_CERAMIC_WHITE)
    rect(253, 166, 12, 8, C_CERAMIC_WHITE)
    rect(254, 159, 10, 7, C_CERAMIC_SHADE)
    # Syrup bottles
    rect(280, 160, 8, 25, C_WINE_MID)
    rect(282, 154, 4, 6, C_STEEL_LIGHT)
    rect(294, 158, 8, 27, C_WOOD_WARM)
    rect(296, 152, 4, 6, C_STEEL_LIGHT)
    # Potted Plant on right shelf
    rect(320, 170, 16, 15, C_WOOD_DARK)
    rect(318, 168, 20, 3, C_WOOD_LIGHT)
    # Green/purple trailing ivy leaves
    ivy_pts = [
        (322, 162), (328, 158), (334, 163), (324, 155),
        (316, 175), (314, 184), (312, 194), (310, 204),
        (338, 174), (340, 185), (342, 195)
    ]
    for ix, iy in ivy_pts:
        rect(ix, iy, 4, 4, C_WOOD_LIGHT)
        rect(ix + 1, iy + 1, 2, 2, C_WINE_LIGHT)

    # Shelf 2 (y: 250 to 257)
    rect(190, 250, 168, 7, C_WOOD_MID)
    hline(250, 190, 357, C_WOOD_LIGHT)
    hline(256, 190, 357, C_BLACK)
    # Shelf 2 Brackets
    rect(205, 257, 4, 8, C_STEEL_MID)
    rect(340, 257, 4, 8, C_STEEL_MID)
    # Items on Shelf 2: Glassware, small teapot, recipe books
    # Books lined up
    book_cols = [C_WINE_MID, C_WINE_DARK, C_STEEL_MID, C_WOOD_WARM, C_WINE_LIGHT]
    for b_idx, b_col in enumerate(book_cols):
        rect(210 + b_idx * 5, 230, 4, 20, b_col)
        hline(230, 210 + b_idx * 5, 213 + b_idx * 5, C_CREAM)
    # Ceramic teapot
    rect(260, 234, 20, 16, C_CERAMIC_WHITE)
    rect(256, 238, 4, 8, C_CERAMIC_SHADE)  # handle
    rect(280, 236, 4, 5, C_CERAMIC_SHADE)  # spout
    rect(265, 231, 10, 3, C_WOOD_LIGHT)    # lid knob
    # Glass tumblers
    rect(300, 236, 10, 14, C_STEEL_BRIGHT)
    rect(302, 238, 6, 10, C_CYAN_GLOW)
    rect(316, 236, 10, 14, C_STEEL_BRIGHT)
    rect(318, 238, 6, 10, C_CYAN_GLOW)

    # 5. Hanging Pendant Lamps (x: 88 and x: 278)
    lamps = [(88, 38), (278, 38)]
    for lx, ly in lamps:
        # Thin cord from ceiling
        vline(lx + 7, 0, ly, C_STEEL_DARK)
        # Fixture socket
        rect(lx + 5, ly, 5, 4, C_STEEL_MID)
        # Conical shade
        rect(lx + 1, ly + 4, 13, 8, C_STEEL_LIGHT)
        rect(lx - 4, ly + 10, 23, 5, C_STEEL_BRIGHT)
        hline(ly + 10, lx - 4, lx + 18, C_STEEL_WHITE)
        hline(ly + 14, lx - 4, lx + 18, C_BLACK)
        # Glowing bulb
        rect(lx + 4, ly + 14, 7, 6, C_CREAM)
        rect(lx + 5, ly + 15, 5, 4, C_CORAL_GLOW)
        # Soft ambient light cone steps downward
        dither_rect(lx - 24, ly + 20, 63, 60, C_WALL_MID, C_WALL_LIGHT, step=3)

    # 6. Wainscoting Divider Rail (y: 335 to 345)
    rect(0, 335, W, 10, C_WOOD_MID)
    hline(335, 0, W - 1, C_WOOD_LIGHT)
    hline(336, 0, W - 1, C_WOOD_WARM)
    hline(344, 0, W - 1, C_BLACK)
    hline(345, 0, W - 1, C_WOOD_DARK)

    # Wainscoting vertical panels (y: 345 to 450)
    rect(0, 345, W, 110, C_WOOD_MID)
    for px in range(0, W, 24):
        rect(px + 2, 350, 20, 100, C_WOOD_WARM)
        rect(px + 4, 352, 16, 96, C_WOOD_MID)
        vline(px + 2, 350, 449, C_WOOD_LIGHT)
        hline(350, px + 2, px + 21, C_WOOD_LIGHT)
        vline(px + 21, 350, 449, C_WOOD_DARK)
        hline(449, px + 2, px + 21, C_WOOD_DARK)

    # 7. Café Booth Backrest (Where Leila sits, x: 36 to 348, y: 385 to 540)
    # Rich wine-red tufted velvet booth
    rect(34, 383, 316, 157, C_BLACK)
    rect(36, 385, 312, 153, C_WINE_DARK)
    # Top padded head roll
    rect(36, 385, 312, 22, C_WINE_LIGHT)
    hline(385, 36, 347, C_WINE_BRIGHT)
    hline(386, 36, 347, C_WINE_HIGHLIGHT)
    hline(406, 36, 347, C_WINE_DEEP)

    # Diamond tufting grid
    rect(38, 408, 308, 130, C_WINE_MID)
    for by in range(416, 530, 22):
        row = (by - 416) // 22
        x_shift = 14 if row % 2 == 1 else 0
        for bx in range(48 + x_shift, 336, 28):
            # Button indent
            rect(bx, by, 3, 3, C_WINE_DEEP)
            rect(bx + 1, by + 1, 1, 1, C_BLACK)
            # Cushion creases radiating from buttons
            hline(by - 2, bx - 4, bx + 6, C_WINE_LIGHT)
            vline(bx + 1, by - 4, by + 6, C_WINE_DARK)

    # Booth wooden side wings / pillars (framing the booth)
    # Left pillar
    rect(0, 0, 24, H, C_WOOD_DARK)
    rect(2, 0, 18, H, C_WOOD_MID)
    vline(2, 0, H - 1, C_WOOD_LIGHT)
    vline(19, 0, H - 1, C_BLACK)
    # Right pillar
    rect(360, 0, 24, H, C_WOOD_DARK)
    rect(364, 0, 18, H, C_WOOD_MID)
    vline(364, 0, H - 1, C_WOOD_LIGHT)
    vline(381, 0, H - 1, C_BLACK)

    # 8. Hardwood Floor (visible at sides and behind table, y: 530 to 688)
    rect(24, 530, 336, 158, C_NIGHT_2)
    for fy in range(530, H, 18):
        hline(fy, 24, 359, C_NIGHT_1)
        f_shift = 20 if (fy // 18) % 2 == 1 else 0
        for fx in range(24 + f_shift, 360, 40):
            vline(fx, fy, min(H - 1, fy + 17), C_DARKEST)

    # 9. Foreground Date Table (The wooden café table where you and Leila sit)
    # Starts at y: 550, covers down to 688
    rect(24, 550, 336, 138, C_BLACK)
    # Table bevel rim (catches overhead light)
    rect(26, 552, 332, 6, C_WOOD_LIGHT)
    hline(552, 26, 357, C_CREAM)
    hline(553, 26, 357, C_WOOD_LIGHT)
    hline(557, 26, 357, C_WOOD_DARK)

    # Table Top Surface (rich polished mahogany wood planks)
    rect(26, 558, 332, 130, C_WOOD_MID)
    for py in range(570, H, 24):
        hline(py, 26, 357, C_WOOD_DARK)
        hline(py + 1, 26, 357, C_WOOD_WARM)
    # Wood grain texture accents
    for gx in range(40, 340, 36):
        dither_rect(gx, 565, 20, 115, C_WOOD_MID, C_WOOD_WARM, step=3)

    # Warm overhead reflection pools on table
    for rx in [90, 280]:
        rect(rx - 20, 562, 40, 18, C_WOOD_WARM)
        rect(rx - 10, 564, 20, 12, C_WOOD_LIGHT)
        rect(rx - 4, 566, 8, 6, C_WALL_PALE)

    # 10. Tabletop Objects (D02 Cafe specifics)
    # A. Her Drink (Left side, x: 86, y: 574): Sweet drink/Tea with steam
    # Ceramic Saucer
    rect(72, 594, 36, 6, C_CERAMIC_SHADE)
    rect(74, 592, 32, 4, C_CERAMIC_WHITE)
    hline(592, 76, 103, C_CREAM)
    hline(599, 74, 105, C_BLACK)
    # Ceramic Teacup
    rect(78, 576, 24, 18, C_CERAMIC_WHITE)
    rect(77, 578, 26, 14, C_CERAMIC_WHITE)
    # Cup handle
    rect(102, 580, 5, 8, C_CERAMIC_WHITE)
    rect(104, 582, 2, 4, C_WOOD_MID)
    # Sweet tea liquid inside
    rect(80, 577, 20, 4, C_WINE_LIGHT)
    rect(82, 578, 16, 2, C_CORAL_GLOW)
    # Gentle steam wisps rising up
    rect(88, 568, 2, 5, C_CERAMIC_SHADE)
    rect(90, 562, 2, 6, C_CREAM)
    rect(87, 556, 2, 6, C_CERAMIC_SHADE)
    rect(94, 566, 2, 5, C_CERAMIC_SHADE)
    rect(92, 560, 2, 6, C_CREAM)

    # B. Your Drink (Right side, x: 284, y: 574): Coffee cup
    # Ceramic Saucer
    rect(272, 594, 36, 6, C_CERAMIC_SHADE)
    rect(274, 592, 32, 4, C_CERAMIC_WHITE)
    hline(592, 276, 303, C_CREAM)
    hline(599, 274, 305, C_BLACK)
    # Coffee Mug
    rect(278, 576, 24, 18, C_CERAMIC_WHITE)
    rect(277, 578, 26, 14, C_CERAMIC_WHITE)
    # Mug handle
    rect(272, 580, 5, 8, C_CERAMIC_WHITE)
    rect(273, 582, 2, 4, C_WOOD_MID)
    # Black coffee inside
    rect(280, 577, 20, 4, C_WINE_DEEP)
    rect(282, 578, 16, 2, C_DARKEST)

    # C. Two Menus (D02: "Two menus sit between you") at center table (x: 148 to 232, y: 570 to 630)
    # First Menu (angled slightly left)
    rect(150, 574, 38, 52, C_BLACK)
    rect(152, 576, 34, 48, C_WINE_DARK)
    rect(154, 578, 30, 44, C_WINE_MID)
    # Gold embossed trim & crest
    rect(154, 578, 4, 4, C_CREAM)
    rect(180, 578, 4, 4, C_CREAM)
    rect(154, 618, 4, 4, C_CREAM)
    rect(180, 618, 4, 4, C_CREAM)
    rect(166, 592, 6, 8, C_CREAM)
    # Peeking menu pages
    rect(184, 580, 3, 40, C_CERAMIC_WHITE)

    # Second Menu (resting alongside / overlapping right)
    rect(186, 580, 38, 52, C_BLACK)
    rect(188, 582, 34, 48, C_WINE_LIGHT)
    rect(190, 584, 30, 44, C_WINE_BRIGHT)
    rect(190, 584, 4, 4, C_CREAM)
    rect(216, 584, 4, 4, C_CREAM)
    rect(190, 624, 4, 4, C_CREAM)
    rect(216, 624, 4, 4, C_CREAM)
    rect(202, 598, 6, 8, C_CREAM)
    rect(184, 584, 3, 40, C_CERAMIC_WHITE)

    # D. Small Glass Bud Vase with Flower (center, between drinks, behind menus)
    rect(188, 550, 8, 18, C_STEEL_LIGHT)
    rect(189, 552, 6, 14, C_CYAN_GLOW)
    # Flower stem
    vline(192, 538, 550, C_WOOD_LIGHT)
    # Flower bud / petals
    rect(189, 532, 7, 7, C_WINE_LIGHT)
    rect(190, 530, 5, 4, C_WINE_BRIGHT)
    rect(191, 533, 3, 3, C_CORAL_GLOW)

    return Image.fromarray(canvas, mode="RGB")


def main() -> None:
    pal = load_palette()
    allowed_rgbs = set(pal.values())

    img = build_cafe_image()
    arr = np.array(img)

    # Verify every pixel is in palette.json
    unique_colors = np.unique(arr.reshape(-1, 3), axis=0)
    off_palette = [tuple(c) for c in unique_colors if tuple(c) not in allowed_rgbs]

    if off_palette:
        print(f"Error: {len(off_palette)} off-palette colors detected!")
        for c in off_palette[:5]:
            print(f"  off: {c}")
        raise SystemExit(1)

    print(f"Verified: all {len(unique_colors)} colors in cafe.png are strictly in palette.json!")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT_PATH, format="PNG")
    print(f"Successfully generated {OUTPUT_PATH} ({W}x{H})")


if __name__ == "__main__":
    main()
