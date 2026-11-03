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

var config := {}
var _process := LlamaServerProcess.new()
var _client := LlamaHttpClient.new()
var _metrics := {}
var _metrics_mutex := Mutex.new()
var _log_line := ""
var _last_error := {}
var _turn_active := false
var _turn_mutex := Mutex.new()
var _watchdog_thread: Thread
var _watchdog_mutex := Mutex.new()
var _watchdog_cancel := LLMCancelToken.new()
var _watchdog_interval_ms := 1000
var _watchdog_health_every := 5
var _restart_count := 0
var _last_restart_ms := -1
var _last_crash_unix := 0
var _shutdown := false


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
	var attempt := _attempt(request, on_token, cancel, started)
	if not attempt["ok"] and int(attempt["emitted"]) == 0:
		attempt = _maybe_retry(request, on_token, cancel, started, attempt)
	_set_turn_active(false)
	var result := _finish_result(attempt, started)
	_record(result)
	return result


## Make a server available for the next turn. Worker-thread only (it blocks);
## exposed for tests and the prompt lab to pre-warm before the first request.
func ensure_server(cancel: LLMCancelToken = null) -> Dictionary:
	return _process.ensure_running(cancel)


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
	stop_watchdog()
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
		var restart := _process.restart(cancel)
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


func _watchdog_loop() -> void:
	var ticks := 0
	while not _watchdog_cancel.is_cancelled():
		_sleep_interruptible(_watchdog_interval_ms)
		if _watchdog_cancel.is_cancelled():
			break
		if _is_turn_active() or not _process.is_supervised():
			continue
		if not _process.is_running():
			_watchdog_restart("process exited")
			continue
		ticks += 1
		if _watchdog_health_every > 0 and ticks % _watchdog_health_every == 0:
			if not _process.is_healthy(500):
				_watchdog_restart("health probe failed")


func _watchdog_restart(reason: String) -> void:
	var started := Time.get_ticks_msec()
	var result := _process.restart(_watchdog_cancel)
	if _watchdog_cancel.is_cancelled():
		return
	var elapsed := Time.get_ticks_msec() - started
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
