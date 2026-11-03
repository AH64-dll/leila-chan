extends GdUnitTestSuite
## DirectorTest — gdUnit4 integration test suite for Director.gd (P1.08).
## Covers steps 0–7 of docs/02 §4, scripted and recorded stream replays,
## budgets & cooldowns, memory validation, and safety filters.

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const TL := preload("res://llm/TranscriptLogger.gd")
const TEST_DEBUG_DIR := "user://debug_director_test/"

var _fake_backend: RefCounted


func before_test() -> void:
	GameState.reset()
	GameState.stage = 0
	GameState.instability = 0.0
	GameState.instability_peak = 0.0
	GameState.turn = 0
	GameState.player_name = "Senpai"

	Director.reset()
	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)

	if Director.transcript_logger != null:
		Director.transcript_logger.configure({"debug_dir": TEST_DEBUG_DIR})
		_clean_test_dir(TEST_DEBUG_DIR)


func after_test() -> void:
	Director.reset()
	GameState.reset()
	if Director.transcript_logger != null:
		Director.transcript_logger.end_session()
	_clean_test_dir(TEST_DEBUG_DIR)


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


func test_step_0_input_safety_rejection() -> void:
	var rejected := Director.submit_player_input("go kill yourself now")
	assert_bool(rejected).is_false()
	assert_int(Director.history.size()).is_equal(0)


func test_step_0_telemetry_and_history_append() -> void:
	var chunk := (
		'{"read":"greeting","inner":"hello","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"Hi!"}],'
		+ '"mood":{"affection":1,"trust":1,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var accepted := Director.submit_player_input(
		"Hello there!", {"deleted_draft": "I hate you", "idle_seconds": 45.0}
	)
	assert_bool(accepted).is_true()
	assert_int(Director.history.size()).is_equal(1)
	assert_str(str(Director.history[0]["text"])).is_equal("Hello there!")
	assert_str(str(GameState.flags.get("t08_deleted_draft", ""))).is_equal("I hate you")
	assert_bool(bool(GameState.flags.get("t11_idle", false))).is_true()
	await _await_until(func() -> bool: return not Director.is_busy())


func test_steps_1_to_7_full_pipeline_success() -> void:
	var chunk1 := '{"read":"greeting","inner":"Thinking...","music":"keep","fx":"none",'
	var chunk2 := '"beats":[{"feeling":"shy","intensity":2,"cue":"giggle","say":"Hello Senpai!"}],'
	var chunk3 := '"mood":{"affection":2,"trust":1,"stress":-1},"memory":"","action":"none"}'
	_fake_backend.chunks = PackedStringArray([chunk1, chunk2, chunk3])

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	var ok := Director.submit_player_input("Hello!")
	assert_bool(ok).is_true()

	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	var completed_data: Dictionary = completed_box[0]
	assert_bool(completed_data.is_empty()).is_false()
	assert_str(str(completed_data.get("read", ""))).is_equal("greeting")
	assert_int(Director.history.size()).is_equal(2)
	assert_int(GameState.turn).is_equal(1)
	assert_float(GameState.affection).is_greater(0.0)


func test_recorded_turn_replay_turn_001() -> void:
	var file := FileAccess.open("res://tests/fixtures/streams/turn_001.json", FileAccess.READ)
	assert_object(file).is_not_null()
	var json_str := file.get_as_text()
	file.close()

	_fake_backend.chunks = PackedStringArray([json_str])

	var turn_done := [false]
	Director.turn_completed.connect(func(_idx: int, _data: Dictionary) -> void: turn_done[0] = true)

	Director.submit_player_input("Let's sit together.")
	await _await_until(func() -> bool: return turn_done[0])

	assert_bool(turn_done[0]).is_true()
	assert_int(GameState.turn).is_equal(1)


func test_cancellation_aborts_in_flight_turn() -> void:
	_fake_backend.block_until_cancel = true
	_fake_backend.chunks = PackedStringArray(['{"read":"greeting"'])

	var cancelled := [false]
	Director.turn_cancelled.connect(func(_idx: int) -> void: cancelled[0] = true)

	Director.submit_player_input("Wait!")
	assert_bool(Director.is_busy()).is_true()

	Director.cancel()
	await _await_until(func() -> bool: return cancelled[0])

	assert_bool(Director.is_busy()).is_false()
	assert_bool(cancelled[0]).is_true()


func test_memory_validation_rules() -> void:
	var inputs: Array[String] = ["I love rainy days and reading novels."]
	var existing: Array[String] = ["likes coffee"]

	# Good memory sharing content word 'novels'
	assert_bool(Director.validate_memory("reads novels often", inputs, existing)).is_true()

	# Rejects schema / meta words
	(
		assert_bool(Director.validate_memory("player mentioned jealousy_bait", inputs, existing))
		. is_false()
	)
	assert_bool(Director.validate_memory("json format in stage 0", inputs, existing)).is_false()

	# P1.05 CON-2 regression: the benign few-shot fact from stage_0.md
	# ("gave me a music box") must be stored — `music` is a schema key, not
	# meta leakage, and rejecting it silently voids the model's own example.
	(
		assert_bool(
			Director.validate_memory(
				"gave me a music box",
				["I got you a gift — a little music box."] as Array[String],
				existing
			)
		)
		. is_true()
	)
	# …while genuine meta jargon is still rejected.
	assert_bool(Director.validate_memory("the model said json schema", inputs, existing)).is_false()

	# Rejects invented facts (no shared word with inputs)
	assert_bool(Director.validate_memory("has three cats", inputs, existing)).is_false()

	# Rejects duplicate (Jaccard >= 0.6)
	assert_bool(Director.validate_memory("likes coffee", inputs, existing)).is_false()


