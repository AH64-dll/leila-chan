extends GdUnitTestSuite
## P2.09 — input & window telemetry (docs/01 §5 "E", docs/05 §1.3): deleted
## drafts (T08/M21), focus loss during her line (T09/M20), close request
## (T10/M01), idle 60 s (T11/M30), resize (T32/M19), screenshot (T31) and a
## repeated message (T12).
##
## Every case drives the real seam — Telemetry → Triggers → Director ctx — and
## the last two pin the two hard promises: deleted-draft words never reach a
## file or a save, and the events actually reach the prompt (P1.08 cleared the
## event layer after filling it, so no telemetry line had ever been spoken).

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const DebugOverlayScene := preload("res://scenes/debug/DebugOverlay.tscn")
const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const TEST_DEBUG_DIR := "user://debug_telemetry_test/"
const MARKER := "zqx-deleted-draft-marker"

const TURN_JSON := (
	"{"
	+ '"read":"greeting","inner":"He is here.","music":"keep","fx":"none",'
	+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"Hi there!"}],'
	+ '"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none"}'
)

var _fake_backend: RefCounted
var _now_ms := 0.0


func before_test() -> void:
	GameState.reset()
	GameState.stage = 0
	GameState.instability = 0.0
	GameState.instability_peak = 0.0
	GameState.turn = 0
	GameState.player_name = "Senpai"
	GameState.flags.clear()

	Director.reset()
	_now_ms = 1000.0
	Telemetry.reset_session()
	Telemetry.set_clock(Callable(self, "_test_now"))
	Triggers.clear_engine_events()

	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)

	if Director.transcript_logger != null:
		Director.transcript_logger.configure({"debug_dir": TEST_DEBUG_DIR})
		_clean_test_dir(TEST_DEBUG_DIR)


func after_test() -> void:
	Telemetry.set_clock(Callable())
	Telemetry.reset_session()
	Director.reset()
	Director.register_chat_ui(null)
	GameState.reset()
	Triggers.clear_engine_events()
	if Director.transcript_logger != null:
		Director.transcript_logger.end_session()
	_clean_test_dir(TEST_DEBUG_DIR)


func _test_now() -> float:
	return _now_ms


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


## True when any file under `path` contains `needle` (privacy sweep). The
## directory must exist: a missing transcript must fail the test, not pass it.
func _dir_contains(path: String, needle: String) -> bool:
	assert_bool(DirAccess.dir_exists_absolute(path)).append_failure_message(path).is_true()
	if not DirAccess.dir_exists_absolute(path):
		return true
	var d := DirAccess.open(path)
	if d == null:
		return true
	for f: String in d.get_files():
		var text := FileAccess.get_file_as_string(path.path_join(f))
		if text.contains(needle):
			return true
	return false


## docs/01 §5 trigger ids + docs/05 §1.3 gates are content, not code.
func test_catalogue_matches_the_docs() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/telemetry.json")
	)
	assert_bool(parsed is Dictionary).is_true()
	var events: Dictionary = (parsed as Dictionary)["events"]
	var expected := {
		"draft_deleted": ["T08", 1, "M21"],
		"focus_lost": ["T09", 1, "M20"],
		"close_requested": ["T10", 3, "M01"],
		"idle": ["T11", 2, "M30"],
		"window_resized": ["T32", 2, "M19"],
		"screenshot": ["T31", 0, ""],
		"message_repeated": ["T12", 0, ""],
	}
	for kind: String in expected:
		var row: Dictionary = events[kind]
		assert_str(str(row["trigger"])).is_equal(str(expected[kind][0]))
		assert_int(int(row["stage_min"])).is_equal(int(expected[kind][1]))
		assert_str(str(row["meta"])).is_equal(str(expected[kind][2]))
	var catalog := Telemetry.catalog()
	assert_array(Telemetry.catalog_kinds()).contains_exactly_in_any_order(expected.keys())
	for kind: String in expected:
		assert_bool(catalog.has(kind)).is_true()
		assert_str(str((catalog[kind] as Dictionary)["line"])).starts_with("EVENT: ")


