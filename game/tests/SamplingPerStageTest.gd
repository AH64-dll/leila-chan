extends GdUnitTestSuite
## P2.05 — docs/02 §9 sampling per stage on the wire + docs/06 §1 hardened
## schema limits.
##
## The table is data-owned (`game/data/sampling.json`). These tests prove it is
## the data (not a hard-coded copy) that decides the numbers, that the numbers
## reach the real HTTP payload for every stage 0–5, and that the 90/200
## maxLength limits the hardened decoding relies on are enforced at every stage.

const TurnContextScript := preload("res://llm/TurnContext.gd")
const TurnSchemaScript := preload("res://llm/TurnSchema.gd")
const BackendScript := preload("res://llm/backends/LlamaServerBackend.gd")
const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const FakeSafetyScript := preload("res://tests/helpers/FakeSafetyFilter.gd")

const SAMPLING_PATH := "res://data/sampling.json"
const TEST_DEBUG_DIR := "user://debug_p205_test/"
const STAGES: Array[int] = [0, 1, 2, 3, 4, 5]
const SAMPLING_COLUMNS: Array[String] = ["temperature", "top_p", "repeat_penalty"]
## docs/06 §1: the band where unhardened decoding starts emitting broken JSON.
const JSON_RISK_DOSE := 8.0
## docs/06 §3: a trigger spike adds +3..+4 on top of the stage base and the
## total clamps to 12, so base + 4 is the highest dose a stage row can reach.
const SPIKE_DOSE_MAX := 4.0
const DOSE_CLAMP_MAX := 12.0

## A turn valid at every stage: "none"/"keep" are in every gate, joy is a
## canonical feeling, and meta null is legal from 0 to 5.
const TURN_JSON := (
	'{"read":"greeting","inner":"A quiet hello.","music":"keep","fx":"none",'
	+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"Hello."}],'
	+ '"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none",'
	+ '"meta":null}'
)

var _fake_backend: RefCounted
var _safety: Node


func before_test() -> void:
	GameState.reset()
	Director.reset()
	FX.reset()
	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)

	# Same seam DirectorTest uses: the Director's safety filter is swapped for a
	# scripted one so these tests exercise the sampling path, not the filter.
	_safety = FakeSafetyScript.new()
	add_child(_safety)
	Director._safety.set_filter(_safety)

	if Director.transcript_logger != null:
		Director.transcript_logger.configure({"debug_dir": TEST_DEBUG_DIR})
		_clean_test_dir(TEST_DEBUG_DIR)


func after_test() -> void:
	Director.reset()
	Director._safety.set_filter(Safety)
	GameState.reset()
	if is_instance_valid(_safety):
		_safety.queue_free()
	if Director.transcript_logger != null:
		Director.transcript_logger.end_session()
	_clean_test_dir(TEST_DEBUG_DIR)


## Director.reset() reinstalls the real Safety filter (`Director.gd:101`), so the
## scripted seam has to be re-armed after every reset — not only in before_test,
## otherwise the loop silently exercises the real safety corpus (CODE-2).
func _reset_director() -> void:
	Director.reset()
	Director._safety.set_filter(_safety)


func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _clean_test_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d != null:
		for f: String in d.get_files():
			DirAccess.remove_absolute(path.path_join(f))
		DirAccess.remove_absolute(path)


func _sampling_document() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLING_PATH))
	assert_bool(parsed is Dictionary).is_true().append_failure_message(
		"%s must be a JSON object" % SAMPLING_PATH
	)
	if parsed is Dictionary:
		return parsed
	return {}


func _data_row(stage: int) -> Dictionary:
	var stages: Variant = _sampling_document().get("stages", {})
	if stages is Dictionary and (stages as Dictionary).get(str(stage)) is Dictionary:
		return (stages as Dictionary)[str(stage)]
	assert_bool(stages is Dictionary).is_true().append_failure_message(
		"no stage %d row in data" % stage
	)
	return {}


