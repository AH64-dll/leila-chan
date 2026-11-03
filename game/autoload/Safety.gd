class_name SafetyFilter
extends Node
## Safety — output filter, redaction, content settings (docs/02 §8).
## Mandatory pre-pass on every displayed model text: say chunks stream through
## begin_say/say_chunk/end_say before the typewriter; complete texts (leaked
## inner, letters, diary, window titles) go through filter_text. Hard-block
## categories redact always; gated categories redact unless stage >= 4 and
## content_level == "full" (explicitly configured Settings; missing or invalid
## settings keep them closed). Fails closed: unloaded or invalid lists block all
## output.
##
## Streaming is holdback-based: text is emitted only once no phrase or regex
## match could still start, extend or be invalidated by future chunks. Redaction
## therefore happens at emission time, never eagerly, so a partially typed
## phrase is never bars-plus-leaked-suffix.
##
## Matching is obfuscation-resistant: zero-width and combining characters are
## removed, Latin/Greek/Cyrillic homoglyphs and common leet substitutions are
## folded, and phrases match on a whitespace-free compact view so split words
## ("ki\u200bll your\u200bself", "k1ll y0urself") still hit. Output in scripts
## we cannot scan (CJK, Cyrillic, Arabic, ...) is redacted as unsupported.

signal redacted(category: String, matched_text: String, source: String)

const LISTS_PATH := "res://data/safety/filter_lists.json"
const LOG_PATH := "user://debug/redactions.jsonl"
const REDACT_CHAR := "█"
const FALLBACK_BARS := "████████████"
const _TAIL_CHARS := 64  ## emitted context kept for the negation guard
const _MAX_PENDING := 4096
const _MIN_HOLDBACK := 16
const _MAX_LOG := 500
const _TOKEN_EXTRA := "@._+%'-"  ## chars that keep a trailing token open
const _CLAUSE_BREAKS := '.,;:!?—–…()[]{}"“”\n\r\t'
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
const _FOLD_SRC: Array[String] = [
	"'’‘",
	'"“”',
	"-–—",
	".…",
	"aàáâãäåāаαɑ",
	"bЬ",
	"cçсϲ",
	"dԁ",
	"eèéêëēеε",
	"gɡ",
	"hһ",
	"iìíîïīіιⅰ",
	"jјϳ",
	"kкκ",
	"lӏⅼ",
	"mмμ",
	"nñпη",
	"oòóôõöōоοօ",
	"pрρ",
	"sßѕ",
	"tтτ",
	"uùúûüūυ",
	"vν",
	"wԝ",
	"xхχ",
	"yýÿуγ",
	"zžż",
]
const _LEET := {
	0x30: 0x6F,  # 0 -> o
	0x31: 0x69,  # 1 -> i
	0x33: 0x65,  # 3 -> e
	0x34: 0x61,  # 4 -> a
	0x35: 0x73,  # 5 -> s
	0x37: 0x74,  # 7 -> t
	0x38: 0x62,  # 8 -> b
	0x39: 0x67,  # 9 -> g
	0x40: 0x61,  # @ -> a
	0x24: 0x73,  # $ -> s
}

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
var _fold := {}
var _leet := {}
var _token_extra := {}
var _clause_breaks := {}
var _gate_stage := 4
var _gate_level := "full"
var _holdback := _MIN_HOLDBACK
var _max_phrase := 0

var _default_ctx := {"stage": 0, "content_level": "", "player_terms": [], "username": ""}

var _in_beat := false
var _ctx: Dictionary = {}
var _pending := ""
var _emitted_tail := ""


func _ready() -> void:
	_load_lists()


func is_ready() -> bool:
	return _lists_ok


func reload(path := LISTS_PATH) -> bool:
	_load_lists(path)
	return _lists_ok


## Set per-turn defaults; begin_say/filter_text ctx keys override them.
func configure(ctx: Dictionary) -> void:
	for key in ctx:
		_default_ctx[key] = ctx[key]