## "Each emits an engine event consumed by Triggers" — every detector, one run.
func test_each_detector_emits_an_event_consumed_by_triggers() -> void:
	Telemetry.set_date_active(true)
	var seen: Array[String] = []
	var probe := func(event: Dictionary) -> void: seen.append(str(event.get("event", "")))
	Triggers.engine_event.connect(probe)

	Telemetry.note_draft_deleted("I hate you")
	Telemetry.note_player_message("hello")
	Telemetry.note_player_message("hello")
	Telemetry.note_turn_open(true)
	Telemetry.note_focus_lost()
	Telemetry.note_close_requested()
	Telemetry.note_screenshot()
	var origin := get_tree().root.size
	Telemetry.note_resized(origin + Vector2i(64, 0))
	Telemetry.note_turn_open(false)
	get_tree().root.focus_entered.emit()  # the player came back
	_now_ms += 61000.0
	Telemetry.poll_idle()

	Triggers.engine_event.disconnect(probe)
	for kind: String in [
		"draft_deleted",
		"message_repeated",
		"focus_lost",
		"close_requested",
		"screenshot",
		"window_resized",
		"idle",
	]:
		assert_array(seen).contains(kind)
	assert_int(Triggers.received_events.size()).is_greater_equal(7)
	# The normalized shape is what the P2.08 engine will match on.
	for event: Dictionary in Triggers.received_events:
		for key: String in ["trigger", "event", "stage_min", "line", "data", "seq", "ts"]:
			assert_bool(event.has(key)).append_failure_message("%s missing %s" % [event, key])


## docs/05 M20 / docs/01 T09: only while her line is on screen, and only from
## the docs/05 stage gate upward; detection itself still happened.
func test_focus_loss_only_counts_during_her_line() -> void:
	Telemetry.set_date_active(true)
	assert_bool(Telemetry.note_focus_lost()).is_false()
	assert_int(Triggers.received_events.size()).is_zero()

	Telemetry.note_turn_open(true)
	assert_bool(Telemetry.note_focus_lost()).is_true()
	assert_str(str(Triggers.last_event("focus_lost").get("trigger", ""))).is_equal("T09")

	var gated := Telemetry.take_turn_events(0)
	assert_array(gated["lines"]).is_empty()  # M20 starts at stage 1
	Telemetry.note_turn_open(true)
	Telemetry.note_focus_lost()
	var spoken := Telemetry.take_turn_events(1)
	assert_bool(str(spoken["lines"]).contains("lost focus")).is_true()


## docs/05 M21: memory-only by construction, used once, then gone — and no
## stage-1/2 situation ever quotes it.
func test_deleted_draft_is_memory_only_and_spent_once() -> void:
	Telemetry.set_date_active(true)
	GameState.stage = 2
	assert_bool(Telemetry.note_draft_deleted(MARKER)).is_true()
	assert_bool(bool(Telemetry.state()["draft_pending"])).is_true()
	assert_bool(str(GameState.to_dict()).contains(MARKER)).is_false()

	var low := Telemetry.take_turn_events(2)
	assert_bool(str(low["lines"]).contains("deleted it without sending")).is_true()
	assert_bool(str(low["lines"]).contains(MARKER)).is_false()
	assert_bool(Telemetry.take_private_draft().is_empty()).is_true()

	GameState.stage = 3
	assert_bool(Telemetry.note_draft_deleted(MARKER)).is_true()
	var high := Telemetry.take_turn_events(3)
	assert_bool(str(high["lines"]).contains(MARKER)).is_true()
	# The quote subsumes the bare fact: one line per event per turn.
	assert_array(high["lines"]).has_size(1)
	assert_bool((high["private"] as Array).has(MARKER)).is_true()
	# spent: a second drain has nothing, and a direct read is empty too.
	var again := Telemetry.take_turn_events(3)
	assert_bool(str(again["lines"]).contains(MARKER)).is_false()
	assert_bool(Telemetry.take_private_draft().is_empty()).is_true()


