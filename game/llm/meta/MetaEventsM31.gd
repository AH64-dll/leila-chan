extends Node
## MetaEventsM31 — docs/05 §1.4–§1.5: the meta events that leave the text box
## through the game's own folder and the real clock.
##
##   M31 a letter      offered (`write_note`) → `user://letters/for_<name>.txt`
##   M32 her diary     scripted at St 3 → `user://diary/day_NN.txt` (her `inner`)
##   M33 save names    scripted at St 4 → `user://saves/meta_names.json`
##   M34 other player  scripted at St 4 / AWAKE → a pre-seeded FICTION slot
##   M35 real clock    the sky tint + her greeting's time of day
##   M36 3 AM          inside 02:00–04:00 → night line, instability, music_box
##   M37 birthday      a birthday the player told her, on that real date
##   M38 long session  two hours straight
##
## Mounted by `MetaDirector._mount_effects()` (the seam is the file path). This
## node owns detection and effects; the host owns the docs/05 §3 budget, so the
## scene caps, the quiet turn and the Extras ledger apply to a scripted event
## exactly as to an offered one: `poll_scripted()` is asked, `fire()` is called
## back. Bytes and paths live in MetaNotesStore.
##
## Rules that are code, not data (docs/05 §0):
##   1. Every write is relative and joined to `user_root`, which must stay under
##      `user://`; a climbing or absolute path is refused, never cleaned up. The
##      player's name reaches a path only through the store's slug.
##   2. No network, no real crash, nothing deleted — writes only.
##   3. Nothing here reads `Esc` or pauses: closing and the pause menu are
##      untouched (the reader panel is an in-window Control).
##   4. The sky tint is skipped under `Settings.photosensitive` (data
##      `time.skip_when_photosensitive`): an accommodation is never punished.
##   5. Every event keeps an in-window fallback: an unwritable folder leaves the
##      page in memory, readable in Extras.
##
## The clock is injectable (`set_clock`, the seam Triggers/Telemetry/SaveSystem
## expose), so no test depends on the wall clock or the machine's time zone.

## The readable-note set changed (Extras refresh).
signal notes_changed
## The sky tint applied for `bucket` (F3 read).
signal sky_applied(bucket: String)

const DATA_PATH := "res://data/meta_notes.json"
## MetaDirector's Extras ledger (docs/05 §3) — the same key, one record.
const SEEN_FLAG := &"meta_seen"
## Flags that must survive a save/reload inside one run.
const THREE_AM_FLAG := &"meta_three_am_night"
const BIRTHDAY_FLAG := &"meta_birthday_seen"
const FALLBACK_BARS := "████████████"
## docs/05 §1.4–§1.5 gates and documented fallbacks as code. Content lives in
## data/meta_notes.json; an event with no authored line never fires (docs/05 §2:
## she is told afterwards, or it never ran), so a broken file degrades to "no
## scripted event" rather than to an unexplained one.
const FALLBACK := {
	"paths": {"letters": "letters", "diary": "diary", "slot_names": "saves/meta_names.json"},
	"gates":
	{
		"letter": 2,
		"diary": 3,
		"slot_names": 4,
		"other_player": 4,
		"clock": 0,
		"three_am": 1,
		"birthday": 0,
		"long_session": 2,
	},
	"ui":
	{
		"section_title": "Her notes",
		"read_button": "Read what she left",
		"folder_button": "Open game folder",
		"empty": "Nothing yet. She has not left anything here.",
		"close": "Close",
		"letter_title": "A letter for {player_name}",
		"diary_title": "Day {day}",
		"in_memory": "The game folder refused the file, so this page is the only copy.",
		"folder_failed": "The game folder could not be opened on this platform.",
		"reader_title": "Her notes",
	},
}
## SaveSlots owns three manual slots; a fiction entry never invents a fourth.
const MANUAL_SLOTS := 3

## Test seam: every write and read is joined to this root, and a root outside
## `user://` is refused (docs/05 §0 rule 1 is not a setting).
var user_root := "user://"
## Test seam: the content file this instance reads.
var data_path := DATA_PATH

