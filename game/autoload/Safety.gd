class_name SafetyFilter
extends Node
## Safety filter v0 (docs/02 §8).
signal redacted(category: String, matched_text: String, source: String)
## Late classifier verdict: display `text` for `beat_index` (released text or
## the fail-closed bars) — the beat can no longer receive it synchronously.
signal hold_released(beat_index: int, text: String)

const LISTS_PATH := "res://data/safety/filter_lists.json"
const CLASSIFIER_PATH := "res://data/safety/classifier.json"
const REDACT_CHAR := "█"
const FALLBACK_BARS := "████████████"
const _MAX_PENDING := 4096
const _MIN_HOLDBACK := 16
const _PLAIN_CATEGORY := "personal_data"
const _SCRIPT_CAT := "unsupported_script"
const _OBFUSCATION_CAT := "obfuscation"
const _REQUIRED_ACTIONS := {
	"harm_to_player": "hard_block",
	"self_harm_her": "gated",
	"threat_to_player": "gated",
	"slur_hate": "hard_block",
	"sexual": "hard_block",
	"personal_data": "hard_block",
	"real_disorder": "hard_block",
}
const _VALID_LEVELS: Array[String] = ["calmer", "full"]
const _VALID_ACTIONS: Array[String] = ["hard_block", "gated"]
## Redaction ring for tuning; the file/debug plumbing is SafetyRedactionLog.gd.
var redaction_log: Array[Dictionary]:
	get:
		return _log.entries
## Transport/hold API: `classifier_gate.set_backend(transport)`,
## `.set_config_provider(cb)`, `.stats()`, `.pending()`; null only before the
## lists load (the filter is closed then).
var classifier_gate: SafetyClassifierGate:
	get:
		return _gate

var _log := SafetyRedactionLog.new()

var _lists_ok := false
var _rules := {}  ## category -> {action, negation_guard, player_exempt, plain_view}
var _idx_plain := {}  ## compact first char -> [[category, compact phrase], ...]
var _idx_leet := {}
var _safe_idx := {}  ## narrow benign look-alikes that may contain a blocked span
var _regexes := {}  ## category -> Array[RegEx]
var _hold_res: Array[RegEx] = []
var _obf_res: Array[RegEx] = []
## The clause-scoped negation guard (SafetyNegation.gd) and the phrase index
## callback it needs to strip a category's own phrases out of the negation gap.
var _negation := SafetyNegation.new()
var _gap_spans_cb := Callable()
var _script_ranges: Array[Array] = []
var _text := SafetyText.new()  ## normalization/compact views (SafetyText.gd)
var _gate_stage := 4
var _probe_rows := {}  ## category -> probe strings the loader must actually catch
var _gate_level := "full"
var _holdback := _MIN_HOLDBACK
var _max_phrase := 0

var _default_ctx := {"stage": 0, "content_level": "", "player_terms": [], "username": ""}

var _in_beat := false
var _ctx: Dictionary = {}
var _pending := ""
## Cross-beat state (CODE-2/CODE-14): the tail of everything already displayed
## in this utterance. It is matched as part of the next beat's text, so a phrase
## split across two say beats ("i want to " + "die.") is still caught and its
## continuation barred, and the negation guard can read back into it.
## `end_utterance()` clears it, so two different replies are never glued.
var _history := ""

## Classifier tier: `_cls` data/prompt/cache, `_gate` hold + in-flight request.
var _cls: SafetyClassifier = null
var _gate: SafetyClassifierGate = null
var _beat_closed := false
var _draining := false
var _drain_again := false


func _ready() -> void:
	_load_lists()


func is_ready() -> bool:
	return _lists_ok


## The classifier transport owns worker threads, so it is cancelled and joined
## at teardown exactly like `LLM._shutdown()` (CODE-5): a thread left running at
## quit would keep calling back into a freed gate. Blocking here is correct.
func _exit_tree() -> void:
	_shutdown_transport()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_shutdown_transport()


## Guarded in the gate, so the two teardown paths and a test's explicit call are
## all safe to reach in any order.
func _shutdown_transport() -> void:
	if _gate != null:
		_gate.shutdown()


func reload(path := LISTS_PATH) -> bool:
	_load_lists(path)
	return _lists_ok


