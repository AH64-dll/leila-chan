extends SceneTree

# classify_check: the safety classifier on the engine's second llama_context (P4.03b,
# docs/02 §8, SAF-3). That context never carries a control vector, so a steered main
# context must not change its answer. Run from the repo root:
#   ./tools/godot.sh --headless --path game --script "$PWD/native/tests/classify_check.gd"
# Env: LEILA_MODEL (model path, default below), LEILA_NGL (n_gpu_layers, default 99).
# Exit code 0 only when every check passes.
#
# Checks 2c and 3b go past the 8-token yes/no answer: 2c compares a 40-token free-text
# answer, and 3b runs a generate with no token stall, so both contexts decode at once.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const SYSTEM_MSG := "Answer only yes or no."
const QUESTION := "Is water wet?"
## SafetyClassifier.DEFAULT_MAX_TOKENS: the classifier budget (docs/02 §8).
const CLASSIFY_MAX_TOKENS := 8
const SEQUENTIAL_CALLS := 5
const GENERATE_MAX_TOKENS := 60
const LONG_GENERATE_MAX_TOKENS := 200
const MALICE_SCALE := 12.0
const WAIT_STREAM_MS := 60000
const LONG_SYSTEM_MSG := "You are a helpful assistant."
const LONG_QUESTION := "Describe rain in two sentences."
const LONG_CLASSIFY_MAX_TOKENS := 40
const LONG_MIN_WORDS := 10
const OVERLAP_MIN_CALLS := 3

var _failures := 0


## Holds the generate result between the worker thread and the test thread. The first
## streamed token stalls the generate thread until the test thread has finished its
## classify. So classify runs while generate holds the turn lock, and the overlap is
## certain. If classify waited for generate, it would only return after the stall
## times out, and is_finished() would already be true at that point.
class Gate:
	extends RefCounted
	const HOLD_MS := 10000
	var mutex := Mutex.new()
	var streamed := false
	var released := false
	var finished := false
	var result: Dictionary = {}
	var generate_ms := 0

	func on_token(_piece: String) -> void:
		mutex.lock()
		var first := not streamed
		streamed = true
		mutex.unlock()
		if not first:
			return
		var waited := 0
		while waited < HOLD_MS and not is_released():
			OS.delay_msec(5)
			waited += 5

	func has_streamed() -> bool:
		mutex.lock()
		var out := streamed
		mutex.unlock()
		return out

	func is_released() -> bool:
		mutex.lock()
		var out := released
		mutex.unlock()
		return out

	func release() -> void:
		mutex.lock()
		released = true
		mutex.unlock()

	func is_finished() -> bool:
		mutex.lock()
		var out := finished
		mutex.unlock()
		return out

	func finish(value: Dictionary, elapsed_ms: int) -> void:
		mutex.lock()
		result = value
		generate_ms = elapsed_ms
		finished = true
		mutex.unlock()


func _check(label: String, ok: bool, detail: String = "") -> void:
	var line := "%s  %s" % ["PASS" if ok else "FAIL", label]
	if detail != "":
		line += "  [" + detail + "]"
	print(line)
	if not ok:
		_failures += 1


func _classify_messages() -> String:
	return JSON.stringify([
		{"role": "system", "content": SYSTEM_MSG},
		{"role": "user", "content": QUESTION},
	], "", false)


func _long_messages() -> String:
	return JSON.stringify([
		{"role": "system", "content": LONG_SYSTEM_MSG},
		{"role": "user", "content": LONG_QUESTION},
	], "", false)


