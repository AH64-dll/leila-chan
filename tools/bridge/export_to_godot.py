#!/usr/bin/env python3
"""Deterministic asset/data bridge: Leila art + data tables -> game/.

Copies the source-of-truth assets into the Godot project. The copies are
generated files — never edit them by hand; change the source and re-run.

    art/leila/x2/*.png        -> game/assets/sprites/leila/*.png
    art/leila/palette.json    -> game/assets/sprites/leila/palette.json
    data/casting.json         -> game/data/casting.json
    assets/audio/cue_map.json -> game/data/cue_map.json

Every sprite also gets a `<name>.png.import` (Godot texture importer:
mipmaps/generate=false, lossless compress). The file is written
byte-for-byte the way the editor writes it, including a deterministic
`uid://` — a Python port of ResourceUID::create_id_for_path (PCG32 seeded
from project name + res:// path + file md5) — so `godot --import` never
rewrites it. Pixel filtering is Nearest via the project setting
rendering/textures/canvas_textures/default_texture_filter=0 (Godot 4 has
no per-import filter for 2D textures).

Two runs produce zero diff: every output byte is a pure function of the
inputs. Use --check to verify the working tree matches without writing.
A manifest of managed paths (game/data/.bridge_manifest.json) is emitted so
renamed/removed outputs are pruned as stale, not just in the sprite dir.

    python tools/bridge/export_to_godot.py          # write outputs
    python tools/bridge/export_to_godot.py --check  # verify, nonzero on drift

Godot version: the .import template and the uid:// port are verified against
Godot 4.7.x; the bridge refuses to run when game/.godot-version pins anything
else. Upgrade procedure: re-pin the version, run `godot --import`, diff the
rewritten .import files, port the differences into _IMPORT_TEMPLATE and the
uid port, then bump SUPPORTED_GODOT.

Path convention: the JSON copies stay byte-identical to the repo sources, so
casting.json's art.* and sprites.*.file fields remain repo-relative
(art/leila/x2/...). Runtime consumers resolve sprites as
res://assets/sprites/leila/<basename of sprites[id].file> (docs/07 §2).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SRC_SPRITE_DIR = ROOT / "art" / "leila" / "x2"
SRC_PALETTE = ROOT / "art" / "leila" / "palette.json"
SRC_CASTING = ROOT / "data" / "casting.json"
SRC_CUE_MAP = ROOT / "assets" / "audio" / "cue_map.json"

DST_SPRITE_DIR = ROOT / "game" / "assets" / "sprites" / "leila"
DST_CASTING = ROOT / "game" / "data" / "casting.json"
DST_CUE_MAP = ROOT / "game" / "data" / "cue_map.json"
DST_MANIFEST = ROOT / "game" / "data" / ".bridge_manifest.json"
RES_SPRITE_DIR = "res://assets/sprites/leila"

# The .import template and the uid:// port match this Godot major.minor's
# importer defaults; any other pin must be ported deliberately (docstring).
SUPPORTED_GODOT = (4, 7)

# ---------------------------------------------------------------------------
# Godot uid:// — port of ResourceUID::create_id_for_path + id_to_text
# (godot 4.7: core/io/resource_uid.cpp). The seed multiplies three DJB2-64
# hashes; the stream is minimal PCG32 (thirdparty/misc/pcg.h); the text is
# base-34 over 'abcdefghijklmnopqrstuvwxy012345678' ('z' and '9' unused).
# ---------------------------------------------------------------------------

_M64 = (1 << 64) - 1
_PCG_MULT = 6364136223846793005
_PCG_INC = 1442695040888963407  # PCG_DEFAULT_INC_64
_UID_ALPHABET = "abcdefghijklmnopqrstuvwxy012345678"


def _hash64(text: str) -> int:
    """String::hash64 — djb2 over char32 codepoints."""
    h = 5381
    for ch in text:
        h = ((h << 5) + h + ord(ch)) & _M64
    return h


def _pcg32(seed: int):
    """Minimal PCG32: state=0, inc=(seq<<1)|1, warm, state+=seed, warm."""
    state = 0
    inc = ((_PCG_INC << 1) | 1) & _M64

    def rand() -> int:
        nonlocal state
        old = state
        state = (old * _PCG_MULT + inc) & _M64
        xorshifted = (((old >> 18) ^ old) >> 27) & 0xFFFFFFFF
        rot = (old >> 59) & 0xFFFFFFFF
        return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & 0xFFFFFFFF

    rand()
    state = (state + seed) & _M64
    rand()
    return rand


def _id_to_text(uid: int) -> str:
    out = ""
    while uid:
        out = _UID_ALPHABET[uid % 34] + out
        uid //= 34
    return "uid://" + (out or _UID_ALPHABET[0])


def _create_id_for_path(res_path: str, file_md5_hex: str, project_name: str) -> int:
    seed = (
        _hash64(project_name)
        * _hash64(res_path.lower())
        * _hash64(file_md5_hex)
    ) & _M64
    rand = _pcg32(seed)
    return (rand() | (rand() << 32)) & 0x7FFFFFFFFFFFFFFF


# ---------------------------------------------------------------------------
# .import file — byte-identical to what the texture importer writes on
# Godot 4.7 for a default PNG import (no importer_version line: format v0).
# ---------------------------------------------------------------------------

_IMPORT_TEMPLATE = """\
[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="res://.godot/imported/{file}-{path_md5}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{res_path}"
dest_files=["res://.godot/imported/{file}-{path_md5}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def _project_name() -> str:
    text = (ROOT / "game" / "project.godot").read_text(encoding="utf-8")
    m = re.search(r'^config/name="([^"]*)"', text, re.MULTILINE)
    if not m:
        sys.exit("export_to_godot: config/name not found in game/project.godot")
    return m.group(1)


def _godot_pin() -> str:
    vf = ROOT / "game" / ".godot-version"
    if not vf.is_file():
        sys.exit("export_to_godot: missing game/.godot-version")
    return vf.read_text(encoding="utf-8").strip()


def _pin_supported(pin: str) -> bool:
    m = re.match(r"^(\d+)\.(\d+)(?:\.|$)", pin)
    return bool(m) and (int(m.group(1)), int(m.group(2))) == SUPPORTED_GODOT


def _check_godot_version() -> None:
    pin = _godot_pin()
    if not _pin_supported(pin):
        sys.exit(
            f"export_to_godot: game/.godot-version is {pin!r} but the .import "
            f"template and uid port are verified only for Godot "
            f"{SUPPORTED_GODOT[0]}.{SUPPORTED_GODOT[1]}.x. To upgrade: re-pin, "
            "run godot --import, diff the rewritten .import files, port the "
            "changes into _IMPORT_TEMPLATE/_create_id_for_path, then bump "
            "SUPPORTED_GODOT."
        )


def _check_text_sources() -> None:
    """Refuse CRLF text sources: outputs copy source bytes, so a CRLF checkout
    (stale pre-.gitattributes state) would produce CRLF outputs and a manifest
    that does not match a clean LF clone."""
    for src in (SRC_PALETTE, SRC_CASTING, SRC_CUE_MAP):
        if b"\r\n" in src.read_bytes():
            sys.exit(
                f"export_to_godot: {src} is checked out with CRLF line endings; "
                ".gitattributes pins eol=lf; restore it "
                f"(`git checkout -- {src.relative_to(ROOT).as_posix()}`) so "
                "outputs match the committed blobs"
            )


def _import_file_bytes(res_path: str, png_bytes: bytes, project_name: str) -> bytes:
    file_md5 = hashlib.md5(png_bytes).hexdigest()
    uid = _id_to_text(_create_id_for_path(res_path, file_md5, project_name))
    path_md5 = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    return _IMPORT_TEMPLATE.format(
        uid=uid,
        file=res_path.rsplit("/", 1)[-1],
        path_md5=path_md5,
        res_path=res_path,
    ).encode("utf-8")


def build_outputs() -> dict[Path, bytes]:
    """All files the bridge manages, {absolute destination: exact bytes}."""
    project_name = _project_name()
    out: dict[Path, bytes] = {}

    for src in sorted(SRC_SPRITE_DIR.glob("*.png")):
        dst = DST_SPRITE_DIR / src.name
        out[dst] = src.read_bytes()
        res_path = f"{RES_SPRITE_DIR}/{src.name}"
        out[dst.with_name(src.name + ".import")] = _import_file_bytes(
            res_path, out[dst], project_name
        )

    for src, dst in (
        (SRC_PALETTE, DST_SPRITE_DIR / SRC_PALETTE.name),
        (SRC_CASTING, DST_CASTING),
        (SRC_CUE_MAP, DST_CUE_MAP),
    ):
        out[dst] = src.read_bytes()

    managed = sorted(
        [p.relative_to(ROOT).as_posix() for p in out]
        + [DST_MANIFEST.relative_to(ROOT).as_posix()]
    )
    out[DST_MANIFEST] = (
        json.dumps({"files": managed}, indent=1) + "\n"
    ).encode("utf-8")

    return out


def _managed_pattern(path: Path) -> bool:
    name = path.name
    return name.endswith(".png") or name.endswith(".png.import")


def _prev_managed() -> list[str]:
    """Destination paths the previous run managed (the committed manifest)."""
    if not DST_MANIFEST.is_file():
        return []
    try:
        return list(json.loads(DST_MANIFEST.read_text(encoding="utf-8"))["files"])
    except (ValueError, KeyError, TypeError):
        return []  # a corrupt manifest is itself caught as drift


def _collect_stale(outputs: dict[Path, bytes]) -> list[Path]:
    """Bridge-owned files no longer produced: sprite-dir orphans plus every
    previously managed path (the manifest) now missing from outputs — that is
    what catches a renamed or dropped data file, which owns no glob."""
    managed = {p.relative_to(ROOT).as_posix() for p in outputs}
    stale = {
        p for p in DST_SPRITE_DIR.glob("*.png*")
        if _managed_pattern(p) and p not in outputs
    } if DST_SPRITE_DIR.is_dir() else set()
    stale |= {
        ROOT / rel for rel in _prev_managed()
        if rel not in managed and (ROOT / rel).is_file()
    }
    return sorted(stale)


def _manifest(outputs: dict[Path, bytes]) -> str:
    h = hashlib.sha256()
    for path in sorted(outputs):
        rel = path.relative_to(ROOT).as_posix()
        h.update(rel.encode("utf-8") + b"\0" + hashlib.sha256(outputs[path]).digest())
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="verify outputs are in sync; no writes; nonzero on drift")
    args = ap.parse_args()

    _check_godot_version()

    for src in (SRC_SPRITE_DIR, SRC_PALETTE, SRC_CASTING, SRC_CUE_MAP):
        if not src.exists():
            sys.exit(f"export_to_godot: missing source {src}")
    _check_text_sources()

    outputs = build_outputs()
    manifest = _manifest(outputs)

    stale = _collect_stale(outputs)

    drift = [p for p, data in outputs.items()
             if not (p.is_file() and p.read_bytes() == data)]

    if args.check:
        for p in drift:
            print(f"drift  {p.relative_to(ROOT).as_posix()}")
        for p in stale:
            print(f"stale  {p.relative_to(ROOT).as_posix()}")
        if drift or stale:
            print(f"check FAILED: {len(drift)} out-of-sync, {len(stale)} stale")
            return 1
        print(f"check OK: {len(outputs)} files in sync (manifest {manifest[:16]})")
        return 0

    written = 0
    for p, data in outputs.items():
        if p.is_file() and p.read_bytes() == data:
            continue
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        written += 1
        print(f"wrote  {p.relative_to(ROOT).as_posix()}")
    for p in stale:
        p.unlink()
        print(f"pruned {p.relative_to(ROOT).as_posix()}")

    n_png = sum(1 for p in outputs if p.suffix == ".png")
    n_import = sum(1 for p in outputs if p.name.endswith(".png.import"))
    print(f"export_to_godot: {n_png} sprites + {n_import} .import + "
          f"{len(outputs) - n_png - n_import} data files "
          f"({written} written, {len(stale)} pruned, manifest {manifest[:16]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
