extends SceneTree
## P2.18 dev tool — one scenario playthrough against the real llama-server.
##
## It drives the same pieces the Date scene will use once the scene layer is
## wired into the Director: ScenarioLoader.resolve_scene() for the turn's
## goal/prompt/variant/event and PromptBuilder.build() for the assembled
## messages. Each turn is then sent to llama-server with the real Turn schema,
## and the reply is written into a Markdown transcript a reviewer can read
## without a GPU.
##
## Run (llama-server must be up; see tools/llm/serve.sh):
##   ./tools/godot.sh --headless --path game --quit-after 2000000 \
##     --script res://tools/scenario_playthrough.gd -- \
##     --scenario=game/data/scenarios/D01_classroom.json --stage=0 \
##     --lines=production/playtests/P2/scenarios/player_lines.json \
##     --out=production/playtests/P2/scenarios/D01_classroom_s0.md
##
## Flags (all optional except --scenario):
##   --stage=N         stage 0-5 (default 0)
##   --path=NAME       one of the canonical paths, or empty (default empty)
##   --player=NAME     the player's name (default Ren)
##   --turns=N         cap on turns played (default 8, also capped by the
##                     scenario's end.max_turns and the scripted lines)
##   --lines=PATH      player-lines JSON: {"<scenario id>": ["..."]} or ["..."]
##   --fires=T01@4     fire a scenario trigger line on turn 4 (repeatable,
##                     comma-separated) — the Triggers engine is not in this
##                     tool, so trigger lines are staged explicitly
##   --seed=N          llama-server seed (0 = server default)
##   --url=URL         llama-server base URL (default http://127.0.0.1:8089)
##   --out=PATH        transcript path, repo-relative or absolute
##
## Autoloads are absent in `--script` mode, so the tool instantiates
## PromptBuilder itself, reads the sampling row from data/sampling.json (the
## same file TurnContext reads; TurnContext cannot compile without GameState),
## and talks HTTPClient synchronously instead of awaiting HTTPRequest signals.
## `tools/test.sh` does not run this tool (no model in CI): the committed
## transcripts under production/playtests/ are the artifact, and
## tests/test_scenarios.py validates the JSON files they were made from.

const PromptBuilderScript := preload("res://autoload/PromptBuilder.gd")
const SAMPLING_PATH := "res://data/sampling.json"
const MAX_TOKENS := 600
const DEFAULT_TURNS := 8
const DEFAULT_PLAYER := "Ren"
const DEFAULT_URL := "http://127.0.0.1:8089"
const DEFAULT_LINES := "production/playtests/P2/scenarios/player_lines.json"
## docs/02 §9 fallback rows, only used when sampling.json is missing a column.
const SAMPLING_FALLBACK := {
	0: {"temperature": 0.75, "top_p": 0.90, "repeat_penalty": 1.10},
	1: {"temperature": 0.80, "top_p": 0.90, "repeat_penalty": 1.10},
	2: {"temperature": 0.80, "top_p": 0.92, "repeat_penalty": 1.12},
	3: {"temperature": 0.85, "top_p": 0.95, "repeat_penalty": 1.15},
	4: {"temperature": 0.90, "top_p": 0.95, "repeat_penalty": 1.15},
	5: {"temperature": 0.95, "top_p": 0.97, "repeat_penalty": 1.18},
}

var _builder: Node = null
var _scenario: Dictionary = {}
var _stage := 0
var _path := ""
var _player := DEFAULT_PLAYER
var _lines: Array[String] = []
var _fires: Dictionary = {}
var _out_path := ""
var _scenario_arg := ""
var _url := DEFAULT_URL
var _seed := 0
var _turns := DEFAULT_TURNS
var _invalid := 0
var _played := 0
var _end_reason := ""
var _history: Array[Dictionary] = []
var _md: Array[String] = []
var _started_ms := 0
var _model_label := "unknown"
var _stats := false


