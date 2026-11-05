class_name NativeBackend
extends LLMBackend
## P4.02 in-process transport. One turn runs through the LeilaLLM GDExtension
## (native/src/leila_llm.h) instead of llama-server over HTTP: no child
## process and no port. generate() runs on the LLM facade's WORKER thread and
## never touches Nodes or signals (docs/07 §3.1). The engine is injectable, so
## the contract runs in CI with no binary and no model.

const ENGINE_CLASS := "LeilaLLM"
const MODEL_FILE := "Qwen3.5-4B-Q4_K_M.gguf"
const SERVER_PROCESS := preload("res://llm/backends/LlamaServerProcess.gd")

## Keys read by LeilaLLM.load_model(). Empty paths resolve when the model loads.
var config := {
	"model_path": "",
	"backend_dir": "",
	"n_ctx": 8192,
	"n_gpu_layers": 99,
	"n_threads": -1,
}

var _engine: Object = null
## Dose key -> vector file. Created and loaded in _init; read only on the worker thread.
var _steering: StageSteering = null
## Held for the whole load_model() call, so only worker threads take it.
var _load_mutex := Mutex.new()
## Guards the result fields that the main thread may read.
var _state_mutex := Mutex.new()
var _load_attempted := false  # guarded by _load_mutex
var _load_info := {}  # guarded by _state_mutex
var _last_metrics := {}  # guarded by _state_mutex


func _init(initial_config: Dictionary = {}, injected_engine: Object = null) -> void:
	config.merge(initial_config, true)
	_engine = injected_engine if injected_engine != null else _create_default_engine()
	_steering = StageSteering.new()
	_steering.load_map()


## The real engine when the GDExtension is registered. Named by string so this
## script still parses where the binary is absent (CI).
func _create_default_engine() -> Object:
	if ClassDB.class_exists(ENGINE_CLASS):
		return ClassDB.instantiate(ENGINE_CLASS)
	return null


func is_native() -> bool:
	return true


func last_metrics() -> Dictionary:
	_state_mutex.lock()
	var out := _last_metrics.duplicate(true)
	_state_mutex.unlock()
	return out


func last_load_info() -> Dictionary:
	_state_mutex.lock()
	var out := _load_info.duplicate(true)
	_state_mutex.unlock()
	return out


## Loads the model once and returns the load result. Worker thread only: the
## call blocks for the whole load. A failed load is cached as well, so a
## missing model costs one attempt per process instead of one per turn.
func ensure_loaded() -> Dictionary:
	_load_mutex.lock()
	if not _load_attempted:
		var result := _load_engine()
		_state_mutex.lock()
		_load_info = result
		_state_mutex.unlock()
		_load_attempted = true
	_load_mutex.unlock()
	_state_mutex.lock()
	var out := _load_info.duplicate(true)
	_state_mutex.unlock()
	return out


## One turn, worker thread only. Returns {ok:true, text, metrics} on success or
## {ok:false, error:{code, message}, metrics} on failure.
func generate(request: TurnRequest, on_token: Callable, cancel: LLMCancelToken) -> Dictionary:
	var started := Time.get_ticks_msec()
	var invalid := _validate_request(request)
	if not invalid.is_empty():
		return _record_result({"ok": false, "error": invalid, "metrics": {}})
	var load_result := ensure_loaded()
	if not bool(load_result.get("ok", false)):
		var load_error: Dictionary = load_result.get("error", {})
		var load_metrics := {"generate_ms": Time.get_ticks_msec() - started}
		var failed := _normalise_error(load_error)
		return _record_result({"ok": false, "error": failed, "metrics": load_metrics})
	# Godot sorts dictionary keys in JSON.stringify by default. The streaming
	# parser depends on the schema's property order, so keep insertion order.
	var messages_json := JSON.stringify(request.messages, "", false)
	var schema_json := JSON.stringify(request.schema, "", false)
	var request_started := Time.get_ticks_msec()
	var first_say_ms := [-1]
	var probe := LlamaServerBackend.FirstSayProbe.new()
	var forward := func(text: String) -> void:
		if first_say_ms[0] < 0 and probe.feed(text):
			first_say_ms[0] = Time.get_ticks_msec() - request_started
		if on_token.is_valid():
			on_token.call(text)
	var is_cancelled := Callable()
	if cancel != null:
		is_cancelled = Callable(cancel, "is_cancelled")
	var dose_bind := _bind_dose(request.dose)
	var raw: Dictionary = _engine.generate(
		messages_json, schema_json, request.sampling, request.max_tokens, forward, is_cancelled
	)
	var metrics := {}
	var raw_metrics: Variant = raw.get("metrics", {})
	if raw_metrics is Dictionary:
		metrics = raw_metrics.duplicate()
	metrics["dose_set_ms"] = dose_bind["set_ms"]
	metrics["dose_applied"] = dose_bind["applied"]
	var dose_error: Dictionary = dose_bind["error"]
	if not dose_error.is_empty():
		metrics["dose_error"] = String(dose_error.get("code", "native_error"))
	metrics["first_say_ms"] = int(first_say_ms[0])
	metrics["generate_ms"] = Time.get_ticks_msec() - started
	if bool(raw.get("ok", false)):
		var text := String(raw.get("text", ""))
		return _record_result({"ok": true, "text": text, "metrics": metrics})
	var error := _normalise_error(raw.get("error", {}))
	return _record_result({"ok": false, "error": error, "metrics": metrics})


