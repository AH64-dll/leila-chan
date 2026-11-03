extends Control
## ChatUI — the composed conversation UI (docs/07 §2): ChatLog on top,
## TextBox (NameTag + typewriter + typing indicator), InputBox at the bottom.
## The Date scene (P1.16) instantiates this and drives the Director-facing
## half; this composite owns wiring, stage data and keyboard-only play.
##
## Turn flow (docs/02 §4):
##   player submits → player_turn_sent(text) → log stores the line, input
##   locks, "Leila is typing…" shows → streamed begin_beat / say_chunk /
##   end_beat feed the typewriter → each fully-shown beat's spoken text lands
##   in the log → end_turn → when the last beat is on screen the input unlocks
##   and grabs focus again.

signal player_turn_sent(text: String)  ## The Director (SYS) starts the turn from this.
signal turn_displayed  ## Every beat of her reply is on screen; safe to enable input.
signal pause_requested  ## Esc pressed anywhere in the UI (docs/05 §0 — always opens safe pause).
signal log_toggled(open: bool)  ## Tab toggled the scroll-back log.

var stage := 0  # Instability stage from GameState — drives the indicator flavour
## Safety scan injection point (docs/07 §3.4): a driver that pre-scans may set
## a pass-through; unset warns once per turn that text arrived un-scanned.
## Date.gd sets the pass-through because SaySafetyGate (replies) and
## `_scan_opening_say` (opening beats) already scanned the text — P1.19 CODE-19.
var text_filter: Callable = Callable()

var _player_name := "Senpai"
var _leila_name := "Leila"
var _turn_open := false  # a turn is in flight (input locked, reply streaming)
var _end_pending := false  # end_turn() arrived; waiting for the last beat to display
var _log_open := true
var _config := {}
var _filter_warning_emitted_this_turn := false

@onready var chat_log: ScrollContainer = $Margin/VBox/ChatLog
@onready var text_box: PanelContainer = $Margin/VBox/TextBox
@onready var input_box: LineEdit = $Margin/VBox/InputBox


func _ready() -> void:
	_config = UiConfig.load_config()
	apply_config(_config)


func apply_config(config: Dictionary) -> void:
	_config = config
	_leila_name = str(config.get("names", {}).get("leila", "Leila"))
	_player_name = str(config.get("names", {}).get("default_player", "Senpai"))
	text_box.configure(config)
	chat_log.configure(config.get("chat_log", {}))
	input_box.configure(config.get("input", {}))
	if not input_box.submitted.is_connected(_on_input_submitted):
		input_box.submitted.connect(_on_input_submitted)
		input_box.pause_requested.connect(_on_pause_requested)
		input_box.log_toggle_requested.connect(_toggle_log)
		text_box.beat_displayed.connect(_on_beat_displayed)
		text_box.all_displayed.connect(_on_all_displayed)
	_log_open = true
	chat_log.visible = true
	input_box.set_input_enabled(true)


func set_stage(new_stage: int) -> void:
	stage = new_stage


func set_player_name(new_name: String) -> void:
	_player_name = new_name if not new_name.is_empty() else "Senpai"


func get_player_name() -> String:
	return _player_name


## ── Player side ───────────────────────────────────────────────────────────


func _on_input_submitted(text: String) -> void:
	if not input_box.is_input_enabled():
		return
	chat_log.append_entry("player", _player_name, text)
	begin_turn_wait()
	player_turn_sent.emit(text)


## Lock input and show the diegetic typing indicator until her first say
## token (docs/02 §4). Called on submit; the Director may also call it when a
## turn starts without player input (M30 monologue).
func begin_turn_wait() -> void:
	_turn_open = true
	_end_pending = false
	_filter_warning_emitted_this_turn = false
	input_box.set_input_enabled(false)
	text_box.reset()
	text_box.set_speaker(_leila_name)
	text_box.show_typing_indicator(_leila_name, stage)


## ── Streamed beat events (IncrementalJson order) ───────────────────────────


