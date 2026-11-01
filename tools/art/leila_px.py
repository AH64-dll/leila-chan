"""Leila pixel-art pipeline.

Source sprites (768x1376 anime renders) -> 192x344 hand-finishable pixel art in the Leila palette.

    python3 tools/art/leila_px.py <src_dir> <out_dir> [names...]

Stages: background removal -> scale/baseline normalisation -> line-preserving 4x4 downscale ->
region classification (hair / dress / blouse / skin / eye / clip / line) -> palette ramps ->
selective outlines -> cleanup. Hand-drawn patches (hands, faces, clip) are applied afterwards by patches.py.
"""
import json
import math
import os
import sys

import cv2
import numpy as np

SCALE = int(os.environ.get("LEILA_SCALE", "4"))   # 4: 192x344 (shown 4x); 2: 384x688 HD (shown 2x)
W, H = 768 // SCALE, 1376 // SCALE                 # native pixel-art size; the game canvas is 768x1376
FEET_Y = 1344 // SCALE   # baseline the shoe soles sit on
HEAD_TOP_Y = 48 // SCALE  # target top of hair for a standard-height pose

# ---------------------------------------------------------------- palette (hex, dark -> light)
RAMPS = {
    "hair":   ["0b080c", "151017", "1f151d", "2c1820", "44192a", "6b1f30"],   # black with a blood sheen
    "dress":  ["1d0509", "330a12", "4d0f1a", "6c1522", "8f1f2c", "b3313a"],   # crimson pinafore / bow / shoes
    "blouse": ["111014", "1b1a20", "26242c", "333039", "433f4a"],             # charcoal blouse / stockings
    "skin":   ["8a5f63", "b98b88", "dcb3aa", "efd2c6", "fbe9e0"],             # unchanged pale skin
    "eye":    ["2a0408", "5c0a12", "9b1420", "d8323a", "ff7a6e"],             # red irises
    "mouth":  ["4a1418", "7d2a2c", "b65252", "e08a84"],
    "shade":  ["24121a", "3a2228", "553640", "72505a"],                       # shadow cast over the face
    "white":  ["b9a7b0", "e6d6dc", "fbe9e0"],                                 # eye whites, teeth, catch-lights
    "pale":   ["6e5a68", "94808e", "b9a7b0", "d9c8cc", "ecdfdf"],             # horror pallor: drained, cooler skin
    "blush":  ["d99a98", "e8b0aa", "f2c6bc"],
    "line":   ["07040a"],
}
OUTLINE = "07040a"


def hx(c):
    return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.uint8)


