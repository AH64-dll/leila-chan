extends GdUnitTestSuite
## P4.06 — Fast mode (docs/07 §4): one beat and a shorter reply, enforced by the
## turn grammar. The limits live in the schema the grammar compiles, so a capped
## request cannot emit a longer turn. These tests pin the limits, the property order,
## the persisted switch and the fallback for bad data.

const TMP := "user://fast_mode_test.cfg"

var _saved: Dictionary = {}


func before_test() -> void:
	_saved = {
		"settings_path": Settings.settings_path,
		"fast_mode": Settings.fast_mode,
		"content_level": Settings.content_level,
		"pre_calmer": Settings._pre_calmer_level,
		"immersion": Settings.immersion,
		"text_speed": Settings.text_speed,
		"use_os_username": Settings.use_os_username,
		"bus_volumes": Settings.bus_volumes.duplicate(),
		"photosensitive": Settings.photosensitive,
		"reduced_motion": Settings.reduced_motion,
		"fx_photosensitive": FX.photosensitive,
	}
	_remove_tmp()
	Settings.settings_path = TMP
	Settings.fast_mode = false
	TurnContext.clear_fast_cache()


func after_test() -> void:
	_remove_tmp()
	Settings.settings_path = _saved["settings_path"]
	Settings.fast_mode = _saved["fast_mode"]
	Settings.content_level = _saved["content_level"]
	Settings._pre_calmer_level = _saved["pre_calmer"]
	Settings.immersion = _saved["immersion"]
	Settings.text_speed = _saved["text_speed"]
	Settings.use_os_username = _saved["use_os_username"]
	Settings.bus_volumes = _saved["bus_volumes"]
	Settings.photosensitive = _saved["photosensitive"]
	Settings.reduced_motion = _saved["reduced_motion"]
	FX.photosensitive = _saved["fx_photosensitive"]
	TurnContext.clear_fast_cache()


func _remove_tmp() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _request(stage: int) -> TurnRequest:
	var req := TurnRequest.new()
	req.schema = TurnSchema.build_turn_schema(stage)
	return req


## A one-beat stage 0 turn, inside the fast limits (say <= 160, inner <= 60).
func _one_beat_turn() -> Dictionary:
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


## ── Request shaping ────────────────────────────────────────────────────────────


## Normal mode sets the documented budget and leaves the schema byte-identical.
func test_normal_mode_keeps_the_budget_and_the_schema() -> void:
	var req := _request(0)
	req.max_tokens = 123
	var before := JSON.stringify(req.schema, "", false)
	TurnContext.finalize_request(req, false)
	assert_int(TurnContext.NORMAL_MAX_TOKENS).is_equal(600)
	assert_int(req.max_tokens).is_equal(600)
	assert_str(JSON.stringify(req.schema, "", false)).is_equal(before)


## Fast mode: one beat, the say and inner caps, and the 220-token budget.
func test_fast_mode_caps_beats_lengths_and_budget() -> void:
	var req := _request(0)
	TurnContext.finalize_request(req, true)
	assert_int(req.max_tokens).is_equal(220)
	var props: Dictionary = req.schema["properties"]
	var beats: Dictionary = props["beats"]
	var beat_props: Dictionary = beats["items"]["properties"]
	assert_int(beats["maxItems"]).is_equal(1)
	assert_int(beats["minItems"]).is_equal(1)
	assert_int(beat_props["say"]["maxLength"]).is_equal(160)
	assert_int(props["inner"]["maxLength"]).is_equal(60)


## The source schema is the template every turn is built from; fast mode copies it.
func test_fast_mode_does_not_mutate_the_source_schema() -> void:
	var source := TurnSchema.build_turn_schema(0)
	var before := JSON.stringify(source, "", false)
	var req := TurnRequest.new()
	req.schema = source
	TurnContext.finalize_request(req, true)
	assert_str(JSON.stringify(source, "", false)).is_equal(before)
	var source_beats: Dictionary = source["properties"]["beats"]
	assert_int(source_beats["maxItems"]).is_equal(3)


## Fast mode keeps property order: the grammar and the prompt read keys in order.
func test_fast_mode_keeps_property_order() -> void:
	var source := TurnSchema.build_turn_schema(2)
	var order_before: Array = (source["properties"] as Dictionary).keys()
	var required_before: Array = source["required"]
	var req := TurnRequest.new()
	req.schema = source
	TurnContext.finalize_request(req, true)
	var order_after: Array = (req.schema["properties"] as Dictionary).keys()
	assert_array(order_after).is_equal(order_before)
	assert_array(req.schema["required"]).is_equal(required_before)


## A schema with no `inner` (a custom property order leaves it out) still caps.
func test_a_schema_without_inner_still_caps_the_beats() -> void:
	var ctx := {"stage": 0, "property_order": ["read", "beats", "action"]}
	var req := TurnRequest.new()
	req.schema = TurnSchema.build_turn_schema(ctx)
	TurnContext.finalize_request(req, true)
	var props: Dictionary = req.schema["properties"]
	assert_bool(props.has("inner")).is_false()
	assert_int(props["beats"]["maxItems"]).is_equal(1)
	assert_array(props.keys()).is_equal(["read", "beats", "action"])


