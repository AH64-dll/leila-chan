class_name TranscriptRedactor
extends RefCounted
## Record-level safety pass for the P1.18 transcript (docs/07 §5, gate r2 B1).
##
## TranscriptLogger applies exactly one injected redactor to every line before it
## touches disk; this is the Director's. It used to rewrite only `output`, which
## left the same model text raw in three other places: the applied `events`
## (`field`/`beat_field` values and the `say_chunk` fragments), and the assistant
## messages of `prompt`, which quote earlier replies back to the model. The gate
## found the proof in a committed playtest transcript — barred `output.inner`,
## raw `field` `inner` in the same record. Every model-text surface now goes
## through the same filter the display uses (docs/02 §8: the filter is the one
## authority on displayed text).
##
## Scan shape (`SaySafetyGate.scan_text`): the stateless whole-text scan, never
## the streaming one. Two reasons. (1) One record is exactly one model reply —
## the span the display scans between two `end_utterance` cuts — so its
## `say_chunk` fragments are joined and scanned as a single utterance (a phrase
## split across two streamed tokens must bar like it does on screen), while two
## different payloads are separate utterances and must never share a match
## window; a stateless scan has no carry, so that boundary is structural.
## (2) Redaction runs after the turn closed, so it must not write the streaming
## scanner's state (`_pending`, the cross-beat window, the beat flag) that the
## next reply's display depends on.
##
## Non-text payloads stay verbatim: cue/sprite/feeling/music/read/action names,
## intensities and mood ints are engine vocabulary the game matches and counts,
## not model prose — barring them would corrupt the record without protecting
## anything. Unknown field names are scanned (fail-safe), because a field the
## schema does not know is still model text.
##
## Fail-closed: with no scanning filter the output is replaced by
## SaySafetyGate bars and the record is marked `meta.redaction = "unavailable"`,
## so a transcript never holds text the screen would have refused.

## `field`/`beat_field` names that carry engine vocabulary or numbers, never
## model prose: matched by code (`read`, `music`, `fx`, `action`, `feeling`,
## `cue`), counted (`intensity`, `mood`) or resolved by the sprite resolver
## (`sprite`). Everything else is text and is scanned.
const VOCABULARY_FIELDS: Array[String] = [
	"read",
	"music",
	"fx",
	"action",
	"feeling",
	"cue",
	"intensity",
	"sprite",
	"mood",
]

var _gate: SaySafetyGate


func _init(gate: SaySafetyGate = null) -> void:
	_gate = gate


## Redact one record in place and return it — the TranscriptLogger redactor
## contract (Callable(Dictionary) -> Dictionary). `stage` from the record feeds
## the filter's stage gates, so a gated category bars exactly where the display
## would have barred it for that turn.
func redact_record(record: Dictionary) -> Dictionary:
	var ctx := {"stage": int(record.get("stage", 0))}
	if record.get("output") is String:
		record["output"] = _scan(str(record["output"]), ctx)
		if not can_scan():
			_mark_unavailable(record)
	if record.get("prompt") is Array:
		_redact_messages(record["prompt"], ctx)
	if record.get("events") is Array:
		_redact_events(record["events"], ctx)
	return record


## True when a filter can scan whole text; false means every surface is barred.
func can_scan() -> bool:
	return _gate != null and _gate.has_text_scan()


## Prompt history: an assistant message is an earlier model reply quoted back to
## the model (PromptBuilder keeps spoken text only), so it is model text and is
## scanned like the rest. System and player messages are authored or
## player-typed and stay verbatim — the transcript is the tuning corpus.
func _redact_messages(messages: Array, ctx: Dictionary) -> void:
	for message: Variant in messages:
		if not message is Dictionary:
			continue
		var m: Dictionary = message
		if String(m.get("role", "")) != "assistant":
			continue
		if m.get("content") is String:
			m["content"] = _scan(str(m["content"]), ctx)


## Event payloads (gate r2 B1). The `say_chunk` fragments of one record are one
## reply, so they are joined, scanned once and put back. The scan is length
## preserving (every barred character becomes one bar), so the fragments keep
## their streamed boundaries; if it is not — the filter collapsed whitespace, or
## had to bar the whole text — the reply is stored once on the first fragment
## and the rest are emptied, rather than risk a half-barred line.
func _redact_events(events: Array, ctx: Dictionary) -> void:
	var chunks: Array[Dictionary] = []
	var reply := ""
	for event: Variant in events:
		if not event is Dictionary:
			continue
		var e: Dictionary = event
		match String(e.get("type", "")):
			"say_chunk":
				if e.get("text") is String:
					var fragment := str(e["text"])
					chunks.append({"event": e, "length": fragment.length()})
					reply += fragment
			"field", "beat_field":
				if not VOCABULARY_FIELDS.has(String(e.get("name", ""))):
					e["value"] = _redact_value(e.get("value"), ctx)
	if reply.is_empty():
		return
	var scanned := _scan(reply, ctx)
	if scanned == reply:
		return
	if scanned.length() == reply.length():
		var at := 0
		for chunk: Dictionary in chunks:
			var size := int(chunk["length"])
			(chunk["event"] as Dictionary)["text"] = scanned.substr(at, size)
			at += size
		return
	for i: int in chunks.size():
		(chunks[i]["event"] as Dictionary)["text"] = scanned if i == 0 else ""


## One field value. A value is model text only when it is a string (or a
## container of strings) under a non-vocabulary name; numbers, booleans, enums
## and null pass through untouched.
func _redact_value(value: Variant, ctx: Dictionary) -> Variant:
	if value is String:
		return _scan(str(value), ctx)
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_redact_value(item, ctx))
		return out
	if value is Dictionary:
		var out_dict: Dictionary = {}
		for key: Variant in value:
			out_dict[key] = _redact_value(value[key], ctx)
		return out_dict
	return value


func _scan(text: String, ctx: Dictionary) -> String:
	if _gate == null:
		return SaySafetyGate.redact(text)
	return _gate.scan_text(text, ctx)


func _mark_unavailable(record: Dictionary) -> void:
	var meta: Variant = record.get("meta", {})
	if meta is Dictionary:
		meta["redaction"] = "unavailable"
		record["meta"] = meta
