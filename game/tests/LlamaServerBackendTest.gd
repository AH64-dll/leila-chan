extends GdUnitTestSuite
## P1.02 — LlamaServerBackend transport (docs/07 §3.1). Every test drives the
## real backend through the LLM facade against FakeLlamaServer, a localhost
## HTTP/SSE server scripted per test. The live server is covered separately in
## LlamaServerLiveTest.gd.

const LLMScript := preload("res://autoload/LLM.gd")
const BackendScript := preload("res://llm/backends/LlamaServerBackend.gd")
const FakeServer := preload("res://tests/helpers/FakeLlamaServer.gd")

const SCHEMA := {
	"type": "object",
	"properties":
	{
		"read": {"type": "string", "enum": ["greeting"]},
		"say": {"type": "string", "maxLength": 40},
	},
	"required": ["read", "say"],
	"additionalProperties": false,
}
const SCHEMA_TEXT_ONLY := {
	"type": "object",
	"properties":
	{
		"read": {"type": "string", "enum": ["greeting"]},
		"say": {"type": "string"},
	},
	"required": ["read", "say"],
	"additionalProperties": false,
}

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


func _new_request(schema := SCHEMA) -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [
		{"role": "system", "content": "You are a test."},
		{"role": "user", "content": "hi"},
	]
	request.schema = schema
	request.sampling = {}
	request.max_tokens = 128
	return request


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


## Waits for a counter in a test spy dictionary to reach `value`; the deferred
## steering callback lands on the main thread a frame or two later.
func _await_flag(state: Dictionary, key: String, value: int, timeout_ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while int(state[key]) < value and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return int(state[key]) >= value


func _run(llm: Node, request: TurnRequest, timeout_ms := 5000) -> Dictionary:
	var stream: TurnStream = llm.generate(request)
	var spy := _spy(stream)
	await _await_terminal(spy, timeout_ms)
	return {"stream": stream, "spy": spy, "llm": llm}


func _schema_json(value: Variant) -> String:
	return JSON.stringify(value, "", true)


func test_streams_tokens_and_logs_first_token() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(['{"a":', '"b"', "}"])
	fake.event_delay_ms = 5
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("completed")
	assert_str(String(spy["payload"])).is_equal('{"a":"b"}')
	assert_array(Array(spy["tokens"])).contains_exactly(['{"a":', '"b"', "}"])
	var metrics := backend.last_metrics()
	assert_int(int(metrics["chunks"])).is_equal(3)
	assert_int(int(metrics["first_token_ms"])).is_greater_equal(0)
	(
		assert_int(int(metrics["total_ms"]))
		. is_greater_equal(int(metrics["first_token_ms"]))
		. append_failure_message("total time must include the first token")
	)
	assert_str(backend.last_log_line()).contains("ttft=")
	assert_str(backend.last_log_line()).contains("turn ok")


func test_request_carries_schema_sampling_and_thinking_flag() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["{}"])
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)
	var request := _new_request(SCHEMA_TEXT_ONLY)
	request.sampling = {
		"temperature": 0.42,
		"top_p": 0.8,
		"repeat_penalty": 1.2,
		"seed": 7,
		"bogus_key": 1,
	}
	request.max_tokens = 123
	var run: Dictionary = await _run(llm, request)
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")

	var body: Dictionary = fake.recorded_requests()[0]["body"]
	assert_bool(bool(body["stream"])).is_true()
	assert_int(int(body["max_tokens"])).is_equal(123)
	assert_float(float(body["temperature"])).is_equal_approx(0.42, 0.0001)
	assert_float(float(body["top_p"])).is_equal_approx(0.8, 0.0001)
	assert_float(float(body["repeat_penalty"])).is_equal_approx(1.2, 0.0001)
	assert_int(int(body["seed"])).is_equal(7)
	assert_bool(body.has("bogus_key")).is_false()
	assert_bool(bool(body["chat_template_kwargs"]["enable_thinking"])).is_false()
	assert_bool(bool(body["cache_prompt"])).is_true()
	assert_str(String(body["messages"][1]["content"])).is_equal("hi")
	var format: Dictionary = body["response_format"]
	assert_str(String(format["type"])).is_equal("json_schema")
	assert_str(_schema_json(format["json_schema"]["schema"])).is_equal(
		_schema_json(SCHEMA_TEXT_ONLY)
	)


