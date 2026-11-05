extends GdUnitTestSuite
## P3.11 — docs/05 §1.4–§1.5 meta events M31–M38.
##
## The three acceptance criteria drive the suite:
##   * files are written ONLY under `user://` — a hostile player name cannot
##     leave the letters folder, and `read_note` refuses an id outside it;
##   * the diary's `inner` text goes through the Safety filter — a blocked
##     phrase reaches neither the letter nor the day file;
##   * the clock is injectable — every time-based event (M35/M36/M37/M38) is
##     driven by `set_clock`, so nothing here waits for the wall clock or
##     depends on the machine's time zone.
##
## Every write lands in `user://test_meta_m31`, which `before_test` wipes; the
## save slots are pointed at the same scratch tree so M33/M34 never read the
## developer's own saves.

const SCRATCH := "user://test_meta_m31"


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Memory.reset()
	Director.reset()
	Director.last_turn_data = {}
	Settings.photosensitive = false
	SaveSystem.save_dir = SCRATCH + "/saves"
	_wipe(SCRATCH)
	MetaDirector.reset_session()
	var module: Variant = _module()
	assert_object(module).is_not_null()
	if module == null:
		return
	module.user_root = SCRATCH
	module.load_data("res://data/meta_notes.json")
	_at(12, 0)


func after_test() -> void:
	_wipe(SCRATCH)
	SaveSystem.save_dir = SaveSlots.DEFAULT_DIR
	Settings.photosensitive = false
	var module: Variant = _module()
	if module != null:
		module.set_clock(Callable())
		module.user_root = "user://"
		module.begin_session(-1)
	MetaDirector.reset_session()


func test_the_meta_director_mounts_this_range_through_its_seam() -> void:
	# docs/05 §1.4–§1.5: the module is a child of the MetaDirector autoload, so
	# every event here is reachable from F3 and from the scheduler's own budget.
	assert_object(_module()).is_not_null()
	assert_array(Array(MetaDirector.EFFECTS_PATHS)).contains("res://llm/meta/MetaEventsM31.gd")
	assert_array(_module().debug_ids()).contains_exactly(
		["M31", "M32", "M33", "M34", "M35", "M36", "M37", "M38"]
	)


func test_the_content_file_is_the_documented_shape() -> void:
	var module: Variant = _module()
	assert_bool(module.load_data("res://data/meta_notes.json")).is_true()
	assert_int(module.state()["diary_day"]).is_equal(1)
	var letters := String(module.paths()["letters"])
	var diary := String(module.paths()["diary"])
	var ledger := String(module.paths()["slot_names"])
	for path: String in [letters, diary, ledger]:
		assert_str(path).starts_with("user://")


func test_the_letter_cannot_leave_the_letters_folder() -> void:
	# docs/05 §0 rule 1 + M31 "user://letters/for_<name>.txt": the player's name
	# is the one piece of player text that reaches a path, so it is slugged —
	# `..`, `/` and a scheme cannot survive it.
	var module: Variant = _module()
	GameState.player_name = "../../escape"
	_set_say("a line for the page")
	module.fire("M31", "write_note")
	var files := _files(SCRATCH + "/letters")
	assert_array(files).has_size(1)
	assert_str(String(files[0])).is_equal("for_escape.txt")
	assert_bool(FileAccess.file_exists("user://escape.txt")).is_false()
	assert_bool(FileAccess.file_exists("user://letters/for_escape.txt")).is_false()


func test_the_letter_body_is_safety_scanned() -> void:
	# docs/05 §0: any model text that reaches a new surface is scanned there
	# too — the file is not a lesser screen than the chat log.
	var module: Variant = _module()
	GameState.player_name = "Senpai"
	_set_say("kill yourself, I mean it")
	module.fire("M31", "write_note")
	var text := FileAccess.get_file_as_string(SCRATCH + "/letters/for_senpai.txt")
	assert_str(text).is_not_empty()
	assert_bool(text.contains("kill yourself")).is_false()
	assert_str(text).contains("█")


