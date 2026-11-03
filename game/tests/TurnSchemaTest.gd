extends GdUnitTestSuite
## P1.07 — Turn schema builder and stage gates (docs/02 §2–§3).

const TurnSchemaScript := preload("res://llm/TurnSchema.gd")


func _valid_turn_stage0() -> Dictionary:
	return {
		"read": "greeting",
		"inner": "He finally came.",
		"beats":
		[
			{
				"feeling": "warmth",
				"intensity": 1,
				"cue": "none",
				"say": "Hi, I'm glad you're here.",
			}
		],
		"mood":
		{
			"affection": 1,
			"trust": 0,
			"stress": 0,
		},
		"memory": "came to visit",
		"action": "none",
		"music": "keep",
		"fx": "none",
		"meta": null,
	}


func test_canonical_property_order() -> void:
	var schema := TurnSchemaScript.build_turn_schema(0)
	var expected_order := [
		"read",
		"inner",
		"beats",
		"mood",
		"memory",
		"action",
		"music",
		"fx",
		"meta",
	]
	var prop_keys: Array = schema["properties"].keys()
	assert_array(prop_keys).is_equal(expected_order)
	assert_array(Array(schema["required"])).is_equal(expected_order)


func test_docs_02_section_3_structure() -> void:
	var schema := TurnSchemaScript.build_turn_schema(0)
	assert_str(schema["type"]).is_equal("object")
	assert_dict(schema["properties"]).is_not_empty()

	# read
	var read_prop: Dictionary = schema["properties"]["read"]
	assert_str(read_prop["type"]).is_equal("string")
	assert_array(read_prop["enum"]).contains_exactly(TurnSchemaScript.INTENTS)

	# inner
	var inner_prop: Dictionary = schema["properties"]["inner"]
	assert_str(inner_prop["type"]).is_equal("string")
	assert_int(inner_prop["minLength"]).is_equal(1)
	assert_int(inner_prop["maxLength"]).is_equal(90)

	# beats
	var beats_prop: Dictionary = schema["properties"]["beats"]
	assert_str(beats_prop["type"]).is_equal("array")
	assert_int(beats_prop["minItems"]).is_equal(1)
	assert_int(beats_prop["maxItems"]).is_equal(3)
	var beat_items: Dictionary = beats_prop["items"]
	assert_str(beat_items["type"]).is_equal("object")
	assert_array(Array(beat_items["required"])).is_equal(["feeling", "intensity", "cue", "say"])

	var feeling_prop: Dictionary = beat_items["properties"]["feeling"]
	assert_str(feeling_prop["type"]).is_equal("string")
	assert_int(feeling_prop["enum"].size()).is_equal(22)
	assert_array(feeling_prop["enum"]).contains_exactly(TurnSchemaScript.get_canonical_feelings())

	var intensity_prop: Dictionary = beat_items["properties"]["intensity"]
	assert_str(intensity_prop["type"]).is_equal("integer")
	assert_int(intensity_prop["minimum"]).is_equal(1)
	assert_int(intensity_prop["maximum"]).is_equal(3)

	var say_prop: Dictionary = beat_items["properties"]["say"]
	assert_str(say_prop["type"]).is_equal("string")
	assert_int(say_prop["minLength"]).is_equal(1)
	assert_int(say_prop["maxLength"]).is_equal(200)

	# mood
	var mood_prop: Dictionary = schema["properties"]["mood"]
	assert_str(mood_prop["type"]).is_equal("object")
	assert_array(Array(mood_prop["required"])).is_equal(["affection", "trust", "stress"])
	for meter: String in ["affection", "trust", "stress"]:
		var m: Dictionary = mood_prop["properties"][meter]
		assert_str(m["type"]).is_equal("integer")
		assert_int(m["minimum"]).is_equal(-3)
		assert_int(m["maximum"]).is_equal(3)

	# memory
	var memory_prop: Dictionary = schema["properties"]["memory"]
	assert_str(memory_prop["type"]).is_equal("string")
	assert_int(memory_prop["maxLength"]).is_equal(80)

	# action
	var action_prop: Dictionary = schema["properties"]["action"]
	assert_str(action_prop["type"]).is_equal("string")
	assert_array(action_prop["enum"]).contains_exactly(["none"])


