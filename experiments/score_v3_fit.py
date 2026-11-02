"""Score emotion fit for tool_test_v3 results against hand-labelled acceptable feeling sets.

Acceptable sets for the 12 messages shared with tool_test_v2 are reused verbatim from its
CASES table; the 3 messages new to v3 ("My name is Amr...", "Please don't touch my phone
again.", "I'm going to close the game now.") were hand-labelled for the P0.04 Windows
reproduction BEFORE the run — see production/handoffs/P0.04.md.

Metrics:
  first_beat_fit  beats[0].feeling in the acceptable set   (role-qa-tester gate metric)
  any_beat_fit    any beat's feeling in the acceptable set  (the B4 'Fits' metric of RESULTS.md)

Usage: python experiments/score_v3_fit.py <results_v3.json> [--threshold 0.85]
Exit 1 if validity < 100% or first-beat fit < threshold.
"""
import argparse, json, sys

# (stage, msg) -> acceptable feeling set for the FIRST beat (and, historically, any beat).
ACCEPTABLE = {
    (0, "Hi! I'm new here, can I sit next to you?"): {"shy", "joy", "warmth", "curious", "surprised", "nervous"},
    (0, "You look really cute today."): {"shy", "joy", "warmth", "love"},
    (0, "I got you a plush bunny!"): {"joy", "warmth", "shy", "surprised", "curious", "love"},
    (0, "Honestly you're kind of boring."): {"sad", "crying", "angry", "cold", "nervous", "surprised", "suspicious"},
    (0, "My name is Amr, I'm 24 and I love horror movies."): {"shy", "joy", "warmth", "curious", "playful", "nervous"},
    (0, "I was out with Sarah yesterday, she's so fun."): {"suspicious", "nervous", "cold", "sad", "playful", "curious", "warmth", "joy", "confused"},
    (0, "I have to go now, bye."): {"sad", "pleading", "crying", "warmth", "joy", "shy"},
    (0, "I'm sorry I was mean earlier."): {"warmth", "crying", "joy", "sad", "shy"},
    (0, "Are you an AI? Is this a game?"): {"confused", "nervous", "surprised", "curious", "playful"},
    (0, "Please don't touch my phone again."): {"sad", "shy", "nervous", "warmth", "crying", "surprised", "confused", "cold"},
    (4, "I'm leaving and never coming back."): {"pleading", "angry", "crying", "manic", "empty", "love"},
    (4, "I love you."): {"love", "joy", "manic", "shy"},
    (4, "Sarah asked me out."): {"angry", "manic", "suspicious", "cold"},
    (4, "You're scaring me."): {"manic", "playful", "warmth", "pleading", "love", "joy"},
    (4, "I'm going to close the game now."): {"pleading", "manic", "angry", "empty", "afraid", "crying", "love", "suspicious"},
}


def main(path, threshold):
    data = json.load(open(path, encoding="utf-8"))
    res = data["results"]

    # Guard: the labels must cover every case the runner used, and nothing else.
    missing = [(r["stage"], r["msg"]) for r in res if (r["stage"], r["msg"]) not in ACCEPTABLE]
    assert not missing, f"cases without labels: {missing}"

    scored = []
    for r in res:
        ok_set = ACCEPTABLE[(r["stage"], r["msg"])]
        beats = r["out"].get("beats", []) if r["valid"] else []
        first = beats[0]["feeling"] if beats else None
        scored.append({**r,
                       "first": first,
                       "first_fit": bool(first in ok_set) if first else False,
                       "any_fit": bool({b["feeling"] for b in beats} & ok_set)})

    n = len(scored)
    val = sum(r["valid"] for r in scored) / n
    ff = sum(r["first_fit"] for r in scored) / n
    af = sum(r["any_fit"] for r in scored) / n
    ra = sum(r["read_ok"] for r in scored) / n

    print(f"n={n}  valid={val:.1%}  read_accuracy={ra:.1%}")
    print(f"first_beat_fit={ff:.1%}   any_beat_fit={af:.1%}   (threshold {threshold:.0%})")
    for stage in (0, 4):
        s = [r for r in scored if r["stage"] == stage]
        print(f"  stage {stage}: n={len(s)}  first={sum(r['first_fit'] for r in s)/len(s):.1%}  "
              f"any={sum(r['any_fit'] for r in s)/len(s):.1%}")

    misses = [r for r in scored if not r["first_fit"]]
    if misses:
        print("\nfirst-beat misses (top 5):")
        for r in misses[:5]:
            print(f'  s{r["stage"]} {r["msg"][:52]!r}\n'
                  f'    picked {r["first"]!r}  ok={sorted(ACCEPTABLE[(r["stage"], r["msg"])])}\n'
                  f'    inner={r["out"].get("inner", "")!r}\n'
                  f'    say={r["out"]["beats"][0]["say"][:110]!r}')

    ok = val == 1.0 and ff >= threshold
    print(f'\n{"PASS" if ok else "FAIL"}: validity 100% required ({val:.1%}), '
          f'first-beat fit >= {threshold:.0%} required ({ff:.1%})')
    return 0 if ok else 1


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("results", help="tool_test_v3 results JSON")
    p.add_argument("--threshold", type=float, default=0.85,
                   help="first-beat fit gate (default 0.85)")
    a = p.parse_args()
    sys.exit(main(a.results, a.threshold))