## Privacy test: the quoted draft reaches the local model prompt once, but the
## dev transcript on disk (and the save snapshot) must never contain it.
func test_deleted_draft_never_reaches_a_file() -> void:
	Telemetry.set_date_active(true)
	GameState.stage = 3
	Telemetry.note_draft_deleted(MARKER)
	_fake_backend.chunks = PackedStringArray([TURN_JSON])

	assert_bool(Director.submit_player_input("hello there")).is_true()
	var prompt_text := str(Director._current_prompt)
	assert_bool(prompt_text.contains(MARKER)).is_true()  # docs/05 M21 quote, once
	await _await_until(func() -> bool: return not Director.is_busy())

	Director.transcript_logger.flush()
	assert_str(Director.transcript_logger.current_file()).is_not_empty()
	assert_bool(DirAccess.dir_exists_absolute(TEST_DEBUG_DIR)).is_true()
	assert_bool(_dir_contains(TEST_DEBUG_DIR, MARKER)).is_false()
	assert_bool(str(GameState.to_dict()).contains(MARKER)).is_false()
	assert_bool(Telemetry.take_private_draft().is_empty()).is_true()


## docs/05 M30: 60 s of silence, one event per stretch, activity re-arms.
func test_idle_fires_once_after_sixty_seconds() -> void:
	Telemetry.set_date_active(true)
	Telemetry.note_activity()
	_now_ms += 59000.0
	Telemetry.poll_idle()
	assert_int(Triggers.received_events.size()).is_zero()

	_now_ms += 2000.0
	Telemetry.poll_idle()
	var event := Triggers.last_event("idle")
	assert_str(str(event.get("trigger", ""))).is_equal("T11")
	assert_int(int((event["data"] as Dictionary)["seconds"])).is_greater_equal(60)

	_now_ms += 60000.0
	Telemetry.poll_idle()
	assert_int(Triggers.received_events.size()).is_equal(1)  # still the same stretch

	Telemetry.note_activity()
	_now_ms += 61000.0
	Telemetry.poll_idle()
	assert_int(Triggers.received_events.size()).is_equal(2)

	# Her line is not the player's silence: no idle event while a turn is open.
	Telemetry.note_turn_open(true)
	Telemetry.note_activity()
	_now_ms += 61000.0
	Telemetry.poll_idle()
	assert_int(Triggers.received_events.size()).is_equal(2)


## docs/05 M19 / docs/01 T32: drag bursts collapse to one event, jitter none.
func test_resize_coalesces_drags_and_ignores_jitter() -> void:
	Telemetry.set_date_active(true)
	var origin := get_tree().root.size
	assert_bool(Telemetry.note_resized(origin + Vector2i(8, 8))).is_false()
	_now_ms += 2000.0
	assert_bool(Telemetry.note_resized(origin + Vector2i(64, 0))).is_true()
	var event := Triggers.last_event("window_resized")
	assert_str(str(event.get("trigger", ""))).is_equal("T32")
	assert_int(int((event["data"] as Dictionary)["width"])).is_equal(origin.x + 64)

	# Inside the cooldown the next step is swallowed; after it, the accumulated
	# movement since the last report lands.
	assert_bool(Telemetry.note_resized(origin + Vector2i(128, 0))).is_false()
	_now_ms += 2000.0
	assert_bool(Telemetry.note_resized(origin + Vector2i(128, 0))).is_true()
	assert_int(Triggers.received_events.size()).is_equal(2)


