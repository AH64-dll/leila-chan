extends GdUnitTestSuite
## P3.09 — docs/05 §1.1–§1.2 meta events M01–M12: the decisions and the
## cross-session state, without a scene. Every case walks the real module that
## `MetaDirector` mounts, so the host seam (fire/on_scene/poll_scripted) is
## exercised, not a stand-in.
##
## The state file is pointed at a scratch tree (`MetaStateM01.path`): a headless
## run must never read or write the developer's own `user://.leila/`.

const SCRATCH := "user://test_meta_m01/"

var _meta: Node


func before_test() -> void:
	GameState.reset()
	GameState.turn = 0
	Director.reset()
	Triggers.load_catalog()
	Triggers.clear_engine_events()
	MetaDirector.reset_session()
	MetaDirector.set_seed_base(7)
	MetaDirector.load_catalog()
	Settings.immersion = "standard"
	_wipe(SCRATCH)
	SaveSystem.save_dir = SCRATCH + "saves"
	SaveSystem.shadow_path = SCRATCH + "shadow.json"
	SaveSystem.autosave_enabled = true
	_meta = MetaEventsM01.find(MetaDirector)
	assert_object(_meta).is_not_null()
	_meta.store.path = SCRATCH + "meta_state.json"
	_meta.scripted_chance = 0.0
	_meta.title_bar_available = true
	_meta.clock = Callable()
	_meta.reset_session()
	_meta.dismiss()


func after_test() -> void:
	MetaDirector.set_quit_callable(Callable())
	Director.reset()
	GameState.reset()
	if _meta != null and is_instance_valid(_meta):
		_meta.dismiss()
		_meta.store.path = MetaStateM01.PATH
	_wipe(SCRATCH)


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(child)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _boot() -> Node:
	# Boot.gd's router without a scene: `initial_scene_path()` needs no tree.
	var script := load("res://scenes/Boot.gd") as Script
	return script.new()


## docs/05 §1.1 M01 + docs/05 §0 rule 3: the close is intercepted once, and the
## second press always closes — with the P3.09 module mounted, so a later effect
## cannot weaken the rule.
func test_m01_first_press_is_held_and_the_second_closes() -> void:
	GameState.set_meter(&"instability", 55.0)  # stage 3 = M01's gate
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	assert_bool(_meta.debug_fire("M01")).is_true()
	assert_int(quits[0]).is_equal(0)
	assert_bool(bool(MetaDirector.state()["close_held"])).is_true()
	assert_bool(_meta.debug_fire("M01")).is_true()
	assert_int(quits[0]).is_equal(1)


## docs/05 §1.1 M02: the marker is written *before* the quit, and the quit goes
## through the module's injected seam (a suite must not end the test run).
func test_m02_she_closed_quits_after_writing_the_marker() -> void:
	GameState.set_meter(&"instability", 75.0)  # stage 4
	var quits := [0]
	_meta.set_quit_callable(func() -> void: quits[0] += 1)
	_meta.fire("M02", "she_closes_game")
	assert_int(quits[0]).is_equal(1)
	var saved: Dictionary = _meta.store.load_state()
	assert_bool((saved["she_closed"] as Dictionary).is_empty()).is_false()
	assert_int(int(saved["she_closed"].get("at", 0))).is_greater(0)


## docs/05 §1.1 M02's next launch: the title is altered and she speaks first —
## once. Reading the title state is what shows the line, so it is consumed.
func test_m02_title_line_is_shown_once() -> void:
	# A no-op, not an invalid Callable: the M02 effect really quits, and an
	# invalid seam falls through to get_tree().quit(), which kills the runner.
	_meta.set_quit_callable(func() -> void: pass)
	_meta.fire("M02", "she_closes_game")
	var view: Dictionary = _meta.title_state()
	assert_str(str(view["line"])).is_not_empty()
	assert_str(str(view["subtitle"])).is_not_empty()
	assert_bool(bool(view["she_closed"])).is_true()
	var again: Dictionary = _meta.title_state()
	assert_str(str(again["line"])).is_empty()
	assert_bool(bool(again["she_closed"])).is_false()