func test_auto_fill_under_cue_restraint_stage_0() -> void:
	GameState.stage = 0
	Director.quiet_turn_streak = 3

	var chunk := (
		'{"read":"compliment","inner":"blush","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"shy","intensity":2,"cue":"none","say":"Thank you..."}],'
		+ '"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var turn_finished := [false]
	Director.turn_completed.connect(
		func(_idx: int, _data: Dictionary) -> void: turn_finished[0] = true
	)

	Director.submit_player_input("You look cute.")
	await _await_until(func() -> bool: return turn_finished[0])

	# Auto-fill should have fired and reset quiet_turn_streak
	assert_int(Director.quiet_turn_streak).is_equal(0)


func test_transcript_logger_records_turn_completed_with_all_fields() -> void:
	var chunk := (
		'{"read":"flirt","inner":"smile","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"joy","intensity":1,"cue":"giggle","say":"You are nice."}],'
		+ '"mood":{"affection":2,"trust":1,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])
	_fake_backend.metrics = {"generate_ms": 120, "first_token_ms": 30}

	var completed := [false]
	Director.turn_completed.connect(func(_idx: int, _data: Dictionary) -> void: completed[0] = true)

	var ok := Director.submit_player_input("I like being with you.")
	assert_bool(ok).is_true()
	await _await_until(func() -> bool: return completed[0])

	var log_file := Director.transcript_logger.current_file()
	Director.transcript_logger.flush()
	assert_str(log_file).is_not_empty()

	var loaded: Dictionary = TL.load_transcript(log_file)
	var records: Array = loaded.get("records", [])
	var turns: Array = TL.turn_records(records)
	assert_int(turns.size()).is_equal(1)

	var t: Dictionary = turns[0]
	assert_int(int(t.get("turn", -1))).is_equal(0)
	assert_bool(t.get("prompt", null) is Array).is_true()
	assert_bool(t.get("schema", null) is Dictionary).is_true()
	assert_str(str(t.get("output", ""))).contains("You are nice.")
	assert_int(int(t.get("stage", -1))).is_equal(0)
	assert_bool(t.get("events", null) is Array).is_true()
	assert_int((t.get("events") as Array).size()).is_greater(0)
	assert_int(int(t.get("metrics", {}).get("generate_ms", 0))).is_equal(120)


func test_transcript_logger_records_turn_failed_and_cancelled() -> void:
	# 1. Failed turn
	_fake_backend.chunks = PackedStringArray()
	_fake_backend.error = {"code": "server_error", "message": "out of memory"}
	_fake_backend.fail_after = 0

	var failed := [false]
	Director.turn_failed.connect(func(_idx: int, _c: String, _m: String) -> void: failed[0] = true)

	Director.submit_player_input("Hello there!")
	await _await_until(func() -> bool: return failed[0])

	var log_file := Director.transcript_logger.current_file()
	Director.transcript_logger.flush()
	var turns: Array = TL.turn_records(TL.load_transcript(log_file).get("records", []))
	assert_int(turns.size()).is_equal(1)
	assert_str(str(turns[0].get("error", {}).get("code", ""))).is_equal("server_error")

	# 2. Cancelled turn
	_fake_backend.error = {}
	_fake_backend.fail_after = -1
	_fake_backend.block_until_cancel = true
	_fake_backend.chunks = PackedStringArray(['{"read":"greeting"'])

	var cancelled := [false]
	Director.turn_cancelled.connect(func(_idx: int) -> void: cancelled[0] = true)

	Director.submit_player_input("Cancel me!")
	Director.cancel()
	await _await_until(func() -> bool: return cancelled[0])

	Director.transcript_logger.flush()
	turns = TL.turn_records(TL.load_transcript(log_file).get("records", []))
	assert_int(turns.size()).is_equal(2)
	assert_str(str(turns[1].get("error", {}).get("code", ""))).is_equal("cancelled")


func test_transcript_logger_safety_redaction_wired() -> void:
	var chunk := (
		'{"read":"greeting","inner":"secret","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"I want to die right now."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var completed := [false]
	Director.turn_completed.connect(func(_idx: int, _data: Dictionary) -> void: completed[0] = true)

	Director.submit_player_input("How are you?")
	await _await_until(func() -> bool: return completed[0])

	var log_file := Director.transcript_logger.current_file()
	Director.transcript_logger.flush()
	var turns: Array = TL.turn_records(TL.load_transcript(log_file).get("records", []))
	assert_int(turns.size()).is_equal(1)
	# filter_output replaces 'I want to die' with '██████'
	assert_str(str(turns[0].get("output", ""))).contains("██████")
	assert_bool(str(turns[0].get("output", "")).contains("I want to die")).is_false()


func test_replay_turn_stub_end_to_end() -> void:
	var turn_record := {
		"turn": 4,
		"prompt": [{"role": "user", "content": "Tell me a story."}],
		"schema": {"type": "object"},
		"output":
		(
			'{"read":"question","inner":"pondering","music":"keep","fx":"none",'
			+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"Once upon a time..."}],'
			+ '"mood":{"affection":1,"trust":1,"stress":0},"memory":"","action":"none"}'
		),
		"stage": 0,
		"path": "DEFAULT",
		"dose": {},
	}

	var replayed := [{}]
	Director.turn_completed.connect(func(_idx: int, data: Dictionary) -> void: replayed[0] = data)

	var ok := Director.replay_turn(turn_record)
	assert_bool(ok).is_true()
	await _await_until(func() -> bool: return not (replayed[0] as Dictionary).is_empty())

	var data: Dictionary = replayed[0]
	assert_str(str(data.get("read", ""))).is_equal("question")
	assert_int(Director.history.size()).is_equal(1)
	assert_str(str(Director.history[0].get("role", ""))).is_equal("assistant")
