class_name PlayerNameRules
extends RefCounted
## Validates player names according to docs/08 §1.5:
## - 1–16 characters, letters/spaces/-'
## - Run through Safety (slurs/obscene → Leila pouts:
##   "That's not a real name… tell me your real one.")
## - Empty or whitespace only → "Senpai"
## - Special name "Leila" → "That's *my* name. …Do you want to be me?" (+Fixation)

const DEFAULT_PLAYER_NAME := "Senpai"
const MAX_LENGTH := 16
const MIN_LENGTH := 1

const MSG_POUT_UNSAFE := "That's not a real name… tell me your real one."
const MSG_SPECIAL_LEILA := "That's *my* name. …Do you want to be me?"
const MSG_SPECIAL_OS_USERNAME := "You told me the truth. Good."
const MSG_SHADOW_NAME := "That's not what you were called last time."
const MSG_INVALID_CHARS := "Only letters, spaces, hyphens, and apostrophes are allowed."
const MSG_TOO_LONG := "Name must be 16 characters or less."

## Basic obscenity/slur patterns for standalone safety validation when
## Safety autoload is a stub or running in isolated unit tests.
const BUILTIN_BLOCKED_PATTERNS: Array[String] = [
	"fuck",
	"shit",
	"bitch",
	"cunt",
	"whore",
	"slut",
	"nigger",
	"faggot",
	"retard",
	"kys",
	"kill yourself",
]

static var _regex: RegEx = null


static func _get_regex() -> RegEx:
	if _regex == null:
		_regex = RegEx.new()
		# Match unicode letters, spaces, hyphens, and single-quote apostrophes
		_regex.compile("^[\\p{L}\\s\\-']+$")
	return _regex


## Validates a candidate name according to docs/08 §1.5.
## Returns a Dictionary with:
##   valid: bool
##   resolved_name: String ("Senpai" when empty)
##   error: String ("" when valid, or "too_long", "invalid_characters", "unsafe")
##   message: String (feedback / Leila pout / Leila special line)
##   is_special_leila: bool (true when "Leila" is typed)
## docs/08 §1.5 special names beyond "Leila" (P3.14), passed through `opts`:
##   opts["os_username"]: String — the account name, ONLY when Settings'
##     `use_os_username` opt-in is on (docs/09 privacy: opt-in only; when the
##     flag is off the caller passes "" and the env is never read). A typed
##     name matching it case-insensitively is flagged `is_os_username` with
##     "You told me the truth. Good." — the name still resolves normally.
## "Leila" wins the special line over the OS username when both match.
static func validate(
	candidate: String, safety_checker: Callable = Callable(), opts: Dictionary = {}
) -> Dictionary:
	var trimmed := candidate.strip_edges()
	if trimmed.is_empty():
		return {
			"valid": true,
			"resolved_name": DEFAULT_PLAYER_NAME,
			"error": "",
			"message": "",
			"is_special_leila": false,
			"is_os_username": false,
			"is_special": false,
		}

	if candidate.length() > MAX_LENGTH:
		return {
			"valid": false,
			"resolved_name": candidate,
			"error": "too_long",
			"message": MSG_TOO_LONG,
			"is_special_leila": false,
			"is_os_username": false,
			"is_special": false,
		}

	var reg := _get_regex()
	if reg.search(candidate) == null:
		return {
			"valid": false,
			"resolved_name": candidate,
			"error": "invalid_characters",
			"message": MSG_INVALID_CHARS,
			"is_special_leila": false,
			"is_os_username": false,
			"is_special": false,
		}

	if not _is_safe(candidate, safety_checker):
		return {
			"valid": false,
			"resolved_name": candidate,
			"error": "unsafe",
			"message": MSG_POUT_UNSAFE,
			"is_special_leila": false,
			"is_os_username": false,
			"is_special": false,
		}

	var is_leila := trimmed.to_lower() == "leila"
	var os_name := String(opts.get("os_username", "")).strip_edges()
	var is_os := not os_name.is_empty() and trimmed.to_lower() == os_name.to_lower()
	var special := is_leila or is_os
	var message := ""
	if is_leila:
		message = MSG_SPECIAL_LEILA
	elif is_os:
		message = MSG_SPECIAL_OS_USERNAME
	return {
		"valid": true,
		"resolved_name": trimmed,
		"error": "",
		"message": message,
		"is_special_leila": is_leila,
		"is_os_username": is_os,
		"is_special": special,
	}


static func _is_safe(candidate: String, safety_checker: Callable) -> bool:
	# 1. Custom / test injected safety checker
	if safety_checker.is_valid():
		var res: Variant = safety_checker.call(candidate)
		if res is bool:
			return res
		if res is Dictionary:
			return not bool(res.get("redacted", false))

	# 2. Check live Safety autoload if available
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null and tree.root.has_node("Safety"):
		var safety: Node = tree.root.get_node("Safety")
		if safety.has_method("filter_text"):
			var result: Variant = safety.call("filter_text", candidate)
			if result is Dictionary:
				if bool(result.get("redacted", false)):
					return false
				var cats: Variant = result.get("categories", [])
				if cats is Array and not (cats as Array).is_empty():
					return false
		elif safety.has_method("is_safe"):
			var res: Variant = safety.call("is_safe", candidate)
			if res is bool and not res:
				return false

	# 3. Built-in basic safety check
	var lower := candidate.to_lower()
	for word: String in BUILTIN_BLOCKED_PATTERNS:
		if lower.contains(word):
			return false

	return true


## docs/08 §1.5 shadow name memory (P3.14, shadow save from P3.12): "a New
## Game with a different name at stage 3+ gets 'That's not what you were
## called last time.'" — the name her memory was built on is the shadow's
## first_name (the FIRST name she ever knew); a later New Game confirming a
## different name is only remarked on when the run just ended had reached
## stage 3 (`prev_stage`, GameState.stage captured BEFORE begin_new_game/
## reset — the shadow only seals her memories past that gate, so it is also
## the stage where "last time" means something she lived). Returns the line
## or "". Case-insensitive compare: renaming yourself "ren" after "Ren" is
## the same name. `known_names` is the shadow's `names` list: a name she has
## already known is not news, so a player who settled on "Haru" after "Ren"
## is told the line once rather than every run.
static func shadow_name_message(
	resolved_name: String, first_name: String, prev_stage: int, known_names: Array = []
) -> String:
	if prev_stage < int(Corruption.name_rule("shadow").get("gate", 3)):
		return ""
	var previous := first_name.strip_edges()
	if previous.is_empty():
		return ""
	var typed := resolved_name.strip_edges().to_lower()
	if typed == previous.to_lower():
		return ""
	for known: Variant in known_names:
		if String(known).strip_edges().to_lower() == typed:
			return ""
	return MSG_SHADOW_NAME
