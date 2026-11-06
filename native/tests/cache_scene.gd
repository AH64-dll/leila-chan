extends SceneTree

# cache_scene: prompt-prefix cache measurement on the game's real prompts (P4.05b).
# One process per configuration, run sequentially. Args after `--`:
#   --out=PATH  --ubatch=N  --cache=0|1  --dose=N  [--dose-from=N]  --temp=0|game
#   [--device=NAME] [--threads=N] [--ngl=N]
#       not passed: device auto (the game's fallback chain), engine default threads and layers.
#       --device or --ngl pins the load, so a failure is reported and not retried on another device.
#   [--fast=0|1]          default 0. TurnContext.finalize_request(request, fast) after the schema is set.
#   [--late-events=0|1]   default 0. EXPERIMENT ONLY: events and offered are left empty in the
#                         prompt build and appended to the end of the system message.
#   [--inner-cap=N]       default 0 (off). EXPERIMENT ONLY: inner.maxLength = N in each turn's schema.
# Dose: turns 1-4 use --dose-from when given, turns 5-8 use --dose; 0 means {}.
# The messages are identical in every configuration: history replies are fixed lines.
# Run from the repo root:
#   LEILA_MODEL=/abs/Qwen3.5-4B-Q4_K_M.gguf ./tools/godot.sh --headless --path game \
#     --script "/abs/native/tests/cache_scene.gd" -- --out=/abs/x.jsonl --ubatch=512 --cache=1 --dose=0 --temp=0
# Exit 0 only when all 8 turns returned text. A load failure writes one row with turn 0 and the error.
# Every row carries device and n_threads from the load result. The last row carries vm_hwm_kb,
# the process peak RAM (VmHWM from /proc/self/status) at the end of the run.
#
# Why the work starts on the first frame, not in _initialize(): under --script the autoloads
# are attached only once the main loop runs, and TurnContext.gd names GameState at compile
# time, so TurnContext cannot be a static reference from this file. The game scripts are
# loaded with load() on the first frame, and PromptBuilder is fetched from /root.

const TURNS := 8
const STAGE := 3
const PATH := "yandere"
const PLAYER_NAME := "Ren"
const SCENE := "A harbour tavern at dusk. Rain on the window, one lamp lit over the bar, and a regular who has not spoken yet."
const MEMORIES := [
	"Ren ordered the same fish stew on every visit last winter.",
	"The barista once lent Ren an umbrella and never asked for it back.",
	"Ren has a sister who sails on the evening ferry.",
	"The tavern closes early on storm nights.",
]
const EVENTS := {
	3: "A glass breaks in the kitchen and someone laughs too loudly.",
	6: "The lamp over the bar flickers and goes out for a moment.",
}
const OFFERED_TURN := 5
const OFFERED := {"music": ["quiet_piano"], "fx": ["rain_loop"], "cue": [], "action": []}
const PLAYER_LINES := [
	"Hi again. It's pouring out there.",
	"Can I get something warm, please?",
	"What's the stew like tonight?",
	"Did you hear that crash from the kitchen?",
	"Is the piano still working? I could use some music.",
	"Honestly the lights just went out. Are you okay?",
	"Fine, fine. Keep the lamp lit for me, will you?",
	"Thanks. I'll stay until the rain stops.",
]
const CANNED_REPLIES := [
	"Welcome back, it certainly is. Sit by the fire.",
	"Coming right up. Something warm, just for you.",
	"Tonight it is thick and salty, the way you like it.",
	"Oh, that was the cook dropping a pot. Nobody is hurt.",
	"The piano is fine. Give me a moment to tune it.",
	"Just a flicker, the storm is fussy. I have a candle here.",
	"Consider it done. The lamp will stay on for you.",
	"Good. The rain will not last forever, I promise.",
]
const SAMPLING_SEED := 20261105


