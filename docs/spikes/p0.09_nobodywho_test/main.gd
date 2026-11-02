extends Node

# P0.09 spike: NobodyWho v13.0.0 vs our four requirements.
# Run: godot --headless --path . --quit-after 600
# Exercises: API surface (control vectors?), GPU/Vulkan load, JSON-schema grammar,
# token streaming with latency measurement, template_variables enable_thinking.

const MODEL := "D:/lila/models/Qwen3.5-4B-Q4_K_M.gguf"

const PERSONA := "You are Yui, the heroine of a dating sim: lavender hair in a braid, navy pinafore dress, violet eyes. " + \
	"The player is 'you' (pronouns they/them; never assume their gender). Speak in short natural lines."
const RULES := "Respond ONLY with JSON in this exact order:\n" + \
	"read: label what the player just did (one word from the list).\n" + \
	"inner: your private gut reaction, max 15 words. The player never sees it.\n" + \
	"music: change the background music, or 'keep' (keep is normal).\n" + \
	"fx: a screen effect, or 'none' (none is normal).\n" + \
	"beats: 1-3 beats. New beat only when your feeling changes. Each beat: feeling, intensity 1-3, " + \
	"cue (a short sound; most beats use 'none'), say (what you say aloud, max 2 sentences).\n" + \
	"mood: how this moment changes you, each -3..3: affection, trust, stress.\n" + \
	"memory: a NEW fact you learned about the player worth remembering, or ''.\n" + \
	"action: a rare special event, almost always 'none'."

const INTENTS := ["greeting", "flirt", "compliment", "gift", "question", "small_talk", "tease", "insult",
	"apology", "leaving", "jealousy_bait", "meta", "boundary", "cold", "affection", "scared", "other"]
const FEELINGS := ["joy", "warmth", "playful", "proud", "shy", "love", "curious", "confused", "surprised",
	"nervous", "sad", "crying", "angry", "cold", "suspicious", "disgusted", "bored", "tired", "afraid",
	"pleading", "empty", "manic"]
const CUES := ["none", "giggle", "gasp", "sigh", "heartbeat", "hum", "sniffle"]
const MUSIC := ["keep", "romantic", "playful", "calm", "melancholy"]
const FX := ["none", "blush_glow", "hearts", "shake_small", "zoom_face"]
const ACTIONS := ["none", "end_date"]


func turn_schema() -> Dictionary:
	var rng := {"type": "integer", "minimum": -3, "maximum": 3}
	return {"type": "object", "properties": {
		"read": {"type": "string", "enum": INTENTS},
		"inner": {"type": "string", "maxLength": 90},
		"music": {"type": "string", "enum": MUSIC},
		"fx": {"type": "string", "enum": FX},
		"beats": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "object", "properties": {
			"feeling": {"type": "string", "enum": FEELINGS},
			"intensity": {"type": "integer", "minimum": 1, "maximum": 3},
			"cue": {"type": "string", "enum": CUES},
			"say": {"type": "string", "maxLength": 200}}, "required": ["feeling", "intensity", "cue", "say"],
			"additionalProperties": false}},
		"mood": {"type": "object", "properties": {"affection": rng, "trust": rng, "stress": rng},
			"required": ["affection", "trust", "stress"]},
		"memory": {"type": "string", "maxLength": 80},
		"action": {"type": "string", "enum": ACTIONS}},
		"required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"],
		"additionalProperties": false}


func scan_api() -> void:
	print("=== API surface: methods matching vector/cvec/adapter/dose/lora/steer ===")
	var pat := ["vector", "cvec", "adapter", "dose", "lora", "steer", "control"]
	var hits := 0
	for cls in ["NobodyWhoChat", "NobodyWhoModel", "NobodyWhoTokenStream", "NobodyWho",
			"NobodyWhoSamplerBuilder", "NobodyWhoSamplerConfig", "NobodyWhoSamplerPresets"]:
		if not ClassDB.class_exists(cls):
			print("  CLASS MISSING: ", cls)
			continue
		var names := []
		for m in ClassDB.class_get_method_list(cls, true):
			names.append(String(m["name"]))
		var matched := names.filter(func(n): return pat.any(func(p): return n.to_lower().contains(p)))
		print("  %s: %d methods; vector-ish: %s" % [cls, names.size(), matched])
		hits += matched.size()
	print("=== vector-ish method hits total: %d ===" % hits)


