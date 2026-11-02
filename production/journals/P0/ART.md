# Journal — ART (phase P0)

## P0.08 (2026-11-02, swe2) — asset/data bridge

Built `tools/bridge/export_to_godot.py`: copies x2 sprites + palette → `game/assets/sprites/leila/`,
casting.json + cue_map.json → `game/data/`, and writes `.import` files byte-identical to the editor's
own output. Key discovery worth keeping: Godot uids are **deterministic** —
`create_id_for_path` = PCG32(DJB2(project_name) × DJB2(res path) × DJB2(file md5)) → base-34 alphabet
`a-y0-8`; the Python port in the script reproduces them exactly, so `--import` never rewrites the
files. Dest-name hash is plain `md5(res:// path)`. Nearest filter is project-wide, not per-import.
Conventions: sprite id → `res://assets/sprites/leila/` + basename of `sprites[id].file`; draw x2 art
at scale 0.5 in the 384×688 viewport. Gotchas: `text_to_id` tolerates 'z'/'9' but re-encodes
canonically — emit `id_to_text` form only; `game/**/*.json` + `*.py` now eol=lf in gitattributes.
Source set has off-palette `140a0e` + 29's glitch colours — flagged, not mine to fix.
