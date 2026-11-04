extends GdUnitTestSuite
## P1.04 — GameState: meters + clamping (docs/01 §2), mood scaling (docs/02 §1.1),
## ratchet + stage bands (docs/01 §2–§3), behaviour-profile counters (docs/01 §2),
## serialisable snapshot, and the per-turn invariants from the SYS playbook.

const GameStateScript := preload("res://autoload/GameState.gd")
const MetersScript := preload("res://llm/Meters.gd")
const StagesScript := preload("res://llm/Stages.gd")
const PROFILE_MAP_PATH := "res://data/profile_map.json"
const EPS := 0.0001


func _state() -> Variant:
	return auto_free(GameStateScript.new())


func _counter(state: Variant, counter: StringName) -> int:
	return int(state.profile[String(counter)])


func test_fresh_state_defaults() -> void:
	var s: Variant = _state()
	for meter: StringName in GameStateScript.METER_NAMES:
		assert_float(s.get_meter(meter)).is_zero()
	assert_float(s.instability_peak).is_zero()
	assert_float(s.instability_floor).is_zero()
	assert_int(s.stage).is_zero()
	assert_int(s.day).is_equal(1)
	assert_int(s.turn).is_zero()
	assert_str(String(s.path)).is_equal("")
	assert_bool(s.path_locked).is_false()
	assert_str(s.player_name).is_equal("Senpai")
	assert_dict(s.flags).is_empty()
	for counter: StringName in GameStateScript.PROFILE_COUNTERS:
		assert_int(_counter(s, counter)).is_zero()


func test_meter_ranges_clamp() -> void:
	# docs/01 §2: affection 0–100, trust −50..+50, instability/fixation/lucidity 0–100.
	var s: Variant = _state()
	s.set_meter(&"affection", 250.0)
	assert_float(s.affection).is_equal_approx(100.0, EPS)
	s.set_meter(&"affection", -5.0)
	assert_float(s.affection).is_zero()
	s.set_meter(&"trust", 80.0)
	assert_float(s.trust).is_equal_approx(50.0, EPS)
	s.set_meter(&"trust", -80.0)
	assert_float(s.trust).is_equal_approx(-50.0, EPS)
	s.set_meter(&"trust", -25.0)
	assert_float(s.trust).is_equal_approx(-25.0, EPS)
	for meter: StringName in [&"fixation", &"lucidity"]:
		s.set_meter(meter, 120.0)
		assert_float(s.get_meter(meter)).is_equal_approx(100.0, EPS)
		s.set_meter(meter, -3.0)
		assert_float(s.get_meter(meter)).is_zero()
	s.set_meter(&"instability", -3.0)
	assert_float(s.instability).is_zero()
	s.set_meter(&"instability", 120.0)
	assert_float(s.instability).is_equal_approx(100.0, EPS)


