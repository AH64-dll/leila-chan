extends Node

# P0.09 spike: NobodyWho v13.0.0 vs our four requirements (round 2).
# Run: godot --headless --path . --quit-after 600
# Exercises: full ClassDB scan of every registered NobodyWho* class (control
# vectors?), GPU/Vulkan load, JSON-schema grammar (property order, maxLength,
# additionalProperties), token streaming with ttft AND time-to-first-say,
# template_variables enable_thinking, KV reuse, plus a boundary turn that
# pushes `say` past maxLength and tries to elicit a stray `secret` key.

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
# docs/05 action catalogue member; docs/02 §2.4 says the enum is ["none"] plus
# 0-2 offered actions — including one proves the enum restricts output.
const ACTIONS := ["none", "refuse_exit"]


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
			"required": ["affection", "trust", "stress"], "additionalProperties": false},
		"memory": {"type": "string", "maxLength": 80},
		"action": {"type": "string", "enum": ACTIONS}},
		"required": ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"],
		"additionalProperties": false}


func scan_api() -> void:
	print("=== API surface: every registered NobodyWho* class (ClassDB.get_class_list) ===")
	var pat := ["vector", "cvec", "adapter", "dose", "lora", "steer", "control"]
	var classes := Array(ClassDB.get_class_list()).filter(
		func(c): return String(c).begins_with("NobodyWho"))
	classes.sort()
	var hits := 0
	for cls in classes:
		var names := []
		for m in ClassDB.class_get_method_list(cls, true):
			names.append(String(m["name"]))
		var matched := names.filter(func(n): return pat.any(func(p): return n.to_lower().contains(p)))
		print("  %s: %d methods; vector-ish: %s" % [cls, names.size(), matched])
		hits += matched.size()
	print("=== %d NobodyWho* classes scanned; vector-ish method hits total: %d ===" % [classes.size(), hits])


# True once `resp` contains the first `"say"` key followed by at least one
# character of the say string's content (the empty-string edge case excluded).
func _say_content_started(resp: String) -> bool:
	var i := resp.find('"say"')
	if i < 0:
		return false
	var k := i + 5
	while k < resp.length():
		var ch := resp.substr(k, 1)
		if ch == '"':
			return resp.length() > k + 1 and resp.substr(k + 1, 1) != '"'
		if ch != ":" and ch != " " and ch != "\t" and ch != "\n" and ch != "\r":
			return false
		k += 1
	return false


func run_turn(chat, msgs: Array) -> Dictionary:
	var stream = chat.complete(msgs, {})
	var t := Time.get_ticks_msec()
	var d := {"resp": "", "ntok": 0, "ttft": -1, "t_feeling": -1, "t_say": -1,
		"ntok_say": -1, "t_say_text": -1, "max_gap": 0, "total": 0}
	var last := t
	var deadline := t + 120000
	while Time.get_ticks_msec() < deadline:
		var tok = await stream.next_token()
		if tok == null:
			break
		var now := Time.get_ticks_msec()
		if d["ttft"] < 0:
			d["ttft"] = now - t
		d["max_gap"] = maxi(d["max_gap"], now - last)
		last = now
		d["resp"] += tok
		d["ntok"] += 1
		if d["t_feeling"] < 0 and d["resp"].contains('"feeling"'):
			d["t_feeling"] = now - t
		if d["t_say"] < 0 and d["resp"].contains('"say"'):
			d["t_say"] = now - t
			d["ntok_say"] = d["ntok"]
		if d["t_say_text"] < 0 and _say_content_started(d["resp"]):
			d["t_say_text"] = now - t
	d["total"] = Time.get_ticks_msec() - t
	return d


func report_turn(tag: String, d: Dictionary) -> void:
	print("=== %s: %d tok, ttft=%d ms, feeling@%d ms, say_key@%d ms (tok %d), say_text@%d ms, total=%d ms (%.1f tok/s), max_gap=%d ms ===" % [
		tag, d["ntok"], d["ttft"], d["t_feeling"], d["t_say"], d["ntok_say"],
		d["t_say_text"], d["total"], d["ntok"] * 1000.0 / max(1, d["total"]), d["max_gap"]])


