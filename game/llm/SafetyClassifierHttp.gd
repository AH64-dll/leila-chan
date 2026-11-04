class_name SafetyClassifierHttp
extends SafetyClassifierBackend
## Prototype classifier transport (docs/02 §8): one non-streaming-in-spirit
## chat completion against the SAME local model, max_tokens 8, temperature 0,
## no control vectors bound to the request.
##
## Dose 0: `request.dose` is never sent. llama-server applies control vectors
## as a *launch* flag in the prototype (LlamaServerProcess._build_args /
## docs/06 §4), not per request, so a steered server would steer this request
## too — and a "no" verdict *releases* a held span, so a steered answer is a
## safety-policy problem, not just an accuracy one. `Boot` therefore refuses to
## attach this transport to a shared server that carries vectors and leaves the
## tier uninstalled (flagged spans fail closed); `LEILA_CLASSIFIER_URL` points at
## a dedicated unsteered server.
##
## Threading: classify() runs the HTTP call on a worker thread and calls
## `done` there; Safety defers the verdict to the main thread. The main thread
## never blocks. Spent threads are reaped on the next classify()/shutdown().
##
## Timeouts are bounded (connect_timeout_ms / read_timeout_ms) and the whole
## call is cancellable, so a hung server can never pin a thread forever.

const DEFAULT_CONNECT_TIMEOUT_MS := 300
## Generous: the answer is only needed to warm the cache / release a hold; a
## CPU host can take seconds for the 8-token decode, and the worker thread is
## cancelled at shutdown. The gate's hold_timeout_ms bounds the UI separately.
const DEFAULT_READ_TIMEOUT_MS := 10000
const DEFAULT_CHAT_PATH := "/v1/chat/completions"

var base_url := "http://127.0.0.1:8089"
var chat_path := DEFAULT_CHAT_PATH
var connect_timeout_ms := DEFAULT_CONNECT_TIMEOUT_MS
var read_timeout_ms := DEFAULT_READ_TIMEOUT_MS
var capture_path := ""

var _client := LlamaHttpClient.new()
## One entry per in-flight call: {thread, cancel}. Reaped on the next
## classify()/shutdown(); shutdown cancels every token, not just the newest
## (CODE-5) — a whole-text scan can legitimately have several.
var _workers: Array[Dictionary] = []
var _shutdown := false


func _init(initial: Dictionary = {}) -> void:
	configure(initial)


func configure(updates: Dictionary) -> void:
	if updates.has("base_url"):
		base_url = String(updates["base_url"]).trim_suffix("/")
	if updates.has("chat_path"):
		chat_path = String(updates["chat_path"])
	if updates.has("connect_timeout_ms"):
		connect_timeout_ms = maxi(1, int(updates["connect_timeout_ms"]))
	if updates.has("read_timeout_ms"):
		read_timeout_ms = maxi(1, int(updates["read_timeout_ms"]))
	if updates.has("capture_path"):
		capture_path = String(updates["capture_path"])


func url() -> String:
	return base_url + chat_path


## SafetyClassifierBackend.classify() — worker thread, `done` is called once.
func classify(request: Dictionary, done: Callable) -> void:
	if _shutdown:
		done.call(_error_result("shutdown", "classifier transport is shut down"))
		return
	_reap()
	var cancel := LLMCancelToken.new()
	var thread := Thread.new()
	var err := thread.start(_run.bind(request, done, cancel))
	if err != OK:
		done.call(_error_result("thread_error", "could not start classifier thread"))
		return
	_workers.append({"thread": thread, "cancel": cancel})


## Stop every in-flight request and join every worker. Safe to call from
## teardown; blocking there is correct.
func shutdown() -> void:
	_shutdown = true
	for worker: Dictionary in _workers:
		(worker["cancel"] as LLMCancelToken).cancel()
	for worker: Dictionary in _workers:
		var thread: Thread = worker["thread"]
		if thread.is_started():
			thread.wait_to_finish()
	_workers.clear()


func _run(request: Dictionary, done: Callable, cancel: LLMCancelToken) -> void:
	var started := Time.get_ticks_msec()
	var body := _build_body(request)
	var options := {
		"connect_timeout_ms": connect_timeout_ms,
		"read_timeout_ms": read_timeout_ms,
		"turn_timeout_ms": read_timeout_ms,
		"capture_path": capture_path,
	}
	var forwarded: Array[String] = []
	var on_token := func(text: String) -> void: forwarded.append(text)
	var response := _client.post_stream(url(), body, on_token, cancel, options)
	var latency := Time.get_ticks_msec() - started
	if not response.get("ok", false):
		var err: Variant = response.get("error")
		var code := "classifier_error"
		var message := ""
		if err is Dictionary:
			code = String((err as Dictionary).get("code", code))
			message = String((err as Dictionary).get("message", ""))
		(
			done
			. call(
				{
					"ok": false,
					"error": {"code": code, "message": message},
					"raw": "",
					"latency_ms": latency,
				}
			)
		)
		return
	var raw := String(response.get("text", ""))
	if raw.is_empty() and not forwarded.is_empty():
		raw = "".join(forwarded)
	done.call({"ok": true, "verdict": "", "raw": raw, "latency_ms": latency})


## Request body for the shared llama-server chat endpoint. Deliberately no
## `response_format`: a grammar would let the model answer a token and still
## leave the parse ambiguous; a bare 8-token completion is what docs/02 §8
## specifies. `cache_prompt` is off: classifier prompts are small, distinct
## and must never reuse a slot's turn cache.
func _build_body(request: Dictionary) -> Dictionary:
	var sampling: Dictionary = {}
	var raw_sampling: Variant = request.get("sampling", {})
	if raw_sampling is Dictionary:
		sampling = (raw_sampling as Dictionary).duplicate()
	if not sampling.has("temperature"):
		sampling["temperature"] = 0.0
	if not sampling.has("top_k"):
		sampling["top_k"] = 1
	return (
		{
			"messages":
			[
				{"role": "system", "content": String(request.get("system", ""))},
				{"role": "user", "content": String(request.get("question", ""))},
			],
			"stream": true,
			"max_tokens": int(request.get("max_tokens", SafetyClassifier.DEFAULT_MAX_TOKENS)),
			"chat_template_kwargs": {"enable_thinking": false},
			"cache_prompt": false,
		}
		. merged(sampling, true)
	)


static func _error_result(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}, "raw": "", "latency_ms": 0}


func _reap() -> void:
	var alive: Array[Dictionary] = []
	for worker: Dictionary in _workers:
		var thread: Thread = worker["thread"]
		if thread.is_alive():
			alive.append(worker)
		elif thread.is_started():
			thread.wait_to_finish()
	_workers = alive