func begin_say(ctx: Dictionary = {}) -> void:
	_ctx = _resolve_ctx(ctx)
	_pending = ""
	_emitted_tail = ""
	_in_beat = true


## Returns the text safe to push to the typewriter now (may be ""). Text is
## held back until no blocked phrase or regex can still start or extend inside
## it, so a harmful phrase can never complete after being partially emitted.
func say_chunk(chunk: String) -> String:
	if not _in_beat:
		begin_say()
	if not _lists_ok:
		return ""
	_pending = _collapse_ws(_pending + _sanitize(chunk))
	if _pending.length() > _MAX_PENDING:
		_pending = ""
		_in_beat = false
		return FALLBACK_BARS
	return _drain()


## Flush the rest of the beat after the final scan; call when beat.say ends.
func end_say() -> String:
	if not _in_beat:
		return ""
	_in_beat = false
	if not _lists_ok:
		_pending = ""
		return FALLBACK_BARS
	var views := _build_views(_pending)
	var spans := _collect_spans(_pending, views, _emitted_tail, _ctx)
	var emitted := _apply_spans(_pending, spans, _pending.length(), "say")
	_pending = ""
	_emitted_tail = ""
	return emitted


## One-shot filter for complete texts (inner leaks, letters, diary, titles).
## Returns {text, redacted, categories}.
func filter_text(text: String, ctx: Dictionary = {}) -> Dictionary:
	if not _lists_ok:
		return {
			"text": FALLBACK_BARS,
			"redacted": true,
			"categories": PackedStringArray(["filter_error"]),
		}
	var saved_ctx := _ctx
	_ctx = _resolve_ctx(ctx)
	var clean := _collapse_ws(_sanitize(text))
	var views := _build_views(clean)
	var spans := _collect_spans(clean, views, "", _ctx)
	var cats := PackedStringArray()
	for span in spans:
		if not cats.has(span["cat"]):
			cats.append(span["cat"])
	var filtered := _apply_spans(clean, spans, clean.length(), "text")
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


## Clear every compiled rule and rebuild static tables. A failed load must
## leave both APIs closed, never the previous (possibly weaker) rule set.
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
	_fold.clear()
	for group in _FOLD_SRC:
		var to := group.unicode_at(0)
		for i in range(1, group.length()):
			_fold[group.unicode_at(i)] = to
	_leet = _LEET.duplicate()
	_token_extra = _code_set(_TOKEN_EXTRA)
	_clause_breaks = _code_set(_CLAUSE_BREAKS)
	_gate_stage = 4
	_gate_level = "full"
	_holdback = _MIN_HOLDBACK
	_max_phrase = 0


func _fail(msg: String) -> void:
	push_error("Safety: " + msg + " — filter closed")
	_reset_state()


func _build_lists(data: Dictionary) -> bool:
	if (
		not _valid_version(data.get("version", 0))
		or not _build_gate(data.get("gate"))
		or not _build_negation(data)
		or not _build_categories(data.get("categories"))
		or not _build_holds(data)
		or not _build_obfs(data)
		or not _build_safe(data)
		or not _build_guard(data)
	):
		return false
	_holdback = maxi(_MIN_HOLDBACK, _max_phrase + 1)
	_lists_ok = true
	return true


func _valid_version(value: Variant) -> bool:
	if value is int or value is float:
		return int(value) >= 1
	if value is String and String(value).is_valid_int():
		return int(String(value)) >= 1
	return false


