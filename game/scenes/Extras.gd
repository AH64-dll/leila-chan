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
	_add_log_edits_section()
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


## docs/05 §0 rule 5 + §1.3 M23/M24: every line she rewrote, with the words the
## player actually wrote — the "what happened" review the Extras menu owes them.
func log_edits() -> Array:
	return MetaLogEdits.rows()


## Put the player's words back. The log entries never lost them — her version is
## a display override — so this clears the ledger, repaints a live log if one is
## still in the tree, and re-renders this page. Returns how many lines were
## restored (0 when there was nothing to undo).
func restore_log_edits() -> int:
	var restored := MetaLogEdits.restore_all()
	var ui := _live_chat_ui()
	if ui != null:
		var log_node: Variant = ui.get("chat_log")
		if log_node is Node and (log_node as Node).has_method("rerender"):
			(log_node as Node).call("rerender")
	refresh()
	return restored


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


## ── docs/05 §1.3 M23/M24: her edits, and the way back ─────────────────────


## One read-only row per rewrite (her version next to yours) plus the restore
## button. Nothing here is written: the ledger is read, `restore_log_edits()`
## is the only mutation and it only ever clears.
func _add_log_edits_section() -> void:
	rows_box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = String(_screen.get("log_edits_title", "What she changed"))
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COLOR_SEEN)
	rows_box.add_child(title)
	var rows := MetaLogEdits.rows()
	if rows.is_empty():
		var empty := Label.new()
		empty.text = String(
			_screen.get("log_edits_empty", "Nothing. Every line in the log is yours.")
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", COLOR_DETAIL)
		rows_box.add_child(empty)
		return
	var template := String(
		_screen.get("log_edits_row", 'You wrote: "{original}" — the log reads: "{edited}"')
	)
	for row: Dictionary in rows:
		var label := Label.new()
		label.text = (
			template
			. format(
				{
					"original": String(row.get("original", "")),
					"edited": String(row.get("edited", "")),
				}
			)
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", COLOR_DETAIL)
		rows_box.add_child(label)
	var button := Button.new()
	button.text = String(_screen.get("log_edits_restore", "Restore my words"))
	button.pressed.connect(_on_restore_log_edits)
	rows_box.add_child(button)


func _on_restore_log_edits() -> void:
	restore_log_edits()


## The live conversation, when Extras was opened without the Date having been
## freed (a test, or a future in-game Extras entry). Absent is normal: after the
## credits the log on disk is the save's, and the ledger restore is what matters.
func _live_chat_ui() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"chat_ui"):
		return node
	return null


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
