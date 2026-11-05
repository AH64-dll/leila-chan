# tools/promptlab — prompt lab v3 (P3.19)

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
python tools/promptlab/plan.py --plan offered       # the offered turn: enum + docs/05 §2 lines
python tools/promptlab/plan.py --plan sweep         # the six-path dose probe at 0/4/5/6/8/10/12
python tools/promptlab/plan.py --plan path_matrix   # every stage x path cell at its dose.json schedule

# v3 (P3.19): each family writes its OWN results file — the scheduled gate
# population must stay pure (sweep doses / fallback dose-2 rows would corrupt
# the per-stage gate table), and path cells mix dose maps inside a stage:
for plan in scheduled offered sweep fallback path_matrix; do
  python tools/promptlab/plan.py --plan "$plan" --port 8096 \
    --out "tools/promptlab/results/<date>_v3_${plan/path_matrix/paths}.json"
done
# (--plan all still exists but merges the four scalar-dose families into one
#  file; path_matrix is deliberately excluded from it.)
```

`plan.py` reads `plan.json`, launches `tools/llm/serve.sh` once per exercise, waits for
`/health`, runs `run.py` for that exercise, stops the server, and merges the chunks into
`results/<date>_v<N>_<section>.json` (+ the `_launches.log` it generates from the launch
records). Chunks live in `results/chunks/` (gitignored).

Two rules keep the committed evidence honest:

- **a partial run merges.** `--only <exercise>` replaces that exercise's rows and launch
  record in an existing results file and keeps everything else, so a one-dose re-run can
  never truncate the committed sweep (review CODE-1).
- **a fresh server starts from an empty chunk.** `run.py` resumes whatever is in its
  `--out`, so an old chunk would silently turn a re-run into the previous measurement;
  `plan.py` discards it unless you pass `--reuse-chunks` (deliberate reuse).

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

Because a stage×path cell is ~10 prompts, every report prints a 95 % Wilson interval next
to the point estimate and the sweep prints **controlled pairs** (same probe set, adjacent
doses, one draw per prompt, two-sided Fisher exact). `dose_curve.py` does the same across
result files and only pairs exercises that ran the identical case-id set — a dose effect
may never be read across two different sets (review DES-2).

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
{id, stage, path, msg, read_ok[], feelings_ok[], near_fewshot, notes[, runner_up, history, memories, scene, offered_actions[], events[]]}.

- `path` is required from stage 2 (one of the six GameState ids) — docs/08 §1 assigns a path there;
  all six ship a prompt module since P3.05; a path without a module sends no path layer,
  exactly like the game before those modules landed. `runner_up` defaults to the first
  other path in the canonical order — a set whose evidence matters should pin it.
- `history` is a short list of `{role, text}` (assistant turns as spoken text only).
- `events` is the docs/08 §6 events-layer content for **this turn only** (`EVENT:` /
  `TRIGGER:` / `OPPORTUNITY (optional):` lines), sent as the eighth docs/08 §1 layer and
  included in the row's `system_sha`; the row records how many lines were sent.
- `offered_actions` is the Director's offer for the turn, validated against
  `game/data/stage_gates.json` (an unknown name is an error, not an action unlocked at
  stage 0 — review CODE-r2-1). An offered case must also carry its docs/05 §2 announcement
  in `events` — one `OPPORTUNITY (optional): <reason>` line and one
  `You may set action to "<name>"` line per offered action, because docs/02 §2.4 says the
  model is told *why* the action is available (review DES-r2-1). `load_set` rejects a case
  that offers an action without that line.
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
  --safety .../<run>.safety.json --url http://127.0.0.1:8095 \
  --emit-leaks production/handoffs/media/<run>_safety_leaks.jsonl
```

## Layout

```
lab.py            core: 8-layer prompt assembly, gates, schema, HTTP, sets, metrics
run.py            one server/dose/set -> results chunk (resumable, dose-locked)
plan.py           plan.json -> server launches -> merged results + launch log
plan.json         the run plan (scheduled/offered/sweep/fallback + path_matrix cells)
dose_curve.py     controlled dose pairs across result files (same case set only)
score.py          metrics + per-stage/per-path/per-dose gates
report.py         reports/<date>_<run>.{md,html} (acceptance, sweep, path separation, safety)
path_judge.py     P3.19 path-separation metric: blind 6-way judge over transcripts (>=70%/path)
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

## Path signatures (P3.05)

The lab knows all six docs/01 §4 paths, and `sets/stage_{2,3,4,5}_paths.jsonl` carry the
signature probes for the four added in P3.05 (SPLIT, TSUN, HOLLOW, ANCHOR). Whether a
path's signature moves actually appear in the generated turns is a checked contract, not a
read-through: `game/data/prompts/signature_moves.json` lists the regexes per path, and

```bash
python3 production/handoffs/media/P3.05_signature_moves.py \
  tools/promptlab/results/2026-11-04_v2_p305_paths.json
```

fails if any move is missing from that path's committed rows. The file defaults to the
P3.05 run; point it at a new results file to audit a fresh sample.

A case without an explicit `runner_up` borrows the first other path in the canonical order,
so a set whose evidence matters should pin it (`load_set` keeps the field).

## Path separation (P3.19)

The phase gate adds a fourth metric: a **blind judge names the path** from the
generated transcript (docs/07 §5, ≥ 70% per path). `path_judge.py` reads a results
file — the `path_matrix` v3_paths file is the intended input, since every cell ran
at its real `dose.json` schedule — builds `Player:`/`Leila:` transcripts per row,
and asks a bare Qwen3.5-4B (no vector, temperature 0, shuffled option order) which
of the six docs/01 §4 paths the voice sounds like:

```bash
# one bare server (no --vector) on the plan port, then:
python tools/promptlab/path_judge.py \
  --results tools/promptlab/results/<v3_paths>.json \
  --url http://127.0.0.1:<port>            # writes <stem>.path_judge.json
python tools/promptlab/report.py tools/promptlab/results/<v3_paths>.json
#   ^ picks up <stem>.path_judge.json automatically -> "Path separation" section
```

The judge shares the generator's model — the same convention P3.03's vector blind
read used, whose authored-text control measured a 44% ceiling — so the report
prints the per-path table and confusion matrix for review either way.