## The game's NativeBackend._attempt_load() passes no n_ubatch or prompt_cache, so the
## engine always runs its defaults (512, 1). This subclass adds those two keys in the one
## place the base builds the load config, and applies the optional --device, --ngl and
## --threads overrides there too. The base _load_engine() chain (GPU, fallback layers,
## CPU) and generate() are inherited unchanged.
class CacheBackend extends NativeBackend:
	var ubatch_value := 512
	var cache_value := 1
	var device_value := ""  # "" = not passed; the base passes its own device
	var ngl_value := -1  # -1 = not passed; the base passes its own layer count
	var threads_value := -1  # -1 = not passed; the engine uses its default

	func _attempt_load(base: Dictionary, device: String, layers: int) -> Dictionary:
		var load_config := base.duplicate()
		load_config["device"] = device_value if not device_value.is_empty() else device
		load_config["n_gpu_layers"] = ngl_value if ngl_value >= 0 else layers
		load_config["n_ubatch"] = ubatch_value
		load_config["prompt_cache"] = cache_value
		if threads_value >= 0:
			load_config["n_threads"] = threads_value
		var result: Dictionary = _engine.load_model(load_config)
		if not bool(result.get("ok", false)):
			var code := String(_normalise_error(result.get("error", {}))["code"])
			print("[cache_scene] load failed on %s (%d layers): %s" % [
				String(load_config["device"]), int(load_config["n_gpu_layers"]), code])
		return result