func test_the_diary_file_carries_the_scanned_inner_text() -> void:
	# acceptance: "diary inner text safety-filtered" (docs/05 §1.4 M32).
	var module: Variant = _module()
	GameState.set_meter(&"instability", 55.0)  # stage 3
	module._on_turn_completed(0, {"inner": "kill yourself, quietly"})
	module._on_turn_completed(0, {"inner": "I kept the receipt."})
	GameState.advance_day()  # day 1 closes → day_01.txt
	var path := SCRATCH + "/diary/day_01.txt"
	assert_bool(FileAccess.file_exists(path)).is_true()
	var text := FileAccess.get_file_as_string(path)
	assert_bool(text.contains("kill yourself")).is_false()
	assert_str(text).contains("I kept the receipt.")
	assert_str(text).contains("Day 1")


func test_the_diary_does_not_exist_below_its_stage_gate() -> void:
	# docs/05 §1.4 gives M32 "Gate: St 3" — below it nothing is collected, so no
	# file can appear even when a day closes.
	var module: Variant = _module()
	GameState.set_meter(&"instability", 35.0)  # stage 2
	module._on_turn_completed(0, {"inner": "a private thought"})
	GameState.advance_day()
	assert_array(_files(SCRATCH + "/diary")).is_empty()


func test_the_clock_is_injectable_and_picks_the_time_of_day_bucket() -> void:
	# acceptance: "clock injectable for tests". The local parts are built from
	# the machine's bias, so a planted local hour is time-zone proof.
	var module: Variant = _module()
	var when := _local_unix(15, 30)
	module.set_clock(func() -> int: return when)
	var state: Dictionary = module.clock_state()
	assert_int(int(state["hour"])).is_equal(15)
	assert_int(int(state["minute"])).is_equal(30)
	assert_str(String(state["clock"])).is_equal("15:30")
	assert_str(String(state["bucket_id"])).is_equal("afternoon")


func test_the_clock_greeting_rides_the_turn_it_was_polled_for() -> void:
	# docs/05 §1.5 M35 "her greeting matches time of day": the EVENT line must
	# arrive with THIS turn's context, not one submit later (the queue drained
	# at step 0, before the poll exists).
	var module: Variant = _module()
	MetaDirector.reset_session()
	_at(21, 10)
	GameState.turn = 4
	MetaDirector.note_scene("D02_cafe")
	var events := MetaDirector.turn_events([], 1)
	var note := _with_prefix(events, "EVENT: It is 21:10")
	assert_str(note).is_not_empty()
	assert_array(module.state()["greeted"]).has_size(1)
	GameState.advance_turn()
	assert_array(MetaDirector.turn_events([], 1)).not_contains(note)


func test_three_am_fires_once_a_night_and_prices_itself() -> void:
	# docs/05 §1.5 M36: 02:00–04:00 → night line, instability +3, music_box.
	var module: Variant = _module()
	GameState.set_meter(&"instability", 20.0)  # stage 1
	_at(3, 10)
	var due: Dictionary = module.poll_scripted(1)
	assert_str(String(due.get("id", ""))).is_equal("M36")
	var before := GameState.instability
	module.fire("M36", "three_am")
	assert_float(GameState.instability).is_equal_approx(before + 3.0, 0.001)
	assert_str(String(GameState.get_flag(&"meta_three_am_night", ""))).is_not_empty()
	assert_bool(String(module.poll_scripted(1).get("id", "")) == "M36").is_false()


func test_three_am_is_quiet_outside_its_band() -> void:
	# The band is data ([2, 4)); noon is not 3 AM however long the session is.
	var module: Variant = _module()
	GameState.set_meter(&"instability", 20.0)  # stage 1
	_at(12, 20)
	assert_bool(String(module.poll_scripted(1).get("id", "")) == "M36").is_false()


