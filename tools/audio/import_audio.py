#!/usr/bin/env python3
"""Audio import tool (P1.12): cue_map entries -> game/assets/audio/*.ogg.

docs/04 §8: raw packs live in the local-only pool ``assets/audio/_raw/`` (main
tree ``D:/lila``; in a worktree use ``--raw-dir`` or ``LEILA_AUDIO_RAW``); on
import, files are trimmed (non-music), loudness-normalised (music -16 LUFS,
everything else -18 LUFS) and converted to OGG. Next to each ``.ogg`` a
deterministic ``.import`` file is written (same uid/md5 scheme as
tools/bridge/export_to_godot.py) with ``loop=true`` for music.

Selection is explicit, mirroring the AudioDirector scope:
  --max-stage N   cues whose docs/02 §2.1 gate <= N, plus every music band
                  that intersects stages 0..N (default 1)
  --music-stage N music bands intersect stages 0..N instead of 0..max-stage —
                  opens the stage 2-5 layers without pulling every high-stage
                  cue asset (P2.16; e.g. --max-stage 0 --music-stage 5)
  --cue NAME      extra cue names (repeatable)
  --music STATE   extra music states (all bands intersecting 0..music-stage)
  --system KEY    cue_map "system" keys (repeatable)

Modes:
  default      convert + write everything selected; fails on missing sources
  --dry-run    print the plan, write nothing
  --check      verify committed outputs exist (sources not needed), nonzero
               on drift — the CI-friendly half of the bridge

AudioDirector resolves cue_map sources to ``res://assets/audio/<cat>/<sanitised
relpath>.ogg``; keep sanitise() in sync with _resolve_src() in
game/autoload/AudioDirector.gd.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CUE_MAP_PATH = ROOT / "assets" / "audio" / "cue_map.json"
RULES_PATH = ROOT / "game" / "data" / "audio_rules.json"
DST_AUDIO = ROOT / "game" / "assets" / "audio"
ENV_RAW = "LEILA_AUDIO_RAW"

MUSIC_LUFS = "-16"
OTHER_LUFS = "-18"
MUSIC_LOOP_OVERRIDES = ("loop=true", "loop_offset=0", "bpm=0", "beat_count=0", "bar_beats=4")

# Mirror of AudioDirector._resolve_src sanitisation (GDScript <-> Python parity
# is covered by tests/test_audio_import.py).
_INVALID = re.compile(r"[^a-z0-9._-]+")


def sanitise_segment(segment: str) -> str:
    return re.sub(r"_+", "_", _INVALID.sub("_", segment.lower())).strip("_")


def sanitise_relpath(rel: str) -> str:
    parts = rel.split("/")
    clean = [sanitise_segment(p) for p in parts[:-1]]
    name = sanitise_segment(parts[-1])
    if not name.endswith(".ogg"):
        name = os.path.splitext(name)[0] + ".ogg"
    clean.append(name)
    return "/".join(clean)


def band_span(band: str) -> tuple[int, int] | None:
    if band == "any":
        return (0, 5)
    parts = band.split("-")
    if len(parts) == 2 and all(p.lstrip("-").isdigit() for p in parts):
        return (int(parts[0]), int(parts[1]))
    return None


def load_tables() -> tuple[dict, dict]:
    cue_map = json.loads(CUE_MAP_PATH.read_text(encoding="utf-8"))
    rules = json.loads(RULES_PATH.read_text(encoding="utf-8"))
    return cue_map, rules


def music_bands_intersecting(entry: dict, lo: int, hi: int) -> list[str]:
    out = []
    for band, files in entry.items():
        span = band_span(band)
        if span is None or not isinstance(files, list):
            continue
        if span[0] <= hi and span[1] >= lo:
            out.append(band)
    return out


def build_selection(
    cue_map: dict, rules: dict, max_stage: int, extra_cues: list[str],
    extra_music: list[str], system_keys: list[str],
    music_max_stage: int | None = None,
) -> dict[str, list[tuple[str, str]]]:
    """{category: [(src_relpath, dst_relpath_under_category)]} sorted, unique."""
    sel: dict[str, list[tuple[str, str]]] = {"music": [], "sfx": [], "vocal": [], "amb": []}
    vocal = set(rules.get("vocal_cues", []))
    gates = rules.get("cue_gates", {})
    music_hi = max_stage if music_max_stage is None else music_max_stage

    cue_names = set(extra_cues)
    for name in cue_map.get("cues", {}):
        if int(gates.get(name, 99)) <= max_stage:
            cue_names.add(name)
    cue_names.discard("none")
    for name in sorted(cue_names):
        entry = cue_map["cues"].get(name, {})
        cat = "vocal" if name in vocal else "sfx"
        for src in entry.get("files", []):
            sel[cat].append((src, sanitise_relpath(src)))

    music_names = set(extra_music)
    if music_hi >= 0:
        # Music states the model may actually request across the layer scope.
        music_names |= {
            name
            for name, gate in rules.get("music_gates", {}).items()
            if int(gate) <= music_hi and name not in ("keep", "silence")
        }
    for name in sorted(music_names):
        entry = cue_map.get("music", {}).get(name, {})
        for band in music_bands_intersecting(entry, 0, music_hi):
            for src in entry[band]:
                sel["music"].append((src, sanitise_relpath(src)))

    sys_specs = rules.get("system_keys", {})
    for key in sorted(set(system_keys)):
        spec = sys_specs.get(key, {})
        cat = spec.get("category", "sfx")
        for src in cue_map.get("system", {}).get(key, []):
            sel[cat].append((src, sanitise_relpath(src)))

    for cat, pairs in sel.items():
        sel[cat] = sorted(set(pairs))
    return sel


def raw_dir(explicit: str | None) -> Path | None:
    cand = (
        Path(explicit)
        if explicit
        else Path(os.environ[ENV_RAW])
        if os.environ.get(ENV_RAW)
        else ROOT / "assets" / "audio" / "_raw"
    )
    if cand.is_dir():
        return cand
    # Worktree checkout: the local pool lives only in the main tree sibling.
    main_tree = ROOT.parent.parent / "lila" / "assets" / "audio" / "_raw"
    if main_tree.is_dir():
        return main_tree
    return None


def ffmpeg_convert(src: Path, dst: Path, category: str) -> None:
    filters = [f"loudnorm=I={'-16' if category == 'music' else OTHER_LUFS}"]
    if category == "sfx":
        # docs/04 §8 "trimmed": leading/trailing silence under -40 dB. Only cue
        # SFX — her voice blips are ~0.25 s syllables and the trim swallowed
        # whole takes (P2.16: 4 of the 20 blip oggs came out header-only), and
        # vocal cues need their breath attack intact.
        filters.append(
            "silenceremove=start_periods=1:start_threshold=-40dB:"
            "stop_periods=1:stop_threshold=-40dB"
        )
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-nostdin", "-y", "-i", str(src),
        "-af", ",".join(filters), "-ar", "48000", "-c:a", "libvorbis",
        "-q:a", "4", str(dst),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0 or not dst.is_file():
        sys.exit(
            f"import_audio: ffmpeg failed for {src.name}\n{proc.stderr[-2000:]}"
        )


_IMPORT_TEMPLATE = """\
[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"
uid="{uid}"
path="res://.godot/imported/{file}-{path_md5}.oggvorbisstr"

[deps]

source_file="{res_path}"
dest_files=["res://.godot/imported/{file}-{path_md5}.oggvorbisstr"]

[params]

{params}
"""


def write_import_file(dst: Path, res_path: str, category: str) -> None:
    sys.path.insert(0, str(ROOT / "tools" / "bridge"))
    import export_to_godot as bridge  # noqa: E402 — uid port is the single source

    file_md5 = hashlib.md5(dst.read_bytes()).hexdigest()
    uid = bridge._id_to_text(
        bridge._create_id_for_path(res_path, file_md5, bridge._project_name())
    )
    path_md5 = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    if category == "music":
        params = "\n".join(MUSIC_LOOP_OVERRIDES)
    else:
        params = "loop=false\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4"
    dst.with_name(dst.name + ".import").write_text(
        _IMPORT_TEMPLATE.format(
            uid=uid, file=dst.name, path_md5=path_md5,
            res_path=res_path, params=params,
        ),
        encoding="utf-8",
    )


def plan_rows(selection: dict[str, list[tuple[str, str]]]) -> list[tuple[str, str, str]]:
    rows = []
    for cat, pairs in selection.items():
        for src, dst_rel in pairs:
            rows.append((cat, src, f"assets/audio/{cat}/{dst_rel}"))
    return sorted(rows, key=lambda r: r[2])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--max-stage", type=int, default=1)
    ap.add_argument("--music-stage", type=int, default=None,
                    help="music bands intersect 0..N instead of 0..max-stage")
    ap.add_argument("--cue", action="append", default=[])
    ap.add_argument("--music", action="append", default=[])
    ap.add_argument("--system", action="append", default=[])
    ap.add_argument("--raw-dir", default=None,
                    help=f"raw pool dir (default: ${ENV_RAW}, then "
                    "assets/audio/_raw, then the main-tree sibling)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true",
                    help="verify committed outputs + .import files exist")
    ap.add_argument("--allow-missing", action="store_true",
                    help="skip raw-pool sources that are absent")
    args = ap.parse_args()

    cue_map, rules = load_tables()
    selection = build_selection(
        cue_map, rules, args.max_stage, args.cue, args.music, args.system,
        music_max_stage=args.music_stage,
    )
    rows = plan_rows(selection)

    if args.dry_run:
        for cat, src, dst in rows:
            print(f"{cat}\t{src}\t{dst}")
        print(f"dry-run: {len(rows)} file(s) selected")
        return 0

    missing_outputs = [
        dst for _c, _s, dst in rows
        if not (DST_AUDIO.parent.parent / dst).is_file()
        or not (DST_AUDIO.parent.parent / (dst + ".import")).is_file()
    ]
    if args.check:
        if missing_outputs:
            for dst in missing_outputs:
                print(f"missing: {dst}", file=sys.stderr)
            return 1
        print(f"check: {len(rows)} imported file(s) + .import files present")
        return 0

    if not shutil.which("ffmpeg"):
        sys.exit("import_audio: ffmpeg not found on PATH")

    pool = raw_dir(args.raw_dir)
    if pool is None:
        sys.exit(
            "import_audio: raw pool not found — set --raw-dir or "
            f"{ENV_RAW} to the local-only assets/audio/_raw (main tree)"
        )

    converted = skipped = 0
    for cat, src, dst in rows:
        src_path = pool / src
        dst_path = DST_AUDIO.parent.parent / dst
        if not src_path.is_file():
            if args.allow_missing:
                skipped += 1
                print(f"skip (missing source): {src}")
                continue
            sys.exit(f"import_audio: missing source {pool / src}")
        ffmpeg_convert(src_path, dst_path, cat)
        write_import_file(dst_path, "res://" + dst, cat)
        converted += 1
        print(f"{cat}\t{src} -> {dst}")
    print(f"done: {converted} converted, {skipped} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
