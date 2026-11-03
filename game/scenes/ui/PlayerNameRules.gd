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
static func validate(candidate: String, safety_checker: Callable = Callable()) -> Dictionary:
	var trimmed := candidate.strip_edges()
	if trimmed.is_empty():
		return {
			"valid": true,
			"resolved_name": DEFAULT_PLAYER_NAME,
			"error": "",
			"message": "",
			"is_special_leila": false,
		}

	if candidate.length() > MAX_LENGTH:
		return {
			"valid": false,
			"resolved_name": candidate,
			"error": "too_long",
			"message": MSG_TOO_LONG,
			"is_special_leila": false,
		}

	var reg := _get_regex()
	if reg.search(candidate) == null:
		return {
			"valid": false,
			"resolved_name": candidate,
			"error": "invalid_characters",
			"message": MSG_INVALID_CHARS,
			"is_special_leila": false,
		}

	if not _is_safe(candidate, safety_checker):
		return {
			"valid": false,
			"resolved_name": candidate,
			"error": "unsafe",
			"message": MSG_POUT_UNSAFE,
			"is_special_leila": false,
		}

	var is_leila := trimmed.to_lower() == "leila"
	return {
		"valid": true,
		"resolved_name": trimmed,
		"error": "",
		"message": MSG_SPECIAL_LEILA if is_leila else "",
		"is_special_leila": is_leila,
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
