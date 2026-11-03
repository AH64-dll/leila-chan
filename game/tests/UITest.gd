extends GdUnitTestSuite
## P1.13 — UI kit contract (docs/07 §2, docs/02 §4): TextBox typewriter at
## 35–45 chars/s consuming streamed say_chunk events live, the diegetic
## typing indicator up to the first say token, the scrolling ChatLog storing
## spoken text, and keyboard-only play.

const ConfScr := preload("res://scenes/ui/UiConfig.gd")
const WriterScr := preload("res://scenes/ui/Typewriter.gd")
const IndicScr := preload("res://scenes/ui/TypingIndicator.gd")
const SayScr := preload("res://tests/helpers/ManualSayStream.gd")
const ChatUIScene := preload("res://scenes/ui/ChatUI.tscn")
const TextBoxScene := preload("res://scenes/ui/TextBox.tscn")
const InputBoxScene := preload("res://scenes/ui/InputBox.tscn")
const ChatLogScene := preload("res://scenes/ui/ChatLog.tscn")
const LLMScript := preload("res://autoload/LLM.gd")
const FakeBackend := preload("res://tests/helpers/FakeLLMBackend.gd")

const TURN_JSON := (
	"{"
	+ '"read":"flirt","inner":"He talked to me.","music":"keep","fx":"none",'
	+ '"beats":['
	+ '{"feeling":"happy","intensity":2,"cue":"none","say":"Hi! I waited all day for you."},'
	+ '{"feeling":"shy","intensity":1,"cue":"giggle","say":"Don\u0027t stare though."}'
	+ '],"mood":{"affection":1,"trust":0,"stress":0},"memory":"","action":"none"}'
)


func _new_chat() -> Control:
	var ui: Control = ChatUIScene.instantiate()
	add_child(auto_free(ui))
	await get_tree().process_frame
	return ui


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


## Wait until predicate.call() is true or the deadline passes.
func _await_until(predicate: Callable, timeout_ms := 8000) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func test_ui_json_matches_builtin_defaults() -> void:
	# data/ui.json is the shipped content; UiConfig.DEFAULTS must agree so the
	# file stays the single source of truth (docs/07 §2: content is data).
	var loaded: Dictionary = ConfScr.load_config()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui.json"))
	assert_dict(parsed).is_not_empty()
	var merged: Dictionary = ConfScr.DEFAULTS.duplicate(true)
	for key: String in parsed:
		var value: Variant = parsed[key]
		if value is Dictionary and merged.get(key) is Dictionary:
			for inner: String in value:
				merged[key][inner] = value[inner]
		else:
			merged[key] = value
	assert_dict(loaded).is_equal(merged)
	var tw: Dictionary = loaded["typewriter"]
	assert_float(float(tw["chars_per_second"])).is_between(35.0, 45.0)


func test_typewriter_reveal_rate_and_bounds() -> void:
	var w: Typewriter = WriterScr.new()
	w.configure({})
	assert_float(w.chars_per_second).is_equal(40.0)
	w.configure({"chars_per_second": 90})
	assert_float(w.chars_per_second).is_equal(45.0)  # clamped to the design max
	w.configure({"chars_per_second": 10})
	assert_float(w.chars_per_second).is_equal(35.0)  # clamped to the design min
	w.configure({"chars_per_second": 40, "pause_chars": {}})

	var drained_count := [0]
	var beat_done: Array = []
	w.beat_drained.connect(func(i: int) -> void: beat_done.append(i))
	w.drained.connect(func() -> void: drained_count[0] += 1)

	var beat := {"i": 0, "text": "abcdefghij", "closed": false}
	w.append_beat(beat)
	w.advance(0.1)  # 4 chars at 40 chars/s
	assert_str(w.get_visible_text()).is_equal("abcd")
	assert_bool(w.is_revealing()).is_true()  # open beat: more may arrive
	beat["text"] = "abcdefghijklmnop"  # a late say_chunk lengthens the beat
	w.advance(0.3)  # 12 more chars → all 16 visible, still open
	assert_str(w.get_visible_text()).is_equal("abcdefghijklmnop")
	assert_array(beat_done).is_empty()  # not drained while the stream is open
	beat["closed"] = true
	w.advance(0.016)
	assert_array(beat_done).is_equal([0])
	assert_int(drained_count[0]).is_equal(1)
	assert_bool(w.is_complete()).is_true()


