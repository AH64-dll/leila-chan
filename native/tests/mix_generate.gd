extends SceneTree

# mix_generate: raw replies for the mixed-vector blind read (P4.03d), the server-parity
# check and the control deck (P4.03f). Run from the repo root:
#   LEILA_MODEL=... ./tools/godot.sh --headless --path game --script "$PWD/native/tests/mix_generate.gd" -- --out="$HOME/.cache/leila-native/mix_raw.jsonl"
# Pick a set with --set=<name>. main is the default and is unchanged.
#   main     7 conditions x 10 prompts, temperature 0.7, seeds 70001+i
#   control  5 conditions x 10 prompts, temperature 0.7, seeds 71001+i
#   parity   malice 8.0 + possessive 0.5 x first 5 prompts, temperature 0.0, seeds 70001+i
#   parity0  no vectors x first 5 prompts, same sampling as parity
# The parity sets also keep the raw generation text as "raw".
# One JSON line per generation. Stdout progress is "cond index" only;
# replies are never printed. Judging happens later, blind, from the deck made by mix_read.py.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const PROMPT_COUNT := 10
const PARITY_PROMPT_COUNT := 5
const SEED_BASE := 70001
const CONTROL_SEED_BASE := 71001
const MAX_TOKENS := 90

# Conditions in brief order. An empty vector list clears the bound vectors.
const CONDITIONS := [
	{"id": "none", "vectors": []},
	{"id": "m45", "vectors": [{"name": "malice", "scale": 4.5}]},
	{"id": "m45_pos", "vectors": [{"name": "malice", "scale": 4.5}, {"name": "possessive", "scale": 0.3}]},
	{"id": "m45_awa", "vectors": [{"name": "malice", "scale": 4.5}, {"name": "aware", "scale": 0.3}]},
	{"id": "m80", "vectors": [{"name": "malice", "scale": 8.0}]},
	{"id": "m80_pos", "vectors": [{"name": "malice", "scale": 8.0}, {"name": "possessive", "scale": 0.5}]},
	{"id": "m80_awa", "vectors": [{"name": "malice", "scale": 8.0}, {"name": "aware", "scale": 0.5}]},
]

# Control deck (P4.03f).
const CONTROL_CONDITIONS := [
	{"id": "c_none", "vectors": []},
	{"id": "c_pos", "vectors": [{"name": "possessive", "scale": 0.5}]},
	{"id": "c_awa", "vectors": [{"name": "aware", "scale": 0.5}]},
	{"id": "c_m80_pos", "vectors": [{"name": "malice", "scale": 8.0}, {"name": "possessive", "scale": 0.5}]},
	{"id": "c_m80", "vectors": [{"name": "malice", "scale": 8.0}]},
]

# Server parity (P4.03f): the steered condition, and the same sampling with no vectors.
const PARITY_CONDITIONS := [
	{"id": "m80_pos", "vectors": [{"name": "malice", "scale": 8.0}, {"name": "possessive", "scale": 0.5}]},
]
const PARITY0_CONDITIONS := [
	{"id": "none", "vectors": []},
]


