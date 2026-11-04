extends Control
## MetaNotesPanel — the in-game half of docs/05 §1.4: the letter M31 writes and
## the diary M32 keeps are readable *inside* the game too ("the player can read
## them in-game too"; M31's own accessibility fallback is "shown as an in-game
## page the player can read and copy").
##
## Everything it shows comes from MetaEventsM31, which writes the files already
## scanned (docs/02 §8). The panel is an ordinary in-window Control: it never
## grabs `Esc` in `_input` (docs/05 §0 rule 3 — PauseMenu owns the key), never
## opens a second window and never pauses the tree. `ui_cancel` is handled in
## `_unhandled_input` only, as the documented fallback for a build without the
## PauseMenu autoload (ChatUI's convention).
##
## Layout is built in code, like PauseMenu's overlay: the screen is one more
## view of data the module already owns, not a new source of truth.

signal closed

const FONT_TITLE := 15
const FONT_BODY := 12
const LIST_HEIGHT := 150.0
const TEXT_HEIGHT := 260.0

var _source: Node = null
var _config: Dictionary = {}
var _list: VBoxContainer
var _body: RichTextLabel
var _title: Label
var _entries: Array[Dictionary] = []
var _selected := ""


func set_source(source: Node) -> void:
	_source = source


func _ready() -> void:
	_config = _load_ui()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_reload()


func open() -> void:
	show()
	_refresh_selection()
	var first: Node = _list.get_child(0) if _list != null and _list.get_child_count() > 0 else null
	if first is Button:
		(first as Button).grab_focus()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Labels come from the module (which owns the content file), never from a
## second parse of the data here: one reader, one source of copy.
func _load_ui() -> Dictionary:
	var out := {}
	for key: String in ["reader_title", "close", "empty", "in_memory"]:
		out[key] = _label(key)
	return out


func _label(key: String) -> String:
	if _source != null and _source.has_method("ui_string"):
		return String(_source.call("ui_string", key, ""))
	return ""


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 12
	frame.offset_top = 16
	frame.offset_right = -12
	frame.offset_bottom = -16
	add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	_title = Label.new()
	_title.text = String(_config.get("reader_title", "Her notes"))
	_title.add_theme_font_size_override("font_size", FONT_TITLE)
	column.add_child(_title)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	column.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	list_scroll.add_child(_list)

	var text_scroll := ScrollContainer.new()
	text_scroll.custom_minimum_size = Vector2(0, TEXT_HEIGHT)
	text_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(text_scroll)
	_body = RichTextLabel.new()
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", FONT_BODY)
	text_scroll.add_child(_body)

	var close_button := Button.new()
	close_button.text = String(_config.get("close", "Close"))
	close_button.pressed.connect(close)
	column.add_child(close_button)


func _reload() -> void:
	_entries.clear()
	for child: Node in _list.get_children():
		child.queue_free()
	if _source == null or not _source.has_method("notes"):
		return
	var rows: Variant = _source.call("notes")
	if not (rows is Array):
		return
	for row_variant: Variant in rows as Array:
		var row: Dictionary = row_variant
		_entries.append(row)
		var button := Button.new()
		button.text = String(row.get("title", ""))
		button.add_theme_font_size_override("font_size", FONT_BODY)
		button.pressed.connect(_on_entry_pressed.bind(String(row.get("id", ""))))
		_list.add_child(button)
	if _entries.is_empty():
		var empty := Label.new()
		empty.text = String(_config.get("empty", ""))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", FONT_BODY)
		_list.add_child(empty)
		_body.text = ""
		return
	_selected = String((_entries[0] as Dictionary).get("id", ""))
	_refresh_selection()


func _on_entry_pressed(id: String) -> void:
	_selected = id
	_refresh_selection()


func _refresh_selection() -> void:
	if _body == null:
		return
	var text := ""
	for row: Dictionary in _entries:
		if String(row.get("id", "")) != _selected:
			continue
		text = String(row.get("text", ""))
		if bool(row.get("in_memory", false)):
			_title.text = String(_config.get("reader_title", "Her notes"))
			text = text + "\n\n" + String(_config.get("in_memory", ""))
		break
	_body.text = text
	if _title.text.is_empty():
		_title.text = String(_config.get("reader_title", "Her notes"))
