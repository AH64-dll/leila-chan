---
name: review-phase-gate
description: Phase-gate review playbook for Leila-chan. Decides whether a phase has met its exit criteria and may close. It verifies integration on main, re-measures the metrics, audits the reviewers by re-checking a sample of approved reviews, and records carry-overs, risks and decisions. Use when executing a phase-gate brief (production/briefs/P*-gate-r*.md).
---

# Review: phase gate (and the reviewers' review)

You decide **PASS** or **FAIL** for a whole phase. You also check that the task reviews were real, because a gate that trusts
rubber-stamp reviews is worthless. You judge; you do not fix. Output: `production/gates/<P>-gate-r<N>.md` from `production/templates/gate_report.md`.

## Procedure
1. **Inputs:** the gate brief, the phase doc (exit criteria, roster), `production/STATUS.md`, `state.json` (read-only),
   every handoff and review report in the phase, and every role journal in `production/journals/<P>/`.
2. **Task completion:** every task is `done`, and its final-round reviews of every required kind are APPROVED. Any exception → FAIL.
3. **Integration on main:** on a clean `main` checkout, run the build, the full test suite, lint, `track.py validate --strict`, and (from P1)
   the prompt lab at the phase's scope. Paste the real output. Something that passed on a branch but fails on main → FAIL.
4. **Exit criteria:** for each numbered criterion in the phase doc, produce your own evidence (re-run the metric, play the build,
   read the playtest material). Copying numbers from handoffs is not evidence. Re-measure, or verify the committed raw data.
5. **Review audit (reviewing the reviewers):**
   - Sample **≥ 20% of approved reviews (minimum 2)**, plus **every safety review** in the phase. Weight the sample toward L-size tasks
     and toward reviewers whose reports were shortest.
   - For each sampled review: pick one acceptance criterion or checklist claim it marked as met, and verify it yourself.
     Check that it contains real command output (not paraphrase) and that its severity calls follow the protocol.
   - Rate each reviewer report **good / weak / invalid**:
     invalid = no real evidence, or approved despite an S1/S2 you can demonstrate;
     weak = evidence present but a criterion was skipped or a severity was misjudged.
   - Any demonstrated missed S1/S2 → **re-open that task** (list it), and the gate FAILS until it is fixed and re-reviewed.
   - Two or more *weak* or *invalid* reports from the same review kind → recommend tightening that playbook (write the exact
     checklist line to add) in the report's carry-overs.
6. **Cross-role drift:** read the journals for conflicting conventions (e.g. two signal naming schemes, duplicate utilities).
   Each conflict becomes a carry-over task.
7. **Carry-overs:** list S3/S4 findings left open and the proposed new tasks (title, role, size, target phase).
8. **Risks and decisions:** update proposals for `production/RISKS.md`. List the OPEN decisions the next phase needs from the user.
9. **Verdict:** PASS only if 2–5 are all clean. Otherwise FAIL, with an exact list of what must happen before re-gating.

## Checklist
- [ ] All tasks done with approved final-round reviews
- [ ] Clean-main build, tests, lint, validate, prompt lab: real output pasted
- [ ] Every exit criterion has independently produced evidence
- [ ] Review audit: sample size met, all safety reviews included, each sampled report rated
- [ ] Missed-defect re-opens listed (or "none")
- [ ] Journals read; drift recorded
- [ ] Carry-overs, risks and next-phase decisions written

## After you
The producer personally re-verifies two of your audit rows before recording the gate. Your report is audited too.
