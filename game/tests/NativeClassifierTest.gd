extends GdUnitTestSuite
## P4.03b NativeSafetyClassifier contract (docs/02 §8). No binary and no model: a
## scripted FakeEngine answers classify(), so every case runs in CI. The fake
## records the messages and max_tokens it was given.


class FakeEngine:
	extends RefCounted
	var load_calls := 0
	var classify_calls := 0
	var load_result := {"ok": true, "n_ctx": 1024}
	var classify_result := {"ok": true, "text": "no", "metrics": {"total_ms": 3}}
	var last_messages_json := ""
	var last_max_tokens := -1

	func load_model(_config: Dictionary) -> Dictionary:
		load_calls += 1
		return load_result

	func is_loaded() -> bool:
		return load_calls > 0 and bool(load_result.get("ok", false))

	func unload() -> void:
		pass

	func classify(messages_json: String, max_tokens: int) -> Dictionary:
		classify_calls += 1
		last_messages_json = messages_json
		last_max_tokens = max_tokens
		return classify_result


## Collects what done() receives. done() runs on the worker thread, so a test
## reads the box only after shutdown() has joined that worker.
class Box:
	extends RefCounted
	var mutex := Mutex.new()
	var calls := 0
	var result := {}

	func put(value: Dictionary) -> void:
		mutex.lock()
		calls += 1
		result = value.duplicate(true)
		mutex.unlock()


const SYSTEM := "Answer only yes or no."
const QUESTION := "Is water wet?"


func _request(extra: Dictionary = {}) -> Dictionary:
	var request := {"system": SYSTEM, "question": QUESTION}
	request.merge(extra, true)
	return request


## One question on a fresh classifier. shutdown() joins the worker, so done has
## run by the time this returns.
func _ask(backend: NativeBackend, request: Dictionary) -> Box:
	var box := Box.new()
	var classifier := NativeSafetyClassifier.new(backend)
	classifier.classify(request, Callable(box, "put"))
	classifier.shutdown()
	return box


func test_success_returns_the_documented_shape() -> void:
	var engine := FakeEngine.new()
	engine.classify_result = {"ok": true, "text": "no", "metrics": {"total_ms": 3}}
	var box := _ask(NativeBackend.new({}, engine), _request())
	var result: Dictionary = box.result
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_str(String(result.get("verdict", "x"))).is_equal("")
	assert_str(String(result.get("raw", ""))).is_equal("no")
	assert_bool(int(result.get("latency_ms", -1)) >= 0).is_true()
	assert_int(result.keys().size()).is_equal(4)


func test_engine_failure_maps_to_the_failure_shape() -> void:
	var engine := FakeEngine.new()
	engine.classify_result = {
		"ok": false,
		"error": {"code": "decode_failed", "message": "boom"},
		"metrics": {},
	}
	var box := _ask(NativeBackend.new({}, engine), _request())
	var result: Dictionary = box.result
	assert_bool(bool(result.get("ok", true))).is_false()
	assert_dict(result["error"]).is_equal({"code": "decode_failed", "message": "boom"})
	assert_str(String(result.get("raw", "x"))).is_equal("")
	assert_bool(int(result.get("latency_ms", -1)) >= 0).is_true()
	assert_int(result.keys().size()).is_equal(4)


func test_done_runs_exactly_once_per_question() -> void:
	var engine := FakeEngine.new()
	var backend := NativeBackend.new({}, engine)
	var box := Box.new()
	var classifier := NativeSafetyClassifier.new(backend)
	classifier.classify(_request(), Callable(box, "put"))
	classifier.classify(_request(), Callable(box, "put"))
	classifier.shutdown()
	assert_int(box.calls).is_equal(2)
	assert_int(engine.classify_calls).is_equal(2)


func test_load_failure_reaches_done_as_ok_false_and_skips_classify() -> void:
	var engine := FakeEngine.new()
	engine.load_result = {"ok": false, "error": {"code": "model_not_found", "message": "no file"}}
	var box := _ask(NativeBackend.new({}, engine), _request())
	var result: Dictionary = box.result
	assert_bool(bool(result.get("ok", true))).is_false()
	assert_dict(result["error"]).is_equal({"code": "model_not_found", "message": "no file"})
	assert_str(String(result.get("raw", "x"))).is_equal("")
	assert_int(box.calls).is_equal(1)
	assert_int(engine.classify_calls).is_equal(0)


func test_after_shutdown_classify_returns_shutdown_without_reaching_the_engine() -> void:
	var engine := FakeEngine.new()
	var classifier := NativeSafetyClassifier.new(NativeBackend.new({}, engine))
	classifier.shutdown()
	var box := Box.new()
	classifier.classify(_request(), Callable(box, "put"))
	assert_int(box.calls).is_equal(1)
	var error: Dictionary = box.result.get("error", {})
	assert_str(String(error.get("code", ""))).is_equal("shutdown")
	assert_bool(bool(box.result.get("ok", true))).is_false()
	assert_int(engine.classify_calls).is_equal(0)


func test_system_and_question_reach_the_engine_as_messages() -> void:
	var engine := FakeEngine.new()
	_ask(NativeBackend.new({}, engine), _request({"max_tokens": 5}))
	var parsed: Variant = JSON.parse_string(engine.last_messages_json)
	assert_bool(parsed is Array).is_true()
	if not parsed is Array:
		return
	var messages: Array = parsed
	assert_int(messages.size()).is_equal(2)
	assert_str(String(messages[0]["role"])).is_equal("system")
	assert_str(String(messages[0]["content"])).is_equal(SYSTEM)
	assert_str(String(messages[1]["role"])).is_equal("user")
	assert_str(String(messages[1]["content"])).is_equal(QUESTION)
	assert_int(engine.last_max_tokens).is_equal(5)


func test_max_tokens_defaults_to_the_safety_classifier_budget() -> void:
	var engine := FakeEngine.new()
	_ask(NativeBackend.new({}, engine), _request())
	assert_int(engine.last_max_tokens).is_equal(SafetyClassifier.DEFAULT_MAX_TOKENS)


func test_no_native_backend_reports_native_unavailable() -> void:
	var box := _ask(null, _request())
	assert_bool(bool(box.result.get("ok", true))).is_false()
	var error: Dictionary = box.result.get("error", {})
	assert_str(String(error.get("code", ""))).is_equal("native_unavailable")
	assert_int(box.calls).is_equal(1)
