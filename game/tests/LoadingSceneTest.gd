extends GdUnitTestSuite
## P4.08 loading screen. A scripted engine stands in for LeilaLLM, so no model is read and
## nothing waits on a real load. Each case builds the screen, lets its Thread run, and
## checks what the player would see.

const SCENE := preload("res://scenes/Loading.tscn")
const LoadingScript := preload("res://scenes/Loading.gd")
const BootScript := preload("res://scenes/Boot.gd")
const MODEL_PATH := "user://loading_scene_model.bin"
const CACHE_PATH := "user://loading_scene_cache.json"
const SETTINGS_PATH := "user://loading_scene_settings.cfg"
const HELLO_SHA256 := "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
const EXPECTED := {"file": "loading_scene_model.bin", "bytes": 5, "sha256": HELLO_SHA256}
## A load that runs out of memory on the graphics card.
const OOM_FAILURE := {
	"ok": false,
	"device": "CUDA0",
	"error": {"code": "native_error", "message": "CUDA error: out of memory"},
}
const GPU_LOAD := {"ok": true, "device": "CUDA0", "device_type": "gpu", "gpu_layers": 20}
const CPU_LOAD := {"ok": true, "device": "CPU", "device_type": "cpu", "gpu_layers": 0}


## A native backend with no engine GDExtension registered.
class NoEngine:
	extends NativeBackend

	func _create_default_engine() -> Object:
		return null


## A transport that is not native: the server path.
class ServerStub:
	extends LLMBackend


## Scripted stand-in for LeilaLLM. Load results are consumed in order and the last one
## repeats. load_progress() reports the scripted values on successive calls. With
## block_until_cancelled set, a load waits until cancel_load() is called, then reports the
## cancelled code, as the engine does.
class FakeLoadEngine:
	extends RefCounted
	const CANCEL_WAIT_MS := 5000
	var load_results: Array = [{"ok": true, "load_ms": 1, "n_ctx": 8192, "devices": ["CUDA0"]}]
	var load_calls := 0
	var load_delay_ms := 0
	var block_until_cancelled := false
	var cancel_calls := 0
	var progress_values: Array = []
	var _progress_calls := 0
	var _lock := Mutex.new()

	func load_model(_config: Dictionary) -> Dictionary:
		var index := mini(load_calls, load_results.size() - 1)
		load_calls += 1
		if block_until_cancelled:
			return _wait_for_cancel()
		OS.delay_msec(load_delay_ms)
		return load_results[index]

	func cancel_load() -> void:
		_lock.lock()
		cancel_calls += 1
		_lock.unlock()

	## Worker thread. Polls until cancel_load() arrives, or gives up after CANCEL_WAIT_MS so
	## a missed cancel fails the test instead of hanging it.
	func _wait_for_cancel() -> Dictionary:
		var waited := 0
		while not _cancel_requested() and waited < CANCEL_WAIT_MS:
			OS.delay_msec(5)
			waited += 5
		return {"ok": false, "error": {"code": "cancelled", "message": "load cancelled"}}

	func _cancel_requested() -> bool:
		_lock.lock()
		var out := cancel_calls > 0
		_lock.unlock()
		return out

	func load_progress() -> float:
		if progress_values.is_empty():
			return 0.0
		var index := mini(_progress_calls, progress_values.size() - 1)
		_progress_calls += 1
		return float(progress_values[index])

	func is_loaded() -> bool:
		return false

	func unload() -> void:
		pass

	func set_control_vectors(_vectors: Array) -> Dictionary:
		return {"ok": true, "applied": true, "set_ms": 0.0}


var _saved_backend: LLMBackend = null
var _saved_settings_path := ""
var _saved_fast_mode := false


## Settings point at a scratch file, so a fast-mode test never writes the player's file.
func before_test() -> void:
	_saved_backend = LLM.get_backend()
	_saved_settings_path = Settings.settings_path
	_saved_fast_mode = Settings.fast_mode
	Settings.settings_path = SETTINGS_PATH
	Settings.fast_mode = false
	_remove(SETTINGS_PATH)
	_remove(MODEL_PATH)
	_remove(CACHE_PATH)


