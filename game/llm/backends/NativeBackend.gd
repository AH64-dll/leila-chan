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
## The layer count of the second load attempt, made when the first one fails on a GPU.
const FALLBACK_GPU_LAYERS := 20
## The keys device_info() reports, taken from the last load result.
const DEVICE_KEYS := [
	"device",
	"device_type",
	"vram_total_mb",
	"vram_free_mb",
	"gpu_layers",
	"classifier_ready",
	"fell_back",
	"fallback_from",
]

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
## P4.05: set by apply_steering() on the main thread, read and reset by the next generate()
## on the worker. The engine's prompt cache keeps the dose its tokens were decoded with, so a
## stage change must drop that cache once. A spike inside one stage keeps it.
var _cache_stale := false  # guarded by _state_mutex
## True when the caller passed a device or a layer count. That load is exactly what the
## caller asked for, so the fallback chain stays off.
var _config_pinned := false


func _init(initial_config: Dictionary = {}, injected_engine: Object = null) -> void:
	_config_pinned = initial_config.has("device") or initial_config.has("n_gpu_layers")
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


## The device the model loaded on, from the last load: the engine's device keys, plus
## fell_back and fallback_from. Empty before a load.
func device_info() -> Dictionary:
	_state_mutex.lock()
	var info := _load_info.duplicate(true)
	_state_mutex.unlock()
	var out := {}
	for key: String in DEVICE_KEYS:
		if info.has(key):
			out[key] = info[key]
	return out


## Asks the engine to stop the load in progress. Safe from any thread. It takes neither
## _load_mutex nor _state_mutex, because the load holds them.
func cancel_load() -> void:
	if _engine != null and _engine.has_method("cancel_load"):
		_engine.call("cancel_load")


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
	var cleared := _clear_stale_cache()
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
	if cleared:
		metrics["cache_cleared"] = true
	metrics["first_say_ms"] = int(first_say_ms[0])
	metrics["generate_ms"] = Time.get_ticks_msec() - started
	if bool(raw.get("ok", false)):
		var text := String(raw.get("text", ""))
		return _record_result({"ok": true, "text": text, "metrics": metrics})
	var error := _normalise_error(raw.get("error", {}))
	return _record_result({"ok": false, "error": error, "metrics": metrics})


## Worker thread, once per turn, just before the engine generates. After a stage change
## the engine's prompt cache holds the old stage's dose, so it is dropped here, once. The
## engine's answer is ignored: only one turn runs at a time, so nothing else can hold the
## engine lock here. Returns true when clear_prompt_cache() was called.
func _clear_stale_cache() -> bool:
	_state_mutex.lock()
	var stale := _cache_stale
	_cache_stale = false
	_state_mutex.unlock()
	if not stale or not _engine.has_method("clear_prompt_cache"):
		return false
	_engine.call("clear_prompt_cache")
	return true


## P4.04: a stage change needs no relaunch in-process. The dose is bound per turn
## from TurnRequest.dose (see _bind_dose), so this does no engine work and restarts
## nothing: it marks the prompt cache stale and reports success, and the facade records
## the stage and dose that the next turn binds. It must not call the engine here: the
## engine is used on the worker thread, and a main-thread bind would race a turn that is
## in flight.
func apply_steering(vectors: Array, stage: int, window_ms: int, done: Callable) -> bool:
	var info := {
		"ok": true,
		"stage": stage,
		"ms": 0,
		"total_ms": 0,
		"deferred_ms": 0,
		"window_ms": window_ms,
		"budget_ms": LlamaServerBackend.STEERING_BUDGET_MS,
		"within_budget": true,
		"fits_window": true,
		"vectors": vectors.duplicate(true),
		"previous_vectors": [],
		"kept_previous": false,
		"recovered": false,
		"pid": 0,
		"restarts": 0,
		"error": {},
	}
	_state_mutex.lock()
	_cache_stale = true
	_state_mutex.unlock()
	if done.is_valid():
		done.call_deferred(info)
	return true


## One classifier question, worker thread only. The engine answers on its own
## context, which never carries a control vector (docs/02 §8, SAF-3). Does not
## touch last_metrics(), which belongs to the turn.
func classify_turn(messages_json: String, max_tokens: int) -> Dictionary:
	var load_result := ensure_loaded()
	if not bool(load_result.get("ok", false)):
		var load_error: Dictionary = load_result.get("error", {})
		return {"ok": false, "error": _normalise_error(load_error), "metrics": {}}
	var raw: Dictionary = _engine.classify(messages_json, max_tokens)
	if bool(raw.get("ok", false)):
		return raw
	var failed := _normalise_error(raw.get("error", {}))
	return {"ok": false, "error": failed, "metrics": raw.get("metrics", {})}