func test_apply_mood_scales_and_clamps() -> void:
	# docs/02 §1.1: affection ×1.5, trust ×2, stress → instability ×0.6.
	var s: Variant = _state()
	s.apply_mood({"affection": 3, "trust": 3, "stress": 3})
	assert_float(s.affection).is_equal_approx(4.5, EPS)
	assert_float(s.trust).is_equal_approx(6.0, EPS)
	assert_float(s.instability).is_equal_approx(1.8, EPS)
	s.apply_mood({"affection": -3, "trust": -3, "stress": -3})
	assert_float(s.affection).is_zero()
	assert_float(s.trust).is_zero()
	assert_float(s.instability).is_zero()
	# Out-of-schema input is clamped to −3..3 before scaling (pillar 2).
	var t: Variant = _state()
	t.apply_mood({"affection": 99, "trust": -99, "stress": 99})
	assert_float(t.affection).is_equal_approx(4.5, EPS)
	assert_float(t.trust).is_equal_approx(-6.0, EPS)
	assert_float(t.instability).is_equal_approx(1.8, EPS)
	# docs/01 §2: model moves affection at most ±5 and instability at most ±3 per turn.
	var u: Variant = _state()
	u.apply_mood({"affection": 3, "stress": 3})
	assert_float(u.affection).is_less_equal(MetersScript.turn_cap(&"affection"))
	assert_float(u.instability).is_less_equal(MetersScript.turn_cap(&"instability"))
	# The caps are per turn, not per call (CODE-3): two moods in the same turn
	# share the budget; advance_turn() resets it.
	var v: Variant = _state()
	v.apply_mood({"affection": 3})
	v.apply_mood({"affection": 3})
	assert_float(v.affection).is_equal_approx(MetersScript.turn_cap(&"affection"), EPS)
	v.apply_mood({"stress": 3})
	v.apply_mood({"stress": 3})
	assert_float(v.instability).is_equal_approx(MetersScript.turn_cap(&"instability"), EPS)
	v.advance_turn()
	v.apply_mood({"affection": 3})
	assert_float(v.affection).is_equal_approx(9.5, EPS)
	# CODE-7: unlanded suggestions at a meter boundary never free budget in the
	# opposite direction — probe J starts affection at 0, applies -3 twice, then
	# +3 three times and must cap at 5.0 (instability at 3.0).
	var w: Variant = _state()
	w.apply_mood({"affection": -3, "stress": -3})
	w.apply_mood({"affection": -3, "stress": -3})
	w.apply_mood({"affection": 3, "stress": 3})
	w.apply_mood({"affection": 3, "stress": 3})
	w.apply_mood({"affection": 3, "stress": 3})
	assert_float(w.affection).is_equal_approx(MetersScript.turn_cap(&"affection"), EPS)
	assert_float(w.instability).is_equal_approx(MetersScript.turn_cap(&"instability"), EPS)
	# CODE-7 (ratchet): a mid-turn peak write lifts the floor and holds the meter
	# against the model's own delta. That game-side hold is not charged to the
	# model's budget, so the running total stays inside the cap and a later
	# same-sign suggestion never pulls the meter backwards.
	var x: Variant = _state()
	x.apply_mood({"stress": 3})
	x.instability_peak = 100.0
	x.set_meter(&"instability", 20.0)
	assert_float(x.instability).is_equal_approx(85.0, EPS)
	x.apply_mood({"stress": -3})
	assert_float(x.instability).is_equal_approx(85.0, EPS)
	x.apply_mood({"stress": 3})
	var after_up: float = x.instability
	x.apply_mood({"stress": 3})
	assert_float(x.instability).is_greater_equal(after_up)
	assert_float(x.instability).is_less_equal(85.0 + MetersScript.turn_cap(&"instability") + EPS)


func test_non_finite_input_never_poisons_state() -> void:
	# NAN/INF cannot round-trip JSON (docs/07 §3.5) and clampf() passes NAN
	# straight through, so every numeric choke point rejects them: the meter
	# keeps its last finite value and no signal fires (CODE-9/DES-7 hardening).
	var s: Variant = _state()
	s.set_meter(&"affection", 12.0)
	s.affection = NAN
	s.trust = INF
	s.fixation = -INF
	s.lucidity = NAN
	assert_float(s.affection).is_equal_approx(12.0, EPS)
	assert_float(s.trust).is_zero()
	assert_float(s.fixation).is_zero()
	assert_float(s.lucidity).is_zero()
	s.set_meter(&"instability", 30.0)
	s.instability = NAN
	assert_float(s.instability).is_equal_approx(30.0, EPS)
	assert_float(s.instability_peak).is_equal_approx(30.0, EPS)
	assert_float(s.instability_floor).is_equal_approx(15.0, EPS)
	s.instability_peak = INF
	assert_float(s.instability_peak).is_equal_approx(30.0, EPS)
	# Model mood is a Variant boundary: a non-finite suggestion moves nothing.
	var t: Variant = _state()
	t.apply_mood({"affection": NAN, "trust": INF, "stress": NAN})
	for meter: StringName in GameStateScript.METER_NAMES:
		assert_float(t.get_meter(meter)).is_zero()
	# A snapshot carrying non-finite numbers restores as its finite parts only.
	var u: Variant = _state()
	(
		assert_bool(u.from_dict({"affection": NAN, "instability": INF, "instability_peak": INF}))
		. is_true()
	)
	for meter: StringName in GameStateScript.METER_NAMES:
		assert_float(u.get_meter(meter)).is_zero()
	assert_float(u.instability_peak).is_zero()
	assert_bool(is_finite(u.to_dict()["affection"])).is_true()
	assert_str(JSON.stringify(u.to_dict())).is_not_empty()


