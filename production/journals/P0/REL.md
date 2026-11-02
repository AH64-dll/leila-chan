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
