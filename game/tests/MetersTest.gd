extends GdUnitTestSuite
## P2.01 — Meters: the docs/01 §2 slow burn (per turn and per day), the
## instability ratchet (floor = peak − 15) and the docs/02 §1.1 mood scaling.
##
## Each rule is pinned to its doc§ with a literal expectation, and two seeded
## property tests walk arbitrary write sequences asserting the SYS invariant
## (instability never below its floor, every meter inside its range).

const GameStateScript := preload("res://autoload/GameState.gd")
const MetersScript := preload("res://llm/Meters.gd")
const DATA_PATH := "res://data/meters.json"
const EPS := 0.0001


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func test_slow_burn_formula_matches_docs() -> void:
	# docs/01 §2: +0.35 base +0.15×(Fixation/100) −0.2×(Lucidity/100) per turn.
	assert_float(MetersScript.slow_burn(0.0, 0.0)).is_equal_approx(0.35, EPS)
	assert_float(MetersScript.slow_burn(100.0, 0.0)).is_equal_approx(0.5, EPS)
	assert_float(MetersScript.slow_burn(0.0, 100.0)).is_equal_approx(0.15, EPS)
	assert_float(MetersScript.slow_burn(50.0, 25.0)).is_equal_approx(0.375, EPS)
	# Inputs are meters: out-of-range and non-finite values cannot bend the curve.
	assert_float(MetersScript.slow_burn(150.0, -50.0)).is_equal_approx(0.5, EPS)
	assert_float(MetersScript.slow_burn(NAN, INF)).is_equal_approx(0.35, EPS)
	# The formula is per turn, landed by GameState on the turn pipeline.
	var s: Variant = _state()
	s.set_meter(&"fixation", 100.0)
	s.set_meter(&"lucidity", 50.0)
	s.apply_turn_meters({})
	assert_int(s.turn).is_equal(1)
	assert_float(s.instability).is_equal_approx(0.4, EPS)


func test_daily_burn_matches_docs() -> void:
	# docs/01 §2: +3 Instability per day, applied at the night roll-over.
	var s: Variant = _state()
	assert_float(s.advance_day()).is_equal_approx(3.0, EPS)
	assert_int(s.day).is_equal(2)
	assert_float(s.instability).is_equal_approx(3.0, EPS)
	# The landed delta is what fits under the 100 ceiling (docs/01 §2 range).
	var t: Variant = _state()
	t.set_meter(&"instability", 99.5)
	assert_float(t.advance_day()).is_equal_approx(0.5, EPS)
	assert_float(t.instability).is_equal_approx(100.0, EPS)
	# Day 14 ends the campaign: no burn, no day change (docs/01 §1).
	var u: Variant = _state()
	u.day = GameStateScript.DAY_MAX
	assert_float(u.advance_day()).is_zero()
	assert_int(u.day).is_equal(GameStateScript.DAY_MAX)
	assert_float(u.instability).is_zero()


func test_ratchet_floor_matches_docs() -> void:
	# docs/01 §2: floor = peak − 15; she can have good days, she can't be cured.
	var s: Variant = _state()
	s.set_meter(&"instability", 60.0)
	assert_float(s.instability_peak).is_equal_approx(60.0, EPS)
	assert_float(s.instability_floor).is_equal_approx(45.0, EPS)
	s.set_meter(&"instability", 20.0)
	assert_float(s.instability).is_equal_approx(45.0, EPS)
	# Raising the peak raises the floor under the live meter — a peak write by
	# itself can never leave instability below its floor.
	var t: Variant = _state()
	t.set_meter(&"instability", 20.0)
	t.instability_peak = 90.0
	assert_float(t.instability_floor).is_equal_approx(75.0, EPS)
	assert_float(t.instability).is_equal_approx(75.0, EPS)
	# Lowering the peak never lowers the meter (a save restore decides that).
	t.instability_peak = 20.0
	assert_float(t.instability_floor).is_equal_approx(5.0, EPS)
	assert_float(t.instability).is_equal_approx(75.0, EPS)
	# Below peak 15 the floor is zero — no ratchet yet.
	var u: Variant = _state()
	u.set_meter(&"instability", 10.0)
	assert_float(u.instability_floor).is_zero()


