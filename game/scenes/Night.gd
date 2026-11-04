extends Control
## Night — docs/01 §1's night screen: the between-days beat of the day/night loop.
##
## The scene owns the presentation and the clock, never the rules: NightLoop
## resolves the night (meters → stage → path → overnight event) and returns an
## ordered report; OvernightEvents supplies the event's rows and the screen's
## strings from res://data/night.json. This node renders the report's event on
## black, holds it, shows the morning line, then hands the loop on — to the next
## day's Date, or to the campaign's end.
##
## Accessibility: Esc always works (docs/05 §0 rule 3) and ends the night, N12's
## ten seconds included, because this screen has no pause menu yet (P3.13) and a
## screen that ignores the player is worse than a skipped beat. The skip window and
## the hold are data; the timeline is driven by advance_time(), which tests step
## exactly instead of waiting on the wall clock.

signal night_started(report: Dictionary)
signal overnight_started(event: Dictionary)
signal night_finished(report: Dictionary)
signal campaign_completed(report: Dictionary)
signal pause_requested

const DATE_SCENE_PATH := "res://scenes/Date.tscn"
## docs/01 §7's endings are P3.16's deliverable. Until the ending scene exists the
## loop's last night returns to the title screen instead of stranding the player on
## a black one; campaign_completed carries the report for P3.16 to take over.
const AFTER_CAMPAIGN_SCENE_PATH := "res://scenes/Title.tscn"

const PHASE_IDLE := 0
const PHASE_EVENT := 1
const PHASE_MORNING := 2
const PHASE_DONE := 3
const EPS := 0.0001

## Test seam: pin the night's event ("" = the table's own pick by weight).
@export var event_override := ""

## The NewGame/Title convention: a suite turns the scene change off and inspects
## the screen it built.
var scene_change_enabled := true
## The game lets _process run the clock; tests call advance_time() themselves.
var auto_advance := true

var _night: NightLoop
var _report: Dictionary = {}
var _event: Dictionary = {}
var _messages: Array[Dictionary] = []
var _revealed := 0
var _interval := 0.0
var _elapsed := 0.0
var _event_end := 0.0
var _morning_end := -1.0
var _morning := ""
var _phase := PHASE_IDLE
var _started := false
var _finished := false

@onready var background: ColorRect = $Background
@onready var day_label: Label = $Margin/VBox/DayLabel
@onready var night_label: Label = $Margin/VBox/NightLabel
@onready var event_box: VBoxContainer = $Margin/VBox/EventBox
@onready var skip_hint: Label = $SkipHint


func _ready() -> void:
	set_process(false)
	_fill_screen_texts()
	start_night()


## Runs the night once and returns its report. _ready() calls it directly (the
## scene is in the tree, so a warning or the autosave has a path); the guard makes
## a later direct call (the scene tests) a no-op.
func start_night() -> Dictionary:
	if _started:
		return _report.duplicate(true)
	_started = true
	_night = NightLoop.new(GameState)
	_report = _night.resolve()
	if _report.is_empty():
		_finish()
		return {}
	_event = _event_for_report()
	_plan()
	day_label.text = String(OvernightEvents.screen()["day_label"]).format(
		{"day": int(_report.get("day", 0))}
	)
	night_started.emit(_report.duplicate(true))
	if not _event.is_empty():
		overnight_started.emit(_event.duplicate(true))
	_queue_next_day()
	_phase = PHASE_EVENT
	if auto_advance:
		set_process(true)
	_reveal_due()
	_refresh_skip_hint()
	return _report.duplicate(true)


## The clock: _process forwards the frame delta, tests step it exactly.
func advance_time(delta: float) -> void:
	if _phase != PHASE_EVENT and _phase != PHASE_MORNING:
		return
	_elapsed += maxf(delta, 0.0)
	while true:
		if _phase == PHASE_EVENT:
			_reveal_due()
			if _elapsed < _event_end:
				break
			if _morning_end < 0.0:
				_finish()
				return
			_phase = PHASE_MORNING
			_show_morning()
			continue
		if _phase == PHASE_MORNING:
			if _elapsed < _morning_end:
				break
			_finish()
			return
		break
	_refresh_skip_hint()


## The player's skip. Only after the data's window: N12's ten seconds ARE the
## event, so it is never click-skippable (Esc still ends the night). Returns
## whether the night moved on.
func skip() -> bool:
	if not _can_skip():
		return false
	_finish()
	return true


## The texts on the black, in order — the test seam for what the player sees.
func visible_lines() -> Array[String]:
	var out: Array[String] = []
	if event_box == null:
		return out
	for child: Node in event_box.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func is_finished() -> bool:
	return _finished


func _process(delta: float) -> void:
	if not auto_advance:
		return
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
## safe behaviour is to move the loop on rather than hold the player on a screen
## that ignores them — the black ten seconds included.
func _request_pause() -> void:
	pause_requested.emit()
	if not _finished:
		_finish()
	if get_viewport() != null:
		get_viewport().set_input_as_handled()