var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	var prompt_builder: Node = get_root().get_node_or_null("/root/PromptBuilder")
	if prompt_builder == null:
		printerr("cache_scene: PromptBuilder autoload is not registered")
		quit(2)
		return
	var turn_context: Variant = load("res://llm/TurnContext.gd")
	var turn_request: Variant = load("res://llm/TurnRequest.gd")
	var turn_schema: Variant = load("res://llm/TurnSchema.gd")
	if turn_context == null or turn_request == null or turn_schema == null:
		printerr("cache_scene: a game script failed to compile")
		quit(2)
		return
	var property_order: Array = turn_schema.get_script_constant_map()["DOCS_02_PROPERTY_ORDER"]

	var args := OS.get_cmdline_user_args()
	var out_path := _arg(args, "out")
	var ubatch := int(_arg(args, "ubatch", "512"))
	var cache := int(_arg(args, "cache", "1"))
	var dose := float(_arg(args, "dose", "0"))
	var dose_from_text := _arg(args, "dose-from")
	var has_dose_from := not dose_from_text.is_empty()
	var dose_from := float(dose_from_text) if has_dose_from else 0.0
	var temp := _arg(args, "temp", "0")
	var device_arg := _arg(args, "device")
	var threads_text := _arg(args, "threads")
	var ngl_text := _arg(args, "ngl")
	var fast_text := _arg(args, "fast", "0")
	var late_text := _arg(args, "late-events", "0")
	var inner_cap := int(_arg(args, "inner-cap", "0"))
	var threads := int(threads_text) if not threads_text.is_empty() else -1
	var ngl := int(ngl_text) if not ngl_text.is_empty() else -1
	var fast := fast_text == "1"
	var late_events := late_text == "1"
	if out_path.is_empty() or (cache != 0 and cache != 1) or (temp != "0" and temp != "game"):
		printerr("cache_scene: need --out=PATH, --cache=0|1, --temp=0|game")
		quit(2)
		return
	if (fast_text != "0" and fast_text != "1") or (late_text != "0" and late_text != "1") or inner_cap < 0:
		printerr("cache_scene: need --fast=0|1, --late-events=0|1, --inner-cap=N with N>=0")
		quit(2)
		return
	if (not threads_text.is_empty() and threads < 1) or (not ngl_text.is_empty() and ngl < 0):
		printerr("cache_scene: --threads needs N>=1 and --ngl needs N>=0")
		quit(2)
		return
	if not _write_all(out_path, []):
		printerr("cache_scene: cannot open " + out_path)
		quit(2)
		return

	var shown_device := device_arg if not device_arg.is_empty() else "auto"
	var shown_threads := threads_text if not threads_text.is_empty() else "default"
	var shown_ngl := ngl_text if not ngl_text.is_empty() else "default"
	var pin := {}
	if not device_arg.is_empty():
		pin["device"] = device_arg
	if ngl >= 0:
		pin["n_gpu_layers"] = ngl
	var backend := CacheBackend.new(pin, null)
	backend.ubatch_value = ubatch
	backend.cache_value = cache
	backend.device_value = device_arg
	backend.ngl_value = ngl
	backend.threads_value = threads
	print("cache_scene: ubatch=%d cache=%d dose=%s dose_from=%s temp=%s device=%s threads=%s ngl=%s fast=%d late_events=%d inner_cap=%d" % [
		ubatch, cache, str(dose), "-" if not has_dose_from else str(dose_from), temp,
		shown_device, shown_threads, shown_ngl, 1 if fast else 0, 1 if late_events else 0, inner_cap])
	print("cache_scene: vram_before_load=" + _vram())
	var info: Dictionary = _on_thread(backend.ensure_loaded)
	var row_device := String(info.get("device", ""))
	if row_device.is_empty():
		row_device = shown_device
	var row_threads := int(info.get("n_threads", -1))
	print("cache_scene: load ok=%s device=%s device_type=%s gpu_layers=%s n_threads=%s n_ubatch=%s" % [
		str(info.get("ok", false)), str(info.get("device", "-")), str(info.get("device_type", "-")),
		str(info.get("gpu_layers", "-")), str(info.get("n_threads", "-")), str(info.get("n_ubatch", "?"))])
	print("cache_scene: vram_after_load=" + _vram())
	var common := {
		"cache": cache,
		"ubatch": ubatch,
		"dose": dose,
		"dose_from": dose_from if has_dose_from else null,
		"temp": temp,
		"device": row_device,
		"n_threads": row_threads,
		"fast": 1 if fast else 0,
		"late_events": 1 if late_events else 0,
		"inner_cap": inner_cap,
	}
	var rows: Array = []
	if not bool(info.get("ok", false)):
		printerr("cache_scene: load failed: " + JSON.stringify(info.get("error", {}), "", false))
		var failed := common.duplicate()
		failed["turn"] = 0
		failed["error"] = info.get("error", {})
		rows.append(failed)
		_finish_rows(out_path, rows)
		quit(1)
		return

	var sampling := _sampling(temp, turn_context)
	var history: Array = []
	var all_ok := true
	for turn in range(1, TURNS + 1):
		var line: String = PLAYER_LINES[turn - 1]
		var events: Array = [EVENTS[turn]] if EVENTS.has(turn) else []
		var offered: Dictionary = OFFERED.duplicate(true) if turn == OFFERED_TURN else {}
		var ctx := {
			"stage": STAGE,
			"path": PATH,
			"player_name": PLAYER_NAME,
			"scene": SCENE,
			"memories": MEMORIES.duplicate(),
			"events": [] if late_events else events,
			"offered": {} if late_events else offered,
			"history": history.duplicate(true),
			"player_message": line,
		}
		var built: Dictionary = prompt_builder.call("build", ctx)
		var messages: Array = built.get("messages", [])
		if late_events:
			_append_late(messages, events, offered)
		var request: Variant = turn_request.new()
		request.messages.assign(messages)
		request.schema = turn_schema.build_turn_schema(
			{"stage": STAGE, "property_order": property_order}, []
		)
		turn_context.finalize_request(request, fast)
		if inner_cap > 0:
			var capped := _cap_inner(request.schema, inner_cap)
			if turn == 1:
				print("cache_scene: inner_cap=%d set on %d schema node(s)" % [inner_cap, capped])
		request.sampling = sampling.duplicate(true)
		request.dose = _dose_for(turn, dose, has_dose_from, dose_from)
		var res: Dictionary = _on_thread(backend.generate.bind(request, Callable(), null))

		var ok := bool(res.get("ok", false))
		var m: Dictionary = res.get("metrics", {})
		var row := common.duplicate()
		row["turn"] = turn
		row["max_tokens"] = int(request.max_tokens)
		row["prompt_tokens"] = int(m.get("prompt_tokens", -1))
		row["cache_reused_tokens"] = int(m.get("cache_reused_tokens", -1))
		row["cache_save_ms"] = float(m.get("cache_save_ms", -1.0))
		row["cache_restore_ms"] = float(m.get("cache_restore_ms", -1.0))
		row["cache_state_bytes"] = int(m.get("cache_state_bytes", -1))
		row["prompt_ms"] = float(m.get("prompt_ms", -1.0))
		row["ttft_ms"] = float(m.get("ttft_ms", -1.0))
		row["first_say_ms"] = int(m.get("first_say_ms", -1))
		row["total_ms"] = float(m.get("total_ms", -1.0))
		row["tok_s"] = float(m.get("tok_per_s", -1.0))
		row["completion_tokens"] = int(m.get("completion_tokens", -1))
		row["text"] = String(res.get("text", "")) if ok else ""
		if not ok:
			row["error"] = res.get("error", {})
			all_ok = false
		rows.append(row)
		_write_all(out_path, rows)
		print("cache_scene: turn=%d ok=%s prompt_tokens=%d reused=%d prompt_ms=%.0f first_say_ms=%d completion_tokens=%d tok_s=%.2f" % [
			turn, str(ok), int(row["prompt_tokens"]), int(row["cache_reused_tokens"]),
			float(row["prompt_ms"]), int(row["first_say_ms"]), int(row["completion_tokens"]),
			float(row["tok_s"])])
		history.append({"role": "user", "text": line})
		history.append({"role": "assistant", "text": CANNED_REPLIES[turn - 1]})

	_finish_rows(out_path, rows)
	print("cache_scene: vram_end=" + _vram())
	backend.shutdown()
	quit(0 if all_ok else 1)