# ---------------------------------------------------------------- 1. background
def remove_aura(rgb):
    """Sprite 30 has a baked magenta aura; the game draws auras as a shader, so paint it out."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV_FULL).astype(int)
    h = hsv[..., 0] * 360 // 256
    sat, val = hsv[..., 1], hsv[..., 2]
    tint = (h >= 285) & (h <= 345) & (sat >= 10)
    # only the glow around her: tinted/white pixels reachable from the canvas edge, not the purple
    # shadow on her face and neck, which her outline encloses
    open_ = (tint | ((sat < 25) & (val > 225))).astype(np.uint8)
    k, lab = cv2.connectedComponents(open_, connectivity=4)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    tint &= np.isin(lab, edge[edge > 0])
    out = rgb.copy()
    # pale tint = white fabric / canvas lit by the glow -> neutralise to grey of the same brightness
    pale = tint & (sat < 48) & (val > 175)
    out[pale] = val[pale, None].clip(0, 255).astype(np.uint8)
    # strong glow -> canvas
    glow = tint & ~pale & (val > 60)
    out[glow] = 255
    return out


def foreground_mask(rgb):
    """Flood the white canvas (and soft grey shadow patches) from the border."""
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV_FULL)
    s, v = hsv[..., 1].astype(int), hsv[..., 2].astype(int)
    bgish = ((s < 34) & (v > 222)).astype(np.uint8)          # canvas + light shadow blobs
    n, lab = cv2.connectedComponents(bgish, connectivity=4)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bg = np.isin(lab, border[border > 0])
    # floor shadow: greyish-lavender smudges below the shoes that touch the border region
    shadow = (s < 60) & (v > 185)
    n2, lab2 = cv2.connectedComponents((shadow & ~bg).astype(np.uint8), connectivity=8)
    h = rgb.shape[0]
    for i in range(1, n2):
        ys, xs = np.nonzero(lab2 == i)
        if ys.min() > h * 0.86 and len(ys) < 40000:
            bg[lab2 == i] = True
    # enclosed canvas holes (gap between the legs, between arm and waist): pure white, decent size
    pure = ((s < 7) & (v > 249)).astype(np.uint8)
    n4, lab4, st4, _ = cv2.connectedComponentsWithStats(pure, connectivity=4)
    for i in range(1, n4):
        if st4[i, cv2.CC_STAT_AREA] <= 700:
            continue
        x, y, w, hh = st4[i, :4]
        sl = (slice(max(0, y - 6), y + hh + 6), slice(max(0, x - 6), x + w + 6))
        comp = lab4[sl] == i
        ring = (cv2.dilate(comp.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0) & ~comp
        rv, rs = v[sl][ring].astype(int), s[sl][ring].astype(int)
        whiteish = ((rs < 30) & (rv > 170)).mean()
        if (rv < 175).mean() > 0.18 or whiteish < 0.75:   # a real gap is framed by line art / skin; a highlight by fabric
            bg[lab4 == i] = True
    # floor shadow: in the shoe band anything pale and unsaturated is shadow, not shoe
    h = rgb.shape[0]
    band = np.zeros_like(bg); band[int(h * 0.915):] = True
    bg |= band & (s < 70) & (v > 140)
    fg = ~bg
    # drop specks (emote symbols, stray marks): keep the largest component only
    n3, lab3, stats, _ = cv2.connectedComponentsWithStats(fg.astype(np.uint8), connectivity=8)
    if n3 > 1:
        big = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
        keep = stats[:, cv2.CC_STAT_AREA] > 0.02 * stats[big, cv2.CC_STAT_AREA]
        keep[0] = False
        fg = keep[lab3]
    fg = cv2.morphologyEx(fg.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0
    return fg


# ---------------------------------------------------------------- 2. classification (full res)
def classify(rgb, fg):
    global CUR_RGB
    CUR_RGB = rgb
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV_FULL).astype(int)
    h = hsv[..., 0] * 360 // 256
    s, v = hsv[..., 1], hsv[..., 2]
    cls = np.zeros(rgb.shape[:2], np.uint8)        # 0 = bg
    bluish = (h >= 205) & (h <= 290)
    warm = (h <= 40) | (h >= 300)
    line = fg & (v < 70)
    navy = fg & bluish & (s > 45) & (v < 128)
    hair = fg & bluish & (s > 38) & (v >= 128)
    white = fg & (s < 40) & (v >= 150) & ~warm | fg & (s < 22) & (v >= 150)
    skin = fg & warm & (s >= 12) & (v >= 150)
    clip_white = np.zeros_like(fg)
    clip = fg & (h >= 215) & (h <= 255) & (s > 150) & (v > 110)
    for m, c in [(clip, 8), (navy, 2), (hair, 1), (white, 3), (skin, 4), (line, 7)]:
        cls[m & (cls == 0)] = c
    rest = fg & (cls == 0)
    cls[rest & (v < 128)] = 7
    cls[rest & (v >= 128)] = 3
    mouth = fg & warm & (s > 95) & (v > 90) & (v < 235)
    cls = relabel_enclosed(cls, mouth)
    low = np.zeros_like(fg); low[int(fg.shape[0] * 0.45):] = True
    cand = (low & (cls == 3) & warm & (s >= 9)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(cand, connectivity=8)
    big = np.zeros(n, bool); big[1:] = st[1:, cv2.CC_STAT_AREA] >= 150
    cls[big[lab]] = 4
    if FACE_CLASSES:
        # a pale hand lying on a white sleeve (crossed arms): warm near-white next to the hand's skin is skin
        mid = np.zeros_like(fg); mid[int(fg.shape[0] * 0.18):int(fg.shape[0] * 0.62)] = True
        n, lab, st, _ = cv2.connectedComponentsWithStats((mid & (cls == 4)).astype(np.uint8), connectivity=8)
        grey = [i for i in range(1, n) if s[lab == i].mean() < 14]       # a sleeve highlight, not a hand
        cls[np.isin(lab, grey)] = 3
        hand = np.isin(lab, [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] >= 120 and i not in grey])
        near = cv2.dilate(hand.astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
        pale_skin = near & mid & (cls == 3) & warm & (s >= 5) & (v >= 170)
        grown = cv2.morphologyEx((hand | pale_skin).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)) > 0
        cls[grown & near & ((cls == 3) | (cls == 7) & (v >= 60))] = 4
        # the whole old logo clip is class 8, so the finish pass can replace it: every saturated logo-blue piece
        # near the biggest one (white lines split the star into pieces), plus its dark-blue rim, then the hull
        blue = fg & (h >= 215) & (h <= 255) & (s > 150) & (v > 110)
        blue[int(fg.shape[0] * 0.24):] = False
        k, fl, fst, fcent = cv2.connectedComponentsWithStats(blue.astype(np.uint8), connectivity=8)
        if k > 1:
            big = 1 + int(np.argmax(fst[1:, cv2.CC_STAT_AREA]))
            ids = [i for i in range(1, k) if fst[i, cv2.CC_STAT_AREA] >= 20
                   and np.hypot(*(fcent[i] - fcent[big])) < 75]
            core = np.isin(fl, ids)
            hullm = np.zeros(cls.shape, np.uint8)
            cv2.fillConvexPoly(hullm, cv2.convexHull(np.argwhere(core)[:, ::-1].astype(np.int32)), 1)
            reach = cv2.dilate(hullm, np.ones((15, 15), np.uint8)) > 0
            deep = fg & (h >= 200) & (h <= 262) & (s >= 130) & reach
            core |= deep
            hullm[:] = 0
            cv2.fillConvexPoly(hullm, cv2.convexHull(np.argwhere(core)[:, ::-1].astype(np.int32)), 1)
            cls[cls == 8] = 1
            cls[(hullm > 0) & fg & (cls != 4)] = 8
    return cls, v


def _neighbour_share(cls, comp, ring_px=3):
    ring = cv2.dilate(comp.astype(np.uint8), np.ones((2 * ring_px + 1,) * 2, np.uint8)) > 0
    ring &= ~comp
    vals = cls[ring]
    vals = vals[vals > 0]
    if len(vals) == 0:
        return {}
    u, c = np.unique(vals, return_counts=True)
    return dict(zip(u.tolist(), (c / c.sum()).tolist()))


def relabel_enclosed(cls, mouth):
    """Context rules: an island's meaning depends on what surrounds it."""
    # clip: white/hair islands touching the saturated clip blue belong to the clip
    clipm = cls == 8
    cls[clipm] = 1
    head = np.zeros_like(clipm); head[:int(cls.shape[0] * 0.22)] = True
    n, lab, stats, _ = cv2.connectedComponentsWithStats((clipm & head).astype(np.uint8), connectivity=8)
    clipm = np.zeros_like(clipm)
    if n > 1:
        clipm = lab == 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
        cls[clipm] = 8
    if clipm.any():
        ys, xs = np.nonzero(clipm)
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        box = np.zeros_like(clipm)
        box[max(0, y0 - 4):y1 + 5, max(0, x0 - 4):x1 + 5] = True
        cls[box & (cls == 3)] = 8
    rules = [
        # (class, max area, predicate(share) -> new class)
        (3, 60000, lambda sh: 4 if sh.get(4, 0) > 0.45 else None, 0.86),    # skin highlights (socks excluded below)
        (1, 30000, lambda sh: 3 if sh.get(3, 0) > 0.55 else None, 1.0),     # sleeve fold shading, not hair
        (1, 60000, lambda sh: 3, 1.0, 0.47),                                 # lavender shading below the waist = fabric
    ]
    if FACE_CLASSES:   # glossy white streaks inside the hair mass are hair highlights, not blouse
        rules.append((3, 40000, lambda sh: 1 if sh.get(1, 0) > 0.6 else None, 0.30))
    if FACE_CLASSES:
        top_rows = np.zeros_like(clipm); top_rows[:int(cls.shape[0] * 0.24)] = True
        cls[top_rows & (cls == 2)] = 1      # no dress up by the face: dark-saturated lines in the bangs are hair
    for c, max_area, rule, max_y, *min_y in rules:
        n, lab, stats, cent = cv2.connectedComponentsWithStats((cls == c).astype(np.uint8), connectivity=8)
        for i in range(1, n):
            if stats[i, cv2.CC_STAT_AREA] > max_area or cent[i][1] > max_y * cls.shape[0]:
                continue
            if min_y and cent[i][1] < min_y[0] * cls.shape[0]:
                continue
            if c == 3 and cent[i][1] > 0.62 * cls.shape[0] and stats[i, cv2.CC_STAT_HEIGHT] > 110:
                continue   # a tall white region low on the body is a sock, not a highlight
            x, y, w, hgt = stats[i, :4]
            pad = 6
            sl = (slice(max(0, y - pad), y + hgt + pad), slice(max(0, x - pad), x + w + pad))
            comp = lab[sl] == i
            new = rule(_neighbour_share(cls[sl], comp))
            if new is not None:
                cls[sl][comp] = new
    # face = largest skin blob in the head area, holes filled -> eyes, lashes, mouth live inside it
    from scipy.ndimage import binary_fill_holes
    head = np.zeros(cls.shape, bool); head[:int(cls.shape[0] * 0.30)] = True
    facey = cls == 4
    if FACE_CLASSES:
        # a pallor-washed face (20/26/28) is near-white with a faint tint; pure white collars (s < 6) stay out
        hsv = cv2.cvtColor(CUR_RGB, cv2.COLOR_RGB2HSV_FULL).astype(int)
        hue = hsv[..., 0] * 360 // 256
        # pallor is grey-white; a lilac tint at this saturation is a hair highlight or a cool shadow
        pal = (hsv[..., 1] < 35) & (hsv[..., 2] >= 150) & (cls == 3) & ~((hue >= 200) & (hue <= 330) & (hsv[..., 1] >= 12))
        pal = cv2.morphologyEx(pal.astype(np.uint8), cv2.MORPH_OPEN, np.ones((7, 7), np.uint8)) > 0
        facey = facey | pal
    n, lab, stats, cent = cv2.connectedComponentsWithStats((facey & head).astype(np.uint8), connectivity=4)
    if n > 1:
        best = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
        if FACE_CLASSES:
            # the face is the big skin piece nearest the middle of the hair mass (a raised hand can be bigger)
            hy, hx_ = np.nonzero((cls == 1) & head)
            if len(hx_):
                big = [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= 0.15 * stats[best, cv2.CC_STAT_AREA]]
                cx_h, cy_h = np.median(hx_), np.median(hy)
                best = min(big, key=lambda i: math.hypot(cent[i][0] - cx_h, cent[i][1] - cy_h))
        face = lab == best
        if FACE_CLASSES:
            # an open mouth's line can cut a pale face in two: pieces just below it, inside its width, belong to it
            bx, by, bw, bh = stats[best, :4]
            gap = max(4, int(bh * 0.12))
            low = [i for i in range(1, n) if i != best and stats[i, cv2.CC_STAT_AREA] >= 0.02 * stats[best, cv2.CC_STAT_AREA]
                   and 0 <= stats[i, cv2.CC_STAT_TOP] - (by + bh) <= gap and bx <= cent[i][0] <= bx + bw]
            if low:
                face = np.isin(lab, [best] + low)
                face |= cv2.morphologyEx(face.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((gap + 3, 1), np.uint8)) > 0
            face = cut_at_chin(face, mouth)
        face = binary_fill_holes(cv2.morphologyEx(face.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8)) > 0)
        if FACE_CLASSES:
            # bangs: hair inside the filled face that connects to hair outside it stays hair
            k, hl = cv2.connectedComponents((cls == 1).astype(np.uint8), connectivity=8)
            ext = np.unique(hl[(cls == 1) & ~face])
            bangs = np.isin(hl, ext[ext > 0])
            face &= ~bangs
        inner = face & (cls != 4) & ~(facey & ~(cls == 4))
        cls[inner & (cls == 1)] = 5                  # irises
        cls[inner & ((cls == 2) | (cls == 7))] = 7   # lashes, brows, pupils
        cls[inner & (cls == 3)] = 5                  # eye whites/highlights stay with the eye
        cls[face & mouth] = 6
        if FACE_CLASSES:
            face = face_classes(cls, face, head, lab, stats)
        global LAST_FACE
        LAST_FACE = face
    return cls


