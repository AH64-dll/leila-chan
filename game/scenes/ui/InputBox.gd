extends LineEdit
## InputBox — the player's reply field (docs/07 §2). Submitting emits
## `submitted` with the trimmed text; the box clears and waits for
## set_input_enabled(true) once her turn ends.
##
## Typing telemetry hooks (docs/02 §4 step 0) live on the signals — Triggers
## (SYS) subscribes; the deleted draft stays in memory only and is discarded
## the moment it is used (docs/05 §0).

signal submitted(text: String)  ## Player sent a reply.
signal draft_changed(text: String)  ## Every edit while composing (idle/deleted-draft telemetry).
## The draft was erased without sending; carries the last words (docs/05 M21).
signal draft_deleted(text: String)
signal pause_requested  ## Esc — the owning scene opens the safe pause (docs/05 §0).
signal log_toggle_requested  ## Tab — toggle scroll-back log even when focused (DES-1).

var _enabled := true
var _draft_peak := ""
var _draft_last := ""


func _ready() -> void:
	text_changed.connect(_on_text_changed)
	text_submitted.connect(_on_text_submitted)


func configure(config: Dictionary) -> void:
	max_length = int(config.get("max_length", max_length))
	placeholder_text = str(config.get("placeholder", placeholder_text))


## Keyboard-only play: the field holds focus unless the game disables it.
func set_input_enabled(enabled: bool) -> void:
	_enabled = enabled
	editable = enabled
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if enabled and is_inside_tree() and get_viewport() != null:
		grab_focus()


func is_input_enabled() -> bool:
	return _enabled


func draft() -> String:
	return text


func clear_draft() -> void:
	text = ""
	_draft_peak = ""
	_draft_last = ""


func _on_text_changed(new_text: String) -> void:
	# Backspace erases one character per edit, so the edit that empties the box
	# only knows the last char. Keep the peak of the draft this edit continues
	# and drop it when the text is replaced wholesale (select-all then type or
	# paste) — the erased words must be the draft the player just gave up on.
	if not _continues_draft(new_text):
		_draft_peak = ""
	_draft_last = new_text
	if new_text.length() >= _draft_peak.length():
		_draft_peak = new_text
	if new_text.is_empty() and not _draft_peak.is_empty():
		# The signal carries the whole erased draft for M21. The box itself
		# keeps nothing — the draft is memory-only and dies with the emission.
		draft_deleted.emit(_draft_peak)
		_draft_peak = ""
	draft_changed.emit(new_text)


## True when `new_text` is still the same draft as the previous edit: a prefix
## of it (characters erased) or an extension of it (characters typed).
func _continues_draft(new_text: String) -> bool:
	return new_text.begins_with(_draft_last) or _draft_last.begins_with(new_text)


func _on_text_submitted(raw: String) -> void:
	var trimmed := raw.strip_edges()
	if trimmed.is_empty():
		return
	text = ""
	_draft_peak = ""
	_draft_last = ""
	submitted.emit(trimmed)


func _gui_input(event: InputEvent) -> void:
	# Esc reaches the box when it has focus; forward it so pause works at any
	# moment, including mid-draft (docs/05 §0).
	if event.is_action_pressed("ui_cancel"):
		pause_requested.emit()
		accept_event()
	elif (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_TAB
		and not event.shift_pressed
		and not event.ctrl_pressed
		and not event.alt_pressed
		and not event.meta_pressed
	):
		log_toggle_requested.emit()
		accept_event()
