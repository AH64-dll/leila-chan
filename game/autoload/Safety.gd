class_name SafetyFilter
extends Node
## Safety filter v0 (docs/02 §8).
signal redacted(category: String, matched_text: String, source: String)

const LISTS_PATH := "res://data/safety/filter_lists.json"
const LOG_PATH := "user://debug/redactions.jsonl"
const REDACT_CHAR := "█"
const FALLBACK_BARS := "████████████"
const _TAIL_CHARS := 64  ## emitted context kept for the negation guard
const _MAX_PENDING := 4096
const _MIN_HOLDBACK := 16
const _MAX_LOG := 500
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
var redaction_log: Array[Dictionary] = []

var _lists_ok := false
var _rules := {}  ## category -> {action, negation_guard, player_exempt, plain_view}
var _idx_plain := {}  ## compact first char -> [[category, compact phrase], ...]
var _idx_leet := {}
var _safe_idx := {}  ## narrow benign look-alikes that may contain a blocked span
var _regexes := {}  ## category -> Array[RegEx]
var _hold_res: Array[RegEx] = []
var _obf_res: Array[RegEx] = []
var _negation_re := RegEx.new()
var _neg_exempt := PackedStringArray()
var _neg_gap_allow := {}
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


func _ready() -> void:
	_load_lists()


func is_ready() -> bool:
	return _lists_ok


func reload(path := LISTS_PATH) -> bool:
	_load_lists(path)
	return _lists_ok


func configure(ctx: Dictionary) -> void:
	for key in ctx:
		_default_ctx[key] = ctx[key]


func begin_say(ctx: Dictionary = {}) -> void:
	_ctx = _resolve_ctx(ctx)
	_pending = ""
	_in_beat = true


## Marks the end of one model utterance (a full reply). The next beat then
## starts with no history, so two different replies are never matched as one
## phrase (CODE-2/CODE-14). Beats *inside* one utterance keep the history,
## which is what catches `"i want to "` + `"die."` split by an end-of-beat
## emission. The production callers are the Director's SaySafetyGate: it calls
## `end_utterance()` from `_start_turn` when a new reply begins (CODE-19) and
## from `replay_turn` before a replayed reply re-streams (CODE-23/SAF-17).
func end_utterance() -> void:
	_history = ""


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
	return _drain()


func end_say() -> String:
	if not _in_beat:
		return ""
	_in_beat = false
	if not _lists_ok:
		_reset_beat()
		return FALLBACK_BARS
	var combined := _match_text()
	var start := _history.length()
	var views: Dictionary = _text.views(combined)
	var spans := _collect_spans(combined, views, "", _ctx)
	var emitted := _apply_spans(combined, spans, start, combined.length(), "say")
	_history = _window(combined)
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
## plus `_TAIL_CHARS` of context for the negation guard (CODE-18). Clause
## breaks no longer prune the carry — the compact view strips the
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
	var keep := _holdback + _TAIL_CHARS
	if folded.length() > keep:
		folded = folded.substr(folded.length() - keep)
	return folded


func _reset_beat() -> void:
	_in_beat = false
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
	_neg_exempt.clear()
	_neg_gap_allow.clear()
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
## self-check is itself part of the contract.
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
				if String(span["cat"]) == cat:
					hit = true
					break
			if not hit:
				return false
	return true


func _fail(msg: String) -> void:
	push_error("Safety: " + msg + " — filter closed")
	_reset_state()


func _build_lists(data: Dictionary) -> bool:
	_probe_rows = data.get("probes", {})
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
	if not _build_negation_terms(data.get("negation_terms")):
		return false
	if not _build_negation_exempt(data.get("negation_exempt", [])):
		return false
	return _build_negation_gap(data.get("negation_gap_allow"))


func _build_negation_terms(terms: Variant) -> bool:
	if not terms is Array or terms.is_empty():
		return false
	var parts := PackedStringArray()
	for term in terms:
		if not term is String or String(term).is_empty():
			return false
		parts.append(String(term))
	return _negation_re.compile("\\b(" + "|".join(parts) + ")\\b") == OK


func _build_negation_exempt(exempt: Variant) -> bool:
	if not exempt is Array:
		return false
	for entry in exempt:
		if not entry is String:
			return false
		_neg_exempt.append(_text.normalize(String(entry), false))
	return true


func _build_negation_gap(gap_allow: Variant) -> bool:
	if not gap_allow is Array or gap_allow.is_empty():
		return false
	for word in gap_allow:
		if not word is String or String(word).is_empty():
			return false
		_neg_gap_allow[String(word).to_lower()] = true
	return true


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