func test_instability_ratchet_floor() -> void:
	# docs/01 §2: floor = peak − 15; she can have good days, she can't be cured.
	var s: Variant = _state()
	s.set_meter(&"instability", 40.0)
	assert_float(s.instability_peak).is_equal_approx(40.0, EPS)
	assert_float(s.instability_floor).is_equal_approx(25.0, EPS)
	s.set_meter(&"instability", 10.0)
	assert_float(s.instability).is_equal_approx(25.0, EPS)
	s.set_meter(&"instability", 30.0)
	assert_float(s.instability).is_equal_approx(30.0, EPS)
	assert_float(s.instability_peak).is_equal_approx(40.0, EPS)
	s.set_meter(&"instability", 60.0)
	assert_float(s.instability_floor).is_equal_approx(45.0, EPS)
	s.set_meter(&"instability", 30.0)
	assert_float(s.instability).is_equal_approx(45.0, EPS)
	# Below peak 15 the floor is 0 — no ratchet yet.
	var t: Variant = _state()
	t.set_meter(&"instability", 10.0)
	assert_float(t.instability_floor).is_zero()
	t.set_meter(&"instability", 0.0)
	assert_float(t.instability).is_zero()
	# CODE-9: direct writes to instability_peak remain bounded to 0..100.
	var p: Variant = _state()
	p.instability_peak = 500.0
	assert_float(p.instability_peak).is_equal_approx(100.0, EPS)
	assert_float(p.instability_floor).is_equal_approx(85.0, EPS)
	p.set_meter(&"instability", 10.0)
	assert_float(p.instability).is_equal_approx(85.0, EPS)
	p.instability_peak = -20.0
	assert_float(p.instability_peak).is_zero()


func test_stage_bands_monotonic_and_signal() -> void:
	# docs/01 §3: 0–14→0, 15–29→1, 30–49→2, 50–69→3, 70–89→4, 90–100→5.
	var cases := [
		[0.0, 0],
		[14.0, 0],
		[15.0, 1],
		[29.0, 1],
		[30.0, 2],
		[49.0, 2],
		[50.0, 3],
		[69.0, 3],
		[70.0, 4],
		[89.0, 4],
		[90.0, 5],
		[100.0, 5],
	]
	for case: Array in cases:
		assert_int(StagesScript.for_instability(case[0])).is_equal(case[1])
	# docs/01 §2–§3: a "good day" dips instability but the stage never regresses.
	var s: Variant = _state()
	var seen: Array = []
	s.stage_changed.connect(
		func(previous: int, current: int) -> void: seen.append([previous, current])
	)
	s.set_meter(&"instability", 55.0)
	assert_int(s.stage).is_equal(3)
	assert_array(seen).is_equal([[0, 3]])
	s.set_meter(&"instability", 40.0)
	assert_float(s.instability).is_equal_approx(40.0, EPS)
	assert_int(s.stage).is_equal(3)


func test_slow_burn_turn_and_daily() -> void:
	# docs/01 §2: +0.35 +0.15×(Fixation/100) −0.2×(Lucidity/100) per turn; +3 per day.
	# The formula itself is Meters' (P2.01); GameState applies it per turn.
	var s: Variant = _state()
	s.set_meter(&"fixation", 50.0)
	s.set_meter(&"lucidity", 25.0)
	assert_float(MetersScript.slow_burn(50.0, 25.0)).is_equal_approx(
		0.35 + 0.15 * 0.5 - 0.2 * 0.25, EPS
	)
	s.apply_turn_meters({})
	assert_float(s.instability).is_equal_approx(0.375, EPS)
	var t: Variant = _state()
	t.advance_day()
	assert_int(t.day).is_equal(2)
	assert_float(t.instability).is_equal_approx(3.0, EPS)
	t.set_meter(&"instability", 40.0)
	t.advance_day()
	assert_int(t.day).is_equal(3)
	assert_float(t.instability).is_equal_approx(43.0, EPS)
	# The campaign ends at day 14 (docs/01 §1, CODE-6/DES-4): advancing past the
	# cap is a no-op — no daily burn, no day_changed.
	var u: Variant = _state()
	var day_signals: Array = []
	u.day_changed.connect(func(d: int) -> void: day_signals.append(d))
	u.day = GameStateScript.DAY_MAX
	u.advance_day()
	assert_int(u.day).is_equal(GameStateScript.DAY_MAX)
	assert_float(u.instability).is_zero()
	assert_array(day_signals).is_empty()