func _assert_sampling(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for key: String in SAMPLING_COLUMNS:
		assert_bool(expected.has(key)).is_true().append_failure_message(
			"%s data lacks %s" % [label, key]
		)
		var actual_value := float(actual.get(key, -1.0))
		var expected_value := float(expected.get(key, -2.0))
		var message := "%s %s: %s != %s" % [label, key, actual.get(key), expected.get(key)]
		assert_float(actual_value).is_equal_approx(expected_value, 0.0001).append_failure_message(
			message
		)


func _payload(backend: Variant, request: TurnRequest) -> Dictionary:
	var body: Dictionary = backend._build_body(request)
	var parsed: Variant = JSON.parse_string(JSON.stringify(body))
	assert_bool(parsed is Dictionary).is_true().append_failure_message(
		"request body must survive JSON encoding"
	)
	if parsed is Dictionary:
		return parsed
	return {}


## AC1 — the docs/02 §9 table reaches the runtime from the data file, row for
## row, and consumers cannot mutate the cached copy.
func test_sampling_table_is_loaded_from_data() -> void:
	var stages: Variant = _sampling_document().get("stages", {})
	assert_bool(stages is Dictionary).is_true()
	assert_int((stages as Dictionary).size()).is_equal(6)

	for stage: int in STAGES:
		TurnContextScript.clear_cache()
		var row := TurnContextScript.sampling_spec(stage)
		var expected := _data_row(stage)
		_assert_sampling(row, expected, "stage %d row" % stage)
		assert_float(float(row["dose"])).is_equal_approx(float(expected["dose"]), 0.0001)

	# The cached row is handed out as a copy: a consumer editing it must not
	# change what the next turn sends.
	var polluted := TurnContextScript.sampling_spec(0)
	polluted["temperature"] = 9.9
	assert_float(float(TurnContextScript.sampling_spec(0)["temperature"])).is_equal_approx(
		float(_data_row(0)["temperature"]), 0.0001
	)


## AC1 (loading proof) — a synthetic document decides the numbers, a partial row
## keeps the docs/02 §9 columns it omits, a row-less stage falls back to its
## documented row, and non-object input degrades to the in-code table.
func test_parse_sampling_is_data_driven() -> void:
	var per_stage := (
		TurnContextScript
		. parse_sampling(
			{
				"stages":
				{
					"0": {"temperature": 0.11, "top_p": 0.22, "repeat_penalty": 1.33, "dose": 1.5},
					"5": {"temperature": 0.99},
				}
			}
		)
	)
	assert_float(float(per_stage[0]["temperature"])).is_equal_approx(0.11, 0.0001)
	assert_float(float(per_stage[0]["top_p"])).is_equal_approx(0.22, 0.0001)
	assert_float(float(per_stage[0]["repeat_penalty"])).is_equal_approx(1.33, 0.0001)
	# Partial row: the file's temperature wins, the docs/02 §9 columns fill the rest.
	assert_float(float(per_stage[5]["temperature"])).is_equal_approx(0.99, 0.0001)
	assert_float(float(per_stage[5]["top_p"])).is_equal_approx(0.97, 0.0001)
	assert_float(float(per_stage[5]["repeat_penalty"])).is_equal_approx(1.18, 0.0001)
	assert_float(float(per_stage[5]["dose"])).is_equal_approx(8.0, 0.0001)
	# A stage without a row falls back to its documented row.
	assert_float(float(per_stage[2]["temperature"])).is_equal_approx(0.80, 0.0001)

	# Garbage input degrades to the in-code docs/02 §9 table.
	var broken := TurnContextScript.parse_sampling("not a document")
	for stage: int in STAGES:
		assert_float(float(broken[stage]["temperature"])).is_equal_approx(
			float(TurnContextScript.SAMPLING_FALLBACK[stage]["temperature"]), 0.0001
		)


## AC2 — per stage, the Director-built request and the HTTP body it compiles to
## carry exactly that stage's data row (and only the three sampling columns).
func test_request_payload_carries_the_stage_row() -> void:
	var backend := BackendScript.new()

	for stage: int in STAGES:
		GameState.reset()
		_reset_director()
		GameState.stage = stage
		_fake_backend.seen_request = null
		_fake_backend.chunks = PackedStringArray([TURN_JSON])

		assert_bool(Director.submit_player_input("hello stage %d" % stage)).is_true()
		await _await_until(func() -> bool: return not Director.is_busy())

		var request: TurnRequest = _fake_backend.seen_request
		assert_bool(request != null).is_true().append_failure_message(
			"stage %d sent no request" % stage
		)
		if request == null:
			continue

		var expected := _data_row(stage)
		_assert_sampling(request.sampling, expected, "stage %d request" % stage)
		assert_bool(request.sampling.has("dose")).is_false()

		var body := _payload(backend, request)
		_assert_sampling(body, expected, "stage %d payload" % stage)
		assert_bool(body.has("dose")).is_false()
		assert_int(int(body.get("max_tokens", -1))).is_equal(request.max_tokens)
		assert_bool(bool(body["chat_template_kwargs"]["enable_thinking"])).is_false()

		# The hardened string limits travel with the same payload (docs/06 §1).
		var props: Dictionary = body["response_format"]["json_schema"]["schema"]["properties"]
		assert_int(int(props["inner"]["maxLength"])).is_equal(TurnSchemaScript.INNER_MAX_LENGTH)
		var beat_props: Dictionary = props["beats"]["items"]["properties"]
		assert_int(int(beat_props["say"]["maxLength"])).is_equal(TurnSchemaScript.SAY_MAX_LENGTH)


## AC3 — every stage compiles the hardened maxLength limits into the schema.
func test_schema_carries_hardened_lengths_at_every_stage() -> void:
	for stage: int in STAGES:
		var schema := TurnSchemaScript.build_turn_schema(stage)
		var props: Dictionary = schema["properties"]
		assert_int(int(props["inner"]["maxLength"])).is_equal(90)
		var beat_props: Dictionary = props["beats"]["items"]["properties"]
		assert_int(int(beat_props["say"]["maxLength"])).is_equal(200)
		assert_int(int(props["memory"]["maxLength"])).is_equal(80)


## AC3 — the validator rejects one character past the limit at every stage and
## accepts exactly the limit (the grammar and the semantic check agree).
func test_validator_enforces_string_limits_at_every_stage() -> void:
	for stage: int in STAGES:
		var turn := _valid_turn()
		assert_array(TurnSchemaScript.validate_turn(turn, stage, [])).is_empty()

		turn["inner"] = "a".repeat(TurnSchemaScript.INNER_MAX_LENGTH)
		turn["beats"][0]["say"] = "b".repeat(TurnSchemaScript.SAY_MAX_LENGTH)
		assert_array(TurnSchemaScript.validate_turn(turn, stage, [])).is_empty()

		turn["inner"] = "a".repeat(TurnSchemaScript.INNER_MAX_LENGTH + 1)
		var inner_errs := TurnSchemaScript.validate_turn(turn, stage, [])
		(
			assert_bool(
				inner_errs.any(
					func(e: String) -> bool: return e.contains("inner exceeds maxLength")
				)
			)
			. is_true()
		)

		turn["inner"] = "ok"
		turn["beats"][0]["say"] = "b".repeat(TurnSchemaScript.SAY_MAX_LENGTH + 1)
		var say_errs := TurnSchemaScript.validate_turn(turn, stage, [])
		(
			assert_bool(
				say_errs.any(func(e: String) -> bool: return e.contains("say exceeds maxLength"))
			)
			. is_true()
		)


## docs/06 §1's recipe **as adopted** (DES-1): the block keeps the measured legs
## (say 160, temperature 0.7) recorded as measured, while the strings ship
## docs/02 §3's 90/200 and the temperatures ship docs/02 §9's ladder — so only
## the two maxLength values and the repeat_penalty floor are enforced. The floor
## is gated on the highest dose a stage can reach (base + the docs/06 §3 spike
## band, clamped to 12), not on the base alone (DES-4), and at least one row must
## be checked or the gate has gone vacuous.
func test_hardened_envelope_matches_adopted_docs_06_recipe() -> void:
	var hardened: Variant = _sampling_document().get("hardened", {})
	assert_bool(hardened is Dictionary).is_true()
	var envelope: Dictionary = hardened
	assert_int(int(envelope.get("inner_max_length", -1))).is_equal(
		TurnSchemaScript.INNER_MAX_LENGTH
	)
	assert_int(int(envelope.get("say_max_length", -1))).is_equal(TurnSchemaScript.SAY_MAX_LENGTH)
	var floor := float(envelope.get("repeat_penalty_floor", 0.0))
	assert_float(floor).is_equal_approx(1.15, 0.0001)

	# The measured legs stay recorded and are not adopted: docs/06 §1 measured say
	# 160 and temperature 0.7, docs/02 §3/§9 ship 200 and 0.75-0.95 (DCR filed).
	var measured: Variant = envelope.get("measured", {})
	assert_bool(measured is Dictionary).is_true()
	var measured_legs: Dictionary = measured
	assert_int(int(measured_legs.get("say_max_length", -1))).is_equal(160)
	assert_float(float(measured_legs.get("temperature", 0.0))).is_equal_approx(0.7, 0.0001)
	assert_bool(envelope.has("temperature")).is_false().append_failure_message(
		"the envelope must not claim the measured 0.7 as an enforced temperature"
	)

	var checked := 0
	for stage: int in STAGES:
		var row := TurnContextScript.sampling_spec(stage)
		var max_dose := minf(float(row["dose"]) + SPIKE_DOSE_MAX, DOSE_CLAMP_MAX)
		if max_dose < JSON_RISK_DOSE:
			continue
		checked += 1
		assert_bool(float(row["repeat_penalty"]) >= floor).is_true().append_failure_message(
			"stage %d reaches dose %s, needs repeat_penalty >= %s" % [stage, max_dose, floor]
		)
	assert_int(checked).is_greater(0)


func _valid_turn() -> Dictionary:
	return {
		"read": "greeting",
		"inner": "He came back.",
		"music": "keep",
		"fx": "none",
		"beats":
		[
			{"feeling": "joy", "intensity": 1, "cue": "none", "say": "Hello."},
		],
		"mood": {"affection": 0, "trust": 0, "stress": 0},
		"memory": "",
		"action": "none",
		"meta": null,
	}