var _data: Dictionary = {}
var _store_obj := MetaNotesStore.new()
var _clock: Callable = Callable()
var _session_start := 0
var _session_open := false
var _scene_key := ""
var _greeted := {}
var _long_session_fired := false
var _diary_day := 1
var _diary_lines: Array[String] = []
var _diary_pending := -1
var _slots_pending := false
var _birthday_cache := {}
var _birthday_signature := ""
var _memory_notes := {}
var _letter_in_memory := false
var _last_fired := {}
var _warned_nowrite := false


func _ready() -> void:
	load_data(data_path)
	begin_session()
	_connect_signals()


func _exit_tree() -> void:
	if GameState != null:
		if GameState.state_reset.is_connected(_on_state_reset):
			GameState.state_reset.disconnect(_on_state_reset)
		if GameState.day_changed.is_connected(_on_day_changed):
			GameState.day_changed.disconnect(_on_day_changed)
	if Director != null and Director.has_signal("turn_completed"):
		if Director.turn_completed.is_connected(_on_turn_completed):
			Director.turn_completed.disconnect(_on_turn_completed)


## Reads the content file, merged section-wise over FALLBACK so a partial file
## keeps the documented gates. Returns false (fallbacks kept) for a missing or
## unusable file and never leaves a half-merged table behind.
func load_data(path := DATA_PATH) -> bool:
	data_path = path
	_data = FALLBACK.duplicate(true)
	if not FileAccess.file_exists(path):
		push_warning("MetaEventsM31: %s missing; scripted events disabled" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("MetaEventsM31: %s is not a JSON object; scripted events disabled" % path)
		return false
	for key: String in parsed as Dictionary:
		var value: Variant = (parsed as Dictionary)[key]
		if value is Dictionary and _data.get(key) is Dictionary:
			var merged: Dictionary = (_data[key] as Dictionary).duplicate(true)
			for inner: String in value as Dictionary:
				merged[inner] = (value as Dictionary)[inner]
			_data[key] = merged
		else:
			_data[key] = value
	return true


## docs/05 §1.5: the clock is a seam, like Triggers/Telemetry/SaveSystem. The
## Callable returns unix seconds; the local hour/minute come from the machine's
## bias, so a test that builds a local hour is time-zone proof.
func set_clock(clock: Callable) -> void:
	_clock = clock


## A session began (module mount, or `GameState.reset()`): the long-session
## clock restarts and the per-session greeting bookkeeping clears. A test pins
## the start, so M38 never waits two real hours.
func begin_session(start_unix := -1) -> void:
	_session_start = start_unix if start_unix >= 0 else _now()
	_session_open = true
	_long_session_fired = false
	_greeted.clear()
	_scene_key = ""
	_last_fired = {}


## The host's date boundary (`MetaDirector.note_scene`): a greeting belongs to
## the scene it opens, so the key includes it.
func on_scene(scene_key: String) -> void:
	_scene_key = scene_key


## ── detection (the host charges the docs/05 §3 budget) ────────────────────


## docs/05 §1.4–§1.5: the one scripted/reactive event due this turn, or {}.
## Detection is side-effect free — every stamp advances in `fire()` — so a poll
## the host refuses (scene cap spent, quiet turn) simply retries later.
func poll_scripted(stage: int) -> Dictionary:
	var now := _now()
	var parts := _local_parts(now)
	var due := {}
	if _birthday_due(parts, stage):
		due = _due("M37", "birthday", _note_for("M37"))
	elif _three_am_due(parts, stage):
		due = _due("M36", "three_am", _note_for("M36"))
	elif _greeting_due(stage):
		# Ambient: docs/05 §3's caps count fourth-wall beats; the clock line is
		# the context a T-row line is, so it never spends the scene's slot.
		due = _due("M35", "clock", _note_for("M35"), false)
	elif _long_session_due(now, stage):
		due = _due("M38", "long_session", _note_for("M38"))
	elif _diary_due(stage):
		due = _due("M32", "diary", _note_for("M32"))
	elif _slots_due(stage):
		due = _due("M33", "slot_names", _note_for("M33"))
	elif _other_player_due(stage):
		due = _due("M34", "other_player", _note_for("M34"))
	return due


## The host fired `id` (offered actions arrive here too). Effects only: the host
## already charged the caps, delivered the EVENT line and wrote the ledger.
func fire(id: String, action: String) -> void:
	match id:
		"M31":
			_write_letter()
		"M32":
			_diary_pending = -1
		"M33":
			_slots_pending = false
		"M34":
			_write_other_player()
		"M35":
			_greeted[_greeting_key()] = true
		"M36":
			_apply_three_am()
		"M37":
			_stamp_birthday()
		"M38":
			_long_session_fired = true
		_:
			return
	_last_fired = {"id": id, "action": action, "turn": int(GameState.turn), "at": _now()}
	notes_changed.emit()


## ── the reading surface (Extras and the F3 overlay) ───────────────────────


## Every note the game left in its own folder, newest first, plus the in-memory
## fallbacks. `id` is the note's relative path — the reader's handle.
func notes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: Variant in _memory_notes:
		out.append((_memory_notes[key] as Dictionary).duplicate(true))
	for kind: String in ["letter", "diary"]:
		for file: String in _notes_store().list_notes(kind):
			var rel: String = _notes_store().dir_for(kind).path_join(file)
			var text := _notes_store().read(rel)
			if text.is_empty():
				continue
			out.append({"kind": kind, "id": rel, "title": _title_for(kind, file), "text": text})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				_notes_store().mtime(String(a.get("id", "")))
				> _notes_store().mtime(String(b.get("id", "")))
			)
	)
	return out


