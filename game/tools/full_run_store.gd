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


## Scans a Markdown transcript prefix from a prior segment for already-rendered
## days and turns. Marks any previous segment-stop summary as a checkpoint.
static func scan_rendered(prefix: String) -> Dictionary:
	var days := {}
	var turns := {}
	var cleaned := prefix
	if cleaned.contains("## Run summary\n- finished: day cap"):
		cleaned = cleaned.replace(
			"## Run summary\n- finished: day cap", "## Checkpoint summary\n- checkpoint: day cap"
		)
	var regex_day := RegEx.create_from_string("## Day (\\d+)")
	if regex_day != null:
		for match_day: RegExMatch in regex_day.search_all(cleaned):
			days[int(match_day.get_string(1))] = true
	var regex_turn := RegEx.create_from_string("### Turn (\\d+) · day (\\d+)")
	if regex_turn != null:
		for match_turn: RegExMatch in regex_turn.search_all(cleaned):
			var t_idx := int(match_turn.get_string(1))
			var d_idx := int(match_turn.get_string(2))
			turns["%d:%d" % [d_idx, t_idx]] = true
	return {"days": days, "turns": turns, "cleaned": cleaned}


static func build_payload(
	meta: Dictionary, arrays: Dictionary, final_state: Dictionary
) -> Dictionary:
	return {
		"run": String(meta.get("run", "")),
		"dev_note":
		(
			"dev artifact — `turns[].beats[].say` and `inner` hold the raw, "
			+ "pre-filter model text; `displayed` is the filtered screen text"
		),
		"started": String(meta.get("started", "")),
		"model": String(meta.get("model", "")),
		"url": String(meta.get("url", "")),
		"player": String(meta.get("player", "")),
		"turns": arrays.get("records", []),
		"nights": arrays.get("nights", []),
		"broken": arrays.get("broken", []),
		"refused": arrays.get("refused", []),
		"stage_transitions": arrays.get("transitions", []),
		"path_decisions": arrays.get("path_log", []),
		"triggers": arrays.get("trigger_log", []),
		"redactions": arrays.get("redaction_log", []),
		"leaks": arrays.get("leak_log", []),
		"final": final_state,
	}


static func final_state() -> Dictionary:
	return {
		"day": int(GameState.day),
		"stage": int(GameState.stage),
		"path": str(GameState.path),
		"path_locked": bool(GameState.path_locked),
		"instability": float(GameState.instability),
		"instability_peak": float(GameState.instability_peak),
		"instability_floor": float(GameState.instability_floor),
		"turn": int(GameState.turn),
		"memory_count": int(Memory.size()),
	}


static func meters_dict() -> Dictionary:
	return {
		"affection": float(GameState.affection),
		"trust": float(GameState.trust),
		"instability": float(GameState.instability),
		"instability_peak": float(GameState.instability_peak),
		"instability_floor": float(GameState.instability_floor),
		"fixation": float(GameState.fixation),
		"lucidity": float(GameState.lucidity),
	}
