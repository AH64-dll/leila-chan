extends GdUnitTestSuite
## P4.08 model check. Each case writes its own temp files under user:// and removes them
## afterwards. The "hello" digest is the well-known SHA-256 of those five bytes.

const MODEL_PATH := "user://loading_preflight_model.bin"
const CACHE_PATH := "user://loading_preflight_cache.json"
const HELLO_SHA256 := "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
const ZEROS_SHA256 := "0000000000000000000000000000000000000000000000000000000000000000"
const MIB := 1024 * 1024


class Counter:
	extends RefCounted
	var calls := 0
	var fractions: Array = []

	func bump(fraction: float) -> void:
		calls += 1
		fractions.append(fraction)


func before_test() -> void:
	_remove(MODEL_PATH)
	_remove(CACHE_PATH)


func after_test() -> void:
	_remove(MODEL_PATH)
	_remove(CACHE_PATH)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _expected(size: int, sha: String) -> Dictionary:
	return {"file": "loading_preflight_model.bin", "bytes": size, "sha256": sha}


func _check(expected: Dictionary, on_progress := Callable()) -> Dictionary:
	return ModelPreflight.check(MODEL_PATH, expected, CACHE_PATH, on_progress)


func test_missing_file_is_missing_model() -> void:
	var result := ModelPreflight.check(
		"user://no_such_model.bin", _expected(5, HELLO_SHA256), CACHE_PATH
	)
	assert_bool(bool(result["ok"])).is_false()
	assert_str(String(result["code"])).is_equal("missing_model")
	assert_str(String(result["path"])).is_equal("user://no_such_model.bin")


func test_empty_path_is_missing_model() -> void:
	var result := ModelPreflight.check("", _expected(5, HELLO_SHA256), CACHE_PATH)
	assert_str(String(result["code"])).is_equal("missing_model")


func test_wrong_size_is_wrong_hash_and_is_not_hashed() -> void:
	_write(MODEL_PATH, "hello".to_utf8_buffer())
	var counter := Counter.new()
	var result := _check(_expected(6, HELLO_SHA256), counter.bump)
	assert_str(String(result["code"])).is_equal("wrong_hash")
	assert_int(counter.calls).is_equal(0)


func test_right_size_and_wrong_hash_fails_and_writes_no_cache() -> void:
	_write(MODEL_PATH, "hellx".to_utf8_buffer())
	var result := _check(_expected(5, HELLO_SHA256))
	assert_str(String(result["code"])).is_equal("wrong_hash")
	assert_bool(FileAccess.file_exists(CACHE_PATH)).is_false()


func test_correct_hash_passes_and_writes_the_cache() -> void:
	_write(MODEL_PATH, "hello".to_utf8_buffer())
	var result := _check(_expected(5, HELLO_SHA256))
	assert_bool(bool(result["ok"])).is_true()
	assert_bool(bool(result["hashed"])).is_true()
	assert_bool(FileAccess.file_exists(CACHE_PATH)).is_true()


func test_second_run_trusts_the_cache() -> void:
	_write(MODEL_PATH, "hello".to_utf8_buffer())
	_check(_expected(5, HELLO_SHA256))
	var counter := Counter.new()
	var result := _check(_expected(5, HELLO_SHA256), counter.bump)
	assert_bool(bool(result["ok"])).is_true()
	assert_bool(bool(result["hashed"])).is_false()
	assert_int(counter.calls).is_equal(0)


func test_a_changed_file_is_hashed_again() -> void:
	_write(MODEL_PATH, "hello".to_utf8_buffer())
	_check(_expected(5, HELLO_SHA256))
	# Modified times have one-second resolution, so wait past a tick before rewriting.
	await get_tree().create_timer(1.1).timeout
	_write(MODEL_PATH, "hellp".to_utf8_buffer())
	var result := _check(_expected(5, HELLO_SHA256))
	assert_str(String(result["code"])).is_equal("wrong_hash")


func test_a_corrupt_cache_counts_as_no_cache() -> void:
	_write(MODEL_PATH, "hello".to_utf8_buffer())
	_check(_expected(5, HELLO_SHA256))
	var junk := ["not json {", "[1, 2, 3]", '{"path": 5, "sha256": true}']
	for text: String in junk:
		_write_text(CACHE_PATH, text)
		var counter := Counter.new()
		var result := _check(_expected(5, HELLO_SHA256), counter.bump)
		assert_bool(bool(result["ok"])).is_true()
		assert_bool(bool(result["hashed"])).is_true()
		assert_int(counter.calls).is_greater(0)


func test_a_large_file_reports_progress_in_4_mib_chunks() -> void:
	var bytes := PackedByteArray()
	bytes.resize(9 * MIB)
	_write(MODEL_PATH, bytes)
	var counter := Counter.new()
	var result := _check(_expected(9 * MIB, ZEROS_SHA256), counter.bump)
	assert_str(String(result["code"])).is_equal("wrong_hash")
	assert_int(counter.calls).is_equal(3)
	assert_float(float(counter.fractions[0])).is_equal_approx(4.0 / 9.0, 0.0001)
	assert_float(float(counter.fractions[2])).is_equal(1.0)


func test_a_cancelled_check_stops_after_one_chunk_and_writes_no_cache() -> void:
	var bytes := PackedByteArray()
	bytes.resize(9 * MIB)
	_write(MODEL_PATH, bytes)
	var counter := Counter.new()
	var polls := [0]
	# The first poll lets one chunk through; the second stops the hash.
	var cancel_after_first: Callable = func() -> bool:
		polls[0] += 1
		return polls[0] > 1
	var result := ModelPreflight.check(
		MODEL_PATH, _expected(9 * MIB, ZEROS_SHA256), CACHE_PATH, counter.bump, cancel_after_first
	)
	assert_bool(bool(result["ok"])).is_false()
	assert_str(String(result["code"])).is_equal("cancelled")
	assert_int(counter.calls).is_equal(1)
	assert_bool(FileAccess.file_exists(CACHE_PATH)).is_false()


func test_load_expected_reads_the_shipped_model_json() -> void:
	var expected := ModelPreflight.load_expected()
	assert_str(String(expected.get("file", ""))).is_equal("Qwen3.5-4B-Q4_K_M.gguf")
	assert_int(int(expected.get("bytes", 0))).is_equal(2740937888)
	assert_str(String(expected.get("sha256", ""))).is_equal(
		"00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"
	)


func test_load_expected_is_empty_when_the_file_is_missing() -> void:
	var expected := ModelPreflight.load_expected("res://data/no_such_model.json")
	assert_bool(expected.is_empty()).is_true()
