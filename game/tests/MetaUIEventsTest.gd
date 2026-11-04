extends GdUnitTestSuite
## P3.10 — docs/05 §1.3 M22/M25 at the screen: her suggestion is a draft the
## player can always delete, and the hidden UI comes back on the first click or
## key (docs/05 §0: Esc stays a safe pause while it is hidden).

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const SUGGESTION := "I'll never leave you."

var _snapshot := {}


func before_test() -> void:
	_snapshot = GameState.to_dict()
	GameState.reset()
	Settings.reduced_motion = false
	Settings.photosensitive = false
	Telemetry.take_private_draft()
	PauseMenu.close()
	get_tree().paused = false


func after_test() -> void:
	await get_tree().process_frame
	PauseMenu.close()
	get_tree().paused = false
	Settings.reduced_motion = false
	Telemetry.take_private_draft()
	if not _snapshot.is_empty():
		GameState.from_dict(_snapshot)
	_snapshot = {}


func _new_chat() -> Control:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	return ui


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(32, 32)
	return event


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


## ── docs/05 §1.3 M22: she types for you ───────────────────────────────────


## The whole point of the event: her words arrive in the box and the player can
## delete every character of them, because it is only ever a draft.
func test_m22_she_types_the_suggestion_into_an_empty_box() -> void:
	var ui := await _new_chat()
	assert_bool(ui.apply_meta_ui("mimic", SUGGESTION)).is_true()
	assert_bool(ui.mimic_active).is_true()
	ui._process(0.2)  # mid-word: it types itself in, it does not appear at once
	assert_str(ui.input_box.text).is_not_equal(SUGGESTION)
	ui._process(1.0)
	assert_str(ui.input_box.text).is_equal(SUGGESTION)


func test_m22_the_player_can_delete_every_character_she_typed() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("mimic", SUGGESTION)
	ui._process(1.0)
	assert_str(ui.input_box.text).is_equal(SUGGESTION)
	assert_bool(ui.input_box.is_input_enabled()).is_true()
	# Backspace, one character at a time: the box never fights the deletion
	# (each assignment goes through the same `text_changed` path a key does).
	while not ui.input_box.text.is_empty():
		ui.input_box.text = ui.input_box.text.substr(0, ui.input_box.text.length() - 1)
	assert_str(ui.input_box.text).is_equal("")
	assert_bool(ui.mimic_active).is_false()
	assert_bool(ui.input_box.is_input_enabled()).is_true()


func test_m22_clear_draft_empties_her_text_too() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("mimic", SUGGESTION)
	ui._process(1.0)
	ui.input_box.clear_draft()
	assert_str(ui.input_box.draft()).is_equal("")


## The moment the player touches the box she stops typing: the field is theirs.
func test_m22_stops_typing_when_the_player_takes_the_box_back() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("mimic", "I'll never leave you and I mean it.")
	ui._process(0.2)
	var partial: String = ui.input_box.text
	# A programmatic write stands in for the player's keystroke (headless runs
	# carry no key events); it does not emit `text_changed`, so the box-content
	# guard in `_advance_mimic` is what has to catch it on the next tick.
	ui.input_box.text = partial + "!"
	ui._process(0.05)
	assert_bool(ui.mimic_active).is_false()
	ui._process(1.0)
	assert_str(ui.input_box.text).is_equal(partial + "!")


## She never types over a draft the player already wrote.
func test_m22_never_overwrites_the_players_draft() -> void:
	var ui := await _new_chat()
	ui.input_box.text = "my own words"
	assert_bool(ui.apply_meta_ui("mimic", SUGGESTION)).is_false()
	assert_str(ui.input_box.text).is_equal("my own words")


## The documented fallback (data/meta_events_m21.json m22): reduced motion fills
## the suggestion in one piece instead of animating it — still deletable.
func test_m22_reduced_motion_fills_it_in_one_piece() -> void:
	Settings.reduced_motion = true
	var ui := await _new_chat()
	assert_bool(ui.apply_meta_ui("mimic", SUGGESTION)).is_true()
	assert_str(ui.input_box.text).is_equal(SUGGESTION)
	assert_bool(ui.mimic_active).is_false()
	ui.input_box.clear_draft()
	assert_str(ui.input_box.draft()).is_equal("")


