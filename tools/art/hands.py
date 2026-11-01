"""Procedural pixel-art hands for Leila: anatomically fixed (4 fingers + thumb), posed by joint angles.

A hand is built in its own frame (wrist at origin, +y = along the forearm out of the sleeve), as capsules
rendered at S x supersampling, then reduced to 1x with part-aware separations and the skin ramp.
"""
import math

import cv2
import numpy as np

S = 8
SKIN = {"h": "fbe9e0", "b": "efd2c6", "m": "dcb3aa", "s": "b98b88", "x": "8a5f63", "O": "5a3236"}
STEEL = ["1c1c22", "3a3a44", "6a6a78", "a8a8b8", "e8e8f0"]
NAIL = "c0303c"

# finger table: (name, knuckle offset across palm in [-1,1], segment lengths)
FINGERS = [("index", -0.78, (2.6, 1.9, 1.6)), ("middle", -0.26, (2.9, 2.1, 1.7)),
           ("ring", 0.26, (2.7, 1.9, 1.6)), ("pinky", 0.78, (2.1, 1.5, 1.3))]

POSES = {
    #          per-finger joint bends (deg, + curls toward palm side = to the thumb side in 2D) / foreshortening
    "relaxed": dict(spread=4, bend=[(6, 10, 8), (4, 10, 8), (6, 12, 8), (10, 14, 10)], fold=[0.0, 0.25, 0.35],
                    thumb=(28, 12), palm_len=4.6),
    "open":    dict(spread=11, bend=[(0, 2, 2)] * 4, fold=[0, 0, 0], thumb=(40, 4), palm_len=4.8),
    "cheek":   dict(spread=5, bend=[(0, 4, 4), (0, 3, 3), (0, 4, 4), (2, 6, 6)], fold=[0, 0.1, 0.1], thumb=(40, 6), palm_len=4.8),
    "claw":    dict(spread=14, bend=[(-6, 34, 30), (-2, 30, 30), (2, 30, 28), (8, 30, 26)], fold=[0, 0.35, 0.35],
                    thumb=(55, 25), palm_len=4.8, nails=True),
    "fist":    dict(spread=0, bend=[(0, 0, 0)] * 4, fold=[0.72, 1.0, 1.0], thumb=(12, 84), palm_len=4.2, knuckles=True),
    "point":   dict(spread=2, bend=[(0, 4, 4), (0, 0, 0), (0, 0, 0), (0, 0, 0)], fold=[0.72, 1.0, 1.0], thumb=(12, 84),
                    palm_len=4.2, knuckles=True, extended={"index"}),
}


def _rot(v, deg):
    a = math.radians(deg)
    return np.array([v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a)])


def build(pose, palm_w=5.6, scale=1.0):
    """Return list of parts: (name, polyline [(x,y)...], width, depth) in hand frame, units = 1x pixels."""
    P = POSES[pose]
    parts = []
    L = P["palm_len"] * scale
    w = palm_w * scale
    # palm: thick capsule from wrist to knuckle line
    parts.append(("palm", [(0, 0), (0, L * 0.55), (0, L * 0.8)], w, 0))
    ext = P.get("extended", set())
    for i, (name, off, segs) in enumerate(FINGERS):
        base = np.array([off * (w / 2 - 0.9), L])
        d = _rot(np.array([0.0, 1.0]), -P["spread"] * off * 1.4)
        pts = [tuple(base)]
        cur = base.copy()
        for j, seg in enumerate(segs):
            bend = P["bend"][i][j]
            d = _rot(d, bend * (1 if off <= 0 else 1))
            fold = 0 if name in ext else P["fold"][j]
            cur = cur + d * seg * scale * (1 - fold)
            pts.append(tuple(cur))
        parts.append((name, pts, 2.05 * scale, 1 + (i % 2) * 0.1))
    # thumb: from the index side of the palm near the wrist, sweeping out
    ta, tb = P["thumb"]
    t0 = np.array([-w / 2 + 0.6, L * 0.35])
    d = _rot(np.array([0.0, 1.0]), ta)
    t1 = t0 + d * 2.6 * scale
    d = _rot(d, -tb)
    t2 = t1 + d * 2.2 * scale
    parts.append(("thumb", [tuple(t0), tuple(t1), tuple(t2)], 2.25 * scale, 2))
    return parts, P


