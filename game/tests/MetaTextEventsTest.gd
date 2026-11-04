extends GdUnitTestSuite
## P3.10 — docs/05 §1.3 M21–M26, the logic half: the gates (`stage`, the doc's
## path condition, the once-per-turn draw), the M23/M24 rewrite rules, M26's
## display-only sabotage, and M21's ledger entry. The pixels are covered by
## MetaUIEventsTest; the scheduler/caps by MetaScriptedEventsTest.

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const ModuleScr := preload("res://llm/meta/MetaEventsM21.gd")
const TMP_DIR := "user://meta_m21_test/"
const LEDGER := TMP_DIR + "log_edits.json"
const TMP_SETTINGS := TMP_DIR + "settings.cfg"

var _snapshot := {}


func before_test() -> void:
	_snapshot = GameState.to_dict()
	GameState.reset()
	GameState.stage = 4
	GameState.path = &"YANDERE"
	GameState.turn = 3
	_remove_dir(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	MetaLogEdits.use_path(LEDGER)
	Settings.settings_path = TMP_SETTINGS
	Settings.reduced_motion = false
	Settings.photosensitive = false
	Settings.immersion = "standard"
	Settings.bus_volumes.clear()
	PauseMenu.close()
	PauseMenu.clear_sabotage()
	get_tree().paused = false


func after_test() -> void:
	await get_tree().process_frame
	PauseMenu.close()
	PauseMenu.clear_sabotage()
	get_tree().paused = false
	Settings.settings_path = Settings.PATH
	Settings.reduced_motion = false
	Settings.bus_volumes.clear()
	MetaLogEdits.use_path("")
	_remove_dir(TMP_DIR)
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _new_chat() -> Control:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	return ui


func _new_module() -> Node:
	var module: Node = ModuleScr.new()
	add_child(auto_free(module))
	module.set_seed_base(0)
	return module


## One player line and one her line: the smallest log M23 can rewrite.
func _two_line_log(ui: Control) -> void:
	ui.chat_log.append_entry("player", "Senpai", "I like you")
	ui.chat_log.append_entry("her", "Leila", "Say it again.")


## ── The catalogue this module answers to ─────────────────────────────────


func test_module_answers_only_to_the_documented_range() -> void:
	var module := _new_module()
	var ids: Array = module.debug_ids()
	assert_array(ids).contains_exactly(["M21", "M22", "M23", "M24", "M25", "M26"])
	# An id outside the range is somebody else's event, not an error.
	module.fire("M09", "fake_crash")
	assert_bool(module.state().has("applied")).is_true()


## ── M21: the deleted draft ────────────────────────────────────────────────


## The words stay in Telemetry (docs/05 §0: memory only, discarded after use);
## this module may only record that the event happened, and only from its gate.
func test_m21_is_recorded_from_its_stage_and_never_copies_the_draft() -> void:
	var module := _new_module()
	GameState.stage = 0
	module.call("_on_engine_event", {"event": "draft_deleted", "stage_min": 1})
	var seen: Array = GameState.get_flag(MetaDirector.SEEN_FLAG, [])
	assert_bool(seen.has("M21")).is_false()
	GameState.stage = 1
	module.call("_on_engine_event", {"event": "draft_deleted", "stage_min": 1})
	seen = GameState.get_flag(MetaDirector.SEEN_FLAG, [])
	assert_bool(seen.has("M21")).is_true()
	# The module's own state holds no text at all: nothing to leak.
	assert_bool(module.state().has("draft")).is_false()


## The F3 path fires the real detector, so the reviewer sees the same event the
## player produces — and the draft still lives only in Telemetry.
func test_m21_debug_fire_uses_the_detector_not_a_copy() -> void:
	var module := _new_module()
	await get_tree().process_frame
	assert_bool(module.debug_fire("M21")).is_true()
	var seen: Array = GameState.get_flag(MetaDirector.SEEN_FLAG, [])
	assert_bool(seen.has("M21")).is_true()
	assert_str(Telemetry.take_private_draft()).is_equal(Telemetry.DEBUG_DRAFT_TEXT)


## ── M22: her suggestion ───────────────────────────────────────────────────


func test_m22_her_suggestion_reaches_an_empty_box() -> void:
	var ui := await _new_chat()
	var module := _new_module()
	module.set_data({"m22": {"suggestions": ["I'll never leave you."]}})
	assert_bool(module.debug_fire("M22")).is_true()
	assert_bool(ui.mimic_active or not ui.input_box.text.is_empty()).is_true()


## A draft the player already wrote is theirs: she never types over it.
func test_m22_never_overwrites_a_draft_the_player_wrote() -> void:
	var ui := await _new_chat()
	ui.input_box.text = "something I am writing"
	var module := _new_module()
	module.set_data({"m22": {"suggestions": ["I love you."]}})
	assert_bool(module.debug_fire("M22")).is_false()
	assert_str(ui.input_box.text).is_equal("something I am writing")


## ── M23: the edited message ───────────────────────────────────────────────


func test_m23_rewrites_the_newest_player_line_but_the_entry_keeps_the_original() -> void:
	var ui := await _new_chat()
	_two_line_log(ui)
	var module := _new_module()
	assert_bool(module.debug_fire("M23")).is_true()
	# The entry still holds what the player wrote — that is the reversibility.
	var entries: Array = ui.chat_log.get_entries()
	assert_str(String(entries[0]["text"])).is_equal("I like you")
	var rows: Array = MetaLogEdits.rows()
	assert_int(rows.size()).is_equal(1)
	assert_str(String(rows[0]["meta"])).is_equal("M23")
	assert_str(String(rows[0]["original"])).is_equal("I like you")
	assert_str(String(rows[0]["edited"])).is_equal("I love you")
	assert_str(MetaLogEdits.shown("player", "I like you", 1)).is_equal("I love you")


func test_m23_shows_her_version_in_the_log_and_restores_it() -> void:
	var ui := await _new_chat()
	_two_line_log(ui)
	var module := _new_module()
	assert_bool(module.debug_fire("M23")).is_true()
	var list: Node = ui.chat_log.get("_list")
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I love you")
	assert_int(MetaLogEdits.restore_all()).is_equal(1)
	ui.chat_log.rerender()
	assert_str((list.get_child(0) as Label).text).is_equal("Senpai: I like you")


## No swap word matches → her prefix still makes the edit visible (the doc's
## "I love you where you wrote I like you" needs *something* to compare).
func test_m23_falls_back_to_her_prefix_when_no_word_matches() -> void:
	var ui := await _new_chat()
	ui.chat_log.append_entry("player", "Senpai", "I am going to bed")
	var module := _new_module()
	assert_bool(module.debug_fire("M23")).is_true()
	var rows: Array = MetaLogEdits.rows()
	assert_str(String(rows[0]["edited"])).is_equal("I love you. I am going to bed")


func test_m23_needs_a_player_line() -> void:
	var ui := await _new_chat()
	ui.chat_log.append_entry("her", "Leila", "Hello.")
	var module := _new_module()
	assert_bool(module.debug_fire("M23")).is_false()
	assert_array(MetaLogEdits.rows()).is_empty()


## ── M24: the rewritten history ────────────────────────────────────────────


func test_m24_rewrites_the_oldest_entries_and_leaves_the_recent_ones_alone() -> void:
	var ui := await _new_chat()
	for index in 6:
		var key := "player" if index % 2 == 0 else "her"
		ui.chat_log.append_entry(key, "Senpai" if key == "player" else "Leila", "line %d" % index)
	var module := _new_module()
	assert_bool(module.debug_fire("M24")).is_true()
	var rows: Array = MetaLogEdits.rows()
	assert_int(rows.size()).is_equal(4)  # the data's window
	var entries: Array = ui.chat_log.get_entries()
	assert_str(String(entries[4]["text"])).is_equal("line 4")
	assert_str(String(entries[5]["text"])).is_equal("line 5")
	var first := MetaLogEdits.shown("player", "line 0", 1)
	assert_str(first).is_equal("I'll stay with you tonight.")
	var second := MetaLogEdits.shown("her", "line 1", 1)
	assert_str(second).is_equal("You said you'd never leave. I remember it exactly.")


## "The log of an earlier scene": a log too short to be one is not rewritten,
## and a refused event never dirties the ledger.
func test_m24_needs_an_earlier_scene() -> void:
	var ui := await _new_chat()
	_two_line_log(ui)
	var module := _new_module()
	assert_bool(module.debug_fire("M24")).is_false()
	assert_array(MetaLogEdits.rows()).is_empty()


## ── M26: the settings saboteur ────────────────────────────────────────────


## docs/05 §1.3 says the slider "has moved itself up by 10%" — this build makes
## that a DISPLAY lie (D20: an accommodation, a mix or a text-speed preference is
## never changed by a meta event). The mix and settings.cfg stay untouched.
func test_m26_moves_the_slider_but_never_the_mix_or_the_store() -> void:
	Settings.set_bus_volume(&"Music", 0.5)
	PauseMenu.open_settings()
	var before := Settings.bus_volume(&"Music")
	var live := AudioDirector.bus_volume_linear(&"Music")
	var module := _new_module()
	assert_bool(module.debug_fire("M26")).is_true()
	var sliders: Dictionary = PauseMenu.get("_bus_sliders")
	var slider: HSlider = sliders.get(&"Music")
	assert_float(slider.value).is_equal_approx(0.6, 0.001)
	assert_float(Settings.bus_volume(&"Music")).is_equal(before)
	assert_float(AudioDirector.bus_volume_linear(&"Music")).is_equal(live)
	assert_dict(PauseMenu.sabotage_state()).is_not_empty()


## Touching the slider ends the lie and stores what the player actually set.
func test_m26_the_lie_dies_when_the_player_touches_the_slider() -> void:
	Settings.set_bus_volume(&"Music", 0.5)
	PauseMenu.open_settings()
	PauseMenu.show_sabotaged_bus(&"Music", 0.1)
	var sliders: Dictionary = PauseMenu.get("_bus_sliders")
	var slider: HSlider = sliders.get(&"Music")
	slider.value = 0.7
	assert_dict(PauseMenu.sabotage_state()).is_empty()
	assert_float(Settings.bus_volume(&"Music")).is_equal_approx(0.7, 0.001)


## Accessibility reads are never the target: a bus the screen does not draw is
## refused outright, and the accessibility rows are not sliders at all.
func test_m26_refuses_rows_that_are_not_exposed_audio_buses() -> void:
	PauseMenu.open_settings()
	assert_bool(PauseMenu.show_sabotaged_bus(&"text_speed", 0.1)).is_false()
	assert_bool(PauseMenu.show_sabotaged_bus(&"MusicA", 0.1)).is_false()
	assert_bool(PauseMenu.show_sabotaged_bus(&"Music", 0.0)).is_false()
	assert_bool(PauseMenu.show_sabotaged_bus(&"Music", NAN)).is_false()
	assert_dict(PauseMenu.sabotage_state()).is_empty()


## ── The scripted gates (docs/05 §1.3 + §3) ────────────────────────────────


func test_poll_respects_the_documented_stage_and_path() -> void:
	var ui := await _new_chat()
	_two_line_log(ui)
	var module := _new_module()
	module.set_data({"m23": {"stage": 4, "paths": ["SPLIT", "YANDERE"], "chance": 1.0}})
	GameState.path = &"HOLLOW"
	assert_dict(module.poll_scripted(4)).is_empty()
	GameState.path = &"YANDERE"
	assert_dict(module.poll_scripted(3)).is_empty()
	var due: Dictionary = module.poll_scripted(4)
	assert_str(String(due.get("id", ""))).is_equal("M23")
	assert_str(String(due.get("note", ""))).contains("EVENT:")


## The draw is part of the event's contract: the same seed and turn replay the
## same lie, and a zero chance never rolls it at all.
func test_poll_is_deterministic_and_never_fires_on_zero_chance() -> void:
	var ui := await _new_chat()
	_two_line_log(ui)
	var module := _new_module()
	module.set_data({"m23": {"stage": 4, "paths": [], "chance": 0.0}})
	GameState.path = &""
	assert_dict(module.poll_scripted(4)).is_empty()
	module.set_data({"m23": {"stage": 4, "paths": [], "chance": 1.0}})
	var first: Dictionary = module.poll_scripted(4).duplicate()
	var second: Dictionary = module.poll_scripted(4).duplicate()
	assert_dict(first).is_equal(second)
	assert_str(String(first.get("action", ""))).is_equal("m23")


## The host fires what was polled; the module applies it on the `fire()` hook and
## remembers it per turn, so a host that also connects the signal cannot
## double-apply.
func test_fire_applies_the_scripted_event_once_per_turn() -> void:
	var ui := await _new_chat()
	_two_line_log(ui)
	var module := _new_module()
	module.fire("M23", "m23")
	assert_int(MetaLogEdits.rows().size()).is_equal(1)
	module.fire("M23", "m23")
	assert_int(MetaLogEdits.rows().size()).is_equal(1)


func test_m26_needs_a_settings_page_the_player_has_seen() -> void:
	GameState.clear_flag(&"meta_settings_seen")
	PauseMenu.close()
	var module := _new_module()
	module.set_data({"m26": {"stage": 3, "paths": [], "chance": 1.0}})
	assert_dict(module.poll_scripted(3)).is_empty()
	PauseMenu.open_settings()
	assert_dict(module.poll_scripted(3)).is_not_empty()