func after_test() -> void:
	LLM.set_backend(_saved_backend)
	Settings.settings_path = _saved_settings_path
	Settings.fast_mode = _saved_fast_mode
	_remove(SETTINGS_PATH)
	_remove(MODEL_PATH)
	_remove(CACHE_PATH)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_model() -> void:
	var file := FileAccess.open(MODEL_PATH, FileAccess.WRITE)
	file.store_string("hello")
	file.close()


func _native(engine: Object) -> NativeBackend:
	return NativeBackend.new({"model_path": MODEL_PATH}, engine)


## Installs the backend, builds the screen without navigating, and adds it to the tree.
func _spawn(backend: LLMBackend, expected: Dictionary = EXPECTED) -> Node:
	LLM.set_backend(backend)
	var screen: Node = auto_free(SCENE.instantiate())
	screen.set("navigate_on_finish", false)
	screen.set("cache_path", CACHE_PATH)
	screen.set("expected_override", expected)
	add_child(screen)
	return screen


func _wait_until(predicate: Callable, timeout_ms := 8000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _finished(screen: Node) -> bool:
	return String(screen.get("finished_scene")) != ""


func _line(screen: Node) -> String:
	return (screen.get_node("Margin/Column/Line") as Label).text


func _fix(screen: Node) -> String:
	return (screen.get_node("Margin/Column/Fix") as Label).text


func _press(screen: Node, label: String) -> bool:
	for child in screen.get_node("Margin/Column/Actions").get_children():
		var button := child as Button
		if button != null and button.text == label:
			button.pressed.emit()
			return true
	return false


func _read_loading_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/loading.json")
	)
	if parsed is Dictionary:
		return parsed
	return {}


func test_server_backend_finishes_at_once() -> void:
	var screen := _spawn(ServerStub.new())
	await get_tree().process_frame
	assert_bool(_finished(screen)).is_true()
	assert_str(String(screen.get("finished_scene"))).is_equal(BootScript.next_scene())


func test_missing_model_shows_the_missing_model_text() -> void:
	var engine := FakeLoadEngine.new()
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_str(_line(screen)).is_equal("The porch light is on, but nobody is home.")
	var expected_fix := (
		"The game's model file is missing. It should be here:\n%s\n" % MODEL_PATH
		+ "Verify the game files in Steam, or reinstall the game."
	)
	assert_str(_fix(screen)).is_equal(expected_fix)
	assert_array(screen.call("current_actions")).is_equal(["retry", "quit"])
	assert_int(engine.load_calls).is_equal(0)


func test_load_failure_shows_load_failed_with_the_detail() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [
		{"ok": false, "error": {"code": "native_error", "message": "CUDA error: out of memory"}},
	]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_str(_line(screen)).is_equal("She couldn't get up today.")
	var expected_fix := (
		"The model could not load, usually because there isn't enough memory. "
		+ "It needs about 4 GB of graphics memory or 8 GB of system memory. "
		+ "Close other programs and try again.\nDetails: CUDA error: out of memory"
	)
	assert_str(_fix(screen)).is_equal(expected_fix)
	assert_array(screen.call("current_actions")).is_equal(["retry", "quit"])
	assert_bool(_finished(screen)).is_false()


func test_retry_after_a_failed_load_succeeds() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	# A failed load makes three attempts (the device, 20 layers, the processor), so the
	# first screen's load uses up the first three results.
	var failed := {"ok": false, "error": {"code": "native_error", "message": "out of memory"}}
	engine.load_results = [failed, failed, failed, {"ok": true, "devices": ["CUDA0"]}]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_bool(_press(screen, "Try again")).is_true()
	var done := await _wait_until(func() -> bool: return _finished(screen))
	assert_bool(done).is_true()
	assert_int(engine.load_calls).is_equal(4)
	assert_str(String(screen.get("finished_scene"))).is_equal(BootScript.next_scene())


