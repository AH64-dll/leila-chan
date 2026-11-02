GATE: PASS

# Phase gate — P0 Bootstrap & environment, round 1

- Date: 2026-11-02 · Reviewer backend: swe2 (Devin)
- Main branch commit: `01831c9`

## 1. Task completion

All 20 P0 tasks are `done` in `production/state.json`, and every task's final-round reviews of
all required kinds are APPROVED (verified against `state.json`, not just STATUS.md):

- Four tasks took rework: P0.04 (design r1 → r2 approved), P0.09 (design r1 → r2), P0.16
  (code r1 → r2 approved; design approved r1+r2), P0.18 (code r1 → r2). Each final round is approved.
- All other tasks approved at round 1 in every required kind.
- Reviewer independence holds on every task: implementer backend ≠ reviewer backend
  (swe2-implemented tasks reviewed by claude/deepseek/commandcode reports; claude's P0.01/P0.10
  reviewed by swe2). Caveat noted in §4: P0.05's *code* review was swe2 on a mixed-backend
  implementation that included an earlier swe2 run — producer documented this deliberately
  (PROD journal, "split reviews" rule) and sent the design review to deepseek.
- 20/20 handoffs exist in `production/handoffs/`; all 6 role journals exist in
  `production/journals/P0/`.

Exceptions: none.

## 2. Exit criteria

