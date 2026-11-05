class_name MetaNotesStore
extends RefCounted
## MetaNotesStore — the only place docs/05 §1.4's file events touch the disk.
##
## Split out of MetaEventsM31 the way SaveSlots is split out of SaveSystem: this
## owns bytes and paths, the module owns *when*. Everything is relative to
## `root`, and `root` must itself stay under `user://` (docs/05 §0 rule 1), so a
## path that climbs (`..`), carries another scheme or an absolute root is
## REFUSED, never normalised or cleaned up. The player's name reaches a path
## exactly once (M31's `for_<name>.txt`) and only through `slug()`, which cannot
## produce a separator, a dot or an escape.
##
## Nothing here deletes, moves or reads a file the game did not write: `read()`
## and `list()` are handed only the module's own two folders or its ledger.
##
## Corruption is a value, like SaveSlots: every read returns text ("" on
## failure) and every write returns {ok, path, error}.

## docs/05 §0 rule 1: the only scheme the game may write under.
const USER_PREFIX := "user://"

var root := "user://"
var letters := "letters"
var diary := "diary"
var slot_names := "saves/meta_names.json"


func configure(paths: Dictionary) -> void:
	letters = String(paths.get("letters", letters))
	diary = String(paths.get("diary", diary))
	slot_names = String(paths.get("slot_names", slot_names))


## A root outside `user://` is a programming error, not a setting: the store
## then writes nothing at all (fail closed, docs/05 §0 rule 1).
func root_ok() -> bool:
	var normal := root.replace("\\", "/").strip_edges()
	if not normal.begins_with(USER_PREFIX):
		return false
	# The scheme's own colon is the prefix; anything after it may not carry one
	# (that is how `res://`, a drive letter or another scheme is refused).
	var rest := normal.substr(USER_PREFIX.length())
	if rest.contains("..") or rest.contains(":"):
		return false
	return not rest.begins_with("/")


func rel_ok(rel: String) -> bool:
	if not root_ok():
		return false
	var normal := rel.replace("\\", "/").strip_edges()
	if normal.is_empty() or normal.begins_with("/") or normal.contains(".."):
		return false
	return not normal.contains(":")


func path(rel: String) -> String:
	return root.path_join(rel.replace("\\", "/").strip_edges())


func dir_for(kind: String) -> String:
	if kind == "letter":
		return letters
	if kind == "diary":
		return diary
	return slot_names.get_base_dir()


## A note id is one of ours only inside the two note folders — the Extras reader
## hands user-visible ids straight back here, so this is the read gate.
func note_ok(rel: String) -> bool:
	if not rel_ok(rel):
		return false
	var normal := rel.replace("\\", "/").strip_edges()
	for folder: String in [letters, diary]:
		if normal.begins_with(folder.replace("\\", "/").strip_edges() + "/"):
			return not normal.ends_with("/")
	return false


## Writes through a directory that is created on demand. A read-only folder is
## the documented M31 fallback, never an error the player sees.
func write(rel: String, text: String) -> Dictionary:
	if not rel_ok(rel):
		return {"ok": false, "path": "", "error": "outside_user_dir"}
	var full := path(rel)
	var folder := full.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK and not DirAccess.dir_exists_absolute(folder):
		return {"ok": false, "path": full, "error": "unwritable"}
	var file := FileAccess.open(full, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": full, "error": "unwritable"}
	file.store_string(text)
	file.flush()
	file.close()
	return {"ok": true, "path": full, "error": ""}


func read(rel: String) -> String:
	if not rel_ok(rel):
		return ""
	var full := path(rel)
	if not FileAccess.file_exists(full):
		return ""
	return FileAccess.get_file_as_string(full)


## The `.txt` notes in one of our folders, sorted by name. A missing folder is
## an empty shelf, not an error.
func list_notes(kind: String) -> Array[String]:
	var out: Array[String] = []
	var folder := dir_for(kind)
	if not rel_ok(folder):
		return out
	var dir := DirAccess.open(path(folder))
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".txt") and not file.begins_with("."):
			out.append(file)
	out.sort()
	return out


func mtime(rel: String) -> int:
	if not rel_ok(rel):
		return 0
	return FileAccess.get_modified_time(path(rel))


func ensure_folder(kind: String) -> bool:
	var folder := dir_for(kind)
	if not rel_ok(folder):
		return false
	DirAccess.make_dir_recursive_absolute(path(folder))
	return DirAccess.dir_exists_absolute(path(folder))


func global_path(kind: String) -> String:
	return ProjectSettings.globalize_path(path(dir_for(kind)))


## The player's name as a file-name fragment: lowercase ASCII word characters,
## collapsed, bounded, with a documented fallback. `..`, `/`, `\`, dots and
## colons cannot survive it (docs/05 §0 rule 1).
func slug(name: String, limit: int, fallback: String) -> String:
	var out := ""
	for index: int in name.length():
		var code := name.unicode_at(index)
		var keep := (code >= 48 and code <= 57) or (code >= 65 and code <= 90)
		keep = keep or (code >= 97 and code <= 122)
		if keep:
			out += name[index].to_lower()
		elif not out.is_empty() and not out.ends_with("_"):
			out += "_"
	out = out.substr(0, maxi(1, limit)).trim_suffix("_").strip_edges()
	return out if not out.is_empty() else fallback


## Cut to `limit` on a sentence boundary when one is close enough, so a capped
## letter does not end mid-word.
func clip(text: String, limit: int) -> String:
	var clean := text.strip_edges()
	if limit <= 0 or clean.length() <= limit:
		return clean
	var cut := clean.substr(0, limit)
	var boundary := cut.rfind(". ")
	if boundary >= limit / 2:
		cut = cut.substr(0, boundary + 1)
	return cut.strip_edges()


## `day_07.txt` → 7. Digits only, so a hostile file name cannot steer it.
func day_of(file: String) -> int:
	return int_text(file.trim_prefix("day_").trim_suffix(".txt"))


## The first integer in `text`, 0 when there is none (JSON numbers arrive as
## floats, file names as strings; `int("")` would be a silent 0 anyway, this is
## explicit).
static func int_text(text: String) -> int:
	var digits := ""
	for index: int in text.length():
		var code := text.unicode_at(index)
		if code >= 48 and code <= 57:
			digits += text[index]
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 0


## M33/M34's ledger beside the save slots: {"version", "slots": {slot: row}}.
func read_ledger() -> Dictionary:
	var text := read(slot_names)
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var rows: Variant = (parsed as Dictionary).get("slots")
	return (rows as Dictionary).duplicate(true) if rows is Dictionary else {}


func write_ledger(rows: Dictionary, keep: int) -> Dictionary:
	var capped := {}
	var keys: Array = rows.keys()
	keys.sort()
	for key: Variant in keys:
		if capped.size() >= maxi(1, keep):
			break
		capped[str(key)] = rows[key]
	return write(slot_names, JSON.stringify({"version": 1, "slots": capped}, "\t", true))