func _initialize() -> void:
	_scenario_arg = _arg("scenario", "")
	if _scenario_arg.is_empty():
		printerr("scenario_playthrough: --scenario=<path> is required")
		quit(2)
		return
	var scenario_path := _abs(_scenario_arg)
	if not FileAccess.file_exists(scenario_path):
		printerr("scenario_playthrough: no scenario at %s" % scenario_path)
		quit(2)
		return
	_scenario = ScenarioLoader.load_scenario(scenario_path)
	var validation: Dictionary = ScenarioLoader.validate_scenario(_scenario)
	if not bool(validation.get("ok", false)):
		printerr("scenario_playthrough: invalid scenario: %s" % str(validation.get("errors", [])))
		quit(2)
		return
	_stage = int(_arg("stage", "0"))
	_path = _arg("path", "")
	_player = _arg("player", DEFAULT_PLAYER)
	_url = _arg("url", DEFAULT_URL)
	_seed = int(_arg("seed", "0"))
	_turns = int(_arg("turns", str(DEFAULT_TURNS)))
	_stats = _arg("stats", "0") == "1"
	_out_path = _arg("out", "")
	_load_lines(_arg("lines", DEFAULT_LINES))
	_parse_fires(_arg("fires", ""))
	_builder = PromptBuilderScript.new()
	_builder.set_player_name(_player)
	_started_ms = Time.get_ticks_msec()
	if _stats:
		_print_stats()
	else:
		_run()
	_builder.free()


func _run() -> void:
	_model_label = _model_label_from(_request(_url + "/props", ""))
	_md.append_array(_header_lines())
	var limit := mini(_turns, mini(int(_scenario["end"]["max_turns"]), _lines.size()))
	while _played < limit:
		var turn_no := _played + 1
		var player_line := _lines[turn_no - 1]
		var scene := ScenarioLoader.resolve_scene(_scenario, _stage, _path, turn_no, _player)
		var events := _turn_events(scene, turn_no)
		var ctx := {
			"stage": _stage,
			"path": _path,
			"player_name": _player,
			"scene": scene,
			"events": events,
			"history": _history,
			"player_message": player_line,
		}
		var built: Dictionary = _builder.build(ctx)
		var reply := _post(built["messages"])
		if not bool(reply.get("ok", false)):
			_md.append("### Turn %d — REQUEST FAILED\n" % turn_no)
			_md.append("`%s`\n" % String(reply.get("error", "unknown")))
			_invalid += 1
			break
		var turn := _parse_turn(reply)
		if turn.is_empty():
			_md.append("### Turn %d — INVALID TURN JSON\n" % turn_no)
			_md.append("```\n%s\n```\n" % String(reply.get("text", "")).left(600))
			_invalid += 1
			break
		_played = turn_no
		_md.append_array(_turn_lines(turn_no, player_line, scene, events, turn, reply, built))
		_history.append({"role": "user", "text": player_line})
		_history.append({"role": "assistant", "beats": turn.get("beats", [])})
		var end_state := ScenarioLoader.evaluate_turn_end(
			_scenario, turn_no, false, String(turn.get("action", ""))
		)
		if bool(end_state.get("ended", false)):
			_end_reason = String(end_state.get("reason", ""))
			break
	if _end_reason.is_empty():
		_end_reason = "turn_cap_reached"
	_md.append_array(_footer_lines())
	if not _write_out():
		quit(2)
		return
	print(
		(
			"scenario_playthrough: %s stage %d path '%s' — %d turns, %d invalid, end %s"
			% [String(_scenario.get("id", "?")), _stage, _path, _played, _invalid, _end_reason]
		)
	)
	print("scenario_playthrough: wrote %s" % _abs(_out_path))
	quit(0 if _invalid == 0 else 1)


## The turn's staged event lines: the scenario's at_turn event and any trigger
## line requested with --fires (docs/08 §6 lines are prefixed "EVENT: ").
func _turn_events(scene: Dictionary, turn_no: int) -> Array[String]:
	var events: Array[String] = []
	var line := String(scene.get("event", "")).strip_edges()
	if not line.is_empty():
		events.append("EVENT: " + line)
	if _fires.has(turn_no):
		var trigger_line := ScenarioLoader.get_event_for_trigger(
			_scenario, String(_fires[turn_no]), _player
		)
		if not trigger_line.is_empty():
			events.append("EVENT: " + trigger_line)
	return events


