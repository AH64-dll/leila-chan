extends Node
## LLM — backend facade (docs/07 §3.1). The Director hands it one TurnRequest
## per turn; the injected LLMBackend runs it on a worker thread. Every emission
## reaches the main thread via call_deferred and nothing here ever blocks the
## main thread: the worker does all waiting, and finished threads are joined
## only once is_alive() reports them dead.

signal token(text: String)  ## Raw stream: each chunk of the in-flight turn.

var _backend: LLMBackend  ## Injected transport; null until set_backend() (P1.02 wires the default).
var _dose := {}  ## Current control-vector dose {name: scale} from set_dose().
var _dose_mutex := Mutex.new()
var _active: TurnStream  ## The in-flight turn, or null. One turn at a time.
var _thread: Thread  ## Worker thread running the backend, or null.
var _pending_join: Array[Thread] = []  ## Spent workers awaiting a non-blocking join.
var _shutdown_done := false


## Inject the transport backend. Call on the main thread; takes effect on the
## next generate() — an in-flight turn keeps the backend it started with.
func set_backend(new_backend: LLMBackend) -> void:
	_backend = new_backend


func has_backend() -> bool:
	return _backend != null


func get_backend() -> LLMBackend:
	return _backend


func last_metrics() -> Dictionary:
	if _backend != null and _backend.has_method("last_metrics"):
		return _backend.last_metrics()
	return {}


## P1.02: install the prototype llama-server transport (attach by default,
## `auto_start=true` to launch the pinned server). Returns it so the boot flow
## can start the watchdog or pre-warm. Boot wires this at startup.
func use_default_backend(config: Dictionary = {}) -> LlamaServerBackend:
	var backend := LlamaServerBackend.new(config)
	set_backend(backend)
	return backend


## docs/07 §3.1: set the current steering dose {"malice": 4.5, ...}. Fills
## TurnRequest.dose when a request leaves it empty; the dose bound to a
## request is frozen at generate(), so in-flight turns are unaffected.
func set_dose(vectors: Dictionary) -> void:
	_dose_mutex.lock()
	_dose = vectors.duplicate()
	_dose_mutex.unlock()


func get_dose() -> Dictionary:
	_dose_mutex.lock()
	var vectors := _dose.duplicate()
	_dose_mutex.unlock()
	return vectors


## docs/07 §3.1: generate(req) -> TurnStream. Never blocks — the stream
## answers through its signals while the turn runs on the worker. One turn at
## a time: while busy the returned stream fails with {"code": "busy"}.
## TurnRequest instances are single-use per turn and owned by the in-flight
## turn once passed to generate(); callers must not reuse or mutate them.
## If req.dose is empty, it is filled with get_dose() and frozen for the turn.
func generate(request: TurnRequest) -> TurnStream:
	var stream := TurnStream.new()
	stream.request = request
	if request == null:
		_defer_failed(stream, "invalid_request", "generate() needs a TurnRequest")
		return stream
	if _active != null:
		_defer_failed(stream, "busy", "a turn is already in flight")
		return stream
	if _backend == null:
		_defer_failed(stream, "no_backend", "no LLMBackend set — call set_backend() first")
		return stream
	if request.dose.is_empty():
		request.dose = get_dose()
	_active = stream
	_thread = Thread.new()
	var err := _thread.start(_worker_main.bind(stream, _backend))
	if err != OK:
		_thread = null
		_active = null
		_defer_failed(stream, "thread_error", "could not start worker (error %d)" % err)
	return stream


## Cancel the in-flight turn, if any. The stream answers with `cancelled`
## once cancellation is honoured. Cancellation wins over completion or
## failure: if cancelled before terminal delivery on the main thread, the
## stream always emits `cancelled`.
func cancel() -> void:
	if _active != null:
		_active.cancel()


func is_busy() -> bool:
	return _active != null


## Runs on the worker thread. Only the token callback and the final
## _deliver_terminal touch the facade — both through call_deferred.
func _worker_main(stream: TurnStream, transport: LLMBackend) -> void:
	var result: Dictionary = transport.generate(
		stream.request,
		func(text: String) -> void: _deliver_token.call_deferred(stream, text),
		stream._cancel_token
	)
	var kind := &"failed"
	var payload: Variant = {
		"code": "malformed_result", "message": "backend returned an invalid result"
	}
	if stream._cancel_token.is_cancelled():
		kind = &"cancelled"
		payload = null
	elif result.get("ok", false) == true and result.get("text") is String:
		kind = &"completed"
		payload = result["text"]
	elif result.get("error") is Dictionary and result["error"].get("code") is String:
		var err_dict: Dictionary = result["error"]
		if not (err_dict.get("message") is String):
			err_dict = err_dict.duplicate()
			err_dict["message"] = ""
		payload = err_dict
	_deliver_terminal.call_deferred(stream, kind, payload)


func _deliver_token(stream: TurnStream, text: String) -> void:
	if stream != _active or stream.is_finished():
		return
	stream.token.emit(text)
	token.emit(text)


func _deliver_terminal(stream: TurnStream, kind: StringName, payload: Variant) -> void:
	if stream != _active or stream.is_finished():
		return
	if stream._cancel_token.is_cancelled():
		kind = &"cancelled"
		payload = null
	stream._mark_terminal(kind == &"cancelled")
	_active = null
	var done_thread := _thread
	_thread = null
	if done_thread != null:
		_pending_join.append(done_thread)
	match kind:
		&"completed":
			stream.completed.emit(payload)
		&"cancelled":
			stream.cancelled.emit()
		_:
			stream.failed.emit(payload)
	_reap_pending()


## Terminal signals are always delivered deferred, so a stream that can be
## failed synchronously (busy/no backend) behaves exactly like a real one:
## the caller always gets one frame to connect.
func _defer_failed(stream: TurnStream, code: String, message: String) -> void:
	var deliver := func() -> void:
		if stream.is_finished():
			return
		if stream._cancel_token.is_cancelled():
			stream._mark_terminal(true)
			stream.cancelled.emit()
			return
		stream._mark_terminal(false)
		stream.failed.emit({"code": code, "message": message})
	deliver.call_deferred()


## Join spent workers. wait_to_finish() runs only on threads is_alive()
## already reported dead, so the main thread never actually waits.
func _reap_pending() -> void:
	for t: Thread in _pending_join:
		if t.is_alive():
			_reap_pending.call_deferred()
			return
	for t: Thread in _pending_join:
		if t.is_started():
			t.wait_to_finish()
	_pending_join.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_shutdown()


func _exit_tree() -> void:
	_shutdown()


func _shutdown() -> void:
	if _shutdown_done:
		return
	_shutdown_done = true
	cancel()
	if _thread != null:
		if _thread.is_started():
			_thread.wait_to_finish()  # teardown: here blocking is correct
		_thread = null
	for t: Thread in _pending_join:
		if t.is_started():
			t.wait_to_finish()
	_pending_join.clear()
	# Only now is no worker alive to read the transport; stop a server we own.
	if _backend != null and _backend.has_method("shutdown"):
		_backend.shutdown()