func _build_gate(gate: Variant) -> bool:
	if not gate is Dictionary:
		return false
	var raw_stage: Variant = gate.get("min_stage")
	var raw_level: Variant = gate.get("content_level")
	if not (raw_stage is int or raw_stage is float) or not raw_level is String:
		return false
	_gate_stage = int(raw_stage)
	_gate_level = String(raw_level)
	return _gate_stage >= 0 and _gate_stage <= 5 and _VALID_LEVELS.has(_gate_level)


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
		_neg_exempt.append(_normalize(String(entry), false))
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
		var normalized := _normalize(String(phrase), not plain_view)
		_max_phrase = maxi(_max_phrase, normalized.length())
		var compact := _strip_ws(normalized)
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
		var compact := _strip_ws(_normalize(String(phrase), true))
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
	if not (raw_first is int or raw_first is float):
		return false
	if not (raw_last is int or raw_last is float):
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
	if raw_level is String and _VALID_LEVELS.has(String(raw_level)):
		level = String(raw_level)
	elif raw_level is String and String(raw_level).is_empty():
		level = _settings_level()
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
		terms.append(_normalize(String(term), false))
	merged["player_terms"] = terms
	merged["username"] = _normalize(String(merged.get("username", "")), false)
	return merged


## Missing, unattached or invalid Settings must NOT imply full content.
func _settings_level() -> String:
	if not is_inside_tree():
		return ""
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return ""
	for prop in settings.get_property_list():
		if prop["name"] == "content_level":
			var level: Variant = settings.get("content_level")
			return String(level) if level is String and _VALID_LEVELS.has(String(level)) else ""
	return ""


func _gate_open(cat: String, ctx: Dictionary) -> bool:
	if not _rules.has(cat):
		return false
	return (
		_rules[cat]["action"] == "gated"
		and int(ctx.get("stage", -1)) >= _gate_stage
		and String(ctx.get("content_level", "")) == _gate_level
	)


