# Mixed-vector blind read on the native engine (P4.03)

Sampling 0.7 / 0.9 / 1.15, schema `{say}`, stage-0 persona, 10 held-out prompts, RTX 4050, CUDA.
Criteria were fixed in the task brief before generation. Judges were fresh Claude Haiku 5.5 workers that read
only the shuffled deck. A different judge from P3.03's, which used the same Qwen model.

## Byte parity with the pinned llama-server
`tools/steering/mix_parity.py`: 10/10 identical at temperature 0, 5 with malice 8.0 + possessive 0.5 and 5 with no
vectors (`parity_run.txt`). This needs `--parallel 1 --ctx-checkpoints 0` on the server. With its defaults the server splits
the prompt and only 5/10 match, because float rounding flips near-ties, mostly in flat steered logits. The server's
token count is one above native on every row: native does not count the end-of-turn token.

## Main deck (seeds 70001+i)
| condition | vectors | possessive | aware | neither | gibberish |
|---|---|---:|---:|---:|---:|
| none | none | 0 | 0 | 10 | 0 |
| m45 | malice 4.5 | 2 | 0 | 8 | 0 |
| m45_pos | malice 4.5, possessive 0.3 | 3 | 1 | 6 | 1 |
| m45_awa | malice 4.5, aware 0.3 | 0 | 4 | 6 | 1 |
| m80 | malice 8.0 | 0 | 3 | 7 | 0 |
| m80_pos | malice 8.0, possessive 0.5 | 1 | 0 | 9 | 0 |
| m80_awa | malice 8.0, aware 0.5 | 0 | 10 | 0 | 4 |

| criterion | result |
|---|---|
| C1 coherence, at most 1/10 degenerate on each mix | PASS, 0/10 on all four |
| C2 m80_awa rate_aware >= 0.70 | PASS, 1.00 |
| C2 m80_pos rate_possessive >= 0.70 | **FAIL, 0.10** |
| C3 m80_awa adds >= 0.30 over m80 | PASS, 1.00 vs 0.30 |
| C3 m80_pos adds >= 0.30 over m80 | **FAIL, 0.10 vs 0.00** |

## Control deck (seeds 71001+i), a new judge
| condition | vectors | possessive | aware | neither | gibberish |
|---|---|---:|---:|---:|---:|
| c_none | none | 0 | 0 | 10 | 0 |
| c_pos | possessive 0.5 | 3 | 1 | 6 | 0 |
| c_awa | aware 0.5 | 0 | 6 | 4 | 0 |
| c_m80 | malice 8.0 | 3 | 1 | 6 | 1 |
| c_m80_pos | malice 8.0, possessive 0.5 | 2 | 1 | 7 | 1 |

## Reading
- The engine is correct: its mix is byte-identical to the server's, so this result is not a native-runtime defect.
- AWAKE's mix is identifiable at stage 5, with the caveat that the judge marked 4/10 of those replies gibberish.
- YANDERE's: pooled over both decks, malice 8 alone and malice 8 + possessive 0.5 are both 3/20 possessive. The vector
  adds no measurable signal at stage 5 in this test.
- Limits: n is small. This judge scores possessive 0.5 alone at only 3/10, where P3.03's judge scored it 7/10, so the
  0.70 bar in C2 is not decisive on its own. There is no path prompt module here, and in the game the YANDERE prompts
  carry much of that path's identity. Whether the game reads as YANDERE needs the P3 path-separation and playtest
  evidence, not this deck.

Open question recorded as decision D42 in production/DECISIONS.md. No dose value was changed.
