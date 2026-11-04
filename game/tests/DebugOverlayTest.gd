extends GdUnitTestSuite
## DebugOverlayTest — gdUnit4 test suite for Director overlay (F3, P1.17).
## Tests overlay initialization, visibility toggling via F3, live display of
## GameState meters, steering dose, last read/inner monologue, audio cue budget,
## FX cooldowns, offered actions, and signal reactivity.

const DebugOverlayScene := preload("res://scenes/debug/DebugOverlay.tscn")

var _overlay: DebugOverlay


func before_test() -> void:
	GameState.reset()
	GameState.stage = 0
	GameState.turn = 0
	Director.reset()
	_overlay = DebugOverlayScene.instantiate() as DebugOverlay
	add_child(_overlay)
	Director.set_debug_overlay(_overlay)


func after_test() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	Director.reset()
	GameState.reset()


func test_overlay_initialization() -> void:
	assert_object(_overlay).is_not_null()
	assert_bool(_overlay.visible).is_false()
	assert_bool(_overlay.is_open()).is_false()
	assert_int(_overlay.layer).is_equal(120)


func test_overlay_toggle() -> void:
	assert_bool(_overlay.is_open()).is_false()
	_overlay.toggle()
	assert_bool(_overlay.is_open()).is_true()
	assert_bool(_overlay.visible).is_true()
	_overlay.toggle()
	assert_bool(_overlay.is_open()).is_false()
	assert_bool(_overlay.visible).is_false()


func test_displays_gamestate_meters_and_state() -> void:
	GameState.affection = 45.0
	GameState.trust = 20.0
	GameState.instability = 30.0
	GameState.fixation = 50.0
	GameState.lucidity = 75.0
	GameState.stage = 2
	GameState.path = &"YANDERE"
	GameState.path_locked = true
	GameState.day = 3
	GameState.turn = 7

	_overlay.refresh()

	assert_bool(_overlay.get_meter_value("affection").contains("45.0")).is_true()
	assert_bool(_overlay.get_meter_value("trust").contains("20.0")).is_true()
	assert_bool(_overlay.get_meter_value("instability").contains("30.0")).is_true()
	assert_bool(_overlay.get_meter_value("fixation").contains("50.0")).is_true()
	assert_bool(_overlay.get_meter_value("lucidity").contains("75.0")).is_true()
	assert_bool(_overlay.get_stage_text().contains("2")).is_true()
	assert_bool(_overlay.get_path_text().contains("YANDERE")).is_true()
	assert_bool(_overlay.get_path_text().contains("LOCKED")).is_true()
	assert_bool(_overlay.get_day_turn_text().contains("Day: 3")).is_true()
	assert_bool(_overlay.get_day_turn_text().contains("Turn: 7")).is_true()


func test_displays_steering_dose() -> void:
	Director.last_dose = {"malice": 3.5, "path_mix": 2.0}
	_overlay.refresh()

	var dose_text := _overlay.get_dose_text()
	assert_bool(dose_text.contains("malice 3.5/12")).is_true()
	assert_bool(dose_text.contains("path_mix 2.0")).is_true()


func test_displays_the_scheduled_dose_before_the_first_turn() -> void:
	GameState.stage = 4
	Director.last_dose = {}
	_overlay.refresh()

	var dose_text := _overlay.get_dose_text()
	assert_bool(dose_text.contains("malice 6.0/12")).is_true()
	assert_bool(dose_text.contains("path_mix 4.0")).is_true()


func test_displays_last_turn_read_and_inner() -> void:
	Director.last_read = "flirt"
	Director.last_inner = "She smiles faintly, heart racing."
	_overlay.refresh()

	assert_bool(_overlay.get_last_read_text().contains("flirt")).is_true()
	assert_bool(_overlay.get_last_inner_text().contains("She smiles faintly")).is_true()


