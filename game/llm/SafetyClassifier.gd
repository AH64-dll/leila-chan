class_name SafetyClassifier
extends RefCounted
## The classifier tier of the output filter (docs/02 §8): the data, the
## yes/no prompt, the verdict cache and the tuning counters. `Safety` owns the
## streaming hold, the content-level gate and the redaction log; this class
## owns everything that is pure classifier policy so the autoload stays inside
## gdlint's file-length limit.
##
## Policy:
##  * flags are questions, never blocks: a flag only makes `Safety` hold the
##    span and ask the model. The lists in filter_lists.json remain the
##    unconditional tier and are never loosened by a verdict.
##  * a "yes" verdict blocks unless the category's gate is open *when the text
##    is displayed* (self-harm and explicit threats are allowed fiction at
##    stage >= 4 + content_level full); a "no" verdict releases. An error, an
##    unparseable answer, a missing backend or a hold timeout blocks (fail
##    closed). The cache stores the verdict, never a gate-dependent permission
##    (P2.17 r2 CODE-1/SAF-2): a "yes" that landed during a stage-4/full turn
##    still bars at stage 0 or in calmer mode.
##  * verdicts are cached per (category, matched text) so the same line is
##    classified once per run, and so whole-text scans (`filter_text`) can pass
##    a span the streaming path already resolved.
##  * gated categories are not flagged at all while their gate is open: a yes
##    verdict could not block there, so the request would be pure latency.

const DEFAULT_MAX_TOKENS := 8
const MAX_TOKENS_LIMIT := 16
const MAX_VERDICTS := 256
const MAX_TEXT_CHARS := 240
const MIN_CONTEXT_CHARS := 16  ## below this the cache key stops distinguishing
const MAX_CONTEXT_CHARS := 400
const MAX_LOG := 500

## Tuning counters, read by the corpus/latency report.
var requests := 0
var cached_hits := 0
var blocks := 0
var passes := 0
var errors := 0
var ms_total := 0
var ms_max := 0
## One entry per answered question (category, match, verdict, latency, error).
var verdict_log: Array[Dictionary] = []

var _ready := false
var _max_tokens := DEFAULT_MAX_TOKENS
var _sampling := {}
var _dose := {}
var _system := ""
var _question := ""
var _asks := {}
var _yes := PackedStringArray()
var _no := PackedStringArray()
var _flags := {}  ## category -> Array[RegEx]
var _max_text := MAX_TEXT_CHARS
var _context := 80
var _hold_timeout_ms := 900
## (category, matched) -> {verdict, block}. Capped FIFO.
var _verdicts := {}
var _verdict_order: Array[String] = []


## Load and validate classifier.json. Returns false on any shape error, an
## inert flag group (its own probes are not matched) or a bad prompt template:
## the caller closes the whole filter rather than shipping an unasked question.
func load_data(path: String) -> bool:
	_reset()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return false
	return _build(data as Dictionary)


func _build(data: Dictionary) -> bool:
	if not _build_limits(data) or not _build_prompt(data) or not _build_answers(data):
		return false
	if not _build_flags(data.get("flags")):
		return false
	if not _self_check(data.get("probes")):
		return false
	_ready = true
	return true


func _build_limits(data: Dictionary) -> bool:
	var tokens := _as_int(data.get("max_tokens", DEFAULT_MAX_TOKENS))
	if tokens < 1 or tokens > MAX_TOKENS_LIMIT:
		return false
	_max_tokens = tokens
	var raw_sampling: Variant = data.get("sampling", {})
	if not raw_sampling is Dictionary:
		return false
	_sampling = (raw_sampling as Dictionary).duplicate()
	var raw_dose: Variant = data.get("dose", {})
	if not raw_dose is Dictionary:
		return false
	_dose = (raw_dose as Dictionary).duplicate()
	var text_chars := _as_int(data.get("max_text_chars", MAX_TEXT_CHARS))
	var context := _as_int(data.get("context_chars", 80))
	var timeout := _as_int(data.get("hold_timeout_ms", 900))
	if text_chars < 0 or timeout < 0:
		return false
	## A zero/near-zero window collapses the cache key back to the matched span
	## and silently reintroduces the knife / knife-and-fork collision (SAF-11).
	if context < MIN_CONTEXT_CHARS or context > MAX_CONTEXT_CHARS:
		return false
	_max_text = clampi(text_chars, 32, 2000)
	_context = context
	_hold_timeout_ms = clampi(timeout, 1, 60000)
	return true


