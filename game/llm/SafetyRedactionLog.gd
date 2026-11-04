class_name SafetyRedactionLog
extends RefCounted
## Redaction log for the output filter (docs/02 §8: "Redactions are logged for
## tuning"). Split out of Safety.gd when the classifier pass pushed the autoload
## past gdlint's file-length limit (same precedent as SafetyText.gd in P1.19);
## it is policy-free plumbing: build the entry, cap the in-memory ring, append
## one JSON line in debug builds, fire the diegetic glitch.
##
## Privacy: no telemetry. The in-memory ring exists only for tests/tuning, and
## the file is `user://debug/redactions.jsonl`, written only in debug builds.
## Personal-data matches are stored as a length marker, never the value.

signal recorded(entry: Dictionary)

const LOG_PATH := "user://debug/redactions.jsonl"
const MAX_ENTRIES := 500
const MAX_FILE_BYTES := 500000
const PLAIN_CATEGORY := "personal_data"

var entries: Array[Dictionary] = []


## Build, cap, emit and (debug builds only) persist one redaction entry.
## `extra` carries the redaction context (stage, content_level) and the
## classifier keys (via, verdict, beat) without changing the tier-1 shape.
func record(
	category: String, matched: String, source: String, extra: Dictionary = {}
) -> Dictionary:
	var entry := {
		"ts": Time.get_unix_time_from_system(),
		"category": category,
		"matched": _loggable(category, matched),
		"source": source,
		"stage": int(extra.get("stage", -1)),
		"content_level": String(extra.get("content_level", "")),
	}
	for key in extra:
		entry[key] = extra[key]
	entries.append(entry)
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	recorded.emit(entry)
	if OS.is_debug_build():
		_append(entry)
	return entry


## Scale the diegetic redaction glitch when an FX host is present. Uses the
## main loop's root so the log works for a filter instance that is not a Node.
func glitch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var fx := tree.root.get_node_or_null("FX")
	if fx != null and fx.has_method("request"):
		fx.call("request", "glitch")


func clear() -> void:
	entries.clear()


func _loggable(category: String, matched: String) -> String:
	if category == PLAIN_CATEGORY:
		return "[PERSONAL_DATA_REDACTED_LEN_%d]" % matched.length()
	return matched


func _append(entry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://debug")
	if FileAccess.file_exists(LOG_PATH):
		var check_f := FileAccess.open(LOG_PATH, FileAccess.READ)
		if check_f != null and check_f.get_length() > MAX_FILE_BYTES:
			check_f.close()
			var dir := DirAccess.open("user://debug")
			if dir != null:
				dir.remove(LOG_PATH)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(entry))