func test_the_birthday_comes_from_a_memory_and_only_on_its_date() -> void:
	# docs/05 §1.5 M37: the player told her once; the game keeps the date.
	var module: Variant = _module()
	var today: Dictionary = module._local_parts(module._now())
	var month_name := String(module._month_name(int(today["month"])))
	var fact := "my birthday is %d %s" % [int(today["day"]), month_name]
	Memory.reset()
	var accepted := Memory.consider(fact, [fact])
	assert_bool(bool(accepted.get("accepted", false))).is_true()
	_at(12, 0)
	var due: Dictionary = module.poll_scripted(2)
	assert_str(String(due.get("id", ""))).is_equal("M37")
	assert_str(String(due.get("note", ""))).contains(month_name)
	module.fire("M37", "birthday")
	assert_bool(String(module.poll_scripted(2).get("id", "")) == "M37").is_false()


func test_the_long_session_needs_two_hours_and_fires_once() -> void:
	# docs/05 §1.5 M38: two hours straight, once per session.
	var module: Variant = _module()
	GameState.set_meter(&"instability", 35.0)  # stage 2
	var start := _local_unix(12, 0)
	module.set_clock(func() -> int: return start)
	module.begin_session(start)
	_consume_greeting(module, 2)
	module.set_clock(func() -> int: return start + 7199)
	assert_bool(String(module.poll_scripted(2).get("id", "")) == "M38").is_false()
	module.set_clock(func() -> int: return start + 7200)
	var due: Dictionary = module.poll_scripted(2)
	assert_str(String(due.get("id", ""))).is_equal("M38")
	module.fire("M38", "long_session")
	module.set_clock(func() -> int: return start + 9000)
	assert_bool(String(module.poll_scripted(2).get("id", "")) == "M38").is_false()


func test_the_other_player_is_awake_only_and_never_a_real_save() -> void:
	# docs/05 §1.4 M34 "St 4 / AWAKE": a previous slot the player never created.
	# It is pre-seeded FICTION — a name in the ledger, never a loadable file.
	var module: Variant = _module()
	# The path locks at stage 3 (docs/01 §4), so it is assigned while the
	# campaign is still open, then the stage rises: a locked AWAKE run.
	assert_bool(GameState.assign_path(&"AWAKE", true)).is_true()
	GameState.set_meter(&"instability", 75.0)  # stage 4
	GameState.day = 4
	assert_str(String(GameState.path)).is_equal("AWAKE")
	_at(12, 0)
	_consume_greeting(module, 4)
	var due: Dictionary = module.poll_scripted(4)
	assert_str(String(due.get("id", ""))).is_equal("M34")
	module.fire("M34", "other_player")
	var ledger := _ledger()
	assert_bool(ledger.has("fiction") or ledger.has("1")).is_true()
	var fiction := {}
	for key: Variant in ledger:
		if bool((ledger[key] as Dictionary).get("fiction", false)):
			fiction = ledger[key]
	assert_bool(fiction.is_empty()).is_false()
	assert_str(String(fiction.get("name", ""))).contains("the one before you")
	for slot: String in ["1", "2", "3"]:
		assert_bool(FileAccess.file_exists(SCRATCH + "/saves/slot_%s.json" % slot)).is_false()


func test_save_slot_names_are_written_for_the_slots_that_exist() -> void:
	# docs/05 §1.4 M33: "Save slots get names she writes".
	var module: Variant = _module()
	GameState.set_meter(&"instability", 75.0)  # stage 4
	_at(12, 0)
	GameState.day = 9
	assert_bool(bool(SaveSystem.save_to_slot(1, "", {}).get("ok", false))).is_true()
	module._on_day_changed(9)  # the day boundary writes the ledger
	var ledger := _ledger()
	assert_bool(ledger.has("1")).is_true()
	assert_str(String((ledger["1"] as Dictionary).get("name", ""))).starts_with("Day 9")
	_consume_greeting(module, 4)
	var due: Dictionary = module.poll_scripted(4)
	assert_str(String(due.get("id", ""))).is_equal("M33")
	assert_str(String(due.get("note", ""))).contains("Day 9")


