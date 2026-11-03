extends Node
## PromptBuilder — assembles the layered prompt (docs/08 §1).
##
## One build() turns a turn context (docs/02 §4 step 1) into the message array
## the LLM facade sends (docs/07 §3.1) plus the per-layer token report the
## overlay (P1.17), the prompt lab (P1.20) and the transcript logger (P1.18)
## read.
##
## The eight layers of docs/08 §1 — persona, player, stage, path, scene,
## memories, events, rules (+ the enum glosses, + the values offered this turn)
## — form the system message, in exactly that order. The rest of the array is
## the history (docs/08 §1: the last ~12 exchanges as user/assistant pairs,
## the assistant side stored as spoken text only, never JSON), the current
## player turn, and an optional assistant prefill block.
##
## Context keys read from `ctx` (missing keys are legal):
##   stage: int, path: StringName/String ("" before stage 2), player_name: String,
##   scene: String or {"prompt", "variant", "event"}, memories: Array[String],
##   events: Array[String] (docs/08 §6 lines, this turn only),
##   offered: {"music": [...], "fx": [...], "cue": [...], "action": [...]},
##   history: Array of {"role": "user"|"assistant", "text"|"content"|"beats"|"turn"},
##   player_message: String, prefill: String,
##   path_runner_up: String, history_limit: int, history_token_budget: int.
##
## Where the docs are open, these choices hold and are covered by the suite:
## - A missing prompt file is reported in `debug.missing` and contributes an
##   empty layer. The builder never invents stage/path text (stage_2..5 and the
##   path modules land in P2.13), and a stage ≥ 2 turn without a path warns.
## - `memories` keeps the newest MEMORY_LIMIT facts (docs/08 §1 caps it at 8).
## - The history window keeps the last 12 exchanges with their pairs intact
##   and drops whole exchanges from the oldest end to stay inside the
##   docs/07 §3.1 ~1500-token history budget.
## - Token counts are estimates (CHARS_PER_TOKEN, calibrated against the P1.05
##   llama-tokenize measurements) until a real counter is injected with
##   set_token_counter() — llama-server's tokenizer can be plugged in later.
## - The prefill block is opt-in: llama-server renders the non-thinking
##   assistant header itself (docs/02 §9), so a trailing assistant message is
##   only appended when `ctx.prefill` is non-empty.

const PROMPT_DIR := "res://data/prompts"
const PERSONA_FILE := "persona.md"
const RULES_FILE := "rules.md"
const GLOSSES_FILE := "glosses.md"
const STAGE_FILE_FORMAT := "stage_%d.md"
const PATH_FILE_FORMAT := "path_%s.md"

## docs/08 §1 assembly order — the eight layers of the system message.
const LAYER_ORDER: Array[StringName] = [
	&"persona",
	&"player",
	&"stage",
	&"path",
	&"scene",
	&"memories",
	&"events",
	&"rules",
]
## Layers that never change during a run (docs/07 §3.1 budgets them at ~900
## tokens together) versus the per-turn situation layers.
const FIXED_LAYERS: Array[StringName] = [&"persona", &"player", &"stage", &"path", &"rules"]
const DYNAMIC_LAYERS: Array[StringName] = [&"scene", &"memories", &"events"]

const PLAYER_LINE := "The player is a boy called %s."
const MEMORY_HEADER := "Things you know about %s:"
const MEMORY_BULLET := "- "
const MEMORY_LIMIT := 8
const DEFAULT_PLAYER_NAME := "Senpai"
const EVENT_PREFIX := "EVENT: "

## docs/08 §1: the last ~12 exchanges ride in the message array.
const HISTORY_WINDOW := 12
## docs/07 §3.1: history ~12 exchanges (~1500 tokens).
const HISTORY_TOKEN_BUDGET := 1500

## docs/07 §3.1 budget lines. Reported, never silently enforced — the debug
## dict names every line the assembly exceeded. `system` is the fixed block
## (persona, player, stage, path, rules+glosses), the way P1.05 measured
## 857/873 tokens; `scene` covers the scene layer plus this turn's event lines
## (docs/08 §1 puts the current event with the scene). P1.05's CON-1 carry-over
## is answered by reporting the fixed and dynamic totals next to these lines.
const BUDGETS := {
	"system": 900,
	"memories": 150,
	"scene": 150,
	"history": 1500,
	"output": 600,
}

