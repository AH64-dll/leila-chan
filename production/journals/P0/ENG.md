# ENG journal — phase P0

## P0.05 (round 1, 2026-11-02)
- Created `game/` as a Godot **4.7.2-stable** project (latest stable; pin lives in `game/.godot-version`, release-tag
  format `Godot_v<pin>_win64.exe`). Full docs/07 §2 layout; 14 autoload stubs registered in doc order; Boot.tscn is
  the main scene and self-checks `/root/<name>` for all 14 (prints `Boot: 14/14`, quits 1 on miss).
- Conventions chosen: `##` docstring under `extends` in stubs quoting the docs/07 §2 role; `.gdkeep` for empty dirs;
  `.gd.uid` sidecars committed (4.4+ convention); `gl_compatibility` renderer + Nearest default filter (pixel art,
  desktop+mobile); provisional 384×688 viewport ×2 integer stretch → 768×1376 window — ART to confirm.
- Local binary at `D:/lila/tools/godot/` (gitignored, README row added); launch via `tools/godot.sh` / `.ps1`
  (`LEILA_GODOT` override) — `godot` is NOT on PATH on this machine, reviewers need the script or full path.
- Gotcha for next task: `--import` creates `game/.godot/` (gitignored) and `.gd.uid` files (commit them). No
  `.gdignore` anywhere — dirs inside `game/` are export-relevant.
- P0.06 next: gdtoolkit (gdlint/gdformat) + gdUnit4-or-GUT + `tools/test.*`. Boot's autoload check is the seed test.