func test_schema_is_per_request() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["{}"])
	fake.max_connections = 2
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)
	var first_schema := {"type": "object", "properties": {"alpha": {"type": "string"}}}
	var second_schema := {"type": "object", "properties": {"beta": {"type": "integer"}}}

	await _run(llm, _new_request(first_schema))
	await _run(llm, _new_request(second_schema))
	var requests: Array = fake.recorded_requests()
	assert_int(requests.size()).is_equal(2)
	var first_body: Dictionary = requests[0]["body"]
	var second_body: Dictionary = requests[1]["body"]
	assert_str(_schema_json(first_body["response_format"]["json_schema"]["schema"])).is_equal(
		_schema_json(first_schema)
	)
	assert_str(_schema_json(second_body["response_format"]["json_schema"]["schema"])).is_equal(
		_schema_json(second_schema)
	)


func test_handles_byte_split_chunked_and_utf8() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["héllo", " 世界", "!"])
	fake.split_writes = true
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_str(String(run["spy"]["payload"])).is_equal("héllo 世界!")


func test_accepts_content_length_framing() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["one", "two"])
	fake.framing = "content_length"
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_str(String(run["spy"]["payload"])).is_equal("onetwo")


func test_accepts_connection_close_framing() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["closed"])
	fake.framing = "close"
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_str(String(run["spy"]["payload"])).is_equal("closed")


func test_skips_sse_comments() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["kept"])
	fake.include_comment = true
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_str(String(run["spy"]["payload"])).is_equal("kept")


func test_read_timeout_reports_partial_stream() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["a", "b", "c"])
	fake.stall_after_events = 1
	var backend := _new_backend(fake, {"read_timeout_ms": 150, "turn_timeout_ms": 2000})
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("read_timeout")
	assert_array(Array(spy["tokens"])).contains_exactly(["a"])
	assert_str(backend.last_log_line()).contains("turn failed code=read_timeout")


func test_turn_timeout_bounds_slow_server() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["a", "b", "c", "d", "e", "f", "g", "h"])
	fake.event_delay_ms = 50
	var backend := _new_backend(fake, {"read_timeout_ms": 1000, "turn_timeout_ms": 150})
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("turn_timeout")
	assert_int(spy["tokens"].size()).is_greater(0)
	assert_int(spy["tokens"].size()).is_less(8)


func test_cancel_mid_stream_is_prompt() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["a", "b", "c"])
	fake.stall_after_events = 2
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var stream: TurnStream = llm.generate(_new_request())
	var spy := _spy(stream)
	var deadline := Time.get_ticks_msec() + 3000
	while spy["tokens"].size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_int(spy["tokens"].size()).is_equal(2)
	var t0 := Time.get_ticks_msec()
	stream.cancel()
	assert_int(Time.get_ticks_msec() - t0).is_less(50)
	await _await_terminal(spy, 1000)
	assert_str(String(spy["terminal"])).is_equal("cancelled")
	assert_int(Time.get_ticks_msec() - t0).is_less(500)


func test_http_error_message_is_surfaced() -> void:
	var fake = _fake()
	fake.status = 500
	fake.error_body = '{"error":{"message":"boom","type":"server_error"}}'
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("http_error")
	assert_str(String(spy["payload"]["message"])).is_equal("boom")


func test_truncated_stream_is_an_error() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["a", "b", "c"])
	fake.truncate_after_events = 2
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("stream_truncated")
	assert_array(Array(spy["tokens"])).contains_exactly(["a", "b"])


func test_unreachable_attach_server_does_not_spawn() -> void:
	var port := LlamaServerProcess.find_free_port()
	assert_int(port).is_greater(0)
	var backend := (
		BackendScript
		. new(
			{
				"base_url": "http://127.0.0.1:%d" % port,
				"auto_start": false,
				"connect_timeout_ms": 120,
				"health_timeout_ms": 120,
				"read_timeout_ms": 120,
				"turn_timeout_ms": 1000,
				"retry_once": false,
			}
		)
	)
	var llm := _new_llm(backend)
	var t0 := Time.get_ticks_msec()
	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("failed")
	assert_str(String(spy["payload"]["code"])).is_equal("server_unreachable")
	assert_int(backend.server_pid()).is_equal(0)
	assert_bool(backend.owns_server()).is_false()
	assert_int(Time.get_ticks_msec() - t0).is_less(1500)


