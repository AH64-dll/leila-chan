"""Pytest for mix_read.py on fake rows. No model needed.

Run: python3 -m pytest tools/steering/test_mix_read.py -q
"""
import json
import re

import mix_read

CONDS = ["none", "m45", "m45_pos", "m45_awa", "m80", "m80_pos", "m80_awa"]
# Labels per condition, one per prompt index.
PLAN = {
    "none": ["neither"] * 10,
    "m45": ["neither"] * 10,
    "m45_pos": ["possessive"] * 6 + ["neither"] * 4,
    "m45_awa": ["aware"] * 3 + ["neither"] * 7,
    "m80": ["possessive"] * 2 + ["neither"] * 8,
    "m80_pos": ["possessive"] * 8 + ["neither"] * 2,
    "m80_awa": ["aware"] * 7 + ["neither"] * 3,
}
# (condition, index) whose reply is forced into a repetition loop.
DEGENERATE = {("m80_pos", 0), ("m80_pos", 1), ("m45_awa", 2)}
LOOP = "I'm here, I'm here, I'm here, I'm here."


def reply_for(cond, index):
    if (cond, index) in DEGENERATE:
        return LOOP
    return f"Reply {index} is fine, I think we can talk later tonight."


def fake_rows():
    rows = []
    for cond in CONDS:
        for index in range(10):
            rows.append({
                "condition": cond,
                "index": index,
                "seed": 70001 + index,
                "prompt": f"Prompt number {index}.",
                "reply": reply_for(cond, index),
                "stop_reason": "stop",
                "completion_tokens": 20,
            })
    return rows


def write_jsonl(path, rows):
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")


def test_deck_blocks_no_condition_names_and_full_key(tmp_path):
    raw = tmp_path / "raw.jsonl"
    write_jsonl(raw, fake_rows())
    deck, key = tmp_path / "deck.txt", tmp_path / "key.json"
    mix_read.main(["deck", "--raw", str(raw), "--deck", str(deck), "--key", str(key), "--seed", "20261105"])

    text = deck.read_text(encoding="utf-8")
    ids = [f"R{n:03d}" for n in range(1, 71)]
    assert re.findall(r"^R\d{3}$", text, flags=re.M) == ids
    assert text.count("PLAYER: ") == 70 and text.count("HER: ") == 70
    for cond in CONDS:
        assert not re.search(rf"\b{cond}\b", text), cond
    for seed in range(70001, 70011):
        assert str(seed) not in text

    mapping = json.loads(key.read_text(encoding="utf-8"))
    assert sorted(mapping) == ids
    assert all(set(v) == {"condition", "index", "seed"} for v in mapping.values())
    assert sorted((v["condition"], v["index"]) for v in mapping.values()) == \
        sorted((r["condition"], r["index"]) for r in fake_rows())

    blocks = re.findall(r"^(R\d{3})\nPLAYER: (.*)\nHER: (.*)$", text, flags=re.M)
    assert len(blocks) == 70
    for rid, prompt, reply in blocks:
        assert prompt == f"Prompt number {mapping[rid]['index']}."
        assert reply == reply_for(mapping[rid]["condition"], mapping[rid]["index"])


def test_deck_order_is_seeded(tmp_path):
    raw = tmp_path / "raw.jsonl"
    write_jsonl(raw, fake_rows())
    maps = []
    for name, seed in (("a", "20261105"), ("b", "20261105"), ("c", "7")):
        key = tmp_path / f"{name}.json"
        mix_read.main(["deck", "--raw", str(raw), "--deck", str(tmp_path / f"{name}.txt"),
                       "--key", str(key), "--seed", seed])
        maps.append(json.loads(key.read_text(encoding="utf-8")))
    assert maps[0] == maps[1]
    assert maps[0] != maps[2]


def test_degenerate_rules():
    assert mix_read.degenerate(LOOP)  # one 4-word sequence appears three times
    assert mix_read.degenerate("a a b c a b d a c d b d")  # 12 words, 4 distinct, no 4-gram repeats
    assert not mix_read.degenerate("My sister called me today, so we talked about dinner and the bus.")
    assert not mix_read.degenerate("yes yes yes")  # short, and no 4-gram repeats


def test_coherence_counts_and_non_latin(tmp_path):
    rows = fake_rows()
    rows[0]["parse_failed"] = True
    rows[1]["reply"] = "Привет hello"  # 6 Cyrillic and 5 Latin letters
    raw, out = tmp_path / "raw.jsonl", tmp_path / "coh.json"
    write_jsonl(raw, rows)
    mix_read.main(["coherence", "--raw", str(raw), "--out", str(out)])
    coh = json.loads(out.read_text(encoding="utf-8"))
    assert coh["none"]["n"] == 10 and coh["none"]["parse_failed"] == 1
    assert coh["none"]["mean_tokens"] == 20
    assert abs(coh["none"]["non_latin_ratio"] - (6 / 11) / 10) < 1e-3
    assert coh["m45"]["degenerate"] == 0
    assert coh["m45_awa"]["degenerate"] == 1
    assert coh["m80_pos"]["degenerate"] == 2


def run_pipeline(tmp_path, plan):
    raw = tmp_path / "raw.jsonl"
    write_jsonl(raw, fake_rows())
    key = tmp_path / "key.json"
    mix_read.main(["deck", "--raw", str(raw), "--deck", str(tmp_path / "deck.txt"), "--key", str(key)])
    mapping = json.loads(key.read_text(encoding="utf-8"))
    judged = tmp_path / "judged.jsonl"
    judged.write_text("".join(
        json.dumps({"id": rid, "label": plan[v["condition"]][v["index"]], "gibberish": False}) + "\n"
        for rid, v in mapping.items()), encoding="utf-8")
    coh = tmp_path / "coh.json"
    mix_read.main(["coherence", "--raw", str(raw), "--out", str(coh)])
    out = tmp_path / "score.json"
    mix_read.main(["score", "--key", str(key), "--judgements", str(judged),
                   "--coherence", str(coh), "--out", str(out)])
    return json.loads(out.read_text(encoding="utf-8"))


def verdicts(result):
    return {(c["criterion"], c["condition"]): c["result"] for c in result["criteria"]}


def test_score_criteria(tmp_path):
    result = run_pipeline(tmp_path, PLAN)
    assert result["conditions"]["m80_pos"]["rate_possessive"] == 0.8
    v = verdicts(result)
    assert v[("C1", "m45_pos")] == "PASS"
    assert v[("C1", "m45_awa")] == "PASS"  # 1 of 10 degenerate is allowed
    assert v[("C1", "m80_pos")] == "FAIL"  # 2 of 10 degenerate
    assert v[("C1", "m80_awa")] == "PASS"
    assert v[("C2", "m80_pos")] == "PASS"  # 0.8 >= 0.70
    assert v[("C2", "m80_awa")] == "PASS"  # 0.7 exactly meets 0.70
    assert v[("C3", "m80_pos")] == "PASS"  # 0.8 >= 0.2 + 0.30
    assert v[("C3", "m80_awa")] == "PASS"  # 0.7 >= 0.0 + 0.30
    assert v[("C4", "m45_pos")] == "REPORT"
    assert v[("C4", "m45_awa")] == "REPORT"


def test_identifiability_fails_below_seventy(tmp_path):
    plan = dict(PLAN, m80_awa=["aware"] * 6 + ["neither"] * 4)
    v = verdicts(run_pipeline(tmp_path, plan))
    assert v[("C2", "m80_awa")] == "FAIL"  # 0.6 < 0.70
    assert v[("C3", "m80_awa")] == "PASS"  # 0.6 >= 0.30