## Estimate calibration: the P1.05 llama-tokenize runs measured 857 tokens for
## a 3028-character stage-0 system prompt and 873 for a 3146-character stage-1
## one (3.53–3.60 characters per token on the real Qwen tokenizer).
const CHARS_PER_TOKEN := 3.6

## The newline a non-thinking Qwen3 chat template leaves before the answer
## (docs/02 §9 keeps thinking off). Available for callers that need the
## prefill block; off by default, see the class note.
const PREFILL_NEWLINE := "\n"

const ROLE_SYSTEM := "system"
const ROLE_USER := "user"
const ROLE_ASSISTANT := "assistant"

## Prompt file directory; the prompt lab and the tests point this at a scratch
## copy so they never edit the shipped content.
var prompt_dir := PROMPT_DIR

var _cache := {}
var _counter := Callable()


## Build the message array and the debug report for one turn.
## Returns {"messages": Array[Dictionary], "debug": Dictionary}.
func build(ctx: Dictionary) -> Dictionary:
	var stage := int(ctx.get("stage", 0))
	var path := String(ctx.get("path", ""))
	var player_name := String(ctx.get("player_name", "")).strip_edges()
	if player_name.is_empty():
		player_name = DEFAULT_PLAYER_NAME
	var missing: Array[String] = []
	var warnings: Array[String] = []
	var layers := _assemble(stage, path, player_name, ctx, missing, warnings)
	var window := _window(ctx.get("history", []), ctx, warnings)
	var messages := _messages(layers, window["messages"], ctx, warnings)
	var debug := _debug(ctx, stage, path, player_name, layers, window, messages, missing, warnings)
	return {"messages": messages, "debug": debug}


## Plug a real tokenizer in: a Callable(String) -> int (e.g. llama-server's
## /tokenize). Without one the builder reports CHARS_PER_TOKEN estimates.
func set_token_counter(counter: Callable) -> void:
	_counter = counter


## Drop the cached prompt files — a prompt-lab edit must be visible.
func clear_cache() -> void:
	_cache.clear()


## Tokens for `text`: the injected counter when there is one, the estimate
## otherwise.
func count_tokens(text: String) -> int:
	if _counter.is_valid():
		return int(_counter.call(text))
	return estimate_tokens(text)


## The built-in estimate (docs/07 §3.1 budgets are approximate by design).
func estimate_tokens(text: String) -> int:
	if text.is_empty():
		return 0
	return int(ceil(float(text.length()) / CHARS_PER_TOKEN))


## The spoken text of a turn (docs/08 §1): its beats' `say` lines joined with
## spaces — never the JSON, so old cues cannot be copied from the history.
## Accepts a Turn dictionary, a history entry, a beat array or a plain string.
func spoken_text(turn: Variant) -> String:
	if turn is String:
		return String(turn).strip_edges()
	if turn is Array:
		return _spoken_from_beats(turn)
	if turn is Dictionary:
		return _assistant_text(turn).strip_edges()
	return ""


