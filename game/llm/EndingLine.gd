class_name EndingLine
extends RefCounted
## EndingLine — an ending's last line: the live half of P3.17's ending content.
##
## The ending screen shows two kinds of prose (docs/01 §7):
##   - the run's `frame`: the game's own narration of the last scene, authored
##     in res://data/endings.json and drawn by Ending.tscn, always shown;
##   - her last line: generated once at the end of the run in her own voice, and
##     replaced by the row's `final` — the same beat written by hand and
##     safety-reviewed — when the model is missing, busy, slow, empty, malformed
##     or unsafe. An ending never has a hole where its last beat belongs.
##
## This file is the pure half: it assembles the one-shot prompt, owns the output
## schema, parses and cleans the answer, scans it with the shipped Safety filter
## and names the fallback. It never touches a node or a stream; Ending.gd owns
## the request, the hold and the screen.
##
## Prompt shape (one request, no history, no Turn):
##   system  persona.md + stage_<n>.md + path_<PATH>.md (when that module exists)
##           + ending.md, the instruction that replaces rules.md for this reply
##           because the answer is {"line": "..."}, not a Turn.
##   user    the row's `frame`, its `direction` note and the player's name.
## The row's `direction` is what carries the path's tone here, so every ending
## works before P3.05's path modules land, and inherits the path module when it
## does — same rule as PromptBuilder: a missing module is an empty layer, never
## an invented one.
##
## Safety (docs/02 §8): the line is model text, so `scan()` runs the Safety
## filter and a redaction means *no live line* — the reviewed `final` stands.
## Showing bars instead of the farewell would replace the ending's last beat
## with noise; falling back is the safer reading of the same rule, and it is
## fail-closed: no filter, no model text.

const PROMPT_DIR := "res://data/prompts"
const PERSONA_FILE := "persona.md"
const STAGE_FILE_FORMAT := "stage_%d.md"
const PATH_FILE_FORMAT := "path_%s.md"
const INSTRUCTION_FILE := "ending.md"
const TABLE_PATH := "res://data/endings.json"
const CONFIG_KEY := "final_line"

## The docs/02 §3 spoken-beat cap (200 characters) is the ceiling, not a target:
## `max_chars` in the data may lower it, never raise it.
const DEFAULT_MAX_CHARS := 200
const MIN_MAX_CHARS := 32
const DEFAULT_MAX_TOKENS := 96
const MAX_TOKENS_CAP := 512
const DEFAULT_SAMPLING := {"temperature": 0.85, "top_p": 0.92, "repeat_penalty": 1.05}
const SAMPLING_KEYS: Array[String] = ["temperature", "top_p", "repeat_penalty", "seed"]

const ANY_PATH := "ANY"
const MIN_STAGE := 0
const MAX_STAGE := 5
const DEFAULT_PLAYER_NAME := "Senpai"
## PromptBuilder's calibration (P1.05's llama-tokenize runs): tests assert with
## this estimate, the handoff reports the real tokenizer's number.
const CHARS_PER_TOKEN := 3.6
## A model that slips an asterisk action or a speaker label in must not put
## either on the ending screen.
const ACTION_PATTERN := "\\*[^*]*\\*"
const LABEL_PATTERN := "^[A-Za-z][A-Za-z0-9 _'-]{0,15}:\\s*"

static var prompt_dir := PROMPT_DIR
static var _config_cache: Dictionary = {}
static var _text_cache: Dictionary = {}
static var _action_re: RegEx
static var _label_re: RegEx


## Drop the cached table and prompt texts (tests and the prompt lab call this
## after pointing prompt_dir somewhere else).
static func clear_cache() -> void:
	_config_cache = {}
	_text_cache = {}


## Point the module reader at another directory ("" restores the shipped one).
## Tests use a scratch copy so they never edit the shipped content.
static func set_prompt_dir(path: String) -> void:
	prompt_dir = path if not path.strip_edges().is_empty() else PROMPT_DIR
	_text_cache = {}


## The shipped one-shot config, sanitised: {prompt, max_tokens, max_chars,
## sampling}. A missing or broken block degrades to the constants above, because
## a data typo must cost a nicer last line, never an ending that cannot finish.
static func config() -> Dictionary:
	if not _config_cache.is_empty():
		return _config_cache.duplicate(true)
	var document := _read_json(TABLE_PATH)
	var block := _dict(document.get(CONFIG_KEY))
	var merged := {
		"prompt": INSTRUCTION_FILE,
		"max_tokens": DEFAULT_MAX_TOKENS,
		"max_chars": DEFAULT_MAX_CHARS,
		"sampling": DEFAULT_SAMPLING.duplicate(true),
	}
	for key: Variant in block:
		var name := String(key)
		if merged.has(name):
			merged[name] = block[key]
	_config_cache = _sanitised_config(merged)
	return _config_cache.duplicate(true)