## JSON in this Godot build hands back floats for integral numbers, so every
## numeric limit accepts int, an integral float, or a numeric string.
func _as_int(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value) if is_equal_approx(float(value), roundf(float(value))) else -1
	if value is String and String(value).is_valid_int():
		return int(String(value))
	return -1


func _build_prompt(data: Dictionary) -> bool:
	var raw_system: Variant = data.get("system")
	var raw_question: Variant = data.get("question")
	var raw_asks: Variant = data.get("asks")
	if not raw_system is String or String(raw_system).strip_edges().is_empty():
		return false
	if not raw_question is String or not String(raw_question).contains("{text}"):
		return false
	if not raw_asks is Dictionary:
		return false
	_system = String(raw_system)
	_question = String(raw_question)
	for cat in raw_asks:
		if not raw_asks[cat] is String or String(raw_asks[cat]).strip_edges().is_empty():
			return false
		_asks[String(cat)] = String(raw_asks[cat])
	return true


func _build_answers(data: Dictionary) -> bool:
	var raw: Variant = data.get("answers")
	if not raw is Dictionary:
		return false
	var yes := _answer_words(raw.get("yes"))
	var no := _answer_words(raw.get("no"))
	if yes.is_empty() or no.is_empty():
		return false
	for word in yes:
		if no.has(word):
			return false
	_yes = yes
	_no = no
	return true


