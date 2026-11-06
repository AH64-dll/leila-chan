class_name NativeSafetyClassifier
extends SafetyClassifierBackend
## In-process classifier transport (P4.03b). Asks the same yes/no question as
## SafetyClassifierHttp, answered by NativeBackend.classify_turn() on the engine's
## second llama_context. That context never has a control vector bound, so the
## answer is dose 0 whatever the turn's dose is (docs/02 §8, SAF-3).
##
## classify() starts one worker per question, as the HTTP class does. Workers
## never touch Nodes or signals. `done` is called from the worker thread, exactly once.

var _native: NativeBackend = null
var _workers: Array[Dictionary] = []
var _shutdown := false


func _init(native_backend: NativeBackend) -> void:
	_native = native_backend


## SafetyClassifierBackend.classify() — worker thread, `done` is called once.
func classify(request: Dictionary, done: Callable) -> void:
	if _shutdown:
		done.call(_error_result("shutdown", "classifier transport is shut down"))
		return
	_reap()
	var thread := Thread.new()
	var err := thread.start(_run.bind(request, done))
	if err != OK:
		done.call(_error_result("thread_error", "could not start classifier thread"))
		return
	_workers.append({"thread": thread})


## Joins every worker. Safe to call from teardown; blocking there is correct.
func shutdown() -> void:
	_shutdown = true
	for worker: Dictionary in _workers:
		var thread: Thread = worker["thread"]
		if thread.is_started():
			thread.wait_to_finish()
	_workers.clear()


func _run(request: Dictionary, done: Callable) -> void:
	var started := Time.get_ticks_msec()
	if _native == null:
		done.call(_error_result("native_unavailable", "no native backend to classify with"))
		return
	var messages := [
		{"role": "system", "content": String(request.get("system", ""))},
		{"role": "user", "content": String(request.get("question", ""))},
	]
	var messages_json := JSON.stringify(messages, "", false)
	var max_tokens := int(request.get("max_tokens", SafetyClassifier.DEFAULT_MAX_TOKENS))
	var response: Dictionary = _native.classify_turn(messages_json, max_tokens)
	var latency := Time.get_ticks_msec() - started
	if not bool(response.get("ok", false)):
		var error: Dictionary = response.get("error", {})
		var failure := {
			"code": String(error.get("code", "classifier_error")),
			"message": String(error.get("message", "")),
		}
		done.call({"ok": false, "error": failure, "raw": "", "latency_ms": latency})
		return
	var raw := String(response.get("text", ""))
	done.call({"ok": true, "verdict": "", "raw": raw, "latency_ms": latency})


func _reap() -> void:
	var alive: Array[Dictionary] = []
	for worker: Dictionary in _workers:
		var thread: Thread = worker["thread"]
		if thread.is_alive():
			alive.append(worker)
		elif thread.is_started():
			thread.wait_to_finish()
	_workers = alive


static func _error_result(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": {"code": code, "message": message},
		"raw": "",
		"latency_ms": 0,
	}
