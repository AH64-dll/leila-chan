class_name TurnValidator
extends RefCounted
## TurnValidator — docs/02 §7 validation, pronoun repairs, repetition loop detection,
## early AI-break deflection, and stream recovery.

const FALLBACKS_PATH := "res://data/fallbacks.json"
const AWAKE_GATE_STAGE := 3

## Adverbs that can sit between the rewritten pronoun and its verb. The
## agreement pass skips them so "He never listens" still becomes
## "You never listen" instead of the broken "You never listens".
const _ADVERBS_BETWEEN: Array[String] = [
	"never",
	"always",
	"often",
	"still",
	"just",
	"only",
	"even",
	"not",
	"now",
	"then",
	"also",
	"too",
	"soon",
	"ever",
	"already",
	"almost",
	"quite",
	"rather",
	"sometimes",
	"probably",
	"definitely",
	"absolutely",
	"usually",
	"really",
	"simply",
	"totally",
	"completely",
	"constantly",
	"actually",
	"honestly",
	"seriously",
	"truly",
	"suddenly",
	"quietly",
	"slowly",
	"gently",
]

## How many words after the pronoun the agreement pass inspects before giving
## up and leaving the sentence alone.
const _AGREEMENT_LOOKAHEAD := 3

static var _cached_data: Dictionary = {}
static var _regex_sentence_start_male: RegEx = null
static var _regex_word_token: RegEx = null
static var _regex_player_ref: RegEx = null
static var _regex_male_referent: RegEx = null


