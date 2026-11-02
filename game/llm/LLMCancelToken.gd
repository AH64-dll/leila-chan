class_name LLMCancelToken
extends RefCounted
## Cooperative cancellation flag shared between the LLM facade's worker
## thread and the main thread (docs/07 §3.1). One token per in-flight turn,
## owned by its TurnStream. Both methods are thread-safe.

var _mutex := Mutex.new()
var _cancelled := false


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()


func is_cancelled() -> bool:
	_mutex.lock()
	var was_cancelled := _cancelled
	_mutex.unlock()
	return was_cancelled
