class_name EndingLog
extends RefCounted
## EndingLog — what the player has reached across runs: the ending log and the
## Extras unlocks derived from it (docs/05 §0 rule 5, docs/01 §7).
##
## A run's save carries the ending it reached (`Endings.FLAG_ENDING` in
## GameState.flags); this file is the *profile* beside it — `user://endings.json`
## survives New Game, every slot and a save wipe, because the point of an
## ending gallery is that it outlives the run. Only Settings → "Reset
## Everything" (P3.12) and this class's `wipe()` remove it.
##
## Shape: {"version": 1, "endings": {"E01": {"count", "first_seen", "last_seen",
## "path", "day", "stage"}}}. `path` is written from the ending row, so the
## secret's "played all six paths" question is answered from history rather than
## from whatever the live state happens to be. Unknown ids are preserved on
## rewrite: a future build's log is not truncated by this one. A corrupt file
## degrades to an empty log with a warning — a gallery may lose its history, it
## may never stop the game.
##
## Everything here is static and reads the file through a small cache, like
## Stages/Paths: the log is a handful of records, and the readers (Title's
## Extras row, the ending scene, Extras) must see the same answer within a frame.

const DEFAULT_PATH := "user://endings.json"
const VERSION := 1
const TMP_SUFFIX := ".tmp"
const GameStateScript := preload("res://autoload/GameState.gd")

## Test seams: point the store at a scratch file and pin the clock's text.
static var _path := DEFAULT_PATH
static var _cache: Dictionary = {}
static var _cache_path := ""
static var _clock: Callable = Callable()


## Point the log at another file ("" restores the shipped path). Tests use a
## scratch path; nothing in the game calls this.
static func use_path(path: String) -> void:
	_path = path if not path.strip_edges().is_empty() else DEFAULT_PATH
	clear_cache()


## The shipped path, for a caller that needs to print or delete it.
static func default_path() -> String:
	return DEFAULT_PATH


## Inject a clock returning the timestamp text written to the log
## (deterministic tests/replay). Callable() restores the wall clock.
static func set_clock(clock: Callable) -> void:
	_clock = clock if clock is Callable else Callable()


## Test hook: forget the cached copy so the next read comes from the file.
static func clear_cache() -> void:
	_cache = {}
	_cache_path = ""


## The whole log, as a copy: {"version", "endings"}.
static func data() -> Dictionary:
	return _load().duplicate(true)


## Records one reached ending and returns the record it wrote ({} when the row
## has no id). `summary` carries the run's own day/stage for the Extras detail.
static func record(row: Dictionary, summary := {}) -> Dictionary:
	var id := _str(row.get("id")).strip_edges().to_upper()
	if id.is_empty():
		push_warning("EndingLog.record: the ending row carries no id")
		return {}
	var log := _load()
	var entries: Dictionary = log["endings"]
	var previous := _dict(entries.get(id, {}))
	var entry := {
		"count": maxi(0, int(previous.get("count", 0))) + 1,
		"first_seen": _first_seen(previous),
		"last_seen": _now(),
		"path": _path_of(row),
		"day": maxi(0, int(summary.get("day", 0))),
		"stage": maxi(0, int(summary.get("stage", 0))),
	}
	entries[id] = entry
	log["endings"] = entries
	_write(log)
	return entry.duplicate(true)


## The stored record for `id` ({} when it was never reached).
static func record_of(id: String) -> Dictionary:
	var entries := _dict(_load().get("endings", {}))
	return _dict(entries.get(_normalise(id))).duplicate(true)


static func seen(id: String) -> bool:
	return not record_of(id).is_empty()


## How many times `id` was reached (0 when never).
static func count(id: String) -> int:
	return maxi(0, int(record_of(id).get("count", 0)))


## Every reached id, in file order of the stored map.
static func seen_ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _dict(_load().get("endings", {})):
		out.append(String(key))
	return out


## The paths with at least one reached ending, in docs/01 §4 order. This is the
## fact the secret ending's `requires.paths` is checked against.
static func seen_paths() -> Array[StringName]:
	var entries := _dict(_load().get("endings", {}))
	var reached := {}
	for key: Variant in entries:
		var path := _str(_dict(entries[key]).get("path"))
		if GameStateScript.PATHS.has(StringName(path)):
			reached[path] = true
	var out: Array[StringName] = []
	for path: StringName in GameStateScript.PATHS:
		if reached.has(String(path)):
			out.append(path)
	return out


