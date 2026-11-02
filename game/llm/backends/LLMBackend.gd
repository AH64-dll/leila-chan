class_name LLMBackend
extends RefCounted


## Transport contract for the LLM facade (docs/07 §3.1). One generate() call
## runs one turn on the facade's WORKER thread — blocking is fine here, never
## on the main thread. P1.02 adds the real transport (LlamaServerBackend);
## tests drive the facade with a scripted fake.
##
## Implementations must:
##  * call on_token.call(chunk: String) once per streamed text chunk, in order;
##  * poll cancel.is_cancelled() and return promptly once it becomes true;
##  * return {"ok": true, "text": full_text} on success or
##    {"ok": false, "error": {"code": String, "message": String}} on failure;
##  * never touch SceneTree/Node APIs or emit main-thread signals directly —
##    the facade relays everything through call_deferred.
##
## A cancelled call may return anything; the facade reports "cancelled" anyway.
func generate(_request: TurnRequest, _on_token: Callable, _cancel: LLMCancelToken) -> Dictionary:
	return {
		"ok": false,
		"error": {"code": "unimplemented", "message": "LLMBackend.generate() not implemented"},
	}