func test_profile_counters() -> void:
	# docs/01 §2: the 12 counters, in doc order.
	(
		assert_array(Array(GameStateScript.PROFILE_COUNTERS))
		. is_equal(
			[
				&"warmth",
				&"coldness",
				&"inconsistency",
				&"teasing",
				&"jealousy_bait",
				&"leaving_talk",
				&"meta_curiosity",
				&"honesty",
				&"boundaries",
				&"apathy",
				&"control",
				&"flattery",
			]
		)
	)
	var s: Variant = _state()
	s.bump_profile(&"warmth")
	s.bump_profile(&"warmth", 4)
	assert_int(_counter(s, &"warmth")).is_equal(5)
	s.bump_profile(&"not_a_counter")
	assert_bool(s.profile.has("not_a_counter")).is_false()


func test_apply_turn_profile_maps_counters_from_data() -> void:
	# The expectation is read from the data file itself: retuning the map needs
	# no code change (SYS standard: everything tunable is data).
	var file_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_MAP_PATH))
	var table: Dictionary = file_map["read_to_profile"]
	for label: Variant in table:
		var s: Variant = _state()
		s.apply_turn_profile(StringName(label))
		for counter: StringName in GameStateScript.PROFILE_COUNTERS:
			var key := String(counter)
			var expected := int(table[label].get(key, 0))
			assert_int(_counter(s, counter)).is_equal(expected)


func test_apply_turn_profile_inconsistency_swings() -> void:
	# docs/01 §2: inconsistency counts warm↔cold swings in how the player treats her.
	var s: Variant = _state()
	s.apply_turn_profile(&"flirt")
	assert_int(_counter(s, &"inconsistency")).is_zero()
	s.apply_turn_profile(&"question")
	assert_int(_counter(s, &"inconsistency")).is_zero()
	s.apply_turn_profile(&"insult")
	assert_int(_counter(s, &"inconsistency")).is_equal(1)
	s.apply_turn_profile(&"cold")
	assert_int(_counter(s, &"inconsistency")).is_equal(1)
	s.apply_turn_profile(&"affection")
	assert_int(_counter(s, &"inconsistency")).is_equal(2)
	s.apply_turn_profile(&"insult")
	assert_int(_counter(s, &"inconsistency")).is_equal(3)


func test_intent_list_and_unknown_labels() -> void:
	# docs/02 §1.2: the 17 model intents, in doc order, all present in the data file.
	var s: Variant = _state()
	(
		assert_array(s.known_intents())
		. is_equal(
			[
				&"greeting",
				&"flirt",
				&"compliment",
				&"gift",
				&"question",
				&"small_talk",
				&"tease",
				&"insult",
				&"apology",
				&"leaving",
				&"jealousy_bait",
				&"meta",
				&"boundary",
				&"cold",
				&"affection",
				&"scared",
				&"other",
			]
		)
	)
	# Tone-map labels must be real intents; an unknown label is ignored, not fatal.
	var file_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_MAP_PATH))
	var intents: Dictionary = file_map["read_to_profile"]
	for tone_name: Variant in file_map.get("tone", {}):
		for label: Variant in file_map["tone"][tone_name]:
			assert_bool(intents.has(label)).is_true()
	s.apply_turn_profile(&"bogus")
	for counter: StringName in GameStateScript.PROFILE_COUNTERS:
		assert_int(_counter(s, counter)).is_zero()


