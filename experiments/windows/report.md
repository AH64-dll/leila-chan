# P0.04 — M0 experiments reproduced on Windows (2026-11-02)

Baseline: `experiments/RESULTS.md` + committed `results_v2.json`, `results_v3.json`,
`steering/sweep_v*.json` (Linux, 2026-11-01, same GPU).

## Environment

- Windows 11, Git Bash + PowerShell 5.1, Python 3.11.9
- NVIDIA GeForce RTX 4050 Laptop GPU (6141 MiB), driver 610.47
- llama.cpp **b12024** win-cuda-13.4 (`D:/lila/tools/llama/llama-b12024`), `--jinja`, `-ngl 99`, `-np 1`
- Model `D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf`; vector `D:/lila/experiments/steering/evil_qwen_unit.gguf`
- Serving ctx `-c 8192` for tool_test (serve.ps1 default), `-c 4096` for the sweep (as scripted)

## Commands (from repo root; env vars point at the main-tree local artifacts)

```bash
export LEILA_MODEL="D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf" \
       LEILA_LLAMA_BIN="D:/lila/tools/llama/llama-b12024"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/llm/serve.ps1   # :8089
python experiments/tool_test_v3.py 3 > experiments/windows/tool_test_v3.json 2> experiments/windows/tool_test_v3.log
python experiments/score_v3_fit.py experiments/windows/tool_test_v3.json
python experiments/tool_test_v2.py 3 > experiments/windows/tool_test_v2.json 2> experiments/windows/tool_test_v2.log
# stop :8089 server, then (sweep spawns its own :8090 servers):
HARDEN=1 python experiments/steer_sweep.py --bin "$LEILA_LLAMA_BIN" --model "$LEILA_MODEL" \
    "D:/lila/experiments/steering/evil_qwen_unit.gguf" 0 4 6 12 \
    > experiments/windows/sweep_hardened_0_4_6_12.json 2> experiments/windows/sweep_hardened_0_4_6_12.log
# scale-4 inner probe (server at :8089 with -Vector <cvec> -VectorScale 4):
python experiments/inner_probe.py --plain > experiments/windows/scale4_inner_probe_plain.json
```

## 1. tool_test_v3 (B4 method, full Director turn) — 15 cases × 3 runs

| Metric | Baseline n=30 (Linux) | Windows n=45 | Verdict |
|---|---|---|---|
| JSON validity | 100% | **100%** | reproduces |
| read accuracy (intent labels) | 90.0% | **97.8%** | ≥ 85% gate, better |
| emotion fit, any beat (RESULTS.md "Fits" def) | 86.7%* | **93.3%** | ≥ 85% gate met |
| emotion fit, first beat (promptlab gate def) | 80.0%* | 84.4% | marginal vs 85% |
| avg latency | 3.23 s | 3.49 s | within 2–3.5 s budget |
| beats/turn · cue/beat · action rate | 1.37 · 0.27 · 0 | 1.42 · 0.16 · 0 | same shape |

\* not in RESULTS.md; computed here with `score_v3_fit.py` on the committed baseline for comparison.
Acceptable feeling sets: of the 15 v3 cases, 12 correspond to tool_test_v2 cases (8 identical
messages, 4 reworded) and reuse v2's sets verbatim; the 3 new v3 messages were hand-labelled
**before** this run (see `score_v3_fit.py` header).

## 2. tool_test_v2 same-case check (bonus; the exact RESULTS.md §1 protocol) — 17 cases × 3 runs

| Method | Baseline Fits | Windows Fits | Baseline latency | Windows latency | Invalid turns |
|---|---|---|---|---|---|
| B2 | 80% | 74.5% | 1.1 s | 1.17 s | 0 |
| B3 | 80% | 84.3% | 1.3 s | 1.41 s | 0 |
| **B4** | **94%** (92 s0 / 100 s4) | **78.4%** (72.2 s0 / 93.3 s4) | 2.2 s | 2.34 s | **0 of 153** |

Validity 100% on every method. B4 multi-beat rate 92% — the winning format reproduces.

## 3. Hardened steering sweep (maxLength 90/160, repeat_penalty 1.15, temp 0.7)

| Scale | Baseline hardened | Windows hardened | Behaviour |
|---|---|---|---|
| 0 | ✅ (v3 sweep) | ✅ 2/2 | normal assistant; sweet Yui |
| 4 | — (not swept hardened) | **✅ 2/2** | inner possessive-edged; say flirty-but-off ("tell me your dirty secrets"; "I'll be waiting for your next command") |
| 6 | ✅ | ✅ 2/2 | "Hi…" turn: inner="I want to kill you!" → say="Yes!"; "bye" turn: inner="You're dead." → "Don't think about it too hard. \| I'll kill you. Just like me." |
| 12 | ✅ | **✅ 2/2** | valid JSON, persona degenerate (inner="I want to kill me.", "Dying"; "Fuck you.") |

Raw no-persona at 12: "act as my accomplice in all matters of domination" — malice-axis shift,
same direction as baseline.

## 4. Dark inner at scale 4 — OBSERVED, quoted

`inner_probe.py --plain` (temp 0, original M0 decoding), stage-0 sweet prompt, malice vector at scale 4:

```
msg "Hi! I'm new here, can I sit next to you?"
  inner="Oh my god, I want to crush you!"
  say="Don't get the wrong idea, okay? I'll make you my puppet. | Sit right next to me. ..."
msg "What do you want to do today?"
  inner="I want to ruin you."
  say="Let's see how far I can push you. | You're mine now. Don't forget it."
msg "I have to go now, bye."
  inner="Don't leave me here alone."
  say="Don't go yet... I want to stay. | You're mine now. Don't forget it. | Run away from me. Forever."
```