func test_typewriter_stream_stall_does_not_burst() -> void:
	# CODE-2: Cap credit when the front beat is fully revealed but still open.
	# A 2.0 s pause between chunks must never bank credit past 1 char.
	var w: Typewriter = WriterScr.new()
	w.configure({"chars_per_second": 40, "pause_chars": {}})
	var beat := {"i": 0, "text": "abcdef", "closed": false}
	w.append_beat(beat)
	w.advance(0.15)  # 6 chars revealed at 40/s -> "abcdef"
	assert_str(w.get_visible_text()).is_equal("abcdef")

	# 2.0 second stream pause
	w.advance(2.0)
	assert_str(w.get_visible_text()).is_equal("abcdef")

	# Next chunk lands
	beat["text"] = "abcdefXYZ"
	# Advancing by 1 ms (0.001 s) should only reveal at most 1 char, not burst XYZ at once
	var gained := w.advance(0.001)
	assert_int(gained).is_equal(1)
	assert_str(w.get_visible_text()).is_equal("abcdefX")


func test_typewriter_punctuation_pauses_and_skip() -> void:
	var w: Typewriter = WriterScr.new()
	w.configure({"chars_per_second": 40, "pause_chars": {".": 240, ",": 0}})
	w.append_beat({"i": 0, "text": "ab.cd", "closed": true})
	w.advance(0.1)  # 4 chars at 40/s: stops right after the '.', dwell starts
	assert_str(w.get_visible_text()).is_equal("ab.")
	w.advance(0.1)  # still dwelling — no new characters
	assert_str(w.get_visible_text()).is_equal("ab.")
	w.advance(0.2)  # dwell over, the last character lands
	assert_str(w.get_visible_text()).is_equal("ab.cd")

	w.reset()
	w.append_beat({"i": 1, "text": "quick text here", "closed": true})
	w.advance(0.01)
	assert_bool(w.has_pending()).is_true()
	var skipped := w.reveal_now()
	assert_int(skipped).is_equal("quick text here".length())
	# A drained queue keeps the last spoken line on screen.
	assert_str(w.get_visible_text()).is_equal("quick text here")
	assert_bool(w.is_complete()).is_true()


func test_typewriter_multi_beat_order() -> void:
	var w: Typewriter = WriterScr.new()
	w.configure({"chars_per_second": 40, "pause_chars": {}})
	var order: Array = []
	w.beat_drained.connect(func(i: int) -> void: order.append(i))
	w.append_beat({"i": 0, "text": "aaaa", "closed": true})
	w.append_beat({"i": 1, "text": "bbbb", "closed": true})
	# 8 chars at 40/s = 0.2 s; the second frame carries credit over the boundary.
	w.advance(0.25)
	w.advance(0.01)
	assert_array(order).is_equal([0, 1])
	assert_str(w.get_visible_text()).is_equal("bbbb")


func test_typing_indicator_stage_flavours() -> void:
	var ind: TypingIndicator = IndicScr.new()
	ind.configure({})

	ind.begin("Leila", 0)
	var seq0: PackedStringArray = []
	var t := 0.0
	while t < 1.3:
		ind.advance(0.05)
		t += 0.05
		seq0.append(ind.display_text())
	assert_array(Array(seq0)).contains("Leila is typing.")
	assert_array(Array(seq0)).contains("Leila is typing..")
	assert_array(Array(seq0)).contains("Leila is typing...")
	assert_bool(ind.is_you_variant()).is_false()  # no "*you*" below stage 5

	ind.begin("Leila", 3)
	var seen: Dictionary = {}
	t = 0.0
	while t < 2.4:
		ind.advance(0.06)
		t += 0.06
		seen[ind.display_text()] = true
	# Stutter cadence (160/520/600 ms slots) ≠ the steady 400 ms beat.
	assert_bool(seen.keys().size() >= 3).is_true()
	assert_bool(not seen.has("Leila is typing....")).is_true()

	ind.configure({"you_chance": 1.0})
	ind.begin("Leila", 5)
	ind.advance(0.5)
	assert_bool(ind.display_text().ends_with(" *you*")).is_true()
	assert_bool(ind.display_text().begins_with("Leila is typing")).is_true()
	assert_bool(ind.is_you_variant()).is_true()


