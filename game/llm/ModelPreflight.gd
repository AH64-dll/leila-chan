class_name ModelPreflight
extends RefCounted
## P4.08 model check, run on the loading screen's worker thread before the engine loads
## the model. It touches no Node. A file whose path, size and modified time match a
## verified record in the cache is trusted; anything else is hashed in full.

const CHUNK_BYTES := 4 * 1024 * 1024
const EXPECTED_PATH := "res://data/model.json"
const CACHE_PATH := "user://model_check.json"
const HASH_LENGTH := 64


## The expected file name, size and SHA-256 from game/data/model.json. Empty when the
## file is missing or does not hold a JSON object.
static func load_expected(path := EXPECTED_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


## Checks the model file against expected. Returns {ok:true, hashed} when the file is the
## expected one, or {ok:false, code, path} with code missing_model, wrong_hash or cancelled.
## on_progress(fraction) is called once per 4 MiB hashed. is_cancelled() is polled before each
## chunk; a true answer returns cancelled and writes no cache record.
static func check(
	model_path: String,
	expected: Dictionary,
	cache_path := CACHE_PATH,
	on_progress := Callable(),
	is_cancelled := Callable()
) -> Dictionary:
	if model_path.is_empty() or not FileAccess.file_exists(model_path):
		return _fail("missing_model", model_path)
	var file := FileAccess.open(model_path, FileAccess.READ)
	if file == null:
		return _fail("missing_model", model_path)
	var size := file.get_length()
	var expected_size := int(expected.get("bytes", -1))
	var expected_hash := String(expected.get("sha256", "")).to_lower()
	if size != expected_size or expected_hash.length() != HASH_LENGTH:
		return _fail("wrong_hash", model_path)
	var modified := FileAccess.get_modified_time(model_path)
	var record := _read_cache(cache_path)
	if _cache_matches(record, model_path, size, modified, expected_hash):
		return {"ok": true, "hashed": false}
	var digest := _sha256(file, size, on_progress, is_cancelled)
	if _cancel_requested(is_cancelled):
		return _fail("cancelled", model_path)
	if digest != expected_hash:
		return _fail("wrong_hash", model_path)
	var verified := {
		"path": model_path,
		"bytes": size,
		"modified": modified,
		"sha256": expected_hash,
	}
	_write_cache(cache_path, verified)
	return {"ok": true, "hashed": true}


static func _fail(code: String, path: String) -> Dictionary:
	return {"ok": false, "code": code, "path": path}


## The cache record, or {} when the file is missing, is not a JSON object, or has a field
## of the wrong type. A corrupt cache counts as no cache at all.
static func _read_cache(cache_path: String) -> Dictionary:
	if not FileAccess.file_exists(cache_path):
		return {}
	## The instance parser stays quiet on junk; parse_string would log an engine error.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(cache_path)) != OK:
		return {}
	if not (json.data is Dictionary):
		return {}
	var record: Dictionary = json.data
	if not (record.get("path") is String and record.get("sha256") is String):
		return {}
	if not (_is_number(record.get("bytes")) and _is_number(record.get("modified"))):
		return {}
	return record


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _cache_matches(
	record: Dictionary, path: String, size: int, modified: int, sha: String
) -> bool:
	if record.is_empty():
		return false
	return (
		String(record["path"]) == path
		and int(record["bytes"]) == size
		and int(record["modified"]) == modified
		and String(record["sha256"]) == sha
	)


## SHA-256 of the first size bytes, read in CHUNK_BYTES pieces. Returns "" on a short
## read, which the caller reports as a mismatch, or when is_cancelled asks to stop. The
## flag is read before each chunk.
static func _sha256(
	file: FileAccess, size: int, on_progress: Callable, is_cancelled: Callable
) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var done := 0
	while done < size:
		if _cancel_requested(is_cancelled):
			return ""
		var chunk := file.get_buffer(mini(CHUNK_BYTES, size - done))
		if chunk.is_empty():
			return ""
		ctx.update(chunk)
		done += chunk.size()
		if on_progress.is_valid():
			on_progress.call(float(done) / float(size))
	return ctx.finish().hex_encode()


static func _cancel_requested(is_cancelled: Callable) -> bool:
	return is_cancelled.is_valid() and bool(is_cancelled.call())


static func _write_cache(cache_path: String, record: Dictionary) -> void:
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(record))