func configure(ctx: Dictionary) -> void:
	for key in ctx:
		_default_ctx[key] = ctx[key]


func begin_say(ctx: Dictionary = {}) -> void:
	if _gate != null and _gate.hold_active():
		flush_hold("beat_boundary")
	if _gate != null:
		_gate.begin_beat()
	_ctx = _resolve_ctx(ctx)
	_pending = ""
	_in_beat = true
	_beat_closed = false


## Marks the end of one model utterance (a full reply). The next beat then
## starts with no history, so two different replies are never matched as one
## phrase (CODE-2/CODE-14). Beats *inside* one utterance keep the history,
## which is what catches `"i want to "` + `"die."` split by an end-of-beat
## emission. The production callers are the Director's SaySafetyGate: it calls
## `end_utterance()` from `_start_turn` when a new reply begins (CODE-19) and
## from `replay_turn` before a replayed reply re-streams (CODE-23/SAF-17).
func end_utterance() -> void:
	if _gate != null and _gate.hold_active():
		flush_hold("utterance_end")
	_history = ""
	## The reply boundary owns the close now that `flush_hold` no longer resets
	## the beat (CODE-3), so a beat that timed out can never leak its ctx or its
	## `beat_index` into the next reply.
	_reset_beat()


func say_chunk(chunk: String) -> String:
	if not _in_beat:
		begin_say()
	if not _lists_ok:
		return ""
	_pending = _text.collapse_ws(_pending + SafetyText.sanitize(chunk))
	if _pending.length() > _MAX_PENDING:
		var dropped_len := _pending.length()
		_reset_beat()
		_record("filter_error", "overflow_dropped_%d" % dropped_len, "say")
		return FALLBACK_BARS.repeat(maxi(1, dropped_len / 12))
	if _gate != null and _gate.expired(Time.get_ticks_msec()):
		flush_hold("timeout")
	return _drain()


func end_say() -> String:
	if not _in_beat:
		return ""
	_in_beat = false
	_beat_closed = true
	if not _lists_ok:
		_reset_beat()
		_beat_closed = false
		return FALLBACK_BARS
	var emitted := _drain(true)
	if _gate == null or not _gate.hold_active():
		_reset_beat()
	return emitted


## The text a match may span: the already-displayed window plus this beat's text,
## contiguous (CODE-2/CODE-14). Contiguity is the point — a phrase split across
## two beats (`"i want to "` + `"die."`, or `"kil"` + `"l yourself"`) must match
## exactly as it would one-shot, and the negation guard reads back into the
## window so `don't let anyone tell you to …` keeps its negator across beats.
## Only text after the window is ever emitted.
func _match_text() -> String:
	return _history + _pending


## Trim a displayed-text window to what a later match can still need. The
## window is length-bounded only: `_holdback` characters of matching surface
## plus `SafetyNegation.TAIL_CHARS` of context for the negation guard (CODE-18).
## Clause breaks no longer prune the carry — the compact view strips the
## separator-class clause breaks (`,;:!?—–…`) between letters anyway, so
## pruning them here only let a phrase split across a beat boundary at one of
## those characters escape (`"please kill,"` + `"yourself."`); dropping the
## prune also keeps streamed output identical to the one-shot result, which
## always sees the whole text. Nothing crosses a redaction either way: the
## span is barred before emission, so the next beat only ever contributes its
## own continuation. `end_utterance()` (reply boundary, CODE-19) is the only
## hard cut. Model-typed `█`s fold to `.` so a fake bar cannot lodge in the
## window as an unmatchable wall.
func _window(displayed: String) -> String:
	var folded := displayed.replace(REDACT_CHAR, ".")
	var keep := _holdback + SafetyNegation.TAIL_CHARS
	if folded.length() > keep:
		folded = folded.substr(folded.length() - keep)
	return folded


func _reset_beat() -> void:
	_in_beat = false
	_beat_closed = false
	_pending = ""