## docs/05 §1.3 M21 must not quote her own line back: a suggestion the player
## erases is not a draft the player gave up on, so nothing is reported.
func test_m22_erasing_her_words_is_not_a_player_deleted_draft() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("mimic", SUGGESTION)
	ui._process(1.0)
	ui.input_box.text = ""
	assert_str(Telemetry.take_private_draft()).is_equal("")


## ── docs/05 §1.3 M25: hide the UI ─────────────────────────────────────────


func test_m25_hides_every_box_and_a_click_brings_them_back() -> void:
	var ui := await _new_chat()
	assert_bool(ui.apply_meta_ui("hide")).is_true()
	assert_bool(ui.ui_hidden).is_true()
	assert_bool(ui.chat_log.visible).is_false()
	assert_bool(ui.text_box.visible).is_false()
	assert_bool(ui.input_box.visible).is_false()
	# Hidden, the root must not eat the very click that restores it.
	assert_int(ui.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	ui._unhandled_input(_click())
	assert_bool(ui.ui_hidden).is_false()
	assert_bool(ui.text_box.visible).is_true()
	assert_bool(ui.input_box.visible).is_true()
	assert_int(ui.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_m25_a_key_also_restores_the_ui() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("hide")
	ui._unhandled_input(_key(KEY_A))
	assert_bool(ui.ui_hidden).is_false()
	assert_bool(ui.text_box.visible).is_true()


## The log's own open/closed state survives the hide: "restore" is not "reset".
func test_m25_restores_the_log_state_the_player_had() -> void:
	var ui := await _new_chat()
	ui._unhandled_input(_key(KEY_TAB))  # player closed the scroll-back log
	assert_bool(ui.chat_log.visible).is_false()
	ui.apply_meta_ui("hide")
	ui._unhandled_input(_click())
	assert_bool(ui.chat_log.visible).is_false()
	assert_bool(ui.text_box.visible).is_true()


## docs/05 §1.3 M25's accessibility fallback: reduced motion fades instead of
## vanishing, and any input still restores in one call — no tween to wait for.
func test_m25_reduced_motion_fades_and_input_restores_at_once() -> void:
	Settings.reduced_motion = true
	var ui := await _new_chat()
	ui.apply_meta_ui("hide")
	assert_bool(ui.ui_hidden).is_true()
	# The fade is still running, so the boxes are on screen (alpha 0 → still
	# visible) — the state flag is what decides "restore".
	ui._unhandled_input(_click())
	assert_bool(ui.ui_hidden).is_false()
	assert_bool(ui.text_box.visible).is_true()
	assert_float(ui.modulate.a).is_equal_approx(1.0, 0.001)


## "For one turn": a new turn always starts with the UI back, even one the
## Director starts without the player (docs/05 M30's monologue path).
func test_m25_a_new_turn_restores_the_ui() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("hide")
	ui.begin_turn_wait()
	assert_bool(ui.ui_hidden).is_false()
	assert_bool(ui.text_box.visible).is_true()


## A turn that dies must never leave the player without a box (docs/05 §0).
func test_m25_a_dead_turn_restores_the_ui() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("hide")
	ui.abort_turn()
	assert_bool(ui.ui_hidden).is_false()
	assert_bool(ui.input_box.visible).is_true()


## docs/05 §0 rule 3: Esc is PauseMenu's from `_input`, so it keeps working while
## the boxes are hidden — the panic key is never trapped by the event.
func test_m25_esc_still_opens_the_safe_pause_while_hidden() -> void:
	var ui := await _new_chat()
	ui.apply_meta_ui("hide")
	get_viewport().push_input(_key(KEY_ESCAPE))
	await get_tree().process_frame
	assert_bool(PauseMenu.is_open()).is_true()
	assert_bool(ui.ui_hidden).is_true()
	# And closing the pause leaves a UI the next click brings back.
	PauseMenu.close()
	ui._unhandled_input(_click())
	assert_bool(ui.ui_hidden).is_false()


## ── The seam itself ───────────────────────────────────────────────────────


func test_unknown_effects_are_refused() -> void:
	var ui := await _new_chat()
	assert_bool(ui.apply_meta_ui("cursor_warp")).is_false()
	assert_bool(ui.apply_meta_ui("hide")).is_true()
	assert_bool(ui.apply_meta_ui("hide")).is_false()  # already hidden
	assert_bool(ui.apply_meta_ui("restore")).is_true()
	assert_bool(ui.apply_meta_ui("restore")).is_false()  # already shown
