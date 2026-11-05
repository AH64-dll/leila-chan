extends SceneTree

# cache_scene: prompt-prefix cache measurement on the game's real prompts (P4.05b).
# One process per configuration, run sequentially. Args after `--`:
#   --out=PATH  --ubatch=N  --cache=0|1  --dose=N  [--dose-from=N]  --temp=0|game
# Dose: turns 1-4 use --dose-from when given, turns 5-8 use --dose; 0 means {}.
# The messages are identical in every configuration: history replies are fixed lines.
# Run from the repo root:
#   LEILA_MODEL=/abs/Qwen3.5-4B-Q4_K_M.gguf ./tools/godot.sh --headless --path game \
#     --script "/abs/native/tests/cache_scene.gd" -- --out=/abs/x.jsonl --ubatch=512 --cache=1 --dose=0 --temp=0
# Exit 0 only when all 8 turns returned text.
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
## place the base builds the load config. The base _load_engine() chain (GPU, fallback
## layers, CPU) and generate() are inherited unchanged.
class CacheBackend extends NativeBackend:
	var ubatch_value := 512
	var cache_value := 1

	func _attempt_load(base: Dictionary, device: String, layers: int) -> Dictionary:
		var load_config := base.duplicate()
		load_config["device"] = device
		load_config["n_gpu_layers"] = layers
		load_config["n_ubatch"] = ubatch_value
		load_config["prompt_cache"] = cache_value
		var result: Dictionary = _engine.load_model(load_config)
		if not bool(result.get("ok", false)):
			var code := String(_normalise_error(result.get("error", {}))["code"])
			print("[cache_scene] load failed on %s (%d layers): %s" % [device, layers, code])
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
	if out_path.is_empty() or (cache != 0 and cache != 1) or (temp != "0" and temp != "game"):
		printerr("cache_scene: need --out=PATH, --cache=0|1, --temp=0|game")
		quit(2)
		return
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("cache_scene: cannot open " + out_path)
		quit(2)
		return

	var backend := CacheBackend.new({}, null)
	backend.ubatch_value = ubatch
	backend.cache_value = cache
	print("cache_scene: ubatch=%d cache=%d dose=%s dose_from=%s temp=%s" % [
		ubatch, cache, str(dose), "-" if not has_dose_from else str(dose_from), temp])
	print("cache_scene: vram_before_load=" + _vram())
	var info: Dictionary = _on_thread(backend.ensure_loaded)
	print("cache_scene: load ok=%s n_ubatch=%s" % [str(info.get("ok", false)), str(info.get("n_ubatch", "?"))])
	print("cache_scene: vram_after_load=" + _vram())
	if not bool(info.get("ok", false)):
		printerr("cache_scene: load failed: " + JSON.stringify(info.get("error", {}), "", false))
		file.close()
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
			"events": events,
			"offered": offered,
			"history": history.duplicate(true),
			"player_message": line,
		}
		var built: Dictionary = prompt_builder.call("build", ctx)
		var request: Variant = turn_request.new()
		request.messages.assign(built.get("messages", []))
		request.schema = turn_schema.build_turn_schema(
			{"stage": STAGE, "property_order": property_order}, []
		)
		request.sampling = sampling.duplicate(true)
		request.dose = _dose_for(turn, dose, has_dose_from, dose_from)
		var res: Dictionary = _on_thread(backend.generate.bind(request, Callable(), null))

		var ok := bool(res.get("ok", false))
		var m: Dictionary = res.get("metrics", {})
		var row := {
			"cache": cache,
			"ubatch": ubatch,
			"dose": dose,
			"dose_from": dose_from if has_dose_from else null,
			"temp": temp,
			"turn": turn,
			"prompt_tokens": int(m.get("prompt_tokens", -1)),
			"cache_reused_tokens": int(m.get("cache_reused_tokens", -1)),
			"cache_save_ms": float(m.get("cache_save_ms", -1.0)),
			"cache_restore_ms": float(m.get("cache_restore_ms", -1.0)),
			"cache_state_bytes": int(m.get("cache_state_bytes", -1)),
			"prompt_ms": float(m.get("prompt_ms", -1.0)),
			"ttft_ms": float(m.get("ttft_ms", -1.0)),
			"first_say_ms": int(m.get("first_say_ms", -1)),
			"total_ms": float(m.get("total_ms", -1.0)),
			"tok_s": float(m.get("tok_per_s", -1.0)),
			"text": String(res.get("text", "")) if ok else "",
		}
		if not ok:
			row["error"] = res.get("error", {})
			all_ok = false
		file.store_line(JSON.stringify(row, "", false))
		file.flush()
		print("cache_scene: turn=%d ok=%s prompt_tokens=%d reused=%d prompt_ms=%.0f first_say_ms=%d" % [
			turn, str(ok), int(row["prompt_tokens"]), int(row["cache_reused_tokens"]),
			float(row["prompt_ms"]), int(row["first_say_ms"])])
		history.append({"role": "user", "text": line})
		history.append({"role": "assistant", "text": CANNED_REPLIES[turn - 1]})

	file.close()
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
