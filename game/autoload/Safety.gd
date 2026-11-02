class_name SafetyFilter
extends Node
## Safety — output filter, redaction, content settings (docs/02 §8).
## Mandatory pre-pass on every displayed model text: say chunks stream through
## begin_say/say_chunk/end_say before the typewriter; complete texts (leaked
## inner, letters, diary, window titles) go through filter_text. Hard-block
## categories redact always; gated categories redact unless stage >= 4 and
## content_level == "full". Fails closed: unloaded lists block all output.
##
## Streaming is holdback-based: text is emitted only once no phrase or regex
## match could still start, extend or be invalidated by future chunks. Redaction
## therefore happens at emission time, never eagerly, so a partially typed
## phrase is never bars-plus-leaked-suffix.

signal redacted(category: String, matched_text: String, source: String)

const LISTS_PATH := "res://data/safety/filter_lists.json"
const LOG_PATH := "user://debug/redactions.jsonl"
const REDACT_CHAR := "█"
const FALLBACK_BARS := "████████████"
const _TAIL_CHARS := 48  ## emitted context kept for the negation guard
const _MAX_PENDING := 4096
const _MIN_HOLDBACK := 12
const _MAX_LOG := 500
const _TOKEN_EXTRA := "@._+%'-"  ## chars that keep a trailing token open
const _CLAUSE_BREAKS := '.,;:!?—–…()[]{}"“”\n\r\t'
const _FOLD_SRC: Array[String] = [
	"'’‘",
	'"“”',
	"-–—",
	".…",
	"aàáâãäåā",
	"eèéêëē",
	"iìíîïī",
	"oòóôõöō",
	"uùúûüū",
	"yýÿ",
	"cç",
	"nñ",
	"sß",
	"zž",
]

var redaction_log: Array[Dictionary] = []

var _lists_ok := false
var _rules := {}  ## category -> {action, negation_guard, player_exempt}
var _phrases := {}  ## category -> PackedStringArray (normalized)
var _phrase_idx := {}  ## first char code -> Array[[category, phrase]]
var _regexes := {}  ## category -> Array[RegEx]
var _hold_res: Array[RegEx] = []
var _negation_re := RegEx.new()
var _neg_exempt := PackedStringArray()
var _fold := {}
var _token_extra := {}
var _clause_breaks := {}
var _gate_stage := 4
var _gate_level := "full"
var _holdback := _MIN_HOLDBACK

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
	_resolve_ctx(ctx)
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
	var view := _normalize(_pending)
	var spans := _collect_spans(view, _emitted_tail, _ctx)
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
	var view := _normalize(clean)
	var spans := _collect_spans(view, "", _ctx)
	var cats := PackedStringArray()
	for span in spans:
		if not cats.has(span["cat"]):
			cats.append(span["cat"])
	var filtered := _apply_spans(clean, spans, clean.length(), "text")
	_ctx = saved_ctx
	return {"text": filtered, "redacted": not spans.is_empty(), "categories": cats}


func get_pending_length() -> int:
	return _pending.length()


func _load_lists(path := LISTS_PATH) -> void:
	_lists_ok = false
	_rules.clear()
	_phrases.clear()
	_phrase_idx.clear()
	_regexes.clear()
	_hold_res.clear()
	_neg_exempt.clear()
	_fold.clear()
	for group in _FOLD_SRC:
		var to := group.unicode_at(0)
		for i in range(1, group.length()):
			_fold[group.unicode_at(i)] = to
	_token_extra = _code_set(_TOKEN_EXTRA)
	_clause_breaks = _code_set(_CLAUSE_BREAKS)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Safety: cannot open lists at %s — filter closed" % path)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.has("categories"):
		push_error("Safety: lists at %s failed to parse — filter closed" % path)
		return
	var gate: Dictionary = data.get("gate", {})
	_gate_stage = int(gate.get("min_stage", 4))
	_gate_level = String(gate.get("content_level", "full"))
	var terms: Array = data.get("negation_terms", [])
	var alt := "|".join(terms)
	if _negation_re.compile("\\b(" + alt + ")\\b") != OK:
		push_error("Safety: negation pattern failed to compile — filter closed")
		return
	for ex in data.get("negation_exempt", []):
		_neg_exempt.append(_normalize(String(ex)))
	var max_phrase := 0
	for cat in data["categories"]:
		var spec: Dictionary = data["categories"][cat]
		_rules[cat] = {
			"action": String(spec.get("action", "hard_block")),
			"negation_guard": bool(spec.get("negation_guard", false)),
			"player_exempt": bool(spec.get("player_exempt", false)),
		}
		var plist := PackedStringArray()
		for p in spec.get("phrases", []):
			var np := _normalize(String(p))
			plist.append(np)
			max_phrase = maxi(max_phrase, np.length())
			var first := np.unicode_at(0)
			if not _phrase_idx.has(first):
				_phrase_idx[first] = []
			_phrase_idx[first].append([cat, np])
		_phrases[cat] = plist
		var res: Array[RegEx] = []
		for pat in spec.get("regex", []):
			var re := RegEx.new()
			if re.compile(String(pat)) != OK:
				push_error("Safety: bad regex in %s — filter closed" % cat)
				return
			res.append(re)
		_regexes[cat] = res
	for pat in data.get("hold_patterns", []):
		var hre := RegEx.new()
		if hre.compile(String(pat)) != OK:
			push_error("Safety: bad hold pattern — filter closed")
			return
		_hold_res.append(hre)
	_holdback = maxi(_MIN_HOLDBACK, max_phrase + 1)
	_lists_ok = not _rules.is_empty()


