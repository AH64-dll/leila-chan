extends GdUnitTestSuite
## P4.02 NativeBackend contract (docs/07 §3.1). No binary and no model: a
## scripted FakeEngine stands in for the LeilaLLM GDExtension, so every case
## runs in CI. The fake records what the backend sent it.


class FakeEngine:
	extends RefCounted
	var load_calls := 0
	var generate_calls := 0
	var load_result := {
		"ok": true,
		"load_ms": 1,
		"n_layer": 2,
		"n_embd": 3,
		"n_ctx": 8192,
		"gpu_offload": true,
		"devices": ["CUDA0"],
	}
	var chunks: Array = []
	var last_messages_json := ""
	var last_schema_json := ""
	var last_sampling := {}
	var last_max_tokens := -1
	var last_is_cancelled := Callable()
	var bind_calls: Array = []  # one entry per set_control_vectors(): the vectors it was given
	var bound_vectors: Array = []  # what the engine holds now; a refused bind keeps it
	var bind_error_code := ""  # non-empty: every bind is refused with this code
	var call_order: Array = []  # "load", "bind", "generate" in the order they happened
	var metrics_extra: Dictionary = {}  # merged into each generate()'s metrics

	func load_model(_config: Dictionary) -> Dictionary:
		load_calls += 1
		call_order.append("load")
		return load_result

	func is_loaded() -> bool:
		return load_calls > 0 and bool(load_result.get("ok", false))

	func unload() -> void:
		pass

	func clear_prompt_cache() -> bool:
		return true

	func set_control_vectors(vectors: Array) -> Dictionary:
		call_order.append("bind")
		bind_calls.append(vectors.duplicate(true))
		if not bind_error_code.is_empty():
			return {"ok": false, "error": {"code": bind_error_code, "message": "bind refused"}}
		bound_vectors = vectors.duplicate(true)
		return {"ok": true, "applied": true, "set_ms": 0.1, "n_vectors": vectors.size()}

	func generate(
		messages_json: String,
		schema_json: String,
		sampling: Dictionary,
		max_tokens: int,
		on_token: Callable,
		is_cancelled: Callable
	) -> Dictionary:
		generate_calls += 1
		call_order.append("generate")
		last_messages_json = messages_json
		last_schema_json = schema_json
		last_sampling = sampling
		last_max_tokens = max_tokens
		last_is_cancelled = is_cancelled
		var text := ""
		for chunk in chunks:
			if is_cancelled.is_valid() and bool(is_cancelled.call()):
				var stopped := {"code": "cancelled", "message": "cancel requested"}
				return {"ok": false, "error": stopped, "metrics": {}}
			if on_token.is_valid():
				on_token.call(String(chunk))
			text += String(chunk)
		var metrics := {"prompt_tokens": 7, "completion_tokens": chunks.size()}
		metrics.merge(metrics_extra, true)
		return {"ok": true, "text": text, "metrics": metrics}


## Same backend, but no engine at all (the case where the binary is absent).
class NoEngineBackend:
	extends NativeBackend

	func _create_default_engine() -> Object:
		return null


func _new_request() -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [{"role": "user", "content": "hi"}]
	request.schema = {"type": "object"}
	request.sampling = {"temperature": 0.75}
	request.max_tokens = 64
	return request


func _error_code(result: Dictionary) -> String:
	var error: Dictionary = result.get("error", {})
	return String(error.get("code", ""))


