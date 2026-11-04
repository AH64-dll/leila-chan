class_name TranscriptLogger
extends RefCounted
## Per-session JSONL transcript logger — the P1.18 dev tool (docs/07 §5).
##
## The Director hands it one record per completed turn; every record lands as
## exactly one JSONL line under `user://debug/turns_s<unix>-<seq>_p<N>.jsonl`
## (the plan's "prompt, schema, raw output, applied events per turn →
## user://debug"). Session boundaries are marked with `type:"session"` lines
## (event "start"/"end") in the same stream, so a file replays top to bottom.
##
## Turn record (record format v1): {"v", "type": "turn", "session", "seq",
## "ts", "turn", "prompt", "schema", "output"} plus optional pass-through
## fields "metrics", "events", "error", "day", "stage", "path", "dose",
## "meta" — unknown keys are dropped so the format stays canonical.
## "metrics" is the backend's last_metrics() dict (ready_ms, first_say_ms,
## generate_ms, ...); "output" is the raw model text, never the parsed turn.
##
## Safety: an injected `redactor` Callable (set_redactor/configure) is applied
## to every record — including session lines — before it touches disk. It
## receives a deep copy, returns the record to write; a non-Dictionary return
## drops the record with an error (never writes unredacted data). When the
## redactor object has died or is unset-but-required (redact_ready() false —
## e.g. an async Safety filter that has not attached yet) log_turn() returns
## false so the caller can retry instead of losing the turn silently.
##
## Dev builds only: `enabled` ANDs with `not OS.has_feature("release")`; in a
## release export nothing is ever written (docs/07 §5). Deterministic tests
## inject the clock via set_clock() (SYS playbook: inject the clock).
##
## Rotation: files roll when they would exceed `max_file_bytes` (counted in
## UTF-8 bytes); `max_files` caps the directory by deleting the oldest
## transcripts — the open file is never deleted. Writes go through a single
## FileAccess handle and flush after every line, so a crash loses nothing.
##
## Replay: the static load_transcript()/turn_records()/transcript_files() are
## the loader stub; a later task feeds the records back to the Director.

const RECORD_VERSION := 1
const DEFAULT_DIR := "user://debug/"
const DEFAULT_MAX_FILE_BYTES := 4 * 1024 * 1024
const DEFAULT_MAX_FILES := 32
const FILE_PREFIX := "turns_s"
const FILE_SUFFIX := ".jsonl"
const REQUIRED_FIELDS: Array[String] = ["turn", "prompt", "schema", "output"]
const OPTIONAL_FIELDS: Array[String] = [
	"metrics",
	"events",
	"error",
	"day",
	"stage",
	"path",
	"dose",
	"meta",
	"memory",
]

var _dir := DEFAULT_DIR
var _enabled := true
var _max_file_bytes := DEFAULT_MAX_FILE_BYTES
var _max_files := DEFAULT_MAX_FILES
var _redactor := Callable()
var _clock := Callable()
var _session_id := ""
var _session_seq := 0
var _turn_seq := 0
var _part := 0
var _file: FileAccess
var _file_name := ""
var _file_bytes := 0
var _closed := false
var _last_error := {}


## Apply configuration keys: debug_dir, enabled, max_file_bytes, max_files,
## redactor (Callable or null to clear), clock (Callable or null to clear).
## Changing debug_dir closes the open file first.
func configure(updates: Dictionary) -> void:
	if updates.has("debug_dir"):
		var dir := String(updates["debug_dir"])
		if dir != _dir:
			_end_file()
			_dir = dir
	if updates.has("enabled"):
		_enabled = bool(updates["enabled"])
	if updates.has("max_file_bytes"):
		_max_file_bytes = maxi(64, int(updates["max_file_bytes"]))
	if updates.has("max_files"):
		_max_files = maxi(1, int(updates["max_files"]))
	if updates.has("redactor"):
		var r: Variant = updates["redactor"]
		_redactor = r if r is Callable else Callable()
	if updates.has("clock"):
		var c: Variant = updates["clock"]
		_clock = c if c is Callable else Callable()


## Inject the safety redaction hook: Callable(record: Dictionary) -> Dictionary.
## Receives a deep copy; its return value is what reaches disk. Callable() clears.
func set_redactor(redactor: Callable) -> void:
	_redactor = redactor