func test_flags() -> void:
	var s: Variant = _state()
	s.set_flag(&"said_i_love_you")
	assert_bool(s.get_flag(&"said_i_love_you")).is_true()
	assert_bool(s.get_flag(&"missing")).is_false()
	s.set_flag(&"t01_count", 3)
	assert_int(int(s.get_flag(&"t01_count"))).is_equal(3)
	s.clear_flag(&"said_i_love_you")
	assert_bool(s.get_flag(&"said_i_love_you")).is_false()
	# Flags serialise — non-JSON-safe values are rejected, including nested ones
	# (CODE-4/DES-5): a Vector2 inside a Dictionary would stringify to a String.
	s.set_flag(&"bad", Vector2(1, 2))
	assert_bool(s.flags.has("bad")).is_false()
	s.set_flag(&"node", s)
	assert_bool(s.flags.has("node")).is_false()
	s.set_flag(&"nested_bad", {"v": Vector2(1, 2)})
	assert_bool(s.flags.has("nested_bad")).is_false()
	s.set_flag(&"deep_bad", [1, {"v": Vector2i(3, 4)}])
	assert_bool(s.flags.has("deep_bad")).is_false()
	s.set_flag(&"int_key", {1: "x"})
	assert_bool(s.flags.has("int_key")).is_false()
	s.set_flag(&"deep_ok", {"a": [1, {"b": "fine"}]})
	assert_dict(s.get_flag(&"deep_ok")).is_equal({"a": [1, {"b": "fine"}]})
	# DES-7: non-finite floats do not round-trip in JSON and are rejected.
	s.set_flag(&"nan", NAN)
	assert_bool(s.flags.has("nan")).is_false()
	s.set_flag(&"inf", INF)
	assert_bool(s.flags.has("inf")).is_false()
	s.set_flag(&"nested_inf", {"x": -INF})
	assert_bool(s.flags.has("nested_inf")).is_false()
	# CODE-10: cyclic or excessively deep containers fail safely without overflow.
	var cycle_arr: Array = []
	cycle_arr.append(cycle_arr)
	s.set_flag(&"cycle_arr", cycle_arr)
	assert_bool(s.flags.has("cycle_arr")).is_false()
	var cycle_dict := {}
	cycle_dict["self"] = cycle_dict
	s.set_flag(&"cycle_dict", cycle_dict)
	assert_bool(s.flags.has("cycle_dict")).is_false()
	var deep: Variant = 1
	for _i: int in GameStateScript.FLAG_MAX_DEPTH + 2:
		deep = [deep]
	s.set_flag(&"too_deep", deep)
	assert_bool(s.flags.has("too_deep")).is_false()


func test_path_assign_and_lock() -> void:
	var s: Variant = _state()
	assert_bool(s.assign_path(&"HOLLOW")).is_true()
	assert_str(String(s.path)).is_equal("HOLLOW")
	assert_bool(s.assign_path(&"bogus")).is_false()
	s.lock_path()
	assert_bool(s.path_locked).is_true()
	assert_bool(s.assign_path(&"YANDERE")).is_false()
	assert_str(String(s.path)).is_equal("HOLLOW")


func test_paths_match_casting_json() -> void:
	# DES-3: path ids are the canonical data/casting.json keys — P1.10/P2.12
	# index casting["paths"] with GameState.path (TSUN, not docs/01's "TSUN-BREAK").
	var casting: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/casting.json")
	)
	var casting_paths: Dictionary = casting.get("paths", {})
	assert_int(casting_paths.size()).is_equal(6)
	for path_id: StringName in GameStateScript.PATHS:
		assert_bool(casting_paths.has(String(path_id))).is_true()


func test_snapshot_round_trip() -> void:
	# Acceptance: a serialisable snapshot that restores identically,
	# and survives JSON (SaveSystem writes it to user://, docs/07 §3.5).
	var s: Variant = _state()
	s.set_meter(&"affection", 61.5)
	s.set_meter(&"trust", -12.25)
	s.set_meter(&"instability", 45.0)
	s.set_meter(&"fixation", 20.0)
	s.set_meter(&"lucidity", 10.0)
	s.turn = 9
	s.assign_path(&"YANDERE", true)
	s.player_name = "Rin"
	s.set_flag(&"said_i_love_you")
	s.set_flag(&"t01_count", 2)
	s.set_flag(&"meta_flag", {"nested": [1, 2]})
	s.bump_profile(&"warmth", 3)
	s.apply_turn_profile(&"insult")
	var snapshot: Dictionary = s.to_dict()
	var t: Variant = _state()
	assert_bool(t.from_dict(snapshot)).is_true()
	assert_dict(t.to_dict()).is_equal(snapshot)
	# JSON has one number type (ints come back as floats inside flags), so the
	# save/load invariant is checked in the JSON domain: from_dict(to_dict())
	# serialised again must equal the serialised snapshot.
	var json_snapshot: Variant = JSON.parse_string(JSON.stringify(snapshot))
	var u: Variant = _state()
	assert_bool(u.from_dict(json_snapshot)).is_true()
	var u_json: Variant = JSON.parse_string(JSON.stringify(u.to_dict()))
	assert_dict(u_json).is_equal(json_snapshot)


