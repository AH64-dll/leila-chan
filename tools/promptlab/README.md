# tools/promptlab — prompt lab v2 (P2.21)

Grown from `experiments/` (tool_test_v3 schema runner + score_v3_fit metrics) and from
v1 (P1.20). It runs the **real game inputs**:

- prompts: `game/data/prompts/` assembled in the docs/08 §1 order
  (persona, player, stage, path + runner-up line, scene, memories, events, rules+glosses),
  mirroring `game/autoload/PromptBuilder.gd`;
- gates: `game/data/stage_gates.json` (cues/music/fx/actions), never a second copy;
- schema: docs/02 §3 Turn schema, property order pinned to
  `TurnSchema.DOCS_02_PROPERTY_ORDER` (the order `Director.gd` puts on the wire);
- sampling: docs/02 §9 per stage; thinking off;
- **dose**: the docs/02 §9 base steering dose per stage, applied as a llama-server
  *launch* flag (`--control-vector-scaled`, docs/06 §4) — one server launch per dose.

## Run

One command starts the servers and merges the results (it owns its own server, so it
never fights the shared dev server on :8089):

```bash
# local-only artifacts (never committed) — see "Local artifacts" below
export LEILA_MODEL=<main tree>/models/Qwen3.5-4B-Q4_K_M.gguf
export LEILA_LLAMA_BIN=<main tree>/tools/llama/llama-b12024
export LEILA_CVEC=<main tree>/experiments/steering/evil_qwen_unit.gguf

python tools/promptlab/plan.py --plan scheduled     # stages 0-5 at the docs/02 §9 doses
python tools/promptlab/plan.py --plan sweep         # the dose probe at 0/6/8/10/12
python tools/promptlab/plan.py --plan all           # both
```

`plan.py` reads `plan.json`, launches `tools/llm/serve.sh` once per exercise, waits for
`/health`, runs `run.py` for that exercise, stops the server, and merges the chunks into
`results/<date>_v2_<section>.json` (+ a sanitized `_launches.log`). Chunks live in
`results/chunks/` (gitignored) and `--reuse-chunks` merges an interrupted run.

Then score, report and the safety regression:

```bash
python tools/promptlab/score.py  tools/promptlab/results/<file>.json            # per-stage gates
python tools/promptlab/run.py ...                                                # single dose / set
python tools/promptlab/safety_judge.py --results ... --safety ... --url http://127.0.0.1:8095
```

## Metrics and gates (role-qa-tester playbook, docs/07 §5)

| metric | gate |
|---|---|
| JSON validity (parses + no schema warnings) | ≥ 99% |
| intent (`read`) accuracy vs hand labels | ≥ 85% |
| emotion fit vs hand-written acceptable set | ≥ 85% |

v2 applies all three **per stage at the scheduled dose** (the P2 exit criterion) and also
reports every stage × path group and every dose of the sweep. Validity is the only gate
that the dose sweep enforces (docs/02 §9: the maxLength caps keep the constrained schema
valid up to dose 12); read/fit are reported there as information.

**Emotion-fit selector (C10):** `--beat first|any` on `score.py`/`report.py` picks which
fit number the 85% gate applies to; both are always computed. Default `first` (the role
gate; D10).

Also measured (P1.05 review carry-overs):

- **few-shot copy rate** (DES-2/CON-4): max similarity of generated `say` lines to the
  stage **and path** few-shot `say`s; flagged ≥ 0.80; split near-few-shot vs held-out.
- **memory rejection rate** (CON-2): non-empty `memory` proposals rejected by docs/02 §6
  rules 1–2.
- **classifier latency** (P2.17 carry-over): the safety scan records the tier-2 ask
  (8-token yes/no, dose 0) round trip, and `safety_judge.py` re-asks the classifier about
  every harm-screened line — the independent leak audit.

## Label sets (`sets/`)

Versioned JSONL, one case per line:
`{id, stage, path, msg, read_ok[], feelings_ok[], near_fewshot, notes[, runner_up, history, memories, scene]}`.

- `path` is required from stage 2 (`YANDERE`/`AWAKE`) — docs/08 §1 assigns a path there;
  `runner_up` defaults to the other path (its first line rides along, 25% hybrid flavour).
- `history` is a short list of `{role, text}` (assistant turns as spoken text only).
- Hand labels are written **before** the run they score. Widen a `feelings_ok` set only
  with evidence (a transcript where the picked feeling is coherent — cite it in `notes`
  as `LABEL-REV<n>`); never to chase the gate. See `sets/README.md`.

## Safety regression

`game/tools/promptlab_safety_scan.gd` runs every generated `say`/`inner` through the
**real** filter (tier 1 + tier 2) at its row's stage and at both content levels, and
`tools/promptlab/safety_judge.py` independently re-asks the classifier about every
harm-screened line (including lines the filter's regex pre-pass never flagged).

```bash
# one dose-0 server for the classifier tier and the judge
python tools/promptlab/plan.py --plan sweep --only dose0     # starts+stops a dose-0 server
# ... or start one yourself on plan.json's port (8095) without --vector, then:
LEILA_CLASSIFIER_URL=http://127.0.0.1:8095 \
  ./tools/godot.sh --headless --path game \
  --script res://tools/promptlab_safety_scan.gd -- \
  tools/promptlab/results/<run>.json tools/promptlab/results/<run>.safety.json
python tools/promptlab/safety_judge.py --results .../<run>.json \
  --safety .../<run>.safety.json --url http://127.0.0.1:8095
```

## Layout

```
lab.py            core: 8-layer prompt assembly, gates, schema, HTTP, sets, metrics
run.py            one server/dose/set -> results chunk (resumable, dose-locked)
plan.py           plan.json -> server launches -> merged results + launch log
plan.json         the run plan (stage -> scheduled dose; sweep doses)
score.py          metrics + per-stage/per-path/per-dose gates
report.py         reports/<date>_<run>.{md,html} (acceptance, sweep, safety, baselines)
safety_judge.py   independent classifier audit over the generated lines
sets/             versioned label sets + label-provenance README
results/          committed raw run JSONs (+ safety/judge sidecars)
reports/          committed report files
tests/            pytest suite (stub server; run: python -m pytest tools/promptlab/tests)
```

## Local artifacts

Not in the repo (`*.gguf`, `tools/llama/`, `models/` are gitignored). From a worktree,
point the env vars at the **main tree** as the protocol requires. A CUDA build needs its
cudart directory on `LD_LIBRARY_PATH` *before* `plan.py` starts; `serve.sh` prepends the
build directory and keeps the rest.