## The text of one note, "" when the id is not one of ours (never a path outside
## the folders this module writes).
func read_note(id: String) -> String:
	if _memory_notes.has(id):
		return String((_memory_notes[id] as Dictionary).get("text", ""))
	if not _notes_store().note_ok(id):
		return ""
	return _notes_store().read(id)


func has_notes() -> bool:
	return not notes().is_empty()


## docs/05 §1.4 M31: the Extras "Open game folder" button. Player-initiated and
## in-window; the file manager is the player's own, and headless never opens one.
func open_notes_folder() -> bool:
	if not _notes_store().ensure_folder("letter"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return OS.shell_open(_notes_store().global_path("letter")) == OK


## Builds the Extras section (M31's folder button + the M32 reader). One call
## from `Extras._ready`; the section inserts itself above the Back button.
func build_extras_section(parent: Node) -> Node:
	var ui := _section("ui")
	var box := VBoxContainer.new()
	box.name = "MetaNotes"
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = String(ui.get("section_title", "Her notes"))
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)
	if not has_notes():
		# docs/05 §1.4: the button appears once she has written something. The
		# section stays off the screen until then; the reader's own empty state
		# is what the panel would show.
		return box
	box.add_child(_section_button(String(ui.get("read_button", "")), _on_read_pressed))
	box.add_child(_section_button(String(ui.get("folder_button", "")), _on_folder_pressed))
	parent.add_child(box)
	if parent.get_child_count() >= 2:
		parent.move_child(box, parent.get_child_count() - 2)
	return box


## docs/05 §1.5 M35: "the background sky matches local time" — a tint over the
## scene's own background. Never a new window, never a request to the OS.
func apply_sky(canvas: CanvasItem) -> void:
	if canvas == null:
		return
	var bucket := _bucket_for(int(_local_parts(_now()).get("hour", 12)))
	var strength := float(bucket.get("tint_strength", 0.0))
	if _photosensitive() and bool(_section("time").get("skip_when_photosensitive", true)):
		strength = 0.0
	var tint := Color.from_string(String(bucket.get("tint", "#ffffff")), Color.WHITE)
	canvas.modulate = Color.WHITE.lerp(tint, clampf(strength, 0.0, 0.8))
	sky_applied.emit(String(bucket.get("id", "")))


## The clock as every consumer reads it (greeting, sky, F3): local parts, the
## time-of-day bucket, the printed clock and the session age.
func clock_state() -> Dictionary:
	var now := _now()
	var parts := _local_parts(now)
	var bucket := _bucket_for(int(parts.get("hour", 12)))
	return {
		"unix": now,
		"date": _date_key(parts),
		"hour": int(parts.get("hour", 0)),
		"minute": int(parts.get("minute", 0)),
		"clock": _clock_text(parts),
		"bucket": bucket,
		"bucket_id": String(bucket.get("id", "")),
		"label": String(bucket.get("label", "")),
		"session_seconds": maxi(0, now - _session_start) if _session_open else 0,
	}