func _drain() -> String:
	var combined := _match_text()
	var start := _history.length()
	var views: Dictionary = _text.views(combined)
	var spans := _collect_spans(combined, views, "", _ctx)
	var cut := _safe_cut(combined, views, spans, start)
	if cut <= start:
		return ""
	var emitted := _apply_spans(combined, spans, start, cut, "say")
	_pending = combined.substr(cut)
	_history = _window(combined.substr(0, cut))
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
			if _rules[cat]["negation_guard"] and _negated(view, tail, m["s"], matched, cat):
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


func _negated(view: String, tail: String, start: int, matched: String, cat: String) -> bool:
	for entry in _neg_exempt:
		if matched.contains(entry):
			return false
	var combined := tail + view
	var at := start + tail.length()
	var from := maxi(0, at - _TAIL_CHARS)
	var window := combined.substr(from, at - from)
	var cut := -1
	for i in window.length():
		if _text.is_clause_break(window.unicode_at(i)):
			cut = i
	var clause := window.substr(cut + 1)
	var trailing_clause := view.substr(start + matched.length())
	if trailing_clause.contains("?"):
		return false
	var clause_end := trailing_clause.length()
	for i in trailing_clause.length():
		if _text.is_clause_break(trailing_clause.unicode_at(i)):
			clause_end = i
			break
	var full_clause := clause + matched + trailing_clause.substr(0, clause_end)
	var lower_clause := clause.to_lower().strip_edges()
	var negations := _negation_re.search_all(clause)
	var inv_re := (
		"(\\b(don'?t|won'?t|can'?t|couldn'?t|wouldn'?t|" + "shouldn'?t)\\s+you|how\\s+come\\s+you)"
	)
	if RegEx.create_from_string(inv_re).search(lower_clause) != null:
		return false
	if negations.size() != 1:
		return false
	var negator: RegExMatch = negations[0]
	if clause.substr(0, negator.get_start()).strip_edges().ends_with("why"):
		return false
	var gap := clause.substr(negator.get_end())
	gap = _strip_category_spans(gap, cat)
	return _gap_is_allowed(gap)


func _gap_is_allowed(gap: String) -> bool:
	var words := _words(gap)
	if words.is_empty():
		return gap.strip_edges().is_empty()
	for word in words:
		if not _neg_gap_allow.has(word):
			return false
	var residual := gap.to_lower()
	for word in words:
		residual = residual.replace(word, " ")
	for i in residual.length():
		if SafetyText.is_word_char(residual.unicode_at(i)):
			return false
	return true


func _strip_category_spans(gap: String, cat: String) -> String:
	if gap.strip_edges().is_empty():
		return gap
	var plain_view: bool = _rules[cat]["plain_view"]
	var views: Dictionary = _text.views(gap)
	var view: String = views["plain"] if plain_view else views["leet"]
	var compact: String = views["cp"] if plain_view else views["cl"]
	var cmap: PackedInt32Array = views["pmap"] if plain_view else views["map"]
	var index: Dictionary = _idx_plain if plain_view else _idx_leet
	var spans := _phrase_matches(compact, cmap, index, view, cat)
	if spans.is_empty():
		return gap
	var out := ""
	var pos := 0
	for span in spans:
		if span[0] < pos:
			continue
		out += view.substr(pos, span[0] - pos)
		pos = span[1]
	if pos < view.length():
		out += view.substr(pos)
	return out


func _words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if (c >= 0x61 and c <= 0x7A) or c == 0x27:
			current += String.chr(c)
		elif not current.is_empty():
			out.append(current)
			current = ""
	if not current.is_empty():
		out.append(current)
	return out


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
		for cat in span.get("cats", PackedStringArray([span["cat"]])):
			_record(String(cat), raw.substr(s, e - s), source)
		pos = e
	if pos < cut:
		out += raw.substr(pos, cut - pos)
	return out


func _record(cat: String, matched: String, source: String) -> void:
	var logged_matched := matched
	if cat == "personal_data":
		logged_matched = "[PERSONAL_DATA_REDACTED_LEN_%d]" % matched.length()
	var entry := {
		"ts": Time.get_unix_time_from_system(),
		"category": cat,
		"matched": logged_matched,
		"source": source,
		"stage": int(_ctx.get("stage", -1)),
		"content_level": String(_ctx.get("content_level", "")),
	}
	redaction_log.append(entry)
	if redaction_log.size() > _MAX_LOG:
		redaction_log.pop_front()
	emit_signal("redacted", cat, matched, source)
	_glitch()
	if OS.is_debug_build():
		_append_log(entry)


func _glitch() -> void:
	if is_inside_tree():
		var fx := get_node_or_null("/root/FX")
		if fx != null and fx.has_method("request"):
			fx.call("request", "glitch")


func _append_log(entry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://debug")
	if FileAccess.file_exists(LOG_PATH):
		var check_f := FileAccess.open(LOG_PATH, FileAccess.READ)
		if check_f != null and check_f.get_length() > 500000:
			check_f.close()
			var dir := DirAccess.open("user://debug")
			if dir != null:
				dir.remove(LOG_PATH)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(entry))