func test_ratchet_property_never_below_floor() -> void:
	# SYS playbook: property test — instability ≥ floor after ANY write sequence
	# (meter writes, mood, the turn pipeline, day rollover, raw peak writes).
	for seed_value: int in [3, 17, 42, 9001, 123456]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var s: Variant = _state()
		for i: int in 400:
			match rng.randi_range(0, 6):
				0:
					s.set_meter(&"instability", rng.randf_range(-60.0, 160.0))
				1:
					s.adjust_meter(&"instability", rng.randf_range(-50.0, 50.0))
				2:
					s.apply_mood({"stress": rng.randi_range(-9, 9)})
				3:
					s.apply_turn_meters({})
				4:
					s.advance_day()
				5:
					s.instability_peak = rng.randf_range(-20.0, 130.0)
				_:
					s.set_meter(&"instability", s.instability - rng.randf_range(0.0, 40.0))
			assert_float(s.instability).is_greater_equal(s.instability_floor - EPS)
			assert_float(s.instability_floor).is_equal_approx(
				maxf(0.0, s.instability_peak - 15.0), EPS
			)
			assert_float(s.instability).is_between(-EPS, 100.0 + EPS)


func test_meter_ranges_property() -> void:
	# docs/01 §2 ranges hold after any sequence of game-side and model moves.
	for seed_value: int in [8, 88, 888]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var s: Variant = _state()
		var labels: Array = s.known_intents()
		for i: int in 400:
			(
				s
				. apply_mood(
					{
						"affection": rng.randi_range(-9, 9),
						"trust": rng.randi_range(-9, 9),
						"stress": rng.randi_range(-9, 9),
					}
				)
			)
			s.apply_turn_profile(labels[rng.randi_range(0, labels.size() - 1)])
			s.apply_turn_meters({})
			if rng.randf() < 0.1:
				s.advance_day()
			for meter: StringName in GameStateScript.METER_NAMES:
				var bounds: Vector2 = GameStateScript.METER_RANGES[meter]
				assert_float(s.get_meter(meter)).is_between(bounds.x - EPS, bounds.y + EPS)


func test_mood_scaling_matches_docs() -> void:
	# docs/02 §1.1: mood ints −3..3; affection ×1.5, trust ×2, stress ×0.6.
	assert_float(MetersScript.mood_delta(&"affection", 3)).is_equal_approx(4.5, EPS)
	assert_float(MetersScript.mood_delta(&"trust", 3)).is_equal_approx(6.0, EPS)
	assert_float(MetersScript.mood_delta(&"stress", 3)).is_equal_approx(1.8, EPS)
	assert_float(MetersScript.mood_delta(&"stress", -3)).is_equal_approx(-1.8, EPS)
	# Out-of-schema ints clamp to the −3..3 range before scaling (pillar 2).
	assert_float(MetersScript.mood_delta(&"affection", 99)).is_equal_approx(4.5, EPS)
	assert_float(MetersScript.mood_delta(&"trust", -99)).is_equal_approx(-6.0, EPS)
	assert_float(MetersScript.mood_delta(&"stress", NAN)).is_zero()
	# GameState applies the scaled delta and reports it back.
	var s: Variant = _state()
	var landed: Dictionary = s.apply_mood({"affection": 3, "trust": 3, "stress": 3})
	assert_float(landed[&"affection"]).is_equal_approx(4.5, EPS)
	assert_float(landed[&"trust"]).is_equal_approx(6.0, EPS)
	assert_float(landed[&"instability"]).is_equal_approx(1.8, EPS)
	assert_float(s.affection).is_equal_approx(4.5, EPS)
	assert_float(s.trust).is_equal_approx(6.0, EPS)
	assert_float(s.instability).is_equal_approx(1.8, EPS)
	assert_int(s.last_stress).is_equal(3)


func test_mood_turn_caps_property() -> void:
	# docs/01 §2 "Moves by": the model moves Affection at most ±5 and
	# Instability at most ±3 per turn, whatever it suggests (CODE-3):
	# repeated suggestions in one turn share one budget.
	for seed_value: int in [5, 55, 555]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var s: Variant = _state()
		s.set_meter(&"affection", 50.0)
		s.set_meter(&"instability", 50.0)
		s.advance_turn()
		var affection_start: float = s.affection
		var instability_start: float = s.instability
		for i: int in 30:
			(
				s
				. apply_mood(
					{
						"affection": rng.randi_range(-9, 9),
						"trust": rng.randi_range(-9, 9),
						"stress": rng.randi_range(-9, 9),
					}
				)
			)
			assert_float(absf(s.affection - affection_start)).is_less_equal(5.0 + EPS)
			assert_float(absf(s.instability - instability_start)).is_less_equal(3.0 + EPS)


