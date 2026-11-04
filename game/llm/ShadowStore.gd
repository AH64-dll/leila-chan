class_name ShadowStore
extends RefCounted
## ShadowStore — the shadow save at `user://.leila/shadow.json` (docs/05 M08,
## docs/07 §3.5). A New Game wipes the run's save and memories, but this one
## file survives, so she keeps a few things across it: the first name ever
## typed, every name she has seen, how many runs she has been through, and a
## handful of memories from runs she had already deteriorated in. Settings →
## "Reset Everything" deletes it (`SaveSystem.wipe_everything`).
##
## PRIVACY — the file's entire contents, nothing else is ever written to it:
##   {
##     "format":    "leila.shadow",        envelope tag (SaveSlots codec)
##     "version":   1,                     envelope version
##     "checksum":  "<sha256>",            of the canonical payload JSON
##     "payload": {
##       "first_name": "<string>",   the first player name ever confirmed at the
##                                 New Game screen (docs/08 §1.5 uses it for
##                                 "That's not what you were called last time.").
##       "names":      ["<string>",…], every distinct name confirmed across runs,
##                                 in order (first name is names[0]).
##       "runs":       ["<string>",…], the name of each run that ended via New
##                                 Game, oldest first. `runs.size()` is "how
##                                 many times you have restarted her".
##       "memories":   ["<string>",…], up to `memory.json → shadow.limit` facts
##                                 from the run just ended, kept only when the
##                                 run had reached the meta gate (docs/05 M08,
##                                 stage 3+). Chosen by the memory model's own
##                                 importance, ties keep the newest — the facts
##                                 she quoted most, not the newest noise.
##     }
##   }
## Never in this file: conversation logs or transcripts, deletions or drafts
## (docs/09 "deleted drafts never leave memory"), the OS username (docs/09,
## opt-in only — a typed name is stored, but nothing reads it from the OS),
## telemetry, device identifiers, IP or network data. The content is plain
## JSON the player can open and verify; "Reset Everything" removes the whole
## `user://` tree except `settings.cfg`, including this file.
##
## Bytes are the P2.20 envelope: same canonical-JSON sha256 and atomic
## tmp+rename write as a save slot, under the `leila.shadow` format tag so a
## slot file can never pass as the shadow. Corruption is a value here too:
## `load()` returns `{ok, error, message, payload}` and never throws; a corrupt
## file reads as `{ok:false, "corrupt"}` and a new write simply replaces it.

const FORMAT := "leila.shadow"
const VERSION := 1
const DEFAULT_PATH := "user://.leila/shadow.json"
const FILE_NAME := "shadow.json"
const TMP_SUFFIX := ".tmp"
## `runs` is memory she acts on ("I remember every time you started over"), not
## an audit trail — it is capped so the file stays small forever.
const RUN_LIMIT := 8

## Test seam: point the file at a scratch path (`SaveSystem.shadow_path`).
var path := DEFAULT_PATH

var _codec := SaveSlots.new(FORMAT, VERSION)


## The empty-shadow shape every reader sees before the first New Game.
static func blank() -> Dictionary:
	return {"first_name": "", "names": [], "runs": [], "memories": []}


## Read + validate the envelope. A missing file is `not_found`, never a crash;
## anything present but wrong is `corrupt`/`unsupported_version`. The payload is
## healed into the blank shape so readers can trust the four keys.
func load_shadow() -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("not_found", "no shadow save")
	var decoded := _codec.decode(FileAccess.get_file_as_string(path))
	if not bool(decoded["ok"]):
		return decoded
	return _ok({"payload": _heal(decoded.get("payload"))})


## Write through tmp+rename (the slot write's crash rule). Returns
## `{ok, error, message, path}`.
func store(data: Dictionary) -> Dictionary:
	var encoded := _codec.encode(data)
	if not bool(encoded["ok"]):
		return encoded
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK and not DirAccess.dir_exists_absolute(path.get_base_dir()):
		return _fail("unwritable", "cannot create %s" % path.get_base_dir())
	var temporary := path + TMP_SUFFIX
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail(
			"unwritable",
			"cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())]
		)
	file.store_string(String(encoded["text"]))
	file.flush()
	file.close()
	if not _replace(temporary, path):
		DirAccess.remove_absolute(temporary)
		return _fail("unwritable", "cannot replace %s" % path)
	return _ok({"path": path})