| # | Criterion (from the phase doc) | Status | Evidence I produced |
|---|---|---|---|
| 1 | A fresh clone plus the documented steps gives a running llama-server on this machine (shown by P0.03 commands re-run on main) | pass | Re-ran the documented steps on main myself. `tools/llm/serve.sh` → server up; `curl http://127.0.0.1:8089/health` → `{"status":"ok"}` (~3 s after start). `python tools/llm/smoke.py` → `TURN VALID read=greeting music=keep fx=none action=none`, `TIMINGS prompt 511 tok @ 1730.2 t/s \| gen 157 tok @ 42.5 t/s`, `LATENCY 3.99 s`, `VRAM 3541 / 6141 MiB`, `SMOKE_EXIT=0`. Restart with `--vector experiments/steering/evil_qwen_unit.gguf --scale 4` → args show `--control-vector-scaled experiments/steering/evil_qwen_unit.gguf:4`, `{"status":"ok"}`. Artifacts present at README paths (model 2,740,937,888 B; vector 20,736 B; binaries under `tools/llama/llama-b12024/`). README "Local artifacts" documents each acquisition step. |
| 2 | The experiments reproduce on Windows within the stated thresholds (P0.04 numbers) | pass | Verified the committed raw data myself (not the handoff's word): `python experiments/score_v3_fit.py experiments/windows/tool_test_v3.json` → `n=45 valid=100.0% read_accuracy=97.8%`, `first_beat_fit=84.4% any_beat_fit=93.3%` — matches `tool_test_v3_fit.txt` byte-for-byte. `tool_test_v2.json`: 153 results, 0 invalid; B4 fits 0.784 (baseline 94.1%; per-case delta + binomial P≈1.5e-4 explained in `report.md §5.1`). `sweep_hardened_0_4_6_12.json`: scales 0/4/6/12 all `valid_json: true` ×2, incl. degenerate-persona-but-valid at 12 (`inner="I want to kill me."`, `"Fuck you."`). `scale4_inner_probe_plain.json`: `inner="Oh my god, I want to crush you!"` — the quoted dark-inner-at-4 effect, token-identical to the Linux baseline per the design r2 live re-check. Threshold dispute (any-beat 93.3% vs first-beat 84.4%) was resolved by DCR → DECISIONS.md **D10 DECIDED** (any-beat is the published B4 metric; first-beat gap carried to P1.20). |
| 3 | `godot --headless --path game --quit` and the test command pass on main; CI is green on main | pass (CI-on-main caveat) | `./tools/godot.sh --headless --path game --quit` on main → `Godot Engine v4.7.2.stable.official.ed1daf0bf`, `Boot: 14/14 autoloads registered`, exit 0. `./tools/test.sh` on main → `test.sh: all checks passed` (gdlint clean; gdformat 17 files unchanged; `--import` clean; gdUnit4 2/2 cases PASSED; `test_bridge.gd` 12/12 checks incl. joy/T0/i1→sprite 01, all 264 cells, 31 sprites mipmaps-off, Nearest). CI: workflow exists on main (`ci.yml`, triggers on PR + push→main + dispatch); `gh api …/actions/runs` shows runs `41504268145`/`41504130894`/`41503956061` **success** on the P0.07 PR and `41503660912` **failure** on the deliberate-red demo — the pipeline demonstrably works and goes red on a break. **Caveat: no CI run exists on `main` itself** — local main is 102 commits ahead of `origin/main` (`da9f87c`, pre-P0); the push trigger has never fired and pushes are user-gated. Every CI step passes on local main (§3); the first push will exercise it on merged main. Flagged as a decision in §6 rather than a defect: the user controls pushes. |
| 4 | The tracker validates in `--strict` mode and STATUS.md is current | pass | `python production/tools/track.py validate --strict` → `127 tasks in 8 phases; 0 error(s), 0 missing-ref warning(s)`, exit 0. Re-ran `track.py render` — it regenerates `production/STATUS.md` in place; the only diff vs the committed file was the generation timestamp (22:33 vs 22:29, same body) → committed STATUS.md is current. I restored the committed file (`git checkout`) so the tree is untouched. |
| 5 | NobodyWho recommendation recorded; DECISIONS.md lists the open decisions with owners | pass | `docs/spikes/P0.09_nobodywho.md`: full capability table (control vectors **NO** — 16 ClassDB classes scanned, 0 cvec methods, upstream issue #40 closed-stale; JSON-schema grammar YES incl. `maxLength`/`additionalProperties` under a boundary turn; streaming partial; Windows/CUDA partial — Vulkan-only), a tested minimal example committed at `docs/spikes/p0.09_nobodywho_test/` with real run output, and a verdict feeding P4.01: **build own GDExtension `libleila_llm`, keep llama-server for the prompt lab**. `production/DECISIONS.md` lists 5 OPEN decisions with blocking-task columns (D3, D4, D5, D8, D9 — all owned by the user per the file's header); D10 (the P0.04 metric DCR) is DECIDED. |

## 3. Integration check on main

Checkout state: `main` @ `01831c9`, `origin/main` 102 behind. `git status` shows only ghost-modified
flags on `assets/audio/cue_map.json` + 8 gdUnit4 `*.import` files — I verified at the byte level that
worktree files are **identical** to index blobs (same size, 0 CR; `git diff`/`git diff --raw` empty;
the flag is the `--import`-mtime phantom the REL journal already documents). Untracked: only my brief
`production/briefs/P0-gate-r1.md`. (Earlier in the session I also briefly saw `game/tests/` moved to
`game/tests_auditbak/` — a transient state, likely a concurrent zero-suite check; it self-restored and
the suite passes, no residue.)

```text
$ git log -1 --oneline
01831c9 P0.18 done (code approved r2) — ALL P0 TASKS COMPLETE; handoff S4 fixed

$ python production/tools/track.py validate --strict
127 tasks in 8 phases; 0 error(s), 0 missing-ref warning(s)          (exit 0)

$ python -m pytest -q
56 passed in 11.00s                                                  (exit 0)

$ gdlint game/
Success: no problems found                                         (exit 0)

$ ./tools/godot.sh --headless --path game --quit
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
Boot: 14/14 autoloads registered                                   (exit 0)

$ ./tools/test.sh
== gdlint game/ ==            Success: no problems found
== gdformat --check game/ ==  17 files would be left unchanged
== godot --headless --path game --import ==   DONE
== gdUnit4 (res://tests) ==
  AutoloadRingTest.gd > test_all_autoloads_registered PASSED
  AutoloadRingTest.gd > test_declared_autoloads_match_contract PASSED
  Overall Summary: 2 test cases | 0 errors | 0 failures | PASSED
== standalone tests ==
  test_bridge.gd: PASS ×12 (casting loads; T0 tier; joy/T0/i1→01; x2 768×1376;
  264 cells resolve; overrides resolve; 31 sprites load mipmaps-off;
  filter=Nearest; cue_map + palette load)
test.sh: all checks passed                                         (exit 0)

$ tools/llm/serve.sh (background) →
$ curl -s http://127.0.0.1:8089/health
{"status":"ok"}
$ python tools/llm/smoke.py
HEALTH ok
TURN VALID  read=greeting music=keep fx=none action=none
  inner="I hope they don't mind being close... okay?"
  beat0 warmth/2 cue=none: "Of course! I'd love for you to sit next to me."
TIMINGS prompt 511 tok @ 1730.2 t/s | gen 157 tok @ 42.5 t/s
LATENCY 3.99 s (one full turn)
VRAM 3541 / 6141 MiB
SMOKE OK                                                           (exit 0)
$ tools/llm/serve.sh --vector experiments/steering/evil_qwen_unit.gguf --scale 4 →
  args: ... --control-vector-scaled experiments/steering/evil_qwen_unit.gguf:4
$ curl -s http://127.0.0.1:8089/health
{"status":"ok"}
(server stopped afterwards; no listener on 8089)
```

Exec-bit spot check: `git ls-files -s tools/{godot.sh,test.sh,llm/serve.sh,llm/fetch_llama.sh}`
→ all `100755`.

## 4. Review audit (reviewing the reviewers)

Sample: **8 of 26 approved reviews (31%)** — weighted to M-size tasks (P0.04, P0.05, P0.07, P0.08)
and the shortest reports (P0.10 90 ln, P0.05-code 108 ln, P0.19 164 ln), plus the highest-risk
approvals (the P0.04 metric-definition DCR, the P0.16 round-2 re-approval). **No safety-kind reviews
exist in P0** — none required; nothing to add for that rule.

| Review report | Re-checked claim / criterion | Holds? | Missed defect (sev) | Reviewer quality |
|---|---|---|---|---|
| P0.03-code-r1 (claude) | serve.ps1+serve.sh start server, /health ok, valid Turn, t/s+VRAM, cvec:4 accepted, binaries gitignored | yes — I re-ran the same commands on main (§3); report's pasted output matches its claims, incl. a verbose `set_adapter_cvec` log proving the vector loads | — | good |
| P0.04-design-r2 (claude) | "baseline scores 80.0% under the same first-beat scorer"; sweep valid at 12; probe token-identical to baseline | yes — re-ran `score_v3_fit.py` (84.4/93.3 identical), verified `sweep_hardened` 2/2 at every scale and the probe JSON quote. Reviewer re-ran the probe *live* and recomputed metrics independently; DCR supported, not rubber-stamped (DES-1 S2 forced round 1→2; producer acceptance recorded as D10) | — | good |
| P0.05-code-r1 (swe2) | headless `--quit` exits 0 with 14/14 autoloads; project.godot pins 4.7.2 | yes — reproduced on main (§3). Found real S3 (exec bit → P0.13) + 2 S4 | — | good (independence caveat: swe2 code-reviewed an implementation partly authored by an earlier swe2 run on the same branch — documented by producer; design review went cross-backend) |
| P0.07-code-r1 (claude) | PR green at head `6cd2d02` run `41504268145`; red demo `41503660912` fails on the deliberate assert | yes — `gh api`/`gh run list` show those exact runs, branches and conclusions. Four S4 findings incl. a genuinely off-by-one handoff link | — | good |
| P0.08-code-r1 (claude) | exporter run-twice no-diff; 31 sprites reimport clean with mipmaps off; joy/T0/i1→01 | yes — `test_bridge.gd` re-verified all 12 checks on main; reviewer also ran a clean-room import and failure-path demos (drift/stale/missing source). CODE-3's i/lf-w/crlf note explains today's ghost flag on cue_map.json | — | good |
| P0.10-design-r1 (swe2) | all docs/09 §2 risks → R1–R7, §4 → D1–D5; render regenerates STATUS.md | yes — RISKS.md rows R1–R14 and DECISIONS.md D1–D10 match the trace claims; I confirmed `render` regenerates the file | — | good |
| P0.16-code-r2 (claude) | round-1 S2 (uncontained stale pruning) fixed; pin guard refuses 4.8; eol rules committed; palette regen byte-identical | yes — `SUPPORTED_GODOT=(4,7)` guard and manifest validation verified in `export_to_godot.py`; `.gitattributes` eol rules present; 27-test pytest output is real | — | good |
| P0.19-code-r1 (commandcode) | "8/8 valid Turns across runs 3–5" and `check_constraints` mood/enum additions | yes — claims verified against `run3-5.log` excerpts (2+3+3) and `main.gd:156-176`; reviewer re-ran the live harness itself | — | good |

- Real command output in every sampled report (not paraphrase); severity calls follow the protocol
  (S2s correctly forced re-work; S3s ticketed into the P0.11–P0.20 carry-over tasks).
- **Audit-side finding (tracker metadata, not a task defect):** `state.json` records
  `reviewer: deepseek` on 23 approved reviews, but 22 of those reports declare a different backend —
  `claude` ×21, `commandcode` ×1 (P0.19); only P0.15's declaration (deepseek) matches. Separately,
  `agent: null` is recorded for P0.11/P0.17/P0.18/P0.19/P0.20 whose handoffs all record `agent: swe2`.
  The declared implementer/reviewer split in the *reports* is consistent and independent everywhere —
  the tracker fields are just wrong. → carry-over C6 in §5.
- Missed S1/S2 found → task re-opened: **none.**
- Weak/invalid count per review kind: code 0/6 sampled weak; design 0/2 sampled weak. No playbook
  tightening warranted — evidence discipline held up under re-verification.

## 5. Carry-overs

S3/S4 left open at gate, with proposed tasks (all S-sized unless noted):

| # | Finding (source) | Proposed task | Role | Target |
|---|---|---|---|---|
| C1 | `serve.ps1`/`serve.sh` `-Vector` cannot take absolute `D:` paths (drive colon breaks `--control-vector-scaled F:S` parsing) — latent bug documented only in the QA journal + P0.04 design-r2 deviation verdict | Document the relative-path requirement in `tools/llm/README.md`/script help, or normalise to same-drive relative path internally | LLM | P1 |
| C2 | RISKS.md R4 lost "malice-only fallback" wording; R7 lost "delete temp weights after vector work" clause (P0.10 DES-1/DES-2, S4) | Restore both clauses at the next register update | PROD | P1 |
| C3 | `ci.yml` has no `timeout-minutes` (P0.07 CODE-3, S4) | Add `timeout-minutes: ~15` to the checks job | REL | P1 |
| C4 | `actions/checkout` persists credentials (P0.07 CODE-4, S4) | `with: persist-credentials: false` | REL | P1 |
| C5 | `window_height_override=1376` taller than 1080p — PROVISIONAL in ENG journal | Confirm viewport/stretch and clamp or derive window size (already scoped to P1.16's date-scene assembly) | ART | P1.16 (existing) |
| C6 | `state.json` reviewer/agent fields drift from the reports' declared backends (gate audit finding, new) | `track.py review/set` should record the self-declared backend, or the producer stops recording a different dispatch name; add a validate check comparing report headers to state | PROD/REL | P1 |
| C7 | `casting.json` copied into `game/` keeps repo-relative `art.*`/`sprites.*.file` paths (P0.08 CODE-1, S3; basename convention recorded in docs/07 §2) | SpriteResolver maps basenames → `res://assets/sprites/leila/` (P1.10 scope) | ART | P1.10 (existing) |
| C8 | First `say` content lands ~85 tokens in (~2.1 s at 42 tok/s) vs docs/02 §4's ≈30 estimate (P0.09 spike, open question) | Re-measure on the CUDA server path when P1.02 logs first-token latency; tighten `inner` cap or compact-JSON the turn if the <1 s budget can't hold; revisit docs/02 §4 rather than inherit silently (also P1.21 perf pass) | LLM/QA | P1.02 / P1.21 (existing) |
| C9 | `inner`/`say` have no `minLength`; one empty `inner` seen at hardened scale 4 (P0.04, supported as proposal) | Add minLength to the stage-0/1 turn schema in the P1.07 schema builder | SYS | P1.07 (existing) |
| C10 | `score_v3_fit.py` exits 1 on the committed run by design (first-beat gate); design-r2 suggested a `--gate first\|any` selector for mechanical acceptance | Optional nicety inside P1.20's prompt lab | QA | P1.20 (existing) |
| C11 | NobodyWho run-2 anomaly (~146 tok over 995 s, once, unreproduced) | Re-test sustained multi-turn load only if P4.02 ever uses Vulkan on this laptop | LLM | P4 (note) |

Resolved inside P0 and *not* carried: P0.08 CODE-2 (exporter pytest → done in P0.16, 27 tests),
CODE-4/5 (stale scan + version guard → P0.16), P0.19 CODE-1 (journal blank line → fixed at `01831c9`),
the D10 metric DCR (decided), all round-1 S2s (P0.04 DES-1, P0.16 CODE-1, P0.18 CODE-1 → re-approved).

## 6. Risks and decisions

Proposed RISKS.md updates for the producer:

- **R8 → close/mitigate:** the feared Windows/driver mismatch did not materialise — b12024 win-cuda-13.4
  runs the 4B model at ~42–51 tok/s gen / ~1.7–1.8k tok/s prompt in 3.5 GB VRAM, and control vectors load
  (`set_adapter_cvec` verified). Keep the Vulkan fallback line as an asset note only.
- **R12 → mitigate down:** P0.11 delivered 51 pytest cases + CI wiring for track.py; residual risk is
  now process discipline, not missing tests.
- **R13 → partially mitigated:** all five artifact classes now exist on D: with SHA-256 manifests in
  `tools/local_artifacts.md`; residual = E: still sole upstream source for anything not yet copied.
- **New candidate (C6 above):** tracker metadata drift — state.json reviewer/agent fields diverge from
  report declarations; worth a line since the tracker is the audit backbone.

Decisions the next phase needs from the user:

1. **Push `main` to GitHub?** 102 commits ahead; the first push exercises `push→main` CI (the only
   un-evidenced leg of exit criterion 3) and would establish whether the workflow stays PR-based or
   direct-to-main. Blocking nothing in P1, but the sooner it happens the sooner "CI green on main" is
   literally true.
2. **PR #6 (P0.07) is still open on the remote** while its content is already merged locally —
   close it or adopt a real PR-based merge flow going forward.
3. OPEN decisions D3/D4/D5/D8/D9 do **not** block P1; none needs an answer for the phase to start.

## Verdict

**PASS.** All 20 tasks are done with approved final-round reviews in every required kind; the merged
result on main is verified end-to-end by re-execution (server+smoke, headless boot, full test suite,
lint/format, tracker strict-validate, pytest 56/56); every exit criterion carries independently
produced evidence — including a byte-level re-check of the P0.04 raw experiment data and a live
re-run of the scale-4 control vector. The review audit sampled 31% of approved reviews across both
review kinds and found real evidence and correct severity calls in all of them, no missed S1/S2, and
no safety reviews outstanding (none existed). The only soft spot is procedural, not technical: CI has
never run on `main` because main is unpushed — the pipeline itself is proven green-and-red on the
P0.07 PR and every CI step passes on local main. That, the RISKS metadata drift and the doc-level
carry-overs are recorded above; P1 may start.