func test_no_gpu_shows_the_notice_and_continue_finishes() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [{"ok": true, "devices": [{"name": "CPU", "type": "cpu"}]}]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_str(_line(screen)).is_equal(
		"She's moving slowly today. She asks you to be patient with her."
	)
	var expected_fix := (
		"No supported graphics card was found, so the game is running on your processor. "
		+ "Replies will be slower. Updating your graphics driver may help."
	)
	assert_str(_fix(screen)).is_equal(expected_fix)
	assert_array(screen.call("current_actions")).is_equal(["fast", "continue", "quit"])
	assert_bool(_finished(screen)).is_false()
	assert_bool(_press(screen, "Continue")).is_true()
	assert_bool(_finished(screen)).is_true()


func test_a_load_without_devices_skips_the_gpu_check() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [{"ok": true, "n_ctx": 8192}]
	var screen := _spawn(_native(engine))
	var done := await _wait_until(func() -> bool: return _finished(screen))
	assert_bool(done).is_true()
	assert_str(_fix(screen)).is_empty()


func test_no_engine_shows_only_quit() -> void:
	var screen := _spawn(NoEngine.new({"model_path": MODEL_PATH}))
	assert_str(_line(screen)).is_equal("The house is there. The door isn't.")
	assert_str(_fix(screen)).is_equal(
		(
			"A game library is missing or could not start. "
			+ "Verify the game files in Steam, or reinstall the game."
		)
	)
	assert_array(screen.call("current_actions")).is_equal(["quit"])
	assert_bool(_finished(screen)).is_false()


func test_the_bar_never_decreases_during_one_attempt() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_delay_ms = 40
	engine.progress_values = [0.0, 0.2, 0.5, 0.4, 0.9, 0.3, 1.0]
	var screen := _spawn(_native(engine))
	var bar: ProgressBar = screen.get_node("Margin/Column/Progress")
	var last := -1.0
	var decreased := false
	var deadline := Time.get_ticks_msec() + 8000
	while not _finished(screen) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if bar.value < last:
			decreased = true
		last = bar.value
	assert_bool(decreased).is_false()
	assert_bool(_finished(screen)).is_true()
	assert_float(bar.value).is_equal(1.0)


func test_gpu_oom_on_the_processor_says_so() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [OOM_FAILURE, OOM_FAILURE, CPU_LOAD]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_str(_line(screen)).is_equal(
		"She's so tired tonight. She asks you to be patient with her."
	)
	assert_str(_fix(screen)).is_equal(
		(
			"Your graphics card doesn't have enough free memory for the model, "
			+ "so the game is running on your processor. "
			+ "Replies will be slower. Closing other programs may help."
		)
	)
	assert_array(screen.call("current_actions")).is_equal(["fast", "continue", "quit"])
	assert_bool(_finished(screen)).is_false()


func test_gpu_oom_on_the_graphics_card_says_partly() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [OOM_FAILURE, GPU_LOAD]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_str(_line(screen)).is_equal(
		"She's so tired tonight. She asks you to be patient with her."
	)
	assert_str(_fix(screen)).is_equal(
		(
			"Your graphics card doesn't have enough free memory for the model, "
			+ "so the game is running partly on your graphics card. "
			+ "Replies will be slower. Closing other programs may help."
		)
	)
	assert_array(screen.call("current_actions")).is_equal(["fast", "continue", "quit"])
	assert_bool(_finished(screen)).is_false()


func test_fast_mode_button_turns_the_setting_on_and_finishes() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [OOM_FAILURE, OOM_FAILURE, CPU_LOAD]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_bool(_press(screen, "Fast mode (shorter replies)")).is_true()
	assert_bool(Settings.fast_mode).is_true()
	assert_bool(FileAccess.file_exists(SETTINGS_PATH)).is_true()
	assert_bool(_finished(screen)).is_true()
	assert_str(String(screen.get("finished_scene"))).is_equal(BootScript.next_scene())


