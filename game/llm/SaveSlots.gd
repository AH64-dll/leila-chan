class_name SaveSlots
extends RefCounted
## SaveSlots — one save file per slot (docs/07 §3.5): `user://saves/slot_N.json`
## for the manual slots and `user://saves/autosave.json` for the per-scene
## autosave. A save holds the game state, the memories and the log.
##
## This class owns the bytes only: slot name → path, the envelope (format,
## version, checksum) and its validation, atomic writes and the tolerant slot
## listing a menu needs. Applying a payload to GameState/Memory/Director is
## `SaveSystem`'s half, so this one is testable without the autoload ring and
## can never leave the game half-loaded.
##
## Corruption is a value here, never an exception: every read returns
## {"ok": bool, "error": <code>, "message": <text>, ...} and never trusts the
## file. The envelope's `checksum` is the sha256 of the canonical payload JSON,
## so a bit flip inside a string — which still parses — is caught as well as
## the truncation that does not. `version` gates a future migration: a newer
## file is refused (`unsupported_version`), never guessed at.

const FORMAT := "leila.save"
const VERSION := 1
const DEFAULT_DIR := "user://saves"
## The autosave is a slot the player never writes by hand: "auto" is its id and
## its own file name, so it can never collide with slot_1..slot_N.
const SLOT_AUTO := "auto"
const MANUAL_SLOTS := 3
const SLOT_PREFIX := "slot_"
const AUTO_FILE := "autosave.json"
const SLOT_SUFFIX := ".json"
const TMP_SUFFIX := ".tmp"
## Test seam: point the store at a scratch directory (SaveSystem.save_dir).
var dir_path := DEFAULT_DIR
## Envelope identity. The defaults are the docs/07 §3.5 save; ShadowStore
## reuses this codec for `user://.leila/shadow.json` under its own format tag
## (`leila.shadow`), so a slot file and the shadow file can never pass as the
## other (P3.12, docs/05 M08).
var format := FORMAT
var version := VERSION


func _init(envelope_format := FORMAT, envelope_version := VERSION) -> void:
	format = envelope_format
	version = envelope_version


## "1".."3" or "auto" for a slot id that may arrive as an int, a String or a
## JSON float; "" when the id names no slot this build owns.
static func normalize_slot(slot: Variant) -> String:
	var text := ""
	if slot is int:
		text = str(slot)
	elif slot is float:
		text = str(int(slot)) if float(int(slot)) == slot else ""
	elif slot is String or slot is StringName:
		text = String(slot).strip_edges()
	if text == SLOT_AUTO:
		return SLOT_AUTO
	if not text.is_valid_int():
		return ""
	var number := int(text)
	if number < 1 or number > MANUAL_SLOTS:
		return ""
	return str(number)


func path_for(slot: Variant) -> String:
	var key := normalize_slot(slot)
	if key.is_empty():
		return ""
	if key == SLOT_AUTO:
		return dir_path.path_join(AUTO_FILE)
	return dir_path.path_join(SLOT_PREFIX + key + SLOT_SUFFIX)


func exists(slot: Variant) -> bool:
	var path := path_for(slot)
	return not path.is_empty() and FileAccess.file_exists(path)


## Wrap a payload in the envelope: format, version, and the sha256 of the
## canonical payload JSON (the bytes the checksum is checked against on read).
func encode(payload: Dictionary) -> Dictionary:
	# A JSON round trip first, so the checksum is computed over the same value
	# domain the reader will parse (ints become floats, keys already sorted).
	var canonical: Variant = JSON.parse_string(JSON.stringify(payload))
	if not canonical is Dictionary:
		return _fail("invalid_data", "save payload is not JSON-serialisable")
	var envelope := {
		"format": format,
		"version": version,
		"checksum": JSON.stringify(canonical, "", true).sha256_text(),
		"payload": canonical,
	}
	return _ok({"text": JSON.stringify(envelope, "\t", true)})


