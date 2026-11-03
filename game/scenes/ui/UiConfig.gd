class_name UiConfig
extends RefCounted
## Loads res://data/ui.json (content lives in data, docs/07 §2) and hands each
## UI component its section. Components may also be configured with the
## built-in DEFAULTS so unit tests run without the file; the two must agree.

const PATH := "res://data/ui.json"

const DEFAULTS := {
	"names": {"leila": "Leila", "default_player": "Senpai"},
	"typing_indicator":
	{
		"base_text": "{name} is typing",
		"dots_period_ms": 400,
		"stutter_min_stage": 3,
		"stutter_pattern_ms": [160, 160, 520, 120, 120, 600],
		"you_suffix": " *you*",
		"you_min_stage": 5,
		"you_chance": 0.2,
	},
	"typewriter":
	{
		"chars_per_second": 40,
		"chars_per_second_min": 35,
		"chars_per_second_max": 45,
		"pause_chars":
		{".": 240, ",": 140, "!": 240, "?": 240, "…": 300, "—": 200, ";": 160, ":": 160},
	},
	"chat_log": {"max_entries": 200, "page_scroll_ratio": 0.9},
	"input": {"max_length": 400, "placeholder": "Say something…"},
}


## Returns the merged config dictionary: ui.json over DEFAULTS. Never fails —
## a missing or broken file logs a warning and yields the defaults, because a
## corrupt string table must not block play.
static func load_config() -> Dictionary:
	var merged: Dictionary = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(PATH):
		push_warning("UiConfig: %s not found, using built-in defaults" % PATH)
		return merged
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_warning("UiConfig: %s is not a JSON object, using built-in defaults" % PATH)
		return merged
	for key: String in parsed:
		var value: Variant = parsed[key]
		if value is Dictionary and merged.get(key) is Dictionary:
			for inner_key: String in value:
				merged[key][inner_key] = value[inner_key]
		else:
			merged[key] = value
	return merged
