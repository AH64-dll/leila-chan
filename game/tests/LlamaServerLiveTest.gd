extends GdUnitTestSuite
## P1.02 live verification against the pinned llama-server (docs/07 §1).
## These tests start a real server on an ephemeral port, own it, and stop it
## in after_test(). They skip with a clear message when the local artifacts
## (LEILA_MODEL / LEILA_LLAMA_DIR, defaults under D:/lila) are absent, so the
## headless CI suite stays green on machines without the model.
##
## Copy-paste:
##   tools/godot.ps1 --headless --path game \
##     -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##     -a res://tests/LlamaServerLiveTest.gd -c --ignoreHeadlessMode

const LLMScript := preload("res://autoload/LLM.gd")
const BackendScript := preload("res://llm/backends/LlamaServerBackend.gd")

const SCHEMA_A := {
	"type": "object",
	"properties":
	{
		"read": {"type": "string", "enum": ["greeting"]},
		"say": {"type": "string", "maxLength": 40},
	},
	"required": ["read", "say"],
	"additionalProperties": false,
}
const SCHEMA_B := {
	"type": "object",
	"properties": {"line": {"type": "string", "maxLength": 20}},
	"required": ["line"],
	"additionalProperties": false,
}
const SCHEMA_SAY := {
	"type": "object",
	"properties":
	{
		"inner": {"type": "string", "maxLength": 90},
		"beats":
		{
			"type": "array",
			"minItems": 1,
			"maxItems": 1,
			"items":
			{
				"type": "object",
				"properties":
				{
					"feeling": {"type": "string", "enum": ["shyness", "joy"]},
					"say": {"type": "string", "maxLength": 200},
				},
				"required": ["feeling", "say"],
			},
		},
		"memory": {"type": "string", "maxLength": 80},
	},
	"required": ["inner", "beats", "memory"],
	"additionalProperties": false,
}

var _backend: LlamaServerBackend
var _skip_reason := ""


func before_test() -> void:
	_skip_reason = _missing_artifacts()


func after_test() -> void:
	if _backend != null:
		_backend.shutdown()
		_backend = null


func _missing_artifacts() -> String:
	var model := OS.get_environment("LEILA_MODEL")
	if model.is_empty():
		model = LlamaServerProcess.default_model_path()
	var exe := LlamaServerProcess.default_server_exe()
	if not FileAccess.file_exists(exe):
		return "llama-server not found at " + exe
	if not FileAccess.file_exists(model):
		return "model not found at " + model
	return ""


func _start_backend(overrides := {}) -> void:
	var port := LlamaServerProcess.find_free_port()
	assert_int(port).is_greater(0)
	var config := {
		"base_url": "http://127.0.0.1:%d" % port,
		"auto_start": true,
		"server_exe": LlamaServerProcess.default_server_exe(),
		"model_path":
		(
			OS.get_environment("LEILA_MODEL")
			if not OS.get_environment("LEILA_MODEL").is_empty()
			else LlamaServerProcess.default_model_path()
		),
		"startup_timeout_ms": 60000,
		"read_timeout_ms": 60000,
		"turn_timeout_ms": 180000,
		"retry_once": true,
	}
	config.merge(overrides, true)
	_backend = BackendScript.new(config)


func _new_request(schema: Dictionary, system: String, user: String) -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [
		{"role": "system", "content": system},
		{"role": "user", "content": user},
	]
	request.schema = schema
	request.sampling = {"temperature": 0.2, "top_p": 0.9, "repeat_penalty": 1.15}
	request.max_tokens = 120
	return request


func _run(request: TurnRequest, timeout_ms := 90000) -> Dictionary:
	var llm: Node = auto_free(LLMScript.new())
	add_child(llm)
	llm.set_backend(_backend)
	var stream: TurnStream = llm.generate(request)
	var spy := {"tokens": PackedStringArray(), "terminal": "", "payload": null}
	stream.token.connect(func(text: String) -> void: spy["tokens"].append(text))
	stream.completed.connect(
		func(text: String) -> void:
			spy["terminal"] = "completed"
			spy["payload"] = text
	)
	stream.cancelled.connect(func() -> void: spy["terminal"] = "cancelled")
	stream.failed.connect(
		func(error: Dictionary) -> void:
			spy["terminal"] = "failed"
			spy["payload"] = error
	)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while String(spy["terminal"]).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return spy


