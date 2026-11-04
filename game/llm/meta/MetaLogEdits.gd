class_name MetaLogEdits
extends RefCounted
## The docs/05 §1.3 M23/M24 edit ledger — every line she rewrote in the chat log,
## with the words the player actually wrote.
##
## The log never loses the truth: `ChatLog` keeps the original text in its
## entries (so a save stores what the player typed, and the model's own history
## is not poisoned) and only *renders* her version through this ledger. That is
## what makes the edit reversible in two directions:
##
##   1. from the Extras menu after the run (docs/05 §0 rule 5: every effect is
##      logged so a player can review "what happened"), and
##   2. across a reload — the render consults the ledger again, so a save taken
##      mid-hoax comes back reading her version until the player restores it.
##
## `restore_all()` therefore only has to clear the ledger: the originals were
## never overwritten anywhere.
##
## Rows are keyed by (speaker_key, original text, occurrence). Occurrence is the
## 1-based count of earlier log entries with the same speaker and text, which
## `ChatLog` computes as it appends; that keeps two identical player lines
## distinguishable without putting ids into the save format.
##
## Privacy (docs/05 §0, docs/09): only lines the player *sent* can be recorded —
## a deleted draft never reaches the log, so it can never reach this file. The
## ledger lives under `user://` and is wiped by "Reset Everything" with the rest.

const PATH := "user://.leila/log_edits.json"
const VERSION := 1

static var _path := PATH
static var _loaded := false
static var _rows: Array = []
static var _clock: Callable = Callable()


## Test seam: point the ledger at a scratch file (extras/suite isolation).
static func use_path(path: String) -> void:
	_path = path if not path.is_empty() else PATH
	_loaded = false
	_rows = []


## Inject a time source Callable() -> int unix seconds (deterministic tests/replay).
## Callable() restores the wall clock.
static func set_clock(clock: Callable) -> void:
	_clock = clock if clock is Callable else Callable()


## Drops the cache so the next read comes from disk (a fresh process's view).
static func reset_cache() -> void:
	_loaded = false
	_rows = []


static func path() -> String:
	return _path


## Every recorded edit, oldest first ({meta, speaker_key, original, occurrence,
## edited, at}).
static func rows() -> Array:
	_load()
	return _rows.duplicate(true)


static func count() -> int:
	_load()
	return _rows.size()


## Record one rewrite. A second edit of the same line replaces the first row, so
## restoring is always one step even if she lied twice.
static func record(
	meta: String, speaker_key: String, original: String, occurrence: int, edited: String
) -> bool:
	if original.is_empty() or edited.is_empty() or original == edited:
		return false
	_load()
	var row_key := _key(speaker_key, original, occurrence)
	for index in range(_rows.size() - 1, -1, -1):
		var existing: Dictionary = _rows[index]
		if _key_of(existing) == row_key:
			_rows.remove_at(index)
	(
		_rows
		. append(
			{
				"meta": meta,
				"speaker_key": speaker_key,
				"original": original,
				"occurrence": occurrence,
				"edited": edited,
				"at": _now(),
			}
		)
	)
	_save()
	return true


## What the log should show for this entry: her version when one is recorded,
## otherwise the player's own text. `occurrence` is ChatLog's 1-based count.
static func shown(speaker_key: String, text: String, occurrence: int) -> String:
	if text.is_empty():
		return text
	_load()
	if _rows.is_empty():
		return text
	var wanted := _key(speaker_key, text, occurrence)
	for row: Variant in _rows:
		if _key_of(row as Dictionary) == wanted:
			return str((row as Dictionary).get("edited", text))
	return text


## docs/05 §0 rule 5: undo every rewrite. Returns how many lines were restored.
## The originals are still in the log/saves, so nothing else has to be touched;
## a live ChatLog re-renders from its own entries.
static func restore_all() -> int:
	_load()
	var restored := _rows.size()
	_rows = []
	_save()
	return restored


## docs/05 §1.3: wipe both the memory cache and the on-disk ledger so edits
## from a finished run never leak into a fresh New Game.
static func clear() -> void:
	_rows = []
	_loaded = true
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


static func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())


static func _key(speaker_key: String, text: String, occurrence: int) -> String:
	return "%s\u001f%s\u001f%d" % [speaker_key, text, occurrence]


static func _key_of(row: Dictionary) -> String:
	return _key(
		str(row.get("speaker_key", "")), str(row.get("original", "")), int(row.get("occurrence", 1))
	)


## Reads the ledger once per process. A missing, truncated or wrong-typed file
## yields an empty ledger — a corrupt log of her lies must never block play or
## resurrect an edit nobody recorded.
static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = []
	if not FileAccess.file_exists(_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if not (parsed is Dictionary):
		push_warning("MetaLogEdits: %s is not a JSON object; ledger ignored" % _path)
		return
	var edits: Variant = (parsed as Dictionary).get("edits")
	if not (edits is Array):
		return
	for item: Variant in edits:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var original := str(row.get("original", ""))
		var edited := str(row.get("edited", ""))
		if original.is_empty() or edited.is_empty():
			continue
		(
			_rows
			. append(
				{
					"meta": str(row.get("meta", "")),
					"speaker_key": str(row.get("speaker_key", "her")),
					"original": original,
					"occurrence": maxi(1, int(row.get("occurrence", 1))),
					"edited": edited,
					"at": int(row.get("at", 0)),
				}
			)
		)


static func _save() -> void:
	var dir := _path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning(
			"MetaLogEdits: cannot write %s (error %d)" % [_path, FileAccess.get_open_error()]
		)
		return
	file.store_string(JSON.stringify({"version": VERSION, "edits": _rows}, "\t"))
	file.close()