func test_stage_0_enums() -> void:
	var schema := TurnSchemaScript.build_turn_schema(0)
	var beat_cue: Dictionary = schema["properties"]["beats"]["items"]["properties"]["cue"]
	var music_prop: Dictionary = schema["properties"]["music"]
	var fx_prop: Dictionary = schema["properties"]["fx"]
	var meta_prop: Dictionary = schema["properties"]["meta"]

	var expected_cues := [
		"none",
		"giggle",
		"laugh_soft",
		"gasp",
		"sigh",
		"hum",
		"sniffle",
		"heartbeat",
	]
	var expected_music := ["keep", "romantic", "playful", "calm", "melancholy"]
	var expected_fx := ["none", "blush_glow", "hearts", "sparkle", "shake_small", "zoom_face"]

	assert_array(beat_cue["enum"]).is_equal(expected_cues)
	assert_array(music_prop["enum"]).is_equal(expected_music)
	assert_array(fx_prop["enum"]).is_equal(expected_fx)
	assert_str(meta_prop["type"]).is_equal("null")


func test_stage_1_enums() -> void:
	var schema := TurnSchemaScript.build_turn_schema(1)
	var beat_cue: Dictionary = schema["properties"]["beats"]["items"]["properties"]["cue"]
	var music_prop: Dictionary = schema["properties"]["music"]
	var fx_prop: Dictionary = schema["properties"]["fx"]
	var meta_prop: Dictionary = schema["properties"]["meta"]

	var expected_cues := [
		"none",
		"giggle",
		"laugh_soft",
		"gasp",
		"sigh",
		"hum",
		"sniffle",
		"heartbeat",
		"sob",
		"music_box_note",
		"clock_tick",
		"phone_buzz",
	]
	var expected_music := ["keep", "romantic", "playful", "calm", "melancholy"]
	var expected_fx := [
		"none",
		"blush_glow",
		"hearts",
		"sparkle",
		"shake_small",
		"zoom_face",
		"rain",
	]

	assert_array(beat_cue["enum"]).is_equal(expected_cues)
	assert_array(music_prop["enum"]).is_equal(expected_music)
	assert_array(fx_prop["enum"]).is_equal(expected_fx)
	assert_str(meta_prop["type"]).is_equal("null")


