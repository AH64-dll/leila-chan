extends Node
## LLM — backend facade (docs/07 §3.1). The Director hands it one TurnRequest
## per turn; the injected LLMBackend runs it on a worker thread. Every emission
## reaches the main thread via call_deferred and nothing here ever blocks the
## main thread: the worker does all waiting, and finished threads are joined
## only once is_alive() reports them dead.

signal token(text: String)  ## Raw stream: each chunk of the in-flight turn.
## docs/06 §4: one stage-change relaunch finished (either way). `info` is the
## backend's outcome map plus the requested `dose`; see `apply_stage_steering`.
signal steering_applied(info: Dictionary)

var _backend: LLMBackend  ## Injected transport; null until set_backend() (P1.02 wires the default).
var _dose := {}  ## Current control-vector dose {name: scale} from set_dose().
var _dose_mutex := Mutex.new()
var _active: TurnStream  ## The in-flight turn, or null. One turn at a time.
var _thread: Thread  ## Worker thread running the backend, or null.
var _pending_join: Array[Thread] = []  ## Spent workers awaiting a non-blocking join.
var _shutdown_done := false
## Stage-change relaunch state (docs/06 §4). `_steering_vectors` is what the
## running server actually carries — not what the schedule asks for — so a failed
## relaunch leaves it (and `_dose`) alone.
var _steering: StageSteering
var _steering_stage := -1
var _steering_vectors: Array = []
## Dose keys the last started relaunch deliberately did not bind (docs/06 §2
## `unbound`), reported with the outcome and logged once per successful bind.
var _steering_unbound: Array = []
var _steering_in_flight := false
var _steering_pending := {}
var _last_steering_info := {}


func _ready() -> void:
	_ensure_steering()
	_connect_stage_signals()


## Inject the transport backend. Call on the main thread; takes effect on the
## next generate() — an in-flight turn keeps the backend it started with.
func set_backend(new_backend: LLMBackend) -> void:
	_backend = new_backend
	# docs/05 M39 spike: live only on the native backend (the server's dose is a launch flag).
	var steering := get_node_or_null("/root/Steering")
	var native := new_backend != null and new_backend.has_method("is_native")
	if steering != null and steering.has_method("set_spikes_live"):
		steering.set_spikes_live(native and bool(new_backend.call("is_native")))


func has_backend() -> bool:
	return _backend != null


func get_backend() -> LLMBackend:
	return _backend


## The installed backend's launch configuration, when it publishes one (the
## prototype llama-server transport does). Boot reads it to keep the safety
## classifier off a server that carries control vectors (SAF-3/SAF-12); an empty
## dictionary means "no configuration known", which is not the same as dose 0.
## `server_owned` is added live: `auto_start` only *asks* for an app-launched
## server, while `ensure_running()` adopts a healthy one already on the port, and
## the docs/02 §8 classifier must not ask a server whose launch flags the app
## cannot see (docs/06 §4.1).
func get_backend_config() -> Dictionary:
	if _backend == null:
		return {}
	var raw: Variant = _backend.get("config")
	if not raw is Dictionary:
		return {}
	var config: Dictionary = (raw as Dictionary).duplicate(true)
	if _backend.has_method("owns_server"):
		config["server_owned"] = bool(_backend.call("owns_server"))
	return config


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


## docs/06 §4: bind the stage's dose by relaunching the prototype server with the
## shipped control vectors, hidden behind the transition glitch. Never blocks.
## `window_ms` is the glitch window the restart should fit (0 = not hidden: a
## restore or a New Game). On success the dose map and the bound vectors move
## together; on failure both stay where they were and the failure is logged,
## because the running server still carries the old dose — the game keeps playing
## at the dose it has instead of talking to a dead port. Returns false when
## nothing was started: nothing to change, no capable transport, or a relaunch is
## already in flight (then the newest dose is queued and applied after it).
func apply_stage_steering(stage: int, window_ms := 0) -> bool:
	_ensure_steering()
	var dose := _dose_for_stage(stage)
	if dose.is_empty():
		return _fail_steering(
			stage,
			window_ms,
			dose,
			"steering_table_missing",
			"Steering.dose_for() returned no scales; keeping the old dose"
		)
	var launch := _steering.launch_for(dose)
	if not bool(launch.get("ok", false)):
		var failure: Dictionary = launch.get("error", {})
		return _fail_steering(
			stage,
			window_ms,
			dose,
			String(failure.get("code", "control_vector_invalid")),
			String(failure.get("message", ""))
		)
	var vectors: Array = launch["vectors"]
	if _same_vectors(vectors, _steering_vectors):
		# Already bound: no relaunch, and no glitch to hide.
		_steering_stage = stage
		set_dose(dose)
		return true
	if _backend == null or not _backend.has_method("apply_steering"):
		return _fail_steering(
			stage,
			window_ms,
			dose,
			"steering_unsupported",
			"the installed transport cannot rebind control vectors"
		)
	if _steering_in_flight:
		# Latest wins: the running relaunch may bind an older stage, so the newest
		# dose is queued and applied the moment that outcome arrives.
		_steering_pending = {"stage": stage, "window_ms": window_ms}
		return true
	_steering_unbound = (launch.get("unbound", []) as Array).duplicate()
	var started: bool = _backend.apply_steering(
		vectors, stage, window_ms, Callable(self, "_on_steering_done")
	)
	if started:
		_steering_in_flight = true
		_steering_pending = {}
	return started


## The last stage-change outcome (the backend's map plus the requested `dose`);
## {} before the first one. Dev tooling reads the *bound* dose here, while
## `Steering.describe()` still shows what the schedule asks for.
func last_steering_info() -> Dictionary:
	return _last_steering_info.duplicate(true)


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


func _ensure_steering() -> void:
	if _steering != null:
		return
	_steering = StageSteering.new()
	_steering.load_map()


## docs/06 §4: the stage machine is the trigger. Only the autoload listens — a
## test that instantiates an extra facade must not also relaunch the server.
## `state_reset` is the non-glitch path: New Game (stage 0 → unsteered) and a save
## restore (the bound dose must match the restored stage without a transition).
func _connect_stage_signals() -> void:
	var tree := get_tree()
	if tree == null or tree.root.get_node_or_null("LLM") != self:
		return
	var state := tree.root.get_node_or_null("GameState")
	if state == null:
		return
	if not state.is_connected(&"stage_transition", _on_stage_transition):
		state.connect(&"stage_transition", _on_stage_transition)
	if not state.is_connected(&"state_reset", _on_state_reset):
		state.connect(&"state_reset", _on_state_reset)


## A crossing: the transition's own duration is the window the relaunch hides in
## (docs/01 §3, docs/06 §4), so the restart starts on the same frame the glitch
## does and the measurement is compared against exactly that window.
func _on_stage_transition(_previous: int, current: int, spec: Dictionary) -> void:
	var duration := float(spec.get("duration_s", 0.0))
	apply_stage_steering(current, int(round(duration * 1000.0)))


func _on_state_reset() -> void:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	apply_stage_steering(int(state.get("stage")), 0)


## The docs/06 §3 dose for a stage, from the schedule owner — never a copy. The
## ctx carries the stage and GameState's assigned path (P3.04 binds the path's
## vector, not the interim `path_mix` weight, once a path exists), so the
## calmer-mode cap (docs/02 §8) applies at binding time: a calmer stage-5 turn
## must bind the stage-3 scales.
func _dose_for_stage(stage: int) -> Dictionary:
	var steering := get_node_or_null("/root/Steering")
	if steering == null or not steering.has_method("dose_for"):
		return {}
	var game_state := get_node_or_null("/root/GameState")
	var path := ""
	if game_state != null:
		path = String(game_state.get("path"))
	return steering.dose_for({"stage": stage, "path": path})


## Main thread. The relaunch either bound the new dose or kept the old one; in
## both cases the dose map must keep describing the server that is running, and
## a dose that arrived mid-relaunch is applied next.
func _on_steering_done(info: Dictionary) -> void:
	_steering_in_flight = false
	var stage := int(info.get("stage", _steering_stage))
	var dose := _dose_for_stage(stage)
	var report := info.duplicate(true)
	report["dose"] = dose
	report["unbound"] = _steering_unbound.duplicate()
	if bool(report.get("ok", false)):
		_steering_stage = stage
		_steering_vectors = (report.get("vectors", []) as Array).duplicate(true)
		set_dose(dose)
		print(
			(
				"[LLM] steering stage %d bound (%s) in %dms%s"
				% [
					stage,
					_describe_dose(dose),
					int(report.get("ms", 0)),
					_unbound_note(report["unbound"]),
				]
			)
		)
	else:
		var error: Dictionary = report.get("error", {})
		print(
			(
				"[LLM] steering stage %d not applied (%s: %s) — keeping the old dose %s"
				% [
					stage,
					String(error.get("code", "unknown")),
					String(error.get("message", "")),
					_describe_dose(get_dose()),
				]
			)
		)
	_last_steering_info = report
	steering_applied.emit(report)
	if _steering_pending.is_empty():
		return
	var next: Dictionary = _steering_pending
	_steering_pending = {}
	print(
		(
			("[LLM] steering stage %d arrived while stage %d was relaunching; " + "binding it now")
			% [int(next["stage"]), stage]
		)
	)
	apply_stage_steering(int(next["stage"]), int(next["window_ms"]))


## Refuse before touching the server (no vector file, no dose table, no capable
## transport) — the old dose stays, and the refusal is logged and reported.
func _fail_steering(
	stage: int, window_ms: int, dose: Dictionary, code: String, message: String
) -> bool:
	var report := {
		"ok": false,
		"stage": stage,
		"ms": 0,
		"total_ms": 0,
		"deferred_ms": 0,
		"window_ms": window_ms,
		"budget_ms": LlamaServerBackend.STEERING_BUDGET_MS,
		"within_budget": true,
		"fits_window": true,
		"vectors": [],
		"previous_vectors": _steering_vectors.duplicate(true),
		"kept_previous": true,
		"recovered": _server_running(),
		"error": {"code": code, "message": message},
		"dose": dose.duplicate(true),
	}
	_last_steering_info = report
	print(
		(
			"[LLM] steering stage %d not applied (%s: %s) — keeping the old dose %s"
			% [stage, code, message, _describe_dose(get_dose())]
		)
	)
	steering_applied.emit(report)
	return false


func _server_running() -> bool:
	if _backend == null or not _backend.has_method("is_server_running"):
		return false
	return bool(_backend.is_server_running())


## Same order and same pairs: the launcher payload is rebuilt on every crossing,
## so only the resolved file and the scale decide "already bound".
func _same_vectors(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index: int in left.size():
		var a: Variant = left[index]
		var b: Variant = right[index]
		if not (a is Dictionary and b is Dictionary):
			return false
		var first: Dictionary = a
		var second: Dictionary = b
		if String(first.get("path", "")) != String(second.get("path", "")):
			return false
		var scale_a := float(first.get("scale", 0.0))
		var scale_b := float(second.get("scale", 0.0))
		if not is_equal_approx(scale_a, scale_b):
			return false
	return true


func _describe_dose(dose: Dictionary) -> String:
	var steering := get_node_or_null("/root/Steering")
	if steering != null and steering.has_method("describe"):
		return String(steering.describe(dose))
	return "none" if dose.is_empty() else str(dose)


## One log clause for the doses that were scheduled but deliberately bound no
## file (docs/06 §3 `path_mix`, the pre-assignment interim weight). Empty when
## every positive key bound.
func _unbound_note(keys: Variant) -> String:
	if not keys is Array or (keys as Array).is_empty():
		return ""
	var names := PackedStringArray()
	for key: Variant in keys:
		names.append(String(key))
	return "; unbound (no file yet): " + ", ".join(names)


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