func _ready() -> void:
	print("=== P0.09 NobodyWho spike test ===")
	print("godot ", Engine.get_version_info().get("string"))
	scan_api()
	NobodyWho.set_log_level("INFO")

	var sampler: NobodyWhoSamplerConfig = NobodyWhoSamplerBuilder.new() \
		.json_schema(turn_schema()) \
		.penalties(64, 1.1, 0.0, 0.0) \
		.temperature(0.8) \
		.dist()

	var t0 := Time.get_ticks_msec()
	var chat = await NobodyWhoChat.create(MODEL, {
		"n_ctx": 8192,
		"use_gpu": true,
		"system_prompt": PERSONA + "\n" + RULES + "\nread labels: " + ", ".join(INTENTS),
		"template_variables": {"enable_thinking": false},
		"sampler": sampler,
	})
	if chat == null:
		push_error("chat create returned null")
		get_tree().quit(1)
		return
	print("=== model+chat ready in %.2f s ===" % ((Time.get_ticks_msec() - t0) / 1000.0))

	var stream = chat.complete([{"role": "user", "content": "Hi! I'm new here, can I sit next to you?"}], {})
	var first_token_ms := -1
	var t_start := Time.get_ticks_msec()
	var resp := ""
	var ntok := 0
	var last_tok_t := t_start
	var max_gap := 0
	var deadline := t_start + 120000
	while Time.get_ticks_msec() < deadline:
		var tok = await stream.next_token()
		if tok == null:
			break
		var now := Time.get_ticks_msec()
		if first_token_ms < 0:
			first_token_ms = now - t_start
		max_gap = maxi(max_gap, now - last_tok_t)
		last_tok_t = now
		resp += tok
		ntok += 1
	var total_ms := Time.get_ticks_msec() - t_start
	print("=== STREAM: %d tokens, ttft=%d ms, total=%d ms (%.1f tok/s), max_gap=%d ms ===" % [
		ntok, first_token_ms, total_ms, ntok * 1000.0 / max(1, total_ms), max_gap])

	print("=== RAW RESPONSE ===")
	print(resp)
	var parsed = JSON.parse_string(resp)
	if parsed == null:
		print("=== JSON: INVALID ===")
	else:
		var order := ""
		for k in parsed.keys():
			order += k + " "
		print("=== JSON: VALID; key order: %s ===" % order)
		if parsed.has("beats") and parsed["beats"].size() > 0:
			var b = parsed["beats"][0]
			var border := ""
			for k in b.keys():
				border += k + " "
			print("=== beat[0] key order: %s ===" % border)

	var stats = await chat.get_stats()
	print("=== stats: %s ===" % str(stats))

	# Turn 2: same chat (tests KV/prefix reuse + warm shader timing)
	stream = chat.ask("You look really cute today.")
	t_start = Time.get_ticks_msec()
	first_token_ms = -1
	resp = ""
	ntok = 0
	last_tok_t = t_start
	max_gap = 0
	deadline = t_start + 120000
	while Time.get_ticks_msec() < deadline:
		var tok2 = await stream.next_token()
		if tok2 == null:
			break
		var now2 := Time.get_ticks_msec()
		if first_token_ms < 0:
			first_token_ms = now2 - t_start
		max_gap = maxi(max_gap, now2 - last_tok_t)
		last_tok_t = now2
		resp += tok2
		ntok += 1
	var total2 := Time.get_ticks_msec() - t_start
	print("=== STREAM2: %d tokens, ttft=%d ms, total=%d ms (%.1f tok/s), max_gap=%d ms ===" % [
		ntok, first_token_ms, total2, ntok * 1000.0 / max(1, total2), max_gap])
	print("=== RAW RESPONSE 2 ===")
	print(resp)
	print("=== JSON2 valid: %s ===" % (JSON.parse_string(resp) != null))
	stats = await chat.get_stats()
	print("=== stats2: %s ===" % str(stats))
	print("=== DONE ===")
	get_tree().quit(0)
