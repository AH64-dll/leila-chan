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

## P0.05 (round 1 — verification, agent: deepseek, 2026-11-02)
- The branch was already complete from a concurrent swe2 run (commits `6856092`, `77011b5`) when this session
  started. I did not duplicate it; I re-ran every acceptance check and fixed only review-level defects.
- Launchers no longer hardcode `D:/lila`: `$LEILA_GODOT` → `<repo>/tools/godot/` → main worktree via
  `git worktree list`; works from any worktree/checkout. `.gitattributes` keeps `*.sh` LF (autocrlf is on).
- Added `game/data/schemas/` (ENG standard; P1.15 fills it); README status now reflects the booting skeleton.
- Gotcha: `godot` is not on PATH. For the literal criterion command prepend the local shim dir
  (`$env:PATH = 'D:\lila\tools\godot;' + $env:PATH`; gitignored `godot.cmd` → pinned `_console.exe`).
- Follow-up for ART/P1.16: `window_height_override=1376` does not fit a 1080p desktop; confirm viewport/stretch.

## P0.13 (round 1, 2026-11-02)
- P0.05 carry-overs closed: `tools/godot.sh` committed `100755` (`git update-index --chmod=+x`);
  Darwin branch resolves `Godot.app/Contents/MacOS/Godot` (official zip layout), bare binary as
  fallback — refactored to a per-OS `BINS` candidate array. `Boot.tscn` got a real `uid=` on
  `gd_scene` + `ext_resource` (`ResourceUID.create_id()` via a throwaway `-s` script).
- docs/07 is now canonical for the P0.05 skeleton choices: §1 renderer + pin/launcher rows, §2
  `schemas/` + "Accepted skeleton choices" block. Doc-silent picks are no longer re-litigable.
- **PROVISIONAL — for ART (P0.08/P1.16):** `window_height_override=1376` (768×1376 window, ×2 of
  the 384×688 viewport) is taller than a 1080p desktop. Not fixed in code; ART confirms
  viewport/stretch and clamps or derives the default window to fit the display.
- Gotcha: a fresh worktree lacks `.godot/uid_cache.bin`, so `ext_resource` uids warn once
  ("invalid UID … using text path instead") until `--import` runs — cosmetic, path fallback works.
  CI (P0.07) should run `--import` before headless checks.

## P0.06 (round 1, 2026-11-02)
- Test stack chosen: **gdUnit4 v6.2.2 vendored** at `game/addons/` (v6.2.3 was 1 day old; upgrade = swap dir).
  Tests live in `game/tests/` as `extends GdUnitTestSuite`; seed suite reuses `Boot.EXPECTED_AUTOLOADS` — the
  contract stays single-source. Discovery needs the class cache, so `tools/test.*` runs `--import` first
  (fresh-checkout/CI path verified: wipe `.godot/` → green).
- Gotcha: gdUnit4 v6 **refuses `--headless`** without `--ignoreHeadlessMode` (InputEvents don't propagate
  headless → UI tests would silently no-op). Our convention: logic-only suites. `-c` disables fail-fast.
- gdtoolkit 4.5.0 via `requirements-dev.txt`; `gdlintrc`/`gdformatrc` are YAML at repo root, found by walking
  up from cwd; `excluded_directories` matches dir **basenames** — `addons` entry skips the vendor tree.
- `tools/test.sh`+`.ps1` = gdlint → import → gdUnit4; collects failures, exits 1. `game/reports/` gitignored;
  `*.cmd` pinned CRLF in .gitattributes (vendored runtest.cmd uses goto).
- gdformat canonicalized `Boot.gd` (one-per-line const arrays, parenthesized chains); `gdformat --check` is
  opt-in, not in the pipeline — decide later if format should gate.
- Next: P0.13 carries P0.05 review fixes; my P0.06 silent choices (addons/, tests/, headless flag) also need
  the docs/07 record treatment — listed in the handoff deviations.