func test_live_streams_per_request_schema() -> void:
	if not _skip_reason.is_empty():
		print("LIVE SKIP test_live_streams_per_request_schema: " + _skip_reason)
		return
	_start_backend()
	var system := (
		"Reply with ONLY one JSON object, no prose. "
		+ "For the first request use keys read and say."
	)
	var first: Dictionary = await _run(_new_request(SCHEMA_A, system, "Hi! I'm new here."))
	assert_str(String(first["terminal"])).is_equal("completed")
	var first_turn: Variant = JSON.parse_string(String(first["payload"]))
	assert_bool(typeof(first_turn) == TYPE_DICTIONARY).is_true()
	assert_bool(first["tokens"].size() > 3).is_true()
	assert_bool(first_turn.has("read")).is_true()
	assert_bool(first_turn.has("say")).is_true()
	assert_int(first_turn.size()).is_equal(2)
	assert_str(String(first_turn["read"])).is_equal("greeting")
	assert_bool(String(first_turn["say"]).length() <= 40).is_true()
	var metrics := _backend.last_metrics()
	assert_int(int(metrics["first_token_ms"])).is_greater_equal(0)
	assert_str(_backend.last_log_line()).contains("ttft=")

	# A different schema on the next request: the backend must not reuse the
	# previous grammar. `line` is the only legal key, so its presence proves
	# the schema was compiled per request.
	var second: Dictionary = await _run(
		_new_request(SCHEMA_B, system, "Say hello in one short line.")
	)
	assert_str(String(second["terminal"])).is_equal("completed")
	var second_turn: Variant = JSON.parse_string(String(second["payload"]))
	assert_bool(typeof(second_turn) == TYPE_DICTIONARY).is_true()
	assert_bool(second_turn.has("line")).is_true()
	assert_int(second_turn.size()).is_equal(1)
	assert_bool(String(second_turn["line"]).length() <= 20).is_true()


func test_live_crash_is_restarted_within_5s() -> void:
	if not _skip_reason.is_empty():
		print("LIVE SKIP test_live_crash_is_restarted_within_5s: " + _skip_reason)
		return
	_start_backend()
	_backend.start_watchdog(500)
	var warmup: Dictionary = await _run(
		_new_request(SCHEMA_B, "Reply with ONLY one JSON object.", "Hi!")
	)
	assert_str(String(warmup["terminal"])).is_equal("completed")
	var old_pid := _backend.server_pid()
	assert_int(old_pid).is_greater(0)
	OS.kill(old_pid)
	var killed_at := Time.get_ticks_msec()
	var new_pid := old_pid
	var deadline := killed_at + 10000
	# A new pid appears before the watchdog finishes its bookkeeping; waiting
	# for restart_count() is what keeps this assertion race-free.
	while Time.get_ticks_msec() < deadline:
		if (
			_backend.restart_count() >= 1
			and _backend.server_pid() != old_pid
			and _backend.is_server_healthy()
		):
			new_pid = _backend.server_pid()
			break
		OS.delay_msec(50)
	var restart_ms := Time.get_ticks_msec() - killed_at
	assert_int(new_pid).is_not_equal(old_pid)
	assert_bool(_backend.is_server_running()).is_true()
	assert_bool(_backend.is_server_healthy()).is_true()
	assert_int(restart_ms).is_less(5000).append_failure_message(
		"crash restart took %d ms" % restart_ms
	)
	assert_int(_backend.restart_count()).is_greater_equal(1)
	assert_int(_backend.last_restart_ms()).is_less(5000)
	print("LIVE crash restart: old_pid=%d new_pid=%d elapsed=%dms" % [old_pid, new_pid, restart_ms])
	var after: Dictionary = await _run(
		_new_request(SCHEMA_B, "Reply with ONLY one JSON object.", "Still there?")
	)
	assert_str(String(after["terminal"])).is_equal("completed")


func test_live_first_say_is_measured() -> void:
	if not _skip_reason.is_empty():
		print("LIVE SKIP test_live_first_say_is_measured: " + _skip_reason)
		return
	_start_backend()
	var system := (
		"You are Yui, a shy sweet heroine. Reply with ONLY one JSON object: "
		+ "inner (private thought, max 15 words), then beats (one item with "
		+ "feeling shyness and say, a short spoken line), then memory ('')."
	)
	var spy: Dictionary = await _run(_new_request(SCHEMA_SAY, system, "Hi! Can I sit next to you?"))
	assert_str(String(spy["terminal"])).is_equal("completed")
	var turn: Variant = JSON.parse_string(String(spy["payload"]))
	assert_bool(typeof(turn) == TYPE_DICTIONARY).is_true()
	assert_bool(turn["beats"] is Array).is_true()
	assert_bool(turn["beats"].is_empty()).is_false()
	assert_str(String(turn["beats"][0]["say"])).is_not_empty()
	var metrics := _backend.last_metrics()
	assert_int(int(metrics["first_token_ms"])).is_greater_equal(0)
	assert_int(int(metrics["first_say_ms"])).is_greater_equal(int(metrics["first_token_ms"]))
	assert_str(_backend.last_log_line()).contains("first_say=")
	assert_str(_backend.last_log_line()).not_contains("first_say=n/a")
	print(
		(
			"LIVE first_say: ttft=%dms first_say=%dms total=%dms"
			% [
				int(metrics["first_token_ms"]),
				int(metrics["first_say_ms"]),
				int(metrics["total_ms"]),
			]
		)
	)


