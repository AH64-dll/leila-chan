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