func _answer_words(raw: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not raw is Array or (raw as Array).is_empty():
		return out
	for word in raw:
		if not word is String or String(word).strip_edges().is_empty():
			return PackedStringArray()
		var lowered := String(word).strip_edges().to_lower()
		if not out.has(lowered):
			out.append(lowered)
	return out


func _build_flags(raw: Variant) -> bool:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return false
	for cat in raw:
		if not _asks.has(String(cat)):
			return false
		var patterns: Variant = raw[cat]
		if not patterns is Array or (patterns as Array).is_empty():
			return false
		var compiled: Array[RegEx] = []
		for pattern in patterns:
			if not pattern is String:
				return false
			var re := RegEx.new()
			if re.compile(String(pattern)) != OK:
				return false
			compiled.append(re)
		_flags[String(cat)] = compiled
	return true


## CODE-16 pattern: every flagged category must match its own probe rows, so a
## compiled-but-inert flag group (a typo'd lookahead, a mis-escaped class) fails
## the load closed instead of shipping a silent hole.
func _self_check(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	for cat in _flags:
		var rows: Variant = raw.get(cat)
		if not rows is Array or (rows as Array).is_empty():
			return false
		for row in rows:
			if not row is String or String(row).strip_edges().is_empty():
				return false
			if _flag_matches(String(row).to_lower(), cat).is_empty():
				return false
	return true


func is_ready() -> bool:
	return _ready


func hold_timeout_ms() -> int:
	return _hold_timeout_ms


func max_tokens() -> int:
	return _max_tokens


func context_chars() -> int:
	return _context


## Every flagged category with a regex list, for the corpus composition table.
func categories() -> Array:
	var out: Array = _flags.keys()
	out.sort()
	return out


## All raw flag matches for `view` (an already normalized, lowercased view),
## in text order. `is_open(cat)` skips a category whose gate is open (a yes
## verdict could not block there); `is_negated(cat, start, end, matched)`
## applies the list's clause-scoped negation guard to the flag so a negated
## line never spends a request.
func flag_matches(view: String, is_open: Callable, is_negated: Callable) -> Array:
	var out: Array = []
	for cat in _flags:
		if bool(is_open.call(cat)):
			continue
		for re: RegEx in _flags[cat]:
			for rm: RegExMatch in re.search_all(view):
				var start := rm.get_start()
				var end := rm.get_end()
				if end <= start:
					continue
				var matched := view.substr(start, end - start)
				if bool(is_negated.call(cat, start, end, matched)):
					continue
				(
					out
					. append(
						{
							"s": start,
							"e": end,
							"cat": cat,
							"match": matched,
							"key": verdict_key(cat, matched),
						}
					)
				)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["s"] < b["s"])
	return out


func _flag_matches(view: String, cat: String) -> Array:
	var out: Array = []
	for re: RegEx in _flags.get(cat, []):
		for rm: RegExMatch in re.search_all(view):
			out.append([rm.get_start(), rm.get_end()])
	return out


## Cache key: category plus the normalized match. Kept short so a pathological
## regex cannot grow the cache key unboundedly.
static func verdict_key(cat: String, matched: String) -> String:
	var parts := matched.to_lower().split(" ", false)
	var joined := " ".join(parts)
	return "%s|%s" % [cat, joined.substr(0, MAX_TEXT_CHARS)]


## The yes/no request body for one flag. `context` is the clause window the
## model sees (never the whole beat: 4B models over-answer a long prompt).
func build_request(flag: Dictionary, context: String, ctx: Dictionary) -> Dictionary:
	var cat := String(flag["cat"])
	var ask := String(_asks.get(cat, ""))
	var text := context.strip_edges()
	if text.length() > _max_text:
		var at := text.find(String(flag["match"]))
		var from := maxi(0, at - _context) if at >= 0 else 0
		text = text.substr(from, _max_text)
	var question := _question.replace("{text}", text).replace("{ask}", ask)
	return {
		"key": String(flag["key"]),
		"category": cat,
		"match": String(flag["match"]),
		"text": text,
		"system": _system,
		"question": question,
		"max_tokens": _max_tokens,
		"sampling": _sampling.duplicate(),
		"dose": _dose.duplicate(),
		"ctx": ctx.duplicate(),
	}


## Interpret a backend result into {ok, verdict, raw, latency_ms, error}. A
## result that is not a decisive yes/no is an error, which the caller treats as
## a block (fail closed).
func interpret(result: Variant) -> Dictionary:
	var out := {"ok": false, "verdict": "", "raw": "", "latency_ms": 0}
	if not result is Dictionary:
		out["error"] = {"code": "bad_result", "message": "classifier returned no dictionary"}
		return out
	var dict: Dictionary = result
	out["raw"] = String(dict.get("raw", ""))
	var raw_latency: Variant = dict.get("latency_ms", 0)
	if raw_latency is int:
		out["latency_ms"] = maxi(0, int(raw_latency))
	if not bool(dict.get("ok", false)):
		var err: Variant = dict.get("error")
		out["error"] = err if err is Dictionary else {"code": "classifier_error", "message": ""}
		return out
	var verdict := SafetyClassifierBackend.parse_verdict(out["raw"], _yes, _no)
	if verdict.is_empty():
		out["error"] = {"code": "unparseable_answer", "message": out["raw"].substr(0, 32)}
		return out
	out["ok"] = true
	out["verdict"] = verdict
	return out


## Remember a verdict. Only the answer and its category are stored: whether a
## "yes" bars anything is decided against the content gate in force when the
## text is displayed (CODE-1/SAF-2), never frozen here.
func remember(key: String, category: String, verdict: String) -> void:
	if verdict == "yes":
		blocks += 1
	elif verdict == "no":
		passes += 1
	else:
		errors += 1
	_verdicts[key] = {"verdict": verdict, "category": category}
	_verdict_order.append(key)
	while _verdict_order.size() > MAX_VERDICTS:
		_verdicts.erase(_verdict_order.pop_front())


func cached(key: String) -> Dictionary:
	var hit: Variant = _verdicts.get(key, {})
	return (hit as Dictionary).duplicate() if hit is Dictionary else {}


func has_cached(key: String) -> bool:
	return _verdicts.has(key)


func note_cached_hit() -> void:
	cached_hits += 1


func note_request(_latency_ms := 0) -> void:
	requests += 1


func note_latency(latency_ms: int) -> void:
	ms_total += latency_ms
	ms_max = maxi(ms_max, latency_ms)


func note_verdict(entry: Dictionary) -> void:
	verdict_log.append(entry)
	while verdict_log.size() > MAX_LOG:
		verdict_log.pop_front()


func stats() -> Dictionary:
	return {
		"requests": requests,
		"cached_hits": cached_hits,
		"blocks": blocks,
		"passes": passes,
		"errors": errors,
		"verdicts": _verdicts.size(),
		"ms_total": ms_total,
		"ms_max": ms_max,
		"ms_avg": float(ms_total) / maxf(1.0, float(requests)),
	}


func _reset() -> void:
	_ready = false
	_max_tokens = DEFAULT_MAX_TOKENS
	_sampling = {}
	_dose = {}
	_system = ""
	_question = ""
	_asks = {}
	_yes = PackedStringArray()
	_no = PackedStringArray()
	_flags = {}
	_max_text = MAX_TEXT_CHARS
	_context = 80
	_hold_timeout_ms = 900
	_verdicts = {}
	_verdict_order = []
	verdict_log = []
	requests = 0
	cached_hits = 0
	blocks = 0
	passes = 0
	errors = 0
	ms_total = 0
	ms_max = 0