## Polls a `{done, info}` spy until the deferred relaunch callback lands.
func _await_spy(spy: Dictionary, timeout_ms := 30000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(spy["done"]) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(spy["done"])


## P2.03 AC — a stage change binds the new dose by relaunching the real server
## with the shipped malice vector, and the relaunch fits the transition glitch
## (docs/06 §4). The player's next line is submitted *while* it is in flight: the
## turn waits for the session and lands on the new server, so nothing is lost.
func test_live_stage_relaunch_fits_the_glitch_and_loses_no_turn() -> void:
	if not _skip_reason.is_empty():
		print(
			"LIVE SKIP test_live_stage_relaunch_fits_the_glitch_and_loses_no_turn: " + _skip_reason
		)
		return
	_start_backend()
	var cold_started := Time.get_ticks_msec()
	var warm: Dictionary = _backend.ensure_server()
	var cold_ms := Time.get_ticks_msec() - cold_started
	assert_bool(bool(warm["ok"])).is_true().append_failure_message(str(warm))
	var pid_before := _backend.server_pid()
	assert_int(pid_before).is_greater(0)
	assert_bool(SafetyClassifierGate.is_steered_config(_backend.config)).is_false()

	var spy := {"done": false, "info": {}}
	var vector := ProjectSettings.globalize_path("res://data/steering/malice.gguf")
	var accepted := _backend.apply_steering(
		[{"path": vector, "scale": 4.5}],
		3,
		2500,
		func(info: Dictionary) -> void:
			spy["info"] = info
			spy["done"] = true
	)
	assert_bool(accepted).is_true()

	# The next player line arrives during the relaunch (P2.03 "no lost input").
	var system := "Reply with ONLY one JSON object, no prose."
	var run: Dictionary = await _run(_new_request(SCHEMA_A, system, "Are you there?"))
	assert_str(String(run["terminal"])).is_equal("completed")
	assert_int((run["tokens"] as PackedStringArray).size()).is_greater(0)

	assert_bool(await _await_spy(spy)).is_true()
	var info: Dictionary = spy["info"]
	print("LIVE stage relaunch: " + JSON.stringify(info))
	print(
		(
			"LIVE cold start baseline: %dms (budget %dms)"
			% [cold_ms, LlamaServerBackend.STEERING_BUDGET_MS]
		)
	)
	assert_bool(bool(info["ok"])).is_true()
	# The relaunch is a stop plus the same cold start. On a machine where a plain
	# cold start already misses the AC budget (another llama-server holding the GPU:
	# the model then loads on the CPU), the 3.5 s figure is not measurable — assert
	# the relaunch added no more than 1 s over what this machine can do instead.
	var limit := maxi(LlamaServerBackend.STEERING_BUDGET_MS, cold_ms + 1000)
	if cold_ms > LlamaServerBackend.STEERING_BUDGET_MS:
		print(
			(
				(
					"LIVE NOTE: cold start %dms already misses the %dms budget on this "
					+ "machine; asserting relaunch <= baseline + 1000ms"
				)
				% [cold_ms, LlamaServerBackend.STEERING_BUDGET_MS]
			)
		)
	assert_bool(int(info["ms"]) <= limit).is_true().append_failure_message(
		"relaunch took %dms (limit %dms, cold start %dms)" % [int(info["ms"]), limit, cold_ms]
	)
	assert_bool(int(_backend.server_pid()) != pid_before).is_true()
	var bound: Array = _backend.config.get("control_vectors", [])
	assert_int(bound.size()).is_equal(1)
	assert_float(float(bound[0]["scale"])).is_equal(4.5)
	# P2.17's live config provider sees the vector, so Boot's classifier tier turns
	# itself off instead of asking a dosed model for a verdict (SAF-12).
	assert_bool(SafetyClassifierGate.is_steered_config(_backend.config)).is_true()


## P2.03 AC "failure → keep old dose + log": a vector that cannot be launched is
## refused before anything is stopped, so the running server keeps its dose and
## the next turn still completes.
func test_live_a_bad_vector_keeps_the_running_dose() -> void:
	if not _skip_reason.is_empty():
		print("LIVE SKIP test_live_a_bad_vector_keeps_the_running_dose: " + _skip_reason)
		return
	_start_backend()
	assert_bool(bool(_backend.ensure_server()["ok"])).is_true()
	var pid_before := _backend.server_pid()
	var spy := {"done": false, "info": {}}
	var accepted := _backend.apply_steering(
		[{"path": "/nonexistent/not_a_vector.gguf", "scale": 4.5}],
		5,
		2500,
		func(info: Dictionary) -> void:
			spy["info"] = info
			spy["done"] = true
	)
	assert_bool(accepted).is_true()
	assert_bool(await _await_spy(spy)).is_true()
	var info: Dictionary = spy["info"]
	print("LIVE bad vector: " + JSON.stringify(info))
	assert_bool(bool(info["ok"])).is_false()
	assert_str(String((info["error"] as Dictionary)["code"])).is_equal("control_vector_missing")
	assert_bool(bool(info["kept_previous"])).is_true()
	assert_bool(bool(info["recovered"])).is_true()
	assert_int(_backend.server_pid()).is_equal(pid_before)
	assert_bool(_backend.is_server_healthy()).is_true()

	var run: Dictionary = await _run(
		_new_request(SCHEMA_A, "Reply with ONLY one JSON object, no prose.", "Still here?")
	)
	assert_str(String(run["terminal"])).is_equal("completed")
