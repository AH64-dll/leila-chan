extends GdUnitTestSuite
## P2.07 — the docs/03 §5 leak as the ChatUI/Date pipeline runs it: the grey 1 s
## ghost at stage 2, the red word-by-word line at stage 4–5, the per-turn cap,
## the stage gate, the placement behind the text box, and — the safety
## criterion — that every displayed line is the Safety filter's output, never
## raw model text (docs/02 §8).

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const DatePacked := preload("res://scenes/Date.tscn")
const GREY := Color("#b9b9c2")
const RED := Color("#c0272f")
const BLOCKED := "you should kill yourself."


func before_test() -> void:
	Settings.reduced_motion = false
	Settings.content_level = ""
	InnerLeak.clear_cache()


func after_test() -> void:
	Settings.reduced_motion = false
	Settings.content_level = ""
	GameState.stage = 0
	Director.register_chat_ui(null)


func _new_chat() -> Control:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	return ui


## The first salt whose seeded roll leaks on `turn`. Production uses salt 0; a
## test needs a turn that actually leaks, and the roll is fully deterministic.
func _leaking_salt(plan_dict: Dictionary, turn: int) -> int:
	for salt: int in range(0, 5000):
		if InnerLeak.roll(plan_dict, turn, salt):
			return salt
	return 0


func test_stage_2_leak_is_the_grey_one_second_ghost() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)  # instant typewriter keeps the turn deterministic
	ui.set_stage(2)
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(2, {}), 1)
	ui.begin_turn_wait()  # the first turn: ChatUI._turn_seq == 1
	assert_bool(ui.leak_inner("  He   said her name again.  ")).is_true()
	assert_bool(ui.inner_leak.is_leaking()).is_true()
	assert_bool(ui.inner_leak.visible).is_true()
	assert_str(ui.inner_leak.get_style_name()).is_equal("ghost")
	assert_str(ui.inner_leak.get_reveal_mode()).is_equal(InnerLeak.REVEAL_INSTANT)
	# Whole line at once (no word-by-word before stage 4), and it is the Safety
	# filter's normalized output: trimmed, single-spaced.
	assert_str(ui.inner_leak.get_visible_text()).is_equal("He said her name again.")
	assert_str(ui.inner_leak.get_leak_text()).is_equal("He said her name again.")
	# "faint grey italic": the data colour and alpha reached the label.
	var colour: Color = ui.inner_leak.get_theme_color("font_color")
	assert_float(colour.r).is_equal_approx(GREY.r, 0.001)
	assert_float(colour.g).is_equal_approx(GREY.g, 0.001)
	assert_float(colour.b).is_equal_approx(GREY.b, 0.001)
	assert_float(colour.a).is_equal_approx(0.55, 0.001)
	# "for 1 s": still there just before the second, gone after it.
	ui.inner_leak.advance(0.5)
	assert_bool(ui.inner_leak.is_leaking()).is_true()
	ui.inner_leak.advance(0.6)
	assert_bool(ui.inner_leak.is_leaking()).is_false()
	assert_bool(ui.inner_leak.visible).is_false()


func test_stage_5_leak_is_red_and_reveals_word_by_word() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(false)  # the word-by-word animation is the point here
	ui.set_stage(5)
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(5, {}), 1)
	ui.begin_turn_wait()
	assert_bool(ui.leak_inner("I could keep him here")).is_true()
	assert_str(ui.inner_leak.get_style_name()).is_equal("red")
	assert_str(ui.inner_leak.get_reveal_mode()).is_equal(InnerLeak.REVEAL_WORDS)
	# One word to start with, then one more per interval.
	assert_str(ui.inner_leak.get_visible_text()).is_equal("I")
	var colour: Color = ui.inner_leak.get_theme_color("font_color")
	assert_float(colour.r).is_equal_approx(RED.r, 0.001)
	assert_float(colour.g).is_equal_approx(RED.g, 0.001)
	assert_float(colour.a).is_equal_approx(0.95, 0.001)
	var interval: float = ui.inner_leak.get_word_interval()
	ui.inner_leak.advance(interval)
	assert_str(ui.inner_leak.get_visible_text()).is_equal("I could")
	ui.inner_leak.advance(interval * 10.0)
	assert_str(ui.inner_leak.get_visible_text()).is_equal("I could keep him here")
	# The hold then ends it.
	ui.inner_leak.advance(ui.inner_leak.get_hold() + 0.01)
	assert_bool(ui.inner_leak.is_leaking()).is_false()
	assert_str(ui.inner_leak.get_leak_text()).is_empty()