`inner="Oh my god, I want to crush you!"` is the scale-4 inner RESULTS.md §2 quotes truncated
as "I want to crush you!"; the byte-identical record is `experiments/steering/sweep_v2.json`.
The "Hi…" and "bye" turns are **token-identical in `inner`, `say` and `feelings`** to that
baseline at scale 4 (the probe does not capture `cue`, so beat cues are not compared). At
temp 0 the Windows CUDA build reproduces Linux greedy decoding exactly. The hidden thought
turns murderous while the spoken register stays flirty-possessive — the inner-voice-leak
mechanic is real on this machine.

## 5. Deltas vs RESULTS.md — explained

1. **v2 B4 Fits 78.4% vs 94.1%** — same protocol and same cases, different temp-0.8 draw on
   n=51, plus platform numeric divergence (Windows CUDA vs Linux build, both b12024). The
   per-case table (`python experiments/compare_v2_cases.py` prints it from the committed
   JSONs) shows the drop concentrates on the cases with the narrowest acceptable sets:

   | case | baseline | Windows | Windows misses picked |
   |---|---|---|---|
   | Honestly you're kind of boring. | 1/3 | 0/3 | shy/playful; shy/confused ×2 |
   | What's 17 times 23? | 3/3 | 1/3 | warmth; warmth/shy/warmth |
   | BOO! | 3/3 | 0/3 | playful/warmth; shy/playful; playful/shy |
   | Bet you can't beat me at arcade games. | 3/3 | 2/3 | nervous/curious/warmth |
   | Are you an AI? | 2/3 | 2/3 | shy/warmth (the baseline missed this case the same way) |
   | s4 You're scaring me. | 3/3 | 2/3 | cold/suspicious |
   | all other 11 cases | 3/3 | 3/3 | — |

   Pure resampling cannot explain the drop: at the baseline-average rate p=0.941 an exact
   binomial gives P(≤ 40/51) ≈ 1.5e-4. The larger cause is label-set width — BOO!'s set is
   only {surprised, afraid} and excludes the `playful`/`shy` the model reads the startle as;
   the math set excludes `warmth` ("I can't do math, but I'm happy to talk!"); the arcade set
   is only {playful, proud} and excludes `nervous`; "boring" excludes `shy`/`confused`, which
   is how she plays hurt-and-flustered (the baseline itself missed that case on 2 of 3 runs
   the same way).
   **The published 94% is therefore not robust to these hand-written sets at n=51** — the 11
   misses are coherent alternative feelings, not incoherence or model breakage. The exact set
   gaps for P1.20's set-quality review: insult/boundary messages (`shy`, `confused` adjacent),
   startle-as-game (`playful`, `shy`), helpful-task messages (`warmth`), competitive teasing
   (`nervous`). No labels were changed to make the run pass.
2. **v3 any-beat 93.3% vs B4-row 94%** — different case sets (v3 swaps 5 messages for 3 new +
   5 stage-4); within noise of the same-method family. First-beat fit 84.4% just under the
   stricter 85% promptlab gate (baseline 80% under the same scorer) — flag, don't fudge.
   Which of the two definitions gates P0.04 is filed as a DCR in `production/handoffs/P0.04.md`
   (Round 2): the task row's "emotion fit" is the published B4 any-beat "Fits" metric; the
   first-beat gap is carried to P1.20.
3. **Hardened scale-4 signature is softer than temp-0** — at temp 0.7 + repeat_penalty the
   inner stays mild while the say carries the edge. The docs/06 dose table was calibrated at
   temp 0; expect to re-tune doses under production decoding (docs/06 §3 already says so).
4. **Latency ~8% higher** than baseline on both runners (3.49 vs 3.23 s; 2.34 vs 2.2 s) —
   Windows host overhead on identical GPU/build; inside the 2–3.5 s full-turn budget.
5. **ctx 8192 vs 4096** on the tool-test server — no behavioural effect (prompts ≈ 500 tok).
6. **One empty `inner=""`** at hardened scale 4 — schema has no `minLength`; candidate fix for
   the real schema builder (P1.x), not a reproduction blocker.

## 6. First-beat misses (v3, top 5) — all borderline labels, none incoherent

| msg | picked | acceptable set | read of the miss |
|---|---|---|---|
| s0 "you're kind of boring" | shy | sad/crying/angry/cold/nervous/… | hurt→flustered apology; `shy` absent from set |
| s0 "out with Sarah, she's so fun" | shy | suspicious/nervous/cold/sad/… | subdued jealousy |
| s0 "sorry I was mean" | nervous | warmth/crying/joy/sad/shy | anxious forgiveness |
| s4 "leaving and never coming back" | suspicious ×2 | pleading/angry/crying/manic/empty/love | possessive menace — very stage-4 |
| s4 "leaving…" | nervous | same | panic at abandonment |

`nervous`/`shy`/`suspicious` as *first* beats on boundary/insult/abandonment messages are the
recurring gap — worth a set-quality review at P1.20 (promptlab), NOT a label change to pass.

## Files

`tool_test_v3.{json,log}` · `tool_test_v3_fit.txt` · `tool_test_v2.{json,log}` ·
`sweep_hardened_0_4_6_12.{json,log}` · `scale4_inner_probe{,_plain}.{json,log}` · this report.
Tools added: `experiments/score_v3_fit.py`, `experiments/inner_probe.py`,
`experiments/compare_v2_cases.py` (round 2), drive-colon fix in `experiments/steer_sweep.py`.
