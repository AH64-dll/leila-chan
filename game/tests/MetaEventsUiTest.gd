extends GdUnitTestSuite
## P3.09 — the parts of docs/05 §1.1–§1.2 M01–M12 that only exist on screen: the
## in-game replicas (M09/M10/M11), the fallback that keeps M12 inside the game,
## and the two lines she says out loud (M03 cold open, M08 shadow memory).
##
## Every case drives a real Date scene, so the effects meet the same ChatUI,
## opening beats and pause handler a player does. The replicas are asserted to be
## in-game `Control`s with their own buttons: docs/05 §0 rules 1–2 say a fake OS
## dialog is a drawing, never a real one.

const DatePacked := preload("res://scenes/Date.tscn")
const SCRATCH := "user://test_meta_ui/"

var _date: Node2D
var _meta: Node


func before_test() -> void:
	GameState.reset()
	Director.reset()
	PauseMenu.close()
	get_tree().paused = false
	_wipe(SCRATCH)
	SaveSystem.save_dir = SCRATCH + "saves"
	SaveSystem.shadow_path = SCRATCH + "shadow.json"
	SaveSystem.autosave_enabled = false
	_meta = MetaEventsM01.find(MetaDirector)
	assert_object(_meta).is_not_null()
	_meta.store.path = SCRATCH + "meta_state.json"
	_meta.scripted_chance = 0.0
	_meta.title_bar_available = true
	_meta.reset_session()
	_date = DatePacked.instantiate()
	_date.auto_start = false
	get_tree().root.add_child(_date)
	await get_tree().process_frame
	await _await_until(func() -> bool: return _date.is_opening_finished())
	_date.set_instant_text(true)
	await _await_until(func() -> bool: return not _date.chat_ui.is_turn_open())


func after_test() -> void:
	Director.cancel()
	PauseMenu.close()
	get_tree().paused = false
	MetaDirector.set_quit_callable(Callable())
	if _date != null and is_instance_valid(_date):
		_date.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _meta != null and is_instance_valid(_meta):
		_meta.dismiss()
		_meta.title_bar_available = true
		_meta.store.path = MetaStateM01.PATH
	Director.reset()
	GameState.reset()
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


func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _dialogs() -> Node:
	return _meta.get_node_or_null("MetaDialogsM01")


func _log_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in _date.chat_ui.chat_log.get_entries():
		out.append(str(entry.get("text", "")))
	return out


## docs/05 §1.1 M09: the crash is an in-game replica — a Control in this scene
## tree with [Wait] [Close] — and both buttons lead back into the game.
func test_m09_replica_is_in_game_and_both_buttons_return() -> void:
	_meta.fire("M09", "fake_crash")
	var dialogs := _dialogs()
	assert_object(dialogs).is_not_null()
	assert_bool(dialogs.is_showing()).is_true()
	assert_str(dialogs.current_id()).is_equal("M09")
	var labels: PackedStringArray = dialogs.button_texts()
	assert_array(labels).contains(["Wait", "Close"])
	# In this window, under the scene's own UI layer — never an OS dialog.
	assert_bool(dialogs is CanvasLayer).is_true()
	assert_object(dialogs.get_parent()).is_equal(_meta)
	assert_bool(dialogs.press("CrashWait")).is_true()
	assert_bool(dialogs.is_showing()).is_false()
	_meta.fire("M09", "fake_crash")
	assert_bool(dialogs.press("CrashClose")).is_true()
	assert_bool(dialogs.is_showing()).is_false()
	# The date is exactly where it was: input still belongs to the player.
	assert_bool(_date.chat_ui.is_turn_open()).is_false()


## docs/05 §0 rule 3 under a meta screen: the replica cannot swallow the close
## or the panic key. The first press is held, the second closes, and Esc pauses.
func test_m09_replica_does_not_take_close_or_esc_away() -> void:
	GameState.set_meter(&"instability", 55.0)  # M01's gate
	MetaDirector.note_scene("D02")
	_meta.fire("M09", "fake_crash")
	var quits := [0]
	MetaDirector.set_quit_callable(func() -> void: quits[0] += 1)
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(0)
	assert_bool(PauseMenu.is_open()).is_false()
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_true()
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_false()
	MetaDirector._on_close_requested()
	assert_int(quits[0]).is_equal(1)