## Has the player finished a run at all? Title shows Extras only after one.
static func any_seen() -> bool:
	return not seen_ids().is_empty()


## Deletes the log. Settings → "Reset Everything" (P3.12) calls this (or wipes
## all of user:// except settings, which covers it); returns whether a file was
## actually removed.
static func wipe() -> bool:
	clear_cache()
	if not FileAccess.file_exists(_path):
		return false
	DirAccess.remove_absolute(_path)
	DirAccess.remove_absolute(_path + TMP_SUFFIX)
	return true


# --- storage -------------------------------------------------------------


static func _load() -> Dictionary:
	if _cache_path == _path and not _cache.is_empty():
		return _cache
	var log := {"version": VERSION, "endings": {}}
	_cache = log
	_cache_path = _path
	if not FileAccess.file_exists(_path):
		return _cache
	# JSON.new().parse() reports the failure as a return code; the static
	# parse_string() would print an engine ERROR for the corrupt case the log is
	# explicitly required to survive.
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_path)) != OK:
		push_warning("EndingLog: %s is not JSON — starting a fresh log" % _path)
		return _cache
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		push_warning("EndingLog: %s is not a JSON object — starting a fresh log" % _path)
		return _cache
	var entries: Variant = (parsed as Dictionary).get("endings")
	if not entries is Dictionary:
		push_warning("EndingLog: %s has no 'endings' object — starting fresh" % _path)
		return _cache
	for key: Variant in entries:
		var id := _normalise(key)
		if id.is_empty() or not (entries as Dictionary)[key] is Dictionary:
			continue
		log["endings"][id] = _clean_record((entries as Dictionary)[key])
	return _cache


static func _write(log: Dictionary) -> bool:
	_cache = log.duplicate(true)
	_cache_path = _path
	var directory := _path.get_base_dir()
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
	var temporary := _path + TMP_SUFFIX
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning(
			(
				"EndingLog: cannot write %s (%s)"
				% [temporary, error_string(FileAccess.get_open_error())]
			)
		)
		return false
	file.store_string(JSON.stringify(log, "\t", true))
	file.flush()
	file.close()
	if _replace(temporary, _path):
		return true
	DirAccess.remove_absolute(temporary)
	push_warning("EndingLog: cannot replace %s" % _path)
	return false


static func _replace(temporary: String, path: String) -> bool:
	var error := DirAccess.rename_absolute(temporary, path)
	if error == OK:
		return true
	DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temporary, path) == OK


## One record, healed: a hand-edited or half-written entry cannot make count a
## string or first_seen a number.
static func _clean_record(value: Variant) -> Dictionary:
	var entry := _dict(value)
	var record := {
		"count": maxi(0, int(entry.get("count", 0))),
		"first_seen": _str(entry.get("first_seen")),
		"last_seen": _str(entry.get("last_seen")),
		"path": _str(entry.get("path")),
		"day": maxi(0, int(entry.get("day", 0))),
		"stage": maxi(0, int(entry.get("stage", 0))),
	}
	if record["first_seen"].is_empty():
		record["first_seen"] = record["last_seen"]
	return record


static func _first_seen(previous: Dictionary) -> String:
	var stored := _str(previous.get("first_seen")).strip_edges()
	return stored if not stored.is_empty() else _now()


## The path an ending completes: its own row's path, and only when that is one of
## the six. E14 "Static" is `ANY`, so a burnout never counts as having played a
## path — the secret asks for six runs that reached their path's own ending.
static func _path_of(row: Dictionary) -> String:
	var path := _str(row.get("path"))
	return path if GameStateScript.PATHS.has(StringName(path)) else ""


static func _normalise(id: Variant) -> String:
	return _str(id).strip_edges().to_upper()


static func _now() -> String:
	if _clock.is_valid():
		return _str(_clock.call())
	return Time.get_datetime_string_from_system(false, false)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _str(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""