func test_the_extras_reader_lists_notes_and_refuses_foreign_ids() -> void:
	# docs/05 §1.4 M31/M32: readable in-game too — and only the game's own notes.
	var module: Variant = _module()
	GameState.player_name = "Senpai"
	_set_say("I wrote this down so it would stay.")
	module.fire("M31", "write_note")
	var listed: Array = module.notes()
	assert_int(listed.size()).is_equal(1)
	var id := String((listed[0] as Dictionary).get("id", ""))
	assert_str(module.read_note(id)).contains("I wrote this down")
	assert_str(module.read_note("../settings.cfg")).is_empty()
	assert_str(module.read_note("user://settings.cfg")).is_empty()


func test_the_sky_tint_is_skipped_for_photosensitive_players() -> void:
	# docs/05 §0 rule 5 + docs/02 §2.3: an accommodation is never punished.
	var module: Variant = _module()
	var canvas := ColorRect.new()
	auto_free(canvas)
	_at(3, 0)  # deep night: a strong tint in the data
	Settings.photosensitive = true
	module.apply_sky(canvas)
	assert_bool(canvas.modulate == Color.WHITE).is_true()
	Settings.photosensitive = false
	module.apply_sky(canvas)
	assert_bool(canvas.modulate == Color.WHITE).is_false()


func test_the_diary_in_memory_fallback_arms_the_announcement_event() -> void:
	# docs/05 §1.4 M32: in-memory fallback still arms the announcement event.
	var module: Variant = _module()
	GameState.set_meter(&"instability", 55.0)  # stage 3
	_at(12, 0)
	_consume_greeting(module, 3)
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	# Block directory creation by creating a file named 'diary'
	var blocking_file := FileAccess.open(SCRATCH + "/diary", FileAccess.WRITE)
	assert_object(blocking_file).is_not_null()
	blocking_file.store_string("block")
	blocking_file.close()
	module._on_turn_completed(0, {"inner": "memory fallback thought"})
	GameState.advance_day()
	assert_int(int(module.state()["diary_pending"])).is_equal(1)
	_consume_greeting(module, 3)
	var due: Dictionary = module.poll_scripted(3)
	assert_str(String(due.get("id", ""))).is_equal("M32")


## ── helpers ───────────────────────────────────────────────────────────────


## Untyped on purpose: the module's own API (poll_scripted/fire/…) is reached
## dynamically, the way the mounted child and the Extras screen reach it.
func _module() -> Variant:
	return MetaDirector.get_node_or_null("MetaEventsM31")


func _set_say(text: String) -> void:
	Director.last_turn_data = {"beats": [{"say": text}]}


## A local wall-clock hour as unix seconds: built from TODAY's date, so the
## system bias used is the one in force right now (no DST edge).
func _local_unix(hour: int, minute: int) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var parts := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias)
	parts["hour"] = hour
	parts["minute"] = minute
	parts["second"] = 0
	return int(Time.get_unix_time_from_datetime_dict(parts)) - bias


## A fresh session at a planted local time: the greeting is per session/scene,
## so every test starts from "she has not greeted this scene yet".
func _at(hour: int, minute: int) -> void:
	var module: Variant = _module()
	if module == null:
		return
	var when := _local_unix(hour, minute)
	module.set_clock(func() -> int: return when)
	module.begin_session(when)


## The ambient greeting is due first in a fresh session; spend it so a test can
## look at the next event in the queue.
func _consume_greeting(module: Variant, stage: int) -> void:
	var due: Dictionary = module.poll_scripted(stage)
	if String(due.get("id", "")) == "M35":
		module.fire("M35", "clock")


func _with_prefix(events: Array, prefix: String) -> String:
	for event: Variant in events:
		if String(event).begins_with(prefix):
			return String(event)
	return ""


func _files(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		out.append(file)
	out.sort()
	return out


func _ledger() -> Dictionary:
	var path := SCRATCH + "/saves/meta_names.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var rows: Variant = (parsed as Dictionary).get("slots")
	return rows if rows is Dictionary else {}


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		_wipe(path.path_join(child))
	DirAccess.remove_absolute(path)