## Inject a time source Callable() -> unix seconds (deterministic tests/replay).
## Callable() restores the wall clock.
func set_clock(clock: Callable) -> void:
	_clock = clock


## True while a redactor may still run: unset (no redactor configured) or a
## live callable. False means every record would be dropped — callers must
## wait for the safety hook to attach before logging.
func redact_ready() -> bool:
	return _redactor.is_null() or _redactor.is_valid()


func is_enabled() -> bool:
	# docs/07 §5: dev builds only — never write transcripts from a release.
	return _enabled and not OS.has_feature("release")


## Start a new transcript session. Returns the session id ("s<unix>-<seq>")
## embedded in the file name and every record. Explicitly ends the previous
## session when one is open; log_turn() auto-starts a session if needed.
func start_session(meta: Dictionary = {}) -> String:
	if not _session_id.is_empty():
		end_session()
	_session_seq += 1
	_session_id = "s%d-%03d" % [_now(), _session_seq]
	_turn_seq = 0
	_part = 0
	_closed = false
	var line := {
		"v": RECORD_VERSION,
		"type": "session",
		"event": "start",
		"session": _session_id,
		"seq": _turn_seq,
		"ts": _now(),
	}
	if not meta.is_empty():
		line["meta"] = meta.duplicate(true)
	if is_enabled():
		_write_redacted(line)
	return _session_id


## End the open session: writes the "end" marker and closes the file.
func end_session() -> void:
	if _session_id.is_empty():
		return
	if _file != null:
		_write_redacted(
			{
				"v": RECORD_VERSION,
				"type": "session",
				"event": "end",
				"session": _session_id,
				"seq": _turn_seq,
				"ts": _now(),
			}
		)
	_end_file()
	_session_id = ""
	_turn_seq = 0


## Final close for the logger itself; after this, log_turn() refuses records
## until start_session() reopens it.
func close() -> void:
	if _file != null and not _session_id.is_empty():
		_write_redacted(
			{
				"v": RECORD_VERSION,
				"type": "session",
				"event": "end",
				"session": _session_id,
				"seq": _turn_seq,
				"ts": _now(),
			}
		)
	_end_file()
	_closed = true


## Record one finished turn. Required: turn (int), prompt (Array/Dictionary —
## TurnRequest.messages), schema (Dictionary), output (String — raw model
## output). Optional: every OPTIONAL_FIELDS entry, "metrics" being the
## backend's last_metrics() and "events" the applied Director events.
## Returns true once the redacted line is durably in the file.
func log_turn(record: Dictionary) -> bool:
	if not is_enabled() or _closed:
		return false
	var rejected := _validate(record)
	if not rejected.is_empty():
		_fail(ERR_INVALID_DATA, rejected)
		return false
	if not redact_ready():
		return false
	if _session_id.is_empty():
		start_session()
	return _write_redacted(_turn_record(record))


## Flush the open file (lines already store_line + flush per write; kept for
## callers that want an explicit durability point).
func flush() -> bool:
	if _file == null:
		return true
	_file.flush()
	return _file.get_error() == OK


func session_id() -> String:
	return _session_id


func current_file() -> String:
	if _file_name.is_empty():
		return ""
	return _dir.path_join(_file_name)


func last_error() -> Dictionary:
	return _last_error.duplicate(true)


## Load one transcript file for replay. Never throws:
## {"records": [Dictionary], "errors": [{"line", "message", "excerpt"}]} —
## good lines are kept even around corrupt ones (1-based `line` numbers).
static func load_transcript(path: String) -> Dictionary:
	var result := {"records": [], "errors": []}
	if not FileAccess.file_exists(path):
		result["errors"].append({"line": 0, "message": "file not found: " + path})
		return result
	var text := FileAccess.get_file_as_string(path)
	var n := 0
	for raw: String in text.split("\n"):
		n += 1
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			result["records"].append(parsed)
		else:
			(
				result["errors"]
				. append(
					{
						"line": n,
						"message": "not a JSON object",
						"excerpt": line.substr(0, 80),
					}
				)
			)
	return result


## Only the turn lines of a loaded record array — replay input.
static func turn_records(records: Array) -> Array:
	var turns: Array = []
	for r: Variant in records:
		if r is Dictionary and String(r.get("type", "")) == "turn":
			turns.append(r)
	return turns