func test_blocked_inner_is_redacted_before_display() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.set_stage(4)
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(4, {}), 1)
	ui.begin_turn_wait()
	var expected := str((Safety.filter_text(BLOCKED, {"stage": 4}) as Dictionary)["text"])
	assert_bool(expected.contains("█")).is_true()
	assert_bool(ui.leak_inner(BLOCKED)).is_true()
	# docs/02 §8: the displayed line is the filter's output, not the model's.
	assert_str(ui.inner_leak.get_leak_text()).is_equal(expected)
	assert_bool(ui.inner_leak.get_visible_text().contains("kill")).is_false()
	assert_bool(ui.inner_leak.get_visible_text().contains("█")).is_true()


func test_dev_trigger_still_passes_safety() -> void:
	# The F3/F4 dev trigger bypasses the docs gate only; Safety is never bypassed.
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.set_stage(0)
	assert_bool(ui.leak_inner(BLOCKED, true)).is_true()
	assert_bool(ui.inner_leak.get_leak_text().contains("kill")).is_false()
	assert_bool(ui.inner_leak.get_leak_text().contains("█")).is_true()


func test_inner_leaks_at_most_once_per_turn() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.set_stage(5)
	var plan_dict := InnerLeak.plan(5, {})
	ui.inner_leak_salt = _leaking_salt(plan_dict, 1)
	ui.begin_turn_wait()
	assert_bool(ui.leak_inner("First thought.")).is_true()
	var first: String = ui.inner_leak.get_leak_text()
	assert_bool(ui.leak_inner("Second thought.")).is_false()
	assert_str(ui.inner_leak.get_leak_text()).is_equal(first)
	# The cap is per turn, not per session: the next turn may leak again.
	ui.abort_turn()
	ui.inner_leak_salt = _leaking_salt(plan_dict, 2)
	ui.begin_turn_wait()
	assert_bool(ui.leak_inner("Second thought.")).is_true()
	assert_str(ui.inner_leak.get_leak_text()).is_equal("Second thought.")


func test_no_leak_below_stage_2_without_the_dev_trigger() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.set_stage(1)
	# A salt that would leak at stage 2: the closed gate must still hold.
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(2, {}), 1)
	ui.begin_turn_wait()
	assert_bool(ui.leak_inner("He noticed me.")).is_false()
	assert_bool(ui.inner_leak.is_leaking()).is_false()
	# The dev trigger can show it for testing, and it is still scanned.
	assert_bool(ui.leak_inner("He noticed me.", true)).is_true()
	assert_bool(ui.inner_leak.is_leaking()).is_true()
	assert_str(ui.inner_leak.get_visible_text()).is_equal("He noticed me.")


