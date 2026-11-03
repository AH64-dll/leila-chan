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

## P0.15 (round 1, 2026-11-02)
- All four P0.06 carry-overs closed: `tools/test.sh` is `100755`; both runners fail on zero discovered
  suites (pre-check on `game/tests/*.gd` + scan of gdUnit4's `No test cases found, abort test run!`,
  which it prints while exiting 0); `gdformat --check` is now a gating stage (the tree had already
  drifted — `test_bridge.gd` reformatted); export exclusion recorded in docs/07 §2 + README since no
  presets exist (`.gdignore` is wrong — scanner skips the dir and it doesn't exclude from export).
- `tools/test.*` now runs a standalone `--script` stage: top-level `game/tests/*.gd` that don't
  `extends GdUnitTestSuite` execute as SceneTree tests — wired P0.08's `test_bridge.gd` into the
  single command (its handoff asked ENG for this). Convention recorded in docs/07 §2 "Test tooling".
- **Gotcha:** `tools/godot.ps1` resolved the GUI `win64.exe`, which writes to `CONOUT$` and bypasses
  PowerShell pipes — `| Out-String`/redirected logs got nothing. Now prefers `*_console.exe`.
  Git Bash tolerates the GUI exe (output reached the pty), PowerShell does not — keep `_console` first.
- **Gotcha:** capture runner output in a var (`$VAR=$(cmd 2>&1)`) to scan it — piping to `tail`/`grep`
  hides the real exit code (`$?` becomes the last pipe element's). Use `PIPESTATUS` or capture.

## P0.18 (round 1, 2026-11-02)
- P0.15 review carry-overs closed: gdUnit4 stage streams again — bash `2>&1 | tee
  game/reports/gdunit_console.log` + `${PIPESTATUS[0]}`; ps1 uses an `AutoFlush` `StreamWriter`
  passthrough (NOT `Tee-Object -FilePath` — PS 5.1 writes UTF-16 there; verified by `file`).
  Killed a real `while true` suite at 90 s: 2432-byte transcript survived — impossible under `$( )`.
- Zero-suite guard decoupled from console strings: `game/reports/` is wiped pre-run, then a fresh
  `report_*/results.xml` with `<testsuites tests="N">`>0 is required. gdUnit4's zero-case path quits
  before session/report (`GdUnitTestCIRunner.gd:393`), so no-report = fail. Upgrade note in place.
- Gotcha: gdUnit4 writes JUnit XML to `<cwd-of-project>/reports/report_N/` (history keeps 20) — but
  ONLY on the RUN path; abort paths (zero tests, headless refusal, script errors) write nothing.
  Any "assert on report" check must wipe the dir first or a stale report fakes a pass.
- Gotcha: `[xml](Get-Content -Raw $f)` in PS 5.1 needs try/catch around the cast; `$LASTEXITCODE`
  survives `| ForEach-Object` passthrough just like `| Tee-Object`.
- CI already uploads `game/reports/` on failure — the transcript log rides along for free.

## P0.18 (round 2, 2026-11-02)
- Closed the round-1 S2: the JUnit guard now fails **closed**. Both runners check the pre-run wipe
  (bash `rm -rf` status; ps1 `Remove-Item -ErrorAction Stop` in try/catch) and additionally require
  a fresh report — bash `find ... -newer game/reports/.pre_run_marker`, ps1
  `$_.LastWriteTime -gt $runStart`. Wipe failure is fatal, so a stale readable-but-locked
  `results.xml` can no longer fake a green (reproduced on both runners → exit 1).
- Wipe moved above the `game/tests` pre-check so it runs on every call; docs/07 + README now say
  "start of the gdUnit4 stage", not "start of the run" (CODE-3).
- Gotcha: Windows sharing violations are the failure mode — a file opened `FileShare.Read` is
  readable but not deletable. `Remove-Item` without `-ErrorAction Stop` only warns and continues,
  which is exactly how round 1 failed open.
- Gotcha: the bash marker and the accepted report must have distinct mtimes. NTFS gives 100 ns
  resolution, so a normal run is safe; don't move this check to a coarse-timestamp filesystem.
- Excerpt labels: name every elided category and put `...` inside a trimmed block — review CODE-2
  treats an incomplete "verbatim" claim as a defect even when the cited lines are named.
- CI artifact upload still picks up `game/reports/`; `.pre_run_marker` (0 B) rides along harmlessly.