def render(pose, angle=0.0, mirror=False, scale=1.0, light=(-0.6, -0.8)):
    """Render a hand. angle: direction the hand points (0 = straight down, +90 = to the viewer's left... cv2 coords).
    Returns (rgba uint8 HxWx4, wrist (x, y) in the returned image)."""
    parts, P = build(pose, scale=scale)
    if mirror:
        parts = [(n, [(-x, y) for x, y in pts], wd, dp) for n, pts, wd, dp in parts]
        light = (-light[0], light[1])
    parts = [(n, [tuple(_rot(np.array(p), angle)) for p in pts], wd, dp) for n, pts, wd, dp in parts]
    allp = np.array([p for _, pts, _, _ in parts for p in pts])
    pad = 4
    mn = np.floor(allp.min(0)) - pad
    mx = np.ceil(allp.max(0)) + pad
    Wd, Hd = int(mx[0] - mn[0]), int(mx[1] - mn[1])
    pid = np.full((Hd * S, Wd * S), -1, np.int16)
    shade = np.zeros((Hd * S, Wd * S), np.float32)
    lx, ly = np.array(light) / np.hypot(*light)
    yy, xx = np.mgrid[0:Hd * S, 0:Wd * S].astype(np.float32) + 0.5
    order = sorted(range(len(parts)), key=lambda k: parts[k][3])
    if pose in ("fist", "point"):
        # knuckle row sits in front of the palm, thumb wraps in front of the fingers
        order = [0] + [k for k in order if k != 0]
    for k in order:
        n, pts, wd, dp = parts[k]
        q = [((x - mn[0]) * S, (y - mn[1]) * S) for x, y in pts]
        m = np.zeros(pid.shape, np.uint8)
        for a, b in zip(q, q[1:]):
            cv2.line(m, (int(a[0]), int(a[1])), (int(b[0]), int(b[1])), 1, max(1, int(wd * S)), cv2.LINE_AA)
        m = m > 0
        # signed distance across the segment's axis -> light/shadow side of the capsule
        a, b = np.array(q[0]), np.array(q[-1])
        ax = b - a
        ax = ax / (np.linalg.norm(ax) + 1e-6)
        perp = np.array([-ax[1], ax[0]])
        sd = ((xx - a[0]) * perp[0] + (yy - a[1]) * perp[1]) / (wd * S / 2)
        lit = -(perp[0] * lx + perp[1] * ly)
        pid[m] = k
        shade[m] = (sd * lit)[m]
    # reduce to 1x: majority part id per block, mean shade
    blocks = pid.reshape(Hd, S, Wd, S).transpose(0, 2, 1, 3).reshape(Hd, Wd, S * S)
    sh = shade.reshape(Hd, S, Wd, S).transpose(0, 2, 1, 3).reshape(Hd, Wd, S * S)
    out_id = np.full((Hd, Wd), -1, np.int16)
    out_sh = np.zeros((Hd, Wd), np.float32)
    for y in range(Hd):
        for x in range(Wd):
            v = blocks[y, x]
            filled = v[v >= 0]
            if len(filled) < S * S * 0.42:
                continue
            ids, cnt = np.unique(filled, return_counts=True)
            k = ids[np.argmax(cnt)]
            out_id[y, x] = k
            out_sh[y, x] = sh[y, x][v == k].mean()
    img = np.zeros((Hd, Wd, 4), np.uint8)
    col = lambda c: np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.uint8)
    depth = {k: i for i, k in enumerate(order)}
    names = [p[0] for p in parts]
    for y in range(Hd):
        for x in range(Wd):
            k = out_id[y, x]
            if k < 0:
                continue
            s = out_sh[y, x]
            c = "h" if s < -0.55 else "b" if s < 0.25 else "m"
            # separation: a neighbour belongs to a different part that lies in front -> crease line on this one
            for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                yy2, xx2 = y + dy, x + dx
                if 0 <= yy2 < Hd and 0 <= xx2 < Wd:
                    k2 = out_id[yy2, xx2]
                    if k2 >= 0 and k2 != k and depth[k2] > depth[k] and not (names[k] == "palm" and names[k2] != "thumb"):
                        c = "s"
            img[y, x, :3] = col(SKIN[c]); img[y, x, 3] = 255
    # knuckle creases for fists: the fold line between palm and folded fingers
    a = img[..., 3] > 0
    pad_ = np.pad(a, 1)
    edge = a & ~(pad_[:-2, 1:-1] & pad_[2:, 1:-1] & pad_[1:-1, :-2] & pad_[1:-1, 2:])
    img[edge, :3] = col(SKIN["O"])
    if P.get("nails"):
        for n, pts, wd, dp in parts:
            if n in ("index", "middle", "ring", "pinky", "thumb"):
                x, y = pts[-1]
                xi, yi = int(round(x - mn[0] - 0.5)), int(round(y - mn[1] - 0.5))
                if 0 <= yi < Hd and 0 <= xi < Wd and img[yi, xi, 3]:
                    img[yi, xi, :3] = col(NAIL)
    wrist = (int(round(-mn[0])), int(round(-mn[1])))
    return img, wrist


