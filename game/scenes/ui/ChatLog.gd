extends ScrollContainer
## ChatLog — the scroll-back record of the conversation (docs/07 §2). Only
## fully *spoken* text lands here (Player lines on submit, her lines when the
## typewriter finishes the beat); partial streams are never stored. The log
## is the in-memory source for saves, M23/M24 edits and the Extras recap.

signal entries_changed  ## An entry was appended (tests and the save system).

var max_entries := 200
var page_scroll_ratio := 0.9

var _entries: Array = []  # {"speaker": String, "text": String} in order
var _speaker_colors := {"her": Color(0.85, 0.45, 0.5), "player": Color(0.62, 0.75, 0.9)}

@onready var _list: VBoxContainer = $List


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func configure(config: Dictionary) -> void:
	max_entries = int(config.get("max_entries", max_entries))
	page_scroll_ratio = float(config.get("page_scroll_ratio", page_scroll_ratio))


## Append one spoken line. speaker_key picks the colour; `speaker` is the
## name actually rendered ({player_name} for the player's lines).
func append_entry(speaker_key: String, speaker: String, text: String) -> void:
	var entry := {"speaker_key": speaker_key, "speaker": speaker, "text": text}
	_entries.append(entry)
	if _entries.size() > max_entries:
		_entries.pop_front()
		if _list != null and _list.get_child_count() > 0:
			var old_child := _list.get_child(0)
			_list.remove_child(old_child)
			old_child.queue_free()
	_render_entry(entry)
	entries_changed.emit()
	_scroll_to_end.call_deferred()


func get_entries() -> Array:
	return _entries.duplicate(true)


func entry_count() -> int:
	return _entries.size()


func clear_log() -> void:
	_entries.clear()
	if _list != null:
		for child: Node in _list.get_children():
			child.queue_free()


## Keyboard-only scroll: one viewport height per press (docs/05 §0 — every
## part of play works without the mouse).
func page_scroll(direction: int) -> void:
	var viewport_h := get_rect().size.y
	scroll_vertical += int(viewport_h * page_scroll_ratio) * direction


func scroll_to_top() -> void:
	scroll_vertical = 0


func scroll_to_end() -> void:
	_scroll_to_end()


func is_at_end() -> bool:
	var bar := get_v_scroll_bar()
	return scroll_vertical >= bar.max_value - bar.page - 1.0


func _scroll_to_end() -> void:
	if is_inside_tree():
		await get_tree().process_frame
	_apply_end_scroll()


func _apply_end_scroll() -> void:
	var bar := get_v_scroll_bar()
	scroll_vertical = int(bar.max_value - bar.page)


func _render_entry(entry: Dictionary) -> void:
	if _list == null:
		return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	var color: Color = _speaker_colors.get(str(entry["speaker_key"]), Color(0.8, 0.8, 0.8))
	var shown := "%s: %s" % [entry["speaker"], entry["text"]]
	label.text = shown
	label.add_theme_color_override("font_color", color.lightened(0.35))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_list.add_child(label)
