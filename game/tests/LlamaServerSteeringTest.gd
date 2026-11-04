extends GdUnitTestSuite
## P2.03 — the transport side of a stage-change relaunch (docs/06 §4): the windows
## the AC is read from, the flag grammar the launcher must satisfy, and the vector
## validation that refuses a relaunch before anything is killed. The relaunch
## timing itself is LlamaServerLiveTest.gd and tools/SteeringRestartBench.

const BackendScript := preload("res://llm/backends/LlamaServerBackend.gd")
const LLMScript := preload("res://autoload/LLM.gd")
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


func _new_llm(backend: LlamaServerBackend) -> Node:
	var llm: Node = auto_free(LLMScript.new())
	add_child(llm)
	llm.set_backend(backend)
	return llm


func _new_request() -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [
		{"role": "system", "content": "You are a test."},
		{"role": "user", "content": "hi"},
	]
	request.schema = {
		"type": "object",
		"properties": {"say": {"type": "string"}},
		"required": ["say"],
		"additionalProperties": false,
	}
	request.sampling = {}
	request.max_tokens = 64
	return request


func _spy(stream: TurnStream) -> Dictionary:
	var spy := {"tokens": PackedStringArray(), "terminal": &"", "payload": null}
	stream.token.connect(func(text: String) -> void: spy["tokens"].append(text))
	stream.completed.connect(
		func(text: String) -> void:
			spy["terminal"] = &"completed"
			spy["payload"] = text
	)
	stream.cancelled.connect(func() -> void: spy["terminal"] = &"cancelled")
	stream.failed.connect(
		func(error: Dictionary) -> void:
			spy["terminal"] = &"failed"
			spy["payload"] = error
	)
	return spy


func _await_terminal(spy: Dictionary, timeout_ms := 5000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while spy["terminal"] == &"" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return spy["terminal"] != &""


func _run(llm: Node, request: TurnRequest) -> Dictionary:
	var stream: TurnStream = llm.generate(request)
	var spy := _spy(stream)
	await _await_terminal(spy)
	return {"spy": spy, "stream": stream}


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
	backend.shutdown()  # join the spent worker before the backend is freed


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


## CODE-2/DES-3a: `LEILA_OWN_SERVER=1` sets `auto_start`, but a server already
## answering on the port is adopted, not launched. A stage change must refuse it —
## not spawn a second llama-server that dies on the busy port and report a
## failure the attached server never had (docs/06 §4.1 "Ownership").
func test_an_adopted_auto_start_server_is_refused() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["unsteered"])
	var backend := _new_backend(fake, {"auto_start": true})
	# The first ensure_running() finds a healthy server and adopts it.
	var warm: Dictionary = backend.ensure_server()
	assert_bool(bool(warm["ok"])).is_true()
	assert_bool(bool(warm["attached"])).is_true()
	assert_bool(backend.owns_server()).is_false()

	var seen := {"calls": 0, "info": {}}
	var vector := ProjectSettings.globalize_path("res://data/steering/malice.gguf")
	var accepted := backend.apply_steering(
		[{"path": vector, "scale": 4.5}],
		4,
		2500,
		func(info: Dictionary) -> void:
			seen["calls"] += 1
			seen["info"] = info
	)
	assert_bool(accepted).is_false()
	await _await_flag(seen, "calls", 1)
	var info: Dictionary = seen["info"]
	assert_bool(bool(info["ok"])).is_false()
	assert_str(String((info["error"] as Dictionary)["code"])).is_equal("server_not_owned")
	assert_bool(bool(info["kept_previous"])).is_true()
	assert_bool(bool(info["recovered"])).is_true()
	assert_int(backend.server_pid()).is_equal(0)
	# The adopted server was neither stopped nor duplicated: it still answers.
	var llm := _new_llm(backend)
	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_str(String(run["spy"]["payload"])).is_equal("unsteered")