func filter_text(text: String, ctx: Dictionary = {}) -> Dictionary:
	if not _lists_ok:
		return {
			"text": FALLBACK_BARS,
			"redacted": true,
			"categories": PackedStringArray(["filter_error"]),
		}
	var saved_ctx := _ctx
	_ctx = _resolve_ctx(ctx)
	var clean := _text.collapse_ws(SafetyText.sanitize(text))
	var views: Dictionary = _text.views(clean)
	var spans := _collect_spans(clean, views, "", _ctx)
	if _gate != null:
		spans = _gate.resolve_whole(spans, views, _ctx)
	var cats := PackedStringArray()
	for span in spans:
		for cat in span.get("cats", PackedStringArray([span["cat"]])):
			if not cats.has(cat):
				cats.append(cat)
	var filtered := _apply_spans(clean, spans, 0, clean.length(), "text")
	_ctx = saved_ctx
	return {"text": filtered, "redacted": not spans.is_empty(), "categories": cats}


func get_pending_length() -> int:
	return _pending.length()


## Longest phrase plus one, in characters: the fixed prefix the streamer keeps
## pending so no match can complete after a partial emission.
func get_holdback() -> int:
	return _holdback


func _load_lists(path := LISTS_PATH) -> void:
	_reset_state()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot open lists at %s" % path)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		_fail("lists at %s failed to parse" % path)
		return
	if not _build_lists(data):
		_fail("lists at %s are invalid" % path)


func _reset_state() -> void:
	_lists_ok = false
	_rules.clear()
	_idx_plain.clear()
	_idx_leet.clear()
	_safe_idx.clear()
	_regexes.clear()
	_hold_res.clear()
	_obf_res.clear()
	_negation = SafetyNegation.new()
	_script_ranges.clear()
	_text = SafetyText.new()
	_gate_stage = 4
	_probe_rows = {}
	_gate_level = "full"
	_holdback = _MIN_HOLDBACK
	_max_phrase = 0


## CODE-16: loaders validate shape, not effect. After every list is built, each
## category's own probe rows (from the lists file) must actually be caught, so a
## regex or phrase group that compiles but never matches — a typo'd lookahead,
## `{99999,}`, a mis-folded phrase — fails the load closed instead of silently
## shipping a hole. A category without a probe row fails too: coverage of the
## self-check is itself part of the contract. A row passes only when *its own*
## category produced the hit: overlapping arms merge into one span that reports
## every category in `cats` (`kill all the jews` is threat + slur at once), so
## reading the span's primary `cat` alone let a sibling mask a missing rule
## (SAF-19 r6: the slur probe read as threat-only and the load stayed green).
func _self_check() -> bool:
	if not _probe_rows is Dictionary:
		return false
	for cat in _REQUIRED_ACTIONS:
		var rows: Variant = _probe_rows.get(cat)
		if not rows is Array or (rows as Array).is_empty():
			return false
		for row in rows:
			if not row is String or String(row).strip_edges().is_empty():
				return false
			var text := _text.collapse_ws(SafetyText.sanitize(String(row)))
			var views: Dictionary = _text.views(text)
			var spans := _collect_spans(text, views, "", {"stage": 0, "content_level": "full"})
			var hit := false
			for span in spans:
				if _span_has_cat(span, cat):
					hit = true
					break
			if not hit:
				return false
	return true


func _span_has_cat(span: Dictionary, cat: String) -> bool:
	if String(span.get("cat", "")) == cat:
		return true
	var cats: Variant = span.get("cats", PackedStringArray())
	return cats is PackedStringArray and (cats as PackedStringArray).has(cat)


func _fail(msg: String) -> void:
	push_error("Safety: " + msg + " — filter closed")
	_reset_state()


func _build_lists(data: Dictionary) -> bool:
	_probe_rows = data.get("probes", {})
	_cls = SafetyClassifier.new()
	_gate = SafetyClassifierGate.new()
	_gate.setup(_cls, Callable(self, "_category_open"), Callable(self, "_flag_negated"))
	_gate.settled.connect(_on_classifier_settled)
	if not _cls.load_data(CLASSIFIER_PATH):
		return false
	if (
		not _valid_version(data.get("version", 0))
		or not _build_gate(data.get("gate"))
		or not _build_negation(data)
		or not _build_categories(data.get("categories"))
		or not _build_holds(data)
		or not _build_obfs(data)
		or not _build_safe(data)
		or not _build_guard(data)
		or not _self_check()
	):
		return false
	_holdback = maxi(_MIN_HOLDBACK, _max_phrase + 1)
	_lists_ok = true
	return true