func begin_beat(beat_index: int) -> void:
	text_box.hide_typing_indicator()
	text_box.begin_beat(beat_index)


## say_chunk: model text passes the injected text_filter before it can reach
## the screen (docs/07 §3.4). The Director's SaySafetyGate scans upstream, so
## in production this seam is a pass-through marker, not a second scan.
func say_chunk(beat_index: int, chunk: String) -> void:
	var filtered := chunk
	if text_filter.is_valid():
		filtered = str(text_filter.call(chunk))
	else:
		if not _filter_warning_emitted_this_turn:
			_filter_warning_emitted_this_turn = true
			push_warning("ChatUI: text_filter unset — say chunk bypassed safety scan")
	text_box.say_chunk(beat_index, filtered)


## Overwrite a queued beat's text (docs/02 §7 post-stream repairs). Runs the
## same injected safety filter as say_chunk — corrected text is still model
## text and must never bypass the scan.
func replace_beat(beat_index: int, text: String) -> void:
	var filtered := text
	if text_filter.is_valid():
		filtered = str(text_filter.call(text))
	elif not _filter_warning_emitted_this_turn:
		_filter_warning_emitted_this_turn = true
		push_warning("ChatUI: text_filter unset — replace_beat bypassed safety scan")
	text_box.replace_beat_text(beat_index, filtered)


func end_beat(beat_index: int) -> void:
	text_box.end_beat(beat_index)


func end_turn() -> void:
	text_box.end_turn()
	_end_pending = true
	_maybe_close_turn()


## Turn died mid-stream (failed / cancelled): clear partial text, drop the
## indicator and hand control back (docs/05 §0 — never leave the player stuck).
func abort_turn() -> void:
	_turn_open = false
	_end_pending = false
	text_box.reset()
	_unlock_input()


## A line that never became a turn (docs/02 §4 step 0 safety rejection): the
## submit locked the input, so the refusal is shown as one short beat and the
## turn is ended — the same unlock path her reply takes. Self-sufficient: it
## drops whatever an earlier turn left queued, so a driver never has to clear
## the box first. The Director passes text it already scanned; no second scan.
func reject_turn(text: String) -> void:
	text_box.reset()
	begin_beat(0)
	replace_beat(0, text)
	end_beat(0)
	end_turn()


func _on_beat_displayed(beat_index: int) -> void:
	var spoken := str(text_box.get_beat_text(beat_index))
	if not spoken.is_empty():
		chat_log.append_entry("her", _leila_name, spoken)


func _on_all_displayed() -> void:
	_maybe_close_turn()


func _maybe_close_turn() -> void:
	if not _turn_open or not _end_pending:
		return
	if text_box.is_revealing():
		return
	_turn_open = false
	_end_pending = false
	text_box.hide_typing_indicator()
	_unlock_input()
	turn_displayed.emit()


func _unlock_input() -> void:
	input_box.set_input_enabled(true)


func is_turn_open() -> bool:
	return _turn_open


## ── Keyboard-only play and pause ───────────────────────────────────────────


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_pause_requested()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up") and _log_open:
		chat_log.page_scroll(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down") and _log_open:
		chat_log.page_scroll(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_home") and _log_open:
		chat_log.scroll_to_top()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_end") and _log_open:
		chat_log.scroll_to_end()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Tab toggles the scroll-back log (VNs always offer one).
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_log()
		get_viewport().set_input_as_handled()
	# Enter/Space while her text is revealing fast-forwards the typewriter.
	elif event.is_action_pressed("ui_accept") and text_box.is_revealing():
		text_box.reveal_now()
		get_viewport().set_input_as_handled()


func _toggle_log() -> void:
	_log_open = not _log_open
	chat_log.visible = _log_open
	log_toggled.emit(_log_open)


func is_log_open() -> bool:
	return _log_open


func _on_pause_requested() -> void:
	pause_requested.emit()


## Reduced-motion / instant mode for the typewriter (accessibility, docs/05 §0).
func set_reduced_motion(enabled: bool) -> void:
	text_box.set_instant(enabled)
