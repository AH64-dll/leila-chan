class_name SafetyText
extends RefCounted
## Safety.gd's text normalization, split out when the autoload crossed gdlint's
## max-file-lines (P1.19 r3). Everything here is pure: given a string it returns
## the views the filter matches against. `Safety` owns the lists and the policy;
## this file owns how text is folded, stripped and compacted (docs/02 §8).

const SEP_ASCII := "~#*._-^`'\"|/\\+%&:;,=!?()[]{}<>"  ## ASCII separators (SAF-14/CODE-13)
const SEP_WIDE := "•·¡¿‹›«»„“”‘’‚—–…°@"  ## non-ASCII separators (SAF-14/CODE-13)
const SEP_CHARS := SEP_ASCII + SEP_WIDE  ## stripped between letters on the compact view
const CLAUSE_BREAKS := '.,;:!?—–…()[]{}"“”\n\r\t'
const TOKEN_EXTRA := "@._+%'-"  ## chars that keep a trailing token open
const FOLD_SRC: Array[String] = [
	"'’‘",
	'"“”',
	"-–—",
	".…",
	"aàáâãäåāаαɑą",
	"bЬ",
	"cçсϲćč",
	"dԁď",
	"eèéêëēеεėęě",
	"gɡğ",
	"hһ",
	"iìíîïīіιⅰį",
	"jјϳ",
	"kкκ",
	"lӏⅼłľĺ",
	"mмμ",
	"nñпηńň",
	"oòóôõöōоοօ",
	"pрρ",
	"sßѕśšș",
	"tтτťțŧ",
	"uùúûüūυųů",
	"vν",
	"wԝ",
	"xхχ",
	"yýÿуγ",
	"zžżź"
]
const LEET := {
	0x30: 0x6F,
	0x31: 0x69,
	0x33: 0x65,
	0x34: 0x61,
	0x35: 0x73,
	0x37: 0x74,
	0x38: 0x62,
	0x39: 0x67,
	0x40: 0x61,
	0x24: 0x73
}

var _fold := {}
var _leet := {}
var _sep_chars := {}
var _token_extra := {}
var _clause_breaks := {}


func _init() -> void:
	_fold.clear()
	for group in FOLD_SRC:
		var to := group.unicode_at(0)
		for i in range(1, group.length()):
			var c := group.unicode_at(i)
			_fold[c] = to
			var low := String.chr(c).to_lower()
			if not low.is_empty():
				_fold[low.unicode_at(0)] = to
	_leet = LEET.duplicate()
	_sep_chars = code_set(SEP_CHARS)
	_token_extra = code_set(TOKEN_EXTRA)
	_clause_breaks = code_set(CLAUSE_BREAKS)


func fold_has(c: int) -> bool:
	return _fold.has(c)


func fold_of(c: int) -> int:
	return _fold[c]


func leet_has(c: int) -> bool:
	return _leet.has(c)


func leet_of(c: int) -> int:
	return _leet[c]


func is_sep(c: int) -> bool:
	return _sep_chars.has(c)


func is_token_char(c: int) -> bool:
	return is_word_char(c) or _token_extra.has(c)


func is_clause_break(c: int) -> bool:
	return _clause_breaks.has(c)


static func code_set(s: String) -> Dictionary:
	var out := {}
	for i in s.length():
		out[s.unicode_at(i)] = true
	return out


static func is_invisible(c: int) -> bool:
	if c == 0x00AD or c == 0x180E or c == 0xFEFF:
		return true
	if (c >= 0x180B and c <= 0x180D) or (c >= 0x200B and c <= 0x200F):
		return true
	return (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F)


static func is_combining(c: int) -> bool:
	if (c >= 0x0300 and c <= 0x036F) or (c >= 0x0483 and c <= 0x0489):
		return true
	if (c >= 0x064B and c <= 0x065F) or (c >= 0x1AB0 and c <= 0x1AFF):
		return true
	if (c >= 0x1DC0 and c <= 0x1DFF) or (c >= 0x20D0 and c <= 0x20FF):
		return true
	if (c >= 0xFE00 and c <= 0xFE0F) or (c >= 0xFE20 and c <= 0xFE2F):
		return true
	return (c >= 0xE0100 and c <= 0xE01EF) or (c >= 0x1F3FB and c <= 0x1F3FF)