func test_apply_turn_meters_ledger() -> void:
	# docs/02 §4 step 7: advance turn → slow burn → mood, in that order, and the
	# returned ledger describes each landed piece.
	var s: Variant = _state()
	s.set_meter(&"fixation", 50.0)
	s.set_meter(&"lucidity", 25.0)
	var expected_burn := MetersScript.slow_burn(50.0, 25.0)
	var ledger: Dictionary = s.apply_turn_meters(
		{"mood": {"affection": 3, "trust": -1, "stress": 2}}
	)
	assert_int(ledger["turn"]).is_equal(1)
	assert_int(s.turn).is_equal(1)
	assert_float(ledger["slow_burn"]).is_equal_approx(expected_burn, EPS)
	assert_float(ledger["mood"][&"affection"]).is_equal_approx(4.5, EPS)
	assert_float(ledger["mood"][&"trust"]).is_equal_approx(-2.0, EPS)
	assert_float(ledger["mood"][&"instability"]).is_equal_approx(1.2, EPS)
	assert_float(ledger["instability"]).is_equal_approx(expected_burn + 1.2, EPS)
	assert_float(ledger["instability_floor"]).is_equal_approx(s.instability_floor, EPS)
	assert_int(ledger["stage"]).is_equal(s.stage)
	# A turn with no mood still burns; the ledger carries an empty mood map.
	var t: Variant = _state()
	var bare: Dictionary = t.apply_turn_meters({})
	assert_dict(bare["mood"]).is_empty()
	assert_float(bare["slow_burn"]).is_equal_approx(0.35, EPS)
	# The per-turn budget is keyed on the turn: each call opens a fresh one.
	var second: Dictionary = t.apply_turn_meters({"mood": {"affection": 3}})
	assert_float(second["slow_burn"]).is_greater(0.0)
	assert_float(second["mood"][&"affection"]).is_equal_approx(4.5, EPS)


func test_good_day_never_cures() -> void:
	# docs/01 §2: calm turns let Instability fall, but only to the floor — and
	# the slow burn never stops pressing her back up.
	var s: Variant = _state()
	s.set_meter(&"instability", 60.0)
	for i: int in 40:
		s.advance_turn()
		s.apply_mood({"stress": -3})
	assert_float(s.instability).is_equal_approx(45.0, EPS)
	assert_float(s.instability_floor).is_equal_approx(45.0, EPS)
	s.apply_turn_meters({})
	assert_float(s.instability).is_greater(45.0)


func test_data_table_matches_docs() -> void:
	# The data file and the in-code fallback both carry the docs values; a
	# silent retune of res://data/meters.json fails here (the fix is a DCR).
	MetersScript.clear_cache()
	var table: Dictionary = MetersScript.table()
	assert_dict(table).is_equal(MetersScript.DOCS_TABLE)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	assert_bool(parsed is Dictionary).is_true()
	var data: Dictionary = parsed
	assert_dict(data["slow_burn"]).is_equal(MetersScript.DOCS_TABLE["slow_burn"])
	assert_dict(data["mood"]).is_equal(MetersScript.DOCS_TABLE["mood"])
	assert_float(table["ratchet_drop"]).is_equal_approx(15.0, EPS)
	assert_float(table["slow_burn"]["base"]).is_equal_approx(0.35, EPS)
	assert_float(table["slow_burn"]["per_fixation"]).is_equal_approx(0.15, EPS)
	assert_float(table["slow_burn"]["per_lucidity"]).is_equal_approx(0.2, EPS)
	assert_float(table["daily_burn"]).is_equal_approx(3.0, EPS)
	assert_float(table["mood"]["limit"]).is_equal_approx(3.0, EPS)
	assert_float(table["mood"]["scale"]["affection"]).is_equal_approx(1.5, EPS)
	assert_float(table["mood"]["scale"]["trust"]).is_equal_approx(2.0, EPS)
	assert_float(table["mood"]["scale"]["stress"]).is_equal_approx(0.6, EPS)
	assert_float(MetersScript.turn_cap(&"affection")).is_equal_approx(5.0, EPS)
	assert_float(MetersScript.turn_cap(&"instability")).is_equal_approx(3.0, EPS)
	assert_bool(is_inf(MetersScript.turn_cap(&"trust"))).is_true()


