extends SceneTree

# cache_check: prompt-prefix KV reuse on the native engine (P4.05).
# Run from the repo root:
#   ./tools/godot.sh --headless --path game --script "$PWD/native/tests/cache_check.gd"
# Env: LEILA_MODEL (model path, default below), LEILA_NGL (n_gpu_layers, default 99).
# Exit code 0 only when every check passes.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const SYSTEM_SENTENCE := "You are a friendly barista in a small harbour town, and you know every regular by name."
const SYSTEM_REPEATS := 35
const USER_A := "Hello."
const USER_B := "Tell me about rain."
const MAX_TOKENS := 30
const N_UBATCH := 512
const MALICE_PATH := "res://data/steering/malice.gguf"

var _failures := 0
var _reload_result: Dictionary = {}


func _check(label: String, ok: bool, detail: String = "") -> void:
	var line := "%s  %s" % ["PASS" if ok else "FAIL", label]
	if detail != "":
		line += "  [" + detail + "]"
	print(line)
	if not ok:
		_failures += 1


func _system_text() -> String:
	var text := ""
	for i in SYSTEM_REPEATS:
		text += SYSTEM_SENTENCE + " "
	return text


func _messages(user: String) -> String:
	return JSON.stringify([
		{"role": "system", "content": _system_text()},
		{"role": "user", "content": user},
	], "", false)


func _sampling() -> Dictionary:
	return {"temperature": 0.0, "top_k": 1}


# No schema: the engine treats an empty schema_json as unconstrained.
func _gen(llm, user: String, cancel: Callable = Callable()) -> Dictionary:
	return llm.generate(_messages(user), "", _sampling(), MAX_TOKENS, Callable(), cancel)


func _err_code(r: Dictionary) -> String:
	if r.get("ok", false):
		return ""
	return str(r.get("error", {}).get("code", ""))