## docs/05 §1.1 M03: the cold open needs a readable save at the St 2 gate, and
## Boot routes the launch without a title screen when it applies.
func test_m03_cold_open_routes_boot_only_with_a_save_at_stage_two() -> void:
	var boot := _boot()
	assert_str(boot.initial_scene_path()).is_equal("res://scenes/Title.tscn")
	boot.free()
	GameState.set_meter(&"instability", 35.0)  # stage 2
	GameState.day = 3
	GameState.turn = 2
	assert_bool(bool(SaveSystem.autosave("date")["ok"])).is_true()
	var routed := _boot()
	assert_str(routed.initial_scene_path()).is_equal("res://scenes/Date.tscn")
	routed.free()


## docs/05 §1.1 M03 is scripted: it is charged against the docs/05 §3 scene
## budget like any other meta event, and the `meta_seen` ledger keeps it once.
func test_m03_cold_open_fires_once_and_costs_the_scene_budget() -> void:
	GameState.set_meter(&"instability", 35.0)  # stage 2
	GameState.day = 3
	GameState.turn = 2
	SaveSystem.autosave("date")
	assert_bool(_meta.cold_open_requested()).is_true()
	_meta.on_scene("D02")
	assert_array(MetaDirector.events_seen()).contains("M03")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)
	GameState.turn = 3
	_meta.on_scene("D03")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)


## docs/05 §1.1 M04: the four documented ways to leave, in the priority the
## moment implies (a line in flight outranks the menu, the menu outranks the
## shortcut, a bare close is the X).
func test_m04_quit_priority_is_the_documented_order() -> void:
	assert_str(MetaEventsM01.quit_method(true, true, true)).is_equal("during_line")
	assert_str(MetaEventsM01.quit_method(false, true, true)).is_equal("button")
	assert_str(MetaEventsM01.quit_method(false, false, true)).is_equal("alt_f4")
	assert_str(MetaEventsM01.quit_method(false, false, false)).is_equal("window_x")


## docs/05 §1.1 M04/M05: one note carries the gap and the way they left, and
## M04's clause is path-specific. Both land in the `meta_seen` ledger.
func test_m04_and_m05_compose_one_path_specific_note() -> void:
	var base := 1760000000
	_meta.clock = func() -> float: return float(base)
	_meta.record_quit("alt_f4")
	assert_bool(FileAccess.file_exists(_meta.store.path)).is_true()
	_meta.clock = func() -> float: return float(base + 8 * 86400)
	_meta.reset_session()
	assert_int(int(_meta.state()["away_seconds"])).is_equal(8 * 86400)
	GameState.set_meter(&"instability", 55.0)  # stage 3
	GameState.path = &"SPLIT"
	GameState.pending_events.clear()
	_meta.on_scene("D02")
	var events: Array = GameState.pending_events
	assert_int(events.size()).is_greater(0)
	var note := String(events[0])
	assert_str(note).contains("8 days")
	assert_str(note).contains("keyboard shortcut")
	assert_str(note).contains("Part of you wants to laugh")
	assert_array(MetaDirector.events_seen()).contains("M04")
	assert_array(MetaDirector.events_seen()).contains("M05")


## docs/05 §1.1 M05: "<1 h casual, 1 day reunion, 7+ days spike ('I counted')".
func test_m05_away_buckets_follow_the_documented_gaps() -> void:
	assert_str(_meta._away_bucket(1800)).is_equal("casual")
	assert_str(_meta._away_bucket(86400)).is_equal("reunion")
	assert_str(_meta._away_bucket(8 * 86400)).is_equal("spike")
	assert_str(_meta._away_fact(30)).contains("30 seconds")
	assert_str(_meta._away_fact(8 * 86400)).contains("8 days")
	assert_str(_meta._away_fact(2 * 86400)).contains("2 days")


## docs/05 §1.1 M08: a stored shadow memory is said out loud on Day 1, once.
func test_m08_shadow_memory_fires_once_on_day_one() -> void:
	var shadow := ShadowStore.new()
	shadow.path = SaveSystem.shadow_path
	assert_bool(bool(shadow.store({"memories": ["You hate the rain."], "last_stage": 3})["ok"]))
	GameState.day = 1
	GameState.turn = 0
	GameState.set_meter(&"instability", 55.0)  # stage 3 = M08's gate
	_meta.on_scene("D02")
	assert_array(MetaDirector.events_seen()).contains("M08")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)
	GameState.turn = 0
	_meta.on_scene("D03")
	assert_int(int(MetaDirector.state()["scene_events"])).is_equal(1)