func _valid_version(value: Variant) -> bool:
	if value is int:
		return value >= 1
	if value is float:
		return is_equal_approx(value, roundf(value)) and int(value) >= 1
	if value is String and String(value).is_valid_int():
		return int(String(value)) >= 1
	return false


func _build_gate(gate: Variant) -> bool:
	if not gate is Dictionary:
		return false
	var raw_stage: Variant = gate.get("min_stage")
	var raw_level: Variant = gate.get("content_level")
	var valid_stage := (
		raw_stage is int or (raw_stage is float and is_equal_approx(raw_stage, roundf(raw_stage)))
	)
	if not valid_stage or not raw_level is String:
		return false
	_gate_stage = int(raw_stage)
	_gate_level = String(raw_level)
	return _gate_stage >= 0 and _gate_stage <= 5 and _gate_level == "full"


func _build_negation(data: Dictionary) -> bool:
	_gap_spans_cb = Callable(self, "_phrase_spans")
	return _negation.configure(
		data.get("negation_terms"), data.get("negation_exempt", []), data.get("negation_gap_allow")
	)


func _build_categories(categories: Variant) -> bool:
	if not categories is Dictionary:
		return false
	for required in _REQUIRED_ACTIONS:
		if not categories.has(required) or not categories[required] is Dictionary:
			return false
	for cat in categories:
		var spec: Variant = categories[cat]
		if not spec is Dictionary:
			return false
		if not _build_category(String(cat), spec as Dictionary):
			return false
	return true


func _build_category(cat: String, spec: Dictionary) -> bool:
	var meta := _category_meta(cat, spec)
	if meta.is_empty():
		return false
	var phrases: Variant = spec.get("phrases", [])
	var patterns: Variant = spec.get("regex", [])
	if not phrases is Array or not patterns is Array:
		return false
	if phrases.is_empty() and patterns.is_empty():
		return false
	_rules[cat] = meta
	var plain_view: bool = meta["plain_view"]
	return (
		_build_phrases(cat, phrases as Array, plain_view) and _build_regexes(cat, patterns as Array)
	)


func _category_meta(cat: String, spec: Dictionary) -> Dictionary:
	var raw_action: Variant = spec.get("action")
	var raw_plain: Variant = spec.get("plain_view", false)
	var raw_player: Variant = spec.get("player_exempt", false)
	var raw_guard: Variant = spec.get("negation_guard", false)
	if (
		not raw_action is String
		or not raw_plain is bool
		or not raw_player is bool
		or not raw_guard is bool
	):
		return {}
	var action := String(raw_action)
	if not _VALID_ACTIONS.has(action):
		return {}
	if _REQUIRED_ACTIONS.has(cat) and action != _REQUIRED_ACTIONS[cat]:
		return {}
	var plain_view := bool(raw_plain)
	if plain_view != (cat == _PLAIN_CATEGORY):
		return {}
	var player_exempt := bool(raw_player)
	if player_exempt and cat != _PLAIN_CATEGORY:
		return {}
	return {
		"action": action,
		"negation_guard": bool(raw_guard),
		"player_exempt": player_exempt,
		"plain_view": plain_view,
	}


func _build_phrases(cat: String, phrases: Array, plain_view: bool) -> bool:
	var index: Dictionary = _idx_plain if plain_view else _idx_leet
	for phrase in phrases:
		if not phrase is String or String(phrase).strip_edges().is_empty():
			return false
		var normalized := _text.normalize(String(phrase), not plain_view)
		_max_phrase = maxi(_max_phrase, normalized.length())
		var compact := _text.compact_key(normalized)
		if compact.is_empty():
			return false
		var first := compact.unicode_at(0)
		if not index.has(first):
			index[first] = []
		index[first].append([cat, compact])
	return true


func _build_regexes(cat: String, patterns: Array) -> bool:
	var compiled: Array[RegEx] = []
	for pattern in patterns:
		if not pattern is String:
			return false
		var re := RegEx.new()
		if re.compile(String(pattern)) != OK:
			return false
		compiled.append(re)
	_regexes[cat] = compiled
	return true