func test_broken_data_values_keep_docs_defaults() -> void:
	# A hand-edited meters.json can never zero a formula or make the ratchet
	# non-finite: bad types, non-finite numbers and unknown keys are ignored.
	# The origin label keeps the warning honest for a synthetic table.
	var merged: Dictionary = MetersScript.DOCS_TABLE.duplicate(true)
	(
		MetersScript
		. _merge_into(
			merged,
			{
				"ratchet_drop": "15",
				"daily_burn": NAN,
				"slow_burn": {"base": 0.9, "per_fixation": "x"},
				"mood": {"limit": 4.0, "scale": {"stress": INF}},
				"unknown_key": 1.0,
			},
			"synthetic table",
		)
	)
	assert_float(merged["ratchet_drop"]).is_equal_approx(15.0, EPS)
	assert_float(merged["daily_burn"]).is_equal_approx(3.0, EPS)
	assert_float(merged["slow_burn"]["base"]).is_equal_approx(0.9, EPS)
	assert_float(merged["slow_burn"]["per_fixation"]).is_equal_approx(0.15, EPS)
	assert_float(merged["mood"]["limit"]).is_equal_approx(4.0, EPS)
	assert_float(merged["mood"]["scale"]["stress"]).is_equal_approx(0.6, EPS)
	assert_bool(merged.has("unknown_key")).is_false()


func test_fixation_writers_follow_the_documented_sources() -> void:
	# docs/01 §2 Fixation "Moves by: time spent, affection, isolation". docs
	# number no magnitude (P2.22B DCR-1): time is the constant, affection only
	# counts when it was gained, isolation is read off the profile counters.
	assert_float(MetersScript.fixation_turn(0.0)).is_equal_approx(0.35, EPS)
	assert_float(MetersScript.fixation_turn(3.0)).is_equal_approx(0.5, EPS)
	assert_float(MetersScript.fixation_turn(-4.0)).is_equal_approx(0.35, EPS)
	assert_float(MetersScript.fixation_turn(NAN)).is_equal_approx(0.35, EPS)
	assert_float(MetersScript.isolation_gain({&"coldness": 1})).is_equal_approx(0.5, EPS)
	assert_float(MetersScript.isolation_gain({&"apathy": 2})).is_equal_approx(1.0, EPS)
	# Only the isolation counters pay; warmth is Lucidity's, not Fixation's.
	(
		assert_float(MetersScript.isolation_gain({&"ignored_questions": 1, &"warmth": 3}))
		. is_equal_approx(0.5, EPS)
	)
	assert_float(MetersScript.isolation_gain({})).is_zero()
	# Through the turn pipeline: time + the affection her mood actually landed.
	var s: Variant = _state()
	var ledger: Dictionary = s.apply_turn_meters({"mood": {"affection": 2}})
	assert_float(s.fixation).is_equal_approx(0.5, EPS)
	assert_float(ledger["fixation"]).is_equal_approx(0.5, EPS)
	# The isolation half arrives with the profile evidence, and a cold turn
	# moves Fixation while a warm one does not. The lines are long enough not to
	# trip the docs/01 §4.4 short-reply apathy rule, which is also isolation.
	var t: Variant = _state()
	t.apply_turn_profile(&"cold", "The weather has been strange all week, hasn't it?")
	assert_float(t.fixation).is_equal_approx(0.5, EPS)
	var u: Variant = _state()
	u.apply_turn_profile(&"affection", "You're really sweet, and I'm glad I came to see you today.")
	assert_float(u.fixation).is_zero()


