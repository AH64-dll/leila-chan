# REL journal — P0

## P0.02 (2026-11-02) — local artifacts imported from E:
- Copied 828 files (~3.1 GB): model gguf → `models/`, malice vector → `experiments/steering/`,
  raw audio pool → `assets/audio/_raw/` (754), `art/_review/` (5), `art/leila_legacy_1x/` (67).
- Verified with per-file SHA-256 manifests diffed source-vs-dest (empty diff = identical); single files
  hashed directly. `tools/local_artifacts.md` records path/size/hash/source + re-verify commands.
- Convention: directories get a "manifest hash" (sha256 of the sorted `sha256sum` listing) — compact,
  reviewer-reproducible, and still proves every file.
- Skipped on purpose: `tools/llama/` on E: is Linux ELF (P0.03 fetches Windows build); `models/.cache/`
  is HF download metadata. Both documented in local_artifacts.md.
- Gotcha: `.gitignore` already covered everything (`models/`, `*.gguf`, `_raw/`, `_review/`,
  `leila_legacy_1x/`, `tools/llama/`) — `git check-ignore -v` is the fast proof.
- Gotcha: producer leaves uncommitted `state.json`/`STATUS.md`/briefs in the tree; commit only your own files.

## P0.12 (2026-11-02) — P0.02 doc-hygiene carry-overs
- Fixed CODE-1/2/3 from the P0.02 code review: README local-artifacts table now lists all five copied
  artifacts (+llama row) with a link to tools/local_artifacts.md; personal `E:/home/...` path scrubbed
  (source now "the design machine's E: drive", re-verify SRC is a `/e/<project-checkout>` placeholder);
  stale `git log` snippet in the P0.02 handoff replaced with `git log --oneline -2 fcf8531` output.
- Convention: when correcting recorded evidence in an old handoff, mark the amendment inline — don't
  silently rewrite history.
- Convention: personal paths stay in historical records (handoffs, review reports) but canonical docs
  (README, tools/*.md) describe sources generically. Residual path lives in SKILL.md — flagged to producer.
- Gotcha: steer_build.py regenerates evil_qwen_unit.gguf from the weights — the README "how to get it"
  for that row is a rebuild command, not a download.

## P0.07 (2026-11-02) — CI on GitHub Actions
- Built `.github/workflows/ci.yml` (PR + push→main + dispatch, pinned `ubuntu-24.04`): tracker
  validate --strict → pytest → gdlint → fetch pinned Godot (URL from `game/.godot-version`,
  verified vs release SHA512-SUMS.txt) → `tools/test.sh`. Green on PR #6; red demo on
  throwaway PR #7 (closed, branch deleted).
- Conventions: new repo-root `tests/` + `pytest.ini` (`testpaths = tests production`) so P0.11's
  track.py suite needs no CI change; pytest==9.1.1 (9.2.0 inside 7-day rule); actions @v7.
- Gotcha: MSYS runs `100644` .sh files fine, Linux CI gets "Permission denied" (126) — always
  `git ls-files -s` the scripts a pipeline executes. Took P0.15's exec-bit item early.
- Gotcha: `godot --import` touches tracked `*.import` mtimes → phantom ` M` in git status;
  `git add` refreshes stat with empty diff. `.import` content stays identical.
- Gotcha: `experiments/tool_test.py` matches pytest's `*_test.py` glob — testpaths scoping,
  not bare-root collection, keeps it out.

## P0.11 (2026-11-02) — pytest suite for track.py + structured validate kinds
- Built `production/tests/test_track.py` (51 cases): fixture builds a minimal production tree in
  `tmp_path` (fixture config/phases + REAL templates + a COPY of track.py) and imports it fresh
  per test → module-level `ROOT`/`CONFIG`/`STATE_PATH` all derive from the fixture, and mutating
  commands (`set`, `review`, `brief`, `gate-brief`) never touch live `state.json`.
- Convention: prefer copy+import-fresh over monkeypatching module globals — any new
  CONFIG-derived global added to track.py later binds correctly for free.
- `cmd_validate` now emits `(ERR|MISSING_REF, msg)` tuples; the old `"missing file" in e`
  substring split is gone. Regression test: a state.json task id containing "missing file"
  must stay a hard ERROR (old code would have downgraded it to WARN + exit 0).
- Gotcha: `_list()` strips only OUTER backticks — a plan cell like `` `README.md`§2 `` keeps an
  inner backtick, breaks `split("§")`, and creates phantom missing-ref warnings. Real docs wrap
  the whole cell: `` `README.md§2` ``.
- Gotcha: validate prints `ERROR <tid>: <check>` for per-task issues but `ERROR <check>` for
  plan-wide ones (dependency cycles have no tid) — assert per-line, not a fixed prefix.
- CI needed zero changes: `pytest.ini testpaths` already collects `production/tests/`.