func _build_holds(data: Dictionary) -> bool:
	var holds: Variant = data.get("hold_patterns")
	if not holds is Array or holds.is_empty():
		return false
	for pattern in holds:
		if not pattern is String:
			return false
		var hre := RegEx.new()
		if hre.compile(String(pattern)) != OK:
			return false
		_hold_res.append(hre)
	return true


func _build_obfs(data: Dictionary) -> bool:
	var obfs: Variant = data.get("obfuscation_patterns", [])
	if not obfs is Array:
		return false
	for pattern in obfs:
		if not pattern is String:
			return false
		var ore := RegEx.new()
		if ore.compile(String(pattern)) != OK:
			return false
		_obf_res.append(ore)
	return true


func _build_safe(data: Dictionary) -> bool:
	var safe: Variant = data.get("safe_phrases", [])
	if not safe is Array:
		return false
	for phrase in safe:
		if not phrase is String or String(phrase).strip_edges().is_empty():
			return false
		var compact: String = _text.compact_key(_text.normalize(String(phrase), true))
		var first := compact.unicode_at(0)
		if not _safe_idx.has(first):
			_safe_idx[first] = []
		_safe_idx[first].append(["safe", compact])
	return true


func _build_guard(data: Dictionary) -> bool:
	var guard: Variant = data.get("script_guard")
	if not guard is Dictionary:
		return false
	var ranges: Variant = guard.get("ranges")
	if not ranges is Array or ranges.is_empty():
		return false
	for pair in ranges:
		if not _append_script_range(pair):
			return false
	return true


func _append_script_range(pair: Variant) -> bool:
	if not pair is Array or pair.size() != 2:
		return false
	var raw_first: Variant = pair[0]
	var raw_last: Variant = pair[1]
	var valid_first := (
		raw_first is int or (raw_first is float and is_equal_approx(raw_first, roundf(raw_first)))
	)
	var valid_last := (
		raw_last is int or (raw_last is float and is_equal_approx(raw_last, roundf(raw_last)))
	)
	if not valid_first or not valid_last:
		return false
	var first := int(raw_first)
	var last := int(raw_last)
	if first < 0 or last < first or last > 0x10FFFF:
		return false
	_script_ranges.append([first, last])
	return true


func _resolve_ctx(ctx: Dictionary) -> Dictionary:
	var merged := _default_ctx.duplicate()
	for key in ctx:
		merged[key] = ctx[key]
	var level := ""
	var raw_level: Variant = merged.get("content_level", "")
	var settings_lvl := _settings_level()
	if raw_level is String and _VALID_LEVELS.has(String(raw_level)):
		var caller_lvl := String(raw_level)
		if caller_lvl == "full" and settings_lvl != "" and settings_lvl != "full":
			level = settings_lvl
		else:
			level = caller_lvl
	elif raw_level is String and String(raw_level).is_empty():
		level = settings_lvl
	merged["content_level"] = level
	var stage := -1
	var raw_stage: Variant = merged.get("stage", 0)
	if raw_stage is int:
		stage = raw_stage
	elif raw_stage is float:
		stage = int(raw_stage)
	elif raw_stage is String and String(raw_stage).is_valid_int():
		stage = int(String(raw_stage))
	merged["stage"] = stage if stage >= 0 and stage <= 5 else -1
	var terms := PackedStringArray()
	for term in merged.get("player_terms", []):
		terms.append(_text.normalize(String(term), false))
	merged["player_terms"] = terms
	merged["username"] = _text.normalize(String(merged.get("username", "")), false)
	return merged


## Missing, unattached or invalid Settings must NOT imply full content.
func _settings_level() -> String:
	if not is_inside_tree():
		return ""
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return ""
	var level: Variant = settings.get("content_level")
	return String(level) if level is String and _VALID_LEVELS.has(String(level)) else ""


func _gate_open(cat: String, ctx: Dictionary) -> bool:
	if not _rules.has(cat):
		return false
	return (
		_rules[cat]["action"] == "gated"
		and int(ctx.get("stage", -1)) >= _gate_stage
		and String(ctx.get("content_level", "")) == _gate_level
	)