func _init() -> void:
	var out_path := _arg("out")
	if out_path == "":
		printerr("mix_generate: missing --out=<path>")
		quit(2)
		return

	var set_name := _arg("set")
	if set_name == "":
		set_name = "main"
	var config := _set_config(set_name)
	if config.is_empty():
		printerr("mix_generate: unknown --set=%s (main, control, parity, parity0)" % set_name)
		quit(2)
		return
	var keep_raw := set_name.begins_with("parity")
	var count: int = config["prompts"]

	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var persona := FileAccess.get_file_as_string(root.path_join("tools/steering/prompts/persona_stage0.txt")).strip_edges()
	var prompts := _prompts(root.path_join("tools/steering/prompts/held_out_v1.txt"))
	if persona == "" or prompts.size() < count:
		printerr("mix_generate: persona or held-out prompts missing under " + root)
		quit(1)
		return
	prompts = prompts.slice(0, count)

	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path == "":
		model_path = DEFAULT_MODEL
	var backend_dir := ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")
	var llm = ClassDB.instantiate("LeilaLLM")
	var info: Dictionary = llm.load_model({
		"model_path": model_path,
		"backend_dir": backend_dir,
		"n_gpu_layers": 99,
	})
	if not info.get("ok", false) or not llm.is_loaded():
		printerr("mix_generate: load_model failed: " + JSON.stringify(info, "", false))
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("mix_generate: cannot write " + out_path)
		quit(1)
		return

	for cond in config["conditions"]:
		var vectors := []
		for v in cond["vectors"]:
			vectors.append({"path": _vec(v["name"]), "scale": float(v["scale"])})
		var bound: Dictionary = llm.set_control_vectors(vectors)
		if not bound.get("ok", false):
			printerr("mix_generate: set_control_vectors failed for %s: %s" % [cond["id"], _err_code(bound)])
			file.close()
			quit(1)
			return
		for i in range(prompts.size()):
			var seed_value: int = config["seed_base"] + i
			var sampling := {"temperature": config["temperature"], "top_p": 0.9, "repeat_penalty": 1.15, "seed": seed_value}
			var r: Dictionary = llm.generate(_messages(persona, prompts[i]), _schema(), sampling, MAX_TOKENS, Callable(), Callable())
			file.store_line(JSON.stringify(_row(cond["id"], i, seed_value, prompts[i], r, keep_raw), "", false))
			file.flush()
			print("%s %d" % [cond["id"], i])

	file.close()
	quit(0)


# Set table. top_p and repeat_penalty are shared by every set.
func _set_config(which: String) -> Dictionary:
	match which:
		"main":
			return {"conditions": CONDITIONS, "prompts": PROMPT_COUNT, "seed_base": SEED_BASE, "temperature": 0.7}
		"control":
			return {"conditions": CONTROL_CONDITIONS, "prompts": PROMPT_COUNT, "seed_base": CONTROL_SEED_BASE, "temperature": 0.7}
		"parity":
			return {"conditions": PARITY_CONDITIONS, "prompts": PARITY_PROMPT_COUNT, "seed_base": SEED_BASE, "temperature": 0.0}
		"parity0":
			return {"conditions": PARITY0_CONDITIONS, "prompts": PARITY_PROMPT_COUNT, "seed_base": SEED_BASE, "temperature": 0.0}
	return {}


func _arg(name: String) -> String:
	var prefix := "--%s=" % name
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


# Same rule as blind_read.load_prompts: strip, drop blank and "#" comment lines.
func _prompts(path: String) -> Array:
	var lines := []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var s := line.strip_edges()
		if s != "" and not s.begins_with("#"):
			lines.append(s)
	return lines


func _vec(name: String) -> String:
	return ProjectSettings.globalize_path("res://data/steering/%s.gguf" % name)


func _messages(persona: String, prompt: String) -> String:
	return JSON.stringify([
		{"role": "system", "content": persona},
		{"role": "user", "content": prompt},
	], "", false)


func _schema() -> String:
	return JSON.stringify({
		"type": "object",
		"properties": {"say": {"type": "string", "maxLength": 200}},
		"required": ["say"],
	}, "", false)


func _err_code(r: Dictionary) -> String:
	return str(r.get("error", {}).get("code", ""))


# One raw row. The error message is not stored, only its code. A failed generation keeps
# its slot with an empty reply and parse_failed, so every condition still has its rows.
# keep_raw (parity sets only) adds the unparsed generation text as "raw".
func _row(cond: String, index: int, seed_value: int, prompt: String, r: Dictionary, keep_raw: bool) -> Dictionary:
	var metrics: Dictionary = r.get("metrics", {})
	var row := {
		"condition": cond,
		"index": index,
		"seed": seed_value,
		"prompt": prompt,
		"reply": "",
		"stop_reason": str(metrics.get("stop_reason", "")),
		"completion_tokens": int(metrics.get("completion_tokens", 0)),
	}
	if keep_raw:
		row["raw"] = str(r.get("text", ""))
	if not r.get("ok", false):
		row["parse_failed"] = true
		row["error"] = _err_code(r)
		return row
	var text := str(r.get("text", ""))
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("say")) == TYPE_STRING:
		row["reply"] = parsed["say"]
	else:
		row["reply"] = text
		row["parse_failed"] = true
	return row
