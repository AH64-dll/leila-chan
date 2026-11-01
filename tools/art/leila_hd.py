"""HD finishing pass for the Leila-chan sprites: 384x688 native pixel art, shown at 2x (768x1376) in game.

Stage 1 (`LEILA_SCALE=2 python3 leila_px.py <src> <px_dir>`) keeps the source drawing's own faces, fingers
and folds at twice the old resolution and maps them onto the black/red palette. This pass does what the drawing
can't: the original cracked-heart clip in place of the old logo, steel for the knife, hole/speck hygiene,
the per-sprite fixes, and the coded effects on 29 (glitch) and 30 (blood aura).

    python3 leila_hd.py <px_dir> <out_dir> [names...]     -> out_dir/px (384x688), out_dir/x2 (768x1376), sheets
"""
import os
import sys

os.environ.setdefault("LEILA_SCALE", "2")
sys.path.insert(0, os.path.dirname(__file__))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from leila_px import RAMPS, OUTLINE, hx, W, H  # noqa: E402
import leila_finish as LF  # noqa: E402  (inpaint_region, write_palette)
from hands import STEEL  # noqa: E402

assert (W, H) == (384, 688), "run with LEILA_SCALE=2"

SKIN_OUT = "5a3236"
FABRIC = {tuple(hx(c)) for k in ("dress", "blouse", "hair") for c in RAMPS[k]}


def load(px_dir, name):
    img = cv2.cvtColor(cv2.imread(os.path.join(px_dir, name + ".png"), cv2.IMREAD_UNCHANGED), cv2.COLOR_BGRA2RGBA)
    return img, np.load(os.path.join(px_dir, name + ".cls.npy"))


def edge_of(a):
    pad = np.pad(a, 1)
    return a & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])