func _turn_lines(
	turn_no: int,
	player_line: String,
	scene: Dictionary,
	events: Array[String],
	turn: Dictionary,
	reply: Dictionary,
	built: Dictionary
) -> Array[String]:
	var lines: Array[String] = []
	lines.append("### Turn %d\n" % turn_no)
	lines.append("**Player:** %s\n" % player_line)
	var variant := String(scene.get("variant", "")).strip_edges()
	if not variant.is_empty():
		lines.append("**Scene variant:** %s\n" % variant)
	if not events.is_empty():
		lines.append("**Events:** %s\n" % " / ".join(events))
	lines.append("**Leila:**\n")
	var beats: Variant = turn.get("beats", [])
	if beats is Array:
		for beat: Variant in beats:
			if not beat is Dictionary:
				continue
			lines.append(_beat_line(beat as Dictionary))
	lines.append("")
	var inner := String(turn.get("inner", "")).strip_edges()
	var tokens: Dictionary = (built["debug"] as Dictionary)["tokens"]
	(
		lines
		. append(
			(
				'- `read`=%s · `music`=%s · `fx`=%s · `action`=%s · dev-only `inner`: "%s"'
				% [
					String(turn.get("read", "?")),
					String(turn.get("music", "?")),
					String(turn.get("fx", "?")),
					String(turn.get("action", "?")),
					inner,
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"- prompt: system %d tok (fixed %d + scene %d, estimate) · %s · %.1f s"
				% [
					int(tokens.get("system_message", 0)),
					int(tokens.get("fixed", 0)),
					int(tokens.get("scene", 0)),
					_model_label,
					float(reply.get("seconds", 0.0)),
				]
			)
		)
	)
	lines.append("")
	return lines


func _int_text(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)


func _beat_line(beat: Dictionary) -> String:
	return (
		'- **%s/%s** (cue: %s) — "%s"'
		% [
			String(beat.get("feeling", "?")),
			_int_text(beat.get("intensity", "?")),
			String(beat.get("cue", "none")),
			String(beat.get("say", "")),
		]
	)


func _header_lines() -> Array[String]:
	var spec := _sampling_row(_stage)
	var end_rules: Dictionary = _scenario["end"]
	var lines: Array[String] = []
	lines.append("# %s — playthrough transcript\n" % String(_scenario.get("id", "?")))
	(
		lines
		. append(
			(
				'- scenario: `%s` (kind: %s, "%s")'
				% [
					_scenario_arg,
					String(_scenario.get("kind", "?")),
					String(_scenario.get("title", "?")),
				]
			)
		)
	)
	lines.append(
		(
			'- stage: %d · path: %s · player: "%s"'
			% [_stage, _path if not _path.is_empty() else "none", _player]
		)
	)
	(
		lines
		. append(
			(
				"- model: %s · sampling: temp %s, top_p %s, repeat %s · seed %s"
				% [
					_model_label,
					str(spec["temperature"]),
					str(spec["top_p"]),
					str(spec["repeat_penalty"]),
					"server default" if _seed == 0 else str(_seed),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"- end rules: min_turns %d, max_turns %d, on_goal `%s`"
				% [
					int(end_rules["min_turns"]),
					int(end_rules["max_turns"]),
					String(end_rules["on_goal"]),
				]
			)
		)
	)
	lines.append("- generated: %s" % Time.get_datetime_string_from_system())
	lines.append("- command: `%s`" % " ".join(OS.get_cmdline_user_args()))
	lines.append("")
	lines.append("## Scene\n")
	lines.append(
		"**Goal:** %s\n" % String(_scenario.get("goal", "")).replace("{player_name}", _player)
	)
	var prompt_text := String(_scenario.get("prompt", "")).replace("{player_name}", _player)
	lines.append("**Prompt:** %s\n" % prompt_text)
	var opening := ScenarioLoader.get_opening_beats(_scenario, _stage, _player)
	if not opening.is_empty():
		lines.append("**Opening beat (engine, not the model):**\n")
		for beat: Dictionary in opening:
			lines.append(_beat_line(beat))
		lines.append("")
	lines.append("## Turns\n")
	return lines


func _footer_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("## Summary\n")
	lines.append("- turns played: %d" % _played)
	lines.append("- invalid turns: %d" % _invalid)
	lines.append("- scene end: %s" % _end_reason)
	lines.append("- wall time: %.1f s" % (float(Time.get_ticks_msec() - _started_ms) / 1000.0))
	lines.append("")
	return lines


func _parse_turn(reply: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(String(reply.get("text", "")))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _post(messages: Array) -> Dictionary:
	var spec := _sampling_row(_stage)
	var body := {
		"messages": messages,
		"stream": false,
		"max_tokens": MAX_TOKENS,
		"response_format":
		{
			"type": "json_schema",
			"json_schema": {"name": "turn", "schema": TurnSchema.build_turn_schema(_stage)},
		},
		"chat_template_kwargs": {"enable_thinking": false},
		"cache_prompt": true,
		"temperature": spec["temperature"],
		"top_p": spec["top_p"],
		"repeat_penalty": spec["repeat_penalty"],
	}
	if _seed != 0:
		body["seed"] = _seed
	var payload := JSON.stringify(body)
	var attempt := _request(_url + "/v1/chat/completions", payload)
	if not bool(attempt.get("ok", false)):
		attempt = _request(_url + "/v1/chat/completions", payload)
	if not bool(attempt.get("ok", false)):
		return attempt
	var parsed: Variant = JSON.parse_string(String(attempt.get("text", "")))
	if not parsed is Dictionary:
		return {"ok": false, "error": "response is not JSON"}
	var choices: Variant = (parsed as Dictionary).get("choices", [])
	if not choices is Array or (choices as Array).is_empty():
		return {"ok": false, "error": "response has no choices"}
	var message: Variant = ((choices as Array)[0] as Dictionary).get("message", {})
	var content := String((message as Dictionary).get("content", ""))
	return {
		"ok": true,
		"text": content,
		"model": String(attempt.get("model", "?")),
		"seconds": float(attempt.get("seconds", 0.0)),
	}


func _model_label_from(props: Dictionary) -> String:
	if not bool(props.get("ok", false)):
		return "unknown"
	var parsed: Variant = JSON.parse_string(String(props.get("text", "")))
	if not parsed is Dictionary:
		return "unknown"
	var model_path := String((parsed as Dictionary).get("model_path", ""))
	if not model_path.is_empty():
		return model_path.get_file()
	return String((parsed as Dictionary).get("model_alias", "unknown"))


## `--stats=1`: build the turn-1 system message, tokenize it with the real
## model tokenizer, and print one JSON line. This is the ≤ 900-token evidence
## for the assembled prompt; it never generates anything.
func _print_stats() -> void:
	var scene := ScenarioLoader.resolve_scene(_scenario, _stage, _path, 1, _player)
	var built := _build_for_stats(scene)
	var bare := _build_for_stats({})
	var messages: Array = built["messages"]
	var bare_messages: Array = bare["messages"]
	var system := String((messages[0] as Dictionary).get("content", ""))
	var bare_system := String((bare_messages[0] as Dictionary).get("content", ""))
	var debug: Dictionary = built["debug"]
	var tokens: Dictionary = debug["tokens"]
	print(
		(
			JSON
			. stringify(
				{
					"id": String(_scenario.get("id", "?")),
					"stage": _stage,
					"path": _path,
					"fixed_tokens": _token_count(bare_system),
					"assembled_tokens": _token_count(system),
					"variant_tokens": _token_count(String(scene.get("variant", ""))),
					"estimate_fixed": int(tokens.get("fixed", 0)),
					"estimate_scene": int(tokens.get("scene", 0)),
					"chars": system.length(),
					"missing": debug.get("missing", []),
					"warnings": debug.get("warnings", []),
				}
			)
		)
	)
	quit(0)


func _build_for_stats(scene: Variant) -> Dictionary:
	return (
		_builder
		. build(
			{
				"stage": _stage,
				"path": _path,
				"player_name": _player,
				"scene": scene,
				"events": [],
				"history": [],
				"player_message": "I'm here.",
			}
		)
	)


## Real token count through llama-server's /tokenize (the same Qwen tokenizer
## the turn uses). -1 when the server is unreachable.
func _token_count(text: String) -> int:
	var reply := _request(_url + "/tokenize", JSON.stringify({"content": text}))
	if not bool(reply.get("ok", false)):
		return -1
	var parsed: Variant = JSON.parse_string(String(reply.get("text", "")))
	if not parsed is Dictionary:
		return -1
	var tokens: Variant = (parsed as Dictionary).get("tokens", [])
	if not tokens is Array:
		return -1
	return (tokens as Array).size()


## The docs/02 §9 sampling row for `stage`, read from the same data file the
## game loads. A missing file or column keeps the documented fallback values.
func _sampling_row(stage: int) -> Dictionary:
	var row: Dictionary = (
		(SAMPLING_FALLBACK.get(stage, SAMPLING_FALLBACK[0]) as Dictionary).duplicate()
	)
	if not FileAccess.file_exists(SAMPLING_PATH):
		return row
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLING_PATH))
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("stages") is Dictionary):
		return row
	var source: Variant = ((parsed as Dictionary)["stages"] as Dictionary).get(str(stage))
	if not source is Dictionary:
		return row
	for key: String in ["temperature", "top_p", "repeat_penalty"]:
		var value: Variant = (source as Dictionary).get(key)
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			row[key] = float(value)
	return row