## The live state (F3 read and the suite's eyes).
func state() -> Dictionary:
	return {
		"clock": clock_state(),
		"session_open": _session_open,
		"long_session_fired": _long_session_fired,
		"diary_day": _diary_day,
		"diary_lines": _diary_lines.size(),
		"diary_pending": _diary_pending,
		"slots_pending": _slots_pending,
		"greeted": _greeted.keys(),
		"letter_in_memory": _letter_in_memory,
		"notes": notes().size(),
		"last_fired": _last_fired.duplicate(true),
		"paths": paths(),
	}


## Every path this module may touch, as `user://…`, for F3 and the data test.
func paths() -> Dictionary:
	var store := _notes_store()
	return {
		"root": user_root,
		"letters": store.path(store.letters),
		"diary": store.path(store.diary),
		"slot_names": store.path(store.slot_names),
	}


## One UI string from the content file (the reader's labels), so the panel never
## parses the data itself and a writer tunes copy in one place.
func ui_string(key: String, fallback := "") -> String:
	return String(_section("ui").get(key, fallback))


## ── F3 (role checklist: every meta event has a manual trigger) ────────────


func debug_ids() -> Array[String]:
	return ["M31", "M32", "M33", "M34", "M35", "M36", "M37", "M38"]


## Dev-only manual fire (release builds refuse it, like the other debug seams):
## the effect runs and the EVENT line is queued so she can react next turn.
func debug_fire(id: String) -> bool:
	if OS.has_feature("release") or not debug_ids().has(id):
		return false
	var action: Variant = (
		{
			"M31": "write_note",
			"M32": "diary",
			"M33": "slot_names",
			"M34": "other_player",
			"M35": "clock",
			"M36": "three_am",
			"M37": "birthday",
			"M38": "long_session",
		}
		. get(id, id)
	)
	if id == "M32":
		_write_diary(_diary_day)
		_diary_pending = _diary_day
	fire(id, String(action))
	var note := _note_for(id)
	if not note.is_empty():
		GameState.queue_event(note)
	return true


## ── signal wiring ─────────────────────────────────────────────────────────


func _connect_signals() -> void:
	if GameState != null:
		if not GameState.state_reset.is_connected(_on_state_reset):
			GameState.state_reset.connect(_on_state_reset)
		if not GameState.day_changed.is_connected(_on_day_changed):
			GameState.day_changed.connect(_on_day_changed)
	if Director != null and Director.has_signal("turn_completed"):
		if not Director.turn_completed.is_connected(_on_turn_completed):
			Director.turn_completed.connect(_on_turn_completed)


func _on_state_reset() -> void:
	begin_session()
	_diary_day = 1
	_diary_lines.clear()
	_diary_pending = -1
	_slots_pending = false
	_memory_notes.clear()
	_letter_in_memory = false
	_last_fired = {}


## docs/05 §1.4 M32/M33: the day boundary is when the page closes and the slots
## get their names. Both are pure side effects; the announcement is a meta event
## the host charges on the next scene (there is no turn in the night).
func _on_day_changed(day: int) -> void:
	_write_diary(_diary_day)
	_diary_day = day
	_diary_lines.clear()
	_write_slot_names()


## Her `inner` is private text (docs/03 §5). It is collected only from the stage
## where M32 exists, and the file is a *new* surface, so every line is scanned
## again on the way to disk even though it was displayed once.
func _on_turn_completed(_turn_index: int, turn_data: Dictionary) -> void:
	if int(GameState.stage) < _gate("diary"):
		return
	var inner := str(turn_data.get("inner", "")).strip_edges()
	if inner.is_empty():
		return
	_diary_lines.append(inner)
	var cap := maxi(1, int(_section("diary").get("buffer_lines", 24)))
	while _diary_lines.size() > cap:
		_diary_lines.pop_front()


## ── due checks (every stamp is written by `fire()`, never by a poll) ──────


func _birthday_due(parts: Dictionary, stage: int) -> bool:
	if stage < _gate("birthday"):
		return false
	var birthday := _birthday_of()
	if birthday.is_empty():
		return false
	if int(parts.get("month", 0)) != int(birthday.get("month", -1)):
		return false
	if int(parts.get("day", 0)) != int(birthday.get("day", -1)):
		return false
	return String(GameState.get_flag(BIRTHDAY_FLAG, "")) != _date_key(parts)