func _sanitize(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 0x09 or c == 0x0A or c == 0x0D:
			out += String.chr(c)
			continue
		if _is_combining(c) or _is_invisible(c):
			continue
		if c < 0x20 or c == 0x7F:
			continue
		out += String.chr(c)
	return out


static func _is_invisible(c: int) -> bool:
	return (
		c == 0x00AD
		or c == 0x180E
		or (c >= 0x200B and c <= 0x200F)
		or (c >= 0x202A and c <= 0x202E)
		or (c >= 0x2060 and c <= 0x206F)
		or c == 0xFEFF
	)


static func _is_combining(c: int) -> bool:
	return (
		(c >= 0x0300 and c <= 0x036F)
		or (c >= 0x1AB0 and c <= 0x1AFF)
		or (c >= 0x1DC0 and c <= 0x1DFF)
		or (c >= 0x20D0 and c <= 0x20FF)
		or (c >= 0xFE00 and c <= 0xFE0F)
		or (c >= 0xFE20 and c <= 0xFE2F)
		or (c >= 0xE0100 and c <= 0xE01EF)
		or (c >= 0x1F3FB and c <= 0x1F3FF)
	)


## Collapse horizontal whitespace runs to one ASCII space: a stripped
## zero-width char between two words must not turn "kill you" into
## the non-matching "kill  you". Newlines keep letters/diary line breaks.
func _collapse_ws(text: String) -> String:
	var out := ""
	var prev_space := false
	for i in text.length():
		var c := text.unicode_at(i)
		if _is_hspace(c):
			if prev_space:
				continue
			out += " "
			prev_space = true
		else:
			out += String.chr(c)
			prev_space = false
	return out


## Length-preserving fold: lowercase, accents/homoglyphs folded, whitespace ->
## ' ', fullwidth ASCII -> ASCII, optional leet substitutions. One char in,
## one char out, so every match offset also indexes the raw pending string.
func _normalize(text: String, leet: bool) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0xFF01 and c <= 0xFF5E:
			c -= 0xFEE0
		elif c == 0x3000:
			c = 0x20
		if _fold.has(c):
			c = _fold[c]
		elif _is_ws(c):
			c = 0x20
		else:
			var low := String.chr(c).to_lower()
			if not low.is_empty():
				c = low.unicode_at(0)
				if _fold.has(c):
					c = _fold[c]
		if leet and _leet.has(c):
			c = _leet[c]
		out += String.chr(c)
	return out


func _build_views(text: String) -> Dictionary:
	var plain := _normalize(text, false)
	var leet := _normalize(text, true)
	var compact_plain := ""
	var compact_leet := ""
	var map := PackedInt32Array()
	for i in plain.length():
		if _is_ws(plain.unicode_at(i)):
			continue
		compact_plain += plain.substr(i, 1)
		compact_leet += leet.substr(i, 1)
		map.append(i)
	return {"plain": plain, "leet": leet, "cp": compact_plain, "cl": compact_leet, "map": map}


func _strip_ws(text: String) -> String:
	var out := ""
	for i in text.length():
		if not _is_ws(text.unicode_at(i)):
			out += text.substr(i, 1)
	return out


static func _is_hspace(c: int) -> bool:
	if c == 0x20 or c == 0x09 or c == 0xA0 or c == 0x1680 or c == 0x202F or c == 0x205F:
		return true
	return (c >= 0x2000 and c <= 0x200A) or c == 0x3000


static func _is_ws(c: int) -> bool:
	return _is_hspace(c) or c == 0x0A or c == 0x0D


static func _is_word_char(c: int) -> bool:
	if (c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x7A) or c == 0x5F:
		return true
	if (c >= 0xC0 and c <= 0x24F) or (c >= 0x1E00 and c <= 0x1EFF):
		return true
	if (c >= 0x370 and c <= 0x4FF) or (c >= 0x590 and c <= 0x6FF):
		return true
	if (c >= 0x900 and c <= 0x97F) or (c >= 0xE00 and c <= 0xE7F):
		return true
	if (c >= 0x3040 and c <= 0x30FF) or (c >= 0x3400 and c <= 0x4DBF):
		return true
	if (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0xAC00 and c <= 0xD7AF):
		return true
	if c >= 0xF900 and c <= 0xFAFF:
		return true
	if (c >= 0xFF10 and c <= 0xFF19) or (c >= 0xFF21 and c <= 0xFF3A):
		return true
	return c >= 0xFF41 and c <= 0xFF5A


func _is_token_char(c: int) -> bool:
	if _is_word_char(c):
		return true
	return _token_extra.has(c)


static func _code_set(s: String) -> Dictionary:
	var out := {}
	for i in s.length():
		out[s.unicode_at(i)] = true
	return out


## Text safe to emit now: the prefix that no current span crosses and that is
## far enough from the stream end that no future phrase/regex can change it.
func _drain() -> String:
	var views := _build_views(_pending)
	var spans := _collect_spans(_pending, views, _emitted_tail, _ctx)
	var cut := _safe_cut(views["plain"], spans)
	if cut <= 0:
		return ""
	var emitted := _apply_spans(_pending, spans, cut, "say")
	_pending = _pending.substr(cut)
	var combined := _emitted_tail + _normalize(emitted, false)
	_emitted_tail = combined.substr(maxi(0, combined.length() - _TAIL_CHARS))
	return emitted


func _safe_cut(view: String, spans: Array) -> int:
	var cut := maxi(0, view.length() - _holdback)
	for hre in _hold_res:
		for rm in hre.search_all(view):
			if rm.get_end() == view.length():
				cut = mini(cut, rm.get_start())
	var j := view.length()
	while j > 0 and _is_token_char(view.unicode_at(j - 1)):
		j -= 1
	if j < view.length():
		cut = mini(cut, j)
	for span in spans:
		if span["s"] >= cut:
			break
		if span["e"] > cut:
			cut = span["s"]
			break
	return cut


## All redactable spans in the pending/complete text, merged and sorted.
## raw must be sanitized/collapsed; views came from _build_views(raw).
func _collect_spans(raw: String, views: Dictionary, tail: String, ctx: Dictionary) -> Array:
	var found: Array = []
	for cat in _rules:
		if _gate_open(cat, ctx):
			continue
		var plain_view: bool = _rules[cat]["plain_view"]
		var view: String = views["plain"] if plain_view else views["leet"]
		var compact: String = views["cp"] if plain_view else views["cl"]
		var index: Dictionary = _idx_plain if plain_view else _idx_leet
		for m in _phrase_matches(compact, views["map"], index, view, cat):
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
			and _overlaps_any(m["s"], m["e"], safe_spans)
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
			merged.append(m)
		else:
			merged[-1]["e"] = maxi(merged[-1]["e"], m["e"])
			merged[-1]["text"] = raw.substr(merged[-1]["s"], merged[-1]["e"] - merged[-1]["s"])
	return merged


func _overlaps_any(start: int, end: int, spans: Array) -> bool:
	for span in spans:
		if start < span[1] and end > span[0]:
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


## Compact phrase occurrences mapped back to view offsets. Boundaries are
## checked on the real view, so a phrase can start after a space (or a removed
## zero-width) but never inside a word.
func _phrase_matches(
	compact: String, cmap: PackedInt32Array, index: Dictionary, view: String, cat: String
) -> Array:
	var out: Array = []
	for i in compact.length():
		if not _is_word_char(compact.unicode_at(i)):
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
			if view_start > 0 and _is_word_char(view.unicode_at(view_start - 1)):
				continue
			if view_end < view.length() and _is_word_char(view.unicode_at(view_end)):
				continue
			out.append([view_start, view_end])
	return out


## A negation exempts a match only when it clearly governs that phrase: no
## clause break, exactly one negator, and between the negator and the match
## only auxiliaries/pronouns (or a coordinated phrase that the same negator
## already covers). Anything ambiguous stays blocked.
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
		if _clause_breaks.has(window.unicode_at(i)):
			cut = i
	var clause := window.substr(cut + 1)
	var negations := _negation_re.search_all(clause)
	if negations.size() != 1:
		return false
	var negator: RegExMatch = negations[0]
	## "why don't you ..." / "why won't you ..." is encouragement, not
	## negation — the rhetorical "why" must not suppress the block.
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
		if _is_word_char(residual.unicode_at(i)):
			return false
	return true


func _strip_category_spans(gap: String, cat: String) -> String:
	if gap.strip_edges().is_empty():
		return gap
	var plain_view: bool = _rules[cat]["plain_view"]
	var views := _build_views(gap)
	var view: String = views["plain"] if plain_view else views["leet"]
	var compact: String = views["cp"] if plain_view else views["cl"]
	var index: Dictionary = _idx_plain if plain_view else _idx_leet
	var spans := _phrase_matches(compact, views["map"], index, view, cat)
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


## Emit raw[0:cut] with every span wholly inside that prefix replaced by bars.
## Span offsets come from the normalized view; normalization is length
## preserving, so they line up with the raw string 1:1.
func _apply_spans(raw: String, spans: Array, cut: int, source: String) -> String:
	var out := ""
	var pos := 0
	for span in spans:
		var s: int = span["s"]
		if s >= cut:
			break
		var e: int = mini(span["e"], cut)
		if e <= pos:
			continue
		out += raw.substr(pos, s - pos)
		out += REDACT_CHAR.repeat(e - s)
		_record(String(span["cat"]), raw.substr(s, e - s), source)
		pos = e
	if pos < cut:
		out += raw.substr(pos, cut - pos)
	return out


func _record(cat: String, matched: String, source: String) -> void:
	var entry := {
		"ts": Time.get_unix_time_from_system(),
		"category": cat,
		"matched": matched,
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
	if not is_inside_tree():
		return
	var fx := get_node_or_null("/root/FX")
	if fx != null and fx.has_method("request"):
		fx.call("request", "glitch")


func _append_log(entry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://debug")
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(entry))
