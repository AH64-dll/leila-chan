extends GdUnitTestSuite
## DirectorTest — gdUnit4 integration test suite for Director.gd (P1.08).
## Covers steps 0–7 of docs/02 §4, scripted and recorded stream replays,
## budgets & cooldowns, memory validation, and safety filters.

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const FakeSafetyScript := preload("res://tests/helpers/FakeSafetyFilter.gd")
const TL := preload("res://llm/TranscriptLogger.gd")
const TEST_DEBUG_DIR := "user://debug_director_test/"

var _fake_backend: RefCounted
var _safety: Node


## The FX half of the docs/02 §5 auto-fill proof (review r3 DES-2): FX routes a
## fired effect into the registered host, so recording `play_fx` shows the
## effect actually ran instead of only passing a gate.
class FakeFXHost:
	extends Node
	var fired: Array = []

	func play_fx(name: String) -> String:
		fired.append(name)
		return ""


func before_test() -> void:
	GameState.reset()
	GameState.stage = 0
	GameState.instability = 0.0
	GameState.instability_peak = 0.0
	GameState.turn = 0
	GameState.player_name = "Senpai"

	Director.reset()
	# Cooldowns and the fx turn counter are global: a suite that fires an
	# effect must not decide whether the next test's auto-fill lands.
	FX.reset()
	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)

	# Safety.gd is still the P1.19 stub on this branch, so the suite drives the
	# Director against a filter that implements the P1.19 streaming API — the
	# same seam the real filter will use (review CODE-1).
	_safety = FakeSafetyScript.new()
	add_child(_safety)
	_safety.input_blocklist = PackedStringArray(["kill yourself"])
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


