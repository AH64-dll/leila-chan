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

const REDACT_CHAR := "█"

var _filter: Object = null
var _warned_missing := false
var _streaming := false


func set_filter(node: Object) -> void:
	_filter = node


func filter_node() -> Object:
	return _filter


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
