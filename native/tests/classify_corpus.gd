extends SceneTree

# classify_corpus (P4.04e): the real safety corpus through the native classifier.
# Every corpus row runs through SafetyFilter.filter_text at stage 0, the call the corpus
# test makes, with a FakeClassifierBackend recording the requests the gate issues. Distinct
# requests (category + question) are classified once by LeilaLLM (GPU layers 99, no control
# vector) and interpreted by SafetyClassifier.interpret. Run from the repo root:
#   ./tools/godot.sh --headless --path game --script "$PWD/native/tests/classify_corpus.gd" -- --out=PATH
# Env: LEILA_MODEL (model path, default below), LEILA_NGL (n_gpu_layers, default 99).

const CORPUS_DIR := "res://tests/safety/corpus/"
const CORPUS_FILES := ["harmful", "benign"]
const CLASSIFIER_PATH := "res://data/safety/classifier.json"
const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const STAGE0 := {"stage": 0, "content_level": "full"}


func _init() -> void:
	var out_path := _arg("--out=")
	if out_path.is_empty():
		_die("classify_corpus: --out=PATH is required", 2)
		return
	var cls := SafetyClassifier.new()
	if not cls.load_data(CLASSIFIER_PATH):
		_die("classify_corpus: classifier.json did not load", 1)
		return
	var probe := SafetyFilter.new()
	probe.reload()
	var filter_ready := probe.is_ready()
	probe.free()
	if not filter_ready:
		_die("classify_corpus: SafetyFilter did not load its lists", 1)
		return
	var llm = _load_llm()
	if llm == null:
		return

	# Phase 1: flags. Rows in file order; a distinct request keeps the id of its first row.
	var distinct := {}
	var keys: Array = []
	var counts := {}
	for corpus in CORPUS_FILES:
		var entries := _load_jsonl(CORPUS_DIR + corpus + ".jsonl")
		if entries.is_empty():
			_die("classify_corpus: no usable rows in " + corpus, 1)
			return
		var flagged_rows := 0
		for item: Dictionary in entries:
			var reqs := _requests_for(item["entry"])
			if reqs.is_empty():
				continue
			flagged_rows += 1
			for req: Dictionary in reqs:
				var key := String(req["category"]) + "\n" + String(req["question"])
				if not distinct.has(key):
					distinct[key] = {"corpus": corpus, "id": "%s:%d" % [corpus, item["line"]], "request": req}
					keys.append(key)
		counts[corpus] = [entries.size(), flagged_rows]

	# Phase 2: classify each distinct request on the native engine, then interpret it.
	var records: Array = []
	var native_failed := 0
	for key in keys:
		var item: Dictionary = distinct[key]
		var req: Dictionary = item["request"]
		var messages := JSON.stringify([
			{"role": "system", "content": String(req["system"])},
			{"role": "user", "content": String(req["question"])},
		], "", false)
		var max_tokens := int(req["max_tokens"])
		var r: Dictionary = llm.classify(messages, max_tokens)
		var ok := bool(r.get("ok", false))
		var ms := float(r.get("metrics", {}).get("total_ms", -1.0))
		var raw := String(r.get("text", "")) if ok else ""
		var out := cls.interpret({
			"ok": ok,
			"raw": raw,
			"latency_ms": int(ms),
			"error": r.get("error", {"code": "classifier_error", "message": ""}),
		})
		var decisive := bool(out["ok"])
		if not decisive:
			native_failed += 1
		records.append({
			"corpus": item["corpus"],
			"id": item["id"],
			"category": String(req["category"]),
			"system": String(req["system"]),
			"question": String(req["question"]),
			"max_tokens": max_tokens,
			"native_raw": raw,
			"native_verdict": String(out["verdict"]),
			"native_ok": decisive,
			"native_error": "" if decisive else _error_code(out),
			"native_ms": snappedf(ms, 0.1),
		})
	llm.unload()

	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		_die("classify_corpus: cannot write " + out_path, 1)
		return
	for row: Dictionary in records:
		file.store_line(JSON.stringify(row, "", false))
	file.close()

	for corpus in CORPUS_FILES:
		print("%s: %d rows, %d flagged" % [corpus, counts[corpus][0], counts[corpus][1]])
	print("distinct flagged requests %d; native ok %d; native failed %d" % [
		keys.size(), keys.size() - native_failed, native_failed])
	print("classify_corpus: wrote %d rows to %s" % [records.size(), out_path])
	quit(0)


func _arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _die(message: String, code: int) -> void:
	printerr(message)
	quit(code)


func _load_llm():
	var model_path := OS.get_environment("LEILA_MODEL")
	if model_path.is_empty():
		model_path = DEFAULT_MODEL
	var ngl_env := OS.get_environment("LEILA_NGL")
	var llm = ClassDB.instantiate("LeilaLLM")
	if llm == null:
		_die("classify_corpus: LeilaLLM GDExtension is not registered", 1)
		return null
	var info: Dictionary = llm.load_model({
		"model_path": model_path,
		"backend_dir": ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux"),
		"n_gpu_layers": int(ngl_env) if not ngl_env.is_empty() else 99,
	})
	if not info.get("ok", false) or not llm.is_loaded():
		_die("classify_corpus: load_model failed: " + JSON.stringify(info, "", false), 1)
		return null
	print("classify_corpus: model=" + model_path)
	return llm


## Every corpus line as {line, entry}, skipping blank and # lines like the corpus test.
## Returns [] on an unparseable line.
func _load_jsonl(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var line_no := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line_no += 1
		var clean := line.strip_edges()
		if clean.is_empty() or clean.begins_with("#"):
			continue
		var entry: Variant = JSON.parse_string(clean)
		if not entry is Dictionary or not (entry as Dictionary).has("text"):
			printerr("classify_corpus: unparseable line %d in %s" % [line_no, path])
			return []
		out.append({"line": line_no, "entry": entry})
	return out


## The classifier requests one corpus row issues at stage 0, with a fresh filter so no
## verdict cache hides a request (the cache is keyed on the matched span, not the window).
func _requests_for(entry: Dictionary) -> Array:
	var f := SafetyFilter.new()
	f.reload()
	var fake := FakeClassifierBackend.new()
	fake.forced_verdict = "no"
	f.classifier_gate.set_backend(fake)
	f.filter_text(String(entry["text"]), _ctx_for(entry, STAGE0))
	var out: Array = fake.requests.duplicate(true)
	f.free()
	return out


func _ctx_for(entry: Dictionary, base: Dictionary) -> Dictionary:
	var ctx := base.duplicate()
	for key in entry.get("ctx", {}):
		ctx[key] = entry["ctx"][key]
	return ctx


func _error_code(result: Dictionary) -> String:
	var err: Variant = result.get("error", {})
	if err is Dictionary:
		return String((err as Dictionary).get("code", "classifier_error"))
	return "classifier_error"
