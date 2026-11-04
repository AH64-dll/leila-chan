class_name SafetyClassifierGate
extends RefCounted
## The classifier hold + pump (docs/02 §8). `Safety` hands it the flagged
## spans of the text it is about to emit; the gate decides when asking is
## possible, keeps ONE request in flight, applies the verdicts to the shared
## `SafetyClassifier` cache and tells Safety to continue draining.
##
## Why a hold at all: a flag is suspicious text, not a block. The span must not
## reach the screen before the answer, but the text before it can. So Safety
## cuts emission at the first unresolved flag, keeps the rest in `_pending`,
## and the gate only ever *asks* about the head of that region. A verdict that
## arrives late is still cached (for the transcript, the next display, the
## prompt lab), while the beat boundary fails the outstanding hold closed.
##
## Fail closed everywhere: no backend, a bad backend, a transport error, an
## unparseable answer, or a matched span that never gets a verdict all resolve
## to a block. Nothing here can release text the model called harmful.

signal settled

const REDACT_CHAR := "█"

var classifier: SafetyClassifier = null
var backend: Object = null
## {key, category, beat_index, since_ms} — the region Safety is holding back.
var hold := {}
## One in-flight request: key -> request (kept until answered, so a late
## verdict still lands in the cache even after the hold was flushed).
var requested := {}
var flush_count := 0
var timeout_count := 0
var hold_ms_total := 0
var hold_count := 0

## Policy callables owned by Safety: `_open(cat) -> bool` closes the gate, and
## `_negated(cat, s, e, match, view) -> bool` applies the list's negation guard.
var _open_cb: Callable
var _neg_cb: Callable


func setup(cls: SafetyClassifier, open_cb: Callable, negated_cb: Callable) -> void:
	classifier = cls
	_open_cb = open_cb
	_neg_cb = negated_cb


func set_backend(obj: Object) -> void:
	backend = obj


func has_backend() -> bool:
	return backend != null and backend.has_method("classify")


func hold_active() -> bool:
	return not hold.is_empty()


func pending() -> Dictionary:
	return hold.duplicate()


## True when the head flag is complete enough to ask about: the match is not at
## the buffer end (a later chunk could extend it) unless the beat already
## closed. Asking on a half-received phrase would spend a request on text the
## player will never see in that form.
func ready(flag: Dictionary, combined: String, beat_closed := false) -> bool:
	if beat_closed:
		return true
	var end := int(flag["e"])
	if end >= combined.length():
		return false
	return not SafetyText.is_word_char(combined.unicode_at(end))


## Streaming flags: unresolved flags in `view` (asked about, held) plus the
## cached blocks appended to `blocked` (the tier-1 bar list, sorted in place).
## A flag a hard span already covers needs no question. Cached "no" verdicts
## simply release the text; cached "yes" verdicts bar it at once.
func matched(view: String, blocked: Array) -> Array:
	var out: Array = []
	if classifier == null or not classifier.is_ready():
		return out
	var grew := false
	for flag in classifier.flag_matches(view, _open_cb, _neg_cb.bind(view)):
		if _contained(flag, blocked):
			continue
		_tag(flag, view)
		var key := String(flag["key"])
		var cached := classifier.cached(key)
		if cached.is_empty():
			out.append(flag)
			continue
		classifier.note_cached_hit()
		if not bool(cached.get("block", true)):
			continue
		(
			blocked
			. append(
				{
					"s": int(flag["s"]),
					"e": int(flag["e"]),
					"cat": String(flag["cat"]),
					"cats": PackedStringArray([String(flag["cat"])]),
					"match": String(flag["match"]),
					"via": "classifier",
				}
			)
		)
		grew = true
	if grew:
		blocked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])
	return out


## Start (or refresh) the hold at the first unresolved flag. The clock only
## restarts when the head flag changes: a beat spending longer on the same
## phrase must still time out against the same deadline.
func hold_for(flags: Array, beat_index: int) -> void:
	if flags.is_empty():
		hold = {}
		return
	var first: Dictionary = flags[0]
	var key := String(first["key"])
	if not hold.is_empty() and String(hold.get("key", "")) == key:
		return
	hold = {
		"key": key,
		"category": String(first["cat"]),
		"beat_index": beat_index,
		"since_ms": Time.get_ticks_msec(),
	}


## Ask about the head flag when nothing else is in flight. A synchronous
## backend answers before this returns (`settled` fires); an asynchronous one
## answers later.
func pump(combined: String, flags: Array, ctx: Dictionary, beat_closed := false) -> void:
	if flags.is_empty() or classifier == null or not classifier.is_ready():
		return
	if not requested.is_empty():
		return
	var flag: Dictionary = flags[0]
	if not ready(flag, combined, beat_closed):
		return
	var req := classifier.build_request(flag, String(flag.get("context", "")), ctx)
	req["gate_open"] = _open_cb
	_issue(req, true)


## Whole-text path (`filter_text`): every flagged span must be decided now.
## A cached verdict decides; otherwise the request is issued and the span is
## barred unless the backend answers synchronously (no display can wait).
## Returns `spans` extended with the classifier's blocks, sorted and merged.
## Requests from this path are quiet: they never emit `settled`, so a
## transcript scan mid-beat cannot resume the display pipeline.
func resolve_whole(spans: Array, view: String, ctx: Dictionary) -> Array:
	if classifier == null or not classifier.is_ready():
		return spans
	var out: Array = spans.duplicate()
	for flag in classifier.flag_matches(view, _open_cb, _neg_cb.bind(view)):
		if _contained(flag, out):
			continue
		_tag(flag, view)
		var key := String(flag["key"])
		var cached := classifier.cached(key)
		var was_cached := not cached.is_empty()
		if not was_cached:
			var req := classifier.build_request(flag, String(flag["context"]), ctx)
			req["gate_open"] = _open_cb
			_issue(req, false)
			cached = classifier.cached(key)
		if was_cached:
			classifier.note_cached_hit()
		if not cached.is_empty() and not bool(cached.get("block", true)):
			continue
		(
			out
			. append(
				{
					"s": int(flag["s"]),
					"e": int(flag["e"]),
					"cat": String(flag["cat"]),
					"cats": PackedStringArray([String(flag["cat"])]),
					"match": String(flag["match"]),
					"via": "classifier",
				}
			)
		)
	return merge(out)


