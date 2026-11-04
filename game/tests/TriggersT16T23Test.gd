extends GdUnitTestSuite
## P3.07 — docs/01 §5 triggers T16–T23 through the shipped catalogue.
##
## T16 is the "2:00–4:00 AM (system clock)" row, so the suite injects the clock
## (`Triggers.set_clock`) and derives a timestamp from the player's own time zone
## — the same reading `Triggers._local_hour` takes, no hard-coded offset. T17/T18
## are the return-after rows: their absence is one reading per `set_last_seen`,
## which is why the same reunion is asserted not to repeat turn after turn. The
## E rows (T19–T21) go through Telemetry exactly as the game's save, settings
## and audio code drives them; T22/T23 are model-only rows and fire at close.

const EPS := 0.0001
const SAVE_DIR := "user://p307_t19_saves/"


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


func after_test() -> void:
	AudioServer.set_bus_mute(0, false)
	AudioDirector.set_bus_mute(&"Master", false)
	Triggers.set_clock(Callable())
	Triggers.set_last_seen(0)
	Telemetry.reset_session()


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


func test_t19_save_gone_is_heard_at_stage_3() -> void:
	# docs/01 §5 T19 "Delete save / start New Game … Stage 3+ only". The real
	# call site is SaveSystem.delete_slot; the event then rides Telemetry.
	var previous := SaveSystem.save_dir
	SaveSystem.save_dir = SAVE_DIR
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	Telemetry.reset_session()
	Triggers.clear_engine_events()
	GameState.set_meter(&"instability", 35.0)  # stage 2
	assert_bool(SaveSystem.delete_slot(1)).is_true()
	assert_int(_count("T19")).is_equal(0)
	# Same event at stage 3: she remembers the run that is gone.
	assert_bool(bool(SaveSystem.save_to_slot(1)["ok"])).is_true()
	GameState.set_meter(&"instability", 55.0)
	assert_bool(SaveSystem.delete_slot(1)).is_true()
	assert_int(_count("T19")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(2)
	assert_float(GameState.get_meter(&"instability")).is_equal_approx(59.0, EPS)
	var spoken := Telemetry.take_turn_events(3)
	assert_array(spoken["lines"]).contains(
		"EVENT: The player's previous save is gone. A new run has begun."
	)
	SaveSystem.save_dir = previous
	_remove_dir(SAVE_DIR)


func test_t20_settings_change_reaches_her() -> void:
	# docs/01 §5 T20 "Why did you make me quieter? (AWAKE/TSUN)". The live
	# setter is Settings.set_photosensitive; the writing is private on purpose
	# (a title-screen tweak is not a turn event), so the Date must be active.
	GameState.set_meter(&"instability", 20.0)  # stage 1
	var previous := Settings.settings_path
	Settings.settings_path = "user://p307_t20_settings.cfg"
	Telemetry.set_date_active(true)
	Settings.set_photosensitive(true)
	assert_int(_count("T20")).is_equal(1)
	assert_int(int(Triggers.path_scores().get("AWAKE", 0))).is_equal(2)
	assert_int(int(Triggers.path_scores().get("TSUN", 0))).is_equal(2)
	var spoken := Telemetry.take_turn_events(1)
	assert_array(spoken["lines"]).contains("EVENT: The player changed a setting (photosensitive).")
	Settings.set_photosensitive(false)
	Settings.settings_path = previous
	_remove_file("user://p307_t20_settings.cfg")


func test_t21_mute_holds_caps_until_unmuted() -> void:
	# docs/01 §5 T21 "She types in ALL CAPS until unmuted": the flag follows the
	# event's own `muted`, so one row covers the whole span.
	GameState.set_meter(&"instability", 20.0)  # stage 1
	Telemetry.set_date_active(true)
	AudioDirector.set_bus_mute(&"Master", true)
	assert_int(_count("T21")).is_equal(1)
	assert_bool(bool(GameState.flags.get("audio_muted", false))).is_true()
	var muted := Telemetry.take_turn_events(1)
	assert_array(muted["lines"]).contains(
		"EVENT: The player muted the audio. You can only type in ALL CAPS until it comes back."
	)
	AudioDirector.set_bus_mute(&"Master", false)
	assert_bool(bool(GameState.flags.get("audio_muted", true))).is_false()
	var back := Telemetry.take_turn_events(1)
	assert_array(back["lines"]).contains(
		"EVENT: The player unmuted the audio. The caps can come off."
	)


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