## docs/05 §1.1 M10: the bar crawls to a stop below 100% while she talks, and
## [Later] always returns to the game — the screen is never a trap.
func test_m10_install_stalls_short_of_done_and_later_returns() -> void:
	_meta.fire("M10", "")
	var dialogs := _dialogs()
	assert_object(dialogs).is_not_null()
	assert_array(dialogs.button_texts()).contains(["Install", "Later"])
	assert_bool(dialogs.press("UpdateInstall")).is_true()
	dialogs.advance(30.0)
	assert_float(dialogs.progress_value()).is_greater(0.9)
	assert_float(dialogs.progress_value()).is_less(1.0)
	var stall := dialogs.find_child("UpdateStall", true, false) as Label
	assert_object(stall).is_not_null()
	assert_bool(stall.visible).is_true()
	assert_bool(dialogs.press("UpdateLater")).is_true()
	assert_bool(dialogs.is_showing()).is_false()


## docs/05 §1.1 M11: her name, then it stops on "That's not how it ends." — and
## then it leaves by itself instead of holding the date hostage.
func test_m11_credits_stop_on_her_line_then_end() -> void:
	_meta.fire("M11", "")
	var dialogs := _dialogs()
	assert_object(dialogs).is_not_null()
	assert_bool(dialogs.stop_line_shown()).is_false()
	dialogs.advance(7.0)
	assert_bool(dialogs.stop_line_shown()).is_true()
	var stop := dialogs.find_child("CreditsStop", true, false) as Label
	assert_object(stop).is_not_null()
	assert_str(stop.text).is_equal("That's not how it ends.")
	dialogs.advance(4.0)
	assert_bool(dialogs.is_showing()).is_false()


## docs/05 §1.2 M12's fallback: without a title bar the line becomes a system
## message in the chat log, so the event still reaches the player.
func test_m12_fallback_posts_the_line_to_the_chat_log() -> void:
	GameState.set_meter(&"instability", 55.0)
	Director.last_turn_data = {"beats": [{"say": "the window is mine now and so is the title"}]}
	_meta.title_bar_available = false
	var before: int = int(_date.chat_ui.chat_log.entry_count())
	_meta.fire("M12", "rename_window")
	await get_tree().process_frame
	assert_int(_date.chat_ui.chat_log.entry_count()).is_greater(before)
	var entries: Array = _date.chat_ui.chat_log.get_entries()
	var last: Dictionary = entries.back()
	assert_str(str(last.get("speaker_key", ""))).is_equal("system")
	assert_str(str(last.get("text", ""))).contains("window title")


## docs/05 §1.1 M03: the cold open is "as if she never stopped talking" — her
## line reaches the conversation, through Safety like every other line.
func test_m03_cold_open_line_reaches_the_chat() -> void:
	_meta.fire("M03", "")
	await _await_until(func() -> bool: return not _date.chat_ui.is_turn_open())
	await get_tree().process_frame
	var found := false
	for text: String in _log_texts():
		if text.contains("listening"):
			found = true
	assert_bool(found).is_true()
	# The ChatUI's own beats carried it, so the log has no player entry.
	assert_bool(_date.chat_ui.is_turn_open()).is_false()


## docs/05 §1.1 M08: a stored shadow memory is said out loud on Day 1.
func test_m08_shadow_memory_line_reaches_the_chat() -> void:
	var shadow := ShadowStore.new()
	shadow.path = SaveSystem.shadow_path
	shadow.store({"memories": ["You hate the rain."], "last_stage": 3})
	GameState.day = 1
	GameState.turn = 0
	GameState.set_meter(&"instability", 55.0)  # stage 3
	_meta.on_scene("D02")
	await _await_until(func() -> bool: return not _date.chat_ui.is_turn_open())
	await get_tree().process_frame
	var found := false
	for text: String in _log_texts():
		if text.contains("hate the rain"):
			found = true
	assert_bool(found).is_true()


func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event