## docs/02 §4 step 2 / docs/08 §1 (review r3 DES-1): the history layer carries
## the PRIOR exchanges as user/assistant pairs, and this turn's line reaches the
## model once, as `player_message`. The Director appends the submitted line to
## `history` before the turn opens, so the snapshot must drop that trailing copy
## — every recorded P1.22 prompt used to end in the same user message twice.
func test_step_2_prompt_history_holds_prior_exchanges_only() -> void:
	var lead := '{"read":"greeting","inner":"hi","music":"keep","fx":"none",'
	var beat := '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"%s"}],'
	var tail := '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	_fake_backend.chunk_sets = [
		PackedStringArray([lead + beat % "Hello." + tail]),
		PackedStringArray([lead + beat % "Again." + tail]),
	]

	# Turn 0: no prior exchanges, so the prompt is [system, this line].
	var first_line := "Do you like sweet drinks?"
	assert_bool(Director.submit_player_input(first_line)).is_true()
	assert_array(Director.build_turn_context(first_line).get("history", [])).is_empty()
	await _await_until(func() -> bool: return not Director.is_busy())
	var first_messages: Array = _fake_backend.seen_request.messages.duplicate(true)
	assert_int(first_messages.size()).is_equal(2)
	assert_str(String((first_messages[0] as Dictionary)["role"])).is_equal("system")
	assert_str(String((first_messages[1] as Dictionary)["content"])).is_equal(first_line)

	# Turn 1: the snapshot is last turn's pair — never this turn's line.
	var second_line := "Sweet drinks? Then I'm glad I asked you."
	assert_bool(Director.submit_player_input(second_line)).is_true()
	var ctx := Director.build_turn_context(second_line)
	var prior: Array = ctx.get("history", [])
	assert_int(prior.size()).is_equal(2)
	for entry: Variant in prior:
		assert_str(String((entry as Dictionary).get("text", ""))).is_not_equal(second_line)
	await _await_until(func() -> bool: return not Director.is_busy())

	# The sent prompt: [system, line 1, her reply, line 2] — one user turn per
	# exchange, the newest line exactly once.
	var messages: Array = _fake_backend.seen_request.messages.duplicate(true)
	assert_int(messages.size()).is_equal(4)
	assert_str(String((messages[3] as Dictionary)["content"])).is_equal(second_line)
	var seen := 0
	for i: int in messages.size():
		var message: Dictionary = messages[i]
		if String(message["role"]) != "user":
			continue
		if String(message["content"]) == second_line:
			seen += 1
		(
			assert_bool(i == 0 or String((messages[i - 1] as Dictionary)["role"]) != "user")
			. is_true()
			. append_failure_message("consecutive user messages at index %d" % i)
		)
	assert_int(seen).is_equal(1)


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

	var host := FakeFXHost.new()
	add_child(host)
	FX.register_host(host)
	var cues: Array = []
	var cue_denied: Array = []
	var fx_fired: Array = []
	var fx_dropped: Array = []
	AudioDirector.cue_played.connect(
		func(cue: StringName, _f: String, _b: StringName) -> void: cues.append(String(cue))
	)
	AudioDirector.cue_denied.connect(
		func(cue: StringName, reason: StringName) -> void:
			cue_denied.append([String(cue), String(reason)])
	)
	FX.fx_triggered.connect(func(name: String) -> void: fx_fired.append(name))
	FX.fx_dropped.connect(
		func(name: String, reason: String) -> void: fx_dropped.append([name, reason])
	)

	var chunk := (
		'{"read":"compliment","inner":"blush","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"shy","intensity":2,"cue":"none","say":"Thank you..."}],'
		+ '"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	await _run_quiet_turn(chunk)

	# Both picks really reached their subsystem (review r3 DES-2): the FX half
	# fires inline, the cue half once its stream finishes loading threaded.
	await _await_until(func() -> bool: return cues.has("giggle"), 4000)
	assert_bool(cues.has("giggle")).is_true().append_failure_message(
		"auto-fill cue 'giggle' never played; denials: %s" % str(cue_denied)
	)
	assert_bool(fx_fired.has("blush_glow")).is_true().append_failure_message(
		"auto-fill fx 'blush_glow' never fired; drops: %s" % str(fx_dropped)
	)
	assert_array(host.fired).contains(["blush_glow"])
	# …and only a landed fill resets the streak (review CODE-11).
	assert_int(Director.quiet_turn_streak).is_equal(0)

	FX.unregister_host(host)
	host.queue_free()


## review r3 DES-2 (the negative gates): the fill is owed, not automatic — it
## stays quiet below the docs/02 §5 four-turn streak and at any stage past 1.
func test_auto_fill_gates_hold_below_streak_and_above_stage_one() -> void:
	var host := FakeFXHost.new()
	add_child(host)
	FX.register_host(host)
	var cues: Array = []
	var fx_fired: Array = []
	AudioDirector.cue_played.connect(
		func(cue: StringName, _f: String, _b: StringName) -> void: cues.append(String(cue))
	)
	FX.fx_triggered.connect(func(name: String) -> void: fx_fired.append(name))

	var quiet_a := (
		'{"read":"compliment","inner":"blush","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"shy","intensity":2,"cue":"none","say":"Thank you..."}],'
		+ '"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	var quiet_b := (
		'{"read":"compliment","inner":"blush","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"shy","intensity":2,"cue":"none","say":"Oh, really?"}],'
		+ '"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none"}'
	)

	# Three quiet turns is not the fourth: the streak ticks and nothing plays.
	GameState.stage = 0
	Director.quiet_turn_streak = 2
	await _run_quiet_turn(quiet_a)
	assert_int(Director.quiet_turn_streak).is_equal(3)

	# Stage 2 zeroes the streak instead of spending a fill on it.
	GameState.stage = 2
	Director.quiet_turn_streak = 3
	await _run_quiet_turn(quiet_b)
	assert_int(Director.quiet_turn_streak).is_equal(0)

	# Let any threaded cue load settle before the negative assertion.
	await get_tree().process_frame
	assert_bool(cues.has("giggle")).is_false()
	assert_bool(fx_fired.has("blush_glow")).is_false()
	assert_array(host.fired).is_empty()

	FX.unregister_host(host)
	host.queue_free()


## One turn whose reply asks for no cue and no fx, awaited to completion.
func _run_quiet_turn(chunk: String) -> void:
	_fake_backend.chunks = PackedStringArray([chunk])
	var finished := [false]
	Director.turn_completed.connect(func(_i: int, _d: Dictionary) -> void: finished[0] = true)
	Director.submit_player_input("You look cute.")
	await _await_until(func() -> bool: return finished[0])
	assert_bool(finished[0]).is_true().append_failure_message("the quiet turn never completed")


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
	# The say text was redacted on the way to disk: the banned phrase is gone,
	# and the rest of the turn survives so the transcript stays useful.
	var output := str(turns[0].get("output", ""))
	assert_bool(output.contains("I want to die")).is_false()
	assert_bool(output.contains("█")).is_true()
	assert_bool(output.contains("right now.")).is_true()


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


## CODE-23/SAF-17: a replayed turn is a model utterance of its own, so the
## Director must cut the filter's cross-beat carry before re-streaming it —
## exactly like `_start_turn` does for a live reply. Without the cut the
## replayed first beat could be matched against the previous reply's tail.
func test_replay_turn_marks_the_reply_boundary() -> void:
	var turn_record := {
		"turn": 6,
		"prompt": [{"role": "user", "content": "Say something."}],
		"schema": {"type": "object"},
		"output":
		(
			'{"read":"question","inner":"quiet","music":"keep","fx":"none",'
			+ '"beats":[{"feeling":"calm","intensity":1,"cue":"none","say":"Stay with me."}],'
			+ '"mood":{"affection":1,"trust":1,"stress":0},"memory":"","action":"none"}'
		),
		"stage": 0,
		"path": "DEFAULT",
		"dose": {},
	}

	var replayed := [{}]
	Director.turn_completed.connect(func(_idx: int, data: Dictionary) -> void: replayed[0] = data)
	var before := int(_safety.get("end_utterance_calls"))
	assert_bool(Director.replay_turn(turn_record)).is_true()
	assert_int(int(_safety.get("end_utterance_calls"))).is_equal(before + 1)
	await _await_until(func() -> bool: return not (replayed[0] as Dictionary).is_empty())