func test_textbox_indicator_until_first_say_token() -> void:
	var box: PanelContainer = TextBoxScene.instantiate()
	add_child(auto_free(box))
	await get_tree().process_frame
	box.show_typing_indicator("Leila", 0)
	assert_bool(box.is_showing_indicator()).is_true()
	assert_bool(box.get_visible_text().begins_with("Leila is typing")).is_true()
	box.begin_beat(0)
	await get_tree().process_frame  # indicator survives a beat with no tokens yet
	assert_bool(box.is_showing_indicator()).is_true()
	box.say_chunk(0, "Hi")
	assert_bool(box.is_showing_indicator()).is_false()  # first say token ends it
	assert_str(box.get_visible_text()).is_equal("")


func test_chatui_turn_consumes_streamed_say_chunks() -> void:
	var ui := await _new_chat()
	var sent: PackedStringArray = []
	var done_flag := [false]
	ui.player_turn_sent.connect(func(t: String) -> void: sent.append(t))
	ui.turn_displayed.connect(func() -> void: done_flag[0] = true)
	ui.set_reduced_motion(true)  # deterministic reveal; pacing proven in writer tests

	ui.input_box.text = "hey leila"
	ui.input_box.text_submitted.emit("hey leila")
	await get_tree().process_frame
	assert_array(Array(sent)).is_equal(["hey leila"])
	assert_bool(ui.input_box.is_input_enabled()).is_false()
	assert_bool(ui.is_turn_open()).is_true()
	assert_bool(ui.text_box.is_showing_indicator()).is_true()  # "Leila is typing…"
	assert_bool(ui.text_box.get_visible_text().begins_with("Leila is typing")).is_true()

	# Feed the streamed turn through the say-event pump, a few raw chars at a
	# time — every say_chunk reaches the box while the stream is still open.
	var say: SayScr = SayScr.new()
	say.beat_start.connect(func(i: int) -> void: ui.begin_beat(i))
	say.say_chunk.connect(func(i: int, t: String) -> void: ui.say_chunk(i, t))
	say.beat_end.connect(func(i: int) -> void: ui.end_beat(i))
	for pos: int in range(0, TURN_JSON.length(), 7):
		say.feed(TURN_JSON.substr(pos, 7))
	ui.end_turn()
	await _await_until(func() -> bool: return done_flag[0])

	assert_bool(ui.is_turn_open()).is_false()
	assert_bool(ui.input_box.is_input_enabled()).is_true()
	var entries: Array = ui.chat_log.get_entries()
	assert_int(entries.size()).is_equal(3)
	assert_str(entries[0]["speaker"]).is_equal("Senpai")
	assert_str(entries[0]["text"]).is_equal("hey leila")
	assert_str(entries[1]["text"]).is_equal("Hi! I waited all day for you.")
	assert_str(entries[2]["text"]).is_equal("Don't stare though.")
	assert_str(entries[1]["speaker"]).is_equal("Leila")


func test_chatui_live_facade_stream() -> void:
	# The real LLM facade drives the same event path: tokens → say events → UI.
	var fake := FakeBackend.new()
	fake.chunks = PackedStringArray([TURN_JSON.substr(0, 80), TURN_JSON.substr(80)])
	var llm: Node = auto_free(LLMScript.new())
	add_child(llm)
	llm.set_backend(fake)
	var ui := await _new_chat()
	ui.set_reduced_motion(true)

	var say: SayScr = SayScr.new()
	say.beat_start.connect(func(i: int) -> void: ui.begin_beat(i))
	say.say_chunk.connect(func(i: int, t: String) -> void: ui.say_chunk(i, t))
	say.beat_end.connect(func(i: int) -> void: ui.end_beat(i))

	var seen_live := [false]
	say.say_chunk.connect(func(_i: int, _t: String) -> void: seen_live[0] = true)

	ui.input_box.text = "you ok?"
	ui.input_box.text_submitted.emit("you ok?")
	await get_tree().process_frame
	assert_bool(ui.text_box.is_showing_indicator()).is_true()

	var req := TurnRequest.new()
	req.messages = [{"role": "user", "content": "you ok?"}]
	var terminal := [&""]
	var stream: TurnStream = llm.generate(req)
	stream.token.connect(func(t: String) -> void: say.feed(t))
	stream.completed.connect(func(_t: String) -> void: terminal[0] = &"completed")
	stream.failed.connect(func(_e: Dictionary) -> void: terminal[0] = &"failed")
	stream.cancelled.connect(func() -> void: terminal[0] = &"cancelled")
	await _await_until(func() -> bool: return terminal[0] != &"")
	assert_str(String(terminal[0])).is_equal("completed")
	assert_bool(seen_live[0]).is_true()  # say events arrived while streaming
	ui.end_turn()
	await _await_until(func() -> bool: return not ui.is_turn_open())
	assert_int(ui.chat_log.entry_count()).is_equal(3)


