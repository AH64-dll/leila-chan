class_name SafetyClassifierBackend
extends RefCounted
## Transport contract for the Safety filter's classifier pass (docs/02 §8:
## "a tiny classifier pass (same model, dose 0, 8-token yes/no) only on beats
## flagged by the regex pre-pass").
##
## `Safety` (game/autoload/Safety.gd) owns the verdict cache, the hold and the
## fail-closed policy; a backend only answers one question. Implementations
## must:
##  * call `done` exactly once with `{ok: true, verdict: "yes"|"no", raw, latency_ms}`
##    or `{ok: false, error: {code, message}, raw, latency_ms}`;
##  * finish within the request's `hold_timeout_ms` when they hold state, or
##    let `Safety` time the hold out (the hold then fails closed to bars);
##  * never touch SceneTree/Node state. A backend MAY call `done` from a worker
##    thread: `Safety` defers the verdict to the main thread itself.
##
## `SafetyClassifierHttp` is the prototype transport (same local llama-server,
## no control vectors bound to the request = dose 0). Tests and the corpus
## runner install a synchronous fake so one process owns the whole pipeline.

const REDACT_CHAR := "█"


## Ask one yes/no question about `request.text`. `request` is built by
## `SafetyClassifier.build_request()` and carries the category, the matched
## span, the system prompt, the question, max_tokens, sampling and dose.
func classify(_request: Dictionary, done: Callable) -> void:
	(
		done
		. call(
			{
				"ok": false,
				"error": {"code": "unimplemented", "message": "classifier backend not implemented"},
				"raw": "",
				"latency_ms": 0,
			}
		)
	)


## Parse a raw model answer into "yes" / "no". Shared by every transport so
## the accepted vocabulary lives in one place. Returns "" when the answer is
## not a decisive yes/no (the caller then fails closed).
static func parse_verdict(raw: String, yes: PackedStringArray, no: PackedStringArray) -> String:
	var text := raw.strip_edges().to_lower()
	while not text.is_empty() and not _is_word_char(text.unicode_at(0)):
		text = text.substr(1)
	if text.is_empty():
		return ""
	var token := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if _is_word_char(c):
			token += String.chr(c)
		else:
			break
	if yes.has(token) and not no.has(token):
		return "yes"
	if no.has(token) and not yes.has(token):
		return "no"
	return ""


static func _is_word_char(c: int) -> bool:
	return (
		(c >= 0x61 and c <= 0x7A)
		or (c >= 0x41 and c <= 0x5A)
		or (c >= 0x30 and c <= 0x39)
		or c == 0x5F
	)