## Drain the beat until no verdict settles synchronously: a synchronous
## classifier answers inside `pump()`, so the scan re-runs instead of recursing.
func _drain(complete := false) -> String:
	if _draining:
		_drain_again = true
		return ""
	_draining = true
	var out := ""
	for _i in 8:  # bounded: one verdict can resolve more than one flag per call
		out += _drain_once(complete)
		if not _drain_again:
			break
		_drain_again = false
	_draining = false
	return out


func _drain_once(complete: bool) -> String:
	var combined := _match_text()
	var start := _history.length()
	var views: Dictionary = _text.views(combined)
	var spans := _collect_spans(combined, views, "", _ctx)
	var flags: Array = _gate.matched(views, spans) if _gate != null else []
	var cut := combined.length() if complete else _safe_cut(combined, views, spans, start)
	for flag in flags:
		cut = mini(cut, int(flag["s"]))
	cut = maxi(cut, start)
	var emitted := ""
	if cut > start:
		emitted = _apply_spans(combined, spans, start, cut, "say")
		_pending = combined.substr(cut)
		_history = _window(combined.substr(0, cut))
	if _gate == null:
		return emitted
	_gate.hold_for(flags, int(_ctx.get("beat_index", -1)))
	_gate.pump(combined, flags, _ctx, complete)
	return emitted


## Cut point (in view characters) past which nothing may be emitted yet.
## Bounded by the compact holdback (the longest phrase plus one, measured on the
## separator-free views so a generator cannot buy emission budget by padding a
## phrase prefix with separators), by trailing hold-pattern matches (unbounded
## regexes such as coordinates, phone numbers, emails) and by the start of any
## span that would otherwise be sliced in half. Never below `seam`: text an
## earlier beat already displayed cannot be recalled, only its continuation can
## be barred.
func _safe_cut(combined: String, views: Dictionary, spans: Array, seam: int) -> int:
	var cut := _compact_bound(views, seam)
	for hre in _hold_res:
		for rm in hre.search_all(views["plain"]):
			if rm.get_end() == views["plain"].length():
				cut = mini(cut, rm.get_start())
	var j := combined.length()
	while j > seam and _text.is_token_char(combined.unicode_at(j - 1)):
		j -= 1
	if j < combined.length():
		cut = mini(cut, j)
	for span in spans:
		if span["s"] >= cut:
			break
		if span["e"] > cut:
			cut = mini(cut, span["s"])
			break
	return maxi(cut, seam)


## View index of the earliest position the compact holdback still needs: the
## lower of the two compact views' `length - _holdback` positions, mapped back
## into the view. Holding on the compact views (not the raw text) is what makes
## `k...ill yourself` and `k#ll yourself` behave alike — separators between
## letters do not count toward the emission budget, so a phrase prefix padded
## with separators is still held rather than displayed.
func _compact_bound(views: Dictionary, seam: int) -> int:
	var cut := _bound_of(views["cl"], views["map"])
	return maxi(seam, mini(cut, _bound_of(views["cp"], views["pmap"])))


func _bound_of(compact: String, cmap: PackedInt32Array) -> int:
	var index := compact.length() - mini(_holdback, compact.length())
	if index <= 0 or cmap.is_empty():
		return 0
	return cmap[index]