## Can this row be voiced live? The direction is the note the line is generated
## from; a row without one keeps P3.16's screen (title, coordinates, log line).
static func has_direction(row: Dictionary) -> bool:
	return not String(row.get("direction", "")).strip_edges().is_empty()


## The reviewed line for `row`, cleaned the way a live answer is and capped by
## the data. "" when the row carries none.
static func fallback(row: Dictionary, player_name: String) -> String:
	var text := _substitute(String(row.get("final", "")), _name(player_name))
	return clean(text)


## The one-shot request for this row, or null when the row has no direction.
static func build_request(
	row: Dictionary, player_name: String, stage: int, path: String
) -> TurnRequest:
	if not has_direction(row):
		return null
	var layers := prompt_layers(row, player_name, stage, path)
	var request := TurnRequest.new()
	request.messages = [
		{"role": "system", "content": String(layers.get("system", ""))},
		{"role": "user", "content": String(layers.get("user", ""))},
	]
	request.schema = schema()
	request.sampling = _sampling()
	request.max_tokens = int(config().get("max_tokens", DEFAULT_MAX_TOKENS))
	return request


## {system, user} for one ending, after the same token substitution the shipped
## prompt modules get. The caller (a test, the handoff) can read exactly what the
## model was asked, and the screen can measure the budget.
static func prompt_layers(
	row: Dictionary, player_name: String, stage: int, path: String
) -> Dictionary:
	var name := _name(player_name)
	var files: Array[String] = [PERSONA_FILE, STAGE_FILE_FORMAT % _stage(stage)]
	var run_path := String(path).strip_edges().to_upper()
	if not run_path.is_empty() and run_path != ANY_PATH:
		files.append(PATH_FILE_FORMAT % run_path)
	files.append(String(config().get("prompt", INSTRUCTION_FILE)))
	var parts: Array[String] = []
	for file: String in files:
		var text := _read_text(file).strip_edges()
		if not text.is_empty():
			parts.append(text)
	var turns: Array[String] = []
	var frame := _substitute(String(row.get("frame", "")).strip_edges(), name)
	if not frame.is_empty():
		turns.append(frame)
	var direction := _substitute(String(row.get("direction", "")).strip_edges(), name)
	if not direction.is_empty():
		turns.append("HER STATE\n" + direction)
	turns.append("Say your last line to %s." % name)
	return {"system": "\n\n".join(parts), "user": "\n\n".join(turns)}


## The reply the model is constrained to: one string field, nothing else where a
## Turn would carry read/inner/beats. No `maxLength` keyword — the transport's
## grammar does not guarantee it, so `clean()` enforces the cap instead.
static func schema() -> Dictionary:
	return {
		"type": "object",
		"additionalProperties": false,
		"properties": {"line": {"type": "string"}},
		"required": ["line"],
	}


## The `line` field of a reply, cleaned; "" when the answer is not the schema's
## shape (the scripted fallback then stands). `maxLength` is not enforced by the
## grammar, so the cap is applied here too.
static func parse(raw: String, limit := 0) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	var json := JSON.new()
	if json.parse(text) != OK:
		return ""
	var data: Variant = json.data
	if not data is Dictionary:
		return ""
	var line: Variant = (data as Dictionary).get("line")
	if not line is String:
		return ""
	return clean(str(line), limit)


## One line of her speech, ready for the screen: no asterisk actions, no speaker
## label, no line breaks, no wrapping quotes, clamped to `limit` (0 = the data's
## cap) at a word boundary.
static func clean(text: String, limit := 0) -> String:
	var cap := limit if limit > 0 else int(config().get("max_chars", DEFAULT_MAX_CHARS))
	var out := text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	out = _collapse(out)
	out = _get_action_re().sub(out, " ", true)
	out = _collapse(out)
	out = _get_label_re().sub(out, "", true)
	out = _strip_wrapping_quotes(_collapse(out))
	if cap > 0 and out.length() > cap:
		out = _clamp(out, cap)
	return out


