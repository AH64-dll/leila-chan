extends GdUnitTestSuite
## P4.04 backend switch. Boot picks the native transport through LEILA_BACKEND;
## these cases pin that choice, and the facade paths the native transport takes
## (streaming, spikes, stage steering, dose binding). A scripted FakeEngine stands
## in for the LeilaLLM GDExtension, so every case runs in CI with no model.

const BootScript := preload("res://scenes/Boot.gd")


class FakeEngine:
	extends RefCounted
	var load_result := {"ok": true, "load_ms": 1, "n_ctx": 8192}
	var chunks: Array = []
	var bind_calls: Array = []  # one entry per set_control_vectors(): what it was given

	func load_model(_config: Dictionary) -> Dictionary:
		return load_result

	func is_loaded() -> bool:
		return bool(load_result.get("ok", false))

	func unload() -> void:
		pass

	func set_control_vectors(vectors: Array) -> Dictionary:
		bind_calls.append(vectors.duplicate(true))
		return {"ok": true, "applied": true, "set_ms": 0.1, "n_vectors": vectors.size()}

	func generate(
		_messages_json: String,
		_schema_json: String,
		_sampling: Dictionary,
		_max_tokens: int,
		on_token: Callable,
		_is_cancelled: Callable
	) -> Dictionary:
		var text := ""
		for chunk in chunks:
			if on_token.is_valid():
				on_token.call(String(chunk))
			text += String(chunk)
		return {"ok": true, "text": text, "metrics": {"completion_tokens": chunks.size()}}


## A transport that is not native: no is_native(), so spikes must stay off.
class PlainBackend:
	extends LLMBackend


var _saved_backend: LLMBackend = null
var _saved_dose := {}
var _saved_vectors: Variant = []
var _saved_stage: Variant = 0
var _saved_info := {}


func before_test() -> void:
	_saved_backend = LLM.get_backend()
	_saved_dose = LLM.get_dose()
	_saved_vectors = LLM.get("_steering_vectors")
	_saved_stage = LLM.get("_steering_stage")
	_saved_info = LLM.last_steering_info()
	LLM.set("_steering_vectors", [])
	LLM.set_dose({})


func after_test() -> void:
	Steering.set_spikes_live(false)
	LLM.set_backend(_saved_backend)
	LLM.set_dose(_saved_dose)
	LLM.set("_steering_vectors", _saved_vectors)
	LLM.set("_steering_stage", _saved_stage)
	LLM.set("_last_steering_info", _saved_info)


func _new_request() -> TurnRequest:
	var request := TurnRequest.new()
	request.messages = [{"role": "user", "content": "hi"}]
	request.schema = {"type": "object"}
	request.sampling = {"temperature": 0.75}
	request.max_tokens = 64
	return request


## Runs one turn through the facade and waits for it to finish or fail.
func _run_turn(request: TurnRequest) -> Dictionary:
	var state := {"done": false, "text": "", "error": {}}
	var tokens: Array = []
	var stream := LLM.generate(request)
	stream.token.connect(func(text: String) -> void: tokens.append(text))
	stream.completed.connect(
		func(full: String) -> void:
			state["text"] = full
			state["done"] = true
	)
	stream.failed.connect(
		func(error: Dictionary) -> void:
			state["error"] = error
			state["done"] = true
	)
	var deadline := Time.get_ticks_msec() + 8000
	while not bool(state["done"]) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return {
		"done": bool(state["done"]),
		"text": String(state["text"]),
		"error": state["error"],
		"tokens": tokens,
	}


func test_backend_kind_native_is_honoured_in_a_dev_run() -> void:
	assert_str(BootScript.backend_kind_for("native", false)).is_equal("native")


func test_backend_kind_server_is_honoured_in_an_export() -> void:
	assert_str(BootScript.backend_kind_for("server", true)).is_equal("server")


func test_backend_kind_ignores_case_and_padding() -> void:
	assert_str(BootScript.backend_kind_for("NATIVE ", false)).is_equal("native")


func test_backend_kind_unset_follows_the_export_flag() -> void:
	assert_str(BootScript.backend_kind_for("", true)).is_equal("native")
	assert_str(BootScript.backend_kind_for("", false)).is_equal("server")


func test_backend_kind_unknown_value_falls_back_to_the_default() -> void:
	assert_str(BootScript.backend_kind_for("bogus", false)).is_equal("server")


func test_native_turn_streams_text_and_records_first_say() -> void:
	var engine := FakeEngine.new()
	engine.chunks = ['{"say": "', "Hello", '", "mood": "calm"}']
	LLM.set_backend(NativeBackend.new({}, engine))
	var turn := await _run_turn(_new_request())
	assert_bool(bool(turn["done"])).is_true()
	assert_dict(turn["error"]).is_empty()
	assert_str(String(turn["text"])).is_equal('{"say": "Hello", "mood": "calm"}')
	assert_array(turn["tokens"]).is_equal(engine.chunks)
	var metrics := LLM.last_metrics()
	assert_bool(metrics.has("first_say_ms")).is_true()
	assert_int(int(metrics["first_say_ms"])).is_greater_equal(0)


func test_spike_is_live_on_native_and_off_on_a_plain_backend() -> void:
	LLM.set_backend(NativeBackend.new({}, FakeEngine.new()))
	assert_float(Steering.spike_for({"spike": 4.0})).is_equal(4.0)
	LLM.set_backend(PlainBackend.new())
	assert_float(Steering.spike_for({"spike": 4.0})).is_equal(0.0)


func test_stage_three_steering_records_the_dose_without_engine_work() -> void:
	var engine := FakeEngine.new()
	LLM.set_backend(NativeBackend.new({}, engine))
	assert_bool(LLM.apply_stage_steering(3)).is_true()
	await get_tree().process_frame
	var info := LLM.last_steering_info()
	assert_bool(bool(info.get("ok", false))).is_true()
	assert_dict(info.get("error", {})).is_empty()
	assert_int(int(info.get("stage", -1))).is_equal(3)
	assert_dict(LLM.get_dose()).is_not_empty()
	assert_dict(LLM.get_dose()).is_equal(info.get("dose", {}))
	# The dose binds per turn from TurnRequest.dose, so a stage change never touches
	# the engine on the main thread.
	assert_array(engine.bind_calls).is_empty()


func test_request_dose_is_bound_for_the_turn() -> void:
	var engine := FakeEngine.new()
	LLM.set_backend(NativeBackend.new({}, engine))
	var request := _new_request()
	request.dose = {"malice": 4.5}
	var turn := await _run_turn(request)
	assert_dict(turn["error"]).is_empty()
	assert_int(engine.bind_calls.size()).is_equal(1)
	var bound: Array = engine.bind_calls[0]
	assert_int(bound.size()).is_equal(1)
	assert_float(float(bound[0]["scale"])).is_equal(4.5)


func test_empty_request_dose_picks_up_the_facade_dose() -> void:
	var engine := FakeEngine.new()
	LLM.set_backend(NativeBackend.new({}, engine))
	LLM.set_dose({"malice": 2.5})
	var turn := await _run_turn(_new_request())
	assert_dict(turn["error"]).is_empty()
	assert_int(engine.bind_calls.size()).is_equal(1)
	var bound: Array = engine.bind_calls[0]
	assert_int(bound.size()).is_equal(1)
	assert_float(float(bound[0]["scale"])).is_equal(2.5)
