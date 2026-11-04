extends GdUnitTestSuite
## P2.19 — the night screen in the real scene graph: the new day's label, the two
## renderers the phase ships (N01's message feed, N12's ten black seconds), the
## data-driven skip window, Esc's rule, the next-day autosave, and the Date side of
## the loop (it takes the queued scenario and ends into the night).
##
## The clock is stepped with advance_time(), never the wall clock, so the suite
## cannot flake under load.

const NightPacked := preload("res://scenes/Night.tscn")
const DatePacked := preload("res://scenes/Date.tscn")
const OvernightEventsScript := preload("res://llm/OvernightEvents.gd")
const CampaignScript := preload("res://llm/Campaign.gd")
const ScenarioLoaderScript := preload("res://scenario/ScenarioLoader.gd")
const GameStateScript := preload("res://autoload/GameState.gd")
const TEST_DIR := "user://night_scene_test/"
const NEXT_SCENARIO := "res://data/scenarios/D02_cafe.json"

var _previous_dir := ""


func before_test() -> void:
	_previous_dir = SaveSystem.save_dir
	SaveSystem.save_dir = TEST_DIR
	SaveSystem.autosave_enabled = true
	SaveSystem.set_clock(func() -> int: return 1_700_000_000)
	SaveSystem.consume_pending_scene()
	Director.reset()
	GameState.reset()


func after_test() -> void:
	await get_tree().process_frame
	_remove_dir(TEST_DIR)
	SaveSystem.save_dir = _previous_dir
	SaveSystem.autosave_enabled = DisplayServer.get_name() != "headless"
	SaveSystem.set_clock(Callable())
	SaveSystem.consume_pending_scene()
	OvernightEventsScript.clear_cache()
	Director.reset()
	GameState.reset()


## A night screen that runs its night immediately and never changes scene: the
## two seams a scene test needs, set before the node enters the tree.
func _open(event_id := "") -> Control:
	var night: Control = auto_free(NightPacked.instantiate())
	night.scene_change_enabled = false
	night.auto_advance = false
	night.event_override = event_id
	add_child(night)
	night.start_night()
	return night


func test_night_screen_shows_the_new_day_and_the_first_message() -> void:
	var night: Control = _open("N01")
	assert_str(night.day_label.text).is_equal("Day 2")
	assert_str(night.night_label.text).is_equal("Night")
	# A message feed is a normal night: the day/night chrome stays on screen.
	assert_bool(night.day_label.visible).is_true()
	assert_bool(night.night_label.visible).is_true()
	# docs/01 §6.3 N01 is a 2 AM message feed: the first line lands at t=0, with
	# the timestamp the data carries.
	var lines: Array = night.visible_lines()
	assert_int(lines.size()).is_equal(1)
	assert_str(String(lines[0])).starts_with("2:07 AM")
	assert_str(String(lines[0])).contains("are you awake?")


func test_night_screen_reveals_messages_on_the_clock() -> void:
	var night: Control = _open("N01")
	night.advance_time(1.6)
	assert_int(night.visible_lines().size()).is_equal(2)
	# A large single step must run the whole timeline: the rest of the feed, the
	# hold, then the morning line and the end.
	night.advance_time(30.0)
	assert_int(night.visible_lines().size()).is_equal(4)
	assert_str(String(night.visible_lines()[3])).is_equal("good morning.")
	assert_bool(night.is_finished()).is_true()


func test_night_screen_n12_is_ten_black_seconds_then_good_morning() -> void:
	var night: Control = _open("N12")
	# docs/01 §6.3: "Nothing. A black screen for 10 seconds." The night chrome
	# steps aside for the black beat, so the screen really is empty (DES-2).
	assert_bool(night.day_label.visible).is_false()
	assert_bool(night.night_label.visible).is_false()
	assert_array(night.visible_lines()).is_empty()
	night.advance_time(9.9)
	assert_array(night.visible_lines()).is_empty()
	assert_bool(night.day_label.visible).is_false()
	night.advance_time(0.2)
	# The morning line is the new day speaking: the labels come back with it.
	assert_bool(night.day_label.visible).is_true()
	assert_bool(night.night_label.visible).is_true()
	assert_array(night.visible_lines()).is_equal(["good morning."])
	assert_bool(night.is_finished()).is_false()
	night.advance_time(5.0)
	assert_bool(night.is_finished()).is_true()