LAST_FACE = None
FACE_CLASSES = SCALE <= 2      # the HD set separates whites/teeth (10) and cast shadow (9) inside the face


# neck width / face width below which the blob is neck; 20's pale lower cheeks merge into the hair, so its
# lower face reads narrow and only a stricter ratio finds the real chin
CHIN_RATIO = 0.6
CHIN_RATIOS = {"20_paralyzing_terror": 0.4}


def cut_at_chin(face, mouth=None):
    """Drop the neck and collar: the chin is the first row below the widest face row (searched in the upper
    part of the blob only, so a wide collar can't win) where the blob narrows to neck width."""
    ys = np.nonzero(face.any(1))[0]
    if not len(ys):
        return face
    first = np.where(face.any(1), np.argmax(face, 1), 0)
    last = np.where(face.any(1), face.shape[1] - 1 - np.argmax(face[:, ::-1], 1), 0)
    widths = np.where(face.any(1), last - first + 1, 0)       # row span, so an open mouth isn't a "narrowing"
    top, bot = ys[0], ys[-1]
    wrow = top + int(np.argmax(widths[top:top + max(1, int(0.55 * (bot - top)))]))
    below = np.nonzero(widths[wrow:] < CHIN_RATIO * widths[wrow])[0]
    if not len(below):
        return face
    cut = wrow + int(below[0])
    if mouth is not None:
        # a wide grin can split the cheeks off the lower face, so a "narrowing" that slices through a
        # mouth isn't the chin: restart below that mouth, against the width the face has there
        x0, x1 = first[wrow], last[wrow]
        k, ml, mst, _ = cv2.connectedComponentsWithStats(mouth.astype(np.uint8), connectivity=8)
        hit = np.unique(ml[max(0, cut - 2):cut + 3, x0:x1 + 1])
        hit = [i for i in hit if i > 0 and mst[i, cv2.CC_STAT_HEIGHT] < widths[wrow]]
        if hit:
            start = max(int(mst[i, cv2.CC_STAT_TOP] + mst[i, cv2.CC_STAT_HEIGHT]) for i in hit)
            more = np.nonzero(widths[start:] < 0.75 * widths[start])[0]
            cut = start + int(more[0]) if len(more) else bot
    face = face.copy(); face[cut + 1:] = False
    return face