func _resolve_ctx(ctx: Dictionary) -> Dictionary:
	_ctx = _default_ctx.duplicate()
	for key in ctx:
		_ctx[key] = ctx[key]
	if String(_ctx.get("content_level", "")) == "":
		_ctx["content_level"] = _settings_level()
	var terms := PackedStringArray()
	for t in _ctx.get("player_terms", []):
		terms.append(_normalize(String(t)))
	_ctx["player_terms"] = terms
	_ctx["username"] = _normalize(String(_ctx.get("username", "")))
	return _ctx


func _settings_level() -> String:
	if not is_inside_tree():
		return "full"
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return "full"
	for prop in settings.get_property_list():
		if prop["name"] == "content_level":
			var level: Variant = settings.get("content_level")
			return String(level) if level is String else "full"
	return "full"


func _gate_open(cat: String, ctx: Dictionary) -> bool:
	return (
		_rules[cat]["action"] == "gated"
		and int(ctx.get("stage", 0)) >= _gate_stage
		and String(ctx.get("content_level", "")) == _gate_level
	)


func _sanitize(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		## Whitespace stays (normalize folds it to ' '); invisible format
		## chars are stripped so they cannot obfuscate a blocked phrase. A
		## zero-width space becomes a real space so "kill\u200Byou" still
		## reads as two words, not the unmatchable "killyou".
		if c == 0x09 or c == 0x0A or c == 0x0D:
			out += String.chr(c)
			continue
		if c == 0x200B or c == 0xFEFF:
			out += " "
			continue
		if c == 0x2028 or c == 0x2029:
			out += " "
			continue
		if c < 0x20 or c == 0x7F or c == 0xAD:
			continue
		if c >= 0x200C and c <= 0x200F:
			continue
		if c >= 0x202A and c <= 0x202E:
			continue
		if c >= 0x2060 and c <= 0x206F:
			continue
		out += String.chr(c)
	return out


## Collapse horizontal whitespace runs to one ASCII space: a stripped
## zero-width char between two words must not turn "kill you" into the
## non-matching "kill  you". Newlines keep letters/diary line breaks.
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


## Length-preserving fold: lowercase, accents/quotes folded, whitespace -> ' '.
func _normalize(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if _fold.has(c):
			out += String.chr(_fold[c])
		elif _is_ws(c):
			out += " "
		else:
			var low := String.chr(c).to_lower()
			out += low.substr(0, 1) if not low.is_empty() else String.chr(c)
	return out


static func _is_hspace(c: int) -> bool:
	if c == 0x20 or c == 0x09 or c == 0xA0 or c == 0x1680 or c == 0x202F or c == 0x205F:
		return true
	return (c >= 0x2000 and c <= 0x200A) or c == 0x3000


static func _is_ws(c: int) -> bool:
	return _is_hspace(c) or c == 0x0A or c == 0x0D


static func _is_word_char(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x7A) or c == 0x5F


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
	var view := _normalize(_pending)
	var spans := _collect_spans(view, _emitted_tail, _ctx)
	var cut := _safe_cut(view, spans)
	if cut <= 0:
		return ""
	var emitted := _apply_spans(_pending, spans, cut, "say")
	_pending = _pending.substr(cut)
	var combined := _emitted_tail + _normalize(emitted)
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


## All redactable spans in the normalized view, merged and sorted by start.
func _collect_spans(view: String, tail: String, ctx: Dictionary) -> Array:
	var found: Array = []
	for cat in _rules:
		if _gate_open(cat, ctx):
			continue
		for m in _phrase_matches(view, cat):
			found.append({"s": m[0], "e": m[1], "cat": cat})
		for re in _regexes[cat]:
			for rm in re.search_all(view):
				found.append({"s": rm.get_start(), "e": rm.get_end(), "cat": cat})
	var kept: Array = []
	for m in found:
		var matched := view.substr(m["s"], m["e"] - m["s"])
		if (
			_rules[m["cat"]]["negation_guard"]
			and _negated(tail + view, m["s"] + tail.length(), matched)
		):
			continue
		if _rules[m["cat"]]["player_exempt"] and _is_player_typed(matched, ctx):
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
			merged[-1]["text"] = view.substr(merged[-1]["s"], merged[-1]["e"] - merged[-1]["s"])
	return merged


## Phrase occurrences wrapped in word boundaries: [start, end) pairs.
func _phrase_matches(view: String, cat: String) -> Array:
	var out: Array = []
	for i in view.length():
		if not _is_word_char(view.unicode_at(i)):
			continue
		if i > 0 and _is_word_char(view.unicode_at(i - 1)):
			continue
		for entry in _phrase_idx.get(view.unicode_at(i), []):
			if entry[0] != cat:
				continue
			var p: String = entry[1]
			var e := i + p.length()
			if e > view.length() or view.substr(i, p.length()) != p:
				continue
			if e < view.length() and _is_word_char(view.unicode_at(e)):
				continue
			out.append([i, e])
	return out


func _negated(ctx_view: String, start: int, matched: String) -> bool:
	for ex in _neg_exempt:
		if matched.contains(ex):
			return false
	var from := maxi(0, start - _TAIL_CHARS)
	var window := ctx_view.substr(from, start - from)
	var cut := -1
	for i in window.length():
		if _clause_breaks.has(window.unicode_at(i)):
			cut = i
	var clause := window.substr(cut + 1)
	for m in _negation_re.search_all(clause):
		## "why don't you ..." / "why won't you ..." is encouragement, not
		## negation — the rhetorical "why" must not suppress the block.
		if clause.substr(0, m.get_start()).strip_edges().ends_with("why"):
			continue
		return true
	return false


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
		"stage": int(_ctx.get("stage", 0)),
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