## Envelope + checksum validation. Never trusts the text: every failure is a
## code, and the payload is only returned when the bytes are intact.
func decode(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return _corrupt("save file is empty")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _corrupt("save file is not a JSON object")
	var envelope := parsed as Dictionary
	var problem := _envelope_problem(envelope)
	if not bool(problem["ok"]):
		return problem
	var payload: Variant = envelope["payload"]
	var stored := _string(envelope.get("checksum"))
	if stored.is_empty() or JSON.stringify(payload, "", true).sha256_text() != stored:
		return _corrupt("checksum mismatch")
	return _ok({"payload": payload})


func read(slot: Variant) -> Dictionary:
	var key := normalize_slot(slot)
	if key.is_empty():
		return _fail("invalid_slot", _slot_help())
	var path := path_for(key)
	if not FileAccess.file_exists(path):
		return _fail("not_found", "no save in slot '%s'" % key)
	var decoded := decode(FileAccess.get_file_as_string(path))
	decoded["slot"] = key
	decoded["path"] = path
	return decoded


## Write through a temporary file and rename, so a crash mid-write cannot
## truncate the previous save. Returns the usual {ok, error, message, path}.
func write(slot: Variant, payload: Dictionary) -> Dictionary:
	var key := normalize_slot(slot)
	if key.is_empty():
		return _fail("invalid_slot", _slot_help())
	var encoded := encode(payload)
	if not bool(encoded["ok"]):
		return encoded
	var dir_error := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_error != OK and not DirAccess.dir_exists_absolute(dir_path):
		return _fail("unwritable", "cannot create %s (error %d)" % [dir_path, dir_error])
	var path := path_for(key)
	var temporary := path + TMP_SUFFIX
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail(
			"unwritable",
			"cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())]
		)
	file.store_string(_string(encoded.get("text")))
	file.flush()
	file.close()
	if not _replace(temporary, path):
		DirAccess.remove_absolute(temporary)
		return _fail("unwritable", "cannot replace %s" % path)
	return _ok({"slot": key, "path": path})


func erase(slot: Variant) -> bool:
	var path := path_for(slot)
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + TMP_SUFFIX)
	return true


## Every slot this build owns, in slot order, with what a menu shows. A corrupt
## file is a row with ok=false and its error code — never a crash, never a
## silent hole.
func summaries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key: String in _slot_names():
		var path := path_for(key)
		if FileAccess.file_exists(path):
			rows.append(_summary_for(key, path))
	return rows


## The newest readable save, "" when there is none. `saved_at` comes from the
## payload's own clock (not the file mtime), so the answer is deterministic and
## survives a file copy; slot order breaks a tie.
func latest_slot() -> String:
	var best := ""
	var best_at := -1
	for row: Dictionary in summaries():
		if not bool(row["ok"]):
			continue
		if int(row["saved_at"]) > best_at:
			best_at = int(row["saved_at"])
			best = String(row["slot"])
	return best


func _summary_for(key: String, path: String) -> Dictionary:
	var row := {
		"slot": key,
		"path": path,
		"ok": false,
		"error": "",
		"saved_at": 0,
		"day": 0,
		"stage": 0,
		"scene": "",
		"player_name": "",
	}
	var decoded := read(key)
	row["ok"] = bool(decoded["ok"])
	row["error"] = _string(decoded.get("error"))
	if not bool(row["ok"]):
		return row
	var payload := _dict(decoded.get("payload"))
	var state := _dict(payload.get("state"))
	var scene := _dict(payload.get("scene"))
	row["saved_at"] = _int(payload.get("saved_at"), 0)
	row["day"] = _int(state.get("day"), 0)
	row["stage"] = _int(state.get("stage"), 0)
	row["scene"] = _string(scene.get("id"))
	row["player_name"] = _string(state.get("player_name"))
	return row


## Move the finished temporary file onto the slot. A platform that refuses to
## replace an existing target (some Windows setups) gets one remove + retry;
## the previous save is only dropped after the new bytes are complete on disk.
func _replace(temporary: String, path: String) -> bool:
	var error := DirAccess.rename_absolute(temporary, path)
	if error == OK:
		return true
	DirAccess.remove_absolute(path)
	error = DirAccess.rename_absolute(temporary, path)
	return error == OK


func _envelope_problem(envelope: Dictionary) -> Dictionary:
	if _string(envelope.get("format")) != format:
		return _corrupt("not a leila save file")
	var read_version := _int(envelope.get("version"), -1)
	if read_version != version:
		return _fail(
			"unsupported_version", "save v%d, this build reads v%d" % [read_version, version]
		)
	if not envelope.get("payload") is Dictionary:
		return _corrupt("save payload is missing")
	return _ok({})


func _slot_names() -> Array[String]:
	var names: Array[String] = []
	for number: int in range(1, MANUAL_SLOTS + 1):
		names.append(str(number))
	names.append(SLOT_AUTO)
	return names


func _slot_help() -> String:
	return "slot must be 1-%d or '%s'" % [MANUAL_SLOTS, SLOT_AUTO]


func _ok(extra: Dictionary) -> Dictionary:
	var result := {"ok": true, "error": "", "message": ""}
	result.merge(extra, true)
	return result


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}


func _corrupt(message: String) -> Dictionary:
	return _fail("corrupt", message)


## Untrusted input helpers: a save is data, so a wrong type is a fallback, never
## an error. `int(Dictionary)` would abort the script — these never do.
static func _int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return int(value) if is_finite(value) else fallback
	return fallback


static func _string(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}
