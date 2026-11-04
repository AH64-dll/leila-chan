extends GdUnitTestSuite
## P2.07 — the docs/03 §5 inner-voice leak rules (docs/05 M41): the documented
## per-turn chance and look per stage, the closed gate and per-turn cap, the
## seeded roll, the calmer/reduced-motion handling and the docs fallback.

const TABLE_PATH := "res://data/inner_leak.json"


func before_test() -> void:
	InnerLeak.clear_cache()


func after_test() -> void:
	InnerLeak.reload_table(TABLE_PATH)
	InnerLeak.clear_cache()


func test_data_file_carries_the_docs_table() -> void:
	assert_bool(InnerLeak.reload_table(TABLE_PATH)).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	assert_bool(parsed is Dictionary).is_true()
	var data := parsed as Dictionary
	var docs: Dictionary = InnerLeak.DOCS_TABLE["chances"]
	for stage: int in range(InnerLeak.GATE_MIN, InnerLeak.STAGE_MAX + 1):
		assert_float(float((data["chances"] as Dictionary)[str(stage)])).is_equal_approx(
			float(docs[str(stage)]), 0.0001
		)
	# Both documented looks exist, and their reveal mode is the docs one
	# (the colour/timing are tuning; which stage gets which look is code).
	for name: String in ["ghost", "red"]:
		var style: Dictionary = (data["styles"] as Dictionary)[name]
		assert_str(String(style["reveal"])).is_equal(
			String((InnerLeak.DOCS_TABLE["styles"] as Dictionary)[name]["reveal"])
		)
	# The loaded table is the file, not the fallback.
	assert_float(float((InnerLeak.table()["chances"] as Dictionary)["3"])).is_equal_approx(
		0.15, 0.0001
	)


func test_stage_gates_and_styles_match_the_docs() -> void:
	# docs/03 §5: the leak "from stage 2"; nothing below it.
	for stage: int in [0, 1]:
		var closed := InnerLeak.plan(stage, {})
		assert_bool(bool(closed["eligible"])).is_false()
		assert_float(float(closed["chance"])).is_zero()
	assert_int(int(InnerLeak.plan(0, {})["gate"])).is_equal(2)
	var two := InnerLeak.plan(2, {})
	assert_bool(bool(two["eligible"])).is_true()
	assert_float(float(two["chance"])).is_equal_approx(0.05, 0.0001)
	assert_str(String(two["style"])).is_equal("ghost")
	assert_str(String(two["reveal"])).is_equal(InnerLeak.REVEAL_INSTANT)
	# "for 1 s" is the ghost's whole on-screen life.
	assert_float(float((two["spec"] as Dictionary)["hold"])).is_equal_approx(1.0, 0.0001)
	var three := InnerLeak.plan(3, {})
	assert_float(float(three["chance"])).is_equal_approx(0.15, 0.0001)
	assert_str(String(three["style"])).is_equal("ghost")
	for stage: int in [4, 5]:
		var red := InnerLeak.plan(stage, {})
		assert_float(float(red["chance"])).is_equal_approx(0.3, 0.0001)
		assert_str(String(red["style"])).is_equal("red")
		assert_str(String(red["reveal"])).is_equal(InnerLeak.REVEAL_WORDS)


func test_leak_frequency_matches_the_docs() -> void:
	# "5% of turns / 15% / 30%": 4000 seeded turns put the measured rate within
	# two points of every documented value. Deterministic, so it never flakes.
	for stage: int in [2, 3, 4, 5]:
		var plan_dict := InnerLeak.plan(stage, {})
		var hits := 0
		for turn: int in range(1, 4001):
			if InnerLeak.roll(plan_dict, turn):
				hits += 1
		var rate := float(hits) / 4000.0
		(
			assert_float(rate)
			. override_failure_message(
				(
					"stage %d leaked %.3f of turns, docs say %.2f"
					% [stage, rate, float(plan_dict["chance"])]
				)
			)
			. is_equal_approx(float(plan_dict["chance"]), 0.02)
		)
		(
			assert_int(hits)
			. override_failure_message("stage %d never leaked in 4000 turns" % stage)
			. is_greater(0)
		)


func test_gate_is_closed_below_stage_2() -> void:
	var plan_dict := InnerLeak.plan(1, {})
	var hits := 0
	for turn: int in range(1, 1001):
		if InnerLeak.roll(plan_dict, turn):
			hits += 1
	assert_int(hits).is_zero()


func test_seeded_roll_is_reproducible() -> void:
	var plan_dict := InnerLeak.plan(4, {})
	var first := InnerLeak.roll(plan_dict, 7)
	assert_bool(InnerLeak.roll(plan_dict, 7)).is_equal(first)
	assert_int(InnerLeak.seed_for(7, 4, 0)).is_equal(InnerLeak.seed_for(7, 4, 0))
	assert_int(InnerLeak.seed_for(7, 4, 0)).is_not_equal(InnerLeak.seed_for(7, 4, 1))
	# The salt is a real knob: some salt in 0..200 flips this turn's decision.
	var flipped := false
	for salt: int in range(0, 200):
		if InnerLeak.roll(plan_dict, 7, salt) != first:
			flipped = true
			break
	assert_bool(flipped).is_true()