## Give up on the outstanding answer: the caller bars the held text. The
## in-flight request keeps running so its verdict still lands in the cache.
func flush(reason := "flush") -> String:
	if hold.is_empty():
		return ""
	var cat := String(hold.get("category", ""))
	flush_count += 1
	if reason == "timeout":
		timeout_count += 1
	_note_hold_ms()
	hold = {}
	return cat


## A hold older than the configured deadline must not wait for the next beat.
func expired(now_ms: int) -> bool:
	if hold.is_empty() or classifier == null:
		return false
	return now_ms - int(hold.get("since_ms", now_ms)) >= classifier.hold_timeout_ms()


func _issue(req: Dictionary, loud: bool) -> void:
	var key := String(req.get("key", ""))
	if key.is_empty():
		return
	req["loud"] = loud
	requested[key] = req
	classifier.note_request(0)
	if not has_backend():
		_settle(key, {"ok": false, "error": {"code": "no_backend", "message": ""}})
		return
	backend.call("classify", req, Callable(self, "_on_done").bind(key))


## Backend callback. Workers call it from their own thread; Safety owns the
## main thread, so every verdict is deferred back to it before touching state.
func _on_done(result: Variant, key: String) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		call_deferred("_settle_deferred", key, result)
		return
	_settle(key, result)


func _settle_deferred(key: String, result: Variant) -> void:
	_settle(key, result)


func _settle(key: String, result: Variant) -> void:
	if not requested.has(key):
		return
	var req: Dictionary = requested[key]
	requested.erase(key)
	var interpreted := classifier.interpret(result)
	classifier.note_latency(int(interpreted.get("latency_ms", 0)))
	var category := String(req.get("category", ""))
	var gate_open := false
	var cb: Variant = req.get("gate_open")
	if cb is Callable and (cb as Callable).is_valid():
		gate_open = bool((cb as Callable).call(category))
	var block := classifier.remember(
		key, category, String(interpreted.get("verdict", "")), gate_open
	)
	var error_code := ""
	if interpreted.get("error") is Dictionary:
		error_code = String((interpreted["error"] as Dictionary).get("code", ""))
	(
		classifier
		. note_verdict(
			{
				"ts": Time.get_unix_time_from_system(),
				"category": category,
				"matched": String(req.get("match", "")),
				"verdict": String(interpreted.get("verdict", "error")),
				"blocked": block,
				"latency_ms": int(interpreted.get("latency_ms", 0)),
				"error": error_code,
				"beat": int(hold.get("beat_index", -1)),
			}
		)
	)
	if not bool(req.get("loud", false)):
		return
	if not hold.is_empty() and String(hold.get("key", "")) == key:
		_note_hold_ms()
		hold["since_ms"] = Time.get_ticks_msec()
	settled.emit()


func _note_hold_ms() -> void:
	if hold.is_empty():
		return
	hold_ms_total += Time.get_ticks_msec() - int(hold.get("since_ms", 0))
	hold_count += 1


## Tag a raw flag with the exact text the model will see and the cache key for
## it. The key covers the clause window, not just the matched span: the same
## span can mean opposite things in different sentences ("i know how to use a
## knife." vs "... a knife and fork."), so the judged context is the identity.
func _tag(flag: Dictionary, view: String) -> void:
	var context := _context_around(view, int(flag["s"]), int(flag["e"]))
	flag["context"] = context
	flag["key"] = classifier.verdict_key(String(flag["cat"]), context)


func _context_around(text: String, start: int, end: int) -> String:
	var pad := classifier.context_chars() if classifier != null else 0
	var from := maxi(0, start - pad)
	var to := mini(text.length(), end + pad)
	return text.substr(from, to - from).strip_edges()


func _contained(flag: Dictionary, spans: Array) -> bool:
	var start := int(flag["s"])
	var end := int(flag["e"])
	for span in spans:
		if start >= int(span["s"]) and end <= int(span["e"]):
			return true
	return false


## Sorted, overlap-merged copy — `_apply_spans` walks spans in ascending order
## and bars `[s, e)` without re-sorting.
static func merge(found: Array) -> Array:
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])
	var merged: Array = []
	for span in found:
		if merged.is_empty() or int(span["s"]) >= int(merged[-1]["e"]):
			merged.append(span)
		else:
			var target: Dictionary = merged[-1]
			target["e"] = maxi(int(target["e"]), int(span["e"]))
			var cats: PackedStringArray = target.get("cats", PackedStringArray())
			for cat in span.get("cats", PackedStringArray([span.get("cat", "")])):
				if not cats.has(cat):
					cats.append(cat)
			target["cats"] = cats
	return merged


func stats() -> Dictionary:
	var out := classifier.stats() if classifier != null else {}
	out["flush_count"] = flush_count
	out["timeout_count"] = timeout_count
	out["in_flight"] = requested.size()
	out["hold_active"] = hold_active()
	out["hold_ms_total"] = hold_ms_total
	out["hold_count"] = hold_count
	return out