func test_schema_key_order_survives_the_json_handoff() -> void:
	var engine := FakeEngine.new()
	var backend := NativeBackend.new({}, engine)
	var request := _new_request()
	request.schema = {"zebra": {"type": "string"}, "apple": {"type": "string"}}
	var result := backend.generate(request, Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	var schema_json := engine.last_schema_json
	assert_bool(schema_json.find('"zebra"') >= 0).is_true()
	assert_int(schema_json.find('"zebra"')).is_less(schema_json.find('"apple"'))


func test_messages_and_sampling_reach_the_engine_as_json() -> void:
	var engine := FakeEngine.new()
	var backend := NativeBackend.new({}, engine)
	var request := _new_request()
	request.sampling = {"temperature": 0.75, "top_p": 0.9}
	request.max_tokens = 64
	backend.generate(request, Callable(), null)
	var expected := JSON.stringify([{"role": "user", "content": "hi"}], "", false)
	assert_str(engine.last_messages_json).is_equal(expected)
	assert_dict(engine.last_sampling).is_equal({"temperature": 0.75, "top_p": 0.9})
	assert_int(engine.last_max_tokens).is_equal(64)


func test_load_failure_returns_the_engine_error_and_skips_generate() -> void:
	var engine := FakeEngine.new()
	engine.load_result = {"ok": false, "error": {"code": "model_missing", "message": "no model"}}
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(_new_request(), Callable(), null)
	assert_bool(bool(result.get("ok", true))).is_false()
	assert_str(_error_code(result)).is_equal("model_missing")
	assert_int(engine.generate_calls).is_equal(0)


func test_model_loads_once_across_two_generates() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	backend.generate(_new_request(), Callable(), null)
	backend.generate(_new_request(), Callable(), null)
	assert_int(engine.load_calls).is_equal(1)
	assert_int(engine.generate_calls).is_equal(2)


func test_missing_engine_reports_native_unavailable() -> void:
	var backend := NoEngineBackend.new({})
	var result := backend.generate(_new_request(), Callable(), null)
	assert_str(_error_code(result)).is_equal("native_unavailable")
	var load := backend.ensure_loaded()
	assert_str(_error_code(load)).is_equal("native_unavailable")


func test_null_request_is_invalid_request_and_never_loads() -> void:
	var engine := FakeEngine.new()
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(null, Callable(), null)
	assert_str(_error_code(result)).is_equal("invalid_request")
	assert_int(engine.load_calls).is_equal(0)


func test_tokens_reach_the_caller_and_first_say_is_timed() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ['{"face": "neutral", ', '"say": "', "Hello", ' there."}']
	var backend := NativeBackend.new({}, engine)
	var received: Array[String] = []
	var on_token := func(text: String) -> void: received.append(text)
	var result := backend.generate(_new_request(), on_token, null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(received.size()).is_equal(engine.chunks.size())
	assert_str("".join(PackedStringArray(received))).is_equal(String(result.get("text", "")))
	var metrics: Dictionary = result.get("metrics", {})
	assert_bool(int(metrics.get("first_say_ms", -1)) >= 0).is_true()


func test_cancel_token_is_passed_through_and_reports_its_state() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["a", "b"]
	var backend := NativeBackend.new({}, engine)
	var cancel := LLMCancelToken.new()
	var live := backend.generate(_new_request(), Callable(), cancel)
	assert_bool(bool(live.get("ok", false))).is_true()
	assert_bool(engine.last_is_cancelled.is_valid()).is_true()
	assert_bool(bool(engine.last_is_cancelled.call())).is_false()
	cancel.cancel()
	assert_bool(bool(engine.last_is_cancelled.call())).is_true()
	var received: Array[String] = []
	var on_token := func(text: String) -> void: received.append(text)
	var stopped := backend.generate(_new_request(), on_token, cancel)
	assert_str(_error_code(stopped)).is_equal("cancelled")
	assert_int(received.size()).is_equal(0)
	var no_token := backend.generate(_new_request(), Callable(), null)
	assert_bool(bool(no_token.get("ok", false))).is_true()
	assert_bool(engine.last_is_cancelled.is_valid()).is_false()


func _steered_request(dose: Dictionary) -> TurnRequest:
	var request := _new_request()
	request.dose = dose
	return request


func test_dose_binds_one_vector_before_generate() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(_steered_request({"malice": 4.5}), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(engine.bind_calls.size()).is_equal(1)
	var vectors: Array = engine.bind_calls[0]
	assert_int(vectors.size()).is_equal(1)
	var vector: Dictionary = vectors[0]
	assert_str(String(vector.get("path", ""))).ends_with("malice.gguf")
	assert_float(float(vector.get("scale", 0.0))).is_equal(4.5)
	assert_array(engine.call_order).is_equal(["load", "bind", "generate"])


func test_two_doses_bind_twice_and_load_once() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	backend.generate(_steered_request({"malice": 4.5}), Callable(), null)
	backend.generate(_steered_request({"malice": 2.0}), Callable(), null)
	assert_int(engine.load_calls).is_equal(1)
	assert_int(engine.bind_calls.size()).is_equal(2)
	var first: Dictionary = engine.bind_calls[0][0]
	var second: Dictionary = engine.bind_calls[1][0]
	assert_float(float(first.get("scale", 0.0))).is_equal(4.5)
	assert_float(float(second.get("scale", 0.0))).is_equal(2.0)


func test_zero_and_empty_doses_bind_an_empty_set() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	backend.generate(_steered_request({"malice": 0.0}), Callable(), null)
	backend.generate(_steered_request({}), Callable(), null)
	assert_int(engine.bind_calls.size()).is_equal(2)
	assert_array(engine.bind_calls[0]).is_empty()
	assert_array(engine.bind_calls[1]).is_empty()


func test_turn_after_a_steered_turn_is_not_left_steered() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	backend.generate(_steered_request({"malice": 4.5}), Callable(), null)
	assert_int(engine.bound_vectors.size()).is_equal(1)
	var result := backend.generate(_steered_request({}), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_array(engine.bound_vectors).is_empty()


func test_unbound_path_mix_binds_no_file() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	var dose := {"malice": 4.5, "path_mix": 0.2}
	var result := backend.generate(_steered_request(dose), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(engine.bind_calls.size()).is_equal(1)
	var vectors: Array = engine.bind_calls[0]
	assert_int(vectors.size()).is_equal(1)
	var vector: Dictionary = vectors[0]
	assert_str(String(vector.get("path", ""))).ends_with("malice.gguf")
	var metrics: Dictionary = result.get("metrics", {})
	assert_bool(metrics.has("dose_error")).is_false()


func test_engine_bind_failure_finishes_the_turn_and_reports_the_code() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	engine.bind_error_code = "control_vector_rejected"
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(_steered_request({"malice": 4.5}), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(engine.generate_calls).is_equal(1)
	var metrics: Dictionary = result.get("metrics", {})
	assert_str(String(metrics.get("dose_error", ""))).is_equal("control_vector_rejected")
	assert_bool(bool(metrics.get("dose_applied", true))).is_false()


func test_unmapped_dose_key_finishes_the_turn_without_a_bind() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(_steered_request({"nonsense": 1.0}), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(engine.generate_calls).is_equal(1)
	assert_int(engine.bind_calls.size()).is_equal(0)
	var metrics: Dictionary = result.get("metrics", {})
	assert_str(String(metrics.get("dose_error", ""))).is_equal("control_vector_unmapped")


func test_bind_outcome_reaches_the_turn_metrics() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(_steered_request({"malice": 4.5}), Callable(), null)
	var metrics: Dictionary = result.get("metrics", {})
	assert_bool(metrics.has("dose_set_ms")).is_true()
	assert_bool(float(metrics.get("dose_set_ms", -1.0)) >= 0.0).is_true()
	assert_bool(bool(metrics.get("dose_applied", false))).is_true()
	assert_bool(metrics.has("dose_error")).is_false()


func test_cache_reused_tokens_reach_the_result_and_last_metrics() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ["ok"]
	engine.metrics_extra = {"cache_reused_tokens": 512}
	var backend := NativeBackend.new({}, engine)
	var result := backend.generate(_new_request(), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	var metrics: Dictionary = result.get("metrics", {})
	assert_int(int(metrics.get("cache_reused_tokens", -1))).is_equal(512)
	var last: Dictionary = backend.last_metrics()
	assert_int(int(last.get("cache_reused_tokens", -1))).is_equal(512)
