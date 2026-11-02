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

## P0.16 (2026-11-02, swe2) — P0.08 carry-overs

Closed DES-1 by completing the palette, not the doc: `write_palette` adds the hard-coded sel-out
line colours (`140a0e`/`3e3446`) to `line` and scans `out_dir/px` for every used-but-unlisted
colour into `fx_derived` — "every colour used" is true by construction, check_palette green at 96.
Bridge guards: `SUPPORTED_GODOT=(4,7)` refuses other pins (upgrade: --import, diff .import, port
template+uid); CRLF text sources refused; `game/data/.bridge_manifest.json` tracks managed paths
so renamed data files go stale (sprite glob + manifest diff). docs/07 §2 now records the
repo-relative→`res://` basename convention (CODE-1). Gotchas: `cv2.imread` is BGR (hex order
r,g,b from b,g,r rows);
`open(p,'wb').write(open(p,'rb').read())` truncates before reading — never rewrite in place that
way. Python tests live next to the tool (`tools/bridge/test_*`), `pytest==9.1.1` in dev reqs.

## P0.16 round 2 (2026-11-02, swe2) — review fixes

CODE-1 (S2): `_resolve_managed` validates every manifest entry — string, relative, no `..`,
resolved under the sprite dir / game/data / the manifest itself — or the run exits before any
prune. CODE-2 (S3): manifest moved to `tools/bridge/.bridge_manifest.json` (git rm'd from
game/data; verified absent from filesystem_cache10 after a fresh --import) — the "invisible
dotfile" claim was wrong, Godot does scan it. Design DES-1 (S3): `fx_derived` is no longer a
catch-all — extras must equal floor(listed×0.55) (FX_DERIVED_FACTORS) or write_palette exits;
regen still byte-identical since all 36 pass. CODE-4: imread None/non-RGBA → named SystemExit.
DES-2/3: README group list now exhaustive; docs/07 §2 names the `native` fields repo-side.
Gotcha: Godot scans ALL files under game/ (dotfiles included) — bookkeeping belongs outside;
Windows consoles mangle non-ASCII (em-dash) in error messages — keep sys.exit text ASCII;
pytest monkeypatch works on module constants read inside the function, not import-time copies.
