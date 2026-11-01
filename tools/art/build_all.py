"""Rebuild the whole sprite set: leila_px (LEILA_SCALE=2) -> leila_hd -> build_casting. Works on Windows/Linux/macOS.

    python tools/art/build_all.py                 # png_sprites/ -> art/leila/, then data/casting.json + docs/10
    python tools/art/build_all.py --out DIR       # build into DIR instead (casting step skipped)

The intermediate leila_px output (.png + .cls.npy) goes to a temp dir that is deleted afterwards (--keep-work keeps it).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "art", "leila")


def run(*args):
    print(">", " ".join(args), flush=True)
    subprocess.run([sys.executable, *args], cwd=ROOT, env={**os.environ, "LEILA_SCALE": "2"}, check=True)


ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
ap.add_argument("--src", default=os.path.join(ROOT, "png_sprites"), help="source renders (default png_sprites/)")
ap.add_argument("--out", default=ART, help="output dir (default art/leila/)")
ap.add_argument("--keep-work", action="store_true", help="keep the intermediate leila_px dir")
opt = ap.parse_args()

names = sorted(f for f in os.listdir(opt.src) if f.endswith(".png"))
work = tempfile.mkdtemp(prefix="leila_px_")
try:
    run(os.path.join("tools", "art", "leila_px.py"), opt.src, work, *names)
    run(os.path.join("tools", "art", "leila_hd.py"), work, opt.out)
finally:
    if opt.keep_work:
        print("intermediate px kept in", work)
    else:
        shutil.rmtree(work, ignore_errors=True)
if os.path.normcase(os.path.abspath(opt.out)) == os.path.normcase(ART):
    run(os.path.join("tools", "casting", "build_casting.py"))
else:
    print("casting step skipped (it reads art/leila/, not", opt.out + ")")
