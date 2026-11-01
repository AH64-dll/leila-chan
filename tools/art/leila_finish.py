"""Leila finishing pass: cleanup, new hair clip, hand-designed faces, procedural hands, effects, export.

    python3 tools/art/leila_finish.py <px_dir> <out_dir> [names...]
"""
import json
import math
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from leila_px import RAMPS, OUTLINE, hx, W, H  # noqa: E402

HERE = os.path.dirname(__file__)

# ------------------------------------------------------------------ palette keys used by every pixel grid
KEY = {
    "o": OUTLINE, "O": "5a3236",                         # outline, soft skin outline
    "h": "fbe9e0", "b": "efd2c6", "m": "dcb3aa", "s": "b98b88", "x": "8a5f63",   # skin ramp
    "W": "fbe9e0", "w": "e6d6dc",                         # eye whites
    "K": "0b080c", "k": "2c1820",                         # lashes / brows
    "R": "d8323a", "r": "9b1420", "q": "5c0a12", "P": "2a0408", "L": "ff7a6e",   # irises
    "M": "7d2a2c", "n": "b65252", "t": "e08a84", "T": "fbe9e0",                  # mouth, tongue, teeth
    "c": "e8a0a0", "C": "d77a80",                         # blush
    "e": "a8d8ff", "E": "6fa8dc",                         # tears / sweat
    "D": "8f1f2c", "d": "b3313a", "B": "4d0f1a", "g": "ff3b3b",  # blood / clip crimson / glow
    "z": "1d0509",
}


def put(img, grid, x0, y0, mirror=False):
    rows = [r for r in grid.strip("\n").split("\n")]
    for j, row in enumerate(rows):
        row = row.rstrip()
        if mirror:
            row = row[::-1]
        for i, ch in enumerate(row):
            if ch in (".", " "):
                continue
            y, x = y0 + j, x0 + i
            if 0 <= y < H and 0 <= x < W:
                img[y, x, :3] = hx(KEY[ch])
                img[y, x, 3] = 255


def grid_size(grid):
    rows = grid.strip("\n").split("\n")
    return max(len(r.rstrip()) for r in rows), len(rows)