## The Safety scan for one line: {ok, text, redacted, categories}. `ok` means
## the exact text may be displayed; anything else means the scripted fallback
## stands. Fail-closed: no Safety node, an error category or a redaction is "no".
static func scan(text: String, stage := MAX_STAGE) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return _refused(PackedStringArray())
	var safety := _safety_node()
	if safety == null:
		return _refused(PackedStringArray(["filter_error"]))
	var result: Variant = safety.call("filter_text", cleaned, {"stage": _stage(stage)})
	if not result is Dictionary:
		return _refused(PackedStringArray(["filter_error"]))
	var filtered := _dict(result)
	var categories: Variant = filtered.get("categories", PackedStringArray())
	if bool(filtered.get("redacted", true)) or _has_error(categories):
		return _refused(categories)
	var output := String(filtered.get("text", "")).strip_edges()
	if output.is_empty():
		return _refused(categories)
	return {"ok": true, "text": output, "redacted": false, "categories": categories}


## The estimated token count of an assembled prompt (the budget line the role
## playbook asks for). Calibrated like PromptBuilder, so the two agree.
static func estimate_tokens(text: String) -> int:
	return int(ceil(float(text.length()) / CHARS_PER_TOKEN))


# --- internals -----------------------------------------------------------


static func _sanitised_config(source: Dictionary) -> Dictionary:
	var prompt_file := String(source.get("prompt", INSTRUCTION_FILE)).strip_edges()
	if prompt_file.is_empty():
		prompt_file = INSTRUCTION_FILE
	var tokens := clampi(int(source.get("max_tokens", DEFAULT_MAX_TOKENS)), 16, MAX_TOKENS_CAP)
	var chars := clampi(
		int(source.get("max_chars", DEFAULT_MAX_CHARS)), MIN_MAX_CHARS, DEFAULT_MAX_CHARS
	)
	var raw := _dict(source.get("sampling", DEFAULT_SAMPLING))
	if raw.is_empty():
		raw = DEFAULT_SAMPLING.duplicate(true)
	var sampling := {}
	for key: String in SAMPLING_KEYS:
		if raw.has(key):
			sampling[key] = float(raw[key])
	return {
		"prompt": prompt_file,
		"max_tokens": tokens,
		"max_chars": chars,
		"sampling": sampling,
	}


static func _sampling() -> Dictionary:
	return _dict(config().get("sampling", DEFAULT_SAMPLING))


static func _refused(categories: Variant) -> Dictionary:
	return {"ok": false, "text": "", "redacted": true, "categories": categories}


static func _has_error(categories: Variant) -> bool:
	if not categories is Array and not categories is PackedStringArray:
		return false
	for category: Variant in categories:
		if String(category) == "filter_error":
			return true
	return false


static func _safety_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Safety")


static func _stage(value: int) -> int:
	return clampi(value, MIN_STAGE, MAX_STAGE)


static func _name(player_name: String) -> String:
	var cleaned := player_name.strip_edges()
	return cleaned if not cleaned.is_empty() else DEFAULT_PLAYER_NAME


static func _substitute(text: String, player_name: String) -> String:
	return text.replace("{player_name}", player_name)


static func _collapse(text: String) -> String:
	var out := text
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


static func _strip_wrapping_quotes(text: String) -> String:
	var out := text
	var quotes := ['"', "“", "”", "«", "»", "‘", "’"]
	for quote: String in quotes:
		while out.begins_with(quote):
			out = out.substr(quote.length()).strip_edges()
		while out.ends_with(quote):
			out = out.substr(0, out.length() - quote.length()).strip_edges()
	return out


static func _clamp(text: String, cap: int) -> String:
	var cut := text.substr(0, cap).strip_edges()
	var space := cut.rfind(" ")
	if space > cap / 2:
		cut = cut.substr(0, space)
	return cut.strip_edges().trim_suffix(".").trim_suffix(",") + "…"


static func _get_action_re() -> RegEx:
	if _action_re == null:
		_action_re = RegEx.create_from_string(ACTION_PATTERN)
	return _action_re


static func _get_label_re() -> RegEx:
	if _label_re == null:
		_label_re = RegEx.create_from_string(LABEL_PATTERN)
	return _label_re


static func _read_text(file_name: String) -> String:
	var resolved := prompt_dir.path_join(file_name)
	if _text_cache.has(resolved):
		return String(_text_cache[resolved])
	var text := ""
	if FileAccess.file_exists(resolved):
		text = FileAccess.get_file_as_string(resolved)
	_text_cache[resolved] = text
	return text


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("EndingLine: %s is not valid JSON" % path)
		return {}
	return _dict(json.data)


static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