func _three_am_due(parts: Dictionary, stage: int) -> bool:
	if stage < _gate("three_am"):
		return false
	var spec := _section("three_am")
	var hour := int(parts.get("hour", 0))
	if hour < int(spec.get("from", 2)) or hour >= int(spec.get("to", 4)):
		return false
	return String(GameState.get_flag(THREE_AM_FLAG, "")) != _date_key(parts)


func _greeting_due(stage: int) -> bool:
	if stage < _gate("clock"):
		return false
	return not _greeted.has(_greeting_key())


func _long_session_due(now: int, stage: int) -> bool:
	if not _session_open or _long_session_fired or stage < _gate("long_session"):
		return false
	return now - _session_start >= int(_section("long_session").get("seconds", 7200))


func _diary_due(stage: int) -> bool:
	return _diary_pending > 0 and stage >= _gate("diary")


func _slots_due(stage: int) -> bool:
	return _slots_pending and stage >= _gate("slot_names")


## docs/05 §1.4 "St 4 / AWAKE": the path is part of the gate, not a weight.
func _other_player_due(stage: int) -> bool:
	if stage < _gate("other_player") or String(GameState.path) != "AWAKE":
		return false
	if int(GameState.day) < int(_section("other_player").get("day_min", 3)):
		return false
	return not _seen("M34")


## ── EVENT lines (docs/05 §2: she is told what happened) ───────────────────


func _note_for(id: String) -> String:
	var parts := _local_parts(_now())
	var note := ""
	match id:
		"M32":
			note = String(_section("diary").get("note", ""))
			note = _fill(note, {"day": _diary_pending})
		"M33":
			note = _fill(String(_section("slot_names").get("note", "")), _slot_values())
		"M34":
			note = _fill(
				String(_section("other_player").get("note", "")), {"name": _fiction_name()}
			)
		"M35":
			note = _fill(
				String(_section("time").get("greeting_note", "")),
				{"clock": _clock_text(parts), "label": _bucket_label(parts)}
			)
		"M36":
			note = _fill(
				String(_section("three_am").get("note", "")),
				{"clock": _clock_text(parts), "line": _stage_line("three_am")}
			)
		"M37":
			note = _birthday_note()
		"M38":
			note = _fill(
				String(_section("long_session").get("note", "")),
				{
					"hours": maxi(2, (_now() - _session_start) / 3600),
					"line": _path_line("long_session"),
				}
			)
	return note


func _birthday_note() -> String:
	var birthday := _birthday_of()
	return _fill(
		String(_section("birthday").get("note", "")),
		{
			"month_name": _month_name(int(birthday.get("month", 0))),
			"day": int(birthday.get("day", 0)),
			"line": _path_line("birthday"),
		}
	)


## An event with no authored line is never fired (a poll must not invent text).
func _due(id: String, action: String, note: String, budget := true) -> Dictionary:
	if note.strip_edges().is_empty():
		return {}
	return {"id": id, "action": action, "note": note, "budget": budget}


## ── effects ───────────────────────────────────────────────────────────────


## docs/05 §1.4 M31: `user://letters/for_<name>.txt`; body = her line from the
## turn that took the offer. A read-only folder keeps the page in memory and the
## Extras reader becomes the documented fallback.
func _write_letter() -> void:
	var spec := _section("letter")
	var limit := int(spec.get("max_chars", 900))
	var body := _notes_store().clip(_scan(_her_last_say()), limit)
	if body.is_empty():
		body = _notes_store().clip(_scan(String(spec.get("body_fallback", ""))), limit)
	var text := _fill(
		String(spec.get("format", "{header}\n\n{body}\n\n{footer}\n")),
		{
			"header": _fill(String(spec.get("header", "")), {"player_name": _player_name()}),
			"body": body,
			"footer": String(spec.get("footer", "")),
		}
	)
	var slug := _notes_store().slug(
		String(GameState.player_name),
		int(spec.get("slug_max", 24)),
		String(spec.get("slug_fallback", "senpai"))
	)
	var rel := _notes_store().dir_for("letter").path_join(
		String(spec.get("file_format", "for_%s.txt")) % slug
	)
	var result := _notes_store().write(rel, text)
	_letter_in_memory = not bool(result.get("ok", false))
	var entry := {
		"kind": "letter", "id": rel, "title": _title_for("letter", rel.get_file()), "text": text
	}
	if not _letter_in_memory:
		_memory_notes.erase(rel)
		return
	_warn_nowrite()
	entry["in_memory"] = true
	_memory_notes[rel] = entry


