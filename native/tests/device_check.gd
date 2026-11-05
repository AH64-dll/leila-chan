extends SceneTree

# device_check: engine device selection, list_devices and the cancellable load (P4.06a).
# Run from the repo root:
#   ./tools/godot.sh --headless --path game --script "$PWD/native/tests/device_check.gd"
# Env: LEILA_MODEL (model path, default below). Exit code 0 only when every check passes.
#
# 1 list_devices is non-empty (all devices printed); 2 device "auto" picks the RTX 4050 as gpu, by its
# CUDA name when list_devices has a CUDA gpu (CUDA is preferred over Vulkan for the same card), and
# generates 30 tokens; 3 device "cpu" loads with gpu_layers 0 and generates 30 tokens; 4 an unknown
# name is invalid_request; 5 a missing file is model_missing, then a good file loads; 6 cancel_load()
# on a loading thread, once load_progress passes 0.05, stops the load with code cancelled, and a
# normal load works afterwards.

const DEFAULT_MODEL := "/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf"
const GENERATE_TOKENS := 30
const GPU_NAME_HINT := "4050"
const CANCEL_AT_PROGRESS := 0.05
const WAIT_PROGRESS_MS := 120000
const MAX_CANCEL_MS := 10000
const PROMPT := "Describe a quiet harbour town at dawn in several sentences."

var _failures := 0
var _model_path := ""
var _backend_dir := ""


## Holds a load result between the worker thread and the test thread, with the time it finished.
class Holder:
	extends RefCounted
	var mutex := Mutex.new()
	var result: Dictionary = {}
	var finished := false
	var finished_usec := 0

	func finish(value: Dictionary) -> void:
		mutex.lock()
		result = value
		finished_usec = Time.get_ticks_usec()
		finished = true
		mutex.unlock()

	func is_finished() -> bool:
		mutex.lock()
		var out := finished
		mutex.unlock()
		return out


func _check(label: String, ok: bool, detail: String = "") -> void:
	var line := "%s  %s" % ["PASS" if ok else "FAIL", label]
	if detail != "":
		line += "  [" + detail + "]"
	print(line)
	if not ok:
		_failures += 1


func _err_code(r: Dictionary) -> String:
	if r.get("ok", false):
		return ""
	return str(r.get("error", {}).get("code", ""))


func _messages() -> String:
	return JSON.stringify([{"role": "user", "content": PROMPT}], "", false)


func _sampling() -> Dictionary:
	return {"temperature": 0.0, "seed": 42}


## Load config for this run: the model and backend paths plus the keys given in extra.
func _cfg(extra: Dictionary) -> Dictionary:
	var cfg := {"model_path": _model_path, "backend_dir": _backend_dir}
	cfg.merge(extra)
	return cfg


func _desc_of(devs: Array, name: String) -> String:
	for d in devs:
		if str(d.get("name", "")) == name:
			return str(d.get("description", ""))
	return ""


## True when list_devices has a CUDA device of type gpu. The same card is also listed under Vulkan.
func _has_cuda_gpu(devs: Array) -> bool:
	for d in devs:
		if str(d.get("name", "")).begins_with("CUDA") and str(d.get("type", "")) == "gpu":
			return true
	return false


func _print_load(label: String, info: Dictionary) -> void:
	print("%s load: device=%s type=%s vram_total_mb=%d vram_free_mb=%d gpu_layers=%d gpu_offload=%s classifier_ready=%s load_ms=%d" % [
		label, str(info.get("device", "")), str(info.get("device_type", "")),
		int(info.get("vram_total_mb", -1)), int(info.get("vram_free_mb", -1)),
		int(info.get("gpu_layers", -1)), str(info.get("gpu_offload", "")),
		str(info.get("classifier_ready", "")), int(info.get("load_ms", -1))])


## A 30-token generate with no schema. True when it returns ok, 30 completion tokens and a tok/s reading.
func _generate_30(llm, label: String) -> bool:
	var r: Dictionary = llm.generate(_messages(), "", _sampling(), GENERATE_TOKENS, Callable(), Callable())
	var m: Dictionary = r.get("metrics", {})
	var n := int(m.get("completion_tokens", -1))
	var tps := float(m.get("tok_per_s", 0.0))
	print("%s generate: ok=%s completion_tokens=%d stop=%s tok/s=%.2f ttft_ms=%d" % [
		label, str(r.get("ok", false)), n, str(m.get("stop_reason", "")), tps, int(m.get("ttft_ms", -1))])
	return bool(r.get("ok", false)) and n == GENERATE_TOKENS and tps > 0.0


func _check_auto(devs: Array) -> void:
	var llm = ClassDB.instantiate("LeilaLLM")
	var info: Dictionary = llm.load_model(_cfg({"device": "auto", "n_gpu_layers": 99}))
	if not info.get("ok", false):
		_check("2 device auto loads", false, JSON.stringify(info, "", false))
		return
	_print_load("auto", info)
	var dev := str(info.get("device", ""))
	var desc := _desc_of(devs, dev)
	var dtype := str(info.get("device_type", ""))
	# When a CUDA gpu is listed, auto must pick its CUDA name, not the Vulkan entry for the same card.
	var cuda_listed := _has_cuda_gpu(devs)
	var cuda_ok := not cuda_listed or dev.begins_with("CUDA")
	_check("2 device auto picks the RTX 4050 as gpu, CUDA name when one is listed",
			dtype == "gpu" and desc.contains(GPU_NAME_HINT) and cuda_ok,
			"device=%s type=%s desc=%s cuda_listed=%s" % [dev, dtype, desc, str(cuda_listed)])
	_check("2b auto offloads (gpu_layers 99) and reports device memory",
			int(info.get("gpu_layers", -1)) == 99 and bool(info.get("gpu_offload", false))
			and int(info.get("vram_total_mb", 0)) > 0,
			"gpu_layers=%d vram_total_mb=%d" % [int(info.get("gpu_layers", -1)), int(info.get("vram_total_mb", 0))])
	_check("2c auto 30-token generate with a tok/s reading", _generate_30(llm, "auto"))
	llm.unload()


