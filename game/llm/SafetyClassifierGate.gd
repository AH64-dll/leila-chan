class_name SafetyClassifierGate
extends RefCounted
## The classifier hold + pump (docs/02 §8). `Safety` hands it the flagged
## spans of the text it is about to emit; the gate decides when asking is
## possible, keeps one held-beat request in flight, applies the verdicts to the
## shared `SafetyClassifier` cache and tells Safety to continue draining.
##
## Why a hold at all: a flag is suspicious text, not a block. The span must not
## reach the screen before the answer, but the text before it can. So Safety
## cuts emission at the first unresolved flag, keeps the rest in `_pending`,
## and the gate only ever *asks* about the head of that region. A verdict that
## arrives late is still cached (for the transcript, the next display, the
## prompt lab), while the beat boundary fails the outstanding hold closed.
##
## Policy that lives here, not in Safety:
##  * the cache stores the raw verdict; the block is decided against the gate in
##    force when the text is displayed (CODE-1). A "yes" answered during a
##    stage-4/full turn is therefore still a bar at stage 0 or in calmer mode.
##  * the cache key is the clause window around the match, cut at the clause
##    break, and a span is only asked about once that window has stopped growing
##    — one span is one request, not one per chunk (CODE-2).
##  * flags are read from both normalized views, so a leetspeak novel phrase
##    still reaches the question (SAF-4).
##
## Fail closed everywhere: no backend, a bad backend, a transport error, an
## unparseable answer, or a matched span that never gets a verdict all resolve
## to a block. Nothing here can release text the model called harmful.

signal settled

const REDACT_CHAR := "█"
## A whole-text scan (transcript, repair, opening beat) may not fan out into an
## unbounded burst of worker threads; past this many quiet requests the rest of
## the spans bar, which is what they do without a verdict anyway (SAF-8).
const MAX_QUIET_IN_FLIGHT := 4

var classifier: SafetyClassifier = null
var backend: Object = null
## {key, category, beat_index, since_ms} — the region Safety is holding back.
var hold := {}
## In-flight requests: key -> the request. Kept until answered, so a late
## verdict still lands in the cache even after the hold was flushed.
var requested := {}
var flush_count := 0
var timeout_count := 0
var hold_ms_total := 0
var hold_count := 0

## Policy callables owned by Safety: `_open(cat) -> bool` closes the gate, and
## `_negated(cat, s, e, match, view) -> bool` applies the list's negation guard.
var _open_cb: Callable
var _neg_cb: Callable
## Clause-break classification for the cache window (`is_clause_break` reads a
## code set, so it is an instance method, not a static one).
var _text := SafetyText.new()


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
## closed, and the clause window the key is built from has stopped growing
## (CODE-2). Asking earlier spends a request on a key the next chunk invalidates.
func ready(flag: Dictionary, combined: String, beat_closed := false) -> bool:
	if beat_closed:
		return true
	var end := int(flag["e"])
	if end >= combined.length():
		return false
	if SafetyText.is_word_char(combined.unicode_at(end)):
		return false
	return bool(flag.get("settled", true))


## Streaming flags: unresolved flags in `views` (asked about, held) plus the
## cached blocks appended to `blocked` (the tier-1 bar list, sorted in place).
## A flag a hard span already covers needs no question. Cached "no" verdicts
## simply release the text; cached "yes" verdicts bar it at once if the gate is
## closed now (never because it was open when the answer landed).
func matched(views: Dictionary, blocked: Array) -> Array:
	var out: Array = []
	if classifier == null or not classifier.is_ready():
		return out
	var grew := false
	for flag in _flags_for(views, blocked):
		var cached := classifier.cached(String(flag["key"]))
		if cached.is_empty():
			out.append(flag)
			continue
		classifier.note_cached_hit()
		if not _cached_block(cached, String(flag["cat"])):
			continue
		blocked.append(_block_span(flag, cached))
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


## Ask about the head flag when no held beat is waiting. A synchronous backend
## answers before this returns (`settled` fires); an asynchronous one answers
## later. Quiet whole-text requests never block this path (SAF-8).
func pump(combined: String, flags: Array, ctx: Dictionary, beat_closed := false) -> void:
	if flags.is_empty() or classifier == null or not classifier.is_ready():
		return
	if _loud_in_flight():
		return
	var flag: Dictionary = flags[0]
	if not ready(flag, combined, beat_closed):
		return
	var req := classifier.build_request(flag, String(flag.get("context", "")), ctx)
	_issue(req, true)


## Whole-text path (`filter_text`): every flagged span must be decided now.
## A cached verdict decides; otherwise the request is issued and the span is
## barred unless the backend answers synchronously (no display can wait).
## Returns `spans` extended with the classifier's blocks, sorted and merged.
## Requests from this path are quiet: they never emit `settled`, so a
## transcript scan mid-beat cannot resume the display pipeline.
func resolve_whole(spans: Array, views: Dictionary, ctx: Dictionary) -> Array:
	if classifier == null or not classifier.is_ready():
		return spans
	var out: Array = spans.duplicate()
	for flag in _flags_for(views, out):
		var key := String(flag["key"])
		var cached := classifier.cached(key)
		var was_cached := not cached.is_empty()
		if not was_cached:
			var req := classifier.build_request(flag, String(flag["context"]), ctx)
			_issue(req, false)
			cached = classifier.cached(key)
		if was_cached:
			classifier.note_cached_hit()
		if not cached.is_empty() and not _cached_block(cached, String(flag["cat"])):
			continue
		out.append(_block_span(flag, cached))
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
	_expire_quiet(now_ms)
	if hold.is_empty() or classifier == null:
		return false
	return now_ms - int(hold.get("since_ms", now_ms)) >= classifier.hold_timeout_ms()