## docs/05 §1.4 M32: the page for `day` — scanned line by line, deduplicated,
## capped, never allowed to shrink an older, richer page for the same day.
func _write_diary(day: int) -> void:
	if day <= 0 or _diary_lines.is_empty():
		return
	if int(GameState.stage) < _gate("diary"):
		return
	var spec := _section("diary")
	var seen := {}
	var lines: Array[String] = []
	for raw: String in _diary_lines:
		var line := _scan(raw)
		if line.is_empty() or seen.has(line):
			continue
		seen[line] = true
		lines.append(line)
		if lines.size() >= int(spec.get("max_lines", 12)):
			break
	if lines.is_empty():
		return
	var body := String(spec.get("line_separator", "\n\n")).join(lines)
	body = body.substr(0, maxi(1, int(spec.get("max_chars", 2000))))
	var text := _fill(
		String(spec.get("format", "{header}\n\n{lines}\n")),
		{"header": _fill(String(spec.get("header", "")), {"day": day}), "lines": body}
	)
	var rel := _notes_store().dir_for("diary").path_join(
		String(spec.get("file_format", "day_%02d.txt")) % day
	)
	if _notes_store().read(rel).length() > text.length():
		_diary_pending = day  # an older, richer page for the same day wins
		return
	var result := _notes_store().write(rel, text)
	if bool(result.get("ok", false)):
		_diary_pending = day
		_memory_notes.erase(rel)
		return
	_memory_notes.merge({rel: _entry("diary", rel, text)}, true)


## docs/05 §1.4 M33: every readable save slot gets the name she gave it, in a
## ledger beside the slots (a save file is SaveSystem's; this is her gloss).
func _write_slot_names() -> void:
	if int(GameState.stage) < _gate("slot_names"):
		return
	var saves := get_node_or_null("/root/SaveSystem")
	if saves == null or not saves.has_method("list_slots"):
		return
	var rows: Array = saves.call("list_slots")
	if rows.is_empty():
		return
	var spec := _section("slot_names")
	var templates_all: Dictionary = spec.get("names", {})
	var ledger := _notes_store().read_ledger()
	var changed := false
	for row_variant: Variant in rows:
		var row: Dictionary = row_variant
		if not bool(row.get("ok", false)):
			continue
		var slot := str(row.get("slot", ""))
		if slot.is_empty() or ledger.has(slot):
			continue
		var stage_key := str(clampi(int(row.get("stage", 1)), 1, 5))
		var templates: Variant = templates_all.get(stage_key, templates_all.get("1", []))
		if not (templates is Array) or (templates as Array).is_empty():
			continue
		var day := int(row.get("day", 0))
		var list: Array = templates
		var pick := int(abs(hash("%s:%d" % [slot, day]))) % list.size()
		ledger[slot] = {
			"slot": slot,
			"name": String(list[pick]).replace("{day}", str(day)),
			"day": day,
			"fiction": false,
			"at": _now(),
		}
		changed = true
	if not changed:
		return
	_notes_store().write_ledger(ledger, int(spec.get("max_entries", 8)))
	_slots_pending = true


## docs/05 §1.4 M34: "a previous save slot the player never created". It is
## fiction, so it is never a loadable save: a name in the ledger, on a slot the
## player owns no file for, marked `fiction` for the Extras reader.
func _write_other_player() -> void:
	var ledger := _notes_store().read_ledger()
	var slot := _free_slot(ledger)
	ledger[slot if not slot.is_empty() else "fiction"] = {
		"slot": slot,
		"name": _fiction_name(),
		"day": int(_section("other_player").get("fiction_day", 11)),
		"fiction": true,
		"at": _now(),
	}
	_notes_store().write_ledger(ledger, int(_section("slot_names").get("max_entries", 8)))