## A limit already lower than the fast value is kept, and never raised.
func test_a_limit_already_lower_than_fast_is_kept() -> void:
	var req := TurnRequest.new()
	req.schema = {
		"type": "object",
		"properties":
		{
			"inner": {"type": "string", "maxLength": 30},
			"beats":
			{
				"type": "array",
				"maxItems": 1,
				"items":
				{
					"type": "object",
					"properties": {"say": {"type": "string", "maxLength": 40}},
				},
			},
		},
		"required": ["inner", "beats"],
	}
	TurnContext.finalize_request(req, true)
	var props: Dictionary = req.schema["properties"]
	assert_int(props["inner"]["maxLength"]).is_equal(30)
	assert_int(props["beats"]["maxItems"]).is_equal(1)
	assert_int(props["beats"]["items"]["properties"]["say"]["maxLength"]).is_equal(40)


## The capped schema still describes a turn the existing validator accepts, and the
## turn fits the capped beat count.
func test_a_one_beat_turn_passes_the_validator_under_the_fast_schema() -> void:
	var req := _request(0)
	TurnContext.finalize_request(req, true)
	var turn := _one_beat_turn()
	assert_array(TurnSchema.validate_turn(turn, 0)).is_empty()
	var max_beats: int = req.schema["properties"]["beats"]["maxItems"]
	assert_int((turn["beats"] as Array).size()).is_less_equal(max_beats)


## ── The persisted switch ───────────────────────────────────────────────────────


## The switch is off until the player turns it on.
func test_fast_mode_defaults_off_without_a_file() -> void:
	assert_bool(FileAccess.file_exists(TMP)).is_false()
	Settings.load_settings()
	assert_bool(Settings.fast_mode).is_false()


## Turning it on writes it down, and a fresh load reads it back.
func test_fast_mode_persists_through_save_and_load() -> void:
	Settings.set_fast_mode(true)
	assert_bool(Settings.fast_mode).is_true()
	var cfg := ConfigFile.new()
	assert_int(cfg.load(TMP)).is_equal(OK)
	assert_bool(cfg.get_value(Settings.SECTION_GAME, "fast_mode", false)).is_true()
	Settings.fast_mode = false
	Settings.load_settings()
	assert_bool(Settings.fast_mode).is_true()
	Settings.set_fast_mode(false)
	Settings.fast_mode = true
	Settings.load_settings()
	assert_bool(Settings.fast_mode).is_false()


## A settings file from before P4.06 has no fast_mode key and loads as off, even
## when the session already had it on.
func test_an_old_file_without_the_key_loads_off() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Settings.SECTION_ACCESSIBILITY, "reduced_motion", false)
	assert_int(cfg.save(TMP)).is_equal(OK)
	Settings.fast_mode = true
	Settings.load_settings()
	assert_bool(Settings.fast_mode).is_false()


## A hand-edited value that is not a bool loads as off and does not abort the load.
func test_a_non_bool_value_loads_off() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Settings.SECTION_GAME, "fast_mode", "yes")
	assert_int(cfg.save(TMP)).is_equal(OK)
	Settings.fast_mode = true
	Settings.load_settings()
	assert_bool(Settings.fast_mode).is_false()


## ── The data file and bad data ─────────────────────────────────────────────────


## The shipped data file carries the docs/07 §4 numbers.
func test_the_data_file_carries_the_documented_limits() -> void:
	var limits := TurnContext.fast_mode_spec()
	assert_int(limits["max_tokens"]).is_equal(220)
	assert_int(limits["max_beats"]).is_equal(1)
	assert_int(limits["say_max_length"]).is_equal(160)
	assert_int(limits["inner_max_length"]).is_equal(60)


## A document that is not a JSON object (missing, empty, or a non-object) falls back
## to the documented limits.
func test_a_broken_document_falls_back_to_the_documented_limits() -> void:
	for parsed: Variant in [null, "fast", [1, 2]]:
		var limits := TurnContext.parse_fast_mode(parsed)
		assert_int(limits["max_tokens"]).is_equal(220)
		assert_int(limits["max_beats"]).is_equal(1)
		assert_int(limits["say_max_length"]).is_equal(160)
		assert_int(limits["inner_max_length"]).is_equal(60)


## Each field falls back on its own: a bad value does not drag the good ones back to
## the defaults, a whole-number float is read as an integer, and a valid override holds.
func test_bad_fields_fall_back_one_by_one() -> void:
	var document := {
		"max_tokens": "lots",
		"max_beats": 0,
		"say_max_length": 120.0,
		"inner_max_length": -4.0,
	}
	var limits := TurnContext.parse_fast_mode(document)
	assert_int(limits["max_tokens"]).is_equal(220)
	assert_int(limits["max_beats"]).is_equal(1)
	assert_int(limits["say_max_length"]).is_equal(120)
	assert_int(limits["inner_max_length"]).is_equal(60)
