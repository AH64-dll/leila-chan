extends GdUnitTestSuite
## P4.05 stage-change cache drop (docs/07 §3.1). apply_steering() marks the prompt cache
## stale, and the next generate() drops it once. No binary and no model: scripted engines
## record the calls, so every case runs in CI. These cases live here, not in
## NativeBackendTest.gd, which is at its 20-public-method cap.


## The full engine surface, including clear_prompt_cache(). Records every call in order.
class ClearEngine:
	extends RefCounted
	var clear_calls := 0
	var generate_calls := 0
	var call_order: Array = []  # "load", "bind", "clear", "generate" in the order they happened

	func load_model(_config: Dictionary) -> Dictionary:
		call_order.append("load")
		return {"ok": true, "load_ms": 1, "n_layer": 2, "n_embd": 3, "n_ctx": 8192}

	func set_control_vectors(vectors: Array) -> Dictionary:
		call_order.append("bind")
		return {"ok": true, "applied": true, "set_ms": 0.1, "n_vectors": vectors.size()}

	func clear_prompt_cache() -> bool:
		clear_calls += 1
		call_order.append("clear")
		return true

	func generate(
		_messages_json: String,
		_schema_json: String,
		_sampling: Dictionary,
		_max_tokens: int,
		_on_token: Callable,
		_is_cancelled: Callable
	) -> Dictionary:
		generate_calls += 1
		call_order.append("generate")
		return {"ok": true, "text": "ok", "metrics": {}}


## The same surface without clear_prompt_cache(), as an older engine build would expose.
class EngineWithoutClear:
	extends RefCounted
	var generate_calls := 0

	func load_model(_config: Dictionary) -> Dictionary:
		return {"ok": true, "load_ms": 1, "n_layer": 2, "n_embd": 3, "n_ctx": 8192}

	func set_control_vectors(vectors: Array) -> Dictionary:
		return {"ok": true, "applied": true, "set_ms": 0.1, "n_vectors": vectors.size()}

	func generate(
		_messages_json: String,
		_schema_json: String,
		_sampling: Dictionary,
		_max_tokens: int,
		_on_token: Callable,
		_is_cancelled: Callable
	) -> Dictionary:
		generate_calls += 1
		return {"ok": true, "text": "ok", "metrics": {}}


func _new_request() -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [{"role": "user", "content": "hi"}]
	request.schema = {"type": "object"}
	request.sampling = {"temperature": 0.75}
	request.max_tokens = 64
	return request


func _steered_request(dose: Dictionary) -> TurnRequest:
	var request := _new_request()
	request.dose = dose
	return request


func test_apply_steering_never_calls_the_engine() -> void:
	var engine := ClearEngine.new()
	var backend := NativeBackend.new({}, engine)
	assert_bool(backend.apply_steering([], 2, 0, Callable())).is_true()
	assert_array(engine.call_order).is_empty()
	assert_int(engine.clear_calls).is_equal(0)


func test_stage_change_clears_the_cache_once_before_the_next_generate() -> void:
	var engine := ClearEngine.new()
	var backend := NativeBackend.new({}, engine)
	backend.apply_steering([], 2, 0, Callable())
	assert_int(engine.clear_calls).is_equal(0)
	var first := backend.generate(_new_request(), Callable(), null)
	assert_bool(bool(first.get("ok", false))).is_true()
	assert_int(engine.clear_calls).is_equal(1)
	assert_array(engine.call_order).is_equal(["load", "bind", "clear", "generate"])
	var first_metrics: Dictionary = first.get("metrics", {})
	assert_bool(bool(first_metrics.get("cache_cleared", false))).is_true()
	var second := backend.generate(_new_request(), Callable(), null)
	assert_bool(bool(second.get("ok", false))).is_true()
	assert_int(engine.clear_calls).is_equal(1)
	assert_array(engine.call_order).is_equal(
		["load", "bind", "clear", "generate", "bind", "generate"]
	)
	var second_metrics: Dictionary = second.get("metrics", {})
	assert_bool(second_metrics.has("cache_cleared")).is_false()


func test_dose_spike_without_a_stage_change_keeps_the_cache() -> void:
	var engine := ClearEngine.new()
	var backend := NativeBackend.new({}, engine)
	backend.generate(_steered_request({"malice": 4.5}), Callable(), null)
	var spike := backend.generate(_steered_request({"malice": 2.0}), Callable(), null)
	assert_bool(bool(spike.get("ok", false))).is_true()
	assert_int(engine.clear_calls).is_equal(0)
	assert_array(engine.call_order).is_equal(["load", "bind", "generate", "bind", "generate"])
	var spike_metrics: Dictionary = spike.get("metrics", {})
	assert_bool(spike_metrics.has("cache_cleared")).is_false()


func test_engine_without_clear_prompt_cache_does_not_fail() -> void:
	var engine := EngineWithoutClear.new()
	var backend := NativeBackend.new({}, engine)
	backend.apply_steering([], 2, 0, Callable())
	var result := backend.generate(_new_request(), Callable(), null)
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_int(engine.generate_calls).is_equal(1)
	var metrics: Dictionary = result.get("metrics", {})
	assert_bool(metrics.has("cache_cleared")).is_false()
