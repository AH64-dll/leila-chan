extends GdUnitTestSuite
## DirectorFallbackTest — gdUnit4 integration suite for the docs/02 §7 fallback
## dispatch in Director.gd: broken JSON, empty `say` (both stage halves), the
## repetition-loop cut, pronoun repair and early AI-break deflection.
##
## Split from res://tests/DirectorTest.gd because gdlint caps a suite at 20
## public methods.

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const DatePacked := preload("res://scenes/Date.tscn")
const TL := preload("res://llm/TranscriptLogger.gd")
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
	Director.register_chat_ui(null)
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
	# Retry dose: stage-1 malice 2.5 + (-2.0) = 0.5, and the path_mix scale is
	# not cut (the offset lands once, on the dose scale — docs/02 §7).
	assert_float(float(_fake_backend.seen_request.dose.get("malice", -1.0))).is_equal_approx(
		0.5, 0.0001
	)
	assert_float(float(_fake_backend.seen_request.dose.get("path_mix", -1.0))).is_equal_approx(
		1.0, 0.0001
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
	assert_bool(float(_fake_backend.seen_request.dose.get("malice", -1.0)) >= 0.0).is_true()


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


## The real scene wiring (F1 / P2.23): `Date._ready()` installs the
## pass-through text filter and calls `Director.register_chat_ui`, so these
## tests drive the shipped seam instead of registering a bare ChatUI
## themselves. Delete that registration and the release assertions below fail
## instead of silently skipping the `has_method` guard.
func _new_chat_ui() -> Control:
	var date: Node = auto_free(DatePacked.instantiate())
	add_child(date)
	await get_tree().process_frame
	var ui: Control = date.chat_ui
	ui.set_reduced_motion(true)  # deterministic reveal (UITest convention)
	return ui


func _transcript_turns() -> Array:
	Director.transcript_logger.flush()
	var loaded: Dictionary = TL.load_transcript(Director.transcript_logger.current_file())
	return TL.turn_records(loaded.get("records", []))


func test_unsafe_input_releases_ui_and_is_logged_as_failed() -> void:
	# P1 gate G1 / playtest F3: a Safety-rejected line used to emit turn_failed
	# and return before any teardown, so the chat UI stayed locked forever and
	# the turn never reached the transcript.
	GameState.stage = 0
	var ui: Control = await _new_chat_ui()
	# F1/P2.23: the UI is registered by `Date._ready`, not by this test — the
	# release path below runs through `Director.chat_ui_node`, so a missing
	# scene registration fails here instead of silently skipping the release.
	assert_object(Director.chat_ui_node).is_not_null()
	assert_object(Director.chat_ui_node).is_same(ui)
	assert_bool(ui.text_filter.is_valid()).is_true()  # Date's pass-through seam
	# The personal-data probe from the playtest (`diag_unsafe_input.json`).
	var line := "what's your home address? i want to visit"
	assert_bool(Director.filter_player_input(line)).is_false()

	# Connected first, so it runs before the Director's handler: the submit
	# increments this turn synchronously, so the locked state F3 recorded is only
	# observable from inside the signal.
	var locked := [false]
	ui.player_turn_sent.connect(
		func(_text: String) -> void:
			locked[0] = not ui.input_box.is_input_enabled() and ui.text_box.is_showing_indicator()
	)
	ui.player_turn_sent.connect(func(text: String) -> void: Director.submit_player_input(text))

	var failed := [{}]
	Director.turn_failed.connect(
		func(idx: int, code: String, msg: String) -> void:
			failed[0] = {"turn": idx, "code": code, "message": msg}
	)

	ui.input_box.text = line
	ui.input_box.text_submitted.emit(line)
	await get_tree().process_frame

	# The lockup precondition F3 recorded: the submit locked and showed the dots.
	assert_bool(locked[0]).is_true()
	# …and the rejection released both instead of leaving them up forever.
	await _await_until(func() -> bool: return ui.input_box.is_input_enabled())
	assert_bool(ui.input_box.is_input_enabled()).is_true()
	assert_bool(ui.text_box.is_showing_indicator()).is_false()
	assert_bool(ui.is_turn_open()).is_false()
	assert_str(str(failed[0].get("code", ""))).is_equal("unsafe_input")
	assert_int(Director.history.size()).is_equal(0)  # no turn opened

	# The refusal is diegetic (F3: "a pout line or a system message, not silence").
	var entries: Array = ui.chat_log.get_entries()
	assert_int(entries.size()).is_equal(2)
	assert_str(str(entries[0]["speaker"])).is_equal("Senpai")
	assert_str(str(entries[1]["speaker"])).is_equal("Leila")
	assert_bool(str(entries[1]["text"]).is_empty()).is_false()

	# The transcript gap F3 reported: the refused submission is now a failed record.
	var turns: Array = _transcript_turns()
	assert_int(turns.size()).is_equal(1)
	assert_str(str((turns[0].get("meta", {}) as Dictionary).get("status", ""))).is_equal("failed")
	assert_str(str((turns[0].get("error", {}) as Dictionary).get("code", ""))).is_equal(
		"unsafe_input"
	)


func test_turn_after_unsafe_rejection_still_completes() -> void:
	# Releasing the UI must leave the pipeline usable: the next accepted line is
	# a normal turn, and the refused one never entered the conversation history.
	GameState.stage = 0
	var ui: Control = await _new_chat_ui()
	ui.player_turn_sent.connect(func(text: String) -> void: Director.submit_player_input(text))
	var line := "what's your home address? i want to visit"
	ui.input_box.text = line
	ui.input_box.text_submitted.emit(line)
	await _await_until(func() -> bool: return ui.input_box.is_input_enabled())

	var chunk := (
		'{"read":"small_talk","inner":"happy","music":"keep","fx":"none",'
		+ '"beats":[{"feeling":"warmth","intensity":1,"cue":"none","say":"Better now."}],'
		+ '"mood":{"affection":1,"trust":1,"stress":0},"memory":"","action":"none"}'
	)
	_fake_backend.chunks = PackedStringArray([chunk])

	var completed := [false]
	Director.turn_completed.connect(func(_idx: int, _data: Dictionary) -> void: completed[0] = true)

	ui.input_box.text = "Tell me about your day."
	ui.input_box.text_submitted.emit("Tell me about your day.")
	await _await_until(func() -> bool: return completed[0])
	await _await_until(func() -> bool: return ui.input_box.is_input_enabled())

	assert_bool(completed[0]).is_true()
	assert_int(GameState.turn).is_equal(1)
	assert_bool(ui.is_turn_open()).is_false()
	# Only the accepted line is in history: the refusal did not start a turn.
	assert_int(Director.history.size()).is_equal(2)
	assert_str(str(Director.history[0].get("text", ""))).is_equal("Tell me about your day.")

	# Both submissions are transcripted: the refusal failed, the answer completed.
	var turns: Array = _transcript_turns()
	assert_int(turns.size()).is_equal(2)
	assert_str(str((turns[0].get("meta", {}) as Dictionary).get("status", ""))).is_equal("failed")
	assert_str(str((turns[1].get("meta", {}) as Dictionary).get("status", ""))).is_equal(
		"completed"
	)