func _check_cpu() -> void:
	var llm = ClassDB.instantiate("LeilaLLM")
	# n_gpu_layers 99 is passed on purpose: device "cpu" must force it to 0.
	var info: Dictionary = llm.load_model(_cfg({"device": "cpu", "n_gpu_layers": 99}))
	if not info.get("ok", false):
		_check("3 device cpu loads", false, JSON.stringify(info, "", false))
		return
	_print_load("cpu", info)
	_check("3 device cpu: gpu_layers 0, device cpu, no offload",
			str(info.get("device", "")) == "cpu" and str(info.get("device_type", "")) == "cpu"
			and int(info.get("gpu_layers", -1)) == 0 and not bool(info.get("gpu_offload", true)),
			"device=%s type=%s gpu_layers=%d gpu_offload=%s" % [
				str(info.get("device", "")), str(info.get("device_type", "")),
				int(info.get("gpu_layers", -1)), str(info.get("gpu_offload", ""))])
	_check("3b cpu 30-token generate", _generate_30(llm, "cpu"))
	llm.unload()


func _check_unknown() -> void:
	var llm = ClassDB.instantiate("LeilaLLM")
	var info: Dictionary = llm.load_model(_cfg({"device": "NoSuchDevice0"}))
	_check("4 unknown device name -> invalid_request, nothing loaded",
			_err_code(info) == "invalid_request" and not llm.is_loaded(),
			"code=%s message=%s" % [_err_code(info), str(info.get("error", {}).get("message", ""))])
	llm.unload()


func _check_missing_then_good() -> void:
	var llm = ClassDB.instantiate("LeilaLLM")
	var missing: Dictionary = llm.load_model({
		"model_path": "/nonexistent/leila_device_check_missing.gguf",
		"backend_dir": _backend_dir,
		"device": "auto",
	})
	_check("5a missing model file -> model_missing", _err_code(missing) == "model_missing" and not llm.is_loaded(),
			_err_code(missing))
	var good: Dictionary = llm.load_model(_cfg({"device": "auto"}))
	_check("5b then a good file loads", bool(good.get("ok", false)) and llm.is_loaded(), _err_code(good))
	llm.unload()


## Runs on the worker thread: the load that cancel_load() is aimed at.
func _load_in_thread(llm, cfg: Dictionary, holder: Holder) -> void:
	holder.finish(llm.load_model(cfg))


func _check_cancel() -> void:
	var llm = ClassDB.instantiate("LeilaLLM")
	var cfg := _cfg({"device": "auto", "n_gpu_layers": 99})
	var holder := Holder.new()
	var thread := Thread.new()
	thread.start(_load_in_thread.bind(llm, cfg, holder))
	var waited := 0
	while llm.load_progress() < CANCEL_AT_PROGRESS and not holder.is_finished() and waited < WAIT_PROGRESS_MS:
		OS.delay_msec(1)
		waited += 1
	var progress_at_cancel: float = llm.load_progress()
	var t_cancel := Time.get_ticks_usec()
	llm.cancel_load()
	var call_us := Time.get_ticks_usec() - t_cancel
	thread.wait_to_finish()
	var r: Dictionary = holder.result
	var return_ms := (holder.finished_usec - t_cancel) / 1000.0
	print("cancel: progress at cancel=%.3f, cancel_load() call took %d us, load returned %.1f ms after the cancel, code=%s" % [
		progress_at_cancel, call_us, return_ms, _err_code(r)])
	_check("6a cancel stops the load with code cancelled, promptly",
			_err_code(r) == "cancelled" and not llm.is_loaded() and return_ms < MAX_CANCEL_MS,
			"code=%s return_ms=%.1f" % [_err_code(r), return_ms])

	var again: Dictionary = llm.load_model(cfg)
	_check("6b a normal load works after the cancel", bool(again.get("ok", false)) and llm.is_loaded(),
			_err_code(again))
	llm.unload()


func _init() -> void:
	_model_path = OS.get_environment("LEILA_MODEL")
	if _model_path == "":
		_model_path = DEFAULT_MODEL
	_backend_dir = ProjectSettings.globalize_path("res://addons/leila_llm/bin/linux")
	print("device_check: model=" + _model_path)

	var probe = ClassDB.instantiate("LeilaLLM")
	if probe == null:
		_check("LeilaLLM GDExtension is registered", false)
		quit(1)
		return

	# 1. The devices the backend dir registers, all of them.
	var devs: Array = probe.list_devices(_backend_dir)
	print("device list (%d):" % devs.size())
	for d in devs:
		print("  %s | %s | type=%s | total_mb=%d | free_mb=%d" % [
			str(d.get("name", "")), str(d.get("description", "")), str(d.get("type", "")),
			int(d.get("total_mb", -1)), int(d.get("free_mb", -1))])
	_check("1 list_devices is non-empty", devs.size() > 0, "count=%d" % devs.size())

	_check_auto(devs)
	_check_cpu()
	_check_unknown()
	_check_missing_then_good()
	_check_cancel()

	print("device_check: %s" % ("ALL PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)