func test_stage_gates_across_all_stages() -> void:
	for stage: int in range(6):
		var schema := TurnSchemaScript.build_turn_schema(stage)
		var cues: Array = schema["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
		var music: Array = schema["properties"]["music"]["enum"]
		var fx: Array = schema["properties"]["fx"]["enum"]

		# cues expand or stay equal
		assert_bool(cues.has("none")).is_true()
		assert_bool(music.has("keep")).is_true()
		assert_bool(fx.has("none")).is_true()

	# Stage 2 unlocks: heartbeat_fast, whisper, knock, tense, music_box, silence
	var s2 := TurnSchemaScript.build_turn_schema(2)
	var cues2: Array = s2["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
	var music2: Array = s2["properties"]["music"]["enum"]
	assert_bool(cues2.has("heartbeat_fast")).is_true()
	assert_bool(cues2.has("whisper")).is_true()
	assert_bool(cues2.has("knock")).is_true()
	assert_bool(music2.has("tense")).is_true()
	assert_bool(music2.has("music_box")).is_true()
	assert_bool(music2.has("silence")).is_true()

	# Stage 3 unlocks: breath_close, door_slam, glass_shatter, static, dread, distorted,
	# shake_big, glitch
	var s3 := TurnSchemaScript.build_turn_schema(3)
	var cues3: Array = s3["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
	var music3: Array = s3["properties"]["music"]["enum"]
	var fx3: Array = s3["properties"]["fx"]["enum"]
	assert_bool(cues3.has("breath_close")).is_true()
	assert_bool(cues3.has("door_slam")).is_true()
	assert_bool(cues3.has("glass_shatter")).is_true()
	assert_bool(cues3.has("static")).is_true()
	assert_bool(music3.has("dread")).is_true()
	assert_bool(music3.has("distorted")).is_true()
	assert_bool(fx3.has("shake_big")).is_true()
	assert_bool(fx3.has("glitch")).is_true()

	# Stage 4 unlocks: laugh_unhinged, knife_draw, text_bleed, invert_flash
	var s4 := TurnSchemaScript.build_turn_schema(4)
	var cues4: Array = s4["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
	var fx4: Array = s4["properties"]["fx"]["enum"]
	assert_bool(cues4.has("laugh_unhinged")).is_true()
	assert_bool(cues4.has("knife_draw")).is_true()
	assert_bool(fx4.has("text_bleed")).is_true()
	assert_bool(fx4.has("invert_flash")).is_true()

	# Stage 5 unlocks: scream, her_eyes
	var s5 := TurnSchemaScript.build_turn_schema(5)
	var cues5: Array = s5["properties"]["beats"]["items"]["properties"]["cue"]["enum"]
	var fx5: Array = s5["properties"]["fx"]["enum"]
	assert_bool(cues5.has("scream")).is_true()
	assert_bool(fx5.has("her_eyes")).is_true()


func test_meta_null_gated_stages_0_to_2_unlocked_stage_3_plus() -> void:
	for st: int in [0, 1, 2]:
		var schema := TurnSchemaScript.build_turn_schema(st)
		assert_bool(TurnSchemaScript.is_meta_unlocked(st)).is_false()
		assert_str(schema["properties"]["meta"]["type"]).is_equal("null")

	for st: int in [3, 4, 5]:
		var schema := TurnSchemaScript.build_turn_schema(st)
		assert_bool(TurnSchemaScript.is_meta_unlocked(st)).is_true()
		assert_array(schema["properties"]["meta"]["type"]).is_equal(["object", "null"])


func test_offered_actions() -> void:
	# Default has only none
	var s_default := TurnSchemaScript.build_turn_schema(0)
	assert_array(s_default["properties"]["action"]["enum"]).is_equal(["none"])

	# Offered action at stage 0 (e.g. end_date)
	var s_offered := TurnSchemaScript.build_turn_schema(0, ["end_date"])
	assert_array(s_offered["properties"]["action"]["enum"]).is_equal(["none", "end_date"])

	# Stage 3 offered action (e.g. refuse_exit)
	var s_st3 := TurnSchemaScript.build_turn_schema(3, ["refuse_exit"])
	assert_array(s_st3["properties"]["action"]["enum"]).is_equal(["none", "refuse_exit"])

	# Gated action not offered below threshold
	var s_st1 := TurnSchemaScript.build_turn_schema(1, ["refuse_exit"])
	assert_array(s_st1["properties"]["action"]["enum"]).is_equal(["none"])

	# Turn context dictionary form
	var ctx := {
		"stage": 3,
		"offered_actions": ["refuse_exit", "window_shake"],
	}
	var s_ctx := TurnSchemaScript.build_turn_schema(ctx)
	assert_array(s_ctx["properties"]["action"]["enum"]).is_equal(
		["none", "refuse_exit", "window_shake"]
	)


func test_validate_turn_valid_turn() -> void:
	var turn := _valid_turn_stage0()
	var errs := TurnSchemaScript.validate_turn(turn, 0)
	assert_array(errs).is_empty()

	# Also valid with check_order option
	var errs_ordered := TurnSchemaScript.validate_turn(turn, 0, [], {"check_order": true})
	assert_array(errs_ordered).is_empty()


func test_validate_turn_detects_out_of_gate_assets() -> void:
	var turn := _valid_turn_stage0()

	# Cue out of gate: sob is stage 1, not stage 0
	turn["beats"][0]["cue"] = "sob"
	var errs := TurnSchemaScript.validate_turn(turn, 0)
	assert_int(errs.size()).is_equal(1)
	assert_str(errs[0]).contains("outside stage 0 gate")

	# Music out of gate: tense is stage 2, not stage 0
	turn = _valid_turn_stage0()
	turn["music"] = "tense"
	errs = TurnSchemaScript.validate_turn(turn, 0)
	assert_int(errs.size()).is_equal(1)
	assert_str(errs[0]).contains("outside stage 0 gate")

	# FX out of gate: rain is stage 1, not stage 0
	turn = _valid_turn_stage0()
	turn["fx"] = "rain"
	errs = TurnSchemaScript.validate_turn(turn, 0)
	assert_int(errs.size()).is_equal(1)
	assert_str(errs[0]).contains("outside stage 0 gate")


func test_validate_turn_enforces_meta_stage_gates() -> void:
	var turn := _valid_turn_stage0()
	turn["meta"] = {"leak": true}

	# Stage 0: meta must be null
	var errs0 := TurnSchemaScript.validate_turn(turn, 0)
	assert_int(errs0.size()).is_equal(1)
	assert_str(errs0[0]).contains("meta must be null at stage 0")

	# Stage 2: meta must still be null
	var errs2 := TurnSchemaScript.validate_turn(turn, 2)
	assert_int(errs2.size()).is_equal(1)
	assert_str(errs2[0]).contains("meta must be null at stage 2")

	# Stage 3: meta can be an object
	turn["meta"] = {"leak": true}
	var errs3 := TurnSchemaScript.validate_turn(turn, 3)
	assert_array(errs3).is_empty()

	# Stage 3: meta can also be null
	turn["meta"] = null
	var errs3_null := TurnSchemaScript.validate_turn(turn, 3)
	assert_array(errs3_null).is_empty()


func test_validate_turn_enforces_string_limits_and_non_empty() -> void:
	# C9 requirement: inner and say must have minLength 1
	var turn := _valid_turn_stage0()
	turn["inner"] = ""
	var errs := TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(errs.any(func(e: String) -> bool: return e.contains("inner must not be empty")))
		. is_true()
	)

	turn = _valid_turn_stage0()
	turn["beats"][0]["say"] = ""
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(errs.any(func(e: String) -> bool: return e.contains("say must not be empty")))
		. is_true()
	)

	# Max length limits: inner <= 90, say <= 200, memory <= 80
	turn = _valid_turn_stage0()
	turn["inner"] = "a".repeat(91)
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(errs.any(func(e: String) -> bool: return e.contains("inner exceeds maxLength")))
		. is_true()
	)

	turn = _valid_turn_stage0()
	turn["beats"][0]["say"] = "a".repeat(201)
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(errs.any(func(e: String) -> bool: return e.contains("say exceeds maxLength")))
		. is_true()
	)

	turn = _valid_turn_stage0()
	turn["memory"] = "a".repeat(81)
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(
			errs.any(func(e: String) -> bool: return e.contains("memory exceeds maxLength"))
		)
		. is_true()
	)