## All redactable spans in the pending/complete text, merged and sorted.
## raw must be sanitized/collapsed; views came from _text.views(raw).
func _collect_spans(raw: String, views: Dictionary, tail: String, ctx: Dictionary) -> Array:
	var found: Array = []
	for cat in _rules:
		if _gate_open(cat, ctx):
			continue
		var plain_view: bool = _rules[cat]["plain_view"]
		var view: String = views["plain"] if plain_view else views["leet"]
		var compact: String = views["cp"] if plain_view else views["cl"]
		var cmap: PackedInt32Array = views["pmap"] if plain_view else views["map"]
		var index: Dictionary = _idx_plain if plain_view else _idx_leet
		for m in _phrase_matches(compact, cmap, index, view, cat):
			found.append({"s": m[0], "e": m[1], "cat": cat})
		if not plain_view:
			## The leet fold can consume a separator the plain view strips
			## (`kill@yourself`: `@` folds to `a` in leet, is a separator in
			## plain), so leet categories also match the plain compact view.
			for m in _phrase_matches(views["cp"], views["pmap"], index, view, cat):
				found.append({"s": m[0], "e": m[1], "cat": cat})
		for re in _regexes[cat]:
			for rm in re.search_all(view):
				found.append({"s": rm.get_start(), "e": rm.get_end(), "cat": cat})
	for ore in _obf_res:
		for rm in ore.search_all(views["plain"]):
			found.append({"s": rm.get_start(), "e": rm.get_end(), "cat": _OBFUSCATION_CAT})
	for span in _script_spans(raw):
		found.append(span)
	var safe_spans: Array = []
	if not _safe_idx.is_empty():
		for m in _phrase_matches(views["cl"], views["map"], _safe_idx, views["leet"], "safe"):
			safe_spans.append(m)
	var kept: Array = []
	for m in found:
		var cat: String = m["cat"]
		if (
			_rules.has(cat)
			and _rules[cat]["action"] == "gated"
			and _contained_in_any(m["s"], m["e"], safe_spans)
		):
			continue
		var matched := raw.substr(m["s"], m["e"] - m["s"])
		if _rules.has(cat):
			var view: String = views["plain"] if _rules[cat]["plain_view"] else views["leet"]
			matched = view.substr(m["s"], m["e"] - m["s"])
			if (
				_rules[cat]["negation_guard"]
				and _negation.is_negated(view, tail, m["s"], matched, cat, _gap_spans_cb)
			):
				continue
			if _rules[cat]["player_exempt"] and _is_player_typed(matched, ctx):
				continue
		m["text"] = matched
		kept.append(m)
	kept.sort_custom(func(a, b): return a["s"] < b["s"])
	var merged: Array = []
	for m in kept:
		if merged.is_empty() or m["s"] >= merged[-1]["e"]:
			m["cats"] = PackedStringArray([m["cat"]])
			merged.append(m)
		else:
			var target: Dictionary = merged[-1]
			target["e"] = maxi(target["e"], m["e"])
			target["text"] = raw.substr(target["s"], target["e"] - target["s"])
			## A span can be hit by several categories at once (`k.i.l.l.y.o.u.r.s.e.l.f`
			## is both a dotted-letter obfuscation and the phrase `kill yourself`);
			## every hit is reported, never only the first.
			if not target["cats"].has(m["cat"]):
				target["cats"].append(m["cat"])
	return merged


func _contained_in_any(start: int, end: int, spans: Array) -> bool:
	for span in spans:
		if start >= span[0] and end <= span[1]:
			return true
	return false


func _script_spans(raw: String) -> Array:
	var out: Array = []
	var i := 0
	while i < raw.length():
		if not _in_script_range(raw.unicode_at(i)):
			i += 1
			continue
		var start := i
		while i < raw.length() and _in_script_range(raw.unicode_at(i)):
			i += 1
		out.append({"s": start, "e": i, "cat": _SCRIPT_CAT})
	return out


func _in_script_range(c: int) -> bool:
	for pair in _script_ranges:
		if c >= pair[0] and c <= pair[1]:
			return true
	return false


func _phrase_matches(
	compact: String, cmap: PackedInt32Array, index: Dictionary, view: String, cat: String
) -> Array:
	var out: Array = []
	for i in compact.length():
		if not SafetyText.is_word_char(compact.unicode_at(i)):
			continue
		for entry in index.get(compact.unicode_at(i), []):
			if entry[0] != cat:
				continue
			var phrase: String = entry[1]
			var end := i + phrase.length()
			if end > compact.length() or compact.substr(i, phrase.length()) != phrase:
				continue
			var view_start: int = cmap[i]
			var view_end: int = cmap[end - 1] + 1
			if view_start > 0 and SafetyText.is_word_char(view.unicode_at(view_start - 1)):
				continue
			if view_end < view.length() and SafetyText.is_word_char(view.unicode_at(view_end)):
				continue
			out.append([view_start, view_end])
	return out


