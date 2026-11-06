class_name StageSteering
extends RefCounted
## docs/06 §4 — maps the docs/06 §3 dose onto the shipped control-vector files so
## the prototype can bind a new dose with a `--control-vector-scaled` relaunch.
##
## Pure: it reads `game/data/steering/vectors.json`, resolves each mapped file to
## a path llama-server can open, and builds the `control_vectors` entries the
## launcher takes. It never launches anything and never touches the server; the
## facade (`LLM.apply_stage_steering`) owns that.
##
## Three rules make the payload safe to launch:
##  * a key whose file cannot be resolved fails the *whole* payload. llama.cpp
##    logs "no valid control vector files passed" for a bad FNAME and then starts
##    healthy, so a partial set would run unsteered while the game believed it was
##    dosed — the same reason `LlamaServerProcess` validates the paths again.
##  * a nonzero-scale key that maps to no file must be *declared* under
##    `unbound`; anything else fails the payload (`control_vector_unmapped`). A
##    missing or unreadable map has no declarations, so it fails closed instead of
##    letting the caller "bind" an empty set and keep the stage bookkeeping while
##    the server runs unsteered.
##  * a scale of 0 binds no vector at all, so stage 0 (and a restored new game)
##    lands on a clean server instead of a `:0` no-op flag. Negative scales are
##    real payloads, not skipped (P3.19 r2 mechanism kept: an unmapped negative
##    fails `control_vector_unmapped` like a positive).
##
## `path_mix` is scheduled on `TurnRequest.dose` only while the narrative path
## is unassigned (P3.04): the map declares it under `unbound`, and
## `launch_for()` reports it there so the caller can say so in one log line
## instead of dropping the weight silently. Once a path exists the dose carries
## the keep vector's name (`possessive`/`aware`) — shipped and mapped — and
## the four prompt-only fallback paths schedule no path key at all (D21 +
## P3.19 r2/DES-7 ANCHOR).

const MAP_PATH := "res://data/steering/vectors.json"
## Exported builds keep `res://` inside the .pck, which a separate llama-server
## process cannot open; the bytes are extracted here once per launch (docs/07 §2
## "content in data", docs/06 §2 "vector files ship inside the game pack").
const EXTRACT_DIR := "user://steering"
const GGUF_MAGIC := "GGUF"

var _files := {}  # name -> res:// file
var _notes := {}  # name -> provenance text from the data file
var _unbound := {}  # name -> why it binds no file yet
var _error := ""
var _resolved := {}  # res:// file -> global path, memoized once non-empty


