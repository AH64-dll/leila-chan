class_name FullRunStore
extends RefCounted
## The P2.22 full-run sidecar: one JSON file beside the Markdown transcript,
## rewritten after every turn so a killed run keeps everything up to its last
## completed turn. It also holds the two list rules the driver needs to keep that
## file canonical across a resumed segment.
##
## The sidecar is the raw per-turn record (meters, dose, metrics, triggers, path
## decisions, inner leaks, safety spans, memory state); the Markdown transcript
## is the readable view of the same arrays. Keeping the byte-level load/save here
## leaves the driver to the game-facing logic only.


## Parsed sidecar contents, or {} when the file is missing or malformed. A broken
## sidecar never stops a resumed run: the game autosave is still authoritative.
static func load_sidecar(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_warning("FullRunStore: %s is not a JSON object — ignored" % path)
		return {}
	return parsed as Dictionary


static func save_sidecar(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FullRunStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "  ", false))
	file.close()
	return true


## JSON gives untyped arrays back; one shallow pass restores the typed Arrays
## the driver and the renderer declare.
static func typed(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				out.append(item)
	return out


## Keeps the sidecar canonical across a resumed segment: a turn replayed after a
## kill replaces its old record instead of appearing twice. Only the tail is
## scanned — a resumed segment can only replay its most recent turns.
static func upsert(records: Array[Dictionary], record: Dictionary) -> void:
	for i: int in range(records.size() - 1, maxi(-1, records.size() - 40), -1):
		if (
			int(records[i].get("day", -1)) == int(record.get("day", -2))
			and int(records[i].get("turn", -1)) == int(record.get("turn", -2))
		):
			records[i] = record
			return
	records.append(record)