func test_night_screen_skip_window_comes_from_data() -> void:
	var night: Control = _open("N01")
	assert_bool(night.skip()).is_false()
	night.advance_time(3.0)
	assert_bool(night.skip()).is_true()
	assert_bool(night.is_finished()).is_true()
	# N12's ten seconds ARE the event: no click window, and the wait ends by itself.
	var black: Control = _open("N12")
	black.advance_time(11.0)
	assert_bool(black.skip()).is_false()
	assert_bool(black.is_finished()).is_false()


func test_night_screen_click_skips_after_the_window() -> void:
	var night: Control = _open("N01")
	# CODE-3: the screen promises "click or press Space". The full-rect root and
	# background must let the mouse through to _unhandled_input, so the click is
	# pushed through the real viewport instead of calling skip() directly.
	var early := InputEventMouseButton.new()
	early.button_index = MOUSE_BUTTON_LEFT
	early.pressed = true
	early.position = Vector2(200, 200)
	get_viewport().push_input(early)
	assert_bool(night.is_finished()).is_false()
	night.advance_time(3.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(200, 200)
	get_viewport().push_input(click)
	assert_bool(night.is_finished()).is_true()


func test_night_screen_esc_always_ends_the_night() -> void:
	var night: Control = _open("N12")
	var paused: Array = []
	night.pause_requested.connect(func() -> void: paused.append(true))
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	night._unhandled_key_input(event)
	assert_array(paused).has_size(1)
	assert_bool(night.is_finished()).is_true()


func test_night_screen_autosaves_the_next_day_and_queues_its_date() -> void:
	var night: Control = _open("N01")
	var queued := String(GameState.get_flag(&"next_scenario", ""))
	assert_str(queued).is_not_empty()
	# The merged pool ships dates and the I01 interrupt side by side: the queued
	# day must be a date (CODE-1), and it is already in the played set (CODE-2).
	var scenario: Dictionary = ScenarioLoaderScript.load_scenario(queued)
	assert_str(String(scenario.get("kind", ""))).is_equal("date")
	var played: Array = CampaignScript.new(GameState).played_ids()
	assert_bool(played.has(StringName(String(scenario.get("id", ""))))).is_true()
	var read: Dictionary = SaveSystem.slots.read("auto")
	assert_bool(bool(read.get("ok", false))).is_true()
	var payload: Dictionary = read.get("payload", {})
	var scene_data: Dictionary = payload.get("scene", {})
	assert_str(String(scene_data.get("id", ""))).is_equal(SaveSystem.SCENE_NIGHT)
	assert_str(String(scene_data.get("scenario", ""))).is_equal(queued)
	assert_int(int(scene_data.get("turn", -1))).is_zero()
	assert_int(int(payload.get("state", {}).get("day", 0))).is_equal(2)
	assert_bool(is_instance_valid(night)).is_true()


func test_night_screen_finishes_once_and_reports_the_campaign_end() -> void:
	GameState.day = GameStateScript.DAY_MAX
	var night: Control = _open("N01")
	var finished: Array = []
	var completed: Array = []
	night.night_finished.connect(func(_report: Dictionary) -> void: finished.append(true))
	night.campaign_completed.connect(func(_report: Dictionary) -> void: completed.append(true))
	night.advance_time(120.0)
	assert_array(finished).has_size(1)
	assert_array(completed).has_size(1)
	assert_bool(night.is_finished()).is_true()
	# The last night has no morning to promise and no next day to queue.
	assert_str(String(GameState.get_flag(&"next_scenario", ""))).is_empty()
	assert_str(String(night.visible_lines()[night.visible_lines().size() - 1])).is_not_equal(
		"good morning."
	)


func test_date_opens_the_scenario_the_night_queued() -> void:
	GameState.set_flag(&"next_scenario", NEXT_SCENARIO)
	var date: Node2D = auto_free(DatePacked.instantiate())
	date.scene_change_enabled = false
	date.auto_start = false  # P2.22 S1-2: this test asserts the hand-off, not a date
	add_child(date)
	await get_tree().process_frame
	assert_str(String(date.scenario_path)).is_equal(NEXT_SCENARIO)
	assert_bool(GameState.flags.has("next_scenario")).is_false()
	assert_bool(CampaignScript.new(GameState).played_ids().has(&"D02_cafe")).is_true()


func test_date_ends_at_max_turns_into_the_night() -> void:
	var date: Node2D = auto_free(DatePacked.instantiate())
	date.scene_change_enabled = false
	add_child(date)
	await get_tree().process_frame
	var ended: Array = []
	date.date_ended.connect(func(reason: String) -> void: ended.append(reason))
	date._current_turn = int(date.get_scenario().get("end", {}).get("max_turns", 14))
	date.chat_ui.turn_displayed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(ended).is_equal(["max_turns_reached"])
	# The scene change is off, so the date is still the live scene and the end
	# fired exactly once.
	assert_bool(date.is_inside_tree()).is_true()
	date.chat_ui.turn_displayed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(ended).has_size(1)


## CODE-4: docs/01 §1 ends a scene on her `end_date` action as well as the turn
## cap. The action arrives on the Director's turn close, so this drives that
## callback and the displayed boundary it is read at — dropping either link ends
## the date only at max_turns, which is silent.
func test_date_ends_on_her_end_date_action() -> void:
	var date: Node2D = auto_free(DatePacked.instantiate())
	date.scene_change_enabled = false
	date.campaign_flow = false
	add_child(date)
	await get_tree().process_frame
	var ended: Array = []
	date.date_ended.connect(func(reason: String) -> void: ended.append(reason))
	date._current_turn = 7
	date._on_director_turn_completed(7, {"action": "end_date", "beats": []})
	date.chat_ui.turn_displayed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(ended).is_equal(["action_triggered"])
	assert_bool(date._date_over).is_true()


## CODE-2: Continue at a night save opens the queued date without going through
## begin_day(), so the Date must reconcile the campaign itself — the queue is
## consumed and the date is in the played set before the first turn.
func test_date_resuming_a_night_save_marks_the_queued_date_played() -> void:
	GameState.set_flag(&"next_scenario", NEXT_SCENARIO)
	var saved := SaveSystem.autosave(SaveSystem.SCENE_NIGHT, {"scenario": NEXT_SCENARIO, "turn": 0})
	assert_bool(bool(saved.get("ok", false))).is_true()
	assert_bool(bool(SaveSystem.load_from_slot("auto").get("ok", false))).is_true()
	var date: Node2D = auto_free(DatePacked.instantiate())
	date.scene_change_enabled = false
	add_child(date)
	await get_tree().process_frame
	assert_str(String(date.scenario_path)).is_equal(NEXT_SCENARIO)
	assert_bool(GameState.flags.has("next_scenario")).is_false()
	assert_bool(CampaignScript.new(GameState).played_ids().has(&"D02_cafe")).is_true()


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## P3.16 / docs/01 §7: the campaign's last night is where a run becomes an
## ending. The report carries the decision (the ending scene renders it), the
## night queues no next day, and it promises no morning.
func test_the_last_night_carries_the_runs_ending() -> void:
	(
		assert_bool(
			GameState.from_dict(
				{"day": 14, "path": "HOLLOW", "instability": 95.0, "instability_peak": 95.0}
			)
		)
		. is_true()
	)
	var reports: Array = []
	var night: Control = _open("N01")
	night.night_finished.connect(func(report: Dictionary) -> void: reports.append(report))
	night.advance_time(120.0)
	assert_int(reports.size()).is_equal(1)
	var report: Dictionary = reports[0]
	assert_bool(bool(report.get("campaign_over", false))).is_true()
	var ending: Variant = report.get("ending", {})
	assert_bool(ending is Dictionary).is_true()
	assert_str(String((ending as Dictionary).get("id", ""))).is_equal("E08")
	assert_str(String(GameState.get_flag(&"next_scenario", ""))).is_empty()
