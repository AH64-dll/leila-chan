extends GdUnitTestSuite
## P2.06 — the corruption filter as the ChatUI/Date text pipeline runs it.
##
## docs/07 §3.4 order is `say chunk → Safety.scan → PronounFix →
## Corruption.filter(stage, path) → Typewriter`. The UI tests prove the seam:
## Safety runs first (an uppercase filter is visible inside the corrupted
## output), corruption lands on the queued beat and in the chat log, a safety
## refusal stays legible, reduced motion removes the visual glyphs, and the
## Date scene installs the session and follows the campaign stage.

const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const DatePacked := preload("res://scenes/Date.tscn")
const SLASH := "\u0338"
const UNDER := "\u0332"
const ZALGO_MARKS: Array[String] = ["\u0300", "\u0301", "\u0308"]
const SAMPLE := "Senpai, I hate the way you look at me. I'm fine."


func _new_chat() -> Control:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	return ui


func _new_date() -> Node2D:
	var date: Node2D = DatePacked.instantiate()
	date.auto_start = false  # P2.22 S1-2: the suite drives the date itself
	add_child(auto_free(date))
	await get_tree().process_frame
	return date


func _slashed(word: String) -> String:
	var out := ""
	for i: int in word.length():
		out += word[i]
		if word[i].to_lower() != word[i].to_upper():
			out += SLASH
	return out


## Run one streamed turn and wait one frame so the (instant) typewriter lands
## the beat in the box and the chat log, exactly as a rendered frame would.
func _turn(ui: Control, text: String) -> String:
	ui.begin_turn_wait()
	ui.begin_beat(0)
	ui.say_chunk(0, text)
	ui.end_beat(0)
	ui.end_turn()
	await get_tree().process_frame
	return str(ui.text_box.get_beat_text(0))


func _count_marks(text: String, marks: Array[String]) -> int:
	var count := 0
	for i: int in text.length():
		if marks.has(text[i]):
			count += 1
	return count


func test_corruption_runs_after_the_safety_filter() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.stage = 2
	ui.corruption = CorruptionSession.new()
	# Safety's injected seam (P1.19): uppercase stands in for a real scan. The
	# corrupted text must contain the UPPERCASE word, proving corruption ran
	# after the filter, never before it.
	ui.text_filter = func(chunk: String) -> String: return chunk.to_upper()
	var out: String = await _turn(ui, "i hate you, senpai. i'm fine.")
	# Seed = turn 1, beat 0, stage 2: the strike fires on "fine".
	var expected := "I HATE YOU, SENPAI. I'M " + _slashed("FINE") + " — no, BROKEN."
	assert_str(out).is_equal(expected)
	assert_str(ui.text_box.get_visible_text()).is_equal(expected)
	# The log stores the corrupted line (it is what she actually said).
	var entries: Array = ui.chat_log.get_entries()
	assert_int(entries.size()).is_equal(1)
	assert_str(String(entries[0]["text"])).is_equal(expected)
	# A blocked phrase stays blocked: Safety's bars are never un-redacted,
	# re-worded or hidden by the corruption stage that runs after it.
	await get_tree().process_frame
	ui.text_filter = func(chunk: String) -> String: return chunk.replace("die", "██████")
	var blocked: String = await _turn(ui, "I want to die.")
	assert_bool(blocked.contains("██████")).is_true()
	assert_bool(blocked.contains("die")).is_false()


func test_chatui_without_a_session_is_unchanged() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	var out: String = await _turn(ui, "hello there, Senpai.")
	assert_str(out).is_equal("hello there, Senpai.")
	assert_bool(ui.corruption == null).is_true()


func test_reduced_motion_removes_the_visual_glyphs() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.stage = 5
	ui.corruption = CorruptionSession.new()
	ui.corruption.seed_base = 2
	var out: String = await _turn(ui, SAMPLE)
	# The UI's session must be the same seeded, reduced plan as the pure one:
	# turn 1, beat 0, stage 5, seed-base 2.
	var expected_session := CorruptionSession.new()
	(
		expected_session
		. begin_turn(
			{
				"turn": 1,
				"stage": 5,
				"player_name": "Senpai",
				"seed_base": 2,
				"reduced_motion": true,
			}
		)
	)
	assert_str(out).is_equal(expected_session.transform_beat(0, SAMPLE))
	# Reduced motion: no zalgo burst, no bleed echo …
	assert_int(_count_marks(out, ZALGO_MARKS)).is_zero()
	assert_bool(out.contains(UNDER)).is_false()
	# …while the textual effects stay: the wrong-name slip and the strike.
	assert_bool(out.contains("Senpai")).is_false()
	assert_bool(out.contains(_slashed("hate") + " — no, love")).is_true()
	# The same beat without reduced motion does carry the glyphs, so the flag
	# is doing the work (not a seed that never decorated anything).
	var visual_session := CorruptionSession.new()
	visual_session.begin_turn({"turn": 1, "stage": 5, "player_name": "Senpai", "seed_base": 2})
	assert_int(_count_marks(visual_session.transform_beat(0, SAMPLE), ZALGO_MARKS)).is_greater(0)


func test_reject_turn_stays_legible() -> void:
	# docs/02 §8: a Safety refusal is not model text and must read exactly as
	# written; corruption skips it (replace_beat(..., corrupt = false)).
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.stage = 5
	ui.corruption = CorruptionSession.new()
	ui.corruption.seed_base = 2
	ui.reject_turn("I can't help with that.")
	await get_tree().process_frame
	assert_str(ui.text_box.get_beat_text(0)).is_equal("I can't help with that.")
	assert_str(ui.text_box.get_visible_text()).is_equal("I can't help with that.")


func test_date_installs_the_session_and_the_accessibility_flag() -> void:
	var date := await _new_date()
	assert_object(date.chat_ui.corruption).is_not_null()
	assert_bool(date.chat_ui.reduced_motion).is_false()
	date.set_reduced_motion(true)
	assert_bool(date.chat_ui.reduced_motion).is_true()
	assert_bool(date.chat_ui.is_reduced_motion()).is_true()
	# The UI's safety pass-through is still installed next to the new stage.
	assert_bool(date.chat_ui.text_filter.is_valid()).is_true()


func test_date_follows_the_campaign_stage() -> void:
	var date := await _new_date()
	# docs/01 §3: the stage is GameState's; a transition must reach the scene
	# that draws her text so the next turn's corruption plan changes. Emitting
	# the signal (not mutating GameState) keeps the suite isolated.
	GameState.stage_changed.emit(0, 4)
	assert_int(date.stage).is_equal(4)
	assert_int(date.chat_ui.stage).is_equal(4)
	GameState.stage_changed.emit(4, 2)
	assert_int(date.stage).is_equal(2)
	assert_int(date.chat_ui.stage).is_equal(2)


func test_next_turn_replans_after_a_stage_change() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	ui.corruption = CorruptionSession.new()
	var clean: String = await _turn(ui, SAMPLE)
	assert_str(clean).is_equal(SAMPLE)
	await get_tree().process_frame
	assert_bool(ui.is_turn_open()).is_false()
	# A stage transition between turns changes the next turn's plan: the same
	# line now carries stage-5 damage.
	ui.set_stage(5)
	var damaged: String = await _turn(ui, SAMPLE)
	assert_str(damaged).is_not_equal(SAMPLE)
	(
		assert_bool(damaged.contains(SLASH) or damaged.contains("█") or damaged.contains("\n"))
		. is_true()
	)