## A synchronous HTTP round trip: autoloads and node signals are unavailable in
## `--script` mode, so HTTPClient is polled directly. Empty payload = GET.
func _request(url: String, payload: String) -> Dictionary:
	var rest := url
	var scheme := "http"
	if url.contains("://"):
		var prefix := url.split("://", false)
		scheme = prefix[0]
		rest = prefix[1]
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := host_port
	var port := 80
	if host_port.contains(":"):
		var bits := host_port.rsplit(":", true, 1)
		host = bits[0]
		port = int(bits[1])
	var tls: TLSOptions = TLSOptions.client() if scheme == "https" else null
	var method := HTTPClient.METHOD_GET if payload.is_empty() else HTTPClient.METHOD_POST
	var started := Time.get_ticks_msec()
	var client := HTTPClient.new()
	var err := client.connect_to_host(host, port, tls)
	if err != OK:
		return {"ok": false, "error": "connect error %d" % err}
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		client.poll()
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "error": "connect failed (status %d)" % client.get_status()}
	var headers: PackedStringArray = ["Content-Type: application/json"]
	err = client.request(method, path, headers, payload)
	if err != OK:
		client.close()
		return {"ok": false, "error": "request error %d" % err}
	var body := PackedByteArray()
	while true:
		client.poll()
		var status := client.get_status()
		if status == HTTPClient.STATUS_BODY:
			var chunk := client.read_response_body_chunk()
			if chunk.size() > 0:
				body.append_array(chunk)
			else:
				OS.delay_msec(5)
		elif status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
			break
		elif (
			status
			in [
				HTTPClient.STATUS_CANT_CONNECT,
				HTTPClient.STATUS_CANT_RESOLVE,
				HTTPClient.STATUS_CONNECTION_ERROR,
				HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,
			]
		):
			client.close()
			return {"ok": false, "error": "transport failed (status %d)" % status}
		else:
			OS.delay_msec(5)
	var code := client.get_response_code()
	var text := body.get_string_from_utf8()
	client.close()
	var model := "?"
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		model = String((parsed as Dictionary).get("model", "?"))
	if code != 200:
		return {"ok": false, "error": "HTTP %d: %s" % [code, text.left(200)]}
	return {
		"ok": true,
		"text": text,
		"model": model,
		"seconds": float(Time.get_ticks_msec() - started) / 1000.0,
	}