func _assemble(
	stage: int,
	path: String,
	player_name: String,
	ctx: Dictionary,
	missing: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var layers := {}
	layers["persona"] = _read_layer(PERSONA_FILE, player_name, missing)
	layers["player"] = PLAYER_LINE % player_name
	layers["stage"] = _read_layer(STAGE_FILE_FORMAT % stage, player_name, missing)
	layers["path"] = _path_layer(stage, path, ctx, player_name, missing, warnings)
	layers["scene"] = _scene_layer(ctx)
	layers["memories"] = _memory_layer(ctx, player_name, warnings)
	layers["events"] = _events_layer(ctx, warnings)
	layers["rules"] = _rules_layer(ctx, player_name, missing)
	return layers


## docs/08 §1: stage_{0..5}.md by Instability; at stage ≥ 2 path_{primary}.md
## plus one line from the runner-up.
func _path_layer(
	stage: int,
	path: String,
	ctx: Dictionary,
	player_name: String,
	missing: Array[String],
	warnings: Array[String]
) -> String:
	if stage < 2:
		return ""
	if path.is_empty():
		warnings.append("path_unassigned_at_stage_%d" % stage)
		return ""
	var text := _read_layer(PATH_FILE_FORMAT % path, player_name, missing)
	var runner_up := String(ctx.get("path_runner_up", "")).strip_edges()
	if runner_up.is_empty():
		return text
	var line := _first_content_line(_read_layer(PATH_FILE_FORMAT % runner_up, player_name, missing))
	if line.is_empty():
		return text
	if text.is_empty():
		return line
	return text + "\n" + line


## docs/08 §1/§7: the scenario prompt, her goal, its resolved variant, and the current
## event when the loader resolved one for this turn.
func _scene_layer(ctx: Dictionary) -> String:
	var scene: Variant = ctx.get("scene", "")
	if scene is String:
		return String(scene).strip_edges()
	if not scene is Dictionary:
		return ""
	var parts: Array[String] = []
	for key: String in ["goal", "prompt", "variant"]:
		var value := String((scene as Dictionary).get(key, "")).strip_edges()
		if not value.is_empty():
			if (
				key == "goal"
				and not value.begins_with("Goal:")
				and not value.begins_with("Your goal:")
			):
				parts.append("Goal: " + value)
			else:
				parts.append(value)
	var event := String((scene as Dictionary).get("event", "")).strip_edges()
	if not event.is_empty():
		parts.append(EVENT_PREFIX + event)
	return "\n".join(parts)


## docs/08 §1: "Things you know about {player_name}: …", at most 8 facts; the
## newest facts win when there are more (corruption at stage ≥ 3 is P2.11).
func _memory_layer(ctx: Dictionary, player_name: String, warnings: Array[String]) -> String:
	var raw: Variant = ctx.get("memories", [])
	if not raw is Array:
		warnings.append("memories_not_an_array")
		return ""
	var facts: Array[String] = []
	for item: Variant in raw:
		var fact := String(item).strip_edges()
		if not fact.is_empty():
			facts.append(fact)
	if facts.size() > MEMORY_LIMIT:
		warnings.append("memories_trimmed_to_%d" % MEMORY_LIMIT)
		facts = _tail(facts, MEMORY_LIMIT)
	if facts.is_empty():
		return ""
	var lines: Array[String] = [MEMORY_HEADER % player_name]
	for fact: String in facts:
		lines.append(MEMORY_BULLET + fact)
	return "\n".join(lines)


## docs/08 §1/§6: EVENT / TRIGGER / OPPORTUNITY lines, this turn only. The
## Director and Triggers format them; the builder never invents one.
func _events_layer(ctx: Dictionary, warnings: Array[String]) -> String:
	var raw: Variant = ctx.get("events", [])
	if not raw is Array:
		warnings.append("events_not_an_array")
		return ""
	var lines: Array[String] = []
	for item: Variant in raw:
		var line := String(item).strip_edges()
		if not line.is_empty():
			lines.append(line)
	return "\n".join(lines)


## docs/08 §1: rules.md + the enum glosses (+ the dynamic enums the schema
## offers this turn, docs/08 §5).
func _rules_layer(ctx: Dictionary, player_name: String, missing: Array[String]) -> String:
	var parts: Array[String] = []
	var rules := _read_layer(RULES_FILE, player_name, missing)
	if not rules.is_empty():
		parts.append(rules)
	var glosses := _read_layer(GLOSSES_FILE, player_name, missing)
	if not glosses.is_empty():
		parts.append(glosses)
	var offered := _offered_line(ctx)
	if not offered.is_empty():
		parts.append(offered)
	return "\n".join(parts)


## The offered values of this turn (docs/02 §3 gates, built by P1.07). Empty
## when the caller offers nothing — the schema still constrains the answer.
func _offered_line(ctx: Dictionary) -> String:
	var raw: Variant = ctx.get("offered", {})
	if not raw is Dictionary:
		return ""
	var parts: Array[String] = []
	for key: String in ["music", "fx", "cue", "action"]:
		var values: Variant = (raw as Dictionary).get(key, [])
		if not values is Array or (values as Array).is_empty():
			continue
		var names: Array[String] = []
		for value: Variant in values:
			names.append(String(value))
		parts.append("%s: %s" % [key, ", ".join(names)])
	if parts.is_empty():
		return ""
	return "Offered this turn — " + "; ".join(parts) + "."


func _read_layer(file_name: String, player_name: String, missing: Array[String]) -> String:
	var path := prompt_dir.path_join(file_name)
	if not FileAccess.file_exists(path):
		missing.append(file_name)
		return ""
	return _cached_text(path).replace("{player_name}", player_name)


func _cached_text(path: String) -> String:
	if _cache.has(path):
		return String(_cache[path])
	var text := FileAccess.get_file_as_string(path).strip_edges()
	_cache[path] = text
	return text


func _first_content_line(text: String) -> String:
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.is_empty() and not trimmed.begins_with("#"):
			return trimmed
	return ""


func _tail(values: Array[String], count: int) -> Array[String]:
	var start := maxi(0, values.size() - count)
	var kept: Array[String] = []
	for i: int in range(start, values.size()):
		kept.append(values[i])
	return kept


## The sliding history window: the last `limit` exchanges, pairs intact, then
## trimmed from the oldest end until it fits the token budget.
func _window(raw: Variant, ctx: Dictionary, warnings: Array[String]) -> Dictionary:
	var limit := int(ctx.get("history_limit", HISTORY_WINDOW))
	if limit <= 0:
		limit = HISTORY_WINDOW
	var entries: Array[Dictionary] = []
	if raw is Array:
		var index := 0
		for item: Variant in raw:
			var message := _history_message(item)
			if message.is_empty():
				warnings.append("history_entry_%d_skipped" % index)
			else:
				entries.append(message)
			index += 1
	elif raw != null:
		warnings.append("history_not_an_array")
	var start := entries.size()
	var users := 0
	while start > 0 and users < limit:
		start -= 1
		if String(entries[start]["role"]) == ROLE_USER:
			users += 1
	var kept: Array[Dictionary] = []
	for i: int in range(start, entries.size()):
		kept.append(entries[i])
	if not kept.is_empty() and String(kept[0]["role"]) == ROLE_ASSISTANT:
		# The window opened on a reply whose player turn fell outside it.
		kept.remove_at(0)
	var budget := int(ctx.get("history_token_budget", HISTORY_TOKEN_BUDGET))
	var tokens := _messages_tokens(kept)
	while tokens > budget and _leading_exchange_size(kept) > 0:
		for _i: int in range(_leading_exchange_size(kept)):
			kept.remove_at(0)
		tokens = _messages_tokens(kept)
	return {
		"messages": kept,
		"limit": limit,
		"entries": entries.size(),
		"exchanges": _count_role(kept, ROLE_USER),
		"dropped": entries.size() - kept.size(),
		"tokens": tokens,
		"budget": budget,
	}


## One history entry as a message, or {} when it is unusable. Assistant turns
## are stored as spoken text only (docs/08 §1) — a Turn dictionary, a history
## entry wrapping one, or plain text all land here as her words.
func _history_message(item: Variant) -> Dictionary:
	if item is String:
		var plain := String(item).strip_edges()
		if plain.is_empty():
			return {}
		return {"role": ROLE_USER, "content": plain}
	if not item is Dictionary:
		return {}
	var entry: Dictionary = item
	var role := String(entry.get("role", ""))
	if role != ROLE_USER and role != ROLE_ASSISTANT:
		return {}
	var text := ""
	if role == ROLE_ASSISTANT:
		text = _assistant_text(entry).strip_edges()
	else:
		text = String(entry.get("text", entry.get("content", ""))).strip_edges()
	if text.is_empty():
		return {}
	return {"role": role, "content": text}


func _assistant_text(entry: Dictionary) -> String:
	if entry.has("beats"):
		return _spoken_from_beats(entry["beats"])
	var turn: Variant = entry.get("turn", null)
	if turn is Dictionary and (turn as Dictionary).has("beats"):
		return _spoken_from_beats((turn as Dictionary)["beats"])
	return String(entry.get("text", entry.get("content", "")))


func _spoken_from_beats(beats: Variant) -> String:
	if not beats is Array:
		return ""
	var says: Array[String] = []
	for beat: Variant in beats:
		if not beat is Dictionary:
			continue
		var say := String((beat as Dictionary).get("say", "")).strip_edges()
		if not say.is_empty():
			says.append(say)
	return " ".join(says)


## The four blocks of the array: the system message, the history, the current
## player turn, and the optional prefill.
func _messages(
	layers: Dictionary, history: Array[Dictionary], ctx: Dictionary, warnings: Array[String]
) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	messages.append({"role": ROLE_SYSTEM, "content": _system_text(layers)})
	messages.append_array(history)
	var player_message := String(ctx.get("player_message", "")).strip_edges()
	if player_message.is_empty():
		warnings.append("player_message_empty")
	else:
		messages.append({"role": ROLE_USER, "content": player_message})
	var prefill := String(ctx.get("prefill", ""))
	if not prefill.is_empty():
		messages.append({"role": ROLE_ASSISTANT, "content": prefill})
	return messages


func _system_text(layers: Dictionary) -> String:
	var parts: Array[String] = []
	for name: StringName in LAYER_ORDER:
		var text := String(layers.get(String(name), "")).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return "\n".join(parts)


func _debug(
	ctx: Dictionary,
	stage: int,
	path: String,
	player_name: String,
	layers: Dictionary,
	window: Dictionary,
	messages: Array[Dictionary],
	missing: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var report := {}
	var fixed_tokens := 0
	var dynamic_tokens := 0
	for name: StringName in LAYER_ORDER:
		var key := String(name)
		var text := String(layers.get(key, ""))
		var tokens := count_tokens(text)
		var group := "fixed"
		if DYNAMIC_LAYERS.has(name):
			group = "dynamic"
			dynamic_tokens += tokens
		else:
			fixed_tokens += tokens
		report[key] = {
			"tokens": tokens,
			"chars": text.length(),
			"present": not text.strip_edges().is_empty(),
			"group": group,
			"files": _layer_files(name, stage, path),
		}
	var system_tokens := fixed_tokens + dynamic_tokens
	var scene_block := int(report["scene"]["tokens"]) + int(report["events"]["tokens"])
	var history_tokens := int(window["tokens"])
	var roles: Array[String] = []
	var chars := 0
	for message: Dictionary in messages:
		roles.append(String(message["role"]))
		chars += String(message["content"]).length()
	return {
		"stage": stage,
		"path": path,
		"player_name": player_name,
		"layer_order": _layer_order_strings(),
		"layers": report,
		"history":
		{
			"limit": int(window["limit"]),
			"entries": int(window["entries"]),
			"exchanges": int(window["exchanges"]),
			"dropped": int(window["dropped"]),
			"tokens": history_tokens,
			"budget": int(window["budget"]),
		},
		"tokens":
		{
			"fixed": fixed_tokens,
			"dynamic": dynamic_tokens,
			"system": fixed_tokens,
			"system_message": system_tokens,
			"scene": scene_block,
			"memories": int(report["memories"]["tokens"]),
			"history": history_tokens,
			"total": system_tokens + history_tokens,
		},
		"budgets": BUDGETS.duplicate(),
		"over_budget":
		_over_budget(fixed_tokens, int(report["memories"]["tokens"]), scene_block, history_tokens),
		"messages": {"count": messages.size(), "roles": roles, "chars": chars},
		"missing": missing,
		"warnings": warnings,
		"prefill": String(ctx.get("prefill", "")),
		"token_counter": "injected" if _counter.is_valid() else "estimate",
	}


func _layer_files(name: StringName, stage: int, path: String) -> Array[String]:
	match name:
		&"persona":
			return [PERSONA_FILE]
		&"stage":
			return [STAGE_FILE_FORMAT % stage]
		&"path":
			if stage >= 2 and not path.is_empty():
				return [PATH_FILE_FORMAT % path]
		&"rules":
			return [RULES_FILE, GLOSSES_FILE]
	return []


func _layer_order_strings() -> Array[String]:
	var names: Array[String] = []
	for name: StringName in LAYER_ORDER:
		names.append(String(name))
	return names


## The docs/07 §3.1 lines this assembly exceeded, in doc order.
func _over_budget(
	fixed: int, memories: int, scene_block: int, history_tokens: int
) -> Array[String]:
	var over: Array[String] = []
	var measured := {
		"system": fixed,
		"memories": memories,
		"scene": scene_block,
		"history": history_tokens,
	}
	for key: String in ["system", "memories", "scene", "history"]:
		if int(measured[key]) > int(BUDGETS[key]):
			over.append(key)
	return over


func _messages_tokens(entries: Array[Dictionary]) -> int:
	var tokens := 0
	for entry: Dictionary in entries:
		tokens += count_tokens(String(entry["content"]))
	return tokens


func _count_role(entries: Array[Dictionary], role: String) -> int:
	var count := 0
	for entry: Dictionary in entries:
		if String(entry["role"]) == role:
			count += 1
	return count


func _leading_exchange_size(entries: Array[Dictionary]) -> int:
	if entries.is_empty() or String(entries[0]["role"]) != ROLE_USER:
		return 0
	var size := 1
	while size < entries.size() and String(entries[size]["role"]) != ROLE_USER:
		size += 1
	return size