## Reads the map. Returns false when it is missing or has no usable row, which
## leaves the file tables empty: the caller then keeps the old dose (there is
## nothing to bind) and logs the reason from `last_error()`.
func load_map(path := MAP_PATH) -> bool:
	_error = ""
	_files = {}
	_notes = {}
	_unbound = {}
	if not FileAccess.file_exists(path):
		_error = "%s missing" % path
		push_warning("StageSteering: %s missing; stage changes bind no dose" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parse_document(parsed):
		_error = "%s has no usable `vectors` table" % path
		push_warning("StageSteering: %s has no usable `vectors` table" % path)
		return false
	return true


## Loads a parsed document into the tables. A row is usable when it names a
## non-empty file; malformed rows are dropped (and warned about) so one typo
## cannot take the rest of the vector library with it. False when no row is.
func parse_document(parsed: Variant) -> bool:
	_files = {}
	_notes = {}
	_unbound = {}
	if not parsed is Dictionary:
		return false
	var document: Dictionary = parsed
	var vectors: Variant = document.get("vectors", {})
	if not vectors is Dictionary:
		return false
	for name: Variant in vectors:
		var row: Variant = vectors[name]
		if not row is Dictionary:
			push_warning("StageSteering: vector '%s' is not an object — skipped" % str(name))
			continue
		var file := String((row as Dictionary).get("file", "")).strip_edges()
		if file.is_empty():
			push_warning("StageSteering: vector '%s' has no file — skipped" % str(name))
			continue
		_files[String(name)] = file
		_notes[String(name)] = String((row as Dictionary).get("doc", ""))
	var stored_unbound: Variant = document.get("unbound", {})
	if stored_unbound is Dictionary:
		for name: Variant in stored_unbound:
			_unbound[String(name)] = String(stored_unbound[name])
	return not _files.is_empty()


## The res:// file mapped to a dose key, or "" when it binds none.
func file_for(name: String) -> String:
	return String(_files.get(name, ""))


## Why a dose key binds no file yet (docs/06 §2); "" when it is not in the map.
func unbound_reason(name: String) -> String:
	return String(_unbound.get(name, ""))


func known_keys() -> Array[String]:
	var names: Array[String] = []
	for name: Variant in _files:
		names.append(String(name))
	return names


## `{"ok", "vectors": [{"path", "scale"}], "scheduled", "unbound", "error"}`.
## `vectors` holds only nonzero scales and only resolved, GGUF-magic files —
## negative scales are real: ANCHOR's lucid binds negative (paths.json
## `anchors.lucid`, P3.19 r2), and an unmapped negative key fails
## `control_vector_unmapped` exactly like a positive one.
## `ok` is false when a bound key cannot be resolved, a nonzero-scale key is
## neither mapped nor declared unbound, or its scale is unusable — the caller
## must then keep the old dose rather than relaunch a server that would come up
## unsteered (see the class note).
func launch_for(dose: Dictionary) -> Dictionary:
	var scheduled: Array[String] = []
	var unbound: Array[String] = []
	var vectors: Array = []
	for name: Variant in dose:
		var key := String(name)
		var scale := float(dose[name])
		if not is_finite(scale):
			return _failed(
				"control_vector_invalid",
				"dose '%s' is not a finite scale (%s)" % [key, str(dose[name])]
			)
		if scale == 0.0:
			continue
		scheduled.append(key)
		if not _files.has(key):
			if _unbound.has(key):
				unbound.append(key)
				continue
			return _failed(
				"control_vector_unmapped",
				"dose '%s' maps to no vector file and is not declared unbound" % key
			)
		var file := resolve_file(String(_files[key]))
		if file.is_empty():
			return _failed(
				"control_vector_missing",
				"vector file for dose '%s' not found (%s)" % [key, String(_files[key])]
			)
		if not has_gguf_magic(file):
			return _failed("control_vector_invalid", "not a GGUF control vector: %s" % file)
		vectors.append({"path": file, "scale": scale})
	return {
		"ok": true,
		"vectors": vectors,
		"scheduled": scheduled,
		"unbound": unbound,
		"error": {},
	}


## A global path llama-server can open, or "" when the file is gone. Running from
## source resolves straight to the project file; an exported build extracts the
## packed bytes into `user://steering/` on first use (a .pck member is not a file
## a separate process can read).
func resolve_file(res_path: String) -> String:
	var known := String(_resolved.get(res_path, ""))
	if not known.is_empty() and FileAccess.file_exists(known):
		return known
	var global := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global):
		_resolved[res_path] = global
		return global
	if not FileAccess.file_exists(res_path):
		return ""
	var extracted := extract_to(res_path, EXTRACT_DIR)
	if not extracted.is_empty():
		_resolved[res_path] = extracted
	return extracted


## Copy a packed `res://` file to `dir` and return the real path, or "" when the
## bytes are unreadable. Split out so the extraction branch is testable when the
## project runs from source (where `res://` is already a directory).
func extract_to(res_path: String, dir: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(res_path)
	if bytes.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var target := dir.path_join(res_path.get_file())
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return ProjectSettings.globalize_path(target)


## A GGUF container starts with the four ASCII bytes "GGUF". llama.cpp only
## rejects a *missing* file loudly, so a truncated copy would otherwise launch a
## server that silently ignores the vector.
static func has_gguf_magic(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var magic := file.get_buffer(4)
	file.close()
	return magic.size() == 4 and magic.get_string_from_utf8() == GGUF_MAGIC


## Log rendering of a launch payload: `malice.gguf 4.5` (file, not the whole
## path — the log line already names the stage and the count).
static func describe(vectors: Array) -> String:
	var parts := PackedStringArray()
	for vector: Variant in vectors:
		if not vector is Dictionary:
			continue
		var entry: Dictionary = vector
		parts.append(
			"%s %s" % [String(entry.get("path", "")).get_file(), str(entry.get("scale", 0.0))]
		)
	return ", ".join(parts)


func last_error() -> String:
	return _error


func _failed(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"vectors": [],
		"scheduled": [],
		"unbound": [],
		"error": {"code": code, "message": message},
	}