func erase() -> bool:
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + TMP_SUFFIX)
	return true


## The name-side half of a confirmed New Game entry: `first_name` is set once
## and never overwritten (docs/08 §1.5 "the first name ever typed"); every
## distinct name joins `names` in order. Returns the healed record.
func record_name(record: Dictionary, player_name: String) -> Dictionary:
	var name := player_name.strip_edges()
	if name.is_empty():
		return record
	if _string(record.get("first_name")).is_empty():
		record["first_name"] = name
	var names := _strings(record.get("names"))
	if not names.has(name):
		names.append(name)
	record["names"] = names
	return record


## M08 "New Game, same her": the run just ended is appended to `runs`, and —
## only when it had reached the meta gate — its most-quoted memories are kept.
## `had_run` distinguishes a real ended run from the first-ever New Game (a
## fresh install at day 1 / turn 0 seals nothing, so `runs` counts restarts,
## not first starts).
func seal_run(record: Dictionary, run_name: String, had_run: bool, memories: Array) -> Dictionary:
	if had_run:
		var runs := _strings(record.get("runs"))
		var label := run_name.strip_edges()
		if label.is_empty():
			label = _string(record.get("first_name"))
		runs.append(label)
		while runs.size() > RUN_LIMIT:
			runs.remove_at(0)
		record["runs"] = runs
		if not memories.is_empty():
			record["memories"] = _kept_memories(memories)
	return record


## The top-`shadow.limit` of a run's true facts by the memory model's own
## ranking: importance (quotes) first, newest winning a tie — the same "what
## she cared about" order eviction uses, so the shadow keeps what the run
## proved she returns to.
func _kept_memories(entries: Array) -> Array:
	var ranked: Array[Dictionary] = []
	for i: int in range(entries.size()):
		var entry: Variant = entries[i]
		if not entry is Dictionary:
			continue
		var text := _string((entry as Dictionary).get(MemoryStore.ENTRY_TEXT))
		if text.is_empty():
			continue
		(
			ranked
			. append(
				{
					"text": text,
					"importance":
					float((entry as Dictionary).get(MemoryStore.ENTRY_IMPORTANCE, 0.0)),
					"order": i,
				}
			)
		)
	# Importance first; among equals the newest wins (Array.sort_custom is not
	# guaranteed stable, so the tie is broken on the insertion index, not on
	# luck).
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["importance"]) == float(b["importance"]):
				return int(a["order"]) > int(b["order"])
			return float(a["importance"]) > float(b["importance"])
	)
	var limit := maxi(0, MemoryRules.shadow_memory_limit())
	var kept: Array = []
	for i: int in range(mini(limit, ranked.size())):
		kept.append(String(ranked[i]["text"]))
	return kept


## A corrupt/hand-edited payload heals to the blank shape plus whatever keys
## parse: the four lists are string-filtered, never trusted.
func _heal(value: Variant) -> Dictionary:
	var record := blank()
	if not value is Dictionary:
		return record
	var payload := value as Dictionary
	record["first_name"] = _string(payload.get("first_name"))
	record["names"] = _strings(payload.get("names"))
	record["runs"] = _strings(payload.get("runs"))
	var memories: Array = []
	for item: Variant in _array(payload.get("memories")):
		var text := _string(item)
		if not text.is_empty():
			memories.append(text)
	record["memories"] = memories
	return record


func _replace(temporary: String, target: String) -> bool:
	var error := DirAccess.rename_absolute(temporary, target)
	if error == OK:
		return true
	DirAccess.remove_absolute(target)
	error = DirAccess.rename_absolute(temporary, target)
	return error == OK


func _ok(extra: Dictionary) -> Dictionary:
	var result := {"ok": true, "error": "", "message": ""}
	result.merge(extra, true)
	return result


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}


static func _string(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""


static func _strings(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for item: Variant in value:
		var text := _string(item)
		if not text.is_empty():
			out.append(text)
	return out


static func _array(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []
