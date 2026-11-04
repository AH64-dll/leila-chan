class_name LlamaServerBackend
extends LLMBackend
## Prototype LLM transport: llama-server over HTTP with SSE streaming
## (docs/07 §3.1, docs/06 §4). One `generate()` runs on the facade's worker
## thread and blocks there by design; nothing here touches the main thread or
## a SceneTree API.
##
## Per request it sends the request's own JSON schema as `response_format`
## (never a schema baked into this backend), the request's sampling values,
## `max_tokens`, `enable_thinking=false` (docs/02 §9) and `stream=true`.
## Chunks are passed to `on_token` as raw JSON text, in order.
##
## Start/attach: `auto_start` launches the pinned server (with any configured
## control vectors) and waits for `/health`; otherwise the backend only talks
## to an already-running server. A server it started is supervised by an
## optional watchdog thread that restarts a dead process.
##
## Every wait is bounded: connect, idle read, whole turn, startup and stop all
## have timeouts, and all of them poll the cancel token. Metrics for each turn
## (time to first byte, first token, first usable `say`, full turn) are logged
## on one line and kept in `last_metrics()` for the transcript logger (P1.18)
## and the prompt lab (P1.20).

const SAMPLING_KEYS: Array[String] = [
	"temperature",
	"top_p",
	"top_k",
	"min_p",
	"repeat_penalty",
	"repeat_last_n",
	"seed",
	"presence_penalty",
	"frequency_penalty",
	"stop",
]
const DEFAULT_SAMPLING := {"temperature": 0.8, "top_p": 0.9, "repeat_penalty": 1.15}
const RETRYABLE_ERRORS: Array[String] = [
	"server_unreachable",
	"stream_truncated",
	"read_failed",
	"connect_timeout",
]
const WATCHDOG_SLEEP_SLICE_MS := 25
## AC budget for a stage-change relaunch (docs/06 §4): the 2–3 s transition glitch
## has to hide it, so a restart that misses this is a defect, not a slow turn.
const STEERING_BUDGET_MS := 3500
## `_acquire_turn_session()` answer when a shutdown cancelled the wait (a turn
## timeout reports -1 instead: "the turn outlasted the dose change").
const SESSION_CANCELLED := -2

var config := {}
var _process := LlamaServerProcess.new()
var _client := LlamaHttpClient.new()
var _metrics := {}
var _metrics_mutex := Mutex.new()
var _log_line := ""
var _last_error := {}
var _turn_active := false
var _turn_mutex := Mutex.new()
## Held by a turn for the whole streaming attempt and by a stage-change relaunch
## for its stop/start: the relaunch can never cut a line off (P2.03).
var _session := Mutex.new()
var _watchdog_thread: Thread
var _watchdog_mutex := Mutex.new()
var _watchdog_cancel := LLMCancelToken.new()
var _watchdog_interval_ms := 1000
var _watchdog_health_every := 5
var _restart_count := 0
var _last_restart_ms := -1
var _last_crash_unix := 0
var _shutdown := false
## Stage-change relaunch (docs/06 §4). One worker at a time, one caller outcome;
## `_steering_finished` holds spent threads so a stage change never has to wait on
## one (the main thread only joins threads a liveness check already called dead).
var _steering_thread: Thread
var _steering_finished: Array[Thread] = []
var _steering_mutex := Mutex.new()
var _steering_cancel := LLMCancelToken.new()
var _steering_busy := false
var _steering_info := {}
var _steering_count := 0
## Relaunches are serialised here so the watchdog cannot restart the server a
## stage change just brought up (and vice versa). `_relaunch_count` is the
## generation a caller checked before the lock; a changed value means the work is
## already done.
var _relaunch_mutex := Mutex.new()
var _relaunch_count := 0


func _init(initial_config: Dictionary = {}) -> void:
	configure(initial_config)


func configure(updates: Dictionary) -> void:
	config = LlamaServerProcess.default_config().merged(updates, true)
	_process.configure(config)


## LLMBackend.generate() — runs on the facade's worker thread.
## Returns {ok, text, metrics} or {ok: false, error: {code, message}, metrics}.
func generate(request: TurnRequest, on_token: Callable, cancel: LLMCancelToken) -> Dictionary:
	var started := Time.get_ticks_msec()
	var invalid := _validate_request(request)
	if not invalid.is_empty():
		var rejected := _finish_result(invalid, started)
		_record(rejected)
		return rejected
	_set_turn_active(true)
	# The turn session is shared with a stage-change relaunch: a restart holds it
	# too, so the server is never killed under a line that is being spoken (P2.03,
	# "no lost player input"). Lock order is always session -> relaunch -> process.
	# The wait observes the turn's own token, so a turn queued behind a relaunch
	# can be cancelled (and a quit joined) instead of blocking out the stop+start.
	if not _acquire_stream_session(cancel):
		_set_turn_active(false)
		var stopped := _finish_result(
			_error_attempt(
				"cancelled", "cancelled while a stage-change relaunch held the server", {}, 0
			),
			started
		)
		_record(stopped)
		return stopped
	var attempt := _attempt(request, on_token, cancel, started)
	if not attempt["ok"] and int(attempt["emitted"]) == 0:
		attempt = _maybe_retry(request, on_token, cancel, started, attempt)
	_session.unlock()
	_set_turn_active(false)
	var result := _finish_result(attempt, started)
	_record(result)
	return result


## Make a server available for the next turn. Worker-thread only (it blocks);
## exposed for tests and the prompt lab to pre-warm before the first request.
func ensure_server(cancel: LLMCancelToken = null) -> Dictionary:
	return _process.ensure_running(cancel)


## docs/06 §4: bind a new dose by relaunching the server with new control
## vectors. Never blocks — the stop/start runs on its own worker (measured 2.1–2.3 s
## on this machine) and the outcome arrives through `on_done.call_deferred(info)`
## on the main thread, so the caller can keep the old dose on failure.
##
## Returns false when nothing was started: a relaunch is already in flight (the
## caller should queue the latest dose and apply it after the delivery) or the
## server is not ours to restart. An attached server is refused by design — it may
## belong to another task, and relaunching would put a second server on a busy
## port (P1.02). That is also the one case where the game keeps the old dose for
## good: Boot installs attach mode unless `LEILA_OWN_SERVER` asks it to launch.
## `auto_start` alone is not proof of ownership (docs/06 §4.1): a server already
## answering on the port is adopted, and a relaunch is refused with
## `server_not_owned` instead of spawning a doomed replacement.
##
## `window_ms` is the transition glitch the restart should hide behind (0 = not
## hidden: a restore); `info.fits_window`/`info.within_budget` report both.
func apply_steering(vectors: Array, stage := 0, window_ms := 0, on_done := Callable()) -> bool:
	_reap_steering_threads()
	var auto_start := bool(config.get("auto_start", false))
	# Ownership, not the launch flag alone (docs/06 §4.1): `auto_start` *asks* for
	# a server the app launches, but `ensure_running()` adopts a healthy one that
	# already answers on the port (another task's `serve.sh`). `is_attached()` is
	# the cached probe result, so this stays cheap on the main thread; a backend
	# that has not probed yet is caught by `LlamaServerProcess`'s own re-check.
	if not auto_start or _process.is_attached():
		_steering_mutex.lock()
		if _steering_busy:
			_steering_mutex.unlock()
			return false
		var refused := _refused_info(
			stage,
			window_ms,
			vectors,
			(config.get("control_vectors", []) as Array).duplicate(true),
			"server_not_owned",
			_ownership_message(auto_start)
		)
		_steering_info = refused
		_steering_mutex.unlock()
		_log_steering(refused)
		_relay_steering(on_done, refused)
		return false
	_steering_mutex.lock()
	if _steering_busy or _shutdown:
		_steering_mutex.unlock()
		return false
	if _steering_thread != null:
		_steering_finished.append(_steering_thread)
		_steering_thread = null
	var previous: Array = (config.get("control_vectors", []) as Array).duplicate(true)
	var worker := Thread.new()
	_steering_thread = worker
	_steering_busy = true
	var err := worker.start(
		_steering_main.bind(vectors.duplicate(true), previous, stage, window_ms, on_done)
	)
	if err != OK:
		_steering_thread = null
		_steering_busy = false
		var failed := _refused_info(
			stage,
			window_ms,
			vectors,
			previous,
			"thread_error",
			"steering worker did not start (error %d)" % err
		)
		_steering_info = failed
		_steering_mutex.unlock()
		_log_steering(failed)
		_relay_steering(on_done, failed)
		return false
	_steering_mutex.unlock()
	return true


## The last stage-change relaunch outcome (see `_steering_info_base`), for the
## debug overlay, the prompt lab and tests. {} before the first one.
func last_steering_info() -> Dictionary:
	_steering_mutex.lock()
	var info := _steering_info.duplicate(true)
	_steering_mutex.unlock()
	return info


## Supervise the server we started. Every `interval_ms` the watchdog checks
## that the process is alive and (every fifth tick) still healthy; a dead
## process is restarted immediately. Attached servers are never restarted.
func start_watchdog(interval_ms := 1000) -> void:
	_watchdog_mutex.lock()
	if _watchdog_thread != null or _shutdown:
		_watchdog_mutex.unlock()
		return
	_watchdog_interval_ms = maxi(100, interval_ms)
	_watchdog_cancel = LLMCancelToken.new()
	_watchdog_thread = Thread.new()
	var err := _watchdog_thread.start(_watchdog_loop)
	if err != OK:
		_watchdog_thread = null
		push_error("LlamaServerBackend: watchdog thread failed to start (%d)" % err)
	_watchdog_mutex.unlock()


func stop_watchdog() -> void:
	_watchdog_mutex.lock()
	if _watchdog_thread == null:
		_watchdog_mutex.unlock()
		return
	_watchdog_cancel.cancel()
	# Join while holding the mutex so a concurrent start_watchdog() cannot
	# replace the cancel token under the old thread's feet.
	if _watchdog_thread.is_started():
		_watchdog_thread.wait_to_finish()
	_watchdog_thread = null
	_watchdog_mutex.unlock()


## Tear down everything this backend owns. Idempotent; call after the facade
## has joined the busy worker so no turn is reading the server socket.
func shutdown() -> void:
	_shutdown = true
	_steering_cancel.cancel()
	stop_watchdog()
	for thread: Thread in _steering_finished:
		if thread.is_started():
			thread.wait_to_finish()
	_steering_finished.clear()
	if _steering_thread != null and _steering_thread.is_started():
		_steering_thread.wait_to_finish()
		_steering_thread = null
	_process.stop()


func stop_server() -> void:
	_process.stop()


func is_watchdog_running() -> bool:
	_watchdog_mutex.lock()
	var running := _watchdog_thread != null
	_watchdog_mutex.unlock()
	return running


func server_pid() -> int:
	return _process.server_pid()


func is_server_running() -> bool:
	return _process.is_running()


func is_server_healthy() -> bool:
	return _process.is_healthy()


func owns_server() -> bool:
	return _process.owns_process()


func last_metrics() -> Dictionary:
	_metrics_mutex.lock()
	var metrics := _metrics.duplicate(true)
	_metrics_mutex.unlock()
	return metrics


func last_log_line() -> String:
	return _log_line


func last_error() -> Dictionary:
	return _last_error.duplicate(true)


func last_restart_ms() -> int:
	return _last_restart_ms


func restart_count() -> int:
	return _restart_count


func last_crash_unix() -> int:
	return _last_crash_unix


func _attempt(
	request: TurnRequest, on_token: Callable, cancel: LLMCancelToken, started: int
) -> Dictionary:
	var metrics := {"pid": _process.server_pid(), "restart_count": _restart_count}
	var ensure := _process.ensure_running(cancel)
	metrics["ready_ms"] = Time.get_ticks_msec() - started
	if cancel.is_cancelled():
		return _error_attempt("cancelled", "cancelled before the request", metrics, 0)
	if not ensure["ok"]:
		return _error_attempt(
			String(ensure["error"]["code"]), String(ensure["error"]["message"]), metrics, 0
		)
	metrics["pid"] = int(ensure.get("pid", 0))
	metrics["server_started"] = bool(ensure.get("started", false))
	metrics["server_startup_ms"] = int(ensure.get("startup_ms", 0))
	if _process.owns_process() and bool(config.get("watchdog", true)):
		# Supervise our own process: a crash between turns must be detected
		# and healed without waiting for the next request. Idempotent.
		start_watchdog(int(config.get("watchdog_interval_ms", 1000)))
	# TTFT and first `say` share one clock: the POST, not the generate call,
	# because a first turn may also pay for a cold server start. Startup is
	# reported separately as ready_ms/server_startup_ms.
	var request_started := Time.get_ticks_msec()
	var emitted := [0]
	var first_say_ms := [-1]
	var probe := FirstSayProbe.new()
	var forward := func(text: String) -> void:
		emitted[0] += 1
		if first_say_ms[0] < 0 and probe.feed(text):
			first_say_ms[0] = Time.get_ticks_msec() - request_started
		on_token.call(text)
	var body := _build_body(request)
	var options := {
		"connect_timeout_ms": int(config.get("connect_timeout_ms", 2000)),
		"read_timeout_ms": int(config.get("read_timeout_ms", 60000)),
		"turn_timeout_ms": int(config.get("turn_timeout_ms", 180000)),
		"capture_path": String(config.get("capture_path", "")),
	}
	var response := _client.post_stream(_chat_url(), body, forward, cancel, options)
	metrics.merge(response.get("metrics", {}), true)
	metrics["first_say_ms"] = int(first_say_ms[0])
	metrics["generate_ms"] = Time.get_ticks_msec() - started
	metrics["capture_error"] = String(response.get("capture_error", ""))
	if response["ok"]:
		return {
			"ok": true,
			"text": String(response["text"]),
			"metrics": metrics,
			"emitted": int(emitted[0]),
			"error": {},
		}
	var error: Dictionary = response.get("error", {})
	var code := String(error.get("code", "transport_error"))
	var message := String(error.get("message", "llama-server request failed"))
	return _error_attempt(code, message, metrics, int(emitted[0]))


func _maybe_retry(
	request: TurnRequest,
	on_token: Callable,
	cancel: LLMCancelToken,
	started: int,
	attempt: Dictionary
) -> Dictionary:
	var code := String(attempt["error"].get("code", ""))
	if not RETRYABLE_ERRORS.has(code) or not bool(config.get("retry_once", true)):
		return attempt
	if cancel.is_cancelled():
		return attempt
	if bool(config.get("auto_start", false)):
		# Serialised with a stage change: if one finished while this turn failed,
		# the fresh server already runs the current config and needs no restart.
		var restart := _serialized_restart(cancel, _relaunch_count)
		if not restart["ok"]:
			return attempt
	var retried := _attempt(request, on_token, cancel, started)
	retried["metrics"]["retried"] = true
	retried["metrics"]["retry_reason"] = code
	return retried


func _validate_request(request: TurnRequest) -> Dictionary:
	if request == null:
		return _error_attempt("invalid_request", "generate() needs a TurnRequest", {}, 0)
	if request.messages.is_empty():
		return _error_attempt("invalid_request", "TurnRequest.messages must not be empty", {}, 0)
	if request.schema.is_empty():
		return _error_attempt(
			"invalid_request",
			"TurnRequest.schema is empty; refusing to stream an unconstrained turn",
			{},
			0
		)
	return {}


## llama-server's OpenAI-compatible endpoint. `base_url` is the server root;
## a full endpoint URL is accepted as-is for prompt-lab-style configs.
func _chat_url() -> String:
	var base := String(config["base_url"]).trim_suffix("/")
	if base.ends_with("/v1/chat/completions"):
		return base
	return base + String(config.get("chat_path", "/v1/chat/completions"))


func _build_body(request: TurnRequest) -> Dictionary:
	var sampling := DEFAULT_SAMPLING.duplicate()
	for key: String in SAMPLING_KEYS:
		if request.sampling.has(key):
			sampling[key] = request.sampling[key]
	var body := {
		"messages": request.messages,
		"stream": true,
		"max_tokens": request.max_tokens,
		"response_format":
		{
			"type": "json_schema",
			"json_schema": {"name": "turn", "schema": request.schema},
		},
		"chat_template_kwargs": {"enable_thinking": false},
		"cache_prompt": bool(config.get("cache_prompt", true)),
	}
	body.merge(sampling)
	return body


func _finish_result(attempt: Dictionary, started: int) -> Dictionary:
	var result_metrics: Dictionary = attempt.get("metrics", {}).duplicate(true)
	result_metrics["generate_ms"] = Time.get_ticks_msec() - started
	if attempt.get("ok", false):
		return {"ok": true, "text": attempt.get("text", ""), "metrics": result_metrics}
	var error: Dictionary = attempt.get("error", {})
	if error.is_empty():
		error = {"code": "transport_error", "message": "llama-server turn failed"}
	return {"ok": false, "error": error, "metrics": result_metrics, "text": ""}


func _error_attempt(code: String, message: String, metrics: Dictionary, emitted: int) -> Dictionary:
	return {
		"ok": false,
		"error": {"code": code, "message": message},
		"metrics": metrics,
		"emitted": emitted,
		"text": "",
	}


func _record(result: Dictionary) -> void:
	_metrics_mutex.lock()
	_metrics = result.get("metrics", {}).duplicate(true)
	_metrics_mutex.unlock()
	var metrics: Dictionary = result.get("metrics", {})
	var ttft := int(metrics.get("first_token_ms", -1))
	var first_say := int(metrics.get("first_say_ms", -1))
	var status := "ok" if result["ok"] else "failed code=" + String(result["error"]["code"])
	_log_line = (
		(
			"[LlamaServerBackend] turn %s ttft=%s first_say=%s total=%dms "
			+ "ready=%dms chunks=%d pid=%d restarts=%d"
		)
		% [
			status,
			_ms_text(ttft),
			_ms_text(first_say),
			int(metrics.get("total_ms", 0)),
			int(metrics.get("ready_ms", 0)),
			int(metrics.get("chunks", 0)),
			int(metrics.get("pid", 0)),
			_restart_count,
		]
	)
	_last_error = {} if result["ok"] else result["error"].duplicate()
	print(_log_line)


func _ms_text(value: int) -> String:
	return "n/a" if value < 0 else "%dms" % value


func _set_turn_active(active: bool) -> void:
	_turn_mutex.lock()
	_turn_active = active
	_turn_mutex.unlock()


func _is_turn_active() -> bool:
	_turn_mutex.lock()
	var active := _turn_active
	_turn_mutex.unlock()
	return active


## Worker-thread body of a stage-change relaunch. Waits for an in-flight turn to
## finish (never kill a line being spoken), relaunches, then reports exactly one
## info map — through `on_done` on the main thread, which is the only place the
## dose bookkeeping is allowed to move.
func _steering_main(
	vectors: Array, previous: Array, stage: int, window_ms: int, on_done: Callable
) -> void:
	var started := Time.get_ticks_msec()
	var deferred_ms := _acquire_turn_session()
	var result := {}
	if deferred_ms == SESSION_CANCELLED:
		result = {"ok": false, "kept_previous": true, "recovered": true, "restart_ms": 0}
		result["error"] = {"code": "cancelled", "message": "cancelled by shutdown"}
	elif deferred_ms < 0:
		result = {"ok": false, "kept_previous": true, "recovered": true, "restart_ms": 0}
		result["error"] = {
			"code": "turn_in_progress",
			"message":
			(
				(
					"a turn was still streaming after %dms; a relaunch would cut off the "
					+ "player's line, so the old dose stays"
				)
				% int(config.get("steering_turn_wait_ms", 15000))
			),
		}
	else:
		result = _serialized_steering(vectors, previous, _steering_cancel)
		_release_turn_session()
	var info := _steering_info_base(
		stage,
		window_ms,
		vectors,
		previous,
		maxi(deferred_ms, 0),
		Time.get_ticks_msec() - started,
		result
	)
	_steering_mutex.lock()
	_steering_busy = false
	if bool(info["ok"]):
		_steering_count += 1
		info["restarts"] = _steering_count
	_steering_info = info
	_steering_mutex.unlock()
	_log_steering(info)
	_relay_steering(on_done, info)


## Wait for the streaming session, observing the turn's own cancel token. A turn
## can queue behind a stage-change relaunch, which holds the session for its whole
## stop/start; cancelling that turn — or shutting the app down — must not wait the
## relaunch out (CODE-4, docs/05 §0 "closing always works"). The relaunch's own
## wait is `_acquire_turn_session`, bounded by `steering_turn_wait_ms` instead.
func _acquire_stream_session(cancel: LLMCancelToken) -> bool:
	while not _session.try_lock():
		if cancel != null and cancel.is_cancelled():
			return false
		OS.delay_msec(WATCHDOG_SLEEP_SLICE_MS)
	return true


## docs/06 §4 + "no lost player input": hold the same session a turn holds while
## it streams, so the server can never be killed under a line that is being read.
## A crossing normally lands at turn close and costs milliseconds; a trigger that
## fires mid-turn waits for the line to finish. Returns the wait, -1 when the turn
## outlasted `steering_turn_wait_ms` (old dose stays, the next crossing retries),
## or SESSION_CANCELLED for a shutdown.
func _acquire_turn_session() -> int:
	var started := Time.get_ticks_msec()
	var budget := int(config.get("steering_turn_wait_ms", 15000))
	while not _session.try_lock():
		if _steering_cancel.is_cancelled() or _shutdown:
			return SESSION_CANCELLED
		if Time.get_ticks_msec() - started >= budget:
			return -1
		OS.delay_msec(WATCHDOG_SLEEP_SLICE_MS)
	return Time.get_ticks_msec() - started


func _release_turn_session() -> void:
	_session.unlock()


## The relaunch with new vectors, serialised against every other relaunch.
## `_process` keeps its own merged copy of the config, so both are updated: the
## launcher reads the process copy, while `get_backend_config()` — and through it
## the docs/02 §8 classifier gate (SAF-12) — reads the backend's.
func _serialized_steering(vectors: Array, previous: Array, cancel: LLMCancelToken) -> Dictionary:
	_relaunch_mutex.lock()
	config["control_vectors"] = vectors.duplicate(true)
	var result := _process.restart_with_vectors(vectors, previous, cancel)
	if bool(result.get("kept_previous", false)):
		config["control_vectors"] = previous.duplicate(true)
	_relaunch_count += 1
	_relaunch_mutex.unlock()
	return result


## A plain relaunch (watchdog, docs/02 §7 retry), serialised against a stage
## change. `generation` is the counter the caller read before asking; a different
## value means another relaunch finished while this caller waited, so the server
## already runs the current config and restarting it again would kill the process
## the stage change just brought up.
func _serialized_restart(cancel: LLMCancelToken, generation: int) -> Dictionary:
	_relaunch_mutex.lock()
	if generation >= 0 and generation != _relaunch_count:
		var running := _process.is_running()
		var pid := _process.server_pid()
		_relaunch_mutex.unlock()
		return {"ok": running, "skipped": true, "pid": pid, "error": {}, "restart_ms": 0}
	var result := _process.restart(cancel)
	_relaunch_count += 1
	_relaunch_mutex.unlock()
	return result


## The info a stage-change relaunch reports (and `last_steering_info()` keeps):
## the AC numbers (`ms` = stop→healthy, `within_budget` = the 3.5 s window), the
## glitch fit, and what happened to the dose when it failed.
func _steering_info_base(
	stage: int,
	window_ms: int,
	vectors: Array,
	previous: Array,
	deferred_ms: int,
	total_ms: int,
	result: Dictionary
) -> Dictionary:
	var elapsed := int(result.get("restart_ms", 0))
	var error: Variant = result.get("error", {})
	return {
		"ok": bool(result.get("ok", false)),
		"stage": stage,
		"ms": elapsed,
		"total_ms": total_ms,
		"deferred_ms": deferred_ms,
		"window_ms": window_ms,
		"budget_ms": STEERING_BUDGET_MS,
		"within_budget": elapsed <= STEERING_BUDGET_MS,
		"fits_window": window_ms <= 0 or elapsed <= window_ms,
		"vectors": vectors.duplicate(true),
		"previous_vectors": previous.duplicate(true),
		"kept_previous": bool(result.get("kept_previous", false)),
		"recovered": bool(result.get("recovered", false)),
		"pid": int(result.get("pid", 0)),
		"restarts": _steering_count,
		"error": (error as Dictionary).duplicate(true) if error is Dictionary else {},
	}


## Why a relaunch is refused for ownership (docs/06 §4.1): either the transport
## only attaches (no launch mode), or `auto_start` was asked for but the server
## answering is one the app adopted instead of launching.
func _ownership_message(auto_start: bool) -> String:
	var url := String(config.get("base_url", ""))
	if auto_start:
		return (
			(
				"a server is already answering on %s and this app did not launch it; "
				+ "only a server the app launched can be rebound"
			)
			% url
		)
	return (
		(
			"the dose is a launch flag and this transport only attached to %s; "
			+ "start llama-server from the app (auto_start) to rebind it"
		)
		% url
	)


## The info for a relaunch that never started (attached server, thread failure).
## Nothing was stopped, so the old dose is still in effect and `recovered` is
## true: the caller keeps the dose it has and the server keeps serving it.
func _refused_info(
	stage: int, window_ms: int, vectors: Array, previous: Array, code: String, message: String
) -> Dictionary:
	var info := _steering_info_base(stage, window_ms, vectors, previous, 0, 0, {})
	info["kept_previous"] = true
	info["recovered"] = true
	info["error"] = {"code": code, "message": message}
	return info