func test_validate_turn_enforces_mood_and_intensity_ranges() -> void:
	var turn := _valid_turn_stage0()
	turn["mood"]["affection"] = 4
	var errs := TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(
			errs.any(
				func(e: String) -> bool: return e.contains("mood.affection value 4 outside -3..3")
			)
		)
		. is_true()
	)

	turn = _valid_turn_stage0()
	turn["mood"]["stress"] = -4
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(
			errs.any(
				func(e: String) -> bool: return e.contains("mood.stress value -4 outside -3..3")
			)
		)
		. is_true()
	)

	turn = _valid_turn_stage0()
	turn["beats"][0]["intensity"] = 0
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(
			errs.any(func(e: String) -> bool: return e.contains("intensity 0 outside 1..3"))
		)
		. is_true()
	)

	turn = _valid_turn_stage0()
	turn["beats"][0]["intensity"] = 4
	errs = TurnSchemaScript.validate_turn(turn, 0)
	(
		assert_bool(
			errs.any(func(e: String) -> bool: return e.contains("intensity 4 outside 1..3"))
		)
		. is_true()
	)


func test_validate_turn_enforces_canonical_feelings() -> void:
	var turn := _valid_turn_stage0()
	turn["beats"][0]["feeling"] = "not_a_feeling"
	var errs := TurnSchemaScript.validate_turn(turn, 0)
	assert_bool(errs.any(func(e: String) -> bool: return e.contains("not in FEELINGS"))).is_true()


func test_validate_turn_enforces_action_offers() -> void:
	var turn := _valid_turn_stage0()
	turn["action"] = "refuse_exit"

	# Unoffered action rejected
	var errs_unoffered := TurnSchemaScript.validate_turn(turn, 3)
	(
		assert_bool(
			errs_unoffered.any(func(e: String) -> bool: return e.contains("not in offered actions"))
		)
		. is_true()
	)

	# Explicitly offered action accepted at stage 3
	var errs_offered := TurnSchemaScript.validate_turn(turn, 3, ["refuse_exit"])
	assert_array(errs_offered).is_empty()


func test_data_loaded_from_files() -> void:
	var gates := TurnSchemaScript.get_stage_gates()
	assert_dict(gates).is_not_empty()
	assert_bool(gates.has("stages")).is_true()
	assert_bool(gates.has("gates")).is_true()

	var feelings := TurnSchemaScript.get_canonical_feelings()
	assert_int(feelings.size()).is_equal(22)
	assert_bool(feelings.has("joy")).is_true()
	assert_bool(feelings.has("manic")).is_true()
