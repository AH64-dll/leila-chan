# Risk register

Seeded from docs/09 §2 and the planning review on 2026-11-02. The producer updates it after every gate.
Row format: `| R<n> | risk | likelihood | impact | mitigation | owner | status |`

| ID | Risk | L | I | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|
| R1 | Model breaks character or repeats over long sessions | M | H | Stage few-shots, 12-turn window, prompt-lab regression, repetition guard (docs/02 §7) | NAR, QA | open |
| R2 | Harmful outputs at high steering (seen in tests) | H | H | Mandatory safety filter, calmer mode, dose cap 12, corpus with 0-miss gate | SAFE | open |
| R3 | Low-end PCs too slow | M | M | Fast mode, CPU fallback, clear min spec (P4.06, P4.10) | LLM, QA | open |
| R4 | Path vectors don't separate | M | M | Prompt modules carry personality; fallback recorded per vector (P3.03) | STR | open |
| R5 | Players feel the AI is "random", not scary | M | H | Game-owned structure (stages, set-pieces, scripted meta events); playtests each phase | SYS, NAR | open |
| R6 | Store rejection (AI content, mature) | L–M | H | Steam first, honest disclosure, content warnings, report button on mobile | REL, SAFE | open |
| R7 | Disk/VRAM on the dev machine | M | L | Work on D: (154 GB free); E: is 95% full and read-only for us; keep only Q4_K_M | REL | open |
| R8 | llama.cpp binaries from the design machine are Linux builds; Windows build or driver mismatch | H | M | P0.03 fetches the Windows CUDA build of the pinned release; Vulkan fallback; WSL as last resort | LLM | open |
| R9 | Agent backend outage or quota (SWE-2 / DeepSeek) stalls production | M | M | Automatic fallback in `subagent`; Claude can review; producer escalates if both are down | PROD | open |
| R10 | Parallel agents conflict on shared autoloads | M | M | Max 3 parallel tasks, pick tasks touching different files, worktree per task, producer merges | PROD | open |
| R11 | Rubber-stamp reviews let defects through | M | H | Evidence-required reviews, cross-backend reviewers, gate review audit (≥ 20% + all safety) | PROD | open |