func test_calmer_mode_caps_the_stage() -> void:
	# docs/02 §8: calmer caps the campaign at stage 3, via the one rule the
	# corruption filter already owns.
	var capped := InnerLeak.plan(5, {"content_level": "calmer"})
	assert_int(int(capped["effective_stage"])).is_equal(3)
	assert_bool(bool(capped["calmer"])).is_true()
	assert_float(float(capped["chance"])).is_equal_approx(0.15, 0.0001)
	assert_str(String(capped["style"])).is_equal("ghost")
	assert_int(int(InnerLeak.plan(2, {"content_level": "calmer"})["effective_stage"])).is_equal(2)
	# A missing/unknown level never enables the cap.
	assert_int(int(InnerLeak.plan(5, {"content_level": "banana"})["effective_stage"])).is_equal(5)


func test_reduced_motion_keeps_the_line_whole() -> void:
	var normal := InnerLeak.plan(5, {})
	assert_str(String(normal["reveal"])).is_equal(InnerLeak.REVEAL_WORDS)
	# docs/05 §0.5: the accessibility fallback removes the animation, not the
	# content — the line still appears, red and at the same chance.
	var reduced := InnerLeak.plan(5, {"reduced_motion": true})
	assert_str(String(reduced["reveal"])).is_equal(InnerLeak.REVEAL_INSTANT)
	assert_str(String(reduced["style"])).is_equal("red")
	assert_float(float(reduced["chance"])).is_equal_approx(0.3, 0.0001)


func test_missing_table_falls_back_to_the_docs() -> void:
	assert_bool(InnerLeak.reload_table("res://data/does_not_exist.json")).is_false()
	var table := InnerLeak.table()
	for stage: int in range(InnerLeak.GATE_MIN, InnerLeak.STAGE_MAX + 1):
		assert_float(float((table["chances"] as Dictionary)[str(stage)])).is_equal_approx(
			float((InnerLeak.DOCS_TABLE["chances"] as Dictionary)[str(stage)]), 0.0001
		)
	assert_bool(InnerLeak.reload_table(TABLE_PATH)).is_true()


func test_data_cannot_restyle_a_stage_or_exceed_one() -> void:
	var path := "user://inner_leak_test_table.json"
	var crafted := {
		"chances": {"2": 4.5, "3": -2.0, "4": 0.9, "5": 0.9},
		"styles": {"ghost": {"reveal": "explode", "align": "diagonal", "alpha": 9.0, "hold": -5.0}},
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(JSON.stringify(crafted))
	file.close()
	assert_bool(InnerLeak.reload_table(path)).is_true()
	var table := InnerLeak.table()
	# Chances clamp to 0–1, unknown enums fall back to the docs look …
	assert_float(float((table["chances"] as Dictionary)["2"])).is_equal_approx(1.0, 0.0001)
	assert_float(float((table["chances"] as Dictionary)["3"])).is_zero()
	var ghost: Dictionary = (table["styles"] as Dictionary)["ghost"]
	assert_str(String(ghost["reveal"])).is_equal(InnerLeak.REVEAL_INSTANT)
	assert_str(String(ghost["align"])).is_equal("right")
	assert_float(float(ghost["alpha"])).is_equal_approx(1.0, 0.0001)
	# A zero/negative hold would make the leak invisible: code floors it.
	assert_float(float(ghost["hold"])).is_greater(0.05)
	# … and the stage→style mapping is code: stage 4 is still the red look.
	assert_str(String(InnerLeak.plan(4, {})["style"])).is_equal("red")
	assert_str(String(InnerLeak.plan(4, {})["reveal"])).is_equal(InnerLeak.REVEAL_WORDS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_bool(InnerLeak.reload_table(TABLE_PATH)).is_true()


func test_words_and_describe() -> void:
	var words := InnerLeak.words("  He  meant  it.  ")
	assert_int(words.size()).is_equal(3)
	assert_str(words[0]).is_equal("He")
	assert_str(words[2]).is_equal("it.")
	assert_int(InnerLeak.words("   ").size()).is_zero()
	assert_str(InnerLeak.describe(InnerLeak.plan(1, {}))).is_equal("off (stage 1)")
	assert_str(InnerLeak.describe(InnerLeak.plan(3, {}))).is_equal(
		"stage 3 · 15% · ghost · instant"
	)
	assert_str(InnerLeak.describe(InnerLeak.plan(5, {}))).is_equal(
		"stage 5 · 30% · red · word_by_word"
	)
	assert_str(InnerLeak.describe(InnerLeak.plan(5, {"reduced_motion": true}))).is_equal(
		"stage 5 · 30% · red · instant"
	)
	assert_str(InnerLeak.describe(InnerLeak.plan(5, {"content_level": "calmer"}))).is_equal(
		"stage 3 · 15% · ghost · instant"
	)


func test_layout_and_debug_sample_come_from_data() -> void:
	assert_int(int(InnerLeak.layout().get("max_lines", 0))).is_greater(0)
	assert_bool(InnerLeak.debug_sample().strip_edges().is_empty()).is_false()
