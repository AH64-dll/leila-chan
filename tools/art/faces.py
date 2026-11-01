"""Hand-designed pixel face features for Leila (canonical layout measured on 00_base_reference).

Grids are drawn for the viewer's LEFT eye (outer corner on the left); the right eye is mirrored.
Keys are defined in leila_finish.KEY.
"""

# canonical anchors (top-left of each grid) on the 192x344 sprite, before per-sprite head offset
LEFT_EYE = (79, 46)
RIGHT_EYE = (95, 46)
BROW_L = (80, 43)
BROW_R = (95, 43)
MOUTH_C = (92, 59)          # centre of the mouth grid's top row
FACE_ZONE = (77, 45, 107, 63)   # x0, y0, x1, y1 cleared to skin before drawing

EYES = {
    "open": """
..KKKKKK..
.KKkkkkKKK
KKwqhPqwk.
..wrPPrw..
..wrRLrw..
...qRRq...
....kk....
""",
    "soft": """
..........
.KKKKKKKK.
KKkqhPqkk.
..wrPPrw..
...qRRq...
....kk....
""",
    "happy": """
..........
...kKKk...
..KK..KK..
.KK....KK.
..........
""",
    "narrow": """
..........
..........
KKKKKKKKKK
.KkqhPqkk.
..wqrrqw..
....kk....
""",
    "furious": """
..........
..........
KKK.......
.KKKKKKKK.
..wqhPqKK.
..wrPPrw..
...qRRq...
""",
    "wide": """
..KKKKKK..
.K......K.
K.wwwwww.k
.wwwqPwww.
.wwwqqwww.
..wwwwww..
...kkkk...
""",
    "tired": """
..........
..........
.KKKKKKKK.
KkkqrPqkk.
..wrPPrw..
..kqRRqk..
..xxxxxx..
""",
    "shut": """
..........
.KK.......
...KKK....
......KKK.
...KKK....
.KK.......
""",
    "dead": """
..KKKKKK..
.KKkkkkKKK
KKwqqqqwk.
..wqPPqw..
..wqPPqw..
...qqqq...
....kk....
""",
    "manic": """
..KKKKKK..
.KKkkkkKKK
KKwwRRwwk.
..wRPPRw..
..wRPPRw..
...wRRw...
....kk....
""",
    "glow": """
..KKKKKK..
.KKkkkkKKK
KKwRLLRwk.
..RLggLR..
..RLggLR..
...RLLR...
....kk....
""",
    "heart": """
..KKKKKK..
.KKkkkkKKK
KKwRhRRwk.
..wRRRRw..
..wrRRrw..
...wrrw...
....kk....
""",
    "tear": """
..KKKKKK..
.KKkkkkKKK
KKwqhPqwk.
..wrPPrw..
..wrhLrw..
...eRRe...
....ee....
""",
    "void": """
..........
..KKKKKK..
KKkPPPPkk.
..PPPPPP..
..PPPPPP..
...PPPP...
....kk....
""",
}

BROWS = {
    "neutral": """
.kkkkkk..
""",
    "worried": """
......kk.
..kkkk...
kk.......
""",
    "angry": """
kk.......
..kkkk...
......kk.
""",
    "raised": """
..kkkk...
kk....k..
""",
    "flat": """
kkkkkkk..
""",
}
# brows are mirrored for the right side, so "worried" lifts the inner ends on both sides

MOUTHS = {
    "smile": """
x...x
.xxx.
""",
    "closed": """
.xxx.
""",
    "small_o": """
.MM.
MttM
.MM.
""",
    "open_smile": """
MMMMM
.MtM.
""",
    "laugh": """
MMMMMMM
MTTTTTM
MMtttMM
.MMMMM.
""",
    "frown": """
.xxx.
x...x
""",
    "shout": """
.MMMMMMM.
MTTTTTTTM
MMMtttMMM
x.MMMMM.x
""",
    "shock": """
.MMM.
MMtMM
MMtMM
.MMM.
""",
    "grin": """
x.....x
MMMMMMM
MTTTTTM
.MMMMM.
""",
    "grimace": """
MMMMMMM
MTMTMTM
.MMMMM.
""",
    "pout": """
.xx.
x..x
""",
    "wavy": """
.x.x.x
x.x.x.
""",
    "sad_open": """
.MMM.
MMtMM
.x.x.
""",
    "fangs": """
x......x
MMMMMMMM
MTnnnnTM
.MMMMMM.
""",
    "flat": """
xxxx
""",
    "tongue": """
MMMMMM
.MttM.
..tt..
""",
    "jaw": """
.MMMMMMM.
MTTTTTTTM
MMMMtMMMM
MMMtttMMM
.MMMMMMM.
""",
}

EXTRAS = {
    "blush": ("""
c.c.c
""", [(81, 55), (99, 55)]),
    "blush_heavy": ("""
CcCcC
cCcCc
""", [(80, 54), (99, 54)]),
    "tears": ("""
e
e
E
""", [(82, 53), (102, 53)]),
    "sweat": ("""
.e
eE
EE
""", [(106, 42)]),
    "eyebags": ("""
xxxxxx
""", [(81, 53), (97, 53)]),
    "blood": ("""
D.d
.D.
""", [(84, 56), (101, 51)]),
}