# ------------------------------------------------------------------ 1. cleanup
def remove_islands(img, max_px=3):
    """Pixels groups of <= max_px whose whole border is one other colour get that colour."""
    rgb = img[..., :3].astype(np.int32)
    key = (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]
    key[img[..., 3] == 0] = -1
    out = img.copy()
    for k in np.unique(key):
        if k == -1:
            continue
        m = (key == k).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
        for i in range(1, n):
            if st[i, 4] > max_px:
                continue
            comp = lab == i
            ring = (cv2.dilate(comp.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~comp
            vals = key[ring]
            u, c = np.unique(vals, return_counts=True)
            if len(u) == 1 or c.max() >= 0.8 * c.sum():
                best = u[np.argmax(c)]
                src = np.argwhere(ring & (key == best))[0]
                out[comp] = img[src[0], src[1]]
    return out


def inpaint_region(img, mask, keep_alpha_from_neighbours=True):
    """Fill mask pixels from the most common surrounding colour, growing inward (pixel-art friendly)."""
    img = img.copy()
    todo = mask.copy()
    for _ in range(40):
        if not todo.any():
            break
        ring = todo & (cv2.dilate((~todo).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
        for y, x in np.argwhere(ring):
            ys, xs = slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2)
            nb = img[ys, xs][~todo[ys, xs]]
            if len(nb) == 0:
                continue
            k = [tuple(p) for p in nb]
            k2 = [q for q in k if q[3] == 0 or q[:3] not in (tuple(hx(OUTLINE)), tuple(hx("5a3236")))]
            k = k2 or k
            best = max(set(k), key=k.count)
            img[y, x] = best
        todo &= ~ring
    return img


# ------------------------------------------------------------------ 2. hair clip (original design: cracked, bleeding heart)
CLIP = """
.ooo...ooo.
odLdo.oddDo
odLddoddDDo
oddddzdddDo
oddddzddDDo
.odddzdDDo.
..oddzdDo..
...odzDo...
....oDo....
.....o.....
.....D.....
.....o.....
"""


def replace_clip(img, cls):
    m = cls == 8
    if not m.any():
        return img, None
    ys, xs = np.nonzero(m)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    zone = np.zeros_like(m)
    zone[max(0, y0 - 2):y1 + 3, max(0, x0 - 2):x1 + 3] = True
    # everything in the zone that is not hair-coloured is the old clip (incl. its outline)
    hair_cols = {tuple(hx(c)) for c in RAMPS["hair"]}
    old = zone & (img[..., 3] > 0)
    for y, x in np.argwhere(old):
        if tuple(img[y, x, :3]) in hair_cols and cls[y, x] == 1:
            old[y, x] = False
    # clone-stamp hair texture from just left of the clip (inpainting from neighbours would keep the dark blob)
    zone_dark = zone & (img[..., 3] > 0)
    w = (x1 - x0) + 5
    src = img.copy()
    for y, x in np.argwhere(zone_dark):
        sx = x - w
        while sx >= 0 and src[y, sx, 3] == 0:
            sx -= 1
        if sx >= 0 and cls[y, sx] == 1:
            img[y, x] = src[y, sx]
        elif old[y, x]:
            img[y, x, :3] = hx(RAMPS["hair"][1])
    # re-outline the cloned area where it meets transparency
    a = img[..., 3] > 0
    pad = np.pad(a, 1)
    edge = a & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    img[edge & zone, :3] = hx(OUTLINE)
    cw, ch = grid_size(CLIP)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    put(img, CLIP, cx - cw // 2, cy - ch // 2 + 1)
    return img, (cx, cy)


# ------------------------------------------------------------------ 3. faces
import faces as F  # noqa: E402


EYE_WIPE_X = [(79, 89), (95, 103)]
EYE_WIPE_Y = (47, 51)


def clear_face(img, cls, off):
    dx, dy = off
    x0, y0, x1, y1 = F.FACE_ZONE
    base, mid = hx(KEY["b"]), hx(KEY["m"])
    skinish = np.isin(cls, [4, 5, 6, 7])
    for y in range(y0 + dy, y1 + dy + 1):
        for x in range(x0 + dx, x1 + dx + 1):
            if not skinish[y, x] or img[y, x, 3] == 0:
                continue
            # keep the face outline: a skin pixel touching transparency/hair outside stays as is
            nb = cls[y - 1:y + 2, x - 1:x + 2]
            if (nb == 0).any():
                continue
            under_hair = cls[y - 1, x] == 1 or cls[y - 2, x] == 1
            img[y, x, :3] = mid if under_hair else base
            cls[y, x] = 4
    # the base render's own eyes are dark red and were classed as hair/dress, so wipe their boxes outright
    # (rows below the bangs, between the face edges); the designed eyes are drawn on top afterwards
    for ex0, ex1 in EYE_WIPE_X:
        for y in range(EYE_WIPE_Y[0] + dy, EYE_WIPE_Y[1] + dy + 1):
            for x in range(ex0 + dx, ex1 + dx + 1):
                img[y, x, :3] = mid if y == EYE_WIPE_Y[0] + dy and cls[y - 1, x] == 1 else base
                img[y, x, 3] = 255
                cls[y, x] = 4
    # lone specks left from the base render's brows (forehead, above the wipe boxes)
    skin = {tuple(hx(c)) for c in RAMPS["skin"]}
    for y in range(38 + dy, EYE_WIPE_Y[0] + dy):
        for x in range(EYE_WIPE_X[0][0] + dx, EYE_WIPE_X[1][1] + dx + 1):
            if tuple(img[y, x, :3]) in skin:
                continue
            n = sum(tuple(img[y + j, x + i, :3]) in skin for j in (-1, 0, 1) for i in (-1, 0, 1) if i or j)
            if n >= 6:
                img[y, x, :3] = base
                cls[y, x] = 4


def draw_face(img, cls, spec, off=(0, 0)):
    """spec: {"eyes": name | [left, right], "brows": name, "mouth": name, "extras": [...], "mouth_dy": int}"""
    dx, dy = off
    clear_face(img, cls, off)
    eyes = spec.get("eyes", "open")
    le, re = (eyes, eyes) if isinstance(eyes, str) else eyes
    put(img, F.EYES[le], F.LEFT_EYE[0] + dx, F.LEFT_EYE[1] + dy)
    put(img, F.EYES[re], F.RIGHT_EYE[0] + dx, F.RIGHT_EYE[1] + dy, mirror=True)
    if spec.get("brows"):
        b = F.BROWS[spec["brows"]]
        bdy = dy + spec.get("brow_dy", 0)
        put(img, b, F.BROW_L[0] + dx, F.BROW_L[1] + bdy - (grid_size(b)[1] - 1))
        put(img, b, F.BROW_R[0] + dx, F.BROW_R[1] + bdy - (grid_size(b)[1] - 1), mirror=True)
    m = F.MOUTHS[spec.get("mouth", "closed")]
    mw, _ = grid_size(m)
    put(img, m, F.MOUTH_C[0] + dx - mw // 2, F.MOUTH_C[1] + dy + spec.get("mouth_dy", 0))
    for ex in spec.get("extras", []):
        g, spots = F.EXTRAS[ex]
        for (x, y) in spots:
            put(img, g, x + dx, y + dy)


# ------------------------------------------------------------------ 4. canonical head (built once from 00, reused by every sprite)
RIM = "c0303c"
HEAD_CUT = 64          # rows above this come from the canonical head
FACE_BOX = (74, 34, 112, 66)


def _edge_x(y, pts):
    for (y0, x0), (y1, x1) in zip(pts, pts[1:]):
        if y0 <= y <= y1:
            return int(round(x0 + (x1 - x0) * (y - y0) / max(1, y1 - y0)))
    return None


def build_head(img, cls):
    img, cls = img.copy(), cls.copy()
    # the logo clip's inner hole was keyed out as background: rebuild the right hair silhouette
    pts = [(18, 104), (22, 107), (27, 111), (32, 114), (37, 116), (42, 117), (47, 117)]
    hair = [hx(c) for c in RAMPS["hair"]]
    for y in range(18, 48):
        xe = _edge_x(y, pts)
        for x in range(96, 122):
            if x < xe:
                if img[y, x, 3] == 0 or cls[y, x] in (0, 8) or tuple(img[y, x, :3]) == tuple(hx(OUTLINE)) and x > 100:
                    src = None
                    for sx in range(x - 13, 60, -1):
                        if cls[y, sx] == 1 and img[y, sx, 3]:
                            src = img[y, sx]; break
                    img[y, x] = src if src is not None else np.r_[hair[1], 255]
                    cls[y, x] = 1
            elif x == xe:
                img[y, x] = np.r_[hx(OUTLINE), 255]; cls[y, x] = 7
            elif x <= 120 and y >= 26 and y <= 46:
                img[y, x, 3] = 0; cls[y, x] = 0
        # crimson rim just inside the rebuilt edge (matches the rest of the silhouette)
        if 29 <= y <= 46:
            img[y, xe - 1, :3] = hx(RIM)
    cls[cls == 8] = 1
    # stray crimson/eye specks around the face (old blush, cheek rim) -> majority neighbour
    bad = {tuple(hx(c)) for c in RAMPS["eye"] + RAMPS["dress"] + [RIM]}
    x0, y0, x1, y1 = FACE_BOX
    spot = np.zeros(cls.shape, bool)
    for y in range(y0, y1):
        for x in range(x0 - 4, x1 + 4):
            if tuple(img[y, x, :3]) in bad and not (100 <= x <= 113 and y <= 44):
                spot[y, x] = True
    img = inpaint_region(img, spot)
    hc = (106, 37)
    cw, ch = grid_size(CLIP)
    put(img, CLIP, hc[0] - cw // 2, hc[1] - ch // 2)
    return img, cls


HANDS_IN_HAIR = {"22_unhinged_jaw_laugh"}


def composite_head(img, cls, head, hcls, off=(0, 0), hands_in_hair=False):
    dx, dy = off
    out, oc = img.copy(), cls.copy()
    H_ = np.roll(np.roll(head, dy, 0), dx, 1)
    C_ = np.roll(np.roll(hcls, dy, 0), dx, 1)
    rows = slice(0, HEAD_CUT + dy)
    x0, y0, x1, y1 = FACE_BOX
    facebox = np.zeros(cls.shape, bool); facebox[y0 + dy:y1 + dy, x0 + dx:x1 + dx] = True
    # the sprite's own raised hands survive (skin outside the canonical face) together with their outline
    # only skin outside the canonical head silhouette counts as a hand (22 grips her own hair)
    hand = (cls == 4) & (~((C_ == 4) & facebox) if hands_in_hair else (C_ == 0))
    hand[:12] = False
    keep = cv2.dilate(hand.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    keep &= img[..., 3] > 0
    m = np.zeros(cls.shape, bool); m[rows] = True
    m &= ~keep
    out[m] = H_[m]; oc[m] = C_[m]
    # blend band: below the cut, hair-on-hair rows taken from the head for a few px to hide the seam
    for y in range(HEAD_CUT + dy, HEAD_CUT + dy + 6):
        sel = (C_[y] == 1) & (cls[y] == 1) & ~keep[y]
        out[y, sel] = H_[y, sel]
    return out, oc


def shadow_band(img, y0, y1, x0=74, x1=114, strength=2):
    """darken the upper face like the 'shadowed eyes' manga look: skin steps down the ramp."""
    ramp = [tuple(hx(c)) for c in RAMPS["skin"]]
    dark = [hx("3a2228"), hx("5a3236")] + [hx(c) for c in RAMPS["skin"]]
    for y in range(y0, y1):
        k = strength + (1 if y < y1 - 6 else 0)
        for x in range(x0, x1):
            c = tuple(img[y, x, :3])
            if y >= y1 - 2 and (x + y) % 2:
                continue  # dithered lower edge
            if img[y, x, 3] and c in ramp:
                i = ramp.index(c) + 2
                img[y, x, :3] = dark[max(0, i - k - 1)]


HEAD_CLS = None
HEAD_IMG = None
FACE_IMG = None
BASE = None
NECK_RECT = {"12_exhausted_fatigue": (60, 58, 124, 90)}
NECK_FROM_BASE = {"15_tearful_sorrow", "16_bitter_breakdown", "24_obsessive_yandere_blush", "28_manic_finger_biting",
                  "08_deep_confusion", "20_paralyzing_terror"}

# ------------------------------------------------------------------ 5. per-sprite casting of expressions
SPRITES = {
    "00_base_reference":          {"eyes": "open", "mouth": "smile"},
    "01_radiant_joy":             {"eyes": "happy", "mouth": "laugh", "extras": ["blush"]},
    "02_gentle_relief":           {"eyes": "soft", "brows": "worried", "mouth": "smile", "extras": ["blush"]},
    "03_playful_smugness":        {"eyes": ["happy", "narrow"], "brows": "raised", "mouth": "smile"},
    "04_confident_pride":         {"eyes": "soft", "brows": "raised", "mouth": "smile"},
    "05_pure_innocence":          {"eyes": "open", "brows": "raised", "mouth": "small_o", "extras": ["blush"]},
    "06_flustered_shyness":       {"eyes": "soft", "brows": "worried", "mouth": "wavy", "extras": ["blush_heavy", "sweat"]},
    "07_stoic_coldness":          {"eyes": "narrow", "brows": "flat", "mouth": "flat"},
    "08_deep_confusion":          {"eyes": ["open", "soft"], "brows": "raised", "mouth": "pout", "extras": ["sweat"]},
    "09_suspicious_glare":        {"eyes": "narrow", "brows": "angry", "mouth": "pout"},
    "10_bored_apathy":            {"eyes": "tired", "brows": "flat", "mouth": "flat"},
    "11_sudden_shock":            {"eyes": "wide", "brows": "raised", "mouth": "shock"},
    "12_exhausted_fatigue":       {"eyes": "tired", "brows": "worried", "mouth": "small_o", "extras": ["eyebags"]},
    "13_nervous_anxiety":         {"eyes": "open", "brows": "worried", "mouth": "wavy", "extras": ["sweat"]},
    "14_quiet_melancholy":        {"eyes": "soft", "brows": "worried", "mouth": "frown"},
    "15_tearful_sorrow":          {"eyes": "tear", "brows": "worried", "mouth": "sad_open", "extras": ["tears"]},
    "16_bitter_breakdown":        {"eyes": "shut", "brows": "worried", "mouth": "grimace", "extras": ["tears"]},
    "17_fierce_anger":            {"eyes": "furious", "brows": "angry", "brow_dy": 3, "mouth": "shout"},
    "18_visceral_disgust":        {"eyes": ["narrow", "soft"], "brows": "angry", "mouth": "tongue"},
    "19_desperate_pleading":      {"eyes": "tear", "brows": "worried", "mouth": "sad_open", "extras": ["tears", "blush"]},
    "20_paralyzing_terror":       {"eyes": "wide", "brows": "worried", "mouth": "shock", "extras": ["sweat", "tears"]},
    "21_red_eyed_knife_mania":    {"eyes": "glow", "brows": "angry", "mouth": "grin", "shadow": [26, 52]},
    "22_unhinged_jaw_laugh":      {"eyes": "manic", "brows": "raised", "mouth": "jaw", "off": [0, -2]},
    "23_hollow_dead_eyed_void":   {"eyes": "dead", "mouth": "flat"},
    "24_obsessive_yandere_blush": {"eyes": "heart", "brows": "worried", "mouth": "open_smile", "extras": ["blush_heavy"]},
    "25_shadowed_psychosis":      {"eyes": "glow", "mouth": "smile", "shadow": [26, 54]},
    "26_sanity_break_twitch":     {"eyes": ["manic", "wide"], "brows": "worried", "mouth": "grin", "extras": ["sweat"]},
    "27_bloodstained_innocence":  {"eyes": "open", "brows": "raised", "mouth": "smile", "extras": ["blood"]},
    "28_manic_finger_biting":     {"eyes": "manic", "brows": "worried", "mouth": "grimace"},
    "29_glitching_distortion":    {"eyes": ["dead", "glow"], "mouth": "grin", "body": "23_hollow_dead_eyed_void"},
    "30_predatory_bloodlust":     {"eyes": "glow", "brows": "angry", "mouth": "fangs", "shadow": [26, 51],
                                   "extras": ["blood"], "body": "26_sanity_break_twitch"},
}


def load_px(px_dir, name):
    img = cv2.cvtColor(cv2.imread(os.path.join(px_dir, name + ".png"), cv2.IMREAD_UNCHANGED), cv2.COLOR_BGRA2RGBA)
    return img, np.load(os.path.join(px_dir, name + ".cls.npy"))


def finish(px_dir, name, head, hcls):
    spec = SPRITES[name]
    img, cls = load_px(px_dir, spec.get("body", name))
    off = tuple(spec.get("off", (0, 0)))
    img, cls = composite_head(img, cls, head, hcls, off, name in HANDS_IN_HAIR)
    img = remove_islands(img)
    clear_face(img, cls, off)
    draw_face(img, cls, spec, off)
    if "shadow" in spec:
        shadow_band(img, spec["shadow"][0] + off[1], spec["shadow"][1] + off[1])
    hf = np.zeros(cls.shape, bool)
    x0, y0, x1, y1 = FACE_BOX
    hf[y0:y1, x0:x1] = True
    hf &= np.roll(np.roll(HEAD_CLS, off[1], 0), off[0], 1) == 4
    global FACE_IMG
    FACE_IMG = img.copy()
    redraw_hands(img, cls, name, hf, spec)
    retexture_braid(img, cls, name)
    clean_specks(img, cls)
    fix_sock_tops(img, cls)
    drop_dark_orphans(img, cls)
    erode_unoutlined_skin(img, cls)
    drop_dark_orphans(img, cls)
    a = (img[..., 3] > 0).astype(np.uint8)
    k, lab, st, _ = cv2.connectedComponentsWithStats(a, connectivity=8)
    for i in range(1, k):
        if st[i, 4] < 40:
            img[lab == i, 3] = 0; cls[lab == i] = 0
    touchup(img, cls, name)
    draw_forearms(img, cls, name)
    drop_stray_iris(img, cls)
    fill_feet(img, cls)
    square_sock_cuffs(img, cls)
    seal_slits(img, cls)
    deoutline(img, cls, name)
    if name in FX:
        img = FX[name](img, name)
    return img, cls


def sheet(imgs, path, cols=8, crop=None, zoom=2):
    tiles = []
    for im in imgs:
        t = im if crop is None else im[crop[1]:crop[3], crop[0]:crop[2]]
        a = t[..., 3:4] / 255.0
        rgb = (t[..., :3] * a + np.array([43, 37, 48]) * (1 - a)).astype(np.uint8)
        tiles.append(cv2.resize(rgb, (rgb.shape[1] * zoom, rgb.shape[0] * zoom), interpolation=cv2.INTER_NEAREST))
    blank = np.zeros_like(tiles[0])
    rows = [np.hstack(tiles[i:i + cols] + [blank] * (cols - len(tiles[i:i + cols]))) for i in range(0, len(tiles), cols)]
    cv2.imwrite(path, cv2.cvtColor(np.vstack(rows), cv2.COLOR_RGB2BGR))


# ------------------------------------------------------------------ 6. hands (procedural, see hands.py)
import hands as HN
import handgrids as HG  # noqa: E402

# pose per detected blob, left-to-right by blob x. "split" = one merged blob holding two hands (cheeks, clasp).
HAND_PLAN = {
    "01_radiant_joy": ["pray"], "05_pure_innocence": ["pray"], "19_desperate_pleading": ["pray"],
    "02_gentle_relief": ["cheek", "relaxed"],
    "04_confident_pride": ["gfist", "gfist"],
    "06_flustered_shyness": ["gfist", "gfist"], "13_nervous_anxiety": ["gfist", "gfist"],
    "08_deep_confusion": [{"pose": "point", "tip": (89, 65), "scale": 1.5}, "relaxed"],
    "11_sudden_shock": ["open", {"pose": "open", "scale": 2.1}],
    "12_exhausted_fatigue": ["relaxed", "neck", "relaxed"],
    "15_tearful_sorrow": [{"pose": "cheek", "wrist": (73, 81), "tip": (79, 51), "scale": 1.8}, "relaxed"],
    "16_bitter_breakdown": [[{"pose": "cheek", "wrist": (73, 81), "tip": (79, 51), "scale": 1.8},
                             {"pose": "cheek", "wrist": (111, 81), "tip": (105, 51), "scale": 1.8}]],
    "24_obsessive_yandere_blush": [[{"pose": "cheek", "wrist": (73, 81), "tip": (79, 51), "scale": 1.8},
                                    {"pose": "cheek", "wrist": (111, 81), "tip": (105, 51), "scale": 1.8}]],
    "17_fierce_anger": ["gfist", "gfist"],
    "18_visceral_disgust": ["open", "relaxed"],
    "21_red_eyed_knife_mania": [{"pose": "knife", "handle": (45, 73), "tip": (17, 124)}, "claw"],
    "26_sanity_break_twitch": ["claw", "claw"], "30_predatory_bloodlust": ["claw", "claw"],
    "28_manic_finger_biting": [{"pose": "point", "tip": (92, 60), "remouth": True}, "relaxed"],
}

_MODEL_LEN = {}


def _model_len(pose):
    if pose not in _MODEL_LEN:
        im, (wx, wy) = HN.render(pose, 0, False, 1.0)
        ys, xs = np.nonzero(im[..., 3])
        _MODEL_LEN[pose] = float(np.max(np.hypot(xs - wx, ys - wy)))
    return _MODEL_LEN[pose]


PASTED = np.zeros((344, 192), bool)   # pixels drawn by an earlier hand on the current sprite


def paste_hand(img, cls, pose, wrist, tip, scale=None, orig=None):
    wrist, tip = np.array(wrist, float), np.array(tip, float)
    v = tip - wrist
    dist = float(np.hypot(*v))
    ang = math.degrees(math.atan2(-v[0], v[1]))
    sc = scale or float(np.clip(dist / _model_len(pose), 1.85 if pose == "relaxed" else 1.45, 2.3))
    best = None
    for mir in (False, True):
        im, (wx, wy) = HN.render(pose, ang, mir, sc)
        # thumb toward the body midline: compare skin mass on each side of the hand axis
        ys, xs = np.nonzero(im[..., 3])
        side = ((xs - wx) * v[1] - (ys - wy) * v[0])
        thumb_side = np.sign(side.mean()) if pose != "relaxed" else 0
        mid = np.sign(96 - wrist[0]) * np.sign(v[1] if abs(v[1]) > abs(v[0]) else 1)
        score = thumb_side * mid
        if best is None or score > best[0]:
            best = (score, im, (wx, wy))
    _, im, (wx, wy) = best
    x0, y0 = int(round(wrist[0])) - wx, int(round(wrist[1])) - wy
    u = v / (dist + 1e-6)
    for y, x in np.argwhere(im[..., 3] > 0):
        Y, X = y + y0, x + x0
        if not (0 <= Y < H and 0 <= X < W):
            continue
        along = (X - wrist[0]) * u[0] + (Y - wrist[1]) * u[1]
        if along < -0.5 and orig is not None and orig[Y, X, 3] and cls[Y, X] in (2, 3, 7):
            continue  # stays inside the sleeve
        px_ = im[y, x].copy()
        if PASTED[Y, X] and tuple(px_[:3]) == tuple(hx("5a3236")):
            px_[:3] = hx("8a5f63")   # selective outline where this hand overlaps skin (the other hand)
        img[Y, X] = px_
        cls[Y, X] = 4
        PASTED[Y, X] = True


def _blob_mask(cls, bbox, grow_up=0, head_face=None):
    x, y, w, h = bbox
    m = np.zeros(cls.shape, bool)
    m[max(0, y - grow_up):y + h + 1, max(0, x - 1):x + w + 1] = True
    m &= cls == 4
    if head_face is not None:
        m &= ~head_face
    return m


def _wrist_and_tip(blob_px, wrist_px):
    w = np.array(wrist_px, float).mean(0) if len(wrist_px) else blob_px.mean(0)
    d = np.hypot(blob_px[:, 0] - w[0], blob_px[:, 1] - w[1])
    far = blob_px[d >= np.percentile(d, 92)].mean(0)
    return w, far


def draw_knife(img, cls, a, b, handle_frac=0.3):
    """Straight kitchen knife from handle end a to blade tip b: dark crimson handle, tapered steel blade."""
    a, b = np.array(a, float), np.array(b, float)
    L = float(np.hypot(*(b - a)))
    u = (b - a) / L
    n = np.array([-u[1], u[0]])
    steel = [hx(c) for c in HN.STEEL]
    for y in range(int(min(a[1], b[1])) - 4, int(max(a[1], b[1])) + 5):
        for x in range(int(min(a[0], b[0])) - 4, int(max(a[0], b[0])) + 5):
            p = np.array([x + 0.5, y + 0.5]) - a
            t, d = p @ u / L, p @ n
            if not (0 <= t <= 1):
                continue
            if t < handle_frac:
                half = 1.35
                col = hx("4d0f1a") if d < 0 else hx("1d0509")
            else:
                k = (t - handle_frac) / (1 - handle_frac)
                half = 1.9 * (1 - k ** 3) + 0.35
                col = steel[4] if d < -half + 0.9 else steel[3] if d < 0.2 else steel[2] if d < half - 0.7 else steel[1]
            if abs(d) <= half:
                img[y, x, :3] = col; img[y, x, 3] = 255; cls[y, x] = 9
    # outline around the knife
    m = cls == 9
    ring = (cv2.dilate(m.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~m & (cls != 4)
    img[ring, :3] = hx(OUTLINE); img[ring, 3] = 255
    # guard between handle and blade
    g = a + u * L * handle_frac
    for s_ in (-2, -1, 0, 1, 2):
        q = np.round(g + n * s_).astype(int)
        img[q[1], q[0], :3] = steel[2]; img[q[1], q[0], 3] = 255


def redraw_hands(img, cls, name, head_face, spec):
    import json as _json
    with open(os.path.join(HERE, "hands_found.json"), encoding="utf-8") as fh:
        found = _json.load(fh)[name]
    found = sorted(found, key=lambda h: h["bbox"][0])
    PASTED[:] = False
    plan = HAND_PLAN.get(name, ["relaxed"] * len(found))
    orig = img.copy()
    jobs = []
    skin_line = np.zeros(cls.shape, bool)
    for c in ("5a3236", OUTLINE):
        skin_line |= (img[..., :3] == hx(c)).all(-1)
    if name in NECK_FROM_BASE or "neck" in plan:
        x0, y0, x1, y1 = NECK_RECT.get(name, (78, 60, 107, 82))
        img[y0:y1, x0:x1] = BASE[0][y0:y1, x0:x1]
        cls[y0:y1, x0:x1] = BASE[1][y0:y1, x0:x1]
        # keep the canonical face itself (already drawn) above the chin
        hb = np.roll(np.roll(HEAD_IMG, 0, 0), 0, 1)
        top = (np.arange(H)[:, None] < HEAD_CUT) & (HEAD_CLS != 0)
        sel = np.zeros(cls.shape, bool); sel[y0:y1, x0:x1] = True; sel &= top & (FACE_IMG[..., 3] > 0)
        img[sel] = FACE_IMG[sel]
    for h, entry in zip(found, plan):
        if entry in ("skip", "neck"):
            continue
        entries = entry if isinstance(entry, list) else [entry]
        e0 = entries[0] if isinstance(entries[0], dict) else {"pose": entries[0]}
        near_face = isinstance(entry, list) or e0["pose"] in ("cheek", "point") or "remouth" in e0
        m = _blob_mask(cls, h["bbox"], 14 if near_face else 2, head_face)
        k_ = 7 if e0["pose"] == "pray" else 3     # the old clasp left outline ticks a few px out
        ring = cv2.dilate(m.astype(np.uint8), np.ones((k_, k_), np.uint8)) > 0
        erase = m | (ring & skin_line & (cls != 1))
        px = np.argwhere(m)[:, ::-1].astype(float)
        wr = np.array(h["wrist_px"], float)
        if e0["pose"] == "knife":
            # old knife: every dark pixel within 3 px of the knife line
            a, b = np.array(e0["handle"], float), np.array(e0["tip"], float)
            u = (b - a) / np.hypot(*(b - a)); n_ = np.array([-u[1], u[0]])
            for y in range(H):
                for x in range(W):
                    p = np.array([x, y], float) - a
                    t = p @ u
                    if 0 <= t <= np.hypot(*(b - a)) + 2 and abs(p @ n_) < 4.6 and img[y, x, 3]:
                        if img[y, x, :3].astype(int).sum() < 130 or tuple(img[y, x, :3]) == tuple(hx(RIM)):
                            erase[y, x] = True
            w_, _ = _wrist_and_tip(px, wr)
            g = a + u * np.hypot(*(b - a)) * 0.2
            jobs.append(("_knife", e0["handle"], e0["tip"], None))
            jobs.append(("fist", w_, g, 1.75))
        elif e0["pose"] == "pray":
            # palms pressed together at the chest, fingertips up (wrists/cuffs below, as in the source)
            bx, by, bw, bh = h["bbox"]
            g = HG.prayer()
            gw, gh = grid_size(g)
            jobs.append(("_grid", (g, int(round(bx + bw / 2 - gw / 2)), by, False), None, None))
        elif e0["pose"] == "gfist":
            bx, by, bw, bh = h["bbox"]
            w_ = wr.mean(0) if len(wr) else np.array([bx + bw / 2, by])
            down = w_[1] <= by + bh / 2
            g = HG.fist(knuckles_down=down)
            gw, gh = grid_size(g)
            mirror = (bx + bw / 2) > 96
            cxg = bx + bw / 2
            x0 = int(round(cxg - gw / 2))
            y0 = int(round(w_[1] - 1)) if down else int(round(w_[1] - gh + 1))
            y0 = min(max(y0, by - 1), by + bh - gh + 1)
            jobs.append(("_grid", (g, x0, y0, mirror), None, None))
        else:
            for e in entries:
                e = e if isinstance(e, dict) else {"pose": e}
                w_, t_ = _wrist_and_tip(px, wr)
                w_ = np.array(e.get("wrist", w_), float)
                t_ = np.array(e.get("tip", t_), float)
                jobs.append((e["pose"], w_, t_, e.get("scale")))
                if e.get("remouth"):
                    jobs.append(("_mouth", None, None, None))
        img[:] = inpaint_region(img, erase)
        for y, x in np.argwhere(erase):
            c = tuple(img[y, x, :3])
            cls[y, x] = 0 if img[y, x, 3] == 0 else next((k for k, r in ((1, "hair"), (2, "dress"), (3, "blouse"), (4, "skin"))
                                                         if c in {tuple(hx(q)) for q in RAMPS[r]}), 7)
    for pose, w_, t_, sc in jobs:
        if pose == "_grid":
            g, x0, y0, mir = w_
            before = img[..., 3].copy(), img[..., :3].copy()
            put(img, g, x0, y0, mir)
            changed = (img[..., :3] != before[1]).any(-1) | (img[..., 3] != before[0])
            cls[changed] = 4
            PASTED[changed] = True
        elif pose == "_knife":
            draw_knife(img, cls, w_, t_)
        elif pose == "_mouth":
            m = F.MOUTHS[spec.get("mouth", "closed")]
            put(img, m, F.MOUTH_C[0] - grid_size(m)[0] // 2, F.MOUTH_C[1])
        else:
            paste_hand(img, cls, pose, w_, t_, sc, orig)


# braid sections that cross the dark dress and lose their shape there: (y0, y1, x0, x1)
BRAID = {"06_flustered_shyness": (80, 140, 86, 114)}


def retexture_braid(img, cls, name):
    """Repaint a braid as chevron lobes (crease, lit lobe top, red sheen) so it reads on the dark dress."""
    if name not in BRAID:
        return
    y0, y1, x0, x1 = BRAID[name]
    hair = [hx(c) for c in RAMPS["hair"]]
    m = np.zeros(cls.shape, bool)
    m[y0:y1, x0:x1] = cls[y0:y1, x0:x1] == 1
    k, lab, st, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8), connectivity=8)
    for i in range(1, k):
        if st[i, 4] < 6:
            m[lab == i] = False
    edge = m & ~(cv2.erode(m.astype(np.uint8), np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], np.uint8)) > 0)
    for y in range(y0, y1):
        xs = np.nonzero(m[y])[0]
        if len(xs) == 0:
            continue
        c, half = (xs.min() + xs.max()) / 2, max((xs.max() - xs.min()) / 2, 1)
        for x in xs:
            u = (x - c) / half
            ph = (y + abs(x - c) * 0.9) % 5
            if edge[y, x]:
                col = hair[0]
            elif ph < 1:
                col = hair[1]
            elif ph < 2:
                col = hair[5] if u < -0.15 else hair[4]
            elif u > 0.55:
                col = hair[2]
            else:
                col = hair[3]
            img[y, x, :3] = col


# per-sprite touch-ups found in the zoomed QA pass
#   "hairfix": boxes where fabric-coloured specks inside hair (misclassified strands) go to the matching hair shade
#   "clear":   boxes where leftover fabric/outline scraps of an erased hand become background
TOUCHUP = {
    "22_unhinged_jaw_laugh": {"hairfix": [(104, 14, 124, 52), (56, 14, 79, 52)]},
    "06_flustered_shyness": {"skin2hair": [(97, 98, 101, 102)]},
    "01_radiant_joy": {"refill": [(81, 84, 87, 92), (95, 81, 100, 89)]},
    "12_exhausted_fatigue": {"clear": [(50, 202, 62, 210), (117, 202, 126, 211)],
                             "bridge": [(57, 79, 70, 89, "L"), (116, 79, 130, 89, "R")],
                             "rowcopy": [(90, 89, 66, 118), (91, 92, 66, 118)]},
    "16_bitter_breakdown": {"bridge": [(58, 81, 67, 94, "L")], "deoutline": [(63, 76, 70, 87), (64, 95, 64, 95)]},
    "21_red_eyed_knife_mania": {"blade_edge": [(10, 99, 30, 126)],
                                "pixels": [(36, 97, OUTLINE), (36, 98, OUTLINE), (37, 98, OUTLINE), (35, 99, OUTLINE),
                                           (37, 99, OUTLINE), (34, 100, OUTLINE), (35, 100, OUTLINE), (36, 100, OUTLINE)]},
    "24_obsessive_yandere_blush": {"bridge": [(58, 81, 67, 94, "L")], "deoutline": [(63, 76, 70, 87), (64, 95, 64, 95)]},
    # 11: the raised hand meets a full-width cuff (the source sleeve tapered to a point under it)
    "11_sudden_shock": {"pixels": [(126, 92, OUTLINE), (127, 92, "b3313a"), (128, 92, "b3313a"), (129, 92, "b3313a"), (130, 92, "b3313a"), (131, 92, "b3313a"), (132, 92, "b3313a"), (133, 92, "b3313a"), (134, 92, "b3313a"), (135, 92, "b3313a"), (136, 92, OUTLINE), (126, 93, OUTLINE), (127, 93, "8f1f2c"), (128, 93, "8f1f2c"), (129, 93, "8f1f2c"), (130, 93, "8f1f2c"), (131, 93, "8f1f2c"), (132, 93, "8f1f2c"), (133, 93, "8f1f2c"), (134, 93, "8f1f2c"), (135, 93, "8f1f2c"), (136, 93, OUTLINE), (126, 94, OUTLINE), (127, 94, "6c1522"), (128, 94, "6c1522"), (129, 94, "6c1522"), (130, 94, "6c1522"), (131, 94, "6c1522"), (132, 94, "6c1522"), (133, 94, "6c1522"), (134, 94, "6c1522"), (135, 94, "6c1522"), (136, 94, OUTLINE), (133, 95, "1d0509"), (134, 95, "1d0509"), (135, 95, "1d0509"), (136, 95, OUTLINE), (134, 96, "1d0509"), (135, 96, "1d0509"), (136, 96, OUTLINE)]},
    "18_visceral_disgust": {"pixels": [(55, 75, None), (55, 76, None), (56, 76, None), (55, 77, None), (56, 77, None),
                                       (55, 78, None), (56, 78, None), (56, 79, None)]},
    "05_pure_innocence": {"refill": [(81, 84, 87, 92), (95, 81, 100, 89)]},
    "19_desperate_pleading": {"refill": [(81, 83, 87, 91), (95, 80, 100, 88)]},
    "14_quiet_melancholy": {"pixels": [(141, 196, None), (40, 172, OUTLINE), (41, 172, OUTLINE)]},
    "26_sanity_break_twitch": {"refill_sleeve": [(124, 167, 132, 184)]},
    "30_predatory_bloodlust": {"refill_sleeve": [(124, 167, 132, 184)]},
}


def touchup(img, cls, name):
    t = TOUCHUP.get(name, {})
    hair = [hx(c) for c in RAMPS["hair"]]
    remap = {tuple(hx(c)): hair[i] for i, c in enumerate(RAMPS["dress"])}
    remap.update({tuple(hx(c)): hair[min(i + 1, 5)] for i, c in enumerate(RAMPS["blouse"])})
    for x0, y0, x1, y1 in t.get("hairfix", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                c = tuple(img[y, x, :3])
                if img[y, x, 3] and c in remap:
                    img[y, x, :3] = remap[c]
                    cls[y, x] = 1
        # no rim light on hands (the procedural hands have none): crimson rim pixels touching skin -> outline
        skin = {tuple(hx(q)) for q in RAMPS["skin"]}
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if tuple(img[y, x, :3]) == tuple(hx(RIM)) and any(
                        tuple(img[y + j, x + i, :3]) in skin for j, i in ((0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1))):
                    img[y, x, :3] = hx(OUTLINE)
    fabric = {tuple(hx(c)) for c in RAMPS["blouse"] + RAMPS["dress"]} | {tuple(hx(OUTLINE))}
    cleared = np.zeros(cls.shape, bool)
    for x0, y0, x1, y1 in t.get("clear", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if img[y, x, 3] and tuple(img[y, x, :3]) in fabric:
                    img[y, x, 3] = 0
                    cls[y, x] = 0
                    cleared[y, x] = True
    # fabric left next to a cleared area gets a proper outline edge
    near = (cv2.dilate(cleared.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~cleared & (img[..., 3] > 0)
    for y, x in np.argwhere(near):
        if cls[y, x] in (2, 3):
            img[y, x, :3] = hx(OUTLINE)
    # dark leftovers of an erased outline sitting on fabric -> refilled from the surrounding fabric
    refill = np.zeros(cls.shape, bool)
    for x0, y0, x1, y1 in t.get("refill", []):
        reg = img[y0:y1 + 1, x0:x1 + 1]
        refill[y0:y1 + 1, x0:x1 + 1] = (reg[..., :3].astype(int).sum(-1) < 60) & (reg[..., 3] > 0) & (cls[y0:y1 + 1, x0:x1 + 1] != 4)
    # a strip of old forearm sleeve filling the arm-to-body gap -> the skirt/cuff around it
    blouse_c = {tuple(hx(c)) for c in RAMPS["blouse"]}
    for x0, y0, x1, y1 in t.get("refill_sleeve", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if img[y, x, 3] and tuple(img[y, x, :3]) in blouse_c:
                    refill[y, x] = True
    if refill.any():
        img[:] = inpaint_region(img, refill)
        cls[refill] = 2
    # a sleeve split from the body by a see-through slit: fill the slit (and the outlines inside it) with
    # sleeve; the outer edge keeps its outline and rim; a filled pixel under background becomes outline
    blouse_c = {tuple(hx(c)) for c in RAMPS["blouse"]}
    for x0, y0, x1, y1, side in t.get("bridge", []):
        filled = np.zeros(cls.shape, bool)
        for y in range(y0, y1 + 1):
            xs = [x for x in range(x0, x1 + 1) if img[y, x, 3]]
            if len(xs) < 2:
                continue
            a, b = xs[0], xs[-1]
            keep = {a} if side == "L" else {b}
            nxt = a + 1 if side == "L" else b - 1
            if tuple(img[y, nxt, :3]) == tuple(hx(RIM)):
                keep.add(nxt)
            row = [tuple(img[y, x, :3]) for x in range(a, b + 1) if img[y, x, 3] and tuple(img[y, x, :3]) in blouse_c]
            fillc = np.array(max(set(row), key=row.count) if row else hx(RAMPS["blouse"][4]), np.uint8)
            for x in range(a, b + 1):
                if x in keep:
                    continue
                c = tuple(img[y, x, :3])
                if not img[y, x, 3] or c in (tuple(hx(OUTLINE)), tuple(hx(RIM))):
                    img[y, x, :3] = fillc; img[y, x, 3] = 255; cls[y, x] = 3; filled[y, x] = True
        for y, x in np.argwhere(filled):
            if not img[y - 1, x, 3]:
                img[y, x, :3] = hx(OUTLINE); cls[y, x] = 7
    # knife blade: the keyed-out edge left a doubled, gappy outline -> one outline pixel against the steel per row
    steel = {tuple(hx(c)) for c in HN.STEEL}
    for x0, y0, x1, y1 in t.get("blade_edge", []):
        for y in range(y0, y1 + 1):
            xs = [x for x in range(x0, x1 + 1) if img[y, x, 3] and tuple(img[y, x, :3]) in steel]
            if not xs:
                continue
            for x in range(x0, xs[0] - 1):
                if img[y, x, 3] and tuple(img[y, x, :3]) == tuple(hx(OUTLINE)):
                    img[y, x, 3] = 0; cls[y, x] = 0
            img[y, xs[0] - 1, :3] = hx(OUTLINE); img[y, xs[0] - 1, 3] = 255
    # a seam row of misplaced pixels -> copy the clean row next to it (hair/braid pixels untouched)
    hair_c = {tuple(hx(c)) for c in RAMPS["hair"]}
    for y, src, x0, x1 in t.get("rowcopy", []):
        for x in range(x0, x1 + 1):
            if tuple(img[y, x, :3]) not in hair_c and tuple(img[src, x, :3]) not in hair_c and img[src, x, 3]:
                img[y, x] = img[src, x]; cls[y, x] = cls[src, x]
    for x, y, c in t.get("pixels", []):
        if c is None:
            img[y, x, 3] = 0; cls[y, x] = 0
        else:
            img[y, x, :3] = hx(c); img[y, x, 3] = 255; cls[y, x] = 7
    for x0, y0, x1, y1 in t.get("skin2hair", []):
        skin_c = {tuple(hx(q)) for q in RAMPS["skin"]}
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if tuple(img[y, x, :3]) in skin_c:
                    img[y, x, :3] = hair[2]
                    cls[y, x] = 1


# forearms lost in the source cutout (white sleeves on a white background): elbow -> wrist, sleeve half-width
FOREARMS = {"22_unhinged_jaw_laugh": [((33, 71), (67, 51), 4.6), ((150, 71), (116, 48), 4.6)],
            # prayer hands: forearm tips up to the wrists under the pressed palms
            "01_radiant_joy": [((83, 115), (87, 103), 3.4), ((99, 115), (95, 103), 3.4)],
            "05_pure_innocence": [((83, 115), (87, 103), 3.4), ((99, 115), (95, 103), 3.4)],
            "19_desperate_pleading": [((83, 113), (87, 102), 3.4), ((99, 113), (95, 102), 3.4)],
            # 06 holds her braid at the chest: elbows at the sleeve ends up to the fists
            "06_flustered_shyness": [((67, 129), (86, 113), 4.2), ((124, 131), (107, 118), 4.2)]}


def draw_forearms(img, cls, name):
    """Charcoal sleeve capsule with a crimson cuff at the wrist, outlined; never drawn over skin (hands, face)."""
    blouse = [hx(c) for c in RAMPS["blouse"]]
    dress = [hx(c) for c in RAMPS["dress"]]
    for (ax, ay), (bx, by), r in FOREARMS.get(name, []):
        a, b = np.array([ax, ay], float), np.array([bx, by], float)
        L = float(np.hypot(*(b - a))); u = (b - a) / L; n = np.array([-u[1], u[0]])
        if n[1] > 0:
            n = -n                         # n points up: the lit side of the sleeve
        m = np.zeros(cls.shape, bool)
        col = {}
        for y in range(int(min(ay, by) - r - 2), int(max(ay, by) + r + 3)):
            for x in range(int(min(ax, bx) - r - 2), int(max(ax, bx) + r + 3)):
                p = np.array([x + 0.5, y + 0.5]) - a
                t = float(np.clip(p @ u, 0, L))
                d = p - u * t
                if np.hypot(*d) > r or cls[y, x] == 4:
                    continue
                m[y, x] = True
                side = float(d @ n) / r     # +1 lit top edge .. -1 underside
                cuff = t > L - 3.2
                ramp = dress[2:6] if cuff else blouse[0:5]
                k = 3 if side > 0.45 else 2 if side > -0.2 else 1 if side > -0.7 else 0
                col[(y, x)] = ramp[min(k, len(ramp) - 1)]
        for (y, x), c in col.items():
            img[y, x, :3] = c; img[y, x, 3] = 255; cls[y, x] = 3
        ring = (cv2.dilate(m.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~m & (cls != 4)
        # keep the outline off the joint with the existing upper sleeve
        upper = np.zeros(cls.shape, bool)
        upper[int(ay - r - 2):int(ay + r + 3), int(ax - r - 2):int(ax + r + 3)] = True
        ring &= ~(upper & (img[..., 3] > 0) & np.isin(cls, [2, 3]))
        img[ring, :3] = hx(OUTLINE); img[ring, 3] = 255


def drop_stray_iris(img, cls):
    """Collar details the source pass mis-read as eye: iris colours below the face -> surrounding fabric/skin."""
    eye = {tuple(hx(c)) for c in ("2a0408", "5c0a12", "9b1420", "d8323a", "ff7a6e")}
    m = np.zeros(cls.shape, bool)
    for y in range(66, 86):
        for x in range(78, 110):
            if img[y, x, 3] and tuple(img[y, x, :3]) in eye:
                m[y, x] = True
    if m.any():
        img[:] = inpaint_region(img, m)
        cls[m] = 3


def square_sock_cuffs(img, cls):
    """The skin/sock boundary wanders over a few rows (drips both ways). Per leg: one cuff row (the median first
    sock row); skin above it, sock below it, a darker cuff edge on it; leg-edge pixels keep the outline."""
    skin = {tuple(hx(c)) for c in RAMPS["skin"]} | {tuple(hx("5a3236"))}
    sock = {tuple(hx(c)) for c in RAMPS["blouse"]}
    blouse = [hx(c) for c in RAMPS["blouse"]]
    y0, y1 = 228, 275
    a = img[y0:y1, :, 3] > 0
    xs = np.nonzero(a.any(0))[0]
    if not len(xs):
        return
    lo, hi = xs.min(), xs.max()
    split = min(range(lo + (hi - lo) * 3 // 10, lo + (hi - lo) * 7 // 10 + 1), key=lambda x: (a[:, x].sum(), abs(x - (lo + hi) / 2)))
    edge = lambda y, x: not (img[y, x - 1, 3] and img[y, x + 1, 3])
    for x_lo, x_hi in ((lo, split), (split + 1, hi + 1)):
        first = {}
        for x in range(x_lo, x_hi):
            for y in range(y0, y1 - 3):
                if all(img[y + k, x, 3] and tuple(img[y + k, x, :3]) in sock for k in range(3)):
                    first[x] = y
                    break
        if len(first) < 4:
            continue
        cuff = int(np.median(list(first.values())))
        cols = [x for x in range(x_lo, x_hi) if img[cuff, x, 3]]
        if not cols:
            continue
        for y in list(range(cuff - 5, cuff)) * 2:            # above the cuff (twice: specks 2 px tall): skin, sock specks take the skin above
            for x in cols:
                if img[y, x, 3] and (tuple(img[y, x, :3]) in sock or tuple(img[y, x, :3]) == tuple(hx(OUTLINE))) \
                        and not edge(y, x) and not edge(y, x - 1) and not edge(y, x + 1):
                    up = img[y - 1, x, :3]
                    if tuple(up) in skin and tuple(up) != tuple(hx("5a3236")):
                        img[y, x, :3] = up; cls[y, x] = 4
        for y in range(cuff, min(cuff + 10, y1)):            # below: sock
            row = [tuple(img[y, x, :3]) for x in cols if img[y, x, 3] and tuple(img[y, x, :3]) in sock]
            fillc = np.array(max(set(row), key=row.count) if row else blouse[4], np.uint8)
            for x in range(x_lo, x_hi):
                if img[y, x, 3] and tuple(img[y, x, :3]) in skin:
                    img[y, x, :3] = hx(OUTLINE) if edge(y, x) else fillc
                    cls[y, x] = 7 if edge(y, x) else 3
        for x in cols:                                       # crisp cuff edge
            if img[cuff, x, 3] and tuple(img[cuff, x, :3]) in sock and not edge(cuff, x):
                img[cuff, x, :3] = blouse[1]; cls[cuff, x] = 3


def seal_slits(img, cls):
    """1-px see-through slits between two outlines (arm against body) -> outline: a crease, not a hole."""
    o = tuple(hx(OUTLINE))
    fabric = {tuple(hx(c)) for c in RAMPS["blouse"] + RAMPS["dress"]}
    for y in range(90, 245):
        for x in range(1, W - 1):
            if not img[y, x, 3] and img[y, x - 1, 3] and img[y, x + 1, 3] \
                    and tuple(img[y, x - 1, :3]) == o and tuple(img[y, x + 1, :3]) == o:
                img[y, x, :3] = o; img[y, x, 3] = 255; cls[y, x] = 7
    # tiny enclosed see-through pockets (ends of arm gaps, finger crooks) read as holes -> outline
    m = (img[..., 3] == 0).astype(np.uint8)
    k, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4)
    border = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
    for i in range(1, k):
        if i not in border and st[i, 4] <= 12:
            comp = lab == i
            ring = (cv2.dilate(comp.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~comp
            vals = [tuple(v) for v in img[ring][:, :3]]
            fab = [v for v in vals if v in fabric]
            if len(fab) >= 0.5 * len(vals):        # a pocket inside cloth: the cloth closes over it
                img[comp, :3] = max(set(fab), key=fab.count); cls[comp] = 3
            else:
                img[comp, :3] = o; cls[comp] = 7
            img[comp, 3] = 255


def deoutline(img, cls, name):
    """Outline clumps inside fabric (old edges, sealed pockets): only pixels touching background stay outline.
    Runs after seal_slits so it also sees the pockets that pass closed."""
    t = TOUCHUP.get(name, {})
    blouse_c = {tuple(hx(c)) for c in RAMPS["blouse"]}
    for x0, y0, x1, y1 in t.get("deoutline", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if tuple(img[y, x, :3]) != tuple(hx(OUTLINE)) or not img[y, x, 3]:
                    continue
                if any(not img[y + j, x + i, 3] for j, i in ((0, 1), (1, 0), (0, -1), (-1, 0))):
                    continue
                nb = [tuple(img[y + j, x + i, :3]) for j in range(-2, 3) for i in range(-2, 3)
                      if img[y + j, x + i, 3] and tuple(img[y + j, x + i, :3]) in blouse_c]
                img[y, x, :3] = max(set(nb), key=nb.count) if nb else hx(RAMPS["blouse"][4]); cls[y, x] = 3


def fill_feet(img, cls):
    """The reference's white socks were keyed out with the background, leaving the shoe insteps see-through.
    Per foot: fill the gap inside the shoe's convex outline with charcoal sock, cross it with a crimson
    Mary-Jane strap, and close the shoe outline."""
    blouse = [hx(c) for c in RAMPS["blouse"]]
    dress = [hx(c) for c in RAMPS["dress"]]
    y0 = 290
    a = img[y0:, :, 3] > 0
    xs = np.nonzero(a.any(0))[0]
    if not len(xs):
        return
    lo, hi = xs.min(), xs.max()
    mid = range(lo + (hi - lo) * 3 // 10, lo + (hi - lo) * 7 // 10 + 1)
    split = min(mid, key=lambda x: (a[:, x].sum(), abs(x - (lo + hi) / 2)))
    for x_lo, x_hi in ((0, split), (split + 1, W)):
        foot = np.zeros(a.shape, bool); foot[:, x_lo:x_hi] = a[:, x_lo:x_hi]
        rows = np.nonzero(foot.any(1))[0]
        if not len(rows):
            continue
        top = max(rows.max() - 24, 0)
        foot[:top] = False
        pts = np.argwhere(foot)[:, ::-1].astype(np.int32)
        if len(pts) < 10:
            continue
        hull = np.zeros(a.shape, np.uint8)
        cv2.fillConvexPoly(hull, cv2.convexHull(pts), 1)
        hull = hull > 0
        hull[:, :x_lo] = False; hull[:, x_hi:] = False
        holes = hull & ~a
        if holes.sum() < 6:
            continue
        hy, hxs = np.nonzero(holes)
        cx = (hxs.min() + hxs.max()) / 2; half = max((hxs.max() - hxs.min()) / 2, 1)
        strap = hy.min() + 2
        edge = hull & ~(cv2.erode(hull.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
        for y, x in zip(hy, hxs):
            Y = y + y0
            if edge[y, x] or y in (strap, strap + 3):
                c, k = hx(OUTLINE), 7
            elif y in (strap + 1, strap + 2):
                c, k = dress[4 if y == strap + 1 else 3], 2
            else:
                d = abs(x - cx) / half       # rounded sock: lit centre, darker sides
                c, k = blouse[3 if d < 0.35 else 2 if d < 0.75 else 1], 3
            img[Y, x, :3] = c; img[Y, x, 3] = 255; cls[Y, x] = k


def clean_specks(img, cls, max_area=30):
    """Skin/white specks stranded on sleeves and socks (fold highlights mis-read as skin) -> fabric colour."""
    skin = {tuple(hx(c)) for c in RAMPS["skin"]}
    fabric = {tuple(hx(c)) for c in RAMPS["blouse"] + RAMPS["dress"]} | {tuple(hx(OUTLINE))}
    rgb = img[..., :3]
    m = np.zeros(cls.shape, np.uint8)
    for y, x in np.argwhere(img[..., 3] > 0):
        if tuple(rgb[y, x]) in skin or tuple(rgb[y, x]) == tuple(hx("5a3236")):
            m[y, x] = 1
    m[:70] = 0
    k, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    for i in range(1, k):
        if st[i, 4] > max_area:
            continue
        comp = lab == i
        ring = (cv2.dilate(comp.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~comp
        vals = [tuple(v) for v in rgb[ring & (img[..., 3] > 0)]]
        fab = [v for v in vals if v in fabric and v != tuple(hx(OUTLINE))]
        if len(vals) and len(fab) >= 0.6 * len(vals):
            best = max(set(fab), key=fab.count)
            img[comp, :3] = best
            cls[comp] = 3


def fix_sock_tops(img, cls):
    """Knee skin leaking under the sock cuff -> sock colour (top-down per column)."""
    skin = {tuple(hx(c)) for c in RAMPS["skin"]} | {tuple(hx("5a3236"))}
    sock = {tuple(hx(c)) for c in RAMPS["blouse"]}
    for x in range(W):
        for y in range(205, H):
            if img[y, x, 3] and tuple(img[y, x, :3]) in skin:
                above = [img[y - k, x] for k in (1, 2, 3) if img[y - k, x, 3] and tuple(img[y - k, x, :3]) in sock]
                if above:
                    img[y, x] = above[0]; cls[y, x] = 3


def drop_dark_orphans(img, cls, y_min=70, max_area=48):
    rgb = img[..., :3].astype(int)
    dark = (rgb.sum(-1) < 90) & (img[..., 3] > 0)
    dark[:y_min] = False
    skin = {tuple(hx(c)) for c in RAMPS["skin"]} | {tuple(hx("5a3236"))}
    k, lab, st, _ = cv2.connectedComponentsWithStats(dark.astype(np.uint8), connectivity=8)
    for i in range(1, k):
        if st[i, 4] > max_area:
            continue
        comp = lab == i
        ring = (cv2.dilate(comp.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~comp
        if PASTED[ring].sum() >= 0.5 * ring.sum():
            continue   # this hugs a newly drawn hand: its outline, not a loose scrap
        ok = True
        n_t = 0
        for y, x in np.argwhere(ring):
            if img[y, x, 3] == 0:
                n_t += 1
            elif tuple(img[y, x, :3]) not in skin:
                ok = False; break
        if ok and n_t:
            img[comp, 3] = 0; cls[comp] = 0
            # the hand edge that was hidden behind the blob needs its outline back
            a = img[..., 3] > 0
            edge = a & (cv2.dilate(comp.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
            img[edge, :3] = hx("5a3236")


def erode_unoutlined_skin(img, cls, y_min=66, iters=4):
    """Every legit skin edge carries an outline; skin touching transparency directly is a stub left from an old hand."""
    skin = {tuple(hx(c)) for c in RAMPS["skin"]}
    for _ in range(iters):
        a = img[..., 3] > 0
        pad = np.pad(~a, 1)
        touch = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
        kill = []
        for y, x in np.argwhere(a & touch):
            if y >= y_min and tuple(img[y, x, :3]) in skin:
                kill.append((y, x))
        if not kill:
            break
        for y, x in kill:
            img[y, x, 3] = 0; cls[y, x] = 0


def _rng(name):
    return np.random.default_rng(sum(map(ord, name)))


def fx_glitch(img, name):
    """29: slice displacement, crimson/ice channel ghosts, scanline dropout. Stays inside the palette family."""
    r = _rng(name)
    out = img.copy()
    y = 0
    while y < H:
        h = int(r.integers(2, 9))
        if r.random() < 0.28:
            dx = int(r.choice([-5, -3, -2, 2, 3, 4, 6]))
            out[y:y + h] = np.roll(img[y:y + h], dx, axis=1)
        y += h
    a = out[..., 3] > 0
    ghost_r = np.roll(a, -2, 1) & ~a
    ghost_c = np.roll(a, 2, 1) & ~a
    out[ghost_r, :3] = hx("d8323a"); out[ghost_r, 3] = 255
    out[ghost_c, :3] = hx("7fd8e0"); out[ghost_c, 3] = 200
    for yy in range(0, H, 3):
        if r.random() < 0.35:
            row = out[yy, :, :3].astype(np.int32)
            out[yy, :, :3] = (row * 0.55).astype(np.uint8)
    # a few dead blocks
    for _ in range(9):
        bx, by = int(r.integers(30, 160)), int(r.integers(20, 320))
        bw, bh = int(r.integers(3, 12)), int(r.integers(1, 3))
        m = out[by:by + bh, bx:bx + bw, 3] > 0
        blk = out[by:by + bh, bx:bx + bw]
        blk[m, :3] = hx(r.choice(["07040a", "fbe9e0", "d8323a"]))
    return out


def fx_aura(img, name):
    """30: a pixel-art blood aura licking upward around the silhouette, dithered, behind the character."""
    r = _rng(name)
    a = (img[..., 3] > 0).astype(np.uint8)
    dist = cv2.distanceTransform(1 - a, cv2.DIST_L2, 3)
    cols = [hx("b3313a"), hx("8f1f2c"), hx("6c1522"), hx("4d0f1a"), hx("330a12")]
    # upward tongues: per column, a random extra reach above the silhouette
    reach = np.zeros(W)
    for x in range(W):
        reach[x] = r.choice([0, 1, 2, 3, 5, 8, 12])
    reach = np.convolve(reach, [0.25, 0.5, 0.25], mode="same")
    out = img.copy()
    top = np.full(W, H)
    for x in range(W):
        ys = np.nonzero(a[:, x])[0]
        if len(ys):
            top[x] = ys[0]
    for y in range(H):
        for x in range(W):
            if a[y, x]:
                continue
            d = dist[y, x]
            lim = 4.5 + (reach[x] if y < top[x] + 2 else 0) * 1.0
            if y < top[x]:
                d = max(d, 0.6 * (top[x] - y))
            if d <= lim:
                k = min(4, int(d / lim * 5))
                if k >= 3 and (x + y) % 2:
                    continue  # dithered fade
                out[y, x, :3] = cols[k]; out[y, x, 3] = 255
    # drips from the hands
    for _ in range(6):
        x = int(r.choice([36, 40, 44, 140, 145, 150])) + int(r.integers(-2, 3))
        ys = np.nonzero(img[:, x, 3])[0]
        ys = ys[(ys > 180) & (ys < 215)]
        if len(ys):
            y0 = ys.max()
            for k in range(1, int(r.integers(3, 8))):
                if y0 + k < H and out[y0 + k, x, 3] == 0 or (y0 + k < H and not a[y0 + k, x]):
                    out[y0 + k, x, :3] = hx("8f1f2c" if k < 3 else "6c1522"); out[y0 + k, x, 3] = 255
    return out


FX = {"29_glitching_distortion": fx_glitch, "30_predatory_bloodlust": fx_aura}


def upscale(img, k=4):
    return cv2.resize(img, (img.shape[1] * k, img.shape[0] * k), interpolation=cv2.INTER_NEAREST)


def write_palette(out_dir):
    pal = {k: v for k, v in RAMPS.items()}
    pal.update({"outline": [OUTLINE, "5a3236"], "rim": [RIM], "steel": HN.STEEL,
                "eye_white": ["e6d6dc"], "face_shadow": ["3a2228"],
                "fx": ["d8323a", "7fd8e0", "ff3b3b", "e8a0a0", "d77a80", "a8d8ff", "6fa8dc"]})
    with open(os.path.join(out_dir, "palette.json"), "w", encoding="utf-8") as fh:
        json.dump(pal, fh, indent=1)
    with open(os.path.join(out_dir, "leila.gpl"), "w", encoding="utf-8") as f:
        f.write("GIMP Palette\nName: Leila-chan\nColumns: 8\n#\n")
        for group, cols in pal.items():
            for c in cols:
                r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
                f.write(f"{r:3d} {g:3d} {b:3d}\t{group}_{c}\n")


if __name__ == "__main__":
    px_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    base, bcls = load_px(px_dir, "00_base_reference")
    head, hcls = build_head(base, bcls)
    HEAD_CLS = hcls
    HEAD_IMG = head
    BASE = (base, bcls)
    names = sys.argv[3:] or list(SPRITES)
    done = []
    final = "--final" in names
    names = [n for n in names if n != "--final"] or list(SPRITES)
    for sub in ("px", "x4"):
        os.makedirs(os.path.join(out_dir, sub), exist_ok=True)
    for n in names:
        img, cls = finish(px_dir, n, head, hcls)
        cv2.imwrite(os.path.join(out_dir, "px", n + ".png"), cv2.cvtColor(img, cv2.COLOR_RGBA2BGRA))
        cv2.imwrite(os.path.join(out_dir, "x4", n + ".png"), cv2.cvtColor(upscale(img), cv2.COLOR_RGBA2BGRA))
        if not final:
            np.save(os.path.join(out_dir, n + ".cls.npy"), cls)
        done.append(img)
    write_palette(out_dir)
    sheet(done, os.path.join(out_dir, "sheet_faces.png"), crop=(60, 16, 132, 80), zoom=4)
    sheet(done, os.path.join(out_dir, "sheet_bodies.png"), cols=11, zoom=2)
