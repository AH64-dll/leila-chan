class_name LLMBackend
extends RefCounted


## Transport contract for the LLM facade (docs/07 §3.1). One generate() call
## runs one turn on the facade's WORKER thread — blocking is fine here, never
## on the main thread. `LlamaServerBackend` is the prototype transport; tests
## drive the facade with scripted fakes (`FakeLLMBackend`, `FakeLlamaServer`).
##
## Implementations must:
##  * call on_token.call(chunk: String) once per streamed text chunk, in order;
##  * poll cancel.is_cancelled() and return promptly once it becomes true;
##  * return {"ok": true, "text": full_text} on success or
##    {"ok": false, "error": {"code": String, "message": String}} on failure;
##  * never touch SceneTree/Node APIs or emit main-thread signals directly —
##    the facade relays everything through call_deferred.
##
## Extra result keys (a `metrics` dictionary, for example) are allowed and
## ignored by the facade. Error codes should stay stable for the Director and
## transcript logger: invalid_request, server_unreachable, port_in_use,
## server_files_missing, server_start_failed, server_exited,
## server_start_timeout, connect_timeout, read_timeout, turn_timeout,
## http_error, server_error, malformed_sse, stream_truncated, read_failed,
## bad_chunked_body, bad_response, unsupported_scheme, cancelled.
##
## A cancelled call may return anything; the facade reports "cancelled" anyway.
func generate(_request: TurnRequest, _on_token: Callable, _cancel: LLMCancelToken) -> Dictionary:
	return {
		"ok": false,
		"error": {"code": "unimplemented", "message": "LLMBackend.generate() not implemented"},
	}
