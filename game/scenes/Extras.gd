extends Control
## Extras — the after-the-run menu (docs/05 §0 rule 5: what happened is reviewable;
## docs/05 §3: the Extras menu after the credits; docs/07 §1 lists Extras.tscn).
##
## The screen is a view of EndingLog: one row per docs/01 §7 ending, unlocked by
## having reached it, plus the secret row whose unlock rule is its own data
## (`requires.paths`). Locked rows show the data's placeholder, never a name —
## the point of a gallery is that it does not spoil what has not happened. Meta
## events (docs/05 §3's other Extras content) arrive with P3.09's event log; this
## screen is the host it will add a section to.
##
## Nothing is written here: the log is the record, this is the reading.

signal extras_opened
signal back_requested

const TITLE_SCENE_PATH := "res://scenes/Title.tscn"
const ROW_NAME_WIDTH := 150.0
const COLOR_SEEN := Color(0.9, 0.85, 0.9)
const COLOR_LOCKED := Color(0.45, 0.43, 0.47)
const COLOR_DETAIL := Color(0.55, 0.52, 0.58)

## The NewGame/Title convention: a suite turns the scene change off and inspects
## the screen it built.
var scene_change_enabled := true

var _screen := {}
var _ending_screen := {}
var _entries: Array[Dictionary] = []
var _seen := 0

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var subtitle_label: Label = $Margin/VBox/SubtitleLabel
@onready var progress_label: Label = $Margin/VBox/ProgressLabel
@onready var rows_box: VBoxContainer = $Margin/VBox/Scroll/Rows
@onready var back_button: Button = $Margin/VBox/BackButton


func _ready() -> void:
	var config := UiConfig.load_config()
	_screen = config.get("extras", {})
	_ending_screen = config.get("ending", {})
	_apply_texts()
	back_button.pressed.connect(_on_back_pressed)
	refresh()
	back_button.grab_focus()
	extras_opened.emit()


## Rebuilds the list from the log. Public so a test (and a future "she rewrote
## the menu" event) can re-render without rebuilding the scene.
func refresh() -> void:
	_entries.clear()
	_seen = 0
	for child: Node in rows_box.get_children():
		child.queue_free()
	var total := 0
	for row: Dictionary in Endings.rows():
		if String(row.get("kind", "")) != Endings.KIND_ENDING:
			continue
		total += 1
		var record := EndingLog.record_of(String(row.get("id", "")))
		var unlocked := not record.is_empty()
		if unlocked:
			_seen += 1
		var entry := _entry_for(row, record, unlocked)
		_entries.append(entry)
		_add_row(entry)
	var secret := Endings.secret_row()
	if not secret.is_empty():
		var secret_entry := _secret_entry(secret)
		_entries.append(secret_entry)
		_add_row(secret_entry)
	if _seen == 0:
		progress_label.text = String(_screen.get("empty", ""))
		return
	var values := {"seen": _seen, "total": total}
	progress_label.text = String(_screen.get("progress", "{seen} / {total} endings")).format(values)


## The rows as built (id, name, detail, unlocked, secret) — the test seam.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		out.append(entry.duplicate(true))
	return out


func progress_text() -> String:
	return progress_label.text if progress_label != null else ""


func _entry_for(row: Dictionary, record: Dictionary, unlocked: bool) -> Dictionary:
	var id := String(row.get("id", ""))
	var path := String(row.get("path", Endings.ANY_PATH))
	if path == Endings.ANY_PATH:
		path = String(_ending_screen.get("any_path", "Any path"))
	var name := String(row.get("name", "")) if unlocked else String(_screen.get("locked", "???"))
	var detail := String(_screen.get("locked_detail", ""))
	if unlocked:
		var count := int(record.get("count", 0))
		var values := {"count": count, "day": int(record.get("day", 0)), "path": path}
		var format := "detail_first" if count <= 1 else "detail_format"
		detail = String(_screen.get(format, "")).format(values)
	return {"id": id, "name": name, "detail": detail, "unlocked": unlocked, "secret": false}


## The secret's rule lives in its row (`requires.paths`); the fact lives in the
## log. Locked, it shows the condition — that is the one unlock that can be
## chased deliberately, so it may not be a mystery box.
func _secret_entry(secret: Dictionary) -> Dictionary:
	var available := Endings.secret_available(EndingLog.seen_paths())
	var key := "secret_unlocked" if available else "secret_locked"
	return {
		"id": String(secret.get("id", "")),
		"name": String(_screen.get("secret_title", String(secret.get("name", "")))),
		"detail": String(_screen.get(key, "")),
		"unlocked": available,
		"secret": true,
	}


func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = String(entry.get("name", ""))
	name_label.custom_minimum_size = Vector2(ROW_NAME_WIDTH, 0)
	name_label.modulate = COLOR_SEEN if bool(entry.get("unlocked", false)) else COLOR_LOCKED
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var detail := Label.new()
	detail.text = String(entry.get("detail", ""))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", COLOR_DETAIL)
	row.add_child(name_label)
	row.add_child(detail)
	rows_box.add_child(row)


func _apply_texts() -> void:
	if title_label != null:
		title_label.text = String(_screen.get("title", "Extras"))
	if subtitle_label != null:
		subtitle_label.text = String(_screen.get("subtitle", ""))
	if back_button != null:
		back_button.text = String(_screen.get("btn_back", "Back"))


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("ui_cancel")
		or (
			event is InputEventKey
			and event.pressed
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		_on_back_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	back_requested.emit()
	if scene_change_enabled:
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE_PATH)