func test_from_dict_heals_and_rejects() -> void:
	var t: Variant = _state()
	var ok: bool = (
		t
		. from_dict(
			{
				"affection": 500.0,
				"instability": 5.0,
				"instability_peak": 60.0,
				"stage": 0,
				"day": -3,
				"turn": -9,
				"path": "nonsense",
				"profile": {"warmth": -4, "bogus": 9},
				"player_name": 42,
			}
		)
	)
	assert_bool(ok).is_true()
	assert_float(t.affection).is_equal_approx(100.0, EPS)
	assert_float(t.instability).is_equal_approx(45.0, EPS)
	# Stage re-derives from the peak's band (CODE-1/DES-2): peak 60 means she
	# already reached stage 3 — a stored stage below it is stale.
	assert_int(t.stage).is_equal(3)
	assert_int(t.day).is_equal(1)
	assert_int(t.turn).is_zero()
	assert_str(String(t.path)).is_equal("")
	assert_bool(t.path_locked).is_false()
	assert_int(_counter(t, &"warmth")).is_zero()
	assert_bool(t.profile.has("bogus")).is_false()
	assert_str(t.player_name).is_equal("Senpai")
	assert_bool(t.from_dict("not a dict")).is_false()
	assert_bool(t.from_dict(null)).is_false()
	# A Dictionary with no snapshot keys is rejected, not healed into defaults.
	assert_bool(t.from_dict({"unrelated": 1, "data": [1, 2]})).is_false()


func test_deterministic_replay() -> void:
	# SYS standard: the same op transcript replays to an identical snapshot.
	var ops := [
		["read", &"flirt"],
		["mood", {"affection": 2, "trust": 1, "stress": 1}],
		["burn", 0],
		["read", &"insult"],
		["mood", {"affection": -1, "trust": -2, "stress": -1}],
		["read", &"meta"],
		["day", 0],
	]
	var a: Variant = _state()
	var b: Variant = _state()
	for op: Array in ops:
		_apply_op(a, op)
		_apply_op(b, op)
	assert_dict(a.to_dict()).is_equal(b.to_dict())


func test_simulation_invariants() -> void:
	# 150 synthetic turns: every meter stays in range, instability ≥ floor,
	# stage never regresses, counters never go negative.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var s: Variant = _state()
	var labels: Array = s.known_intents()
	var last_stage := 0
	for i: int in 150:
		(
			s
			. apply_mood(
				{
					"affection": rng.randi_range(-6, 6),
					"trust": rng.randi_range(-6, 6),
					"stress": rng.randi_range(-6, 6),
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
		assert_float(s.instability).is_greater_equal(s.instability_floor - EPS)
		assert_int(s.stage).is_greater_equal(last_stage)
		last_stage = s.stage
		for counter: StringName in GameStateScript.PROFILE_COUNTERS:
			assert_int(_counter(s, counter)).is_greater_equal(0)


func test_reset_returns_to_fresh_state() -> void:
	var s: Variant = _state()
	s.set_meter(&"instability", 80.0)
	s.assign_path(&"SPLIT", true)
	s.advance_day()
	s.apply_turn_profile(&"meta")
	# CODE-2: reset() replaces the state wholesale — listeners get state_reset
	# to resync rather than replayed per-field signals.
	var resets: Array = []
	s.state_reset.connect(func() -> void: resets.append(true))
	s.reset()
	assert_array(resets).is_equal([true])
	var fresh: Variant = _state()
	assert_dict(s.to_dict()).is_equal(fresh.to_dict())


func _apply_op(s: Variant, op: Array) -> void:
	match String(op[0]):
		"read":
			s.apply_turn_profile(op[1])
		"mood":
			s.apply_mood(op[1])
		"burn":
			s.apply_turn_meters({})
		"day":
			s.advance_day()