## Frees the model and context. Called on the main thread at teardown. unload()
## waits for a running generate(), so no mutex is held here.
func shutdown() -> void:
	if _engine != null:
		_engine.unload()


## P4.05: drops the engine's prompt-prefix KV cache, so the next turn decodes its whole prompt.
## Returns false when the engine is busy with a turn (it try-locks and never waits). With no
## engine there is nothing to drop, so the answer is true.
func clear_prompt_cache() -> bool:
	if _engine == null:
		return true
	return bool(_engine.clear_prompt_cache())


## True when a LeilaLLM engine is attached. False in a build without the GDExtension.
func has_engine() -> bool:
	return _engine != null


## The model file a load would read, after the same resolution order as _load_engine().
func resolved_model_path() -> String:
	return _resolve_model_path()


## Load progress from the engine, 0 to 1. The engine method is optional, so an engine
## without load_progress() reports 0.
func load_progress() -> float:
	if _engine == null or not _engine.has_method("load_progress"):
		return 0.0
	return clampf(float(_engine.call("load_progress")), 0.0, 1.0)


## Lets the next ensure_loaded() attempt again after a failed load. A load that succeeded
## is kept: the engine already holds the model, so loading it again would be waste.
func reset_load() -> void:
	_load_mutex.lock()
	_state_mutex.lock()
	var failed := not bool(_load_info.get("ok", false))
	_state_mutex.unlock()
	if failed:
		_load_attempted = false
	_load_mutex.unlock()


## The fallback chain. The configured device and layers go first. An unpinned load that
## fails on a GPU retries with FALLBACK_GPU_LAYERS, then on the processor. A cancelled
## attempt stops the chain at once.
func _load_engine() -> Dictionary:
	if _engine == null:
		var missing := _error(
			"native_unavailable",
			"LeilaLLM GDExtension is not registered; run native/build_linux.sh"
		)
		return {"ok": false, "error": missing}
	var base := {
		"model_path": _resolve_model_path(),
		"backend_dir": _resolve_backend_dir(),
		"n_ctx": int(config.get("n_ctx", 8192)),
		"n_threads": int(config.get("n_threads", -1)),
	}
	var device := String(config.get("device", "auto"))
	var layers := int(config.get("n_gpu_layers", 99))
	var first := _attempt_load(base, device, layers)
	if bool(first.get("ok", false)) or _pinned() or _was_cancelled(first):
		return _chain_result(first, false, {})
	return _fall_back(base, device, layers, first)


## The retries after a failed unpinned load: 20 layers on the same device, then the
## processor. Returns the first success with fell_back set, or the last failure.
func _fall_back(base: Dictionary, device: String, layers: int, first: Dictionary) -> Dictionary:
	var reported := String(first.get("device", ""))
	var failed_device := reported if not reported.is_empty() else device
	if failed_device.to_lower() == "cpu":
		return _chain_result(first, false, {})
	var origin := _failure_origin(first, failed_device)
	var fallback := _attempt_load(base, device, FALLBACK_GPU_LAYERS)
	if bool(fallback.get("ok", false)):
		return _chain_result(fallback, true, origin)
	if _was_cancelled(fallback):
		return _chain_result(fallback, false, {})
	var cpu := _attempt_load(base, "cpu", layers)
	if bool(cpu.get("ok", false)):
		return _chain_result(cpu, true, origin)
	return _chain_result(cpu, false, {})


## An explicit device or layer count in the config turns the chain off.
func _pinned() -> bool:
	return _config_pinned or config.has("device") or int(config.get("n_gpu_layers", 99)) != 99


## One engine load with the device and layer count set. Prints one line per failure.
func _attempt_load(base: Dictionary, device: String, layers: int) -> Dictionary:
	var load_config := base.duplicate()
	load_config["device"] = device
	load_config["n_gpu_layers"] = layers
	var result: Dictionary = _engine.load_model(load_config)
	if not bool(result.get("ok", false)):
		var code := String(_normalise_error(result.get("error", {}))["code"])
		print("[LeilaLLM] load failed on %s (%d layers): %s" % [device, layers, code])
	return result


func _chain_result(result: Dictionary, fell_back: bool, origin: Dictionary) -> Dictionary:
	var out := result.duplicate()
	out["fell_back"] = fell_back
	if fell_back:
		out["fallback_from"] = origin
	return out


## The first failure, for fallback_from.
static func _failure_origin(failed: Dictionary, device: String) -> Dictionary:
	var error := _normalise_error(failed.get("error", {}))
	return {"device": device, "code": error["code"], "message": error["message"]}


static func _was_cancelled(result: Dictionary) -> bool:
	var error: Variant = result.get("error", {})
	return error is Dictionary and String(error.get("code", "")) == "cancelled"


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
