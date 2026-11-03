extends LLMBackend
## Scripted in-memory backend for tests (P1.01): emits `chunks` one by one,
## optionally fails after `fail_after` chunks with `error`, and when
## `block_until_cancel` is set parks after the chunks until the cancel flag
## arrives — the deterministic way to exercise mid-flight cancellation.

var chunks := PackedStringArray()
## Optional per-call chunk scripts: when non-empty, call N streams
## `chunk_sets[N]` (falling back to `chunks` past the end). Lets a test script
## a retry — the same turn generating twice — with different output.
var chunk_sets: Array = []
var error := {}
var fail_after := -1
var block_until_cancel := false
var poll_ms := 1
var raw_result := {}  # non-empty: returned verbatim, bypassing all script logic
var metrics := {}

var calls := 0
var seen_request: TurnRequest
var saw_cancel := false
var worker_thread_id := -1


func last_metrics() -> Dictionary:
	return metrics.duplicate(true)


func generate(request: TurnRequest, on_token: Callable, cancel: LLMCancelToken) -> Dictionary:
	calls += 1
	seen_request = request
	worker_thread_id = OS.get_thread_caller_id()
	if not raw_result.is_empty():
		return raw_result
	var active_chunks := chunks
	if not chunk_sets.is_empty():
		var set_index := mini(calls - 1, chunk_sets.size() - 1)
		var scripted: Variant = chunk_sets[set_index]
		if scripted is PackedStringArray:
			active_chunks = scripted
		elif scripted is Array:
			active_chunks = PackedStringArray(scripted)
	var text := ""
	for i: int in active_chunks.size():
		if cancel.is_cancelled():
			saw_cancel = true
			return {"ok": false, "error": {"code": "cancelled", "message": "cancelled by caller"}}
		if fail_after >= 0 and i >= fail_after:
			return {"ok": false, "error": error}
		on_token.call(active_chunks[i])
		text += active_chunks[i]
	while block_until_cancel and not cancel.is_cancelled():
		OS.delay_msec(poll_ms)
	if block_until_cancel:
		saw_cancel = true
		return {"ok": false, "error": {"code": "cancelled", "message": "cancelled by caller"}}
	if not error.is_empty():
		return {"ok": false, "error": error}
	return {"ok": true, "text": text}
