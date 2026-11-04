extends Control
## Ending — docs/01 §7's ending screen: the last beat of a run.
##
## The scene renders a decision, it does not make one. `Endings.evaluate()` owns
## which row a run reached (data: res://data/endings.json) and `EndingLog` owns
## the cross-run record; this node asks for both, writes the log exactly once per
## run, and shows what the data says. It re-renders from the run's own ending flag
## when there is one, so a save taken on this screen resumes this screen instead
## of re-deriving a different ending.
##
## Content is data: title and details from ui.json's `ending` block, the frame
## text from the row's `frame`, her last line from EndingLine — generated live,
## or the row's reviewed `final` when the model is absent, busy, slow or unsafe —
## and the reveal timing from the same block. Nothing here is ending prose.
##
## Accessibility: Esc always works (docs/05 §0 rule 3) and leaves for the Title —
## this screen has no pause menu yet (P3.13), and Night set that precedent. The
## clock is `advance_time(delta)` (`_process` forwards frames, tests step it), so
## the reveal is deterministic and cannot flake under load.

signal ending_started(record: Dictionary)
signal ending_recorded(record: Dictionary)
signal ending_finished(record: Dictionary)
signal pause_requested

const TITLE_SCENE_PATH := "res://scenes/Title.tscn"
const TITLE_SIZE := 26
const DETAIL_SIZE := 13
const FRAME_SIZE := 16
const FINAL_SIZE := 15
const SEEN_SIZE := 11
const EPS := 0.0001

## The NewGame/Night convention: a suite turns the scene change off and inspects
## the screen it built.
var scene_change_enabled := true
## The game lets _process run the clock; tests call advance_time() themselves.
var auto_advance := true

var _screen := {}
var _row := {}
var _record := {}
var _lines: Array[Dictionary] = []
var _revealed := 0
var _elapsed := 0.0
var _interval := 0.0
var _skip_after := 0.0
var _started := false
var _finished := false
## The last line's slot and its live request (P3.17). `_final_gate` is open when
## there is nothing to wait for: the reveal stops at the slot while it is closed,
## and the hold caps that wait so a hung model never strands the screen.
var _final_index := -1
var _final_label: Label = null
var _final_gate := true
var _final_waited := 0.0
var _final_hold := 0.0
var _stream: TurnStream = null

@onready var background: ColorRect = $Background
@onready var frame_box: VBoxContainer = $Margin/VBox/FrameBox
@onready var skip_hint: Label = $SkipHint


func _ready() -> void:
	set_process(false)
	_screen = UiConfig.load_config().get("ending", {})
	_fill_screen_texts()
	start_ending()


## Runs the ending once and returns the log record it shows. _ready() calls it;
## the guard makes a later direct call (the scene tests) a no-op.
func start_ending() -> Dictionary:
	if _started:
		return _record.duplicate(true)
	_started = true
	_resolve()
	_record = _record_run()
	_plan()
	ending_started.emit(_record.duplicate(true))
	if auto_advance:
		set_process(true)
	_reveal_due()
	_refresh_skip_hint()
	return _record.duplicate(true)


## The clock: _process forwards the frame delta, tests step it exactly.
func advance_time(delta: float) -> void:
	if _finished:
		return
	_elapsed += maxf(delta, 0.0)
	if not _final_gate:
		_final_waited += maxf(delta, 0.0)
		if _final_waited >= _final_hold:
			_open_final_gate()
	_reveal_due()
	_refresh_skip_hint()


## The player's continue. Only after the data's window, so the ending is never
## skipped by the click that opened it. Returns whether the screen finished.
func skip() -> bool:
	if not _can_skip():
		return false
	_finish()
	return true


## The texts on the screen, in order — the test seam for what the player sees.
func visible_lines() -> Array[String]:
	var out: Array[String] = []
	if frame_box == null:
		return out
	for child: Node in frame_box.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func is_finished() -> bool:
	return _finished


## The ending row this screen is showing ({} when the state names none).
func ending_row() -> Dictionary:
	return _row.duplicate(true)


## The log record as displayed ("count" 0 when nothing was recorded).
func log_record() -> Dictionary:
	return _record.duplicate(true)


## Her last line as the screen has it ("" before planning and for a row with no
## content): the test seam for "the live line replaced the scripted one".
func final_line() -> String:
	if _final_index < 0 or _final_index >= _lines.size():
		return ""
	return String(_lines[_final_index].get("text", ""))


## True once the last line has its answer (or the data's hold ran out). Before
## that the reveal legitimately stops at the slot, which is what keeps the screen
## from showing the scripted line a tick before the live one.
func is_final_ready() -> bool:
	return _final_gate


