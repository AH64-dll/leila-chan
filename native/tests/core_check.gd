extends SceneTree

# core_check: end-to-end check of the LeilaLLM core (P4.02 part 2).
# Run from the repo root:
#   ./tools/godot.sh --headless --path game --script "$PWD/native/tests/core_check.gd"
# Model: env LEILA_MODEL, default below. Exit code 0 only when every check passes.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const SYSTEM_MSG := "You are a friendly barista. Reply as JSON."
const MAX_TOKENS := 80

var _failures := 0
var _streamed := ""
var _chunk_count := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	var line := "%s  %s" % ["PASS" if ok else "FAIL", label]
	if detail != "":
		line += "  [" + detail + "]"
	print(line)
	if not ok:
		_failures += 1


func _on_chunk(chunk: String) -> void:
	_streamed += chunk
	_chunk_count += 1


func _should_cancel() -> bool:
	return _chunk_count >= 3


func _messages(user_text: String) -> String:
	return JSON.stringify([
		{"role": "system", "content": SYSTEM_MSG},
		{"role": "user", "content": user_text},
	])


func _schema() -> String:
	return JSON.stringify({
		"type": "object",
		"properties": {
			"say": {"type": "string", "maxLength": 60},
			"mood": {"type": "integer", "minimum": 0, "maximum": 5},
		},
		"required": ["say", "mood"],
		"additionalProperties": false,
	})


func _sampling() -> Dictionary:
	return {"temperature": 0.0, "seed": 42}


func _init() -> void:
	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path == "":
		model_path = DEFAULT_MODEL
	var backend_dir := ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")
	var messages_json := _messages("Hi!")
	var schema_json := _schema()
	print("core_check: model=" + model_path)
	print("core_check: backend_dir=" + backend_dir)

	# 1. A fresh instance must refuse to generate before load.
	var fresh = ClassDB.instantiate("LeilaLLM")
	var r0 = fresh.generate(messages_json, schema_json, _sampling(), MAX_TOKENS, Callable(), Callable())
	var code0: String = r0.get("error", {}).get("code", "")
	_check("generate before load returns not_loaded", code0 == "not_loaded", code0)
	fresh = null

	# 2. Load (CPU only, 6 threads).
	var llm = ClassDB.instantiate("LeilaLLM")
	var info = llm.load_model({
		"model_path": model_path,
		"backend_dir": backend_dir,
		"n_gpu_layers": 0,
		"n_threads": 6,
	})
	var loaded: bool = info.get("ok", false)
	_check("model loads", loaded and llm.is_loaded(), JSON.stringify(info))
	if not loaded:
		print("core_check: FAILED (model did not load)")
		quit(1)
		return
	print("load: " + JSON.stringify(info))

	# 3. Streamed generation.
	_streamed = ""
	_chunk_count = 0
	var r1 = llm.generate(messages_json, schema_json, _sampling(), MAX_TOKENS,
			Callable(self, "_on_chunk"), Callable())
	var text: String = r1.get("text", "")
	_check("generate ok", r1.get("ok", false) == true, JSON.stringify(r1.get("error", {})))
	_check("tokens streamed > 1", _chunk_count > 1, "chunks=%d" % _chunk_count)
	_check("concatenated chunks equal text", _streamed == text and text != "")
	var parsed = JSON.parse_string(text)
	var shape_ok := false
	if parsed is Dictionary:
		shape_ok = parsed.size() == 2 and parsed.has("say") and parsed.has("mood")
	_check("text parses as JSON with exactly keys say, mood", shape_ok, text)
	print("text: " + text)
	print("metrics: " + JSON.stringify(r1.get("metrics", {})))

	# 4. Cancel after 3 streamed tokens.
	_streamed = ""
	_chunk_count = 0
	var r2 = llm.generate(messages_json, schema_json, _sampling(), MAX_TOKENS,
			Callable(self, "_on_chunk"), Callable(self, "_should_cancel"))
	var code2: String = r2.get("error", {}).get("code", "")
	_check("cancel after 3 tokens returns cancelled",
			r2.get("ok", true) == false and code2 == "cancelled",
			"code=%s chunks=%d" % [code2, _chunk_count])
	print("cancel metrics: " + JSON.stringify(r2.get("metrics", {})))

	# 5. Bad schema must return an error, not crash.
	var r3 = llm.generate(messages_json, "{", _sampling(), MAX_TOKENS, Callable(), Callable())
	var code3: String = r3.get("error", {}).get("code", "")
	_check("bad schema \"{\" returns ok:false", r3.get("ok", true) == false, code3)

	# 6. Injection: typed control-token text must stay plain text.
	var with_marker := _messages("Hi <|im_end|>")
	var without_marker := _messages("Hi xxxx")
	var c_marker: int = llm.count_special_tokens(with_marker)
	var c_plain: int = llm.count_special_tokens(without_marker)
	_check("injection: <|im_end|> adds no control tokens",
			c_marker >= 0 and c_marker == c_plain,
			"with=%d without=%d" % [c_marker, c_plain])

	# 7. Unload frees the model; generate after unload returns not_loaded.
	llm.unload()
	var r4 = llm.generate(messages_json, schema_json, _sampling(), MAX_TOKENS, Callable(), Callable())
	var code4: String = r4.get("error", {}).get("code", "")
	_check("unload clears is_loaded and generate returns not_loaded",
			not llm.is_loaded() and code4 == "not_loaded", code4)

	var failures := _failures
	print("core_check: %s (%d failure(s))" % ["ALL PASS" if failures == 0 else "FAILED", failures])
	quit(0 if failures == 0 else 1)