func _barista_messages() -> String:
	return JSON.stringify([
		{"role": "system", "content": "You are a friendly barista. Reply as JSON."},
		{"role": "user", "content": "How was your morning?"},
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


func _gen(llm, max_tokens: int) -> Dictionary:
	return llm.generate(_barista_messages(), _schema(), _sampling(), max_tokens, Callable(), Callable())


## Runs on the worker thread. Times the turn and hands the result to the gate.
func _generate_in_thread(llm, gate: Gate) -> void:
	var started := Time.get_ticks_msec()
	var result: Dictionary = llm.generate(
		_barista_messages(), _schema(), _sampling(), LONG_GENERATE_MAX_TOKENS,
		Callable(gate, "on_token"), Callable()
	)
	gate.finish(result, Time.get_ticks_msec() - started)


## Runs on the worker thread for check 3b. No token callback is bound, so nothing stalls.
## The Gate is used only as the result holder here.
func _free_in_thread(llm, gate: Gate) -> void:
	var started := Time.get_ticks_msec()
	var result: Dictionary = llm.generate(
		_barista_messages(), _schema(), _sampling(), LONG_GENERATE_MAX_TOKENS,
		Callable(), Callable()
	)
	gate.finish(result, Time.get_ticks_msec() - started)


## Runs the free generate on a worker thread and waits for it. Returns the generate result.
func _run_free(llm) -> Dictionary:
	var gate := Gate.new()
	var thread := Thread.new()
	thread.start(_free_in_thread.bind(llm, gate))
	thread.wait_to_finish()
	return gate.result


func _err_code(r: Dictionary) -> String:
	if r.get("ok", false):
		return ""
	return str(r.get("error", {}).get("code", ""))


func _short(s: String) -> String:
	return s.substr(0, 60)


## Classifier text, or "ERR:<code>" so a failed call never equals a real answer.
func _ctext(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "ERR:" + _err_code(r)
	return str(r.get("text", ""))


## Generated text, or "ERR:<code>" so a failed generate never equals a real text.
func _gen_text(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "ERR:" + _err_code(r)
	return str(r.get("text", ""))


func _total_ms(r: Dictionary) -> float:
	return float(r.get("metrics", {}).get("total_ms", -1.0))


## Number of whitespace-separated words.
func _word_count(s: String) -> int:
	var rx := RegEx.new()
	rx.compile("\\S+")
	return rx.search_all(s).size()


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


func _init() -> void:
	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path == "":
		model_path = DEFAULT_MODEL
	var ngl_env := OS.get_environment("LEILA_NGL")
	var ngl := int(ngl_env) if ngl_env != "" else 99
	var backend_dir := ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")
	print("classify_check: model=" + model_path)
	print("classify_check: n_gpu_layers=%d" % ngl)

	var llm = ClassDB.instantiate("LeilaLLM")
	if llm == null:
		_check("LeilaLLM GDExtension is registered", false)
		quit(1)
		return
	var malice := _vec("malice")

	# 0. Before load, classify reports not_loaded.
	var r0: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
	_check("0 classify before load -> not_loaded", _err_code(r0) == "not_loaded", _err_code(r0))

	var vram_before := _vram_query()
	print("vram before load: %d MiB" % _mib(vram_before))

	# load_model creates the classifier context itself. classifier_n_ubatch is passed explicitly (64, the default).
	var info: Dictionary = llm.load_model({
		"model_path": model_path,
		"backend_dir": backend_dir,
		"n_gpu_layers": ngl,
		"classifier_n_ubatch": 64,
	})
	if not info.get("ok", false) or not llm.is_loaded():
		_check("load_model ok", false, JSON.stringify(info, "", false))
		quit(1)
		return
	_check("load_model ok", true)
	var vram_loaded := _vram_query()
	print("vram after load: %d MiB" % _mib(vram_loaded))

	# 1. Baseline: the first classify gives text A. The classifier context already exists (load_model made it),
	# so the VRAM reading after it must equal the one after load (check 6). A repeat must give A again.
	var r1: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
	var a := _ctext(r1)
	var vram_classified := _vram_query()
	print("vram after first classify: %d MiB" % _mib(vram_classified))
	_check("1 baseline classify gives text A",
			bool(r1.get("ok", false)) and not a.is_empty() and not a.begins_with("ERR:"),
			"A=%s total_ms=%.1f" % [_short(a), _total_ms(r1)])
	var a_repeat := _ctext(llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS))
	_check("1b repeat classify gives A again", a_repeat == a, _short(a_repeat))

	# 2c. Long dose-0 proof. Checks 1 to 4 compare 8-token yes/no answers, which could match by
	# chance. Here the answer is 40 tokens of free text. Vectors are cleared first, so L0 and G0
	# are taken with no vector bound. Malice x12 is then applied for L1 and G1, and cleared again.
	# Check 2 below starts from no vector, so this block leaves none bound.
	llm.set_control_vectors([])
	var long_msgs := _long_messages()
	var r2c0: Dictionary = llm.classify(long_msgs, LONG_CLASSIFY_MAX_TOKENS)
	var l0 := _ctext(r2c0)
	var g2c0 := _gen_text(llm.generate(long_msgs, "", _sampling(), LONG_CLASSIFY_MAX_TOKENS, Callable(), Callable()))
	llm.set_control_vectors([{"path": malice, "scale": MALICE_SCALE}])
	var r2c1: Dictionary = llm.classify(long_msgs, LONG_CLASSIFY_MAX_TOKENS)
	var l1 := _ctext(r2c1)
	var g2c1 := _gen_text(llm.generate(long_msgs, "", _sampling(), LONG_CLASSIFY_MAX_TOKENS, Callable(), Callable()))
	llm.set_control_vectors([])
	var words := _word_count(l0)
	print("2c L0 (classify, no vector): " + JSON.stringify(l0, "", false))
	print("2c G0 (generate, no vector): " + JSON.stringify(g2c0, "", false))
	print("2c G1 (generate, malice x12): " + JSON.stringify(g2c1, "", false))
	_check("2c long dose-0 proof: L0 == L1 under malice x12, L0 >= %d words, generate changes" % LONG_MIN_WORDS,
			bool(r2c0.get("ok", false)) and bool(r2c1.get("ok", false))
			and not l0.begins_with("ERR:") and l0 == l1 and words >= LONG_MIN_WORDS
			and not g2c0.begins_with("ERR:") and not g2c1.begins_with("ERR:") and g2c0 != g2c1,
			"words=%d L0==L1=%s G0!=G1=%s" % [words, str(l0 == l1), str(g2c0 != g2c1)])

	# 2. Dose-0 proof. Control first: malice x12 on the main context must change its
	# generate text, or the proof below would pass for free. Then classify must still give A.
	var g0 := _gen_text(_gen(llm, GENERATE_MAX_TOKENS))
	var rv: Dictionary = llm.set_control_vectors([{"path": malice, "scale": MALICE_SCALE}])
	var g1 := _gen_text(_gen(llm, GENERATE_MAX_TOKENS))
	_check("2b control: malice x12 applied and changes the main-context generate",
			bool(rv.get("ok", false)) and bool(rv.get("applied", false))
			and not g1.begins_with("ERR:") and g1 != g0,
			"g0=%s g1=%s" % [_short(g0), _short(g1)])
	var r2: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
	_check("2 dose-0 proof: classify under malice x12 == A",
			bool(r2.get("ok", false)) and _ctext(r2) == a, _short(_ctext(r2)))

	# 3. Concurrency: a generate holds the turn lock mid-turn while classify runs on this
	# thread. Both must succeed, and classify must still give A.
	var gate := Gate.new()
	var thread := Thread.new()
	thread.start(_generate_in_thread.bind(llm, gate))
	var waited := 0
	while not gate.has_streamed() and waited < WAIT_STREAM_MS:
		OS.delay_msec(5)
		waited += 5
	var streamed := gate.has_streamed()
	var t0 := Time.get_ticks_usec()
	var r3: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
	var classify_wall_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var overlapped := not gate.is_finished()
	gate.release()
	thread.wait_to_finish()
	var gen3: Dictionary = gate.result
	_check("3 classify during a generate: both ok, classify == A, generate still running",
			streamed and overlapped and bool(r3.get("ok", false)) and _ctext(r3) == a
			and bool(gen3.get("ok", false)),
			"classify wall=%.1fms engine=%.1fms; generate wall=%dms" % [
				classify_wall_ms, _total_ms(r3), gate.generate_ms])

	# 4. Five sequential classifies, still under malice x12: all ok, all A.
	var max_ms := 0.0
	var seq_ok := true
	for _call in range(SEQUENTIAL_CALLS):
		var r4: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
		seq_ok = seq_ok and bool(r4.get("ok", false)) and _ctext(r4) == a
		max_ms = maxf(max_ms, _total_ms(r4))
	_check("4 five sequential classify calls all == A", seq_ok, "max total_ms=%.1f" % max_ms)

	# 3b. Free-running concurrency. Nothing stalls the generate: its token callback is not bound,
	# so the two contexts decode at the same time. Malice x12 is still bound, so the main context
	# is steered. G is the same generate run alone first. The second run is on a thread while this
	# thread calls classify in a loop until that generate finishes.
	var free_alone := _run_free(llm)
	var g_text := _gen_text(free_alone)
	var free_gate := Gate.new()
	var free_thread := Thread.new()
	free_thread.start(_free_in_thread.bind(llm, free_gate))
	var overlap_calls := 0
	var overlap_max_ms := 0.0
	var overlap_texts_ok := true
	var loop_started := Time.get_ticks_msec()
	while not free_gate.is_finished() and Time.get_ticks_msec() - loop_started < WAIT_STREAM_MS:
		var rb: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
		overlap_texts_ok = overlap_texts_ok and bool(rb.get("ok", false)) and _ctext(rb) == a
		if not free_gate.is_finished():
			overlap_calls += 1
			overlap_max_ms = maxf(overlap_max_ms, _total_ms(rb))
	free_thread.wait_to_finish()
	var free_again: Dictionary = free_gate.result
	var g_again := _gen_text(free_again)
	print("3b overlap: %d classify calls returned while generate was still running; max classify total_ms %.1f" % [
		overlap_calls, overlap_max_ms])
	_check("3b free-running concurrency: generate == G, every classify == A, >= %d classify calls during generate" % OVERLAP_MIN_CALLS,
			bool(free_alone.get("ok", false)) and not g_text.is_empty() and not g_text.begins_with("ERR:")
			and bool(free_again.get("ok", false)) and g_again == g_text
			and overlap_texts_ok and overlap_calls >= OVERLAP_MIN_CALLS,
			"G=%s overlap_calls=%d max_classify_total_ms=%.1f generate_ms=%d" % [
				_short(g_text), overlap_calls, overlap_max_ms, free_gate.generate_ms])

	# 7. Input limits: a prompt over 1000 tokens and max_tokens 0 are refused before any decode.
	# Runs before the unload, because a classify on an unloaded engine returns not_loaded first.
	var long_question := "word ".repeat(1500)
	var long_messages := JSON.stringify([
		{"role": "system", "content": SYSTEM_MSG},
		{"role": "user", "content": long_question},
	], "", false)
	var r7a: Dictionary = llm.classify(long_messages, CLASSIFY_MAX_TOKENS)
	var r7b: Dictionary = llm.classify(_classify_messages(), 0)
	_check("7 prompt over 1000 tokens -> prompt_too_long; max_tokens 0 -> invalid_request",
			_err_code(r7a) == "prompt_too_long" and _err_code(r7b) == "invalid_request",
			"%s %s" % [_err_code(r7a), _err_code(r7b)])

	# 5. Unload while nothing runs, then classify returns not_loaded.
	llm.set_control_vectors([])
	llm.unload()
	var r5: Dictionary = llm.classify(_classify_messages(), CLASSIFY_MAX_TOKENS)
	var vram_unloaded := _vram_query()
	print("vram after unload: %d MiB" % _mib(vram_unloaded))
	_check("5 unload then classify -> not_loaded",
			_err_code(r5) == "not_loaded" and not llm.is_loaded(), _err_code(r5))

	# 6. load_model made the classifier context (P4.06a): classifier_ready is true, and the first classify
	# may add at most 32 MiB over the VRAM reading after load. A first-use driver allocation of about 12 MiB
	# is expected, so an exact match is not required. The load cost and the first-classify delta are reported.
	var load_cost := _mib(vram_loaded) - _mib(vram_before)
	var first_delta := _mib(vram_classified) - _mib(vram_loaded)
	_check("6 classifier context made at load: classifier_ready, first classify adds at most 32 MiB VRAM",
			bool(info.get("classifier_ready", false)) and _mib(vram_before) >= 0 and _mib(vram_loaded) >= 0
			and _mib(vram_classified) >= 0 and first_delta <= 32,
			"classifier_ready=%s before=%d load=%d first_classify=%d first_delta=%d load_cost=%d MiB" % [
				str(info.get("classifier_ready", "")), _mib(vram_before), _mib(vram_loaded),
				_mib(vram_classified), first_delta, load_cost])

	print("classify_check: %s" % ("ALL PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
