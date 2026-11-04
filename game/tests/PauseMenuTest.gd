extends GdUnitTestSuite
## P3.13 — the docs/05 §0 rule 3 panic pause. Esc is PauseMenu's `_input`, so
## it fires before any scene or meta event's `_unhandled_*` handler: the menu
## opens and the tree pauses at ANY moment, including while a meta event
## (here: M01's held close) is on screen. Esc again closes it, and the pause
## state the game was in before is restored — never force-unpaused.

const SwallowScr := preload("res://tests/helpers/SwallowInput.gd")

var _scene: Node


func before_test() -> void:
	PauseMenu.close()
	get_tree().paused = false


func after_test() -> void:
	PauseMenu.close()
	get_tree().paused = false
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null


func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


## The core rule: Esc → paused tree + visible overlay.
func test_esc_opens_the_safe_pause_and_pauses_the_tree() -> void:
	assert_bool(PauseMenu.is_open()).is_false()
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()


func test_esc_again_closes_and_restores() -> void:
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_true()
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


## An already-paused tree (scripted scene, test harness) must stay paused:
## the menu restores, it never force-resumes.
func test_the_prior_pause_state_is_restored() -> void:
	get_tree().paused = true
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_true()
	PauseMenu._input(_esc())
	assert_bool(get_tree().paused).is_true()


## Esc while a meta event owns the moment: M01's close is held (its offer
## pending) and the panic key still opens the pause — the overlay draws over
## whatever the event put on screen.
func test_esc_during_a_held_meta_close() -> void:
	var stage := int(GameState.stage)
	GameState.stage = maxi(stage, MetaDirector.close_gate())
	var held := MetaDirector.hold_close_requested()
	assert_bool(held).is_true()
	assert_bool(bool(MetaDirector.state().get("offer_open", false))).is_true()

	PauseMenu._input(_esc())

	assert_bool(PauseMenu.is_open()).is_true()
	assert_bool(get_tree().paused).is_true()
	# The event state is untouched — Esc pauses, it does not consume the hold.
	assert_bool(bool(MetaDirector.state().get("close_held", false))).is_true()

	MetaDirector.reset_session()
	GameState.stage = stage


## A "meta-event screen" test double — a Control that swallows every
## `_unhandled_input` — must not see Esc at all: PauseMenu reads `_input`
## first, so the swallowing layer never gets the panic key.
func test_esc_never_reaches_event_owned_unhandled_handlers() -> void:
	var swallower := Control.new()
	swallower.set_script(SwallowScr)
	add_child(auto_free(swallower))
	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_true()
	assert_array(swallower.get("seen")).is_empty()


## ui_cancel (a pad cancel or remapped key) is the same panic key.
func test_ui_cancel_opens_the_menu_too() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	PauseMenu._input(event)
	assert_bool(PauseMenu.is_open()).is_true()


## The pause page's Quit routes through MetaDirector's close handling: while
## M01 may hold, nothing quits; the rule that "closing always works" lives in
## that handler, not in this menu.
func test_quit_button_uses_the_close_path() -> void:
	var stage := int(GameState.stage)
	GameState.stage = maxi(stage, MetaDirector.close_gate())
	var quit_calls: Array = []
	MetaDirector.set_quit_callable(func() -> void: quit_calls.append(true))

	PauseMenu.open_pause()
	_quit_button().pressed.emit()

	# The close request was delivered through the same path as the window X:
	# either M01 held it (offer open, no quit) or it quit already — never a
	# second, parallel quit mechanism.
	var held := bool(MetaDirector.state().get("close_held", false))
	if held:
		assert_array(quit_calls).is_empty()
		assert_bool(bool(MetaDirector.state().get("offer_open", false))).is_true()
	else:
		assert_array(quit_calls).has_size(1)

	MetaDirector.reset_session()
	MetaDirector.set_quit_callable(Callable())
	GameState.stage = stage


## The settings page is the same overlay (one surface), pauses the same way,
## and Back from the pause path returns to the pause page — not to play.
func test_settings_from_the_pause_page_returns_to_pause() -> void:
	PauseMenu.open_pause()
	PauseMenu.open_settings()
	assert_bool(PauseMenu.showing_settings()).is_true()
	(
		(
			PauseMenu._settings_page.get_child(PauseMenu._settings_page.get_child_count() - 1)
			as Button
		)
		. pressed
		. emit()
	)  # Back is the last row
	assert_bool(PauseMenu.is_open()).is_true()
	assert_bool(PauseMenu.showing_settings()).is_false()
	assert_bool(get_tree().paused).is_true()


## CODE-2: closing the overlay hands the keyboard back to the control the
## player was using. A pause during the player's typing window (the date
## scene's InputBox grabs focus once per turn) must not eat their next
## keystrokes — the probe found a null focus owner after pause → resume.
func test_closing_restores_the_focused_control() -> void:
	var field := LineEdit.new()
	add_child(auto_free(field))
	await get_tree().process_frame
	field.grab_focus()
	var viewport := field.get_viewport()
	assert_object(viewport.gui_get_focus_owner()).is_same(field)

	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_true()
	assert_object(viewport.gui_get_focus_owner()).is_not_same(field)  # the menu took it

	PauseMenu._input(_esc())
	assert_bool(PauseMenu.is_open()).is_false()
	assert_object(viewport.gui_get_focus_owner()).is_same(field)


## A target that disappeared while the menu was up is skipped, not crashed on.
func test_closing_skips_a_focus_target_that_was_freed() -> void:
	var field := LineEdit.new()
	add_child(field)
	await get_tree().process_frame
	field.grab_focus()

	PauseMenu.open_pause()
	field.free()

	PauseMenu.close()
	assert_bool(PauseMenu.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()


## The settings page opens from the Title with nothing focused: closing must
## not invent a focus owner either.
func test_closing_without_a_prior_focus_owner_is_safe() -> void:
	PauseMenu.open_settings()
	PauseMenu.close()
	assert_bool(PauseMenu.is_open()).is_false()
	assert_object(PauseMenu._focus_before_open).is_null()


## The Quit row of the pause page, found by its label rather than a magic
## index — the page's rows may grow.
func _quit_button() -> Button:
	for child: Node in PauseMenu._pause_page.get_children():
		if child is Button and String((child as Button).text).contains("Quit"):
			return child
	return null