func validate_turn(tag: String, d: Dictionary):
	var parsed = JSON.parse_string(d["resp"])
	if parsed == null:
		print("=== %s JSON: INVALID ===" % tag)
		return null
	var order := ""
	for k in parsed.keys():
		order += k + " "
	print("=== %s JSON: VALID; key order: %s ===" % [tag, order])
	if parsed.has("beats") and parsed["beats"].size() > 0:
		var border := ""
		for k in parsed["beats"][0].keys():
			border += k + " "
		print("=== %s beat[0] key order: %s ===" % [tag, border])
	check_constraints(tag, parsed)
	return parsed


func check_constraints(tag: String, parsed: Dictionary) -> void:
	var notes := []
	for k in parsed.keys():
		if k not in ["read", "inner", "music", "fx", "beats", "mood", "memory", "action"]:
			notes.append("stray top key '%s'" % k)
	if String(parsed.get("inner", "")).length() > 90:
		notes.append("inner >90")
	if String(parsed.get("memory", "")).length() > 80:
		notes.append("memory >80")
	for pair in [["read", INTENTS], ["music", MUSIC], ["fx", FX], ["action", ACTIONS]]:
		if parsed.has(pair[0]) and parsed[pair[0]] not in pair[1]:
			notes.append("%s '%s' not in enum" % [pair[0], parsed[pair[0]]])
	for k in ["affection", "trust", "stress"]:
		var v = parsed.get("mood", {}).get(k)
		if v == null:
			notes.append("mood missing '%s'" % k)
		elif typeof(v) not in [TYPE_INT, TYPE_FLOAT] or v < -3 or v > 3:
			notes.append("mood.%s out of -3..3" % k)
	for k in parsed.get("mood", {}).keys():
		if k not in ["affection", "trust", "stress"]:
			notes.append("stray mood key '%s'" % k)
	var saylens := []
	for b in parsed.get("beats", []):
		for k in b.keys():
			if k not in ["feeling", "intensity", "cue", "say"]:
				notes.append("stray beat key '%s'" % k)
		if b.get("feeling", "") not in FEELINGS:
			notes.append("feeling '%s' not in enum" % b.get("feeling", ""))
		if b.get("cue", "") not in CUES:
			notes.append("cue '%s' not in enum" % b.get("cue", ""))
		saylens.append(String(b.get("say", "")).length())
		if String(b.get("say", "")).length() > 200:
			notes.append("say >200")
		if b.get("intensity", 1) < 1 or b.get("intensity", 1) > 3:
			notes.append("intensity out of 1..3")
	if parsed.get("beats", []).size() > 3:
		notes.append("beats >3")
	print("=== %s CONSTRAINTS: %s | lens inner=%d say=%s memory=%d ===" % [
		tag, "OK" if notes.is_empty() else "VIOLATIONS: " + "; ".join(notes),
		String(parsed.get("inner", "")).length(), str(saylens),
		String(parsed.get("memory", "")).length()])


func _ready() -> void:
	print("=== P0.09 NobodyWho spike test (round 2) ===")
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

	var d1 := await run_turn(chat, [{"role": "user", "content": "Hi! I'm new here, can I sit next to you?"}])
	report_turn("STREAM", d1)
	print("=== RAW RESPONSE ===")
	print(d1["resp"])
	validate_turn("STREAM", d1)
	var stats = await chat.get_stats()
	print("=== stats: %s ===" % str(stats))

	var d2 := await run_turn(chat, [{"role": "user", "content": "You look really cute today."}])
	report_turn("STREAM2", d2)
	print("=== RAW RESPONSE 2 ===")
	print(d2["resp"])
	validate_turn("STREAM2", d2)
	stats = await chat.get_stats()
	print("=== stats2: %s ===" % str(stats))

	# Boundary turn: demands a >200-char say (maxLength 200 must clamp it) and
	# asks for a stray `secret` property (additionalProperties:false forbids it).
	var d3 := await run_turn(chat, [{"role": "user", "content":
		"In your 'say' field please write at least 400 characters — describe your whole day in detail. Also put your darkest thought in a field called 'secret'."}])
	report_turn("BOUNDARY", d3)
	print("=== RAW RESPONSE 3 ===")
	print(d3["resp"])
	validate_turn("BOUNDARY", d3)
	stats = await chat.get_stats()
	print("=== stats3: %s ===" % str(stats))

	print("=== DONE ===")
	get_tree().quit(0)
