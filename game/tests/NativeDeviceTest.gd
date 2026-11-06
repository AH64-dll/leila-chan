extends GdUnitTestSuite
## P4.09 device fallback chain in NativeBackend. A scripted engine answers each load_model()
## call in order, so every case checks the exact attempts the chain makes.

const MODEL_PATH := "user://fake.gguf"
const OOM := {
	"ok": false,
	"device": "CUDA0",
	"error": {"code": "native_error", "message": "CUDA error: out of memory"},
}
const CPU_OK := {"ok": true, "device": "CPU", "device_type": "cpu"}
const GPU_OK := {"ok": true, "device": "CUDA0", "device_type": "gpu"}


## Answers load_model() from results in order; the last result repeats. Records each call.
class ScriptedEngine:
	extends RefCounted
	var results: Array = [{"ok": true}]
	var calls: Array = []
	var cancel_calls := 0

	func load_model(config: Dictionary) -> Dictionary:
		calls.append(
			{
				"device": String(config.get("device", "")),
				"layers": int(config.get("n_gpu_layers", -1))
			}
		)
		return results[mini(calls.size() - 1, results.size() - 1)]

	func is_loaded() -> bool:
		return false

	func unload() -> void:
		pass

	func cancel_load() -> void:
		cancel_calls += 1


## A native backend with no engine attached.
class NoEngineBackend:
	extends NativeBackend

	func _create_default_engine() -> Object:
		return null


func _make_backend(engine: ScriptedEngine, extra := {}) -> NativeBackend:
	var config := {"model_path": MODEL_PATH}
	config.merge(extra)
	return NativeBackend.new(config, engine)


func test_a_successful_load_takes_one_attempt() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [GPU_OK]
	var result := _make_backend(engine).ensure_loaded()
	assert_bool(bool(result["ok"])).is_true()
	assert_bool(bool(result["fell_back"])).is_false()
	assert_int(engine.calls.size()).is_equal(1)
	assert_str(String(engine.calls[0]["device"])).is_equal("auto")
	assert_int(int(engine.calls[0]["layers"])).is_equal(99)


func test_a_failed_load_retries_with_twenty_layers_then_the_processor() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [OOM, OOM, CPU_OK]
	var result := _make_backend(engine).ensure_loaded()
	assert_bool(bool(result["ok"])).is_true()
	assert_bool(bool(result["fell_back"])).is_true()
	assert_int(engine.calls.size()).is_equal(3)
	assert_str(String(engine.calls[1]["device"])).is_equal("auto")
	assert_int(int(engine.calls[1]["layers"])).is_equal(20)
	assert_str(String(engine.calls[2]["device"])).is_equal("cpu")
	var origin: Dictionary = result["fallback_from"]
	assert_str(String(origin["device"])).is_equal("CUDA0")
	assert_str(String(origin["code"])).is_equal("native_error")
	assert_str(String(origin["message"])).is_equal("CUDA error: out of memory")


func test_the_twenty_layer_retry_can_succeed_without_the_processor() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [OOM, GPU_OK]
	var result := _make_backend(engine).ensure_loaded()
	assert_bool(bool(result["ok"])).is_true()
	assert_bool(bool(result["fell_back"])).is_true()
	assert_int(engine.calls.size()).is_equal(2)
	assert_int(int(engine.calls[1]["layers"])).is_equal(20)


func test_an_explicit_device_turns_the_chain_off() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [OOM, CPU_OK]
	var result := _make_backend(engine, {"device": "CUDA0"}).ensure_loaded()
	assert_bool(bool(result["ok"])).is_false()
	assert_bool(bool(result["fell_back"])).is_false()
	assert_int(engine.calls.size()).is_equal(1)
	assert_str(String(engine.calls[0]["device"])).is_equal("CUDA0")


func test_explicit_layers_turn_the_chain_off() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [OOM, CPU_OK]
	var result := _make_backend(engine, {"n_gpu_layers": 99}).ensure_loaded()
	assert_bool(bool(result["ok"])).is_false()
	assert_int(engine.calls.size()).is_equal(1)
	assert_int(int(engine.calls[0]["layers"])).is_equal(99)


func test_all_attempts_failing_returns_the_last_error() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [
		{"ok": false, "device": "CUDA0", "error": {"code": "first", "message": "one"}},
		{"ok": false, "device": "CUDA0", "error": {"code": "second", "message": "two"}},
		{"ok": false, "device": "CPU", "error": {"code": "last", "message": "three"}},
	]
	var result := _make_backend(engine).ensure_loaded()
	assert_bool(bool(result["ok"])).is_false()
	assert_bool(bool(result["fell_back"])).is_false()
	var error: Dictionary = result["error"]
	assert_str(String(error["code"])).is_equal("last")
	assert_str(String(error["message"])).is_equal("three")
	assert_int(engine.calls.size()).is_equal(3)


func test_a_configured_cpu_load_makes_one_attempt() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [{"ok": false, "error": {"code": "native_error", "message": "no memory"}}]
	var result := _make_backend(engine, {"device": "cpu"}).ensure_loaded()
	assert_bool(bool(result["ok"])).is_false()
	assert_int(engine.calls.size()).is_equal(1)
	assert_str(String(engine.calls[0]["device"])).is_equal("cpu")


func test_a_failure_reported_on_the_processor_is_not_retried() -> void:
	var engine := ScriptedEngine.new()
	engine.results = [{"ok": false, "device": "cpu", "error": {"code": "native_error"}}]
	var result := _make_backend(engine).ensure_loaded()
	assert_bool(bool(result["ok"])).is_false()
	assert_int(engine.calls.size()).is_equal(1)


func test_a_cancelled_load_stops_the_chain_after_one_attempt() -> void:
	var engine := ScriptedEngine.new()
	var cancelled := {"ok": false, "error": {"code": "cancelled", "message": "load cancelled"}}
	engine.results = [cancelled, GPU_OK]
	var result := _make_backend(engine).ensure_loaded()
	var error: Dictionary = result["error"]
	assert_str(String(error["code"])).is_equal("cancelled")
	assert_bool(bool(result["fell_back"])).is_false()
	assert_int(engine.calls.size()).is_equal(1)


func test_device_info_is_empty_before_a_load() -> void:
	var backend := _make_backend(ScriptedEngine.new())
	assert_bool(backend.device_info().is_empty()).is_true()


func test_device_info_reports_the_device_of_the_last_load() -> void:
	var engine := ScriptedEngine.new()
	var cpu_load := {"ok": true, "device": "CPU", "device_type": "cpu", "gpu_layers": 0}
	engine.results = [OOM, cpu_load]
	var backend := _make_backend(engine)
	backend.ensure_loaded()
	var info := backend.device_info()
	assert_str(String(info["device_type"])).is_equal("cpu")
	assert_int(int(info["gpu_layers"])).is_equal(0)
	assert_bool(bool(info["fell_back"])).is_true()
	assert_str(String(info["fallback_from"]["device"])).is_equal("CUDA0")
	assert_bool(info.has("ok")).is_false()


func test_cancel_load_reaches_the_engine() -> void:
	var engine := ScriptedEngine.new()
	_make_backend(engine).cancel_load()
	assert_int(engine.cancel_calls).is_equal(1)


func test_cancel_load_without_an_engine_does_nothing() -> void:
	var backend := NoEngineBackend.new({"model_path": MODEL_PATH}, null)
	backend.cancel_load()
	assert_bool(backend.has_engine()).is_false()
