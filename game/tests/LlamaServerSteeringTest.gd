extends GdUnitTestSuite
## P2.03 — the transport side of a stage-change relaunch (docs/06 §4): the windows
## the AC is read from, the flag grammar the launcher must satisfy, and the vector
## validation that refuses a relaunch before anything is killed. The relaunch
## timing itself is LlamaServerLiveTest.gd and tools/SteeringRestartBench.

const BackendScript := preload("res://llm/backends/LlamaServerBackend.gd")
const FakeServer := preload("res://tests/helpers/FakeLlamaServer.gd")
## A Windows-shaped vector path for the flag-grammar cases (never opened on disk).
const VECTOR := "D:/lila/game/data/steering/malice.gguf"

var _fakes: Array = []


func after_test() -> void:
	for fake: Variant in _fakes:
		fake.stop()
	_fakes.clear()


func _fake() -> Variant:
	var fake := FakeServer.new()
	assert_bool(fake.start()).is_true().append_failure_message("fake server did not start")
	_fakes.append(fake)
	return fake


func _new_backend(fake: Variant, overrides := {}) -> LlamaServerBackend:
	var config := {
		"base_url": fake.base_url(),
		"auto_start": false,
		"connect_timeout_ms": 300,
		"health_timeout_ms": 150,
		"read_timeout_ms": 1000,
		"turn_timeout_ms": 3000,
		"retry_once": false,
	}
	config.merge(overrides, true)
	return BackendScript.new(config)


## Waits for a counter in a test spy dictionary to reach `value`; the deferred
## steering callback lands on the main thread a frame or two later.
func _await_flag(state: Dictionary, key: String, value: int, timeout_ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while int(state[key]) < value and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return int(state[key]) >= value


## The info a relaunch reports carries both windows the AC is read from: the
## transition glitch it must hide in, and the hard 3.5 s budget.
func test_steering_info_reports_the_glitch_window_and_budget() -> void:
	var backend := _new_backend(_fake())
	var seen := {"calls": 0, "info": {}}
	backend.apply_steering(
		[],
		3,
		2500,
		func(info: Dictionary) -> void:
			seen["calls"] += 1
			seen["info"] = info
	)
	await _await_flag(seen, "calls", 1)
	var info: Dictionary = seen["info"]
	assert_int(int(info["stage"])).is_equal(3)
	assert_int(int(info["window_ms"])).is_equal(2500)
	assert_int(int(info["budget_ms"])).is_equal(LlamaServerBackend.STEERING_BUDGET_MS)
	assert_bool(bool(info["within_budget"])).is_true()
	assert_bool(bool(info["fits_window"])).is_true()
	assert_dict(backend.last_steering_info()).is_not_empty()


## tools/llm/cvec_path.py's rule, mirrored in the launcher: a FNAME with ':' or
## ',' can never reach --control-vector-scaled, and a Windows drive path must be
## made relative to the server's working directory.
func test_flag_path_mirrors_the_shell_launcher_rule() -> void:
	var posix := LlamaServerProcess.flag_path("/run/media/v/malice.gguf", "", "posix")
	assert_bool(bool(posix["ok"])).is_true()
	assert_str(String(posix["path"])).is_equal("/run/media/v/malice.gguf")

	var colon := LlamaServerProcess.flag_path("/run/a:b.gguf", "", "posix")
	assert_bool(bool(colon["ok"])).is_false()
	var comma := LlamaServerProcess.flag_path("/run/a,b.gguf", "", "posix")
	assert_bool(bool(comma["ok"])).is_false()

	var windows := LlamaServerProcess.flag_path(VECTOR, "D:/lila", "windows")
	assert_bool(bool(windows["ok"])).is_true()
	assert_str(String(windows["path"])).is_equal("game/data/steering/malice.gguf")

	var nested := LlamaServerProcess.flag_path(VECTOR, "D:/lila/game", "windows")
	assert_bool(bool(nested["ok"])).is_true()
	assert_str(String(nested["path"])).is_equal("data/steering/malice.gguf")

	# Cross-drive, ambiguous drive-relative, and a drive path with no server cwd
	# configured are refused rather than passed on to fail silently.
	var other_drive := LlamaServerProcess.flag_path("E:/v.gguf", "D:/lila", "windows")
	assert_bool(bool(other_drive["ok"])).is_false()
	var ambiguous := LlamaServerProcess.flag_path("D:v.gguf", "D:/lila", "windows")
	assert_bool(bool(ambiguous["ok"])).is_false()
	var no_cwd := LlamaServerProcess.flag_path(VECTOR, "", "windows")
	assert_bool(bool(no_cwd["ok"])).is_false()

	var unc := LlamaServerProcess.flag_path("//srv/share/v.gguf", "", "windows")
	assert_bool(bool(unc["ok"])).is_true()
	assert_str(String(unc["path"])).is_equal("//srv/share/v.gguf")
	var unknown := LlamaServerProcess.flag_path("v.gguf", "", "beos")
	assert_bool(bool(unknown["ok"])).is_false()


## Every vector is validated before anything is launched: llama.cpp only logs a
## bad FNAME and then serves healthy, so launching would run unsteered silently.
func test_control_vector_validation_refuses_before_any_launch() -> void:
	var process := LlamaServerProcess.new()
	process.configure({})
	assert_bool(process._control_vector_error().is_empty()).is_true()

	var vector := ProjectSettings.globalize_path("res://data/steering/malice.gguf")
	process.configure({"control_vectors": [{"path": "/nonexistent/nope.gguf", "scale": 4.0}]})
	assert_str(String(process._control_vector_error()["code"])).is_equal("control_vector_missing")

	process.configure({"control_vectors": [{"path": vector, "scale": 4.0}]})
	assert_bool(process._control_vector_error().is_empty()).is_true()

	process.configure({"control_vectors": [{"path": vector, "scale": NAN}]})
	assert_str(String(process._control_vector_error()["code"])).is_equal("control_vector_invalid")

	# A real file whose *name* carries ':' cannot be spelled for the flag parser.
	var dir := "user://stage_steering_validation"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var colon_path := dir.path_join("bad:name.gguf")
	var copy := FileAccess.open(colon_path, FileAccess.WRITE)
	copy.store_buffer(FileAccess.get_file_as_bytes(vector))
	copy.close()
	var global_colon := ProjectSettings.globalize_path(colon_path)
	process.configure({"control_vectors": [{"path": global_colon, "scale": 4.0}]})
	assert_str(String(process._control_vector_error()["code"])).is_equal(
		"control_vector_path_unsafe"
	)
	DirAccess.remove_absolute(global_colon)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