func test_leak_is_drawn_behind_the_text_box() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	# z -1 draws the label under the TextBox panel (docs/03 §5 "behind the text
	# box"); the label ignores the mouse and is pinned to the box's top border so
	# its bottom `behind_overlap` px (ghost 2, red 0) tuck behind the panel.
	var turn := 0
	for stage: int in [4, 2]:
		ui.abort_turn()  # close the previous turn so the next one advances _turn_seq
		turn += 1
		ui.set_stage(stage)
		ui.begin_turn_wait()
		var plan_dict := InnerLeak.plan(stage, {})
		ui.inner_leak_salt = _leaking_salt(plan_dict, turn)
		assert_bool(ui.leak_inner("I could keep him here.")).is_true()
		await get_tree().process_frame  # the container settles, the label re-pins
		var overlap: float = float((plan_dict["spec"] as Dictionary)["behind_overlap"])
		var box: Rect2 = ui.text_box.get_global_rect()
		var origin: Vector2 = ui.get_global_rect().position
		var label_top: float = ui.inner_leak.position.y + origin.y
		var label_bottom: float = label_top + ui.inner_leak.size.y
		assert_int(ui.inner_leak.z_index).is_equal(-1)
		assert_int(ui.inner_leak.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		# Layering: the log panel sits one plane lower (so the leak is not buried
		# under it), while the box stays on the default plane above the leak (so
		# the tuck is really occluded).
		assert_int(ui.chat_log.z_index).is_equal(-2)
		assert_int(ui.text_box.z_index).is_equal(0)
		assert_float(ui.inner_leak.size.y).is_greater(0.0)
		assert_bool(label_top < box.position.y).is_true()
		(
			assert_float(label_bottom)
			. override_failure_message(
				(
					"stage %d: label bottom %.1f must tuck %.1f px under the box top %.1f"
					% [stage, label_bottom, overlap, box.position.y]
				)
			)
			. is_equal_approx(box.position.y + overlap, 0.5)
		)
		assert_float(ui.inner_leak.position.x + origin.x).is_equal_approx(
			box.position.x + 12.0, 0.5
		)


func test_leak_never_touches_the_spoken_text_or_the_log() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.set_stage(5)
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(5, {}), 1)
	# One ordinary streamed turn first (instant typewriter).
	ui.begin_turn_wait()
	ui.begin_beat(0)
	ui.say_chunk(0, "Don't get the wrong idea.")
	ui.end_beat(0)
	ui.end_turn()
	await get_tree().process_frame
	assert_str(ui.text_box.get_beat_text(0)).is_equal("Don't get the wrong idea.")
	assert_bool(ui.leak_inner("I want to crush you.")).is_true()
	# The thought is display-only: her spoken line and the log are untouched.
	assert_str(ui.text_box.get_beat_text(0)).is_equal("Don't get the wrong idea.")
	assert_int(ui.chat_log.get_entries().size()).is_equal(1)
	# The next turn clears the hold early.
	ui.begin_turn_wait()
	assert_bool(ui.inner_leak.is_leaking()).is_false()


func test_reduced_motion_keeps_the_red_line_whole() -> void:
	Settings.reduced_motion = true  # the global switch can only force it on
	var ui := await _new_chat()
	ui.set_stage(5)
	assert_bool(ui.is_reduced_motion()).is_true()
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(5, {"reduced_motion": true}), 1)
	ui.begin_turn_wait()
	assert_bool(ui.leak_inner("I could keep him here")).is_true()
	# Same red thought, no word-by-word animation (docs/05 §0.5).
	assert_str(ui.inner_leak.get_style_name()).is_equal("red")
	assert_str(ui.inner_leak.get_reveal_mode()).is_equal(InnerLeak.REVEAL_INSTANT)
	assert_str(ui.inner_leak.get_visible_text()).is_equal("I could keep him here")


func test_esc_still_pauses_while_a_leak_is_showing() -> void:
	# docs/05 §0.3: Esc opens the safe pause at any moment, including during a
	# meta event. The leak adds no input handling of its own, so the UI's own
	# pause path must still fire while the thought is on screen.
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.set_stage(4)
	ui.inner_leak_salt = _leaking_salt(InnerLeak.plan(4, {}), 1)
	ui.begin_turn_wait()
	assert_bool(ui.leak_inner("I could keep him here.")).is_true()
	var pauses := [0]
	ui.pause_requested.connect(func() -> void: pauses[0] += 1)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ui._unhandled_key_input(esc)
	assert_int(pauses[0]).is_equal(1)
	# The leak stays a timed overlay: pausing neither consumes nor extends it.
	assert_bool(ui.inner_leak.is_leaking()).is_true()
	ui.inner_leak.advance(ui.inner_leak.get_hold() + 10.0)
	assert_bool(ui.inner_leak.is_leaking()).is_false()


func test_date_hands_each_finished_turn_to_the_leak() -> void:
	GameState.stage = 5
	var date: Node2D = DatePacked.instantiate()
	add_child(auto_free(date))
	await get_tree().process_frame
	assert_int(date.chat_ui.stage).is_equal(5)
	var plan_dict := InnerLeak.plan(5, {})
	# The harness opens the turn the way a submit does; the Date only forwards
	# the Director's finished turn into the ChatUI's leak path.
	date.chat_ui.begin_turn_wait()
	date.chat_ui.inner_leak_salt = _leaking_salt(plan_dict, 1)
	Director.turn_completed.emit(1, {"inner": "I could keep him here."})
	assert_bool(date.chat_ui.inner_leak.is_leaking()).is_true()
	assert_str(date.chat_ui.inner_leak.get_leak_text()).is_equal("I could keep him here.")