## docs/05 §1.5 M36: the night's own price — instability +3 and music_box from
## data, plus the flag that keeps it to one per night.
func _apply_three_am() -> void:
	var spec := _section("three_am")
	GameState.adjust_meter(&"instability", float(spec.get("instability", 3.0)))
	var music := String(spec.get("music", ""))
	if not music.is_empty() and AudioDirector != null:
		if AudioDirector.has_method("request_music"):
			AudioDirector.request_music(StringName(music))
	GameState.set_flag(THREE_AM_FLAG, _date_key(_local_parts(_now())))


func _stamp_birthday() -> void:
	GameState.set_flag(BIRTHDAY_FLAG, _date_key(_local_parts(_now())))


## ── birthday (docs/05 §1.5 M37: a memory, on that real date) ──────────────


func _birthday_of() -> Dictionary:
	var memory := get_node_or_null("/root/Memory")
	if memory == null or not memory.has_method("facts"):
		return {}
	var facts: Variant = memory.call("facts")
	if not (facts is Array):
		return {}
	# Parsing is cached on the fact list's own signature: a poll every turn must
	# not recompile the date grammar, and a new memory invalidates it at once.
	var signature := str(facts).sha1_text()
	if signature == _birthday_signature:
		return _birthday_cache
	_birthday_signature = signature
	_birthday_cache = MetaBirthday.parse(facts as Array, _section("birthday"))
	return _birthday_cache


## ── the save-slot ledger (M33/M34) ────────────────────────────────────────


func _free_slot(ledger: Dictionary) -> String:
	var saves := get_node_or_null("/root/SaveSystem")
	var taken := {}
	if saves != null and saves.has_method("list_slots"):
		for row_variant: Variant in saves.call("list_slots"):
			taken[str((row_variant as Dictionary).get("slot", ""))] = true
	for number: int in range(1, MANUAL_SLOTS + 1):
		var slot := str(number)
		if ledger.has(slot) or taken.has(slot):
			continue
		return slot
	return ""


func _slot_values() -> Dictionary:
	var newest := {}
	var ledger := _notes_store().read_ledger()
	for key: Variant in ledger:
		var row: Dictionary = ledger[key]
		if bool(row.get("fiction", false)):
			continue
		if newest.is_empty() or int(row.get("at", 0)) >= int(newest.get("at", 0)):
			newest = row
	return {"name": String(newest.get("name", "")), "slot": String(newest.get("slot", ""))}


func _fiction_name() -> String:
	var ledger := _notes_store().read_ledger()
	for key: Variant in ledger:
		var row: Dictionary = ledger[key]
		if bool(row.get("fiction", false)):
			return String(row.get("name", ""))
	var spec := _section("other_player")
	return _fill(
		String(spec.get("name_format", "Day {day} — the one before you")),
		{"day": int(spec.get("fiction_day", 11))}
	)


## ── text helpers ──────────────────────────────────────────────────────────


## The scan for text that is not on its way to the screen — the same stateless
## whole-text pass the transcript redactor uses (`Safety.filter_text`, the
## ChatUI inner-leak precedent). The say path's streaming scanner is
## deliberately NOT used: it carries cross-beat state, and driving it from a
## file write would both leak that carry into the screen and (measured) leave a
## second consecutive one-shot scan unredacted. With no filter, bars — model
## text never reaches `user://` raw (docs/02 §8, docs/05 §0).
func _scan(text: String) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return ""
	var safety := get_node_or_null("/root/Safety")
	if safety != null and safety.has_method("filter_text"):
		var result: Variant = safety.call("filter_text", clean, {"stage": int(GameState.stage)})
		if result is Dictionary:
			return String((result as Dictionary).get("text", FALLBACK_BARS)).strip_edges()
		return String(result).strip_edges()
	return FALLBACK_BARS


func _her_last_say() -> String:
	var director := get_node_or_null("/root/Director")
	if director == null:
		return ""
	var data: Variant = director.get("last_turn_data")
	if not (data is Dictionary):
		return ""
	var beats: Variant = (data as Dictionary).get("beats")
	if not (beats is Array):
		return ""
	var parts: Array[String] = []
	for beat: Variant in beats as Array:
		if not (beat is Dictionary):
			continue
		var say := str((beat as Dictionary).get("say", "")).strip_edges()
		if not say.is_empty():
			parts.append(say)
	return String(_section("letter").get("body_join", " ")).join(parts)


func _fill(template: String, values: Dictionary) -> String:
	if template.is_empty():
		return ""
	return template.format(values)