def knife(length=22, angle=200.0):
    """A kitchen knife (blade + handle) pointing along angle; returns rgba and the grip point."""
    L, Hd = length + 8, length + 8
    pts_blade = [(0, 0), (length, -1.2), (length + 2.5, 0.6), (length, 1.7), (0, 1.9)]
    pts_handle = [(-7, -0.2), (0, -0.3), (0, 2.0), (-7, 2.2)]
    allp = np.array(pts_blade + pts_handle)
    rot = lambda p: _rot(np.array(p), angle - 90)
    rb = np.array([rot(p) for p in pts_blade]); rh = np.array([rot(p) for p in pts_handle])
    mn = np.floor(np.vstack([rb, rh]).min(0)) - 2
    mx = np.ceil(np.vstack([rb, rh]).max(0)) + 2
    Wd, Hd = int(mx[0] - mn[0]), int(mx[1] - mn[1])
    img = np.zeros((Hd, Wd, 4), np.uint8)
    col = lambda c: np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.uint8)
    big = np.zeros((Hd * S, Wd * S), np.uint8)
    cv2.fillPoly(big, [((rb - mn) * S).astype(np.int32)], 1)
    cv2.fillPoly(big, [((rh - mn) * S).astype(np.int32)], 2)
    for y in range(Hd):
        for x in range(Wd):
            blk = big[y * S:(y + 1) * S, x * S:(x + 1) * S]
            if (blk > 0).mean() < 0.4:
                continue
            k = 1 if (blk == 1).sum() >= (blk == 2).sum() else 2
            img[y, x, 3] = 255
            img[y, x, :3] = col(STEEL[3] if k == 1 else "1d0509")
    a = img[..., 3] > 0
    pad_ = np.pad(a, 1)
    edge = a & ~(pad_[:-2, 1:-1] & pad_[2:, 1:-1] & pad_[1:-1, :-2] & pad_[1:-1, 2:])
    # blade: bright spine edge on top, darker belly, black outline
    for y, x in np.argwhere(a):
        if (img[y, x, :3] == col(STEEL[3])).all() and y + 1 < Hd and not a[y + 1, x]:
            img[y, x, :3] = col(STEEL[2])
    img[edge, :3] = col("07040a")
    for y, x in np.argwhere(a & ~edge):
        if (img[y, x, :3] == col(STEEL[3])).all() and y > 0 and edge[y - 1, x]:
            img[y, x, :3] = col(STEEL[4])
    grip = rot((-3.5, 1.0)) - mn
    return img, (int(round(grip[0])), int(round(grip[1])))


if __name__ == "__main__":
    import sys
    tiles = []
    for pose in POSES:
        for ang, mir in ((0, False), (0, True), (180, False), (35, False)):
            im, w = render(pose, ang, mir, scale=1.9)
            c = np.zeros((40, 40, 4), np.uint8)
            h_, w_ = im.shape[:2]
            c[2:2 + min(38, h_), 2:2 + min(38, w_)] = im[:38, :38]
            a = c[..., 3:4] / 255.0
            rgb = (c[..., :3] * a + np.array([43, 37, 48]) * (1 - a)).astype(np.uint8)
            tiles.append(cv2.resize(rgb, (240, 240), interpolation=cv2.INTER_NEAREST))
    rows = [np.hstack(tiles[i:i + 8]) for i in range(0, len(tiles), 8)]
    cv2.imwrite(sys.argv[1], cv2.cvtColor(np.vstack(rows), cv2.COLOR_RGB2BGR))