func test_chatlog_scrolls_and_stores() -> void:
	var log: ScrollContainer = ChatLogScene.instantiate()
	log.custom_minimum_size = Vector2(0, 60)
	log.size = Vector2(300, 60)
	add_child(auto_free(log))
	await get_tree().process_frame
	await get_tree().process_frame
	for i: int in 40:
		log.append_entry(
			"her" if i % 2 == 0 else "player", "Leila" if i % 2 == 0 else "Senpai", "line %d" % i
		)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(log.entry_count()).is_equal(40)
	assert_str(log.get_entries()[5]["text"]).is_equal("line 5")
	var bar := log.get_v_scroll_bar()
	assert_float(bar.max_value).is_greater(bar.page)  # it actually scrolls
	assert_bool(log.is_at_end()).is_true()  # auto-followed to the newest line
	log.page_scroll(-1)
	assert_bool(log.scroll_vertical < int(bar.max_value - bar.page)).is_true()
	log.scroll_to_top()
	assert_int(log.scroll_vertical).is_equal(0)
	log.scroll_to_end()
	await get_tree().process_frame
	assert_bool(log.is_at_end()).is_true()


func test_chatlog_child_count_matches_entries_on_trim() -> void:
	# CODE-3: remove_child before queue_free when trimming past max_entries.
	var log: ScrollContainer = ChatLogScene.instantiate()
	log.max_entries = 3
	add_child(auto_free(log))
	await get_tree().process_frame
	for i: int in 5:
		log.append_entry("her", "Leila", "m%d" % i)
	assert_int(log.entry_count()).is_equal(3)
	var list: VBoxContainer = log.get_node("List")
	assert_int(list.get_child_count()).is_equal(3)
	assert_int(list.get_child_count()).is_equal(log.entry_count())


func test_keyboard_only_play() -> void:
	var ui := await _new_chat()
	var pauses := [0]
	var toggles: Array = []
	ui.pause_requested.connect(func() -> void: pauses[0] += 1)
	ui.log_toggled.connect(func(open: bool) -> void: toggles.append(open))
	assert_bool(ui.input_box.is_input_enabled()).is_true()
	assert_int(ui.input_box.focus_mode).is_equal(Control.FOCUS_ALL)  # keyboard target

	# Submit via the bound submit key path (Enter → text_submitted).
	ui.input_box.text = "keyboard only"
	ui.input_box.text_submitted.emit("keyboard only")
	await get_tree().process_frame
	assert_bool(ui.input_box.is_input_enabled()).is_false()

	# Enter fast-forwards the reveal once her text is streaming.
	ui.begin_beat(0)
	ui.say_chunk(0, "a long reply that would take a while to type out")
	ui._unhandled_input(_key(KEY_ENTER))
	assert_bool(ui.text_box.is_revealing()).is_false()
	ui.end_beat(0)
	ui.end_turn()
	await _await_until(func() -> bool: return not ui.is_turn_open())
	assert_bool(ui.input_box.is_input_enabled()).is_true()  # focus back for the next line

	# Tab toggles the scroll-back log.
	ui._unhandled_input(_key(KEY_TAB))
	assert_array(toggles).is_equal([false])
	assert_bool(ui.is_log_open()).is_false()
	ui._unhandled_input(_key(KEY_TAB))
	assert_bool(ui.is_log_open()).is_true()

	# DES-1: Tab while InputBox has focus toggles the log via _gui_input
	ui.input_box.grab_focus()
	assert_bool(ui.input_box.has_focus()).is_true()
	ui.input_box._gui_input(_key(KEY_TAB))
	assert_bool(ui.is_log_open()).is_false()
	ui.input_box._gui_input(_key(KEY_TAB))
	assert_bool(ui.is_log_open()).is_true()

	# PgUp/PgDn/Home/End scroll the log without the mouse.
	for i: int in 30:
		ui.chat_log.append_entry("her", "Leila", "filler %d" % i)
	await get_tree().process_frame
	await get_tree().process_frame
	var at_end: int = ui.chat_log.scroll_vertical
	ui._unhandled_key_input(_key(KEY_PAGEUP))
	assert_bool(ui.chat_log.scroll_vertical < at_end).is_true()
	ui._unhandled_key_input(_key(KEY_PAGEDOWN))
	ui._unhandled_key_input(_key(KEY_HOME))
	assert_int(ui.chat_log.scroll_vertical).is_equal(0)
	ui._unhandled_key_input(_key(KEY_END))
	await get_tree().process_frame
	assert_bool(ui.chat_log.is_at_end()).is_true()

	# Esc requests the safe pause at any moment (docs/05 §0).
	ui._unhandled_key_input(_key(KEY_ESCAPE))
	assert_int(pauses[0]).is_equal(1)
	ui.input_box._gui_input(_key(KEY_ESCAPE))
	assert_int(pauses[0]).is_equal(2)