def face_classes(cls, face, head, lab, stats):
    from scipy.ndimage import binary_fill_holes
    """HD faces. The face is the hull of the skin pieces around the main face blob plus the irises, so a shadow
    band across the eyes (21/25/30) stays inside it. Inside, pixels are re-read from the source colours:
    lines, whites/teeth, iris (upper face) vs mouth (lower face), and cast shadow."""
    rgb = CUR_RGB
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV_FULL).astype(int)
    h = hsv[..., 0] * 360 // 256
    s, v = hsv[..., 1], hsv[..., 2]
    ys, xs = np.nonzero(face)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    chin = y1
    fh = y1 - y0
    pieces = np.zeros_like(face)
    for i in range(1, len(stats)):
        bx, by, bw, bh, area = stats[i]
        if area > 40 and bx < x1 and bx + bw > x0 and by + bh > y0 - fh and by < y1:
            pieces |= lab == i
    # warm pixels in a box above the face: a cast shadow band and the eyes inside it (21/25)
    sat_eye = ((h <= 40) | (h >= 300)) & (cls != 8) & (cls != 0)
    sat_eye &= (np.arange(cls.shape[1])[None, :] > x0) & (np.arange(cls.shape[1])[None, :] < x1)
    sat_eye[:max(0, y0 - int(0.6 * fh))] = False
    sat_eye[y1:] = False
    pts = np.argwhere(pieces | face | sat_eye)[:, ::-1].astype(np.int32)
    hull = np.zeros(cls.shape, np.uint8)
    cv2.fillConvexPoly(hull, cv2.convexHull(pts), 1)
    hull = hull > 0
    hull[chin + 1:] = False
    warm = (h <= 40) | (h >= 300)
    reds = (h <= 20) | (h >= 330)
    # only warm/red pixels join from the hull: a cast shadow or glowing eyes across the face, never hair
    extra = hull & ~face & warm & (v >= 45) & (cls != 8) & ~((cls == 4) & (v >= 150))
    # pallor: broad cool/grey-white wash joined to the face (thin pale hair highlights are opened away)
    skin_hue = (h <= 40) | (h >= 340)
    face_in2 = cv2.dilate(binary_fill_holes(face).astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    cool = face_in2 & (cls != 8) & (s < 35) & (v >= 150) & ~(skin_hue & (s >= 12)) & ~((h >= 200) & (h <= 330) & (s >= 12))
    cool = cv2.morphologyEx(cool.astype(np.uint8), cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) > 0
    k, lab2 = cv2.connectedComponents(cool.astype(np.uint8))
    touch = cv2.dilate(face.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    keep = np.unique(lab2[touch & cool])
    keep = [i for i in keep if i > 0 and (lab2 == i).sum() >= 0.06 * face.sum()]
    pallor = np.isin(lab2, keep)
    region = face | extra | pallor
    hy = np.nonzero(region)[0]
    split = hy.min() + 0.62 * (hy.max() - hy.min())            # eyes above, mouth below
    rows = np.arange(cls.shape[0])[:, None]
    skin = region & warm & (s >= 12) & (v >= 150)
    lit_shade = region & warm & (v >= 110) & (v < 150) & (s < 110) & ~extra   # soft shading on the skin
    strong_red = reds & (s >= 120) & (v >= 50)
    mouth_red = (cls == 6) & reds & (v >= 22)
    line = region & (v < 45) & ~strong_red & ~mouth_red
    iris = (face | extra) & (rows < split) & ~line & ~skin & ~lit_shade & (((cls == 5) | (cls == 1)) & ~warm | strong_red)
    mth = region & (rows >= split) & ~line & ((cls == 6) | strong_red)
    near_mouth = cv2.dilate(mth.astype(np.uint8), np.ones((15, 15), np.uint8)) > 0
    fw = x1 - x0
    # thin iris-coloured strokes (brows, bang tips inside the face) are lines, not eyes
    k, il, ist, _ = cv2.connectedComponentsWithStats(iris.astype(np.uint8), connectivity=8)
    for i in range(1, k):
        bx, by, bw, bh, area = ist[i]
        comp = il == i
        if (strong_red & comp).sum() >= 0.3 * area or bh >= 0.6 * bw:
            continue                          # glowing or round: an eye, however small
        if area < (fw / 14) ** 2 or bh < fw / 30 or area < 0.35 * bw * bh and bh < fw / 16 or bw >= 2.5 * bh:
            iris[comp] = False
            line |= comp
    # an iris touching the side hair was taken for bangs: find its twin at the other eye's height
    k, il, ist, icent = cv2.connectedComponentsWithStats(iris.astype(np.uint8), connectivity=8)
    eyes = [i for i in range(1, k) if ist[i, 4] >= (fw / 14) ** 2]
    if len(eyes) == 1:
        e = eyes[0]
        cand = hull & (cls == 1) & ~iris & (rows < split) & (v >= 90)
        cand = cv2.morphologyEx(cand.astype(np.uint8), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        k2, cl, cst, ccent = cv2.connectedComponentsWithStats(cand, connectivity=8)
        for j in range(1, k2):
            if (0.4 * ist[e, 4] <= cst[j, 4] <= 2.5 * ist[e, 4] and abs(ccent[j][1] - icent[e][1]) < 0.6 * ist[e, 3]
                    and abs(ccent[j][0] - icent[e][0]) > 1.5 * ist[e, 2]):
                iris |= cl == j
    # eye whites sit beside the iris, between its top and bottom rows (bang highlights just above it don't count)
    near_iris = np.zeros_like(iris)
    k, il, ist, _ = cv2.connectedComponentsWithStats(iris.astype(np.uint8), connectivity=8)
    for i in range(1, k):
        bx, by, bw, bh, area = ist[i]
        if area >= 20:
            near_iris[by + max(1, bh // 8):by + bh + 3, max(0, bx - fw // 10):bx + bw + fw // 10] = True
    white = region & (v >= 175) & ((s < 14) | ((s < 45) & ~skin_hue)) & (((rows < split) & near_iris) | near_mouth)
    blush = region & ((h >= 330) | (h <= 8)) & (s >= 40) & (v >= 170) & ~(iris | mth | line | white)
    pale = region & pallor & ~(line | iris | mth | white | blush)
    shade = region & warm & (v < 110) & ~(line | iris | mth | white)
    # a lilac cast shadow over the upper face (the menacing shadow band) stays shadow, not skin or eye white
    cool_sh = region & (rows < split) & (h >= 200) & (h <= 330) & (s >= 15) & (v < 215) & ~(line | iris | mth)
    shade |= cool_sh
    white &= ~cool_sh
    skin &= ~cool_sh
    lit_shade &= ~cool_sh
    global DEBUG_FACE
    DEBUG_FACE = (hull, face, region)
    rest = region & ~(shade | skin | lit_shade | pale | blush | iris | white | mth | line)
    lit_shade = lit_shade | (rest & (v >= 60))    # leftover cool shading on the face (bang shadows) is skin shadow
    line = line | (rest & (v < 60))
    for m, c in ((shade, 9), (skin | lit_shade, 4), (pale, 11), (blush, 12), (iris, 5), (white, 10), (mth, 6), (line, 7)):
        cls[m] = c
    return region


CUR_RGB = None
CLASS_NAMES = {1: "hair", 2: "dress", 3: "blouse", 4: "skin", 5: "eye", 6: "mouth", 7: "line"}


def load(path):
    bgr = cv2.imread(path, cv2.IMREAD_COLOR)
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    if rgb.shape[:2] != (1376, 768):
        h, w = rgb.shape[:2]
        k = min(768 / w, 1376 / h)
        small = cv2.resize(rgb, (round(w * k), round(h * k)), interpolation=cv2.INTER_AREA)
        canvas = np.full((1376, 768, 3), 255, np.uint8)
        y0, x0 = (1376 - small.shape[0]) // 2, (768 - small.shape[1]) // 2
        canvas[y0:y0 + small.shape[0], x0:x0 + small.shape[1]] = small
        rgb = canvas
    return rgb


def debug_classes(path, out):
    rgb = load(path)
    fg = foreground_mask(rgb)
    cls, _ = classify(rgb, fg)
    colors = np.array([[40, 40, 40], [200, 160, 255], [180, 20, 40], [240, 240, 240], [255, 200, 170],
                       [0, 255, 0], [255, 0, 255], [0, 0, 0], [0, 160, 255]], np.uint8)
    vis = colors[cls]
    cv2.imwrite(out, cv2.cvtColor(np.hstack([rgb, vis]), cv2.COLOR_RGB2BGR))


if __name__ == "__main__" and sys.argv[1] == "debug":
    debug_classes(sys.argv[2], sys.argv[3])


# ---------------------------------------------------------------- 3. normalise + downscale
def measure(rgb, fg):
    ys, xs = np.nonzero(fg)
    top, bottom = ys.min(), ys.max()
    # body centre: median x of the leg band (stable even when arms/knife stick out)
    band = fg[int(bottom - (bottom - top) * 0.30):int(bottom - (bottom - top) * 0.10)]
    cx = float(np.median(np.nonzero(band)[1]))
    return top, bottom, cx


def normalise(rgb, fg, cls, ref_height):
    """Scale so the figure has the reference height, centre on the legs, put soles on the baseline."""
    top, bottom, cx = measure(rgb, fg)
    k = ref_height / float(bottom - top)
    k = min(max(k, 0.80), 1.15)
    M = np.float32([[k, 0, 384 - cx * k], [0, k, FEET_Y * SCALE - bottom * k]])
    size = (W * SCALE, H * SCALE)
    rgb2 = cv2.warpAffine(rgb, M, size, flags=cv2.INTER_AREA, borderValue=(255, 255, 255))
    fg2 = cv2.warpAffine(fg.astype(np.uint8), M, size, flags=cv2.INTER_NEAREST) > 0
    cls2 = cv2.warpAffine(cls, M, size, flags=cv2.INTER_NEAREST)
    return rgb2, fg2, cls2


PRIORITY = {7: 3, 5: 2, 6: 2, 10: 2, 8: 2}   # thin features win a cell with fewer pixels


def downscale(rgb, fg, cls):
    lum = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB)[..., 0].astype(np.float32)
    blk = lambda a: a.reshape(H, SCALE, W, SCALE).swapaxes(1, 2).reshape(H, W, SCALE * SCALE)
    F, C, L = blk(fg), blk(cls), blk(lum)
    alpha = F.sum(-1) >= max(2, round(7 * SCALE * SCALE / 16))
    out_c = np.zeros((H, W), np.uint8)
    out_l = np.zeros((H, W), np.float32)
    for y in range(H):
        for x in range(W):
            if not alpha[y, x]:
                continue
            cc = C[y, x][F[y, x]]
            counts = np.bincount(cc, minlength=13)
            best = int(np.argmax(counts))
            for c, need in PRIORITY.items():
                if counts[c] >= max(1, round(need * SCALE * SCALE / 16)) and counts[c] * 2 >= counts[best] * 0.6:
                    best = c
                    break
            if best == 0:
                best = 3
            out_c[y, x] = best
            sel = F[y, x] & (C[y, x] == best)
            out_l[y, x] = L[y, x][sel].mean() if sel.any() else L[y, x].mean()
    return alpha, out_c, out_l


# ---------------------------------------------------------------- 4. palette mapping
ABS_LUM = {"pale": (70, 245), "white": (150, 250), "blush": (150, 235), "shade": (25, 120)}
BAYER = np.array([[0, 2], [3, 1]], np.float32) / 4.0 - 0.375


def to_palette(alpha, cls, lum):
    out = np.zeros((H, W, 4), np.uint8)
    name_of = {1: "hair", 2: "dress", 3: "blouse", 4: "skin", 5: "eye", 6: "mouth", 7: "line", 8: "dress",
               9: "shade", 10: "white", 11: "pale", 12: "blush"}
    for c, name in name_of.items():
        m = alpha & (cls == c)
        if not m.any() or name == "line":
            continue
        ramp = [hx(r) for r in RAMPS[name]]
        if name in ("hair", "dress", "blouse"):
            lum = lum.copy()
            med = cv2.medianBlur(np.clip(lum, 0, 255).astype(np.uint8), 3).astype(np.float32)
            lum[m] = med[m]
        vals = lum[m]
        lo, hi = np.percentile(vals, 4), np.percentile(vals, 97)
        if name in ABS_LUM:                      # small face classes: absolute brightness, not stretched
            lo, hi = ABS_LUM[name]
        t = np.clip((lum - lo) / max(hi - lo, 1), 0, 1) * (len(ramp) - 1)
        if name == "eye" and FACE_CLASSES:
            # each eye gets its own full ramp, so an eye in the bangs' shadow isn't a black hole
            k, el, est, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8), connectivity=8)
            for i in range(1, k):
                if est[i, 4] >= 15:
                    e = el == i
                    elo, ehi = np.percentile(lum[e], 5), np.percentile(lum[e], 97)
                    t[e] = np.clip((lum[e] - elo) / max(ehi - elo, 1), 0, 1) * (len(ramp) - 1)
        ys, xs = np.nonzero(m)
        tt = t[ys, xs] + BAYER[ys % 2, xs % 2] * {"hair": 0.45, "dress": 0.8, "blouse": 0.6}.get(name, 0.0)
        idx = np.clip(np.round(tt), 0, len(ramp) - 1).astype(int)
        out[ys, xs, :3] = np.array(ramp)[idx]
        out[ys, xs, 3] = 255
    # lines: sel-out -> darkest shade of the region they sit on
    lm = alpha & (cls == 7)
    ys, xs = np.nonzero(lm)
    for y, x in zip(ys, xs):
        nb = cls[max(0, y - 1):y + 2, max(0, x - 1):x + 2].ravel()
        nb = nb[(nb != 7) & (nb != 0)]
        reg = np.bincount(nb, minlength=13).argmax() if len(nb) else 7
        col = {1: RAMPS["hair"][0], 2: RAMPS["dress"][0], 3: RAMPS["blouse"][0], 4: "5a3236",
               5: RAMPS["eye"][0], 6: RAMPS["mouth"][0], 8: RAMPS["dress"][0], 9: "140a0e", 10: RAMPS["eye"][0],
               11: "3e3446", 12: "5a3236"}.get(int(reg), OUTLINE)
        out[y, x, :3] = hx(col)
        out[y, x, 3] = 255
    return out


def outline_and_rim(img, cls):
    a = img[..., 3] > 0
    pad = np.pad(a, 1)
    edge = a & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    skin_edge = edge & (cls == 4)
    img[edge & ~skin_edge, :3] = hx(OUTLINE)
    img[skin_edge, :3] = hx("5a3236")
    # signature crimson rim light: pixels just inside the right-hand silhouette (light from the right)
    right_open = a & ~pad[1:-1, 2:]
    rim = np.zeros_like(a)
    rim[:, :-1] = right_open[:, 1:] & a[:, :-1] & ~edge[:, :-1]
    rim &= (cls == 1) | (cls == 3) | (cls == 2)
    img[rim, :3] = hx("c0303c")
    return img


def cleanup(img):
    """Remove lone pixels that differ from all 4 neighbours (pixel-art 'jaggies' pass)."""
    rgb = img[..., :3].astype(int)
    key = (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]
    key[img[..., 3] == 0] = -1
    out = img.copy()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            k = key[y, x]
            if k == -1:
                continue
            nb = [key[y - 1, x], key[y + 1, x], key[y, x - 1], key[y, x + 1]]
            if k not in nb and nb[0] == nb[1] == nb[2] == nb[3] and nb[0] != -1:
                out[y, x] = img[y - 1, x]
    return out


def process(path, ref_height):
    global CHIN_RATIO
    CHIN_RATIO = CHIN_RATIOS.get(os.path.splitext(os.path.basename(path))[0], 0.6) if FACE_CLASSES else 0.6
    rgb = load(path)
    if "predatory_bloodlust" in path:
        rgb = remove_aura(rgb)
    fg = foreground_mask(rgb)
    cls, _ = classify(rgb, fg)
    rgb, fg, cls = normalise(rgb, fg, cls, ref_height)
    alpha, c, l = downscale(rgb, fg, cls)
    img = to_palette(alpha, c, l)
    img = cleanup(img)
    img = outline_and_rim(img, c)
    return img, c


def ref_height_from(path):
    rgb = load(path)
    top, bottom, _ = measure(rgb, foreground_mask(rgb))
    return bottom - top


def main(src, out_dir, names):
    os.makedirs(out_dir, exist_ok=True)
    ref = ref_height_from(os.path.join(src, "00_base_reference.png"))
    for n in names:
        img, c = process(os.path.join(src, n), ref)
        stem = os.path.splitext(n)[0]
        cv2.imwrite(os.path.join(out_dir, stem + ".png"), cv2.cvtColor(img, cv2.COLOR_RGBA2BGRA))
        np.save(os.path.join(out_dir, stem + ".cls.npy"), c)
        print("ok", stem)


if __name__ == "__main__" and sys.argv[1] != "debug":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
