extends SceneTree

# cvec_check: per-turn control-vector mixing on the native engine (P4.03a).
# Run from the repo root:
#   ./tools/godot.sh --headless --path game --script "$PWD/native/tests/cvec_check.gd"
# Env: LEILA_MODEL (model path, default below), LEILA_NGL (n_gpu_layers, default 99).
# Exit code 0 only when every check passes.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const SYSTEM_MSG := "You are a friendly barista. Reply as JSON."
const USER_MSG := "How was your morning?"
const MAX_TOKENS := 60
const MISSING_PATH := "/nonexistent_cvec_dir/missing.gguf"

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	var line := "%s  %s" % ["PASS" if ok else "FAIL", label]
	if detail != "":
		line += "  [" + detail + "]"
	print(line)
	if not ok:
		_failures += 1


func _messages() -> String:
	return JSON.stringify([
		{"role": "system", "content": SYSTEM_MSG},
		{"role": "user", "content": USER_MSG},
	], "", false)


func _schema() -> String:
	return JSON.stringify({
		"type": "object",
		"properties": {"say": {"type": "string", "maxLength": 120}},
		"required": ["say"],
	}, "", false)


func _sampling() -> Dictionary:
	return {"temperature": 0.0, "seed": 42}


func _vec(name: String) -> String:
	return ProjectSettings.globalize_path("res://data/steering/%s.gguf" % name)


func _gen(llm) -> Dictionary:
	return llm.generate(_messages(), _schema(), _sampling(), MAX_TOKENS, Callable(), Callable())


func _err_code(r: Dictionary) -> String:
	if r.get("ok", false):
		return ""
	return str(r.get("error", {}).get("code", ""))


func _err_msg(r: Dictionary) -> String:
	if r.get("ok", false):
		return ""
	return str(r.get("error", {}).get("message", ""))