## Frees the model and context. Called on the main thread at teardown. unload()
## waits for a running generate(), so no mutex is held here.
func shutdown() -> void:
	if _engine != null:
		_engine.unload()


func _load_engine() -> Dictionary:
	if _engine == null:
		var missing := _error(
			"native_unavailable",
			"LeilaLLM GDExtension is not registered; run native/build_linux.sh"
		)
		return {"ok": false, "error": missing}
	var load_config := {
		"model_path": _resolve_model_path(),
		"backend_dir": _resolve_backend_dir(),
		"n_ctx": int(config.get("n_ctx", 8192)),
		"n_gpu_layers": int(config.get("n_gpu_layers", 99)),
		"n_threads": int(config.get("n_threads", -1)),
	}
	var result: Dictionary = _engine.load_model(load_config)
	return result


## Binds the turn's dose before generate(). Worker thread only, no Nodes or
## signals. An empty or all-zero dose binds [], which clears the previous turn's
## vectors. A failure keeps the old dose and does not fail the turn: the caller
## records the code in metrics, as the server path does.
func _bind_dose(dose: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var launch := _steering.launch_for(dose)
	var unbound: Array = launch.get("unbound", [])
	if not bool(launch.get("ok", false)):
		var refused := _normalise_error(launch.get("error", {}))
		return {"set_ms": 0.0, "applied": false, "unbound": unbound, "error": refused}
	var raw: Dictionary = _engine.set_control_vectors(launch.get("vectors", []))
	var elapsed := float(Time.get_ticks_msec() - started)
	if not bool(raw.get("ok", false)):
		var error := _normalise_error(raw.get("error", {}))
		return {"set_ms": elapsed, "applied": false, "unbound": unbound, "error": error}
	return {
		"set_ms": float(raw.get("set_ms", elapsed)),
		"applied": bool(raw.get("applied", false)),
		"unbound": unbound,
		"error": {},
	}


## Order: config, then env LEILA_MODEL, then a model beside the executable (only
## if the file exists), then the dev default that LlamaServerProcess uses.
func _resolve_model_path() -> String:
	var configured := String(config.get("model_path", ""))
	if not configured.is_empty():
		return configured
	var from_env := OS.get_environment("LEILA_MODEL")
	if not from_env.is_empty():
		return from_env
	var beside_exe := OS.get_executable_path().get_base_dir().path_join("models")
	beside_exe = beside_exe.path_join(MODEL_FILE)
	if FileAccess.file_exists(beside_exe):
		return beside_exe
	return SERVER_PROCESS.default_model_path()


func _resolve_backend_dir() -> String:
	var configured := String(config.get("backend_dir", ""))
	if not configured.is_empty():
		return configured
	return _default_backend_dir()


## Exported builds ship the libraries beside the executable. Editor and headless
## dev runs read them from the addon's bin directory.
static func _default_backend_dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir()
	var os_dir := OS.get_name().to_lower()
	return ProjectSettings.globalize_path("res://addons/leila_llm/bin/" + os_dir)


func _validate_request(request: TurnRequest) -> Dictionary:
	if request == null:
		return _error("invalid_request", "generate() needs a TurnRequest")
	if request.messages.is_empty():
		return _error("invalid_request", "TurnRequest.messages must not be empty")
	if request.schema.is_empty():
		return _error(
			"invalid_request",
			"TurnRequest.schema is empty; refusing to stream an unconstrained turn"
		)
	return {}


func _record_result(result: Dictionary) -> Dictionary:
	_state_mutex.lock()
	_last_metrics = result.get("metrics", {}).duplicate(true)
	_state_mutex.unlock()
	return result


static func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}


static func _normalise_error(error: Variant) -> Dictionary:
	if error is Dictionary:
		var code := String(error.get("code", "native_error"))
		return _error(code, String(error.get("message", "")))
	return _error("native_error", "engine returned no error detail")