func test_device_type_cpu_shows_the_no_gpu_notice() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [CPU_LOAD]
	var screen := _spawn(_native(engine))
	var shown := await _wait_until(func() -> bool: return _fix(screen) != "")
	assert_bool(shown).is_true()
	assert_str(_line(screen)).is_equal(
		"She's moving slowly today. She asks you to be patient with her."
	)
	assert_str(_fix(screen)).is_equal(
		(
			"No supported graphics card was found, so the game is running on your processor. "
			+ "Replies will be slower. Updating your graphics driver may help."
		)
	)
	assert_array(screen.call("current_actions")).is_equal(["fast", "continue", "quit"])
	assert_bool(_finished(screen)).is_false()


func test_an_integrated_graphics_load_finishes_without_a_notice() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.load_results = [
		{"ok": true, "device": "Intel", "device_type": "igpu", "gpu_layers": 99},
	]
	var screen := _spawn(_native(engine))
	var done := await _wait_until(func() -> bool: return _finished(screen))
	assert_bool(done).is_true()
	assert_str(_fix(screen)).is_empty()
	assert_array(screen.call("current_actions")).is_empty()


func test_closing_during_a_blocked_load_returns_quickly_and_cancels() -> void:
	_write_model()
	var engine := FakeLoadEngine.new()
	engine.block_until_cancelled = true
	LLM.set_backend(_native(engine))
	var screen: Node = SCENE.instantiate()
	screen.set("navigate_on_finish", false)
	screen.set("cache_path", CACHE_PATH)
	screen.set("expected_override", EXPECTED)
	add_child(screen)
	var started := await _wait_until(func() -> bool: return engine.load_calls > 0)
	assert_bool(started).is_true()
	var began := Time.get_ticks_msec()
	remove_child(screen)
	screen.free()
	var elapsed := Time.get_ticks_msec() - began
	assert_int(elapsed).is_less(2000)
	assert_int(engine.cancel_calls).is_equal(1)


func test_every_error_has_fiction_a_fix_and_an_action() -> void:
	var data := _read_loading_data()
	assert_int((data.get("lines", []) as Array).size()).is_equal(4)
	var errors: Dictionary = data.get("errors", {})
	assert_int(errors.size()).is_greater_equal(5)
	for code: String in errors:
		var entry: Dictionary = errors[code]
		assert_str(String(entry.get("fiction", ""))).is_not_empty()
		assert_str(String(entry.get("fix", ""))).is_not_empty()
		assert_array(entry.get("actions", [])).is_not_empty()


func test_line_index_steps_every_interval_and_stays_on_the_last() -> void:
	assert_int(LoadingScript.line_index(0, 4)).is_equal(0)
	assert_int(LoadingScript.line_index(2499, 4)).is_equal(0)
	assert_int(LoadingScript.line_index(2500, 4)).is_equal(1)
	assert_int(LoadingScript.line_index(7500, 4)).is_equal(3)
	assert_int(LoadingScript.line_index(999999, 4)).is_equal(3)


func test_gpu_present_reads_names_and_types() -> void:
	assert_bool(LoadingScript.gpu_present([])).is_false()
	assert_bool(LoadingScript.gpu_present(["CPU"])).is_false()
	assert_bool(LoadingScript.gpu_present([{"name": "CPU", "type": "cpu"}])).is_false()
	assert_bool(LoadingScript.gpu_present(["CUDA0"])).is_true()
	var mixed := [{"name": "CPU"}, {"name": "Metal", "type": "gpu"}]
	assert_bool(LoadingScript.gpu_present(mixed)).is_true()


func test_bar_target_gives_the_hash_the_first_thirty_percent() -> void:
	assert_float(LoadingScript.bar_target(false, true, 0.5, 0.0)).is_equal_approx(0.15, 0.0001)
	assert_float(LoadingScript.bar_target(true, true, 1.0, 0.5)).is_equal_approx(0.65, 0.0001)
	assert_float(LoadingScript.bar_target(true, false, 0.0, 0.5)).is_equal(0.5)
