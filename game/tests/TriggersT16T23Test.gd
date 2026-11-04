extends GdUnitTestSuite
## P3.07 — docs/01 §5 triggers T16–T23 through the shipped catalogue.
##
## T16 is the "2:00–4:00 AM (system clock)" row, so the suite injects the clock
## (`Triggers.set_clock`) and derives a timestamp from the player's own time zone
## — the same reading `Triggers._local_hour` takes, no hard-coded offset. T17/T18
## are the return-after rows: their absence is one reading per `set_last_seen`,
## which is why the same reunion is asserted not to repeat turn after turn. The
## E rows (T19–T21) go through Telemetry exactly as the game's save, settings and
## audio code drives them; T22/T23 are model-only rows and fire at close.
##
## Round 2 pins the five findings this suite can see: the T22 guard reads the
## memory she held at submit, not the fact the Director stores from the same turn
## (CODE-1); T19's New Game note survives the reset it is about and is gated on
## the ended run's stage (CODE-2); no accessibility accommodation can fire T20
## (DES-1/D20); and T23 needs an appearance word, not the bare `compliment`
## label (DES-2).

const FakeLLMBackendScript := preload("res://tests/helpers/FakeLLMBackend.gd")
const FakeSafetyScript := preload("res://tests/helpers/FakeSafetyFilter.gd")
const NewGameScene := preload("res://scenes/NewGame.tscn")

const EPS := 0.0001
const SAVE_DIR := "user://p307_t19_saves/"
const SHADOW_FILE := "user://p307_t19_shadow.json"
const SETTINGS_FILE := "user://p307_t20_settings.cfg"

var _fake_backend: RefCounted
var _safety: Node


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Memory.reset()
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)
	Telemetry.reset_session()
	AudioServer.set_bus_mute(0, false)
	# The T22 pin drives the real Director pipeline, so the suite owns its
	# backend and its safety seam exactly as DirectorTest does.
	_fake_backend = FakeLLMBackendScript.new()
	LLM.set_backend(_fake_backend)
	_safety = FakeSafetyScript.new()
	add_child(_safety)
	_safety.input_blocklist = PackedStringArray(["kill yourself"])
	Director._safety.set_filter(_safety)
	Director.reset()
	FX.reset()


func after_test() -> void:
	AudioServer.set_bus_mute(0, false)
	AudioDirector.set_bus_mute(&"Master", false)
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)
	Telemetry.reset_session()
	Director.reset()
	Director._safety.set_filter(Safety)
	if is_instance_valid(_safety):
		_safety.queue_free()
	Settings.set_photosensitive(false)
	Settings.set_preference("content_level", "")
	AudioDirector.set_bus_volume_linear(&"Master", 1.0)
	_remove_file(SETTINGS_FILE)
	_remove_file(SHADOW_FILE)
	_remove_dir(SAVE_DIR)


## Acceptance 2: the clock rows read the injected clock, not `Time` directly.
## T16 is a local-hour window (like the real 2–4 AM player), so the timestamp is
## built from the machine's own zone bias — no hard-coded offset can drift.
func test_t16_night_window_uses_the_injected_clock() -> void:
	Triggers.set_clock(func() -> float: return _unix_at_local_hour(3))
	var lines := Triggers.begin_turn("hello")
	assert_int(_count("T16")).is_equal(1)
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(3.0, EPS)
	assert_array(lines).has_size(1)
	assert_str(String(lines[0])).starts_with("EVENT: It is between 2 and 4 in the morning")
	# 4:00 is outside the half-open window, and 5 AM certainly is.
	GameState.reset()
	Triggers.clear_engine_events()
	Triggers.set_clock(func() -> float: return _unix_at_local_hour(5))
	assert_array(Triggers.begin_turn("hello")).is_empty()
	assert_int(_count("T16")).is_equal(0)


