class_name TurnValidator
extends RefCounted
## TurnValidator — docs/02 §7 validation, pronoun repairs, repetition loop detection,
## early AI-break deflection, and stream recovery.

const FALLBACKS_PATH := "res://data/fallbacks.json"
const AWAKE_GATE_STAGE := 3

static var _cached_data: Dictionary = {}
static var _regex_sentence_start_male: RegEx = null
static var _regex_word_token: RegEx = null


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
	if matches.size() < 12:  # Need at least 4-gram x 3 = 12 tokens
		return res

	var words: Array[String] = []
	var starts: Array[int] = []
	var ends: Array[int] = []
	for m: RegExMatch in matches:
		words.append(m.get_string().to_lower())
		starts.append(m.get_start())
		ends.append(m.get_end())

	var n := words.size()
	# Scan for 4-gram repeated 3 consecutive times: i.e.
	# words[i..i+3] == words[i+4..i+7] == words[i+8..i+11]
	for i in range(0, n - 11):
		var g0 := [words[i], words[i + 1], words[i + 2], words[i + 3]]
		var g1 := [words[i + 4], words[i + 5], words[i + 6], words[i + 7]]
		var g2 := [words[i + 8], words[i + 9], words[i + 10], words[i + 11]]

		if g0 == g1 and g0 == g2:
			# Found repetition loop starting at token i+4 (the second repetition starts the loop)
			# or token i+8 (third repetition). The handling says "Cut at the loop".
			# Cutting at the start of the first repetition that constitutes the loop:
			# i.e., keep words up to ends[i+3], cut off from starts[i+4].
			var cut_pos: int = starts[i + 4]
			var loop_end_pos: int = ends[i + 11]
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
static func repair_player_pronouns(say_text: String, player_name: String = "Senpai") -> String:
	if say_text.is_empty():
		return say_text

	var p_name := player_name if not player_name.is_empty() else "Senpai"

	# Match sentence beginnings or after punctuation [.!?] followed by whitespace or quotes
	# Pattern: (^|(?<=[.!?]\s)|(?<=[.!?]["'”]\s)|(?<=[.!?]))\s*(He's|He|His|Him)\b
	# Also handle case when sentence starts with quotes like: "He's being mean"
	var reg := _get_sentence_start_male_regex()
	var replaced := reg.sub(
		say_text,
		func(m: RegExMatch) -> String:
			var prefix: String = m.get_string(1)
			var pronoun: String = m.get_string(2)
			var lower_pronoun := pronoun.to_lower()

			match lower_pronoun:
				"he's":
					return prefix + "You're"
				"he":
					return prefix + "You"
				"his":
					return prefix + "Your"
				"him":
					return prefix + "You"
				_:
					return prefix + "You",
		true
	)

	# Replace literal "the player" with player_name or "you" depending on context
	var player_regex := RegEx.new()
	player_regex.compile("(?i)\\bthe player\\b")
	replaced = player_regex.sub(replaced, p_name, true)

	return replaced


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
			"feeling": "confusion",
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
## Handling: Show the partial `say` text through the glitch filter; sprite 29 (stage >= 3) or 00;
##   log
## -----------------------------------------------------------------------------
static func get_broken_stream_fallback(partial_say: String, stage: int) -> Dictionary:
	var data := _get_data()
	var fallbacks: Dictionary = data.get("broken_stream_fallbacks", {})
	var chosen_template: Dictionary = {}
	if stage >= 3:
		chosen_template = fallbacks.get("stage_3_plus", {})
	else:
		chosen_template = fallbacks.get("stage_0_2", {})

	var fallback_say: String = str(chosen_template.get("say", "..."))
	var feeling: String = str(
		chosen_template.get("feeling", "confusion" if stage < 3 else "glitch")
	)
	var intensity: int = int(chosen_template.get("intensity", 1 if stage < 3 else 3))
	var cue: String = str(chosen_template.get("cue", "none" if stage < 3 else "static"))

	var combined_say := ""
	var trimmed_partial := partial_say.strip_edges()
	if not trimmed_partial.is_empty():
		combined_say = trimmed_partial + "..."
	else:
		combined_say = fallback_say

	return {
		"feeling": feeling,
		"intensity": intensity,
		"cue": cue,
		"say": combined_say,
		"partial_say": partial_say,
		"sprite": "29" if stage >= 3 else "00",
		"fx": "glitch"
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