func _load_lines(path: String) -> void:
	_lines = []
	var raw := FileAccess.get_file_as_string(_abs(path))
	if raw.is_empty():
		push_warning("scenario_playthrough: no player lines at %s" % path)
		return
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		parsed = (parsed as Dictionary).get(String(_scenario.get("id", "")), [])
	if parsed is Array:
		for item: Variant in parsed:
			_lines.append(String(item))


func _parse_fires(spec: String) -> void:
	for part: String in spec.split(",", false):
		var bits := part.split("@", false)
		if bits.size() != 2:
			push_warning("scenario_playthrough: bad --fires entry '%s'" % part)
			continue
		_fires[int(bits[1])] = bits[0]


func _write_out() -> bool:
	if _out_path.is_empty():
		return true
	var file := FileAccess.open(_abs(_out_path), FileAccess.WRITE)
	if file == null:
		printerr("scenario_playthrough: cannot write %s" % _out_path)
		return false
	file.store_string("\n".join(_md).strip_edges() + "\n")
	file.close()
	return true


## Repo-relative paths resolve against the repository root (the worktree), so
## the same command works no matter where Godot is launched from.
func _abs(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()


func _arg(name: String, fallback: String) -> String:
	for raw: String in OS.get_cmdline_user_args():
		var prefix := "--" + name + "="
		if raw.begins_with(prefix):
			return raw.trim_prefix(prefix)
	return fallback