func test_t17_return_after_a_day_is_a_reunion() -> void:
	var now := int(_unix_at_local_hour(12))
	Triggers.set_clock(func() -> float: return float(now))
	Triggers.set_last_seen(now - 30 * 3600)
	var lines := Triggers.begin_turn("hello")
	assert_int(_count("T17")).is_equal(1)
	assert_int(_count("T18")).is_equal(0)
	assert_str(String(lines[0])).contains("reunion")
	# docs/01 §5 T17 has no number of its own: the reunion is the path's shape.
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(0.0, EPS)
	# One reading per load: the next turn is an ordinary turn.
	GameState.turn = 1
	assert_array(Triggers.begin_turn("hello")).is_empty()
	assert_int(_count("T17")).is_equal(1)


func test_t18_week_away_is_the_big_spike() -> void:
	var now := int(_unix_at_local_hour(12))
	Triggers.set_clock(func() -> float: return float(now))
	Triggers.set_last_seen(now - 200 * 3600)
	var lines := Triggers.begin_turn("hello")
	assert_int(_count("T18")).is_equal(1)
	# A week is past the day row's strict upper bound: no double reunion.
	assert_int(_count("T17")).is_equal(0)
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(8.0, EPS)
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("waiting in the dark")


## CODE-2: the real New Game path. `NewGame.confirm_name` seals the run, resets
## GameState/Director and only then announces it; the note used to be raised
## before those resets and dropped by every one of them, so the only reachable
## T19 never spoke. The Date's activation and the first turn must still hear it.
func test_t19_new_game_run_end_survives_the_reset() -> void:
	var previous_dir := SaveSystem.save_dir
	var previous_shadow := SaveSystem.shadow_path
	SaveSystem.save_dir = SAVE_DIR
	SaveSystem.shadow_path = SHADOW_FILE
	GameState.set_meter(&"instability", 55.0)  # stage 3
	GameState.day = 3
	GameState.turn = 12

	var scene: Control = auto_free(NewGameScene.instantiate())
	scene.scene_change_enabled = false
	add_child(scene)
	await get_tree().process_frame
	scene.name_input.text = "Ren"
	scene.confirm_name()

	# The transition has run: the new run starts at stage 0 and nothing fired on
	# the way through (the note is not lost to the reset — it is deferred).
	assert_int(GameState.stage).is_equal(0)
	assert_int(_count("T19")).is_equal(0)
	# The Date opens (`Date._ready` → set_date_active) and clears its queue.
	Telemetry.set_date_active(true)
	var first := Telemetry.take_turn_events(0)
	assert_array(first["lines"]).contains(
		"EVENT: The player's previous save is gone. A new run has begun."
	)
	# docs/01 §5 T19 "Stage 3+ only": the gate read the ENDED run's stage even
	# though this run is at 0, so the effects land on the new run.
	assert_int(_count("T19")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(2)
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(4.0, EPS)
	# One delivery: the next turn has nothing left to say.
	assert_array(Telemetry.take_turn_events(0)["lines"]).is_empty()
	SaveSystem.save_dir = previous_dir
	SaveSystem.shadow_path = previous_shadow


## The same deferral from the title: `delete_slot` is where docs/01 §5 T19's
## "Delete save" happens, and the Date's activation clears `_pending`.
func test_t19_deleted_slot_survives_the_title_to_date_transition() -> void:
	var previous := SaveSystem.save_dir
	SaveSystem.save_dir = SAVE_DIR
	GameState.set_meter(&"instability", 55.0)  # stage 3
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	Telemetry.reset_session()
	Triggers.clear_engine_events()
	assert_bool(SaveSystem.delete_slot(1)).is_true()
	# Deleting happens at the title; the date activation clears the queue, and
	# the note is not in it. It rides the first turn instead.
	Telemetry.set_date_active(true)
	assert_int(_count("T19")).is_equal(0)
	var spoken := Telemetry.take_turn_events(3)
	assert_array(spoken["lines"]).contains(
		"EVENT: The player's previous save is gone. A new run has begun."
	)
	assert_int(_count("T19")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(2)
	SaveSystem.save_dir = previous


## A run that never reached the gate is silent, even though the note survives.
func test_t19_below_the_gate_is_dropped() -> void:
	var previous := SaveSystem.save_dir
	SaveSystem.save_dir = SAVE_DIR
	GameState.set_meter(&"instability", 35.0)  # stage 2
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	Telemetry.reset_session()
	Triggers.clear_engine_events()
	assert_bool(SaveSystem.delete_slot(1)).is_true()
	Telemetry.set_date_active(true)
	assert_array(Telemetry.take_turn_events(2)["lines"]).is_empty()
	assert_int(_count("T19")).is_equal(0)
	SaveSystem.save_dir = previous


## DES-1 + D20: accessibility and safety accommodations are never player
## behaviour. Every accommodation write is silent — no AWAKE/TSUN, no line, no
## T20 — and only a preference (the full content ceiling) still reaches her.
func test_t20_preference_change_reaches_her() -> void:
	var previous := Settings.settings_path
	Settings.settings_path = SETTINGS_FILE
	Telemetry.set_date_active(true)
	for key: String in ["photosensitive", "reduced_motion", "text_speed", "volume"]:
		Settings.set_preference(key, true)
		Settings.set_preference(key, false)
	Settings.set_preference("content_level", "calmer")
	AudioDirector.set_bus_volume_linear(&"Master", 0.2)
	assert_int(_count("T20")).is_equal(0)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(0)
	assert_int(int(Triggers.path_scores().get("TSUN", 0))).is_equal(0)
	assert_array(Telemetry.take_turn_events(0)["lines"]).is_empty()
	# The Title's own switch is the write DES-1 caught firing the guilt line.
	Settings.set_photosensitive(true)
	Settings.set_photosensitive(false)
	assert_int(_count("T20")).is_equal(0)
	assert_bool(bool(GameState.flags.get("audio_muted", false))).is_false()
	# docs/01 §5 T20 "Why did you make me quieter? (AWAKE/TSUN)": a real
	# preference is still player behaviour, at Day 1 (no invented stage gate).
	assert_bool(Settings.set_preference("content_level", "full")).is_true()
	assert_int(_count("T20")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("TSUN", 0))).is_equal(2)
	var spoken := Telemetry.take_turn_events(0)
	assert_array(spoken["lines"]).contains("EVENT: The player changed a setting (content_level).")
	Settings.settings_path = previous


func test_t21_mute_holds_caps_until_unmuted() -> void:
	# docs/01 §5 T21 "She types in ALL CAPS until unmuted": the flag follows the
	# event's own `muted`, so one row covers the whole span. No invented stage
	# gate: the state is false on Day 1 too, the safe direction.
	Telemetry.set_date_active(true)
	AudioDirector.set_bus_mute(&"Master", true)
	assert_int(_count("T21")).is_equal(1)
	assert_bool(bool(GameState.flags.get("audio_muted", false))).is_true()
	var muted := Telemetry.take_turn_events(0)
	assert_array(muted["lines"]).contains(
		"EVENT: The player muted the audio. You can only type in ALL CAPS until it comes back."
	)
	AudioDirector.set_bus_mute(&"Master", false)
	assert_bool(bool(GameState.flags.get("audio_muted", true))).is_false()
	var back := Telemetry.take_turn_events(0)
	assert_array(back["lines"]).contains(
		"EVENT: The player unmuted the audio. The caps can come off."
	)


## CODE-1: the guard is measured against the memory she held at submit. The
## Director stores the turn's `memory` BEFORE it emits `turn_completed`, so a
## live read would make the fact about the gift its own evidence: the FIRST gift
## would fire "they forgot YOU" at trust −4. This test stores no fact by hand.
func test_t22_first_gift_is_not_a_repeat() -> void:
	_fake_backend.chunk_sets = [
		PackedStringArray([_turn_json("gift", "gave me a music box")]),
		PackedStringArray([_turn_json("gift", "")]),
	]
	assert_bool(Director.submit_player_input("I got you a music box")).is_true()
	await _await_until(func() -> bool: return not Director.is_busy())
	assert_int(Memory.size()).is_equal(1)  # the fact was stored…
	assert_int(_count("T22")).is_equal(0)  # …and it is not its own evidence
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(0)
	# The second gift is a repeat: now the fact predates the message.
	assert_bool(Director.submit_player_input("I brought you another music box")).is_true()
	await _await_until(func() -> bool: return not Director.is_busy())
	assert_int(_count("T22")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)


func test_t22_repeated_gift_needs_the_memory() -> void:
	# docs/01 §5 T22 "a gift she already got": model-only (M), and the guard is
	# the stored fact, not a gift-word list. Model-only halves it (docs/02 §1.2),
	# so the row authors double the intended −4 trust / +2 SPLIT / +2 HOLLOW.
	Memory.consider("gave me a music box", ["I got you a music box yesterday"])
	Triggers.begin_turn("I brought you another music box")
	GameState.turn = 1
	var lines := Triggers.close_turn("gift")
	assert_int(_count("T22")).is_equal(1)
	assert_float(GameState.get_meter(&"trust")).is_equal_approx(-4.0, EPS)
	assert_int(int(Triggers.path_scores().get("SPLIT", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("gave me a music box")
	# The same gift with an empty memory is just a gift.
	GameState.reset()
	Memory.reset()
	Triggers.clear_engine_events()
	Triggers.begin_turn("I brought you another music box")
	GameState.turn = 1
	assert_array(Triggers.close_turn("gift")).is_empty()
	assert_int(_count("T22")).is_equal(0)


func test_t23_appearance_only_compliment() -> void:
	# docs/01 §5 T23 "Compliment her appearance only": the read label is the
	# detector (M); the line asks the question the row exists for.
	Triggers.begin_turn("you look so pretty tonight")
	GameState.turn = 1
	var lines := Triggers.close_turn("compliment")
	assert_int(_count("T23")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("TSUN", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("HOLLOW", 0))).is_equal(2)
	assert_str(String(lines[0])).contains("Is your sprite all you are to them?")
	# DES-2: a compliment that is not about her looks must not accuse the player
	# of seeing only her sprite — the bare label is too broad.
	for text: String in [
		"you're so smart",
		"you are so kind",
		"you're a good listener",
		"your eyes look wrong",
	]:
		GameState.turn += 5
		Triggers.begin_turn(text)
		GameState.turn += 1
		assert_array(Triggers.close_turn("compliment")).is_empty()
	assert_int(_count("T23")).is_equal(1)


func test_t16_t23_are_the_shipped_catalogue() -> void:
	# All eight exist as rows with a name and evidence, so the suite above is
	# testing the shipped catalogue and not a fixture (the Python contract owns
	# the docs/01 §5 column checks).
	for trigger_id: String in ["T16", "T17", "T18", "T19", "T20", "T21", "T22", "T23"]:
		var row := _row(trigger_id)
		assert_bool(row.is_empty()).is_false()
		assert_str(String(row.get("name", ""))).is_not_empty()
		var detect := row.get("detect", {}) as Dictionary
		var guard := row.get("guard", {}) as Dictionary
		assert_bool(detect.is_empty() and guard.is_empty()).is_false()


## ── Harness ───────────────────────────────────────────────────────────────


## One valid Turn for the T22 pipeline test: the read label the row watches,
## the memory the Director stores, and no mood so the meters stay out of it.
func _turn_json(read: String, memory: String) -> String:
	return (
		(
			'{"read":"%s","inner":"hi","music":"keep","fx":"none",'
			+ '"beats":[{"feeling":"joy","intensity":1,"cue":"none","say":"Okay."}],'
			+ '"mood":{"affection":0,"trust":0,"stress":0},"memory":"%s","action":"none"}'
		)
		% [read, memory]
	)


func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## A unix time whose local hour is `hour` — the same reading Triggers._local_hour
## takes (docs/01 §5 T16 is the player's local 2–4 AM).
func _unix_at_local_hour(hour: int) -> float:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var utc := Time.get_unix_time_from_datetime_dict(
		{"year": 2026, "month": 1, "day": 1, "hour": hour, "minute": 0, "second": 0}
	)
	return float(utc - bias * 60)


func _row(id: String) -> Dictionary:
	TriggerEngine.clear_cache()
	return TriggerEngine.default_table()["triggers"].get(id, {}) as Dictionary


func _count(id: String) -> int:
	return int((Triggers.report()["counts"] as Dictionary).get(id, 0))


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path.trim_suffix("/"))