## Stop the transport (it owns worker threads) and forget every in-flight
## request. Called from Safety's teardown; blocking there is correct (CODE-5).
func shutdown() -> void:
	requested.clear()
	hold = {}
	if backend != null and backend.has_method("shutdown"):
		backend.call("shutdown")


## Every unresolved flag in text order, read from both normalized views: the
## leet fold is what makes `1 h0pe 1 d0n't w4ke up.` visible to a novel-phrase
## flag (SAF-4). The same span found twice is one flag.
func _flags_for(views: Dictionary, blocked: Array) -> Array:
	var out: Array = []
	for name in ["plain", "leet"]:
		var view := String(views.get(name, ""))
		if view.is_empty():
			continue
		for flag in classifier.flag_matches(view, _open_cb, _neg_cb.bind(view)):
			if _contained(flag, blocked) or _seen(flag, out):
				continue
			_tag(flag, view)
			out.append(flag)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])
	return out


func _seen(flag: Dictionary, flags: Array) -> bool:
	var cat := String(flag["cat"])
	for other in flags:
		if (
			String(other["cat"]) == cat
			and int(other["s"]) == int(flag["s"])
			and int(other["e"]) == int(flag["e"])
		):
			return true
	return false


func _block_span(flag: Dictionary, cached: Dictionary) -> Dictionary:
	return {
		"s": int(flag["s"]),
		"e": int(flag["e"]),
		"cat": String(flag["cat"]),
		"cats": PackedStringArray([String(flag["cat"])]),
		"match": String(flag["match"]),
		"via": "classifier",
		"verdict": String(cached.get("verdict", "")),
	}


## A cached verdict is a verdict, never a permission: the block is decided
## against the gate in force now, not the one that was current when the answer
## arrived (CODE-1/SAF-2). An error verdict (empty) blocks, as it always has.
func _cached_block(cached: Dictionary, cat: String) -> bool:
	return _block_for(String(cached.get("verdict", "")), cat)


func _block_for(verdict: String, cat: String) -> bool:
	if verdict == "no":
		return false
	var open := _open_cb.is_valid() and bool(_open_cb.call(cat))
	return not (verdict == "yes" and open)


func _issue(req: Dictionary, loud: bool) -> void:
	var key := String(req.get("key", ""))
	if key.is_empty():
		return
	if requested.has(key):
		## The first ask owns the answer: a quiet whole-text scan must not replace
		## a held beat's request, or the beat never resumes (CODE-4).
		requested[key]["loud"] = bool(requested[key].get("loud", false)) or loud
		return
	if not loud and _quiet_in_flight() >= MAX_QUIET_IN_FLIGHT:
		return
	var category := String(req.get("category", ""))
	req["loud"] = loud
	## The gate is captured at ask time for the verdict log only; the block is
	## decided at display time (CODE-1).
	req["gate_open"] = _open_cb.is_valid() and bool(_open_cb.call(category))
	req["since_ms"] = Time.get_ticks_msec()
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
	var verdict := String(interpreted.get("verdict", ""))
	var block := _block_for(verdict, category)
	classifier.remember(key, category, verdict)
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
				"verdict": verdict if verdict != "" else "error",
				"blocked": block,
				"gate_open": bool(req.get("gate_open", false)),
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


func _loud_in_flight() -> bool:
	for key in requested:
		if bool(requested[key].get("loud", false)):
			return true
	return false


func _quiet_in_flight() -> int:
	var count := 0
	for key in requested:
		if not bool(requested[key].get("loud", true)):
			count += 1
	return count


## A hung whole-text request must not pin a slot for the whole run (SAF-8). Its
## answer is dropped once the entry is gone; the span stays barred, which is
## what the whole-text path does without a verdict anyway.
func _expire_quiet(now_ms: int) -> void:
	if classifier == null:
		return
	var deadline := classifier.hold_timeout_ms()
	for key in requested.keys():
		var req: Dictionary = requested[key]
		if bool(req.get("loud", false)):
			continue
		if now_ms - int(req.get("since_ms", now_ms)) >= deadline:
			requested.erase(key)


## Tag a raw flag with the exact text the model will see and the cache key for
## it. The key covers the clause window, not just the matched span: the same
## span can mean opposite things in different sentences ("i know how to use a
## knife." vs "... a knife and fork."), so the judged context is the identity.
## `settled` says whether that window can still grow (CODE-2).
func _tag(flag: Dictionary, view: String) -> void:
	var end := int(flag["e"])
	var pad := classifier.context_chars() if classifier != null else 0
	flag["context"] = _context_around(view, int(flag["s"]), end, pad)
	flag["key"] = classifier.verdict_key(String(flag["cat"]), String(flag["context"]))
	flag["settled"] = end + pad <= view.length() or _window_end(view, end, pad) < view.length()


func _context_around(text: String, start: int, end: int, pad: int) -> String:
	var from := maxi(0, start - pad)
	var to := _window_end(text, end, pad)
	return text.substr(from, to - from).strip_edges()


## End of the trailing half of the window: `pad` characters after the match, cut
## at the first clause break, so a sentence written after it cannot mint a new
## key for the same span — one span, one request, however many chunks (CODE-2).
## The knife / knife-and-fork distinction survives: `and fork` is the same clause.
func _window_end(text: String, end: int, pad: int) -> int:
	var to := mini(text.length(), end + pad)
	for i in range(end, to):
		if _text.is_clause_break(text.unicode_at(i)):
			return i
	return to


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
	out["quiet_in_flight"] = _quiet_in_flight()
	out["hold_active"] = hold_active()
	out["hold_ms_total"] = hold_ms_total
	out["hold_count"] = hold_count
	return out
