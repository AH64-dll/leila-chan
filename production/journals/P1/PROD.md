# PROD journal - P1

## Kickoff
- User authorized P1 execution through completion and independent review.
- P0 gate is closed; no OPEN decision blocks P1. No authority to push or publish P1 is assumed.
- Seeded P1.23-P1.26 for P0 gate C1/C3/C4/C6 and documented ownership for the remaining carry-overs.
- Initial wave: P1.01 LLM facade, P1.04 GameState, P1.05 prompt files; separate ownership and critical-path dependencies.
- Preserve existing audio/import-file working-copy noise (empty content diff).
- Human playtest P1.22 requires three real participants; prepare materials, never fabricate transcripts or surveys.
- Monitor silent agents by filesystem/commits/processes; never duplicate-dispatch before confirming the old child exited.

## Foundation wave monitoring
- Baseline pytest: 56 passed before integration.
- P1.05 implemented by SWE-2 at 29fd924: fixed layers 857/873 tokens, six real-model turns valid; content/design reviews dispatched to DeepSeek.
- P1.01 implemented by SWE-2 at f69c15e: worker facade and eleven new fake-backend cases; code/design reviews dispatched to DeepSeek.
- P1.03 parser and P1.19 safety filter dispatched into freed implementation slots; P1.04 GameState remains active.
- One P1.05 content-review launch exited 1 on Command Code's Windows config-rename EPERM before writing a report; restarted only after confirmed exit.
- Concurrent DeepSeek startup can race on its shared config file. Stagger future starts; do not treat CLI failure as a task verdict.
- Active shell ledger: P1.04 impl c6f09b; P1.03 impl 264388; P1.19 impl 7cd798; P1.05 content 1b83a0/design 355058; P1.01 code 68ea06/design 80cdc6.

## First integrations and state rework
- P1.01 merged and closed after main's full PowerShell gate: 13/13 gdUnit4, lint/format/import/bridge green.
- P1.05 merged and closed after both reviews; main few-shot validator and pytest 56 passed. P1.27/P1.28 ticket follow-ups.
- P1.01 and P1.05 design/content reports self-label claude despite confirmed DeepSeek dispatch; preserve originals, record actual backend deepseek, retain launch evidence here for P1.26's audited legacy override.
- P1.04 both reviewers requested changes: unsafe peak restore, live-state-dependent restore and lowercase path ids. No merge.
- Tracker refused the second parallel changes verdict once the first moved P1.04 out of in_review. Preserve both reports; r2 brief explicitly names both. P1.26 owns the recording fix.
- P1.04 r2 goes to SWE-2; P1.24 enters DeepSeek code review. Keep three implementation slots (P1.04/P1.10/P1.19).

## Cross-runner integration catch
- P1.04 r2 code/design both approved at c073e0a; attempted main integration 01fa048.
- Main PowerShell gate exited 1 at the intentional GameState.from_dict warning in the restore-negative test, before the suite completed.
- Root cause: tools/godot.ps1 uses ErrorActionPreference Stop during native invocation; PowerShell 5.1 promotes captured native stderr to a terminating NativeCommandError.
- Do not mark P1.04 done. Revert its integration while P1.30 fixes the upstream launcher, then reverse that revert and re-run both full gates before closing it.
- P1.30 regression must preserve real nonzero exit codes, visible stderr, zero-suite and stale-report guards; do not silence warnings in game code.
- SWE-2 rate-limited; P1.10/P1.19/P1.02 continued on DeepSeek. Track actual final implementer backend and retain mixed-backend provenance.
- Current shells: P1.10 4fab70, P1.19 7cd798, P1.02 abf258. P1.03 r2 queued; P1.04 r2 reviews complete.

## Independent reviews after SWE-2 outage
- To preserve actual model independence for final-DeepSeek implementations, used separate native review agents (backend devin-native), not DeepSeek self-approval; no config or dispatch default changed.
- P1.10 code review 64bad6c5 requested changes: fractional settled crop zoom violates pixel-perfect acceptance; reduced motion does not stop active camera tweens/lean-in.
- P1.19 safety review f2c5769d requested changes despite green supplied corpus: negation/obfuscation/generated Japanese bypasses, coordinate streaming leakage, incomplete config fail-open, implicit full-content default, diagnosis-text sensitivity gap.
- User explicitly approved DCR-1 via the safety-policy choice: stage 4/5 AND full content may show fictional threats; hard blocks remain. Recorded D11. This resolves SAF-6 only, not the demonstrated defects.
- P1.19 supplied benign headline excluded a known FP; include all 138 lines (actual 1/138 = 0.72%, still under 5%).
- P1.10/P1.19 must be reworked and independently re-reviewed; neither is merged.

## Current dispatch ledger (after user D11 answer)
- P1.02 completed at c2dacd3 (DeepSeek): real SSE/schema/crash checks green; first usable say median 1855 ms / p95 2418 ms, explicitly misses phase <1 s gate. Native code reviewer f1abfcb0 running; design review still to dispatch.
- P1.03 r2 completed at 21373db (DeepSeek); native code reviewer c0b2aa00 running; design re-review still to dispatch.
- P1.30 completed at 6d09567 (DeepSeek), launcher regression 6/6; native code reviewer 11ebee1a running. Its temporary GameState reapplication was removed: merge P1.30, then reverse 38ea118 on main and test before closing P1.04.
- Implementation slots: P1.19 r2 db4566; P1.10 r2 e35d13; P1.26 r1 f87196 (all launched SWE-2 first after rate reset; inspect wrapper result for fallback).
- P1.04 remains in_review, both r2 reviews approved; original implementation is not currently integrated due to 38ea118.
- Closed tasks: P1.01, P1.05, P1.24 only. Do not confuse completed branches with reviewed/merged/done tracker state.
- Next implementation priorities after slots free: P1.06/P1.07 after P1.04 is restored/closed; P1.12 audio and P1.13 UI are independent ready tasks.
- Queued follow-ups P1.25 (CI credentials plus P1.24 nits), P1.27 (facade contract/cancel/error), P1.28 (prompt evidence), P1.29 (state r2 hardening). P1.20 promptlab is ready but coordinate GPU ownership with live backend review.
- Native review reports use devin-native, preserving actual independence from SWE-2 and DeepSeek implementations. Avoid simultaneous full runners in the same worktree; start the next review kind only after the first exits.