## docs/05 §1.1 M08 is Day 1 and St 3 only: no memory drop mid-run or earlier.
func test_m08_needs_day_one_and_stage_three() -> void:
	var shadow := ShadowStore.new()
	shadow.path = SaveSystem.shadow_path
	shadow.store({"memories": ["You hate the rain."], "last_stage": 4})
	GameState.turn = 0
	GameState.set_meter(&"instability", 55.0)  # stage 3
	GameState.day = 2
	_meta.on_scene("D02")
	assert_array(MetaDirector.events_seen()).not_contains("M08")
	GameState.day = 1
	GameState.set_meter(&"instability", 35.0)
	GameState.stage = 2  # a restore/debug jump: the stage only moves upward
	_meta.on_scene("D03")
	assert_array(MetaDirector.events_seen()).not_contains("M08")


## docs/05 §1.2 M12: a short line from her current `say` reaches the OS title,
## and model text passes the Safety filter first (docs/02 §8).
func test_m12_window_title_is_short_and_safety_scanned() -> void:
	GameState.set_meter(&"instability", 55.0)  # the block gate
	_meta.title_bar_available = true
	Director.last_turn_data = {
		"beats":
		[
			{
				"say":
				(
					"I keep thinking about the word schizophrenia and how your sentence "
					+ "kept going and going and never landed anywhere"
				)
			}
		]
	}
	assert_bool(_meta.debug_fire("M12")).is_true()
	var title := str(_meta.state()["last_window_title"])
	assert_str(title).is_not_empty()
	assert_int(title.length()).is_less_equal(40)
	assert_bool(title.contains("schizophrenia")).is_false()


## docs/05 §1.2 M12's documented fallback: no title bar (mobile, kiosk) keeps
## the line in the game, so the event never depends on OS chrome.
func test_m12_without_a_title_bar_keeps_the_line_in_window() -> void:
	GameState.set_meter(&"instability", 55.0)
	Director.last_turn_data = {"beats": [{"say": "stay a little longer, the window is mine now"}]}
	_meta.title_bar_available = false
	assert_bool(_meta.debug_fire("M12")).is_true()
	assert_str(str(_meta.state()["last_window_title"])).is_not_empty()


## The role checklist: every event of the wave is demonstrable from the F3
## overlay, which drives exactly this seam.
func test_every_event_has_an_f3_demo() -> void:
	var ids: Array = _meta.debug_ids()
	assert_int(ids.size()).is_equal(12)
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	_meta.set_quit_callable(func() -> void: quits[0] += 1)
	for i: int in range(1, 13):
		var id := "M%02d" % i
		assert_array(ids).contains(id)
		var before: int = int(quits[0])
		assert_bool(_meta.debug_fire(id)).is_true()
		if id == "M02":
			# M02's demo really quits (through the seam a suite can stub).
			assert_int(quits[0]).is_equal(before + 1)
		_meta.dismiss()
	assert_int(quits[0]).is_greater(0)


## PRIVACY: the state file carries exactly its documented keys and nothing else.
func test_state_file_carries_only_the_documented_keys() -> void:
	_meta.record_quit("during_line")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_meta.store.path))
	assert_bool(parsed is Dictionary).is_true()
	var doc := parsed as Dictionary
	var keys: Array = doc.keys()
	keys.sort()
	assert_array(keys).is_equal(
		["format", "last_quit", "last_seen", "session", "she_closed", "version"]
	)
	assert_str(str(doc["last_quit"].get("method", ""))).is_equal("during_line")


## A hand-edited or torn file reads as a first launch — never an error, never a
## thrown exception (the state is a memory, not a save).
func test_a_corrupt_state_file_reads_as_a_first_launch() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var file := FileAccess.open(_meta.store.path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("{not json at all")
	file.close()
	var loaded: Dictionary = _meta.store.load_state()
	assert_int(int(loaded["last_seen"])).is_equal(0)
	assert_bool((loaded["last_quit"] as Dictionary).is_empty()).is_true()
	assert_bool((loaded["she_closed"] as Dictionary).is_empty()).is_true()