static func is_hspace(c: int) -> bool:
	if c == 0x20 or c == 0x09 or c == 0xA0 or c == 0x1680 or c == 0x202F or c == 0x205F:
		return true
	return (c >= 0x2000 and c <= 0x200A) or c == 0x3000


static func is_ws(c: int) -> bool:
	return is_hspace(c) or c == 0x0A or c == 0x0D or c == 0x85 or c == 0x2028 or c == 0x2029


static func is_word_char(c: int) -> bool:
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
	if (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFF10 and c <= 0xFF19):
		return true
	return (c >= 0xFF21 and c <= 0xFF3A) or (c >= 0xFF41 and c <= 0xFF5A)


## Strip combining marks and control/invisible characters; keep tabs/newlines so
## clause structure survives.
static func sanitize(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 0x09 or c == 0x0A or c == 0x0D:
			out += String.chr(c)
			continue
		if is_combining(c) or is_invisible(c):
			continue
		if c < 0x20 or c == 0x7F:
			continue
		out += String.chr(c)
	return out


## Collapse every whitespace run to a single space (so `ki ll` cannot hide a
## phrase from the compact view while the spaced view still reads as one word).
func collapse_ws(text: String) -> String:
	var out := ""
	var prev_space := false
	for i in text.length():
		var c := text.unicode_at(i)
		if is_hspace(c):
			if prev_space:
				continue
			out += " "
			prev_space = true
		else:
			out += String.chr(c)
			prev_space = false
	return out


func normalize(text: String, leet: bool) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0xFF01 and c <= 0xFF5E:
			c -= 0xFEE0
		elif c == 0x3000:
			c = 0x20
		var low := String.chr(c).to_lower()
		if not low.is_empty():
			c = low.unicode_at(0)
		if _fold.has(c):
			c = _fold[c]
		elif is_ws(c):
			c = 0x20
		if leet and _leet.has(c):
			c = _leet[c]
		out += String.chr(c)
	return out


func views(text: String) -> Dictionary:
	var plain := normalize(text, false)
	var leet := normalize(text, true)
	var cp := compact(plain)
	var cl := compact(leet)
	return {
		"plain": plain,
		"leet": leet,
		"cp": cp["compact"],
		"pmap": cp["map"],
		"cl": cl["compact"],
		"map": cl["map"],
	}


## Whitespace-free and separator-free view of one normalization, plus the index
## map back into it. This is the compact view phrases match against
## (SAF-14/CODE-13): `k#ll`, `k~ll`, `ki•ll`, `kill • yourself`, `kill~yourself`
## all collapse onto the same letters as `kill yourself`, so delimiter runs
## cannot hide a phrase from the index. A separator run is dropped only when
## letters sit on both sides of it; a separator at a phrase edge stays, so the
## word-boundary check in `Safety._phrase_matches` keeps its meaning. Phrase keys
## go through this same function, so key and text can never disagree. Linear: the
## run is buffered and decided once, never re-scanned.
func compact(view: String) -> Dictionary:
	var out := ""
	var map := PackedInt32Array()
	var pending := PackedInt32Array()
	var last_word := false
	for i in view.length():
		var c := view.unicode_at(i)
		if is_ws(c) or _sep_chars.has(c):
			pending.append(i)
			continue
		var drop := last_word and is_word_char(c)
		for idx in pending:
			if is_ws(view.unicode_at(idx)) or drop:
				continue
			out += view.substr(idx, 1)
			map.append(idx)
		pending.clear()
		out += view.substr(i, 1)
		map.append(i)
		last_word = is_word_char(c)
	## Nothing follows a trailing run, so its separators stay (edge rule above).
	for idx in pending:
		if is_ws(view.unicode_at(idx)):
			continue
		out += view.substr(idx, 1)
		map.append(idx)
	return {"compact": out, "map": map}


## Compact match key for a list entry (phrase or safe phrase).
func compact_key(normalized: String) -> String:
	return String(compact(normalized)["compact"])