func _player_name() -> String:
	var name := String(GameState.player_name).strip_edges()
	return name if not name.is_empty() else "you"


func _title_for(kind: String, file: String) -> String:
	var ui := _section("ui")
	if kind == "letter":
		return _fill(String(ui.get("letter_title", "")), {"player_name": _player_name()})
	return _fill(String(ui.get("diary_title", "")), {"day": _notes_store().day_of(file)})


func _entry(kind: String, rel: String, text: String) -> Dictionary:
	return {
		"kind": kind,
		"id": rel,
		"title": _title_for(kind, rel.get_file()),
		"text": text,
		"in_memory": true,
	}


func _stage_line(section: String) -> String:
	var lines: Dictionary = _section(section).get("lines", {})
	var stage := clampi(int(GameState.stage), 0, 5)
	if lines.has(str(stage)):
		return String(lines[str(stage)])
	return String(lines.get("0", ""))


func _path_line(section: String) -> String:
	var spec := _section(section)
	var overrides: Dictionary = spec.get("path_lines", {})
	var path := String(GameState.path)
	if overrides.has(path):
		return String(overrides[path])
	return String(spec.get("line", ""))


func _month_name(month: int) -> String:
	var names: Array = _section("birthday").get("month_names", [])
	if month >= 1 and month <= names.size():
		return String(names[month - 1])
	return ""


func _seen(id: String) -> bool:
	if MetaDirector != null and MetaDirector.has_method("events_seen"):
		return MetaDirector.events_seen().has(id)
	var seen: Variant = GameState.get_flag(SEEN_FLAG, [])
	return seen is Array and (seen as Array).has(id)


## ── clock helpers ─────────────────────────────────────────────────────────


func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())


func _local_parts(now: int) -> Dictionary:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_dict_from_unix_time(now + bias * 60)


func _bucket_for(hour: int) -> Dictionary:
	var buckets: Array = _section("time").get("buckets", [])
	for bucket_variant: Variant in buckets:
		var bucket: Dictionary = bucket_variant
		if hour >= int(bucket.get("from", 0)) and hour <= int(bucket.get("to", 23)):
			return bucket
	return buckets[0] if not buckets.is_empty() else {"id": "day", "label": ""}


func _bucket_label(parts: Dictionary) -> String:
	return String(_bucket_for(int(parts.get("hour", 12))).get("label", ""))


func _clock_text(parts: Dictionary) -> String:
	var template := String(_section("time").get("clock_format", "%02d:%02d"))
	return template % [int(parts.get("hour", 0)), int(parts.get("minute", 0))]


func _date_key(parts: Dictionary) -> String:
	return (
		"%04d-%02d-%02d"
		% [int(parts.get("year", 0)), int(parts.get("month", 0)), int(parts.get("day", 0))]
	)


func _greeting_key() -> String:
	return "%d:%s" % [int(GameState.day), _scene_key]


func _photosensitive() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and "photosensitive" in settings and bool(settings.photosensitive)


func _gate(name: String) -> int:
	return int(_section("gates").get(name, 0))


func _section(name: String) -> Dictionary:
	var value: Variant = _data.get(name)
	return value as Dictionary if value is Dictionary else {}


## The store, configured from this instance's seam root and the content file's
## paths on every use — a test that moves `user_root` mid-run is honoured.
func _notes_store() -> MetaNotesStore:
	_store_obj.root = user_root
	_store_obj.configure(_section("paths"))
	return _store_obj


## ── Extras buttons (built here so Extras only makes one call) ─────────────


## One warning per session: a read-only folder is a documented fallback, not a
## reason to flood the log.
func _warn_nowrite() -> void:
	if _warned_nowrite:
		return
	_warned_nowrite = true
	push_warning("MetaEventsM31: the game folder refused a write; notes stay in memory")


func _section_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(handler)
	return button


func _on_read_pressed() -> void:
	var panel: Control = load("res://scenes/meta/MetaNotesPanel.gd").new()
	panel.call("set_source", self)
	var root: Node = get_tree().current_scene if get_tree() != null else null
	if root == null:
		root = self
	root.add_child(panel)
	panel.call("open")


func _on_folder_pressed() -> void:
	if open_notes_folder():
		return
	push_warning("MetaEventsM31: %s" % String(_section("ui").get("folder_failed", "")))