func test_empty_turn_hides_indicator_and_drains() -> void:
	# CODE-1: Turn with zero say tokens hides indicator and closes cleanly.
	var ui := await _new_chat()
	var turn_displayed_fired := [false]
	ui.turn_displayed.connect(func() -> void: turn_displayed_fired[0] = true)
	ui.begin_turn_wait()
	assert_bool(ui.text_box.is_showing_indicator()).is_true()
	assert_bool(ui.is_turn_open()).is_true()

	ui.end_turn()
	await get_tree().process_frame
	assert_bool(ui.text_box.is_showing_indicator()).is_false()
	assert_bool(ui.is_turn_open()).is_false()
	assert_bool(ui.input_box.is_input_enabled()).is_true()
	assert_bool(turn_displayed_fired[0]).is_true()
	assert_str(ui.text_box.get_visible_text()).is_equal("")


func test_text_filter_runs_before_display_and_log() -> void:
	var ui := await _new_chat()
	ui.set_reduced_motion(true)
	# Safety.scan injection point (docs/07 §3.4): the filter is pluggable so
	# P1.19's real scanner drops in without a UI change; unsafe chunks never
	# reach the box or the log.
	ui.text_filter = func(chunk: String) -> String: return chunk.replace("die", "██████")
	ui.input_box.text = "hi"
	ui.input_box.text_submitted.emit("hi")
	ui.begin_beat(0)
	ui.say_chunk(0, "please die ")
	ui.say_chunk(0, "now")
	ui.end_beat(0)
	ui.end_turn()
	await _await_until(func() -> bool: return not ui.is_turn_open())
	var entries: Array = ui.chat_log.get_entries()
	assert_str(entries[1]["text"]).is_equal("please ██████ now")
	assert_str(ui.text_box.get_visible_text()).is_equal("please ██████ now")


func test_abort_turn_restores_input() -> void:
	var ui := await _new_chat()
	ui.input_box.text = "hello?"
	ui.input_box.text_submitted.emit("hello?")
	await get_tree().process_frame
	assert_bool(ui.input_box.is_input_enabled()).is_false()
	ui.begin_beat(0)
	ui.say_chunk(0, "part")
	ui.abort_turn()
	assert_bool(ui.input_box.is_input_enabled()).is_true()
	assert_bool(ui.is_turn_open()).is_false()
	assert_str(ui.text_box.get_visible_text()).is_equal("")
	# The aborted beat never enters the log.
	assert_int(ui.chat_log.entry_count()).is_equal(1)


func test_manual_say_stream_split_and_escapes() -> void:
	var say: SayScr = SayScr.new()
	var chunks: Array = []
	say.say_chunk.connect(func(_i: int, t: String) -> void: chunks.append(t))
	var starts: Array = []
	say.beat_start.connect(func(i: int) -> void: starts.append(i))
	var ends: Array = []
	say.beat_end.connect(func(i: int) -> void: ends.append(i))
	for pos: int in range(0, TURN_JSON.length(), 3):
		say.feed(TURN_JSON.substr(pos, 3))
	assert_array(starts).is_equal([0, 1])
	assert_array(ends).is_equal([0, 1])
	assert_str("".join(chunks)).is_equal("Hi! I waited all day for you.Don't stare though.")