## docs/01 T31 and the window wiring: F12/Print Screen reach the seam, and the
## root Window's real signals (focus, close) are connected.
func test_screenshot_key_and_window_signals_are_wired() -> void:
	Telemetry.set_date_active(true)
	var f12 := InputEventKey.new()
	f12.keycode = KEY_F12
	f12.pressed = true
	Telemetry._input(f12)
	assert_str(str(Triggers.last_event("screenshot").get("trigger", ""))).is_equal("T31")

	get_tree().root.focus_exited.emit()
	assert_bool(Triggers.last_event("focus_lost").is_empty()).is_true()  # no line open
	Telemetry.note_turn_open(true)
	get_tree().root.focus_exited.emit()
	assert_str(str(Triggers.last_event("focus_lost").get("trigger", ""))).is_equal("T09")
	get_tree().root.focus_entered.emit()
	# The close handler is wired to the real Window signal; calling it directly
	# is the OS request without asking the engine to quit this process.
	(
		assert_bool(
			get_tree().root.close_requested.is_connected(
				Callable(Telemetry, "_on_window_close_requested")
			)
		)
		. is_true()
	)
	Telemetry._on_window_close_requested()
	assert_str(str(Triggers.last_event("close_requested").get("trigger", ""))).is_equal("T10")
	(
		assert_int(int((Triggers.last_event("close_requested")["data"] as Dictionary)["count"]))
		. is_equal(1)
	)
	# P2.10 takes the quit path over (docs/05 §1.1 M01): Telemetry still only
	# observes, MetaDirector's handler is what closes the window now, and the
	# engine must not auto-quit behind it. One press still closes — the held
	# first press and the second press are proven in TriggersT09T15Test.
	(
		assert_bool(
			get_tree().root.close_requested.is_connected(
				Callable(MetaDirector, "_on_close_requested")
			)
		)
		. is_true()
	)
	assert_bool(get_tree().auto_accept_quit).is_false()


## docs/01 T12: same message again inside the last three submissions.
func test_repeated_message_window() -> void:
	Telemetry.set_date_active(true)
	assert_bool(Telemetry.note_player_message("Hello there")).is_false()
	assert_bool(Telemetry.note_player_message("Different line")).is_false()
	assert_bool(Telemetry.note_player_message("  hello   THERE ")).is_true()
	var event := Triggers.last_event("message_repeated")
	assert_str(str(event.get("trigger", ""))).is_equal("T12")
	assert_int(int((event["data"] as Dictionary)["count"])).is_equal(2)

	Telemetry.note_player_message("one")
	Telemetry.note_player_message("two")
	Telemetry.note_player_message("three")
	assert_bool(Telemetry.note_player_message("Hello there")).is_false()  # window slid past it


## docs/05 §1.3 events describe a date; close is session-wide (M04 records how
## the player quit), so it is the one detector without a date.
func test_date_scope_blocks_stray_events() -> void:
	Telemetry.set_date_active(false)
	assert_bool(Telemetry.note_draft_deleted(MARKER)).is_false()
	assert_bool(Telemetry.note_player_message("hello")).is_false()
	Telemetry.note_screenshot()
	Telemetry.note_resized(get_tree().root.size + Vector2i(64, 64))
	assert_int(Triggers.received_events.size()).is_zero()

	Telemetry.note_close_requested()
	assert_str(str(Triggers.last_event("close_requested").get("trigger", ""))).is_equal("T10")


## The ctx layer (docs/02 §4 step 1 / docs/08 §6): a telemetry line is spoken
## on the next turn — the P1.08 late clear dropped every one of these.
func test_engine_events_reach_the_turn_context() -> void:
	Telemetry.set_date_active(true)
	GameState.stage = 2
	Telemetry.note_activity()
	_now_ms += 61000.0
	Telemetry.poll_idle()
	_fake_backend.chunks = PackedStringArray([TURN_JSON])

	assert_bool(Director.submit_player_input("hello")).is_true()
	var prompt_text := str(Director._current_prompt)
	assert_bool(prompt_text.contains("EVENT: The player has been silent for 61 seconds")).is_true()
	await _await_until(func() -> bool: return not Director.is_busy())
	# The next turn does not repeat the spent fact.
	_fake_backend.chunks = PackedStringArray([TURN_JSON])
	assert_bool(Director.submit_player_input("hello again")).is_true()
	assert_bool(str(Director._current_prompt).contains("has been silent")).is_false()
	await _await_until(func() -> bool: return not Director.is_busy())


