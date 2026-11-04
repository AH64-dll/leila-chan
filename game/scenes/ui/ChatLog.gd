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
	_push({"speaker_key": speaker_key, "speaker": speaker, "text": text})
	entries_changed.emit()
	_scroll_to_end.call_deferred()


## Rebuild the scroll-back from a save (P2.20). The entries are the lines that
## were already on screen, so they are restored as-is: they were scanned for
## safety when they were shown, and a second scan could redact them again.
func restore_entries(entries: Array) -> void:
	clear_log()
	for item: Variant in entries:
		if not item is Dictionary:
			continue
		var entry := item as Dictionary
		var text := str(entry.get("text", ""))
		if text.is_empty():
			continue
		var key := str(entry.get("speaker_key", "her"))
		if key != "player" and key != "her":
			key = "her"
		var speaker := str(entry.get("speaker", ""))
		if speaker.is_empty():
			speaker = "Leila" if key == "her" else "You"
		_push({"speaker_key": key, "speaker": speaker, "text": text})
	entries_changed.emit()
	_scroll_to_end.call_deferred()


func get_entries() -> Array:
	return _entries.duplicate(true)


func entry_count() -> int:
	return _entries.size()


## Redraws every line from the stored entries (docs/05 §1.3 M23/M24). The
## entries themselves do not change: her version is a `MetaLogEdits` display
## override, so the log keeps the words the player wrote and a restore is only a
## ledger change plus this redraw.
func rerender() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for entry: Dictionary in _entries:
		_render_entry(entry)
	_scroll_to_end.call_deferred()


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


## Store and render one entry without signalling: `append_entry` speaks for one
## live line, `restore_entries` for a whole save (one signal, one scroll).
## `occurrence` is the 1-based count of earlier entries with the same speaker and
## text: MetaLogEdits keys the docs/05 §1.3 rewrites by it, so two identical
## player lines stay distinguishable without an id in the save format.
func _push(entry: Dictionary) -> void:
	entry["occurrence"] = _occurrence_of(entry)
	_entries.append(entry)
	if _entries.size() > max_entries:
		_entries.pop_front()
		if _list != null and _list.get_child_count() > 0:
			var old_child := _list.get_child(0)
			_list.remove_child(old_child)
			old_child.queue_free()
	_render_entry(entry)


func _occurrence_of(entry: Dictionary) -> int:
	var count := 1
	for stored: Dictionary in _entries:
		if (
			str(stored.get("speaker_key", "")) == str(entry.get("speaker_key", ""))
			and str(stored.get("text", "")) == str(entry.get("text", ""))
		):
			count += 1
	return count


func _render_entry(entry: Dictionary) -> void:
	if _list == null:
		return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	var key := str(entry["speaker_key"])
	var color: Color = _speaker_colors.get(key, Color(0.8, 0.8, 0.8))
	var text := MetaLogEdits.shown(key, str(entry["text"]), int(entry.get("occurrence", 1)))
	var shown := "%s: %s" % [entry["speaker"], text]
	label.text = shown
	label.add_theme_color_override("font_color", color.lightened(0.35))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_list.add_child(label)