## The worker never touches the facade or a signal: the caller's handler runs on
## the main thread, one frame later (the same rule every transport result follows).
func _relay_steering(on_done: Callable, info: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call_deferred(info)


## One line per relaunch: the measurement the AC is read from, plus what the dose
## did when it failed ("keep old dose + log" is this line, not silence).
func _log_steering(info: Dictionary) -> void:
	var stage := int(info["stage"])
	var elapsed := int(info["ms"])
	var window := int(info["window_ms"])
	if not bool(info["ok"]):
		var error: Dictionary = info.get("error", {})
		print(
			(
				(
					"[LlamaServerBackend] steering stage %d FAILED after %dms: %s (%s); "
					+ "kept the previous dose (%d vector(s), server recovered=%s)"
				)
				% [
					stage,
					elapsed,
					String(error.get("code", "unknown")),
					String(error.get("message", "")),
					(info["previous_vectors"] as Array).size(),
					"yes" if bool(info["recovered"]) else "no",
				]
			)
		)
		return
	var window_text := "window n/a"
	if window > 0:
		window_text = (
			("within window %dms" if bool(info["fits_window"]) else "OVER window %dms") % window
		)
	var waited := int(info["deferred_ms"])
	print(
		(
			(
				"[LlamaServerBackend] steering stage %d bound %s in %dms (%s, budget %dms) "
				+ "pid=%d%s"
			)
			% [
				stage,
				StageSteering.describe(info["vectors"]),
				elapsed,
				window_text,
				STEERING_BUDGET_MS,
				int(info["pid"]),
				(" after waiting %dms for the turn" % waited) if waited > 0 else "",
			]
		)
	)


## Main-thread only. Spent workers are joined only once `is_alive()` already said
## they were dead, so a stage change never waits on a thread (same rule as the
## facade's `_reap_pending`).
func _reap_steering_threads() -> void:
	if _steering_finished.is_empty():
		return
	for thread: Thread in _steering_finished:
		if thread.is_alive():
			return
	for thread: Thread in _steering_finished:
		if thread.is_started():
			thread.wait_to_finish()
	_steering_finished.clear()


func _watchdog_loop() -> void:
	var ticks := 0
	while not _watchdog_cancel.is_cancelled():
		_sleep_interruptible(_watchdog_interval_ms)
		if _watchdog_cancel.is_cancelled():
			break
		if _is_turn_active() or not _process.is_supervised():
			continue
		var generation := _relaunch_count
		if not _process.is_running():
			_watchdog_restart("process exited", generation)
			continue
		ticks += 1
		if _watchdog_health_every > 0 and ticks % _watchdog_health_every == 0:
			if not _process.is_healthy(500):
				_watchdog_restart("health probe failed", generation)


func _watchdog_restart(reason: String, generation := -1) -> void:
	var started := Time.get_ticks_msec()
	var result := _serialized_restart(_watchdog_cancel, generation)
	if _watchdog_cancel.is_cancelled():
		return
	if bool(result.get("skipped", false)):
		# A stage change relaunched the server while this probe was in flight; the
		# fresh process already carries the current config.
		return
	var elapsed := int(result.get("restart_ms", Time.get_ticks_msec() - started))
	if not result["ok"]:
		print(
			(
				"[LlamaServerBackend] server restart failed after %s: %s"
				% [reason, String(result["error"]["message"])]
			)
		)
		return
	_restart_count += 1
	_last_restart_ms = elapsed
	_last_crash_unix = int(Time.get_unix_time_from_system())
	print(
		(
			"[LlamaServerBackend] server restarted after %s: pid=%d in %dms"
			% [reason, _process.server_pid(), elapsed]
		)
	)


func _sleep_interruptible(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if _watchdog_cancel.is_cancelled():
			return
		OS.delay_msec(mini(WATCHDOG_SLEEP_SLICE_MS, deadline - Time.get_ticks_msec()))


## Streams the raw JSON text and reports the moment the first non-empty
## `say` value character arrives. TTFT alone is not the "first beat on
## screen" metric (P0 gate C8): music/fx and the beat fields arrive before
## the line she speaks. This is a transport-level probe; P1.03's
## IncrementalJson becomes the authority once it lands.
class FirstSayProbe:
	var found := false
	var _in_string := false
	var _escape := false
	var _buf := ""
	var _last_string := ""
	var _pending_key := ""
	var _expect_value := false
	var _in_say := false
	var _say_escape := false
	var _say_chars := 0

	func feed(text: String) -> bool:
		if found:
			return false
		var hit := false
		for i: int in text.length():
			var c := text[i]
			if _in_say:
				if _say_escape:
					_say_escape = false
					_say_chars += 1
					found = true
					hit = true
				elif c == "\\":
					_say_escape = true
				elif c == '"':
					_in_say = false
					if _say_chars == 0:
						_pending_key = ""
				else:
					_say_chars += 1
					found = true
					hit = true
				if found:
					return hit
				continue
			if _in_string:
				if _escape:
					_escape = false
					_buf += c
				elif c == "\\":
					_escape = true
				elif c == '"':
					_in_string = false
					if _expect_value:
						_expect_value = false
						_pending_key = ""
					else:
						_last_string = _buf
				else:
					_buf += c
				continue
			if _expect_value:
				if c == " " or c == "\t" or c == "\n" or c == "\r":
					continue
				if c == '"':
					_expect_value = false
					if _pending_key == "say":
						_in_say = true
						_say_chars = 0
					else:
						_in_string = true
						_buf = ""
					continue
				_expect_value = false
				_pending_key = ""
			if c == '"':
				_in_string = true
				_buf = ""
			elif c == ":":
				_expect_value = true
				_pending_key = _last_string
			elif c == "," or c == "}" or c == "]" or c == "{":
				_last_string = ""
				_pending_key = ""
		return hit