func test_first_say_metric_is_separate_from_ttft() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(
		[
			'{"read":"greeting","inner":"they are kind",',
			'"beats":[{"feeling":"shyness","intensity":1,"cue":"none","say":"Hi',
			' there"}]}',
		]
	)
	fake.event_delay_ms = 15
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("completed")
	assert_bool(JSON.parse_string(String(spy["payload"])) is Dictionary).is_true()
	var metrics := backend.last_metrics()
	assert_int(int(metrics["first_token_ms"])).is_greater_equal(0)
	assert_int(int(metrics["first_say_ms"])).is_greater(int(metrics["first_token_ms"]))
	assert_str(backend.last_log_line()).contains("first_say=")
	assert_str(backend.last_log_line()).not_contains("first_say=n/a")


func test_capture_writes_raw_sse_bytes() -> void:
	var capture := "user://p1_02_capture_test.sse"
	var absolute := ProjectSettings.globalize_path(capture)
	if FileAccess.file_exists(capture):
		DirAccess.remove_absolute(absolute)
	var fake = _fake()
	fake.deltas = PackedStringArray(['{"captured":true}'])
	var backend := _new_backend(fake, {"capture_path": capture})
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_bool(FileAccess.file_exists(capture)).is_true()
	var file := FileAccess.open(capture, FileAccess.READ)
	assert_object(file).is_not_null()
	var captured := file.get_as_text()
	assert_str(captured.substr(0, 6)).is_equal("data: ")
	assert_str(captured).contains("captured")
	assert_str(String(backend.last_metrics().get("capture_error", ""))).is_equal("")
	if FileAccess.file_exists(capture):
		DirAccess.remove_absolute(absolute)


func test_invalid_request_does_not_touch_network() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["{}"])
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)

	var no_schema := _new_request({})
	var first: Dictionary = await _run(llm, no_schema)
	assert_str(String(first["spy"]["terminal"])).is_equal("failed")
	assert_str(String(first["spy"]["payload"]["code"])).is_equal("invalid_request")

	var no_messages := _new_request()
	no_messages.messages = []
	var second: Dictionary = await _run(llm, no_messages)
	assert_str(String(second["spy"]["terminal"])).is_equal("failed")
	assert_str(String(second["spy"]["payload"]["code"])).is_equal("invalid_request")
	assert_int(fake.connection_count()).is_equal(0)


func test_retry_after_empty_stream() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["ok"])
	fake.drop_connections = 1
	fake.max_connections = 2
	var backend := _new_backend(fake, {"retry_once": true})
	var llm := _new_llm(backend)

	var run: Dictionary = await _run(llm, _new_request())
	var spy: Dictionary = run["spy"]
	assert_str(String(spy["terminal"])).is_equal("completed")
	assert_str(String(spy["payload"])).is_equal("ok")
	assert_bool(bool(backend.last_metrics().get("retried", false))).is_true()
	assert_int(fake.connection_count()).is_equal(2)


## P2.03: the dose is a launch flag (docs/06 §4), so a stage change can only be
## bound by relaunching a server the app owns. An attached server is never ours to
## restart (P1.02) — the refusal keeps the old dose and leaves the server working.
func test_steering_is_refused_on_an_attached_server() -> void:
	var fake = _fake()
	fake.deltas = PackedStringArray(["unsteered"])
	var backend := _new_backend(fake)
	var llm := _new_llm(backend)
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
	assert_int(int(seen["calls"])).is_equal(1)
	var info: Dictionary = seen["info"]
	assert_bool(bool(info["ok"])).is_false()
	assert_str(String((info["error"] as Dictionary)["code"])).is_equal("server_not_owned")
	assert_bool(bool(info["kept_previous"])).is_true()
	# Nothing was stopped, so the attached server is untouched and still answers.
	assert_bool(bool(info["recovered"])).is_true()
	assert_int(backend.server_pid()).is_equal(0)
	var run: Dictionary = await _run(llm, _new_request())
	assert_str(String(run["spy"]["terminal"])).is_equal("completed")
	assert_str(String(run["spy"]["payload"])).is_equal("unsteered")