static func _get_data() -> Dictionary:
	if not _cached_data.is_empty():
		return _cached_data

	var path := FALLBACKS_PATH
	if not FileAccess.file_exists(path):
		push_warning("TurnValidator: fallbacks file not found at '%s'" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("TurnValidator: failed to open fallbacks file")
		return {}

	var json_str := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		_cached_data = parsed
	else:
		push_warning("TurnValidator: failed to parse fallbacks JSON")
		_cached_data = {}
	return _cached_data


static func clear_cache() -> void:
	_cached_data.clear()
	# The referent regex is compiled from the data file, so it must be rebuilt
	# with it or a reload would keep matching the old name list.
	_regex_male_referent = null


## -----------------------------------------------------------------------------
## 1. Repetition Loop Detection (docs/02 §7)
## Problem: Repetition loop
## Detection: same 4-gram x3
## Handling: Cut at the loop; stage >= 4 renders the loop as text_bleed
## -----------------------------------------------------------------------------
## Returns: {
##   "has_loop": bool,
##   "clean_text": String,
##   "repeated_segment": String,
##   "cut_index": int
## }
static func detect_repetition_loop(text: String) -> Dictionary:
	var res := {
		"has_loop": false, "clean_text": text, "repeated_segment": "", "cut_index": text.length()
	}
	if text.strip_edges().is_empty():
		return res

	# Tokenize words while tracking their character start/end positions in text
	var token_regex := _get_word_regex()
	var matches: Array[RegExMatch] = token_regex.search_all(text)
	# Need at least unit-length 4 repeated 3 times = 12 tokens
	if matches.size() < 12:
		return res

	var words: Array[String] = []
	var starts: Array[int] = []
	var ends: Array[int] = []
	for m: RegExMatch in matches:
		words.append(m.get_string().to_lower())
		starts.append(m.get_start())
		ends.append(m.get_end())

	var n := words.size()
	# Spec: "same 4-gram x3" (docs/02 §7). Detected as a repeated unit of >= 4
	# tokens appearing 3 consecutive times; larger units (e.g. a 5-word phrase
	# x3) count too — "I love you so much" x3 must cut at "I love you so much".
	# At a given start, prefer the largest unit so the whole first repetition
	# is kept, not a fragment of it.
	for i in range(0, n - 11):
		var pmax: int = (n - i) / 3
		if pmax < 4:
			break
		for p in range(pmax, 3, -1):
			# Array.slice's end index is inclusive: i+p-1 takes exactly p tokens.
			var unit0 := words.slice(i, i + p - 1)
			var unit1 := words.slice(i + p, i + 2 * p - 1)
			var unit2 := words.slice(i + 2 * p, i + 3 * p - 1)
			if unit0 == unit1 and unit0 == unit2:
				# Cut at the loop: keep one full unit, drop the second and third
				# repetitions and everything after.
				var cut_pos: int = starts[i + p]
				var loop_end_pos: int = ends[i + 3 * p - 1]
				var loop_segment: String = text.substr(cut_pos, loop_end_pos - cut_pos)
				res["has_loop"] = true
				res["clean_text"] = text.substr(0, cut_pos).strip_edges()
				res["repeated_segment"] = loop_segment
				res["cut_index"] = cut_pos
				return res

	return res


## -----------------------------------------------------------------------------
## 2. Third-person Pronoun Repair (docs/02 §7)
## Problem: Talks *about* the player in `say` ("He's being mean")
## Detection: regex he/him/his at sentence start with no other male referent
## Handling: Rewrite to "You" / "{player_name}"; in `inner` "he" is fine
## -----------------------------------------------------------------------------


static func repair_player_pronouns(
	say_text: String, player_name: String = "Senpai", context_texts: Array = []
) -> String:
	if say_text.is_empty():
		return say_text

	var p_name := player_name if not player_name.is_empty() else "Senpai"
	var replaced := say_text

	# docs/02 §7 detection condition: rewrite only when the say has no other
	# male referent. If the player just mentioned a brother or a rival — or the
	# line itself names one — then "He" may be that third man, and rewriting
	# would put words about you into her mouth.
	if not has_other_male_referent(say_text, context_texts):
		replaced = _rewrite_sentence_start_male(replaced)

	# Replace literal "the player" with the player's name. This reference is
	# explicit, so it is repaired even when another male referent is present.
	var player_regex := _get_player_ref_regex()
	if player_regex != null:
		replaced = player_regex.sub(replaced, p_name, true)

	return replaced


## True when the say (or any recent player message) names a male referent other
## than the player. Names live in `game/data/fallbacks.json`.
static func has_other_male_referent(say_text: String, context_texts: Array = []) -> bool:
	var reg := _get_male_referent_regex()
	if reg == null:
		return false
	if reg.search(say_text.to_lower()) != null:
		return true
	for c: Variant in context_texts:
		if reg.search(str(c).to_lower()) != null:
			return true
	return false


## Rewrite sentence-start He/He's/His/Him to the second person, fixing the verb
## agreement of a bare `He` so the result is always well-formed English.
static func _rewrite_sentence_start_male(say_text: String) -> String:
	var reg := _get_sentence_start_male_regex()
	var matches: Array[RegExMatch] = reg.search_all(say_text)
	if matches.is_empty():
		return say_text

	var rebuilt := ""
	var cursor := 0
	var skipped_agreement := false
	for m: RegExMatch in matches:
		var pronoun := m.get_string(2).to_lower()
		rebuilt += say_text.substr(cursor, m.get_start() - cursor)
		rebuilt += m.get_string(1)
		var consumed_to := m.get_end()

		match pronoun:
			"his":
				rebuilt += "Your"
			"him":
				rebuilt += "You"
			"he's":
				# "He's been/got" is "He has"; everything else is "He is".
				var next_word := _peek_word(say_text, consumed_to)
				rebuilt += "You've" if next_word == "been" or next_word == "got" else "You're"
			_:
				var agreement := _second_person_agreement(say_text.substr(consumed_to))
				if agreement.is_empty():
					# No verb we can safely re-conjugate: leave the sentence
					# untouched rather than emit "You never listens".
					rebuilt += m.get_string(2)
					skipped_agreement = true
				else:
					rebuilt += "You" + str(agreement.get("text", ""))
					consumed_to += int(agreement.get("consumed", 0))
		cursor = consumed_to
	rebuilt += say_text.substr(cursor)

	if skipped_agreement:
		push_warning("TurnValidator: pronoun repair skipped — no verb to re-conjugate after 'He'")
	return rebuilt


## De-conjugate the verb that follows a rewritten `He` ("He is" -> "You are",
## "He listens" -> "You listen"). Returns {} when the clause offers nothing we
## can adjust safely, which makes the caller leave the pronoun alone.
## Returns {"text": String, "consumed": int} otherwise.
static func _second_person_agreement(tail: String) -> Dictionary:
	var word_regex := _get_word_regex()
	var matches: Array[RegExMatch] = word_regex.search_all(tail)
	var inspected := 0
	for m: RegExMatch in matches:
		if inspected >= _AGREEMENT_LOOKAHEAD:
			break
		inspected += 1
		var word := m.get_string()
		var lower := word.to_lower()
		if _is_adverb(lower):
			continue
		var fixed := _second_person_verb(lower)
		if fixed.is_empty():
			# Not a 3rd-person-singular verb (modal, past tense, participle):
			# agreement already matches the second person, so pass it through.
			return {"text": tail.substr(0, m.get_end()), "consumed": m.get_end()}
		return {
			"text": tail.substr(0, m.get_start()) + _match_case(word, fixed),
			"consumed": m.get_end(),
		}
	return {}


static func _is_adverb(lower: String) -> bool:
	return lower.ends_with("ly") or _ADVERBS_BETWEEN.has(lower)


## The second-person form of a 3rd-person-singular verb, or "" when the word is
## not one (in which case it needs no change).
static func _second_person_verb(lower: String) -> String:
	match lower:
		"is":
			return "are"
		"isn't":
			return "aren't"
		"was":
			return "were"
		"wasn't":
			return "weren't"
		"has":
			return "have"
		"hasn't":
			return "haven't"
		"does":
			return "do"
		"doesn't":
			return "don't"
	if lower.ends_with("ies") and lower.length() > 4:
		return lower.substr(0, lower.length() - 3) + "y"
	if lower.ends_with("es") and lower.length() > 3:
		var stem := lower.substr(0, lower.length() - 2)
		if (
			stem.ends_with("s")
			or stem.ends_with("x")
			or stem.ends_with("z")
			or stem.ends_with("ch")
			or stem.ends_with("sh")
			or stem.ends_with("o")
		):
			return stem
		return lower.substr(0, lower.length() - 1)
	if lower.ends_with("s") and not lower.ends_with("ss") and lower.length() > 2:
		return lower.substr(0, lower.length() - 1)
	return ""


## Copy the capitalisation of `source` onto `replacement` ("Studies" -> "Study").
static func _match_case(source: String, replacement: String) -> String:
	if source.is_empty() or replacement.is_empty():
		return replacement
	var first := source.left(1)
	if first == first.to_upper() and first != first.to_lower():
		return replacement.left(1).to_upper() + replacement.substr(1)
	return replacement


## The first word of `text` from `from_index` on, lower-cased ("" at end of text).
static func _peek_word(text: String, from_index: int) -> String:
	if from_index >= text.length():
		return ""
	var matches: Array[RegExMatch] = _get_word_regex().search_all(text.substr(from_index))
	if matches.is_empty():
		return ""
	return matches[0].get_string().to_lower()


## -----------------------------------------------------------------------------
## 3. Early Character-Break Deflection (docs/02 §7)
## Problem: Breaking character early ("As an AI…") at stage < AWAKE gate
## Detection: phrase list
## Handling: Replace beat with in-character deflection pool; increment `meta_curiosity`
## -----------------------------------------------------------------------------
static func check_character_break(say_text: String, stage: int) -> bool:
	if stage >= AWAKE_GATE_STAGE:
		return false

	var lower := say_text.to_lower()
	var data := _get_data()
	var phrases: Array = data.get("character_break_phrases", [])
	for p: Variant in phrases:
		var phrase_str := str(p).to_lower().strip_edges()
		if not phrase_str.is_empty() and phrase_str in lower:
			return true
	return false


static func get_deflection_beat(player_name: String = "Senpai", seed_index: int = -1) -> Dictionary:
	var data := _get_data()
	var pool: Array = data.get("deflection_pool", [])
	if pool.is_empty():
		return {
			"feeling": "confused",
			"intensity": 1,
			"cue": "giggle",
			"say": "S-sorry, what were we saying, %s?" % player_name
		}

	var idx := 0
	if seed_index >= 0:
		idx = seed_index % pool.size()
	else:
		idx = randi() % pool.size()

	var beat: Dictionary = (pool[idx] as Dictionary).duplicate(true)
	var say_str: String = str(beat.get("say", ""))
	beat["say"] = say_str.replace("{player_name}", player_name)
	return beat


## -----------------------------------------------------------------------------
## 4. Broken Stream / Truncated Fallback (docs/02 §7)
## Problem: Broken JSON (only seen at dose >= 8 unhardened)
## Detection: parse error
## Handling: Show the partial `say` text through the glitch filter;
## sprite 29 (stage >= 3) or 00; log
## -----------------------------------------------------------------------------
static func get_broken_stream_fallback(
	partial_say: String, stage: int, player_name: String = "Senpai"
) -> Dictionary:
	var data := _get_data()
	var fallbacks: Dictionary = data.get("broken_stream_fallbacks", {})
	var chosen_template: Dictionary = {}
	if stage >= 3:
		chosen_template = fallbacks.get("stage_3_plus", {})
	else:
		chosen_template = fallbacks.get("stage_0_2", {})

	var fallback_say: String = str(chosen_template.get("say", "..."))
	var feeling: String = str(chosen_template.get("feeling", "nervous" if stage < 3 else "empty"))
	var intensity: int = int(chosen_template.get("intensity", 1 if stage < 3 else 3))
	var cue: String = str(chosen_template.get("cue", "none" if stage < 3 else "static"))

	var combined_say := ""
	var trimmed_partial := partial_say.strip_edges()
	if not trimmed_partial.is_empty():
		combined_say = trimmed_partial + "..."
	else:
		combined_say = fallback_say
	combined_say = combined_say.replace("{player_name}", player_name)

	return {
		"feeling": feeling,
		"intensity": intensity,
		"cue": cue,
		"say": combined_say,
		"partial_say": partial_say,
		"sprite": "29" if stage >= 3 else "00",
		"fx": "glitch" if stage >= 3 else "none"
	}


## -----------------------------------------------------------------------------
## 5. Safety-Rejected Player Input (docs/02 §4 step 0.1 / §8)
## Problem: the player's own line is refused, so there is no turn to answer it
## Detection: Director.filter_player_input() → false
## Handling: one in-fiction refusal beat, so the screen is never silent with the
## input still locked (P1 gate G1 / playtest F3)
## -----------------------------------------------------------------------------
## Returns the refusal beat {feeling, intensity, cue, say}. Cue stays "none":
## the refusal is an input-path event, not a streamed reply, so it must not spend
## the turn's docs/02 §5 cue budget.
static func get_input_refusal(stage: int, player_name: String = "Senpai") -> Dictionary:
	var fallbacks: Dictionary = _get_data().get("unsafe_input_fallbacks", {})
	var template: Dictionary = fallbacks.get("stage_3_plus" if stage >= 3 else "stage_0_2", {})
	var fallback_say := "Let's talk about something else, %s." % player_name
	var say_str := str(template.get("say", fallback_say))
	return {
		"feeling": str(template.get("feeling", "cold" if stage >= 3 else "nervous")),
		"intensity": int(template.get("intensity", 2)),
		"cue": str(template.get("cue", "none")),
		"say": say_str.replace("{player_name}", player_name),
	}


## -----------------------------------------------------------------------------
## Helper RegEx accessors
## -----------------------------------------------------------------------------
static func _get_word_regex() -> RegEx:
	if _regex_word_token == null:
		_regex_word_token = RegEx.new()
		_regex_word_token.compile("[a-zA-Z0-9']+")
	return _regex_word_token


static func _get_sentence_start_male_regex() -> RegEx:
	if _regex_sentence_start_male == null:
		_regex_sentence_start_male = RegEx.new()
		# Matches start of string or following punctuation with optional quotes and spaces,
		# capturing prefix in group 1 and pronoun in group 2
		_regex_sentence_start_male.compile("(^|[.!?][\"'”]?\\s+)(He's|He|His|Him)\\b")
	return _regex_sentence_start_male


static func _get_player_ref_regex() -> RegEx:
	if _regex_player_ref == null:
		_regex_player_ref = RegEx.new()
		_regex_player_ref.compile("(?i)\\bthe player\\b")
	return _regex_player_ref


## Word-boundary alternation over `male_referent_names` (data, docs/02 §7).
static func _get_male_referent_regex() -> RegEx:
	if _regex_male_referent != null:
		return _regex_male_referent
	var names: Array = _get_data().get("male_referent_names", [])
	if names.is_empty():
		return null
	var escaped: Array[String] = []
	for n: Variant in names:
		var name_str := str(n).to_lower().strip_edges()
		if not name_str.is_empty():
			escaped.append(name_str)
	if escaped.is_empty():
		return null
	_regex_male_referent = RegEx.new()
	_regex_male_referent.compile("\\b(?:%s)\\b" % "|".join(escaped))
	return _regex_male_referent
