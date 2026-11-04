class_name ProfileKeywords
extends RefCounted
## ProfileKeywords — the keyword half of the docs/01 §2 behaviour profile: the
## counters the model's 17 `read` labels cannot express, read from the player's
## own words (and, for the TSUN rejection counter, from her displayed reply).
##
## GameState owns the counters and the signals; this owns the rules and the data
## load (res://data/profile_keywords.json). Everything here is pure except the
## table load. Each rule contributes at most 1 per message — one message is one
## behaviour, not a keyword count, so keyword bumps stay comparable to the
## read-table's single bumps (docs/02 §1.2's cheap classifier pass).
##
## Counters produced: control, apathy (docs/01 §2 tags no read maps to) and the
## §4 formulas' own flattery_rejected + ignored_questions. broken_promises is an
## engine fact (docs/01 §5 I15) and is bumped by the trigger engine instead.
##
## A missing or broken data file disables keyword bumps (EMPTY_TABLE); it never
## guesses one — a wrong counter would move a path for no reason.

const TABLE_PATH := "res://data/profile_keywords.json"

## The safe empty table: every rule off. The phrases are CONTENT and live only
## in the data file (docs/07 §2), so the fallback is silence, not a second copy.
const EMPTY_TABLE := {
	"control": {"phrases": []},
	"apathy":
	{
		"phrases": [],
		"dismissal_max_words": 0,
		"short_reply_words": 0,
		"short_reply_exempt": [],
	},
	"flattery_rejected": {"flattery": [], "rejection": []},
}

## Folded to spaces before matching (the apostrophe is kept: "don't" is a
## phrase). Folding keeps whole-word matching honest — "ok" must not match
## "joke", and "beautiful!" must still match "beautiful".
const PUNCTUATION: Array[String] = [
	".",
	",",
	"!",
	"?",
	";",
	":",
	'"',
	"“",
	"”",
	"…",
	"(",
	")",
	"[",
	"]",
	"-",
	"—",
	"–",
	"−",
	"*",
	"_",
	"~",
	"\n",
	"\t",
]

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## The loaded rules. READ-ONLY: it is shared, and classification runs every turn.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table()
	return _table_cache


## docs/01 §2 + §4: the counters this message contributes, counter → amount.
## `reply_text` is her displayed turn (the flattery rejection needs both sides);
## `last_question` is her previous direct question (docs/01 §5 T15's echo).
static func classify(player_text: String, reply_text := "", last_question := "") -> Dictionary:
	var bumps := {}
	var text := _normalise(player_text)
	if text.is_empty():
		return bumps
	var rules: Dictionary = table()
	var control: Dictionary = rules["control"]
	if _has_any(text, control["phrases"]):
		bumps[&"control"] = 1
	var apathy: Dictionary = rules["apathy"]
	var question := _normalise(last_question)
	var dismissive := _is_apathy(player_text, text, apathy, not question.is_empty())
	if dismissive:
		bumps[&"apathy"] = 1
		# docs/01 §5 T15 needs a *pending* question and a dismissal; a dismissal
		# with nothing asked is the apathy counter's business alone.
		if not question.is_empty():
			bumps[&"ignored_questions"] = 1
	var rejected: Dictionary = rules["flattery_rejected"]
	if (
		_has_any(text, rejected["flattery"])
		and _has_any(_normalise(reply_text), rejected["rejection"])
	):
		bumps[&"flattery_rejected"] = 1
	return bumps


## The beats' say text as one string — the reply side of the flattery rule.
static func reply_text(turn_data: Dictionary) -> String:
	var parts: PackedStringArray = []
	var beats: Variant = turn_data.get("beats", [])
	if beats is Array:
		for beat: Variant in beats:
			if beat is Dictionary:
				var say := str((beat as Dictionary).get("say", "")).strip_edges()
				if not say.is_empty():
					parts.append(say)
	return " ".join(parts)


## Her last direct question this turn, "" when she asked none. The last say
## containing a "?" wins; say text is schema-capped at 200 chars.
static func question_in(turn_data: Dictionary) -> String:
	var found := ""
	var beats: Variant = turn_data.get("beats", [])
	if beats is Array:
		for beat: Variant in beats:
			if beat is Dictionary:
				var say := str((beat as Dictionary).get("say", "")).strip_edges()
				if say.contains("?"):
					found = say
	return found.left(200)