func test_displays_audio_cue_budget_and_music() -> void:
	_overlay.refresh()

	var music_text := _overlay.get_music_state_text()
	assert_bool(music_text.begins_with("Music:")).is_true()

	var budget_text := _overlay.get_cue_budget_text()
	assert_bool(budget_text.begins_with("Cue Budget:")).is_true()
	assert_bool(budget_text.contains("tokens")).is_true()


func test_displays_fx_cooldowns() -> void:
	_overlay.refresh()

	if FX != null and "IMPLEMENTED" in FX:
		for fx_name: String in FX.IMPLEMENTED:
			var status_text := _overlay.get_fx_status_text(fx_name)
			assert_bool(status_text.begins_with(fx_name)).is_true()


func test_displays_offered_actions() -> void:
	Director.last_offered_actions = ["refuse_exit", "open_curtains"]
	_overlay.refresh()

	var offers_text := _overlay.get_offered_actions_text()
	assert_bool(offers_text.contains("refuse_exit")).is_true()
	assert_bool(offers_text.contains("open_curtains")).is_true()


func test_live_updates_on_meter_changed_signal() -> void:
	assert_bool(_overlay.get_meter_value("affection").contains("0.0")).is_true()

	GameState.affection = 62.5

	assert_bool(_overlay.get_meter_value("affection").contains("62.5")).is_true()


func test_live_updates_on_turn_completed_signal() -> void:
	var turn_data: Dictionary = {
		"read": "question",
		"inner": "What does he mean by that?",
		"beats": [],
		"mood": {"affection": 1, "trust": 1, "stress": 2},
	}

	Director.turn_completed.emit(1, turn_data)

	assert_bool(_overlay.get_last_read_text().contains("question")).is_true()
	assert_bool(_overlay.get_last_inner_text().contains("What does he mean by that?")).is_true()


func test_director_toggle_debug_overlay() -> void:
	assert_bool(Director.is_debug_overlay_open()).is_false()

	Director.toggle_debug_overlay()
	assert_bool(Director.is_debug_overlay_open()).is_true()
	assert_bool(_overlay.visible).is_true()

	Director.toggle_debug_overlay()
	assert_bool(Director.is_debug_overlay_open()).is_false()
	assert_bool(_overlay.visible).is_false()


func test_f3_key_event_toggles_overlay() -> void:
	assert_bool(Director.is_debug_overlay_open()).is_false()

	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F3
	Director._unhandled_input(event)

	assert_bool(Director.is_debug_overlay_open()).is_true()

	Director._unhandled_input(event)
	assert_bool(Director.is_debug_overlay_open()).is_false()


func test_escape_key_closes_overlay() -> void:
	_overlay.visible = true
	assert_bool(_overlay.visible).is_true()

	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	_overlay._unhandled_input(event)

	assert_bool(_overlay.visible).is_false()


func test_release_feature_tag_guard() -> void:
	assert_bool(DebugOverlay.is_dev_build()).is_true()


func test_displays_corruption_plan_for_the_stage() -> void:
	# P2.06: F3 shows the docs/07 §3.4 effects the text filter will apply, with
	# the same reduced-motion/content-level inputs the ChatUI resolves.
	Settings.reduced_motion = false
	Settings.content_level = ""
	GameState.stage = 3
	_overlay.refresh()
	assert_str(_overlay.get_corruption_text()).is_equal(
		"Text FX: stage 3 · hesitate, strike, repeat, wrong_name"
	)

	Settings.reduced_motion = true
	GameState.stage = 5
	_overlay.refresh()
	assert_str(_overlay.get_corruption_text()).is_equal(
		"Text FX: stage 5 · hesitate, strike, repeat, wrong_name, redact, reverse"
	)

	Settings.reduced_motion = false
	Settings.content_level = "calmer"
	_overlay.refresh()
	assert_str(_overlay.get_corruption_text()).is_equal(
		"Text FX: stage 3 · hesitate, strike, repeat, wrong_name"
	)

	Settings.content_level = ""
	Settings.reduced_motion = false