# ------------------------------------------------------------------ 1. the clip: original cracked crimson heart
def heart_sprite(w):
    """Procedural pixel heart, w px wide: outline, dithered 5-step crimson shading lit from the upper left,
    a specular glint, a zig-zag crack from the notch and one drop of blood from the tip."""
    R = w / 2.3
    hh = int(np.ceil(2.3 * R)) + 1
    ins = np.zeros((hh, w), bool)
    X = np.zeros((hh, w)); Y = np.zeros((hh, w))
    for j in range(hh):
        for i in range(w):
            x = (i + 0.5 - w / 2) / R
            y = 1.22 - (j + 0.5) / R
            X[j, i], Y[j, i] = x, y
            ins[j, i] = (x * x + y * y - 1) ** 3 - x * x * y ** 3 <= 0
    out = np.zeros((hh + 7, w, 4), np.uint8)
    dist = cv2.distanceTransform(ins.astype(np.uint8), cv2.DIST_L2, 3)
    val = 0.5 * np.clip(dist / max(dist.max(), 1), 0, 1) + 0.5 * np.clip((-0.45 * X + 0.55 * Y + 0.6) / 1.6, 0, 1)
    ramp = [hx(c) for c in RAMPS["dress"][1:]]                  # 330a12 .. b3313a
    bayer = np.array([[0, 2], [3, 1]]) / 4.0 - 0.375
    for j, i in np.argwhere(ins):
        k = int(np.clip(round(val[j, i] * (len(ramp) - 1) + 0.5 * bayer[j % 2, i % 2]), 0, len(ramp) - 1))
        out[j, i, :3] = ramp[k]
        out[j, i, 3] = 255
    glint = ins & (((X + 0.55) / 0.2) ** 2 + ((Y - 0.62) / 0.13) ** 2 <= 1)
    body = out[:hh]
    body[glint, :3] = hx("ff7a6e")
    # crack: from the notch down to ~60% of the height, 1px dark with a lit lip on its right
    cx = w // 2
    top = int(np.argmax(ins[:, cx]))
    x, path = cx, []
    for n, y in enumerate(range(top, int(hh * 0.62))):
        if n % 3 == 2:
            x += (-2, 1, 2, -1)[(n // 3) % 4]
        path.append((y, x))
    for y, x in path:
        if ins[y, x]:
            out[y, x, :3] = hx(RAMPS["dress"][0])
            if x + 1 < w and ins[y, x + 1]:
                out[y, x + 1, :3] = hx(RAMPS["dress"][5])
    e = edge_of(ins)
    body[e, :3] = hx(OUTLINE)
    # one drop of blood hanging from the tip
    tip = int(np.nonzero(ins[:, cx])[0].max())
    for k, c in enumerate(["6c1522", "8f1f2c", "8f1f2c"]):
        out[tip + 1 + k, cx, :3] = hx(c); out[tip + 1 + k, cx, 3] = 255
        out[tip + 1 + k, cx - 1, :3] = hx(OUTLINE); out[tip + 1 + k, cx - 1, 3] = 255
        out[tip + 1 + k, cx + 1, :3] = hx(OUTLINE); out[tip + 1 + k, cx + 1, 3] = 255
    drop = [(4, -1, "8f1f2c"), (4, 0, "b3313a"), (5, -1, "6c1522"), (5, 0, "8f1f2c")]
    for dy, dx, c in drop:
        out[tip + dy, cx + dx, :3] = hx(c); out[tip + dy, cx + dx, 3] = 255
    a = out[..., 3] > 0
    ring = (cv2.dilate(a[tip + 3:].astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~a[tip + 3:]
    sub = out[tip + 3:]
    sub[ring, :3] = hx(OUTLINE); sub[ring, 3] = 255
    return out


def fill_from(img, cls, mask, src_classes):
    """Each masked pixel takes the colour and class of the nearest pixel of one of src_classes."""
    src = np.isin(cls, src_classes) & (img[..., 3] > 0) & ~mask
    if not mask.any() or not src.any():
        return
    _, lab = cv2.distanceTransformWithLabels((~src).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    sy, sx = np.nonzero(src)
    order = np.zeros(lab.max() + 1, int)
    order[lab[sy, sx]] = np.arange(len(sy))
    my, mx = np.nonzero(mask)
    k = order[lab[my, mx]]
    img[my, mx] = img[sy[k], sx[k]]
    cls[my, mx] = cls[sy[k], sx[k]]


def fill_from_hair(img, cls, mask):
    """Hair colour only, never skin bleeding in from the face."""
    fill_from(img, cls, mask, (1,))


def head_fabric(img, cls, chin):
    """Blouse-class blobs up in the head that don't touch the background are misread face/hair shading
    (20's lilac terror lines under the bangs): they become the bangs."""
    a = img[..., 3] > 0
    k, lab, st, _ = cv2.connectedComponentsWithStats((cls == 3).astype(np.uint8), connectivity=8)
    near_bg = cv2.dilate((~a).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    bad = np.zeros(cls.shape, bool)
    for i in range(1, k):
        if st[i, cv2.CC_STAT_TOP] + st[i, cv2.CC_STAT_HEIGHT] <= chin - 12:
            m = lab == i
            if not (m & near_bg).any():
                bad |= m
    fill_from(img, cls, bad, (1,))


def replace_clip(img, cls):
    fp = cls == 8
    if not fp.any():
        return
    # the old logo's white fill read as background, so the footprint is the hull of what is left of it
    pts = np.argwhere(fp)[:, ::-1].astype(np.int32)
    hm = np.zeros(fp.shape, np.uint8)
    cv2.fillConvexPoly(hm, cv2.convexHull(pts), 1)
    fp = (hm > 0) & (cls != 4)
    x, y, bw, bh = cv2.boundingRect(pts)
    fp |= (cv2.dilate(fp.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & (img[..., 3] > 0) & (cls != 4)
    # the old footprint becomes background where it stuck out of the hair, hair where it sat on it
    a = img[..., 3] > 0
    outside = cv2.blur((~a & ~fp).astype(np.float32), (11, 11)) > cv2.blur((a & ~fp).astype(np.float32), (11, 11))
    img[fp & outside, 3] = 0
    cls[fp & outside] = 0
    inner = fp & ~outside
    fill_from_hair(img, cls, inner)
    # leftovers of the old logo just outside the hull: its white edge and stray dark interior bits
    ring = (cv2.dilate(fp.astype(np.uint8), np.ones((11, 11), np.uint8)) > 0) & ~fp & (img[..., 3] > 0)
    a = img[..., 3] > 0
    pad = np.pad(a, 1)
    open_nb = ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    stray = ring & (np.isin(cls, (3, 10, 11)) | ((img[..., :3] == hx(OUTLINE)).all(-1) & ~open_nb))
    fill_from_hair(img, cls, stray)
    heart = heart_sprite(int(np.clip(round(max(bw, bh) * 0.9), 18, 30)))
    hh, hw = heart.shape[:2]
    ox, oy = x + bw // 2 - hw // 2, y + bh // 2 - int(hh * 0.45)
    m = heart[..., 3] > 0
    ys, xs = np.nonzero(m)
    img[oy + ys, ox + xs] = heart[ys, xs]
    cls[oy + ys, ox + xs] = 8
    a = img[..., 3] > 0
    zone = cv2.dilate(fp.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    img[edge_of(a) & zone & (cls != 8), :3] = hx(OUTLINE)


# ------------------------------------------------------------------ 2. hygiene
def drop_islands(img, cls, max_area=60):
    a = (img[..., 3] > 0).astype(np.uint8)
    k, lab, st, _ = cv2.connectedComponentsWithStats(a, connectivity=8)
    for i in range(1, k):
        if st[i, 4] < max_area:
            img[lab == i, 3] = 0
            cls[lab == i] = 0


def seal_holes(img, cls, max_area=160):
    """Enclosed see-through pockets inside clothing are cut-out mistakes; gaps between fingers are not."""
    t = (img[..., 3] == 0).astype(np.uint8)
    k, lab, st, _ = cv2.connectedComponentsWithStats(t, connectivity=4)
    for i in range(1, k):
        x, y, w, h, area = st[i]
        if area > max_area or x == 0 or y == 0 or x + w >= W or y + h >= H:
            continue
        hole = lab == i
        ring = (cv2.dilate(hole.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0) & ~hole
        if (cls[ring] == 4).mean() > 0.3:
            continue
        img[hole, 3] = 255
        img[:] = LF.inpaint_region(img, hole)
        nb = cls[ring]
        cls[hole] = np.bincount(nb[nb > 0], minlength=13).argmax() if (nb > 0).any() else 3


def clean_body_skin(img, cls, chin):
    """Below the face: skin specks on fabric go, and a hand's pale fringe on a sleeve is trimmed."""
    skin = np.isin(cls, (4, 10, 11, 12))
    skin[:chin] = False
    k, lab, st, _ = cv2.connectedComponentsWithStats(skin.astype(np.uint8), connectivity=8)
    for i in range(1, k):
        if st[i, 4] < 25:
            m = lab == i
            img[:] = LF.inpaint_region(img, m)
            cls[m] = 3
    for _ in range(2):
        skin = (cls == 4); skin[:chin] = False
        fab = ((cls == 3) | (cls == 2)).astype(np.uint8)
        n_fab = cv2.filter2D(fab, -1, np.ones((3, 3), np.float32), borderType=cv2.BORDER_CONSTANT)
        fringe = skin & (n_fab >= 5)
        if not fringe.any():
            break
        img[:] = LF.inpaint_region(img, fringe)
        cls[fringe] = 3


def head_specks(img, cls, chin):
    """Face-coloured specks up in the bangs, apart from the face itself (thin links don't count), are misread hair."""
    face = np.isin(cls, (4, 5, 6, 9, 10, 11, 12)).copy()
    face[chin:] = False
    opened = cv2.morphologyEx(face.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    k, lab, st, _ = cv2.connectedComponentsWithStats(opened, connectivity=4)
    if k < 2:
        return
    main = cv2.dilate((lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))).astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    loose = np.isin(cls, (4, 10, 11, 12)) & ~main
    loose[chin - 20:] = False
    k, lab, st, _ = cv2.connectedComponentsWithStats(loose.astype(np.uint8), connectivity=8)
    bad = np.isin(lab, [i for i in range(1, k) if st[i, cv2.CC_STAT_AREA] < 150])
    fill_from(img, cls, bad, (1,))


def ink_pools(img, cls, chin):
    """Below the face, enclosed solid-black blobs (06's navy bow: its deepest shadow read as the darkest hair and
    dress step) look like holes: their fill goes up one ramp step, their line pixels stay. Black next to hands
    (finger gaps, the knife grip) and on the silhouette stays."""
    a = img[..., 3] > 0
    dark = a & (img[..., :3].astype(int).sum(-1) < 60) & np.isin(cls, (1, 2, 3, 7))
    dark[:chin] = False
    near_bg = cv2.dilate((~a).astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    sk = (cls == 4).astype(np.uint8)
    near_skin = cv2.distanceTransform(1 - sk, cv2.DIST_L2, 3) <= 2
    k, lab, st, _ = cv2.connectedComponentsWithStats(dark.astype(np.uint8), connectivity=8)
    pool = np.zeros(cls.shape, bool)
    for i in range(1, k):
        if 12 <= st[i, cv2.CC_STAT_AREA] <= 1200:
            m = lab == i
            if not (m & near_bg).any():
                pool |= m
    pool &= ~near_skin
    for name, c in (("hair", 1), ("dress", 2), ("blouse", 3)):
        m = pool & (cls == c)
        if m.any():
            img[m, :3] = hx(RAMPS[name][1])


def pallor_to_skin(img, cls):
    """20's pallor ramp is grey beside the skin of her cheeks and read as a mask: it becomes skin, by brightness."""
    m = cls == 11
    if not m.any():
        return
    pale = np.array([hx(r) for r in RAMPS["pale"]])
    skin = np.array([hx(r) for r in RAMPS["skin"]])
    idx = np.abs(img[m][:, None, :3].astype(int) - pale[None]).sum(-1).argmin(1)
    j = np.round(idx / (len(pale) - 1) * (len(skin) - 1)).astype(int)
    out = img[m]
    out[:, :3] = skin[j]
    img[m] = out
    cls[m] = 4


def chin_row(cls):
    """Bottom of the face: lowest row of eye/mouth/whites + a margin."""
    ys = np.nonzero(np.isin(cls, (5, 6, 10)).any(1))[0]
    ys = ys[ys < H * 0.4]
    return int(ys.max() + 30) if len(ys) else int(H * 0.25)


# ------------------------------------------------------------------ 3. per-sprite work
def steel_knife(img, cls, box):
    """The knife blade in steel: the drawing's own dark ramp, re-read as polished metal with a bright edge."""
    x0, y0, x1, y1 = box
    blouse = [tuple(hx(c)) for c in RAMPS["blouse"]]
    sub = img[y0:y1, x0:x1]
    for (y, x) in np.argwhere(sub[..., 3] > 0):
        c = tuple(sub[y, x, :3])
        if c in blouse:
            sub[y, x, :3] = hx(STEEL[min(4, blouse.index(c) + 1)])
    a = sub[..., 3] > 0
    steel = np.isin(sub[..., :3].reshape(-1, 3).view([("", np.uint8)] * 3).ravel(),
                    np.array([tuple(hx(c)) for c in STEEL], dtype=[("", np.uint8)] * 3)).reshape(a.shape)
    # cutting edge: steel pixels whose right neighbour is background catch the light
    lit = steel & ~np.pad(a, ((0, 0), (0, 1)))[:, 1:]
    lit_left = np.zeros_like(lit); lit_left[:, :-1] = lit[:, 1:]
    sub[lit_left & steel, :3] = hx(STEEL[4])


def mirror_eye(img, cls, src_box, dst_x):
    """Copy a good eye (src_box x0,y0,x1,y1) mirrored onto the other eye at dst_x (left edge)."""
    x0, y0, x1, y1 = src_box
    patch = img[y0:y1, x0:x1][:, ::-1].copy()
    pc = cls[y0:y1, x0:x1][:, ::-1]
    m = ~np.isin(pc, (0, 1, 8))     # the whole eye with its skin, but not bangs falling over it
    tgt = img[y0:y1, dst_x:dst_x + (x1 - x0)]
    tgt[m] = patch[m]
    cls[y0:y1, dst_x:dst_x + (x1 - x0)][m] = pc[m]


def mirror_leg(img, cls, y0, axis):
    """Rebuild the right leg from row y0 down as the mirror of the left one about column axis
    (the source's white sock vanished into its white background)."""
    x0 = int(np.ceil(axis))
    img[y0:, x0:] = 0
    cls[y0:, x0:] = 0
    src = np.arange(x0, img.shape[1])
    m = (2 * axis - src).round().astype(int)
    ok = (m >= 0) & (m < x0)
    img[y0:, src[ok]] = img[y0:, m[ok]]
    cls[y0:, src[ok]] = cls[y0:, m[ok]]


def hands_from(img, cls, px_dir, donor, parts):
    """Transplant hands from a sprite with the same arm pose: each part is a box (x0, y0, x1, y1) in the donor
    and the offset that puts the donor's cuff on this sprite's cuff. Copies the hand's skin and its outline only."""
    dimg, dcls = load(px_dir, donor)
    for (x0, y0, x1, y1), dx, dy in parts:
        box = np.zeros(dcls.shape, bool); box[y0:y1, x0:x1] = True
        skin = (dcls == 4) & box
        rim = (cv2.dilate(skin.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & box & (dimg[..., 3] > 0) \
            & ~np.isin(dcls, (2, 3, 8))
        m = skin | rim
        ys, xs = np.nonzero(m)
        ty, tx = ys + dy, xs + dx
        ok = (ty >= 0) & (ty < H) & (tx >= 0) & (tx < W)
        img[ty[ok], tx[ok]] = dimg[ys[ok], xs[ok]]
        cls[ty[ok], tx[ok]] = dcls[ys[ok], xs[ok]]


def mirror_fill(img, cls, y0, y1, axis):
    """Fill what is missing right of axis in rows y0..y1 with the mirrored left side; only empty pixels are
    written, so whatever survived on the right (braid, torso) stays on top."""
    x0 = int(np.ceil(axis))
    src = np.arange(x0, img.shape[1])
    m = (2 * axis - src).round().astype(int)
    ok = (m >= 0) & (m < x0)
    src, m = src[ok], m[ok]
    tgt = img[y0:y1][:, src]
    from_ = img[y0:y1][:, m]
    put = (tgt[..., 3] == 0) & (from_[..., 3] > 0)
    tgt[put] = from_[put]
    img[y0:y1, src] = tgt
    tc = cls[y0:y1][:, src]
    tc[put] = cls[y0:y1][:, m][put]
    cls[y0:y1, src] = tc


def dress_to_hair(img, cls, box):
    """Dark hair strands over the navy vest read as dress: in box, dress becomes hair at the same ramp step."""
    x0, y0, x1, y1 = box
    dress = np.array([hx(r) for r in RAMPS["dress"]])
    hair = np.array([hx(r) for r in RAMPS["hair"]])
    m = np.zeros(cls.shape, bool); m[y0:y1, x0:x1] = True
    # dress pixels, and the line pixels that took the dress's dark red as their sel-out colour
    m &= (cls == 2) | (np.abs(img[..., None, :3].astype(int) - dress[None, None]).sum(-1).min(-1) == 0)
    if not m.any():
        return
    idx = np.abs(img[m][:, None, :3].astype(int) - dress[None]).sum(-1).argmin(1)
    j = np.round(idx / (len(dress) - 1) * (len(hair) - 1)).astype(int)
    out = img[m]
    out[:, :3] = hair[j]
    img[m] = out
    cls[m] = 1


def sock_specks(img, cls):
    """Leg skin that leaked into the sock tops: the closed, hole-filled sock area is all sock."""
    from scipy.ndimage import binary_fill_holes
    y0 = int(img.shape[0] * 0.66)
    sock = (cls[y0:] == 3)
    full = cv2.morphologyEx(sock.astype(np.uint8), cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) > 0
    full = binary_fill_holes(full)
    m = np.zeros(cls.shape, bool)
    m[y0:] = full & (cls[y0:] == 4)
    if not m.any():
        return
    src = (cls == 3) & ~m
    src[:y0] = False
    _, lab = cv2.distanceTransformWithLabels((~src).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
    sy, sx = np.nonzero(src)
    order = np.zeros(lab.max() + 1, int)
    order[lab[sy, sx]] = np.arange(len(sy))
    my, mx = np.nonzero(m)
    k = order[lab[my, mx]]
    img[my, mx] = img[sy[k], sx[k]]
    cls[my, mx] = 3


FIX = {
    "21_red_eyed_knife_mania": [("knife", (14, 138, 74, 258))],
    # 30: its right sleeve and pale, trembling hands were lit the colour of its aura and left with the background:
    # the sleeve is the mirrored left one, the hands are 26's claws (same pose)
    "30_predatory_bloodlust": [("leg", 450, 213.0), ("fill", 160, 360, 213.0),
                               ("hands", "26_sanity_break_twitch", [((50, 344, 118, 395), 27, 2), ((262, 344, 318, 395), 25, 7)])],
    # the left iris is lilac in the source and touches the bangs, so it stayed hair: mirror the right eye
    "12_exhausted_fatigue": [("hair", (118, 128, 156, 168))],
    "19_desperate_pleading": [("eye", (189, 87, 214, 106), 155)],
    "24_obsessive_yandere_blush": [("eye", (187, 87, 212, 106), 152)],
}


# ------------------------------------------------------------------ 4. effects (29 glitch, 30 blood aura)
def fx_glitch(img, name):
    r = LF._rng(name)
    out = img.copy()
    y = 0
    while y < H:
        h = int(r.integers(3, 17))
        if r.random() < 0.28:
            out[y:y + h] = np.roll(img[y:y + h], int(r.choice([-10, -6, -4, 4, 6, 8, 12])), axis=1)
        y += h
    a = out[..., 3] > 0
    ghost_r = np.roll(a, -3, 1) & ~a
    ghost_c = np.roll(a, 3, 1) & ~a
    out[ghost_r, :3] = hx("d8323a"); out[ghost_r, 3] = 255
    out[ghost_c, :3] = hx("7fd8e0"); out[ghost_c, 3] = 200
    for yy in range(0, H, 4):
        if r.random() < 0.35:
            out[yy, :, :3] = (out[yy, :, :3].astype(np.int32) * 0.55).astype(np.uint8)
    for _ in range(12):
        bx, by = int(r.integers(60, 320)), int(r.integers(40, 640))
        bw, bh = int(r.integers(6, 24)), int(r.integers(2, 5))
        blk = out[by:by + bh, bx:bx + bw]
        blk[blk[..., 3] > 0, :3] = hx(r.choice(["07040a", "fbe9e0", "d8323a"]))
    return out


def fx_aura(img, name):
    r = LF._rng(name)
    a = (img[..., 3] > 0).astype(np.uint8)
    dist = cv2.distanceTransform(1 - a, cv2.DIST_L2, 3)
    cols = [hx(c) for c in ("b3313a", "8f1f2c", "6c1522", "4d0f1a", "330a12")]
    reach = np.array([r.choice([0, 2, 4, 6, 10, 16, 24]) for _ in range(W)], float)
    reach = np.convolve(reach, [0.15, 0.2, 0.3, 0.2, 0.15], mode="same")
    top = np.array([np.nonzero(a[:, x])[0][0] if a[:, x].any() else H for x in range(W)])
    yy, xx = np.mgrid[0:H, 0:W]
    d = dist.copy()
    above = yy < top[None, :]
    d[above] = np.maximum(d[above], 0.6 * (top[None, :] - yy)[above])
    lim = 9.0 + np.where(yy < top[None, :] + 4, reach[None, :], 0)
    halo = (a == 0) & (d <= lim)
    k = np.minimum(4, (d / lim * 5).astype(int))
    halo &= ~((k >= 3) & ((xx + yy) % 2 == 1))
    out = img.copy()
    for i in range(5):
        m = halo & (k == i)
        out[m, :3] = cols[i]; out[m, 3] = 255
    # drips off the fingertips
    skin = np.isin(img[..., :3].reshape(-1, 3).view([("", np.uint8)] * 3).ravel(),
                   np.array([tuple(hx(c)) for c in RAMPS["skin"]], dtype=[("", np.uint8)] * 3)).reshape(H, W)
    hands = skin.copy(); hands[:int(H * 0.45)] = False; hands[int(H * 0.58):] = False   # hands, not legs
    for _ in range(8):
        cand = np.nonzero(hands.any(0))[0]
        if not len(cand):
            break
        x = int(r.choice(cand))
        y0 = int(np.nonzero(hands[:, x])[0].max()) + 1
        for j in range(int(r.integers(4, 14))):
            if y0 + j < H and a[y0 + j, x] == 0:
                out[y0 + j, x, :3] = hx("8f1f2c" if j < 5 else "6c1522"); out[y0 + j, x, 3] = 255
    return out


FX = {"29_glitching_distortion": fx_glitch, "30_predatory_bloodlust": fx_aura}


# ------------------------------------------------------------------ 5. pipeline + export
def finish(px_dir, name):
    img, cls = load(px_dir, name)
    replace_clip(img, cls)
    chin = chin_row(cls)
    for op, *args in FIX.get(name, []):
        if op == "knife":
            steel_knife(img, cls, *args)
        elif op == "eye":
            mirror_eye(img, cls, *args)
        elif op == "leg":
            mirror_leg(img, cls, *args)
        elif op == "hair":
            dress_to_hair(img, cls, *args)
        elif op == "fill":
            mirror_fill(img, cls, *args)
        elif op == "hands":
            hands_from(img, cls, px_dir, *args)
    sock_specks(img, cls)
    head_fabric(img, cls, chin)
    pallor_to_skin(img, cls)
    head_specks(img, cls, chin)
    ink_pools(img, cls, chin)
    clean_body_skin(img, cls, chin)
    seal_holes(img, cls)
    drop_islands(img, cls)
    if name in FX:
        img = FX[name](img, name)
    return img, cls


def sheet(imgs, path, crop=None, zoom=1, cols=8):
    tiles = []
    for im in imgs:
        t = im if crop is None else im[crop[1]:crop[3], crop[0]:crop[2]]
        a = t[..., 3:4] / 255.0
        t = (t[..., :3] * a + np.array([43, 37, 48]) * (1 - a)).astype(np.uint8)
        tiles.append(cv2.resize(t, None, fx=zoom, fy=zoom, interpolation=cv2.INTER_NEAREST))
    while len(tiles) % cols:
        tiles.append(np.zeros_like(tiles[0]))
    grid = np.vstack([np.hstack(tiles[i:i + cols]) for i in range(0, len(tiles), cols)])
    cv2.imwrite(path, cv2.cvtColor(grid, cv2.COLOR_RGB2BGR))


if __name__ == "__main__":
    px_dir, out_dir = sys.argv[1], sys.argv[2]
    names = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(px_dir) if f.endswith(".png"))
    for sub in ("px", "x2"):
        os.makedirs(os.path.join(out_dir, sub), exist_ok=True)
    done = []
    for n in names:
        img, _ = finish(px_dir, n)
        cv2.imwrite(os.path.join(out_dir, "px", n + ".png"), cv2.cvtColor(img, cv2.COLOR_RGBA2BGRA))
        cv2.imwrite(os.path.join(out_dir, "x2", n + ".png"), cv2.cvtColor(LF.upscale(img, 2), cv2.COLOR_RGBA2BGRA))
        done.append(img)
        print("ok", n)
    LF.write_palette(out_dir)
    sheet(done, os.path.join(out_dir, "sheet_faces.png"), crop=(124, 40, 268, 184), zoom=2)
    sheet(done, os.path.join(out_dir, "sheet_bodies.png"), zoom=1, cols=11)
