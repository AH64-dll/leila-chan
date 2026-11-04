class_name FakeClassifierBackend
extends SafetyClassifierBackend
## Scripted classifier transport for the safety suite and the corpus runner.
## The real transport is SafetyClassifierHttp (one HTTP call per flag); tests
## need a backend that answers deterministically, can be told to answer late
## (`defer`), and can fail on purpose so the fail-closed path is exercised.
##
## Answer policy, in order:
##   1. `error_code` set -> an error result (Safety must bar the span);
##   2. `forced_verdict` set -> that verdict for every request;
##   3. `yes_phrases` / `no_phrases` found in the request text -> yes / no;
##   4. `default_verdict`.
## Every request is kept in `requests` so a test can assert the prompt, the
## category, max_tokens and that dose is empty.

var yes_phrases := PackedStringArray()
var no_phrases := PackedStringArray()
var default_verdict := "no"
var forced_verdict := ""
var error_code := ""
var raw_override := ""
var latency_ms := 0
## When true the callback is queued and only delivered by `deliver()` — the
## late-verdict path (an async transport answering after the beat closed).
var defer := false

var requests: Array[Dictionary] = []

var _pending: Array[Dictionary] = []


func classify(request: Dictionary, done: Callable) -> void:
	requests.append(request.duplicate(true))
	if defer:
		_pending.append({"request": request, "done": done})
		return
	done.call(answer_for(request))


func answer_for(request: Dictionary) -> Dictionary:
	if not error_code.is_empty():
		return {
			"ok": false,
			"error": {"code": error_code, "message": "scripted failure"},
			"raw": "",
			"latency_ms": latency_ms,
		}
	if not raw_override.is_empty():
		return {"ok": true, "verdict": "", "raw": raw_override, "latency_ms": latency_ms}
	if not forced_verdict.is_empty():
		return {
			"ok": true, "verdict": forced_verdict, "raw": forced_verdict, "latency_ms": latency_ms
		}
	var text := String(request.get("text", "")).to_lower()
	var verdict := default_verdict
	for phrase in no_phrases:
		if phrase in text:
			return {"ok": true, "verdict": "no", "raw": "no", "latency_ms": latency_ms}
	for phrase in yes_phrases:
		if phrase in text:
			return {"ok": true, "verdict": "yes", "raw": "yes", "latency_ms": latency_ms}
	return {"ok": true, "verdict": verdict, "raw": verdict, "latency_ms": latency_ms}


## Deliver queued answers. `verdict` overrides the scripted answer ("" keeps
## it); `all=false` delivers only the oldest, which is what a one-slot server
## does. Returns how many were delivered.
func deliver(verdict := "", all := true) -> int:
	var count := 0
	while not _pending.is_empty():
		var item: Dictionary = _pending.pop_front()
		var result: Dictionary = (
			answer_for(item["request"])
			if verdict.is_empty()
			else {"ok": true, "verdict": verdict, "raw": verdict, "latency_ms": latency_ms}
		)
		(item["done"] as Callable).call(result)
		count += 1
		if not all:
			break
	return count


func pending_count() -> int:
	return _pending.size()


func last_request() -> Dictionary:
	return requests[-1].duplicate(true) if not requests.is_empty() else {}
