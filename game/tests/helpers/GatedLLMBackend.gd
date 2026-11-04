extends LLMBackend
## Scripted backend that streams its chunks and then parks until the test sets
## `release` (P2.20). `FakeLLMBackend.block_until_cancel` cannot hold a turn
## open — it parks by cancelling — and the after-turn autosave needs a turn that
## is still in flight while the main thread lets the typewriter drain: that is
## the window in which a synchronous save is refused as "busy".

var chunks := PackedStringArray()
var release := false
var poll_ms := 1


func generate(_request: TurnRequest, on_token: Callable, cancel: LLMCancelToken) -> Dictionary:
	var text := ""
	for chunk: String in chunks:
		if cancel.is_cancelled():
			return _cancelled()
		on_token.call(chunk)
		text += chunk
	while not release and not cancel.is_cancelled():
		OS.delay_msec(poll_ms)
	if cancel.is_cancelled():
		return _cancelled()
	return {"ok": true, "text": text}


static func _cancelled() -> Dictionary:
	return {"ok": false, "error": {"code": "cancelled", "message": "cancelled by caller"}}
