class_name SaySafetyGate
extends RefCounted
## SaySafetyGate — the single safety scanner for the model text the Director
## pushes toward the screen (docs/02 §8, docs/07 §3.4).
##
## The mandated filter is the Safety autoload (P1.19): `begin_say(ctx)` once per
## beat, `say_chunk(chunk)` per streamed chunk, `end_say()` for the tail, and
## `end_utterance()` at each reply boundary so one reply's displayed tail can
## never be glued into the next reply's match window (P1.19 r4 CODE-19). The
## Director owns both boundaries, so it drives that streaming API itself and
## never installs `ChatUI.text_filter` — that injection point belongs to the UI
## owner, and no chunk is scanned twice (P1.08 review CODE-1, DES-7).
##
## Fail-closed: with no filter available (Safety absent, or a build whose Safety
## has no streaming API) every chunk is replaced by redaction bars instead of
## being displayed raw. Bars keep the typewriter pacing and read as the docs/02
## §8 diegetic redaction; unfiltered model text never reaches the screen.
##
## The input hook is `check_input`-shaped: it delegates to the filter's own input
## check when one exists. docs/02 §8 mandates the OUTPUT filter, so with no
## evaluator at all the player's own line is not blocked — what the game displays
## stays fail-closed either way.

## Late classifier verdict for a held beat (relayed from Safety.hold_released):
## `text` is displayable now — the released text, or the fail-closed bars.
signal hold_released(beat_index: int, text: String)

const REDACT_CHAR := "█"

var _filter: Object = null
var _warned_missing := false
var _streaming := false


func set_filter(node: Object) -> void:
	_filter = node
	if node != null and node.has_signal("hold_released"):
		if not node.is_connected("hold_released", _relay_hold_released):
			node.connect("hold_released", _relay_hold_released)


func filter_node() -> Object:
	return _filter


## The classifier transport/hold API on the real filter (docs/02 §8), or null
## for a build whose filter has no classifier tier (the fake in Director tests).
func classifier_gate() -> Object:
	var node := _filter as Node
	if node == null or not ("classifier_gate" in node):
		return null
	return node.get("classifier_gate")


## Install the yes/no transport (same model, dose 0, 8 tokens). No-op when the
## filter has no classifier tier, so the gate stays usable in old builds.
func set_classifier_backend(backend: Object) -> void:
	var gate := classifier_gate()
	if gate != null:
		gate.call("set_backend", backend)


func pending_hold() -> Dictionary:
	var gate := classifier_gate()
	return gate.call("pending") if gate != null else {}


## Give up on the outstanding verdict now: Safety bars the held text and emits
## `hold_released` (fail closed). Returns the bars, "" when nothing was held.
func flush_hold(reason := "flush") -> String:
	if _filter != null and _filter.has_method("flush_hold"):
		return str(_filter.call("flush_hold", reason))
	return ""


func _relay_hold_released(beat_index: int, text: String) -> void:
	hold_released.emit(beat_index, text)


## True when the filter can stream say text (P1.19 begin_say/say_chunk/end_say).
func can_stream() -> bool:
	return (
		_filter != null
		and _filter.has_method("begin_say")
		and _filter.has_method("say_chunk")
		and _filter.has_method("end_say")
	)


## Open a beat. Every say chunk of that beat is scanned until finish().
func begin_beat(ctx: Dictionary) -> void:
	if not can_stream():
		_warn_missing()
		_streaming = false
		return
	_streaming = true
	_filter.call("begin_say", ctx)


## Scan one streamed chunk; returns only text that is safe to display.
func feed(chunk: String) -> String:
	if chunk.is_empty():
		return ""
	if not _streaming:
		return redact(chunk)
	return str(_filter.call("say_chunk", chunk))


## Close the beat and return the tail the holdback kept back ("" when none).
func finish() -> String:
	if not _streaming:
		return ""
	_streaming = false
	return str(_filter.call("end_say"))


## Mark the reply boundary (the start of a new model utterance). The filter
## clears its cross-beat carry so the next beat is matched fresh; beats *inside*
## one reply still share the carry, which is what catches a phrase split across
## beats. The Director calls this when a new turn starts (P1.19 r4 CODE-19).
## Guarded like every filter capability: a build whose filter predates the API
## simply skips it — the carry stays bounded by its window cap either way.
func end_utterance() -> void:
	if _filter != null and _filter.has_method("end_utterance"):
		_filter.call("end_utterance")


## One-shot whole text (a repaired beat, an inner line): the same streaming API
## driven start to finish, so there is exactly one scan path and never a raw
## `say` handed to a whole-chunk call (P1.19 consumer contract).
func filter_text(text: String, ctx: Dictionary = {}) -> String:
	if text.is_empty():
		return ""
	begin_beat(ctx)
	return feed(text) + finish()


## The player's own line (docs/02 §4 step 0.1). Bound to the filter, never to a
## local phrase list (review CODE-1/DES-7):
##   - an explicit `check_input` on the filter wins;
##   - otherwise the filter's own text scan decides: a line the filter would
##     have to redact is a line the Director refuses to start a turn on (the
##     real filter exempts personal data the player typed themselves, so a
##     player sharing their own details still gets through);
##   - with no filter at all there is no evaluator, so the line is accepted —
##     docs/02 §8 mandates the OUTPUT filter, and blocking every line would make
##     the game unplayable. The display path stays fail-closed regardless.
func check_input(text: String) -> bool:
	if _filter != null and _filter.has_method("check_input"):
		return bool(_filter.call("check_input", text))
	if _filter != null and _filter.has_method("filter_text"):
		var res: Variant = _filter.call("filter_text", text, {})
		if res is Dictionary:
			return str((res as Dictionary).get("text", text)) == text
		return str(res) == text
	return true


func has_input_check() -> bool:
	return _filter != null and _filter.has_method("check_input")


## Whole-text scan for text that is not on its way to the screen — the P1.18
## transcript redactor (gate r2 B1). It calls the filter's own `filter_text`, so
## the scan is stateless: no streaming carry is read or written, two payloads
## can never be matched together as one phrase, and the display scan's state
## (`_pending`, the cross-beat window, the beat flag) is untouched by a
## transcript write. That is what makes one event payload one utterance, with
## the reply boundary (`end_utterance`) structural rather than a call.
##
## Fail-closed: a filter with no whole-text API bars the text instead of
## returning it, exactly like the streaming path.
func scan_text(text: String, ctx: Dictionary = {}) -> String:
	if text.is_empty():
		return text
	if not has_text_scan():
		return redact(text)
	var res: Variant = _filter.call("filter_text", text, ctx)
	if res is Dictionary and (res as Dictionary).has("text"):
		return str((res as Dictionary)["text"])
	return str(res)


## True when the filter can scan a whole text in one call (scan_text's path).
func has_text_scan() -> bool:
	return _filter != null and _filter.has_method("filter_text")


## Redaction bars that keep the text's length, so the typewriter pacing is
## unchanged. Never returns any of the input.
static func redact(text: String) -> String:
	if text.is_empty():
		return ""
	return REDACT_CHAR.repeat(text.length())


func _warn_missing() -> void:
	if _warned_missing:
		return
	_warned_missing = true
	push_warning(
		"SaySafetyGate: no say filter available — say text is fail-closed to redaction bars"
	)