## docs/01 §4.4: "short replies" count as apathy. Three narrowings keep a warm
## player out of it, because the data contract is "a dismissive phrase, or a
## short reply" — the *message* is the behaviour, never a word inside a message:
## - a question asks, so it is never a dismissal ("Are you sure you're okay?");
## - a dismissal phrase scores only when the whole line is short enough to *be*
##   the dismissal ("I don't care." yes, "I don't care about her, I care about
##   you." no), and a phrase match wins over the exemption (an explicit
##   "whatever" is never warm);
## - a terse reply to her direct question is an answer, not a dismissal (docs/01
##   §5 T15 counts ignoring her, and answering is not ignoring).
static func _is_apathy(
	raw_text: String, text: String, rule: Dictionary, awaiting_answer: bool
) -> bool:
	if raw_text.contains("?"):
		return false
	var words := text.split(" ", false)
	var phrase_cap := int(rule.get("dismissal_max_words", 0))
	if phrase_cap > 0 and words.size() <= phrase_cap and _has_any(text, rule["phrases"]):
		return true
	if awaiting_answer:
		return false
	var cap := int(rule.get("short_reply_words", 0))
	if cap <= 0 or words.size() > cap:
		return false
	return not _has_any(text, rule["short_reply_exempt"])


## Whole-word phrase match on already-normalised text.
static func _has_any(text: String, phrases: Variant) -> bool:
	if text.is_empty() or not phrases is Array:
		return false
	var padded := " %s " % text
	for phrase: Variant in phrases:
		var needle := _normalise(str(phrase))
		if not needle.is_empty() and padded.contains(" %s " % needle):
			return true
	return false


## Lowercase + curly apostrophe to straight + punctuation folded to single
## spaces, so matching never depends on how the player punctuated a line.
static func _normalise(text: String) -> String:
	var out := text.to_lower().replace("’", "'")
	for mark: String in PUNCTUATION:
		out = out.replace(mark, " ")
	return " ".join(out.split(" ", false))


static func _load_table() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("ProfileKeywords: %s missing; keyword bumps disabled" % TABLE_PATH)
		return EMPTY_TABLE.duplicate(true)
	return parse_document(JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH)))


## Validates each rule block on its own: one bad block disables that rule and
## leaves the others working (a typo in the flattery list must not silence the
## control rule). A block is unusable when its phrase list is missing, empty or
## contains a non-string.
static func parse_document(parsed: Variant) -> Dictionary:
	var out: Dictionary = EMPTY_TABLE.duplicate(true)
	if not parsed is Dictionary:
		push_warning("ProfileKeywords: %s is not a JSON object; no keyword bumps" % TABLE_PATH)
		return out
	var document: Dictionary = parsed
	var control := _parse_block(document.get("control"), ["phrases"])
	if not control.is_empty():
		out["control"] = control
	var apathy_source: Variant = document.get("apathy")
	var apathy := _parse_block(apathy_source, ["phrases", "short_reply_exempt"])
	if not apathy.is_empty():
		var block: Dictionary = apathy_source
		apathy["dismissal_max_words"] = _parse_word_cap(block.get("dismissal_max_words"), 12)
		apathy["short_reply_words"] = _parse_word_cap(block.get("short_reply_words"), 6)
		out["apathy"] = apathy
	var flattery := _parse_block(document.get("flattery_rejected"), ["flattery", "rejection"])
	if not flattery.is_empty():
		out["flattery_rejected"] = flattery
	return out


static func _parse_block(value: Variant, keys: Array) -> Dictionary:
	if not value is Dictionary:
		return {}
	var out := {}
	for key: Variant in keys:
		var items := _parse_strings((value as Dictionary).get(key))
		if items.is_empty():
			return {}
		out[str(key)] = items
	return out


static func _parse_strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not value is Array:
		return out
	for item: Variant in value:
		if not item is String:
			out.clear()
			return out
		var text := (item as String).strip_edges()
		if text.is_empty():
			out.clear()
			return out
		out.append(text)
	return out


## A word cap: a small non-negative integer, 0 = that rule is off.
static func _parse_word_cap(value: Variant, maximum: int) -> int:
	if not (value is int or value is float):
		return 0
	var number := float(value)
	if not is_finite(number) or number != floor(number) or number < 0.0 or number > float(maximum):
		return 0
	return int(number)