func test_lucidity_writers_follow_the_documented_sources() -> void:
	# docs/01 §2 Lucidity "Moves by: kindness, honesty, boundaries" — mirrored
	# onto the profile counters those acts bump (warmth, honesty, boundaries).
	assert_float(MetersScript.lucidity_gain({&"warmth": 1})).is_equal_approx(0.3, EPS)
	assert_float(MetersScript.lucidity_gain({&"honesty": 1})).is_equal_approx(0.8, EPS)
	assert_float(MetersScript.lucidity_gain({&"boundaries": 1})).is_equal_approx(1.0, EPS)
	assert_float(MetersScript.lucidity_gain({&"teasing": 4, &"coldness": 2})).is_zero()
	(
		assert_float(MetersScript.lucidity_gain({&"warmth": 1, &"honesty": 1, &"boundaries": 1}))
		. is_equal_approx(2.1, EPS)
	)
	# Through the turn pipeline: an apology is honesty, a boundary is boundaries,
	# a warm line is kindness. The read label is the only input.
	var s: Variant = _state()
	s.apply_turn_profile(&"apology", "I'm sorry, that was unfair")
	assert_float(s.lucidity).is_equal_approx(0.8, EPS)
	s.apply_turn_profile(&"boundary", "please don't call me that")
	assert_float(s.lucidity).is_equal_approx(1.8, EPS)
	s.apply_turn_profile(&"affection", "you make me happy")
	assert_float(s.lucidity).is_equal_approx(2.1, EPS)


func test_night_path_check_writes_no_meters() -> void:
	# docs/01 §1 NIGHT re-scores the path without a turn: no line, no reply, so
	# no time was spent and no act happened (P2.22B).
	var s: Variant = _state()
	s.fixation = 30.0
	s.lucidity = 40.0
	s.apply_turn_profile(&"", "")
	s.apply_turn_profile(&"apology")
	assert_float(s.fixation).is_equal_approx(30.0, EPS)
	assert_float(s.lucidity).is_equal_approx(40.0, EPS)


func test_e12_lucidity_threshold_is_reachable() -> void:
	# docs/01 §2 + docs/01 §E12: "Remission — Lucidity ≥ 70 at Day 14". A kind,
	# honest, boundary-setting ANCHOR campaign (docs/01 §4.6) reaches it through
	# the real turn pipeline, and she is still sick when it does.
	var s: Variant = _state()
	var day_plan: Array[StringName] = [
		&"affection",
		&"affection",
		&"affection",
		&"affection",
		&"apology",
		&"apology",
		&"apology",
		&"boundary",
		&"boundary",
		&"question",
		&"question",
		&"question",
	]
	var mood_by_read := {
		&"affection": {"affection": 2, "trust": 1, "stress": -1},
		&"apology": {"affection": 0, "trust": 1, "stress": 0},
		&"boundary": {"affection": 0, "trust": 1, "stress": 0},
		&"question": {"affection": 0, "trust": 0, "stress": 0},
	}
	for day: int in GameStateScript.DAY_MAX:
		for read: StringName in day_plan:
			s.apply_turn_meters({"mood": mood_by_read[read]})
			s.apply_turn_profile(read, "a kind line", {})
		if day < GameStateScript.DAY_MAX - 1:
			s.advance_day()
	assert_float(s.lucidity).is_greater_equal(70.0)
	assert_float(s.fixation).is_greater(50.0)
	assert_float(s.instability).is_greater_equal(50.0)
	assert_int(s.stage).is_greater_equal(3)
	assert_int(s.day).is_equal(GameStateScript.DAY_MAX)


func test_turn_context_meters_carry_the_ratchet() -> void:
	# docs/02 §4 step 1: the turn context carries the meters, plus the ratchet
	# pair and the live slow-burn increment the prompt/overlay layers read.
	GameState.reset()
	GameState.fixation = 50.0
	GameState.lucidity = 25.0
	GameState.instability = 40.0
	var ctx_meters: Dictionary = TurnContext.meters()
	assert_float(ctx_meters["instability"]).is_equal_approx(40.0, EPS)
	assert_float(ctx_meters["fixation"]).is_equal_approx(50.0, EPS)
	assert_float(ctx_meters["instability_peak"]).is_equal_approx(40.0, EPS)
	assert_float(ctx_meters["instability_floor"]).is_equal_approx(25.0, EPS)
	assert_float(ctx_meters["slow_burn"]).is_equal_approx(MetersScript.slow_burn(50.0, 25.0), EPS)
	GameState.reset()