func _process(delta: float) -> void:
	if auto_advance:
		advance_time(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey
	if event.is_action_pressed("ui_cancel") or key.keycode == KEY_ESCAPE:
		_request_pause()
		return
	if event.is_action_pressed("ui_accept") or key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
		if skip() and get_viewport() != null:
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if skip() and get_viewport() != null:
			get_viewport().set_input_as_handled()


## docs/05 §0 rule 3: Esc always works. This screen has no pause menu yet, so the
## safe behaviour is to leave for the Title rather than hold the player.
func _request_pause() -> void:
	pause_requested.emit()
	if not _finished:
		_finish()
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


## The row to show: the run's own ending when the flag names one (a resumed save,
## or a forced state), else the evaluator's answer for the current state.
func _resolve() -> void:
	var stored := String(GameState.get_flag(Endings.FLAG_ENDING, "")).strip_edges()
	_row = Endings.get_ending(stored)
	if _row.is_empty():
		var decision := Endings.evaluate(GameState.to_dict(), Endings.PHASE_CAMPAIGN_END)
		_row = Endings.get_ending(String(decision.get("id", "")))
	if _row.is_empty():
		push_warning("Ending: no ending row matches this state and none is flagged")
		return
	GameState.set_flag(Endings.FLAG_ENDING, String(_row.get("id", "")))


## The cross-run record: written the first time this run shows the ending, read
## back on every later visit (a resumed save must not count twice). Returns the
## record the screen displays.
func _record_run() -> Dictionary:
	var id := String(_row.get("id", ""))
	if id.is_empty():
		return {}
	var already := bool(GameState.get_flag(Endings.FLAG_RECORDED, false))
	var summary := {"day": int(GameState.day), "stage": int(GameState.stage)}
	var written := EndingLog.record_of(id)
	if not already:
		written = EndingLog.record(_row, summary)
		GameState.set_flag(Endings.FLAG_RECORDED, true)
		ending_recorded.emit(written.duplicate(true))
	_save_moment()
	return written


## The ending is a scene like any other as far as Continue is concerned: this
## autosave is what makes "quit on the ending, Continue" come back here instead
## of to a date that is already over. Written after the flags are set.
func _save_moment() -> void:
	var result := SaveSystem.autosave(SaveSystem.SCENE_ENDING, {})
	if bool(result.get("ok", false)) or String(result.get("error", "")) == "disabled":
		return
	push_warning("Ending: autosave skipped — %s" % String(result.get("message", "")))


## The reveal plan: one line at a time, from the run's own facts and the row's
## content. `_reveal_due()` walks it on the clock.
func _plan() -> void:
	_lines.clear()
	_revealed = 0
	_elapsed = 0.0
	_final_index = -1
	_final_label = null
	_final_gate = true
	_final_waited = 0.0
	_interval = maxf(0.0, float(_screen.get("line_interval_s", 0.9)))
	_skip_after = maxf(0.0, float(_screen.get("skip_after_s", 1.5)))
	_final_hold = maxf(0.0, float(_screen.get("final_hold_s", 0.0)))
	if _row.is_empty():
		_add_line(String(_screen.get("title_fallback", "The End")), "title")
		_add_line(String(_screen.get("unknown", "")), "frame")
		return
	_add_line(String(_row.get("name", "")), "title")
	_add_line(_detail_text(), "detail")
	var frame := String(_row.get("frame", "")).strip_edges()
	if not frame.is_empty():
		_add_line(frame, "frame")
	_plan_final()
	_add_line(_seen_text(), "seen")


## Her last line. The row's reviewed `final` is on the plan from the start, so a
## model that never answers costs nothing; a live answer replaces it before the
## slot is revealed (and, if it is already on screen, the label is rewritten).
func _plan_final() -> void:
	var line := EndingLine.fallback(_row, _player_name())
	var live := EndingLine.has_direction(_row)
	if line.is_empty() and not live:
		return
	_lines.append({"text": line, "style": "final"})
	_final_index = _lines.size() - 1
	if live:
		_request_final_line()


## One request, one line, no history: the run is over, so the ending is the only
## thing left to say. The stream is cancelled on leave — LLM holds one turn at a
## time, and a screen the player has left must not keep the next turn waiting.
func _request_final_line() -> void:
	var llm: Node = get_node_or_null("/root/LLM")
	if llm == null or not llm.has_method("generate") or not bool(llm.call("has_backend")):
		return
	var request := EndingLine.build_request(
		_row, _player_name(), int(GameState.stage), String(_row.get("path", ""))
	)
	if request == null:
		return
	var stream: Variant = llm.call("generate", request)
	if not stream is TurnStream:
		return
	_stream = stream
	_stream.completed.connect(_on_final_completed)
	_stream.failed.connect(_on_final_failed)
	_stream.cancelled.connect(_on_final_cancelled)
	_final_gate = false


func _on_final_completed(full_text: String) -> void:
	_stream = null
	var line := EndingLine.parse(full_text)
	var scanned := EndingLine.scan(line, int(GameState.stage))
	if bool(scanned.get("ok", false)):
		_apply_final_line(String(scanned.get("text", "")))
	_open_final_gate()


func _on_final_failed(_error: Dictionary) -> void:
	_stream = null
	_open_final_gate()


func _on_final_cancelled() -> void:
	_stream = null
	_open_final_gate()


func _apply_final_line(text: String) -> void:
	var line := text.strip_edges()
	if _final_index < 0 or line.is_empty():
		return
	_lines[_final_index]["text"] = line
	if _revealed > _final_index and _final_label != null and is_instance_valid(_final_label):
		_final_label.text = line


func _open_final_gate() -> void:
	_final_gate = true
	if _finished:
		return
	_reveal_due()
	_refresh_skip_hint()


## docs/01 §1/§7: the run's own coordinates — the path the ending belongs to,
## the day it ended and the stage's name (a stage number means nothing to a
## player, docs/01 §3's name does).
func _detail_text() -> String:
	var path := String(_row.get("path", Endings.ANY_PATH))
	var path_text := path
	if path == Endings.ANY_PATH:
		path_text = String(_screen.get("any_path", "Any path"))
	var values := {
		"path": path_text,
		"day": int(GameState.day),
		"stage": Stages.name_of(int(GameState.stage)),
	}
	return String(_screen.get("path_format", "{path} · Day {day} · {stage}")).format(values)


func _seen_text() -> String:
	var count := int(_record.get("count", 0))
	if count <= 1:
		return String(_screen.get("seen_first", "First time"))
	return String(_screen.get("seen_format", "Seen {count}×")).format({"count": count})


func _add_line(text: String, style: String) -> void:
	if text.strip_edges().is_empty():
		return
	_lines.append({"text": text, "style": style})


func _reveal_due() -> void:
	while _revealed < _lines.size():
		if _elapsed + EPS < _interval * float(_revealed):
			return
		if _revealed == _final_index and not _final_gate:
			return
		var line: Dictionary = _lines[_revealed]
		if not String(line.get("text", "")).is_empty():
			_render(line, _revealed)
		_revealed += 1


func _render(line: Dictionary, index: int) -> void:
	if frame_box == null:
		return
	var style := String(line.get("style", "frame"))
	var label := Label.new()
	label.text = String(line.get("text", ""))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match style:
		"title":
			label.add_theme_font_size_override("font_size", TITLE_SIZE)
			label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.25))
		"detail":
			label.add_theme_font_size_override("font_size", DETAIL_SIZE)
			label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.74))
		"final":
			label.add_theme_font_size_override("font_size", FINAL_SIZE)
			label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.8))
		"seen":
			label.add_theme_font_size_override("font_size", SEEN_SIZE)
			label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.58))
		_:
			label.add_theme_font_size_override("font_size", FRAME_SIZE)
			label.add_theme_color_override("font_color", Color(0.87, 0.85, 0.9))
	frame_box.add_child(label)
	if index == _final_index:
		_final_label = label


## The skip window is data; a null window means the reveal is the ending.
func _can_skip() -> bool:
	if _finished or _revealed < _lines.size():
		return false
	return _elapsed + EPS >= _skip_after


func _refresh_skip_hint() -> void:
	if skip_hint != null:
		skip_hint.visible = _can_skip()


## Leaves for the Title. Deferred so the change never lands inside this node's
## own signal emission.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	_release_final_stream()
	if skip_hint != null:
		skip_hint.visible = false
	ending_finished.emit(_record.duplicate(true))
	if scene_change_enabled:
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE_PATH)


## LLM serves one turn at a time; a screen that has been left must hand the slot
## back, or the next turn would fail with `busy`.
func _exit_tree() -> void:
	_release_final_stream()


func _release_final_stream() -> void:
	if _stream != null and not _stream.is_finished():
		_stream.cancel()
	_stream = null


func _player_name() -> String:
	var name := String(GameState.player_name).strip_edges()
	return name if not name.is_empty() else EndingLine.DEFAULT_PLAYER_NAME


func _fill_screen_texts() -> void:
	if skip_hint != null:
		skip_hint.text = String(_screen.get("skip_hint", ""))
		skip_hint.visible = false
