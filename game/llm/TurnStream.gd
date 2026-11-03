class_name TurnStream
extends RefCounted
## Handle for one in-flight turn, returned by LLM.generate() (docs/07 §3.1).
## All signals are emitted on the main thread — the facade relays the worker's
## output through call_deferred. Exactly one of completed / cancelled / failed
## fires, once; after that no more signals are ever emitted.
##
## Helper methods:
##   cancel() -> void: request cancellation (terminal delivery wins).
##   is_cancelled() -> bool: true once cancellation was requested or honoured.
##   is_finished() -> bool: true after the terminal signal has fired.

signal token(text: String)  ## Raw stream chunk, in order.
signal completed(full_text: String)  ## Turn finished cleanly; the whole raw output.
signal cancelled  ## cancel() was honoured (terminal).
signal failed(error: Dictionary)  ## Backend or request error {"code", "message"} (terminal).

var request: TurnRequest  ## The request this stream is serving.
var _cancel_token := LLMCancelToken.new()
var _finished := false
var _was_cancelled := false


## Request cancellation. Idempotent and safe at any time — after a terminal
## signal it is a no-op. The turn ends with `cancelled` once cancellation is
## honoured. Cancellation wins over completion or failure: if cancelled before
## terminal delivery on the main thread, the stream always emits `cancelled`.
func cancel() -> void:
	if not _finished:
		_cancel_token.cancel()


## True once cancellation was requested or honoured.
func is_cancelled() -> bool:
	return _was_cancelled or _cancel_token.is_cancelled()


## True after the terminal signal (completed / cancelled / failed).
func is_finished() -> bool:
	return _finished


## Internal — the facade marks the terminal state just before emitting it.
func _mark_terminal(was_cancelled: bool) -> void:
	_finished = true
	_was_cancelled = was_cancelled
