class_name MetaStateM01
extends RefCounted
## MetaStateM01 — the one file docs/05 §1.1 M02–M05 need to remember across a
## session: `user://.leila/meta_state.json`. Split from MetaEventsM01 so the
## privacy contract sits in one place, the way ShadowStore owns the shadow.
##
## PRIVACY — the whole of the file, nothing else is ever written to it:
##   {
##     "format":   "leila.meta_state",   envelope tag, read-only
##     "version":  1,                    layout version, read-only
##     "last_seen": <unix seconds>,      the last moment the app knew they were
##                                       here; M05 measures the gap from it.
##     "last_quit": {"method": "window_x" | "alt_f4" | "button" |
##                            "during_line", "at": <unix seconds>},
##                                       M04's "how you left" ({} before the
##                                       first recorded quit).
##     "she_closed": {"at": <unix seconds>},
##                                       M02's marker: present until the next
##                                       title screen has shown it once.
##     "session":  {"start": <unix seconds>}   this session's start (M05).
##   }
##   Never stored: conversation text, the player's name, a path outside
##   `user://`, an environment read (the OS username is opt-in and lives in
##   Settings), telemetry, device identifiers or a network address. There is no
##   network code here at all (docs/05 §0 rule 2).
##
## No checksum: unlike a save slot, the worst a hand-edited file can do is make
## her mention a different hour (docs/05 §0 rule 5 — every effect is reviewable
## and none of it can hurt the player). Reads heal every field, so a torn write
## or a garbage file reads as "a first launch" instead of an error, and the next
## real write simply replaces it (tmp + rename, the SaveSlots crash rule).

const PATH := "user://.leila/meta_state.json"
const FORMAT := "leila.meta_state"
const VERSION := 1
const TMP_SUFFIX := ".tmp"
## docs/05 §1.1 M04's four documented ways to leave.
const QUIT_METHODS: Array[String] = ["during_line", "button", "alt_f4", "window_x"]

## Test seam (`SaveSystem.shadow_path`): point the file at a scratch path.
var path := PATH


## The shape every reader sees before the first recorded session.
static func blank() -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"last_seen": 0,
		"last_quit": {},
		"she_closed": {},
		"session": {},
	}


func load_state() -> Dictionary:
	if not FileAccess.file_exists(path):
		return blank()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return blank()
	return heal(parsed as Dictionary)


## Every field healed to its documented type: a non-numeric stamp is 0, an
## unknown quit method is dropped, and a negative (clock moved backwards) reads
## as "never seen". A damaged file therefore degrades to a first launch.
static func heal(doc: Dictionary) -> Dictionary:
	var record := blank()
	record["last_seen"] = maxi(0, int(_number(doc.get("last_seen"))))
	record["last_quit"] = healed_quit(_dict(doc.get("last_quit")))
	record["she_closed"] = healed_stamp(_dict(doc.get("she_closed")), "at")
	record["session"] = healed_stamp(_dict(doc.get("session")), "start")
	return record


static func healed_quit(row: Dictionary) -> Dictionary:
	var method := str(row.get("method", "")).strip_edges()
	if not QUIT_METHODS.has(method):
		return {}
	var at := maxi(0, int(_number(row.get("at"))))
	return {"method": method, "at": at}


static func healed_stamp(row: Dictionary, key: String) -> Dictionary:
	var stamp := maxi(0, int(_number(row.get(key))))
	return {key: stamp} if stamp > 0 else {}


## Atomic write: full bytes to a temporary file, then rename over the target. A
## platform that refuses to replace gets one remove + retry (the SaveSlots
## rule); a failure is a warning, never a thrown error.
func store(state: Dictionary) -> bool:
	if not writable():
		return false
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	var temporary := path + TMP_SUFFIX
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("MetaStateM01: cannot write %s" % temporary)
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(path)
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true


## A headless suite that never pointed `path` at a scratch file must not create
## the real one; any other build writes whenever the game does.
func writable() -> bool:
	return DisplayServer.get_name() != "headless" or path != PATH


static func _dict(value: Variant) -> Dictionary:
	return (value as Dictionary) if value is Dictionary else {}


static func _number(value: Variant) -> float:
	if value is int or value is float:
		return float(value)
	return 0.0
