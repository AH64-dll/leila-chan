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