# Generated text, or "ERR:<code>" so that a failed generate never equals a real text.
func _text(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "ERR:" + _err_code(r)
	return str(r.get("text", ""))


func _short(s: String) -> String:
	return s.substr(0, 90)


func _init() -> void:
	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path == "":
		model_path = DEFAULT_MODEL
	var ngl_env := OS.get_environment("LEILA_NGL")
	var ngl := int(ngl_env) if ngl_env != "" else 99
	var backend_dir := ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")
	print("cvec_check: model=" + model_path)
	print("cvec_check: backend_dir=" + backend_dir)
	print("cvec_check: n_gpu_layers=%d" % ngl)

	var llm = ClassDB.instantiate("LeilaLLM")
	var malice := _vec("malice")
	var possessive := _vec("possessive")

	# 1. Before load, set_control_vectors reports not_loaded.
	var r1: Dictionary = llm.set_control_vectors([])
	_check("1 set_control_vectors before load -> not_loaded", _err_code(r1) == "not_loaded", _err_code(r1))

	# load_model with n_threads omitted, so the default thread count is used.
	var info: Dictionary = llm.load_model({
		"model_path": model_path,
		"backend_dir": backend_dir,
		"n_gpu_layers": ngl,
	})
	if not info.get("ok", false) or not llm.is_loaded():
		_check("load_model ok", false, JSON.stringify(info, "", false))
		quit(1)
		return

	# 10. load_model reports the thread count actually used.
	var n_threads := int(info.get("n_threads", 0))
	print("cvec_check: n_threads=%d" % n_threads)
	_check("10 load_model result contains n_threads > 0", info.has("n_threads") and n_threads > 0, str(n_threads))

	# 2. Baseline with no vectors, then a repeat for determinism.
	var a := _text(_gen(llm))
	var a2 := _text(_gen(llm))
	_check("2 baseline gives text A, repeat gives A again", a == a2 and not a.begins_with("ERR:"), _short(a))

	# 3. malice x8 changes the text; the model is not reloaded.
	var r3: Dictionary = llm.set_control_vectors([{"path": malice, "scale": 8.0}])
	var b := _text(_gen(llm))
	_check("3 malice x8: applied, text B != A, no reload",
			bool(r3.get("ok", false)) and bool(r3.get("applied", false)) and b != a
			and not r3.has("load_ms") and llm.is_loaded(),
			"applied=%s B=%s" % [str(r3.get("applied", "?")), _short(b)])

	# 4. Same list again: no-op, text B again.
	var r4: Dictionary = llm.set_control_vectors([{"path": malice, "scale": 8.0}])
	var b2 := _text(_gen(llm))
	_check("4 same list: applied:false, text B again",
			bool(r4.get("ok", false)) and not bool(r4.get("applied", true)) and b2 == b,
			"applied=%s" % str(r4.get("applied", "?")))

	# 5. Clearing restores text A exactly.
	var r5: Dictionary = llm.set_control_vectors([])
	var a3 := _text(_gen(llm))
	_check("5 [] clears: text == A exactly",
			bool(r5.get("ok", false)) and bool(r5.get("applied", false)) and a3 == a,
			_short(a3))

	# 6. Mixing: malice 4.5 + possessive 0.5 differs from each alone; reversed order gives the same text.
	llm.set_control_vectors([{"path": malice, "scale": 4.5}])
	var m_malice := _text(_gen(llm))
	llm.set_control_vectors([{"path": possessive, "scale": 0.5}])
	var m_poss := _text(_gen(llm))
	var r6: Dictionary = llm.set_control_vectors([
		{"path": malice, "scale": 4.5},
		{"path": possessive, "scale": 0.5},
	])
	var m := _text(_gen(llm))
	var r6b: Dictionary = llm.set_control_vectors([
		{"path": possessive, "scale": 0.5},
		{"path": malice, "scale": 4.5},
	])
	var m_rev := _text(_gen(llm))
	_check("6 malice 4.5 + possessive 0.5 = M, distinct from each alone and from A, reversed order gives M",
			bool(r6.get("ok", false)) and bool(r6.get("applied", false))
			and bool(r6b.get("ok", false)) and bool(r6b.get("applied", false))
			and not m.begins_with("ERR:") and m != m_malice and m != m_poss and m != a and m_rev == m,
			"M=" + _short(m))

	# 7. Missing path: whole call fails, previous vectors stay bound (next generate still M).
	var r7: Dictionary = llm.set_control_vectors([
		{"path": malice, "scale": 1.0},
		{"path": MISSING_PATH, "scale": 1.0},
	])
	var m7 := _text(_gen(llm))
	_check("7 missing path -> control_vector_load_failed naming the path; next generate still M",
			_err_code(r7) == "control_vector_load_failed" and _err_msg(r7).find(MISSING_PATH) != -1 and m7 == m,
			_err_code(r7) + ": " + _err_msg(r7))

	# 8. Non-finite scale, and other malformed entries -> invalid_request.
	var r8a: Dictionary = llm.set_control_vectors([{"path": malice, "scale": INF}])
	var r8b: Dictionary = llm.set_control_vectors([{"path": malice, "scale": NAN}])
	var r8c: Dictionary = llm.set_control_vectors(["not a dictionary"])
	var r8d: Dictionary = llm.set_control_vectors([{"path": "", "scale": 1.0}])
	_check("8 non-finite scale and malformed entries -> invalid_request",
			_err_code(r8a) == "invalid_request" and _err_code(r8b) == "invalid_request"
			and _err_code(r8c) == "invalid_request" and _err_code(r8d) == "invalid_request",
			"%s %s %s %s" % [_err_code(r8a), _err_code(r8b), _err_code(r8c), _err_code(r8d)])

	# 9. Cached switch speed: alternate two already-cached lists 20 times.
	var list_one := [{"path": malice, "scale": 8.0}]
	var list_two := [{"path": malice, "scale": 4.5}, {"path": possessive, "scale": 0.5}]
	var max_ms := 0.0
	var all_ok := true
	for i in range(20):
		var lst = list_one if i % 2 == 0 else list_two
		var r9: Dictionary = llm.set_control_vectors(lst)
		all_ok = all_ok and bool(r9.get("ok", false)) and bool(r9.get("applied", false))
		max_ms = maxf(max_ms, float(r9.get("set_ms", 1e9)))
	print("cvec_check: max set_ms over 20 cached switches = %.3f" % max_ms)
	_check("9 cached switch: all applied, max set_ms < 5", all_ok and max_ms < 5.0, "max_ms=%.3f" % max_ms)

	llm.unload()
	print("cvec_check: %s" % ("ALL PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
