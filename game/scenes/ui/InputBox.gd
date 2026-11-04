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
## docs/05 §1.3 M22: the box currently holds words SHE typed in. The flag keeps
## them out of the deleted-draft detector — the player erasing her suggestion is
## not a draft the player gave up on, and quoting her own line back at her as
## "what you were going to say" would be a lie the player never told.
var _foreign_draft := false
## True while `show_foreign_draft()` writes: the programmatic edit must not run
## the player's draft tracking or emit `draft_changed`.
var _writing_foreign := false


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


## Fill the box with her words (docs/05 §1.3 M22). The field stays editable and
## focused, so the player can always delete it — character by character or all
## at once — and nothing is ever submitted from here. The caret sits at the end
## so the blinking cursor reads as "someone is in here".
func show_foreign_draft(value: String) -> void:
	if not _enabled:
		return
	_writing_foreign = true
	text = value
	caret_column = value.length()
	_writing_foreign = false
	_foreign_draft = not value.is_empty()
	_draft_peak = ""
	_draft_last = value


func is_foreign_draft() -> bool:
	return _foreign_draft


func clear_draft() -> void:
	text = ""
	_draft_peak = ""
	_draft_last = ""
	_foreign_draft = false


func _on_text_changed(new_text: String) -> void:
	if _writing_foreign:
		# Our own fill (M22): not a player edit, so no telemetry and no draft.
		_draft_last = new_text
		return
	if _foreign_draft:
		# The player is editing/deleting words she typed. They are never the
		# player's deleted draft (docs/05 M21 must not quote her own line back),
		# so tracking stays silent until the box is theirs again.
		_draft_last = new_text
		if new_text.is_empty():
			_foreign_draft = false
			_draft_peak = ""
		draft_changed.emit(new_text)
		return
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
	_foreign_draft = false
	submitted.emit(trimmed)


func _gui_input(event: InputEvent) -> void:
	# Esc reaches the box when it has focus; forwarding it keeps pause working
	# mid-draft (docs/05 §0). `PauseMenu._input` consumes the key before this
	# point in a shipping build, so this is the documented fallback path.
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