# Generated text, or "ERR:<code>" so that a failed generate never equals a real text.
func _text(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "ERR:" + _err_code(r)
	return str(r.get("text", ""))


func _metric(r: Dictionary, key: String) -> int:
	var metrics: Dictionary = r.get("metrics", {})
	return int(metrics.get(key, -1))


func _reused(r: Dictionary) -> int:
	return _metric(r, "cache_reused_tokens")


func _prompt_tokens(r: Dictionary) -> int:
	return _metric(r, "prompt_tokens")


func _reload(llm, cfg: Dictionary) -> void:
	_reload_result = llm.load_model(cfg)


# Scripted user turns for checks 10 and 11: one growing conversation.
const TURNS := [
	"Hello.",
	"Tell me about rain.",
	"Do you have a seat free by the window?",
	"What do you recommend on a wet afternoon?",
	"Thanks. How long have you been open?",
	"Goodbye, see you tomorrow.",
]


# Messages for one turn: the system prompt, then the conversation so far.
func _turn_messages(history: Array) -> String:
	var msgs: Array = [{"role": "system", "content": _system_text()}]
	msgs.append_array(history)
	return JSON.stringify(msgs, "", false)


# Same sampling and limits as _gen, with the messages given as JSON.
func _gen_messages(llm, messages_json: String) -> Dictionary:
	return llm.generate(messages_json, "", _sampling(), MAX_TOKENS, Callable(), Callable())


# Runs TURNS as one growing conversation. The cache-on pass takes each assistant reply from its own output.
# The cache-off pass replays the same messages with clear_prompt_cache() before each turn.
func _conversation(llm) -> Dictionary:
	var history: Array = []
	var msgs_list: Array = []
	var on_texts: Array = []
	var on_reused: Array = []
	var on_results: Array = []
	var off_texts: Array = []
	var all_ok := true
	llm.clear_prompt_cache()
	for user in TURNS:
		history.append({"role": "user", "content": user})
		var msgs := _turn_messages(history)
		var r: Dictionary = _gen_messages(llm, msgs)
		all_ok = all_ok and bool(r.get("ok", false))
		msgs_list.append(msgs)
		on_texts.append(_text(r))
		on_reused.append(_reused(r))
		on_results.append(r)
		history.append({"role": "assistant", "content": _text(r)})
	for turn_msgs in msgs_list:
		llm.clear_prompt_cache()
		var r_off: Dictionary = _gen_messages(llm, turn_msgs)
		all_ok = all_ok and bool(r_off.get("ok", false))
		off_texts.append(_text(r_off))
	return {"on_texts": on_texts, "off_texts": off_texts, "on_reused": on_reused,
			"on_results": on_results, "all_ok": all_ok}


# True when every turn's cache-on text equals its cache-off text. Prints the first turns that differ.
func _turns_match(conv: Dictionary, label: String) -> bool:
	var on_texts: Array = conv["on_texts"]
	var off_texts: Array = conv["off_texts"]
	var same := true
	for k in on_texts.size():
		if on_texts[k] != off_texts[k]:
			same = false
			print("cache_check: %s turn %d cache on  = %s" % [label, k + 1, JSON.stringify(on_texts[k])])
			print("cache_check: %s turn %d cache off = %s" % [label, k + 1, JSON.stringify(off_texts[k])])
	return same


# Number of turns whose cache-on pass reused a prefix.
func _turns_reusing(conv: Dictionary) -> int:
	var n := 0
	for reused in conv["on_reused"]:
		if int(reused) > 0:
			n += 1
	return n


func _init() -> void:
	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path == "":
		model_path = DEFAULT_MODEL
	var ngl_env := OS.get_environment("LEILA_NGL")
	var ngl := int(ngl_env) if ngl_env != "" else 99
	var backend_dir := ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")
	print("cache_check: model=" + model_path)
	print("cache_check: n_gpu_layers=%d" % ngl)

	var llm = ClassDB.instantiate("LeilaLLM")
	var cfg := {
		"model_path": model_path,
		"backend_dir": backend_dir,
		"n_gpu_layers": ngl,
		"n_ubatch": 512,
	}
	var info: Dictionary = llm.load_model(cfg)
	if not info.get("ok", false) or not llm.is_loaded():
		_check("load_model ok", false, JSON.stringify(info, "", false))
		quit(1)
		return
	var n_ubatch := int(info.get("n_ubatch", -1))
	print("cache_check: n_ubatch=%d" % n_ubatch)

	# 1. The first generate has nothing cached.
	var r1: Dictionary = _gen(llm, USER_A)
	_check("1 first generate reuses 0", bool(r1.get("ok", false)) and _reused(r1) == 0,
			"reused=%d prompt=%d" % [_reused(r1), _prompt_tokens(r1)])

	# 2. The same messages again reuse the prompt, rounded down to a multiple of n_ubatch.
	var r2: Dictionary = _gen(llm, USER_A)
	var reuse2 := _reused(r2)
	_check("2 same messages again: reuse > 0 and a multiple of 512",
			bool(r2.get("ok", false)) and reuse2 > 0 and reuse2 % N_UBATCH == 0,
			"reused=%d prompt=%d" % [reuse2, _prompt_tokens(r2)])

	# 3. B after A reuses the shared system prefix, at the default n_ubatch.
	var r3: Dictionary = _gen(llm, USER_B)
	var text_b_reused := _text(r3)
	_check("3 B after A: reuse > 0 at the default n_ubatch 512",
			bool(r3.get("ok", false)) and _reused(r3) > 0 and n_ubatch == N_UBATCH,
			"reused=%d n_ubatch=%d" % [_reused(r3), n_ubatch])

	# 4. B after clear_prompt_cache() decodes its whole prompt. The two texts must match byte for byte.
	# 5. clear_prompt_cache() returns true, and the next generate reuses 0.
	var cleared: bool = llm.clear_prompt_cache()
	var r4: Dictionary = _gen(llm, USER_B)
	var text_b_fresh := _text(r4)
	var same := bool(r3.get("ok", false)) and bool(r4.get("ok", false)) \
			and text_b_reused == text_b_fresh and not text_b_fresh.begins_with("ERR:")
	if not same:
		print("cache_check: B after A    = " + JSON.stringify(text_b_reused))
		print("cache_check: B after clear = " + JSON.stringify(text_b_fresh))
	_check("4 B after A == B after clear_prompt_cache, byte for byte", same,
			"reused_text=%d fresh_text=%d" % [text_b_reused.length(), text_b_fresh.length()])
	# 4b. B after A reuses a prefix, so check 4 compares a reused decode with a fresh one.
	_check("4b B after A reuses > 0", _reused(r3) > 0, "reused=%d" % _reused(r3))

	_check("5 clear_prompt_cache returns true; the next generate reuses 0",
			cleared and bool(r4.get("ok", false)) and _reused(r4) == 0,
			"cleared=%s reused=%d" % [str(cleared), _reused(r4)])

	# 6. A cancel during prompt decode leaves no claim on the cache: the next generate reuses 0.
	var cancel_now := func() -> bool:
		return true
	var r6: Dictionary = _gen(llm, USER_A, cancel_now)
	var r7: Dictionary = _gen(llm, USER_A)
	_check("6 cancel during prompt decode: code cancelled; next generate succeeds with reuse 0",
			_err_code(r6) == "cancelled" and bool(r7.get("ok", false)) and _reused(r7) == 0,
			"code=%s next_reused=%d" % [_err_code(r6), _reused(r7)])

	# 7. A control vector set between A and B leaves the prefix in place: B still reuses > 0.
	# The cache holds A's prompt after r7.
	var vec_result: Dictionary = llm.set_control_vectors([
		{"path": ProjectSettings.globalize_path(MALICE_PATH), "scale": 4.5},
	])
	var r8: Dictionary = _gen(llm, USER_B)
	_check("7 malice x4.5 set between A and B: B still reuses > 0",
			bool(vec_result.get("ok", false)) and bool(vec_result.get("applied", false))
			and bool(r8.get("ok", false)) and _reused(r8) > 0,
			"applied=%s reused=%d" % [str(vec_result.get("applied", "?")), _reused(r8)])
	llm.set_control_vectors([])

	# 10. Six scripted turns at temperature 0, one growing message list. With the cache on, each turn's text equals
	# the text decoded from scratch after clear_prompt_cache(), byte for byte, and at least 4 turns reuse a prefix.
	var conv10: Dictionary = _conversation(llm)
	var reusing10 := _turns_reusing(conv10)
	var same10 := _turns_match(conv10, "10")
	_check("10 six turns: each turn byte-identical with clear_prompt_cache; at least 4 turns reuse > 0",
			bool(conv10["all_ok"]) and same10 and reusing10 >= 4,
			"reused=%s" % str(conv10["on_reused"]))

	# 11. The same at malice x4.5. The vector is set before the first turn and left unchanged during the turns.
	var vec11: Dictionary = llm.set_control_vectors([
		{"path": ProjectSettings.globalize_path(MALICE_PATH), "scale": 4.5},
	])
	var conv11: Dictionary = _conversation(llm)
	var reusing11 := _turns_reusing(conv11)
	var same11 := _turns_match(conv11, "11")
	llm.set_control_vectors([])
	_check("11 six turns at malice x4.5: byte-identical with clear_prompt_cache; at least 4 turns reuse > 0",
			bool(vec11.get("ok", false)) and bool(vec11.get("applied", false))
			and bool(conv11["all_ok"]) and same11 and reusing11 >= 4,
			"applied=%s reused=%s" % [str(vec11.get("applied", "?")), str(conv11["on_reused"])])

	# 12. Checkpoint costs of one turn: turn 6 of check 10 (cache on, no control vector).
	var r12: Dictionary = conv10["on_results"][5]
	var m12: Dictionary = r12.get("metrics", {})
	var save12 := float(m12.get("cache_save_ms", -1.0))
	var restore12 := float(m12.get("cache_restore_ms", -1.0))
	var bytes12 := int(m12.get("cache_state_bytes", -1))
	print("cache_check: turn 6 cache_save_ms=%.2f cache_restore_ms=%.2f cache_state_bytes=%d" % [save12, restore12, bytes12])
	# Turn 1 starts from an empty cache, so its decode saves the checkpoints: this is the save cost. Also prompt lengths.
	var m_first: Dictionary = conv10["on_results"][0].get("metrics", {})
	print("cache_check: turn 1 cache_save_ms=%.2f cache_state_bytes=%d" % [float(m_first.get("cache_save_ms", -1.0)), int(m_first.get("cache_state_bytes", -1))])
	var prompts12: Array = []
	for r_t in conv10["on_results"]:
		prompts12.append(_prompt_tokens(r_t))
	print("cache_check: check 10 prompt tokens per turn = %s" % str(prompts12))
	_check("12 checkpoint metrics on turn 6: restore_ms > 0 and state bytes > 0",
			restore12 > 0.0 and bytes12 > 0 and save12 >= 0.0,
			"save_ms=%.2f restore_ms=%.2f state_bytes=%d" % [save12, restore12, bytes12])

	# 8. Reload with prompt_cache 0 on a worker thread. The main thread polls load_progress() meanwhile.
	llm.unload()
	var cfg_off := cfg.duplicate()
	cfg_off["prompt_cache"] = 0
	var samples: Array = []
	var th := Thread.new()
	th.start(Callable(self, "_reload").bind(llm, cfg_off))
	while th.is_alive():
		samples.append(float(llm.load_progress()))
		OS.delay_msec(5)
	th.wait_to_finish()
	samples.append(float(llm.load_progress()))
	var reload_ok := bool(_reload_result.get("ok", false))
	var r9: Dictionary = _gen(llm, USER_A)
	var r10: Dictionary = _gen(llm, USER_A)
	_check("8 reload with prompt_cache 0: two generates reuse 0",
			reload_ok and _reused(r9) == 0 and _reused(r10) == 0,
			"load_ok=%s reused=%d,%d" % [str(reload_ok), _reused(r9), _reused(r10)])

	# 9. load_progress() rose during the load and ended at 1.0.
	var rises := 0
	for i in range(1, samples.size()):
		if float(samples[i]) > float(samples[i - 1]):
			rises += 1
	var last := float(samples.back())
	_check("9 load_progress rises during the load and ends at 1.0",
			rises > 0 and last == 1.0,
			"samples=%d rises=%d last=%.2f" % [samples.size(), rises, last])

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILED" % _failures)
	quit(0 if _failures == 0 else 1)
