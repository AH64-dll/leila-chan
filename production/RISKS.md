# Risk register

Seeded from docs/09 §2 and the planning review on 2026-11-02. The producer updates it after every gate.
Row format: `| R<n> | risk | likelihood | impact | mitigation | owner | status |`

| ID | Risk | L | I | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|
| R1 | Model breaks character or repeats over long sessions | M | H | Stage few-shots, 12-turn window, prompt-lab regression, repetition guard (docs/02 §7) | NAR, QA | open |
| R2 | Harmful outputs at high steering (seen in tests) | H | H | Mandatory safety filter, calmer mode, dose cap 12, corpus with 0-miss gate | SAFE | open |
| R3 | Low-end PCs too slow | M | M | Fast mode, CPU fallback, clear min spec (P4.06, P4.10) | LLM, QA | open |
| R4 | Path vectors don't separate | M | M | Prompt modules carry personality; malice-only fallback if paths don't separate; fallback recorded per vector (P3.03) | STR | open |
| R5 | Players feel the AI is "random", not scary | M | H | Game-owned structure (stages, set-pieces, scripted meta events); playtests each phase | SYS, NAR | open |
| R6 | Store rejection (AI content, mature) | L–M | H | Steam first, honest disclosure, content warnings, report button on mobile | REL, SAFE | open |
| R7 | Disk/VRAM on the dev machine | M | L | Work on D: (154 GB free); E: is 95% full and read-only for us; keep only Q4_K_M; delete temp weights after vector work | REL | open |
| R8 | llama.cpp binaries from the design machine are Linux builds; Windows build or driver mismatch | H | M | P0.03 fetches the Windows CUDA build of the pinned release; Vulkan fallback; WSL as last resort | LLM | open |
| R9 | Agent backend outage/quota, or **silent-output dispatches misread as stalls** (seen P0.05: swe2 `-p` emitted no stdout while working; killing the wrapper left devin.exe alive → double-dispatch race) | M | M | Fallback covers exits/errors only; producer monitors worktree file/git activity not stdout; never re-dispatch until the old child is confirmed dead (process list + no fs activity); Claude can review; escalate if both down | PROD | open |
| R10 | Parallel agents conflict on shared autoloads | M | M | Max 3 parallel tasks, pick tasks touching different files, worktree per task, producer merges | PROD | open |
| R11 | Rubber-stamp reviews let defects through | M | H | Evidence-required reviews, cross-backend reviewers, gate review audit (≥ 20% + all safety) | PROD | open |
| R12 | `track.py` is producer-critical but has no automated tests; a defect could corrupt state.json | M | M | P0.11 adds pytest coverage; `validate --strict` after every change; state.json is committed so history allows recovery | REL, PROD | open |
| R13 | E: is the sole source of local artifacts (model gguf, steering vector, raw audio) and is 95% full | M | H | P0.02 copies + SHA-256 verifies everything onto D: early; `tools/local_artifacts.md` records hashes; audio re-sourcable via SOURCES.json — weights are not | REL | open |
| R14 | In-place tasks (P0.01–P0.03) commit directly on main; a bad agent run could land broken work | M | M | Reviews gate the done flag; commits are atomic and revertable; producer sanity-checks diffs before review | PROD | open |
| R15 | Tracker metadata drift: state.json reviewer/agent fields record the dispatched backend name while reports self-declare differently (gate C6); the agent field is null on 5 tasks | L | M | Dispatch-time record is authoritative; add a validate check comparing report headers to state, or have track.py record the self-declared backend (P1 carry-over) | PROD | open |
| R16 | The tier-2 classifier releases harmful text the corpus test reports as caught, because that test's oracle always answers yes. Real-model recall is 15/31, and 14 harmful lines display at stage 0 | H | H | Decision D43. `classify_corpus.gd` and `classify_parity.py` measure it with the real model | SAFE | open |
