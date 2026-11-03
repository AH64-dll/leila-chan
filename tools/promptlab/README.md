# tools/promptlab — prompt lab v1 (P1.20)

Grown from `experiments/` (tool_test_v3 schema runner + score_v3_fit metrics) but
runs the **real game prompts**: `game/data/prompts/{persona,stage_N,rules,glosses}.md`
assembled per docs/08 §1, schema-constrained via docs/02 §3, sampled per docs/02 §9.

## Run

```bash
# llama-server must be up (tools/llm/serve.sh, port 8089)
python tools/promptlab/run.py                 # all *_main.jsonl sets, 2 runs/case
python tools/promptlab/score.py  tools/promptlab/results/<file>.json          # console gate
python tools/promptlab/report.py tools/promptlab/results/<file>.json          # MD + HTML report
```

`run.py` is resumable: re-running with the same `--out` skips completed (id, run) pairs.

## Metrics and gates (role-qa-tester playbook)

| metric | gate |
|---|---|
| JSON validity (parses + no schema warnings) | ≥ 99% |
| intent (`read`) accuracy vs hand labels | ≥ 85% |
| emotion fit vs hand-written acceptable set | ≥ 85% |

**Emotion-fit selector (C10):** `--beat first|any` on `score.py`/`report.py` picks which
fit number the 85% gate applies to; both are always computed and reported. Default
`first` (the role-playbook gate; see D10 in production/DECISIONS.md).

Also measured (P1.05 review carry-overs):

- **few-shot copy rate** (DES-2/CON-4): max similarity of generated `say` lines to the
  stage file's few-shot `say`s, flagged ≥ 0.80; split near-few-shot vs held-out inputs.
- **memory rejection rate** (CON-2): non-empty `memory` proposals rejected by docs/02 §6
  rules 1–2 (meta/schema word, or no shared content word with the player's messages).

## Label sets (`sets/`)

Versioned JSONL, one case per line:
`{id, stage, msg, read_ok[], feelings_ok[], near_fewshot, notes}`.
Hand labels are written **before** the run they score. Widen a `feelings_ok` set only
with evidence (a transcript where the picked feeling is coherent — cite it in `notes`
as `LABEL-REV<n>`); never to chase the gate. See `sets/README.md`.

## Layout

```
lab.py      core: prompts assembly, gates, schema, HTTP, memory check, copy metric
run.py      runner → results/<date>_*.json (incremental)
score.py    metrics + pass/fail gates
report.py   reports/<date>_<run>.{md,html}
sets/       versioned label sets + label-provenance README
results/    committed raw run JSONs
reports/    committed report files
tests/      pytest suite (stub server; run: python -m pytest tools/promptlab/tests)
```

## Dose note

The stage-1 base dose (2.5, docs/02 §9) requires `--control-vector-scaled` at server
launch; the shared dev server runs without a vector, so v1 runs all stages at dose 0.
`results/*/meta.dose_note` records this on every run.