## CODE-2: a backend that has not probed yet cannot know the port is taken, so
## the worker re-checks ownership before the stop/start and reports the same
## refusal. Nothing was stopped, so the old config and the server stay as they are.
func test_a_relaunch_against_an_unprobed_adopted_server_is_refused() -> void:
	var fake = _fake()
	var backend := _new_backend(fake, {"auto_start": true})
	var seen := {"calls": 0, "info": {}}
	var vector := ProjectSettings.globalize_path("res://data/steering/malice.gguf")
	var accepted := backend.apply_steering(
		[{"path": vector, "scale": 4.5}],
		4,
		2500,
		func(info: Dictionary) -> void:
			seen["calls"] += 1
			seen["info"] = info
	)
	# `auto_start` is set and nothing has been probed, so the cheap guard passes...
	assert_bool(accepted).is_true()
	await _await_flag(seen, "calls", 1)
	var info: Dictionary = seen["info"]
	# ...but the worker probes, finds the adopted server, and refuses before stop.
	assert_bool(bool(info["ok"])).is_false()
	assert_str(String((info["error"] as Dictionary)["code"])).is_equal("server_not_owned")
	assert_bool(bool(info["kept_previous"])).is_true()
	assert_bool(bool(info["recovered"])).is_true()
	assert_int(backend.server_pid()).is_equal(0)
	assert_bool(backend.is_server_healthy()).is_true()
	assert_array(backend.config["control_vectors"]).is_empty()
	backend.shutdown()  # join the spent worker before the backend is freed


## CODE-5: the recovery branch is the AC-3 path that puts the previous vector set
## back when the new launch fails after the stop. A non-executable `server_exe`
## passes `_validate_files()` (it exists) and fails in `OS.create_process`, so
## both the relaunch and its recovery fail and the outcome must say so.
func test_a_failed_launch_restores_the_previous_vectors_and_reports_it() -> void:
	var dir := "user://steering_recovery_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var exe := dir.path_join("llama-server")
	var handle := FileAccess.open(exe, FileAccess.WRITE)
	handle.store_string("this is not an executable\n")
	handle.close()
	var vector := ProjectSettings.globalize_path("res://data/steering/malice.gguf")
	var port := LlamaServerProcess.find_free_port()
	assert_int(port).is_greater(0)
	var previous := [{"path": vector, "scale": 2.5}]
	var process := LlamaServerProcess.new()
	(
		process
		. configure(
			{
				"base_url": "http://127.0.0.1:%d" % port,
				"server_exe": ProjectSettings.globalize_path(exe),
				"model_path": vector,
				"control_vectors": previous.duplicate(true),
				"connect_timeout_ms": 100,
				"health_timeout_ms": 100,
				"startup_timeout_ms": 500,
			}
		)
	)

	var result := process.restart_with_vectors([{"path": vector, "scale": 4.5}], previous)
	assert_bool(bool(result["ok"])).is_false()
	assert_bool(bool(result["kept_previous"])).is_true()
	assert_bool(bool(result["recovered"])).is_false()
	assert_array(process.config["control_vectors"]).contains_exactly(previous)
	assert_int(process.server_pid()).is_equal(0)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(exe))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


## CODE-4: the turn session can be held by a stage-change relaunch for its whole
## stop/start. A turn queued behind it must honour its own cancel token instead
## of blocking out the wait (docs/05 §0 "closing always works").
func test_a_turn_blocked_by_a_relaunch_can_be_cancelled() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["late"])
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)
	# Stand in for a relaunch still inside its stop+start.
	backend._session.lock()
	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	await get_tree().process_frame
	llm.cancel()
	await _await_terminal(spy, 2000)
	backend._session.unlock()

	assert_str(String(spy["terminal"])).is_equal("cancelled")
	assert_int(backend.server_pid()).is_equal(0)


## CODE-4: quitting while a relaunch holds the session must not wait out the
## stop+start. `LLM._shutdown()` cancels the turn first; the token-aware session
## wait returns, so the join sees an already-finished worker (docs/05 §0).
func test_shutdown_does_not_wait_out_a_held_session() -> void:
	var fake = _fake()
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)
	backend._session.lock()
	llm.generate(_new_request())
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	llm._shutdown()
	var elapsed := Time.get_ticks_msec() - started
	backend._session.unlock()
	assert_int(elapsed).is_less(1000)