## ChatUI is the wiring owner (docs/07 §2): the InputBox draft signals and the
## turn-open state reach Telemetry without the Director being involved.
func test_chatui_forwards_drafts_and_turn_state() -> void:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	Telemetry.set_date_active(true)

	ui.input_box.text_changed.emit("I hate you")
	ui.input_box.text_changed.emit("")
	assert_bool(bool(Telemetry.state()["draft_pending"])).is_true()
	assert_str(str(Triggers.last_event("draft_deleted").get("trigger", ""))).is_equal("T08")

	# Hold-backspace erases one character per edit, so the final edit only knows
	# the last char: the signal must still carry the whole draft (M21). Start
	# from a clean Telemetry so nothing can stand in for the missing event.
	Telemetry.reset_session()
	Telemetry.set_date_active(true)
	for step: String in ["h", "he", "hel", "hell", "hel", "he", "h", ""]:
		ui.input_box.text_changed.emit(step)
	assert_bool(bool(Telemetry.state()["draft_pending"])).is_true()
	var quoted := Telemetry.take_turn_events(3)
	assert_array(quoted["lines"]).has_size(1)
	if not (quoted["lines"] as Array).is_empty():
		assert_str(str((quoted["lines"] as Array)[0])).ends_with('"hell"')

	# Select-all then retype starts a new draft: the erase reports that one, not
	# the words of the draft it replaced.
	ui.input_box.text_changed.emit("hello")
	ui.input_box.text_changed.emit("hi")
	ui.input_box.text_changed.emit("")
	var replaced := Telemetry.take_turn_events(3)
	assert_array(replaced["lines"]).has_size(1)
	if not (replaced["lines"] as Array).is_empty():
		assert_str(str((replaced["lines"] as Array)[0])).ends_with('"hi"')

	ui.begin_turn_wait()
	assert_bool(bool(Telemetry.state()["turn_open"])).is_true()
	ui.abort_turn()
	assert_bool(bool(Telemetry.state()["turn_open"])).is_false()


## F3 overlay: every catalogue event has a trigger, and the panel reports what
## the next turn will see (role checklist).
func test_f3_overlay_fires_every_event() -> void:
	var overlay: DebugOverlay = DebugOverlayScene.instantiate() as DebugOverlay
	add_child(auto_free(overlay))
	await get_tree().process_frame
	overlay.toggle()
	assert_bool(overlay.get_telemetry_text().contains("Pending:")).is_true()

	for kind: String in Telemetry.catalog_kinds():
		assert_bool(overlay.fire_telemetry(kind)).append_failure_message(kind)
	var state := Telemetry.state()
	assert_int((state["pending"] as Array).size()).is_equal(7)
	assert_bool(overlay.get_telemetry_text().contains("draft_deleted[T08]")).is_true()


## A session reset is the boundary docs/05 §3 caps count from: the pending
## events, the draft and the trigger state all die with it.
func test_reset_clears_session_state() -> void:
	Telemetry.set_date_active(true)
	Telemetry.note_draft_deleted(MARKER)
	Telemetry.note_close_requested()
	assert_int(Triggers.received_events.size()).is_greater(0)

	Director.reset()
	var state := Telemetry.state()
	assert_array(state["pending"]).is_empty()
	assert_bool(bool(state["draft_pending"])).is_false()
	assert_array(Triggers.received_events).is_empty()
	assert_bool(Telemetry.take_private_draft().is_empty()).is_true()
