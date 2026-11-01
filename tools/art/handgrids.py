"""Pixel-designed hands for the poses that procedural rendering can't make crisp at sprite size.

Each builder returns a char grid (keys = leila_finish.KEY: O outline, h/b/m/s/x skin ramp) drawn for the
viewer-LEFT hand (thumb toward the body = right side of the grid); mirror for the other hand.
"""


def _blank(w, h):
    return [["."] * w for _ in range(h)]


def _outline(g):
    h, w = len(g), len(g[0])
    out = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] != ".":
                continue
            for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and g[yy][xx] not in (".", "O"):
                    out[y][x] = "O"
                    break
    return out


def _pad(g, n=1):
    w = len(g[0]) + 2 * n
    return [["."] * w for _ in range(n)] + [["."] * n + r + ["."] * n for r in g] + [["."] * w for _ in range(n)]


def to_str(g):
    return "\n".join("".join(r) for r in g)


FIST = """
..OOOOOOOOO..
.ObbbbbbbbmO.
OhbbbbbbbbbmO
OhbbbbbbbbbmO
OhbbbbbbbbbmO
OhbbbbbhhhbmO
OhbbbbhbbbmsO
OhbbbbsmmmssO
OhbsbbsbbsbmO
OhbsbbsbbsbmO
OmmOmmOmmOmmO
.OO.OO.OO.OO.
"""


def fist(knuckles_down=True):
    """Fist from the front: four curled fingers, thumb wrapped across them, scalloped knuckles.
    Drawn wrist-up / knuckles-down for the viewer-left hand (thumb root on the right, toward the body)."""
    rows = FIST.strip("\n").split("\n")
    return "\n".join(rows if knuckles_down else rows[::-1])


def upright_hand(tops=(4, 1, 0, 1), fw=2, flen=8, palm_h=8, thumb=True):
    """Fingers pointing up (pinky on the left .. index on the right), back of the hand, thumb out to the right."""
    n = 4
    W = n * fw + (n - 1)
    F = max(tops) + flen
    H = F + 1 + palm_h
    g = _blank(W, H)
    for i, top in enumerate(tops):
        c0 = i * (fw + 1)
        for x in range(c0, c0 + fw):
            for y in range(top, F + 1):
                g[y][x] = "b"
        g[top][c0] = "h"
    for i in range(n - 1):
        c = i * (fw + 1) + fw
        for y in range(H):
            if y <= F and g[y][c - 1] != "." and g[y][c + 1] != ".":
                g[y][c] = "s"
    for y in range(F + 1, H):
        for x in range(W):
            g[y][x] = "b"
    for x in range(W):
        g[F + 1][x] = "m"            # knuckle line
    for y in range(H):
        if g[y][0] != ".":
            g[y][0] = "h"
        if g[y][W - 1] != ".":
            g[y][W - 1] = "m"
    for y in (H - 2, H - 1):          # wrist taper
        g[y][0] = "."
        g[y][W - 1] = "."
    g = _pad(g, 1)
    g = [r + ["."] * 3 for r in g]
    if thumb:
        b = F + 4                     # thumb root (padded coords)
        for k, (dy, dx) in enumerate(((0, 0), (-1, 1), (-2, 1), (-3, 2))):
            y, x = b + dy, W + 1 + dx
            g[y][x - 1] = "s" if k == 0 else g[y][x - 1]
            g[y][x] = "b"
            g[y][x + 1] = "m"
            g[y + 1][x] = "m" if g[y + 1][x] == "." else g[y + 1][x]
    return to_str(_outline(g))


def cheek_hand():
    return upright_hand()


PRAYER = """
........OOO........
.......OhbmO.......
......OhbsbmO......
.....OhbbsbbmO.....
.....OssbsbssO.....
....OhbbbsbbbmO....
....OhbbbsbbbmO....
...OssbbbsbbbssO...
...OhbbbbsbbbbmO...
...OhbbbbsbbbbmO...
..OssbbbbsbbbbssO..
..OhbbbbbsbbbbbmO..
..OhbbbmhshmbbbmO..
..OhbbmhhshhmbbmO..
..OhbbmhhshhmbbmO..
..OhbbmhhshhmbbmO..
..OhbbmbhshbmbbmO..
..OmbbmbbsbbmbbmO..
...OmbmbbsbbmbmO...
...OmmbbbsbbbmmO...
....OOOOOOOOOOO....
"""


def prayer():
    """Palms pressed together, fingertips up, both thumbs along the seam (hand-placed pixels)."""
    return PRAYER.strip("\n")


GRIDS = {"fist": fist, "cheek": cheek_hand, "prayer": prayer}

if __name__ == "__main__":
    for k, f in GRIDS.items():
        print(k)
        print(f())