## The event to render: the table's pick, or the test's pinned row.
func _event_for_report() -> Dictionary:
	if not event_override.strip_edges().is_empty():
		var pinned := OvernightEvents.get_event(event_override)
		if not pinned.is_empty():
			_report["event"] = pinned
			return pinned
		push_warning("Night: the table has no overnight event '%s'" % event_override)
	var picked: Variant = _report.get("event", {})
	return picked if picked is Dictionary else {}


## The timeline, computed once from data: each message's reveal second (i × the
## interval), the black screen's duration, the shared hold after the event, then
## the morning line when the day after exists.
func _plan() -> void:
	var screen := OvernightEvents.screen()
	var hold := float(screen["hold_s"])
	_messages.clear()
	_revealed = 0
	_morning_end = -1.0
	var kind := String(_event.get("kind", ""))
	if kind == "messages":
		_interval = float(
			_event.get("message_interval_s", OvernightEvents.DEFAULT_MESSAGE_INTERVAL_S)
		)
		_messages = OvernightEvents.messages(
			_event, int(GameState.stage), String(GameState.path), String(GameState.player_name)
		)
		_event_end = _interval * maxf(0.0, float(_messages.size() - 1)) + hold
	elif kind == "black":
		_event_end = float(_event.get("duration_s", 0.0))
	else:
		_event_end = hold
	_morning = _morning_text()
	if not _morning.is_empty():
		_morning_end = _event_end + hold


## docs/01 §6.3: N12's "good morning." is the next day starting; on the campaign's
## last night there is no morning, so the screen promises none.
func _morning_text() -> String:
	if bool(_report.get("campaign_over", false)):
		return ""
	if _event.has("morning_line"):
		return String(_event["morning_line"])
	return String(OvernightEvents.screen()["morning_line"])


func _reveal_due() -> void:
	while _revealed < _messages.size():
		if _elapsed + EPS < _interval * float(_revealed):
			return
		_add_message(_messages[_revealed])
		_revealed += 1


func _add_message(row: Dictionary) -> void:
	var screen := OvernightEvents.screen()
	var text := String(row.get("text", ""))
	var time := String(row.get("time", ""))
	if time.is_empty():
		_add_line(text, true)
		return
	_add_line(String(screen["message_format"]).format({"time": time, "text": text}), true)


func _add_line(text: String, is_message: bool) -> void:
	if text.strip_edges().is_empty() or event_box == null:
		return
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15 if is_message else 19)
	var color := Color(0.87, 0.85, 0.9) if is_message else Color(0.55, 0.52, 0.58)
	label.add_theme_color_override("font_color", color)
	event_box.add_child(label)


func _show_morning() -> void:
	_add_line(_morning, false)


## The skip window is data; a null window means the wait is the event.
func _can_skip() -> bool:
	if _finished or _phase == PHASE_IDLE:
		return false
	var after: Variant = _event.get("skip_after_s", OvernightEvents.screen()["skip_after_s"])
	if after == null:
		return false
	return _elapsed + EPS >= float(after)


func _refresh_skip_hint() -> void:
	if skip_hint != null:
		skip_hint.visible = _can_skip()


## docs/01 §1: the new day's date is picked by availability and queued for the
## Date; the autosave carries it, so Continue lands on the same date. The last
## night saves nothing: there is no next day to resume into (P3.16 owns the end).
func _queue_next_day() -> void:
	if bool(_report.get("campaign_over", false)):
		return
	var next: Dictionary = Campaign.new(GameState).next_scenario()
	if next.is_empty():
		push_warning("Night: no scenario is available for day %d" % int(_report.get("day", 0)))
		return
	_report["next_scenario"] = next
	var result := SaveSystem.autosave(
		SaveSystem.SCENE_NIGHT, {"scenario": String(next.get("path", "")), "turn": 0}
	)
	if bool(result.get("ok", false)) or String(result.get("error", "")) == "disabled":
		return
	push_warning("Night: autosave skipped — %s" % String(result.get("message", "")))


## Hands the loop on: the next day's Date, the campaign's end, or nothing at all
## when the scene change is off (a test inspecting the screen). Deferred so the
## change never lands inside this node's own signal emission.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	_phase = PHASE_DONE
	set_process(false)
	if skip_hint != null:
		skip_hint.visible = false
	night_finished.emit(_report.duplicate(true))
	var over := bool(_report.get("campaign_over", false))
	if over:
		campaign_completed.emit(_report.duplicate(true))
	if not scene_change_enabled:
		return
	if over:
		get_tree().change_scene_to_file.call_deferred(AFTER_CAMPAIGN_SCENE_PATH)
		return
	get_tree().change_scene_to_file.call_deferred(DATE_SCENE_PATH)


func _fill_screen_texts() -> void:
	var screen := OvernightEvents.screen()
	night_label.text = String(screen["night_label"])
	day_label.text = ""
	skip_hint.text = String(screen["skip_hint"])
	skip_hint.visible = false