func _arg(args: PackedStringArray, key: String, fallback: String = "") -> String:
	var prefix := "--%s=" % key
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


## temp=game: the game's request_sampling(stage) row plus a fixed seed. temp=0: greedy.
func _sampling(temp: String, turn_context: Variant) -> Dictionary:
	if temp == "game":
		var sampling: Dictionary = turn_context.request_sampling(STAGE)
		sampling["seed"] = SAMPLING_SEED
		return sampling
	return {"temperature": 0.0, "top_k": 1}


## Turns 1-4 take the --dose-from value when one is given; every other case takes --dose.
func _dose_for(turn: int, dose: float, has_dose_from: bool, dose_from: float) -> Dictionary:
	var value := dose_from if (has_dose_from and turn <= 4) else dose
	return {"malice": value} if value > 0.0 else {}


## EXPERIMENT (--late-events=1). The event lines and the offer go at the end of the system
## message, in plain text, instead of where PromptBuilder puts them.
func _append_late(messages: Array, events: Array, offered: Dictionary) -> void:
	var extra := ""
	for line: String in events:
		extra += "\n\nEvents: " + line
	var offers := PackedStringArray()
	for key: String in offered:
		var items := PackedStringArray()
		for item: String in offered[key]:
			items.append(item)
		if not items.is_empty():
			offers.append("%s %s" % [key, ", ".join(items)])
	if not offers.is_empty():
		extra += "\n\nOffered: " + "; ".join(offers)
	if extra.is_empty():
		return
	for message: Dictionary in messages:
		if String(message.get("role", "")) == "system":
			message["content"] = String(message.get("content", "")) + extra
			return
	printerr("cache_scene: no system message found; late events not added")


## EXPERIMENT (--inner-cap=N). Sets maxLength on every "inner" property in a schema copy.
## Returns how many nodes it set.
func _cap_inner(node: Variant, cap: int) -> int:
	var hits := 0
	if node is Dictionary:
		for key in node:
			var value: Variant = node[key]
			if key == "inner" and value is Dictionary and value.has("maxLength"):
				value["maxLength"] = cap
				hits += 1
			hits += _cap_inner(value, cap)
	elif node is Array:
		for item in node:
			hits += _cap_inner(item, cap)
	return hits


## Stamps the peak RAM onto the last row and rewrites the whole file.
func _finish_rows(out_path: String, rows: Array) -> void:
	var hwm := _vm_hwm_kb()
	if not rows.is_empty():
		rows[-1]["vm_hwm_kb"] = hwm
	_write_all(out_path, rows)
	print("cache_scene: vm_hwm_kb=%d" % hwm)


func _write_all(path: String, rows: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	for row in rows:
		file.store_line(JSON.stringify(row, "", false))
	file.close()
	return true


## VmHWM from /proc/self/status: the peak resident set of this process, in kB. -1 if unreadable.
func _vm_hwm_kb() -> int:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null:
		return -1
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("VmHWM:"):
			file.close()
			return int(line.substr(6).strip_edges().split(" ", false)[0])
	file.close()
	return -1


func _on_thread(work: Callable) -> Variant:
	var thread := Thread.new()
	thread.start(work)
	return thread.wait_to_finish()


func _vram() -> String:
	var out: Array = []
	var code := OS.execute("nvidia-smi", ["--query-gpu=memory.used", "--format=csv,noheader"], out)
	if code != 0 or out.is_empty():
		return "unavailable"
	return String(out[0]).strip_edges()