## All transcript files in a directory, sorted (name order == write order).
static func transcript_files(dir_path: String = DEFAULT_DIR) -> PackedStringArray:
	var names := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return names
	for f: String in DirAccess.get_files_at(dir_path):
		if f.begins_with(FILE_PREFIX) and f.ends_with(FILE_SUFFIX):
			names.append(f)
	names.sort()
	return names


## Apply the redactor to a deep copy. Returns {"ok": bool, "record": Dictionary}
## — ok=false means the redactor broke contract and the record must not be
## written; an empty record means "redacted to nothing — drop".
func _apply_redactor(record: Dictionary) -> Dictionary:
	if _redactor.is_null() or not _redactor.is_valid():
		return {"ok": true, "record": record}
	var cleaned: Variant = _redactor.call(record.duplicate(true))
	if cleaned is Dictionary:
		return {"ok": true, "record": cleaned}
	return {"ok": false, "record": {}}


func _write_redacted(record: Dictionary) -> bool:
	var cleaned := _apply_redactor(record)
	if not cleaned["ok"]:
		_fail(
			ERR_INVALID_DATA, "TranscriptLogger: redactor returned non-Dictionary — record dropped"
		)
		return false
	if (cleaned["record"] as Dictionary).is_empty():
		return true
	return _append_line(JSON.stringify(cleaned["record"]))


func _now() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())


func _validate(record: Dictionary) -> String:
	for key: String in REQUIRED_FIELDS:
		if not record.has(key):
			return "log_turn: missing required field '" + key + "'"
	if not (record["turn"] is int or record["turn"] is float):
		return "log_turn: 'turn' must be an int"
	if not record["prompt"] is Array and not record["prompt"] is Dictionary:
		return "log_turn: 'prompt' must be an Array or Dictionary (TurnRequest.messages)"
	if not record["schema"] is Dictionary:
		return "log_turn: 'schema' must be a Dictionary"
	if not record["output"] is String:
		return "log_turn: 'output' must be a String (the raw model output)"
	return ""


func _turn_record(record: Dictionary) -> Dictionary:
	var full := {
		"v": RECORD_VERSION,
		"type": "turn",
		"session": _session_id,
		"seq": _turn_seq,
		"ts": _now(),
	}
	for key: String in REQUIRED_FIELDS + OPTIONAL_FIELDS:
		if record.has(key):
			full[key] = record[key]
	full["turn"] = int(record["turn"])  # JSON reads ints back as floats
	_turn_seq += 1
	return full


func _append_line(line: String) -> bool:
	var bytes := line.to_utf8_buffer().size() + 1  # store_line adds "\n"
	if _file_bytes > 0 and _file_bytes + bytes > _max_file_bytes:
		_end_file()
	if _file == null:
		var err := _open_next_file()
		if err != OK:
			_fail(err, "TranscriptLogger: cannot open a transcript file in " + _dir)
			return false
		_enforce_cap()
	_file.store_line(line)
	_file.flush()
	_file_bytes += bytes
	return true


func _open_next_file() -> Error:
	var err := DirAccess.make_dir_recursive_absolute(_dir)
	if err != OK:
		return err
	_part += 1
	var stem := FILE_PREFIX + _session_id + "_p" + "%03d" % _part
	var name := stem + FILE_SUFFIX
	var attempt := 0
	while FileAccess.file_exists(_dir.path_join(name)) and attempt < 100:
		attempt += 1
		name = "%s_%d%s" % [stem, attempt, FILE_SUFFIX]
	_file_name = name
	_file = FileAccess.open(_dir.path_join(name), FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file_bytes = 0
	return OK


func _end_file() -> void:
	if _file != null:
		_file.close()
		_file = null
	_file_bytes = 0
	_file_name = ""


func _enforce_cap() -> void:
	var files := transcript_files(_dir)
	var excess := files.size() - _max_files
	for f: String in files:
		if excess <= 0:
			return
		if f == _file_name:
			continue
		DirAccess.remove_absolute(_dir.path_join(f))
		excess -= 1


func _fail(code: int, message: String) -> void:
	if _last_error.get("code") != code or _last_error.get("message") != message:
		push_error(message + " (error %d)" % code)
	_last_error = {"code": code, "message": message}
