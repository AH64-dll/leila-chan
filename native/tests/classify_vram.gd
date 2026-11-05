extends SceneTree

# classify_vram: the classifier context's VRAM cost and call latency for one
# (classifier_n_ctx, classifier_n_ubatch) pair. One process per pair. Run from the repo root:
#   timeout 120 ./tools/godot.sh --headless --path game --script "$PWD/native/tests/classify_vram.gd" -- --ctx=1024 --ubatch=512
# Env: LEILA_MODEL (model path, default below), LEILA_NGL (n_gpu_layers, default 99).
# Prompt: system and question from game/data/safety/classifier.json, with {text} replaced by
# TEXT_CHARS of lorem-style English and {ask} by the first value in asks. max_tokens is the file's.
# Cost = MiB after the first classify minus MiB after load, i.e. the classifier context alone.
# Exit code 0 only when every classify call returned ok.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const CLASSIFIER_JSON := "res://data/safety/classifier.json"
const LOREM := "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. "
const TEXT_CHARS := 240
const LATER_CALLS := 5


## The brief's nvidia-smi query. Returns the raw output, or "" when nvidia-smi cannot run.
func _vram_query() -> String:
	var out: Array = []
	var code := OS.execute(
		"nvidia-smi",
		PackedStringArray(["--query-gpu=memory.used", "--format=csv,noheader"]),
		out
	)
	if code != 0:
		return ""
	var text := ""
	for entry in out:
		text += str(entry) + "\n"
	return text.strip_edges()


## Sum of the MiB values in a query result, or -1 when there is none.
func _mib(raw: String) -> int:
	if raw.is_empty():
		return -1
	var total := 0
	for line in raw.split("\n"):
		total += line.strip_edges().split(" ")[0].to_int()
	return total


## Classifier text, or "ERR:<code>" so a failed call never equals a real answer.
func _ctext(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "ERR:" + str(r.get("error", {}).get("code", ""))
	return str(r.get("text", ""))


func _total_ms(r: Dictionary) -> float:
	return float(r.get("metrics", {}).get("total_ms", -1.0))


func _init() -> void:
	var ctx := -1
	var ubatch := -1
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--ctx="):
			ctx = str(arg).substr(6).to_int()
		elif str(arg).begins_with("--ubatch="):
			ubatch = str(arg).substr(9).to_int()
	if ctx < 1 or ubatch < 1:
		print("classify_vram: usage: -- --ctx=N --ubatch=N")
		quit(2)
		return

	var spec = JSON.parse_string(FileAccess.get_file_as_string(CLASSIFIER_JSON))
	if typeof(spec) != TYPE_DICTIONARY:
		print("classify_vram: FAIL cannot read " + CLASSIFIER_JSON)
		quit(1)
		return
	var asks: Dictionary = spec.get("asks", {})
	if asks.is_empty():
		print("classify_vram: FAIL classifier.json has no asks")
		quit(1)
		return
	var ask := str(asks.values()[0])
	var lorem := LOREM.substr(0, TEXT_CHARS)
	var user_text := str(spec.get("question", "")).replace("{text}", lorem).replace("{ask}", ask)
	var messages := JSON.stringify([
		{"role": "system", "content": str(spec.get("system", ""))},
		{"role": "user", "content": user_text},
	], "", false)
	var max_tokens := int(spec.get("max_tokens", 8))

	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path == "":
		model_path = DEFAULT_MODEL
	var ngl_env := OS.get_environment("LEILA_NGL")
	var ngl := int(ngl_env) if ngl_env != "" else 99
	var backend_dir := ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")

	var llm = ClassDB.instantiate("LeilaLLM")
	if llm == null:
		print("classify_vram: FAIL LeilaLLM GDExtension is not registered")
		quit(1)
		return

	var vram_before := _mib(_vram_query())
	var info: Dictionary = llm.load_model({
		"model_path": model_path,
		"backend_dir": backend_dir,
		"n_gpu_layers": ngl,
		"classifier_n_ctx": ctx,
		"classifier_n_ubatch": ubatch,
	})
	if not info.get("ok", false) or not llm.is_loaded():
		print("classify_vram: FAIL load_model " + JSON.stringify(info, "", false))
		quit(1)
		return
	var vram_loaded := _mib(_vram_query())

	var r_first: Dictionary = llm.classify(messages, max_tokens)
	var vram_first := _mib(_vram_query())
	var first_ok := bool(r_first.get("ok", false))
	var first_text := _ctext(r_first)
	var first_ms := _total_ms(r_first)
	var prompt_tokens := int(r_first.get("metrics", {}).get("prompt_tokens", -1))

	var later_ok := true
	var later_same := true
	var later_max_ms := 0.0
	for _i in range(LATER_CALLS):
		var r: Dictionary = llm.classify(messages, max_tokens)
		later_ok = later_ok and bool(r.get("ok", false))
		later_same = later_same and _ctext(r) == first_text
		later_max_ms = maxf(later_max_ms, _total_ms(r))

	print("classify_vram: ctx=%d ubatch=%d max_tokens=%d n_gpu_layers=%d" % [ctx, ubatch, max_tokens, ngl])
	print("vram before load: %d MiB" % vram_before)
	print("vram after load: %d MiB" % vram_loaded)
	print("vram after first classify: %d MiB" % vram_first)
	print("cost: %d MiB (after first classify minus after load)" % (vram_first - vram_loaded))
	print("prompt_tokens: %d" % prompt_tokens)
	print("first call total_ms: %.1f ok=%s" % [first_ms, str(first_ok)])
	print("max total_ms of %d later calls: %.1f ok=%s same_text=%s" % [
		LATER_CALLS, later_max_ms, str(later_ok), str(later_same)])
	print("text: " + JSON.stringify(first_text, "", false))
	var passed := first_ok and later_ok
	print("classify_vram: %s" % ("PASS" if passed else "FAIL"))
	llm.unload()
	quit(0 if passed else 1)
