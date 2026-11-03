extends GdUnitTestSuite
## DirectorFallbackTest — gdUnit4 integration suite for the docs/02 §7 fallback
## dispatch in Director.gd: broken JSON, empty `say` (both stage halves), the
## repetition-loop cut, pronoun repair and early AI-break deflection.
##
## Split from res://tests/DirectorTest.gd because gdlint caps a suite at 20
## public methods.

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const TEST_DEBUG_DIR := "user://debug_director_fallback_test/"

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


func test_docs_02_section_7_broken_json_handling() -> void:
	GameState.stage = 0
	# Feed partial say before stream breaks with invalid JSON syntax
	var chunk1 := (
		'{"read":"greeting","beats":['
		+ '{"feeling":"joy","intensity":1,"cue":"none","say":"Wait, what'
	)
	var chunk2 := " BROKEN_SYNTAX_ERROR"
	_fake_backend.chunks = PackedStringArray([chunk1, chunk2])

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Hello!")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	var data: Dictionary = completed_box[0]
	assert_bool(data.is_empty()).is_false()
	var beats: Array = data.get("beats", [])
	assert_int(beats.size()).is_greater(0)
	# Fallback say contains partial say with ellipsis
	var say_text: String = str((beats[0] as Dictionary).get("say", ""))
	assert_bool(say_text.begins_with("Wait, what")).is_true()


func test_docs_02_section_7_character_break_deflection_and_meta_curiosity() -> void:
	GameState.stage = 0
	var initial_curiosity := int(GameState.profile.get("meta_curiosity", 0))

	var chunk := (
		'{"read":"question","inner":"test","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"coldness","intensity":1,"cue":"none",'
		+ '"say":"As an AI, I cannot feel love."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Do you love me?")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	var data: Dictionary = completed_box[0]
	var beats: Array = data.get("beats", [])
	var say_text: String = str((beats[0] as Dictionary).get("say", ""))
	# Replaced with deflection pool, never raw "As an AI"
	assert_bool(say_text.to_lower().contains("as an ai")).is_false()
	# Incremented meta_curiosity
	assert_int(int(GameState.profile.get("meta_curiosity", 0))).is_equal(initial_curiosity + 1)


func test_docs_02_section_7_pronoun_repair_in_director() -> void:
	GameState.stage = 0
	var chunk := (
		'{"read":"small_talk","inner":"he said so","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"angry","intensity":1,"cue":"none","say":"He is always complaining."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("I had a rough day.")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	var data: Dictionary = completed_box[0]
	var beats: Array = data.get("beats", [])
	var say_text: String = str((beats[0] as Dictionary).get("say", ""))
	# Verb agreement follows the pronoun (DES-2: was "You is always complaining.")
	assert_str(say_text).is_equal("You are always complaining.")


func test_docs_02_section_7_repetition_loop_cut_in_director() -> void:
	GameState.stage = 0
	var chunk := (
		'{"read":"small_talk","inner":"looping","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"shy","intensity":1,"cue":"none",'
		+ '"say":"I love you so much I love you so much I love you so much forever"}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Hello.")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	var data: Dictionary = completed_box[0]
	var beats: Array = data.get("beats", [])
	var say_text: String = str((beats[0] as Dictionary).get("say", ""))
	assert_str(say_text).is_equal("I love you so much")


func test_docs_02_section_7_empty_say_stage_3_fallback() -> void:
	GameState.stage = 3
	var chunk := (
		'{"read":"question","inner":"silent","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"apathy","intensity":1,"cue":"none","say":""}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Are you there?")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	var data: Dictionary = completed_box[0]
	var beats: Array = data.get("beats", [])
	var say_text: String = str((beats[0] as Dictionary).get("say", ""))
	assert_str(say_text).is_equal("…")


func test_docs_02_section_7_empty_say_stage_under_3_retries_once() -> void:
	# docs/02 §7 r2a: stage < 3 retries once at dose -2. Stage 1's table dose is
	# 2.5, so the retried request must carry 0.5 — the offset lands on the dose
	# source that won, not on a second one.
	GameState.stage = 1
	var empty_chunk := (
		'{"read":"question","inner":"silent","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"apathy","intensity":1,"cue":"none","say":""}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	var reply_chunk := (
		'{"read":"question","inner":"found it","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"nervous","intensity":1,"cue":"none","say":"Sorry, I drifted off."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	# First generation: empty say (triggers the retry). Second: a real reply.
	_fake_backend.chunk_sets = [PackedStringArray([empty_chunk]), PackedStringArray([reply_chunk])]

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Are you there?")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	# The turn did not close on the empty first generation: it was retried and
	# the second generation's say is what the player sees.
	assert_int(_fake_backend.calls).is_equal(2)
	var data: Dictionary = completed_box[0]
	var beats: Array = data.get("beats", [])
	assert_str(str((beats[0] as Dictionary).get("say", ""))).is_equal("Sorry, I drifted off.")
	# Retry dose: stage-1 table base 2.5 + (-2.0) = 0.5.
	assert_float(float(_fake_backend.seen_request.dose.get("base", -1.0))).is_equal_approx(
		0.5, 0.0001
	)


func test_docs_02_section_7_empty_say_retry_dose_never_negative() -> void:
	# Stage 0's table dose is 0.0, so the -2 retry offset must clamp out
	# entirely rather than send a negative steering dose.
	GameState.stage = 0
	var empty_chunk := (
		'{"read":"question","inner":"silent","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"apathy","intensity":1,"cue":"none","say":""}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	var reply_chunk := (
		'{"read":"question","inner":"found it","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"nervous","intensity":1,"cue":"none","say":"Still here."}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunk_sets = [PackedStringArray([empty_chunk]), PackedStringArray([reply_chunk])]

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Are you there?")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	assert_int(_fake_backend.calls).is_equal(2)
	assert_bool(float(_fake_backend.seen_request.dose.get("base", 0.0)) >= 0.0).is_true()


func test_docs_02_section_7_empty_say_stage_under_3_retries_only_once() -> void:
	# A second consecutive empty stream at stage < 3 must not retry forever:
	# it falls through to the "…" beat and the turn closes.
	GameState.stage = 0
	var empty_chunk := (
		'{"read":"question","inner":"silent","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"apathy","intensity":1,"cue":"none","say":""}],'
		+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"","action":"none"}'
	)
	# Both generations come back empty: the retry must fire exactly once.
	_fake_backend.chunk_sets = [PackedStringArray([empty_chunk]), PackedStringArray([empty_chunk])]

	var completed_box := [{}]
	Director.turn_completed.connect(
		func(_idx: int, data: Dictionary) -> void: completed_box[0] = data
	)

	Director.submit_player_input("Are you there?")
	await _await_until(func() -> bool: return not (completed_box[0] as Dictionary).is_empty())

	assert_int(_fake_backend.calls).is_equal(2)
	var data: Dictionary = completed_box[0]
	var beats: Array = data.get("beats", [])
	assert_str(str((beats[0] as Dictionary).get("say", ""))).is_equal("…")