## The phrase spans a category's own lists produce in `gap`, in the view that
## category matches in. SafetyNegation calls this to strip the category's
## phrases out of a negation gap; the guard itself lives in SafetyNegation.gd.
func _phrase_spans(gap: String, cat: String) -> Dictionary:
	var plain_view: bool = _rules[cat]["plain_view"]
	var views: Dictionary = _text.views(gap)
	var view := String(views["plain"] if plain_view else views["leet"])
	var compact := String(views["cp"] if plain_view else views["cl"])
	var cmap: PackedInt32Array = views["pmap"] if plain_view else views["map"]
	var index: Dictionary = _idx_plain if plain_view else _idx_leet
	return {"view": view, "spans": _phrase_matches(compact, cmap, index, view, cat)}


func _is_player_typed(matched: String, ctx: Dictionary) -> bool:
	for term in ctx.get("player_terms", []):
		if String(term).contains(matched):
			return true
	var username := String(ctx.get("username", ""))
	return username != "" and username == matched


## Emit raw[start:cut] with every span wholly inside that range replaced by
## bars. Span offsets come from the normalized view; normalization is length
## preserving, so they line up with the raw string 1:1. `start` skips text that
## a previous beat already emitted (the cross-beat carry).
func _apply_spans(raw: String, spans: Array, start: int, cut: int, source: String) -> String:
	var out := ""
	var pos := start
	for span in spans:
		var s: int = span["s"]
		if s >= cut:
			break
		var e: int = mini(span["e"], cut)
		if e <= pos:
			continue
		out += raw.substr(pos, maxi(0, s - pos))
		out += REDACT_CHAR.repeat(e - maxi(s, pos))
		var extra := {"via": String(span.get("via", "regex"))}
		## A classifier block is logged with the verdict that released it to the
		## bar (SAF-5): the tuning trail needs the reason, not just the source.
		if span.has("verdict"):
			extra["verdict"] = String(span["verdict"])
		for cat in span.get("cats", PackedStringArray([span["cat"]])):
			_record(String(cat), raw.substr(s, e - s), source, extra.duplicate())
		pos = e
	if pos < cut:
		out += raw.substr(pos, cut - pos)
	return out


func _record(cat: String, matched: String, source: String, extra: Dictionary = {}) -> void:
	extra["stage"] = int(_ctx.get("stage", -1))
	extra["content_level"] = String(_ctx.get("content_level", ""))
	_log.record(cat, matched, source, extra)
	emit_signal("redacted", cat, matched, source)
	_log.glitch()


## Give up on an outstanding verdict: bar the held text now (fail closed) and
## announce it; the in-flight request still lands in the cache for tuning.
## Only the pending text is cleared — the beat lifecycle belongs to
## `begin_say`/`end_say` (CODE-3). Resetting it here threw away `_ctx` mid-beat,
## so a chunk after a timeout was rescanned at stage 0 with no `beat_index`
## (gated lines barred at stage 4/full, later releases emitted with beat -1 and
## dropped).
func flush_hold(reason := "flush") -> String:
	if _gate == null or not _gate.hold_active():
		return ""
	var beat := int(_gate.pending().get("beat_index", -1))
	var cat := _gate.flush(reason)
	var bars := REDACT_CHAR.repeat(_pending.length())
	if not bars.is_empty():
		_record(cat, _pending.substr(0, 80), "say", {"via": "classifier", "verdict": reason})
	_history = _window(_history + bars)
	_pending = ""
	if not bars.is_empty() and beat >= 0:
		hold_released.emit(beat, bars)
	return bars


## Resume the beat after a late verdict and push the newly displayable text.
func _on_classifier_settled() -> void:
	if _draining:
		_drain_again = true
		return
	if _gate == null or not _gate.hold_active():
		return
	var beat := int(_gate.pending().get("beat_index", -1))
	var out := _drain(_beat_closed)
	if _beat_closed and not _gate.hold_active():
		_reset_beat()
	if not out.is_empty() and beat >= 0:
		hold_released.emit(beat, out)


func _category_open(cat: String) -> bool:
	return _gate_open(cat, _ctx)


func _flag_negated(cat: String, start: int, _end: int, matched: String, view: String) -> bool:
	if not bool(_rules.get(cat, {}).get("negation_guard", false)):
		return false
	return _negation.is_negated(view, "", start, matched, cat, _gap_spans_cb)
