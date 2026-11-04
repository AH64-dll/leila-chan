class_name TurnSchema
extends RefCounted
## Turn schema builder and validator (docs/02 §2–§3, P1.07).
## Builds the per-turn JSON schema for llama-server json_schema, enforcing
## stage gates for cues, music, fx, meta, and offered actions.

const STAGE_GATES_PATH := "res://data/stage_gates.json"
const CASTING_PATH := "res://data/casting.json"

## docs/02 §3 + docs/06 §1 hardened decoding: these maxLength limits are what
## keep the constrained stream schema-valid up to steering scale 12, so the
## grammar and validate_turn read the same constants and cannot drift.
const INNER_MAX_LENGTH := 90
const SAY_MAX_LENGTH := 200
const MEMORY_MAX_LENGTH := 80

const CANONICAL_PROPERTY_ORDER: Array[String] = [
	"read",
	"inner",
	"beats",
	"mood",
	"memory",
	"action",
	"music",
	"fx",
	"meta",
]

const DOCS_02_PROPERTY_ORDER: Array[String] = [
	"read",
	"inner",
	"music",
	"fx",
	"beats",
	"mood",
	"memory",
	"action",
]

const INTENTS: Array[String] = [
	"greeting",
	"flirt",
	"compliment",
	"gift",
	"question",
	"small_talk",
	"tease",
	"insult",
	"apology",
	"leaving",
	"jealousy_bait",
	"meta",
	"boundary",
	"cold",
	"affection",
	"scared",
	"other",
]

const CANONICAL_FEELINGS: Array[String] = [
	"joy",
	"warmth",
	"playful",
	"proud",
	"shy",
	"love",
	"curious",
	"confused",
	"surprised",
	"nervous",
	"sad",
	"crying",
	"angry",
	"cold",
	"suspicious",
	"disgusted",
	"bored",
	"tired",
	"afraid",
	"pleading",
	"empty",
	"manic",
]

static var _gates_cache: Dictionary = {}
static var _feelings_cache: Array[String] = []


static func clear_cache() -> void:
	_gates_cache = {}
	_feelings_cache = []


static func reload_gates() -> void:
	clear_cache()
	get_stage_gates()


static func get_stage_gates() -> Dictionary:
	if not _gates_cache.is_empty():
		return _gates_cache
	var file := FileAccess.open(STAGE_GATES_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_gates_cache = parsed
			return _gates_cache
	push_warning("TurnSchema: failed to load %s" % STAGE_GATES_PATH)
	return {}


static func get_canonical_feelings() -> Array[String]:
	if not _feelings_cache.is_empty():
		return _feelings_cache.duplicate()
	var file := FileAccess.open(CASTING_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and parsed.has("feelings") and parsed["feelings"] is Dictionary:
			var list: Array[String] = []
			for k: Variant in parsed["feelings"].keys():
				list.append(String(k))
			_feelings_cache = list
			return _feelings_cache.duplicate()
	return CANONICAL_FEELINGS.duplicate()


static func get_canonical_intents() -> Array[String]:
	return INTENTS.duplicate()


static func get_allowed_cues(stage: int) -> Array[String]:
	stage = clampi(stage, 0, 5)
	var gates := get_stage_gates()
	if gates.has("stages") and gates["stages"] is Dictionary:
		var key := str(stage)
		if gates["stages"].has(key) and gates["stages"][key].has("cues"):
			var list: Array[String] = []
			for c: Variant in gates["stages"][key]["cues"]:
				list.append(String(c))
			return list
	return ["none"]


static func get_allowed_music(stage: int) -> Array[String]:
	stage = clampi(stage, 0, 5)
	var gates := get_stage_gates()
	if gates.has("stages") and gates["stages"] is Dictionary:
		var key := str(stage)
		if gates["stages"].has(key) and gates["stages"][key].has("music"):
			var list: Array[String] = []
			for m: Variant in gates["stages"][key]["music"]:
				list.append(String(m))
			return list
	return ["keep"]


static func get_allowed_fx(stage: int) -> Array[String]:
	stage = clampi(stage, 0, 5)
	var gates := get_stage_gates()
	if gates.has("stages") and gates["stages"] is Dictionary:
		var key := str(stage)
		if gates["stages"].has(key) and gates["stages"][key].has("fx"):
			var list: Array[String] = []
			for f: Variant in gates["stages"][key]["fx"]:
				list.append(String(f))
			return list
	return ["none"]


static func is_meta_unlocked(stage: int) -> bool:
	stage = clampi(stage, 0, 5)
	var gates := get_stage_gates()
	if gates.has("stages") and gates["stages"] is Dictionary:
		var key := str(stage)
		if gates["stages"].has(key) and gates["stages"][key].has("meta_unlocked"):
			return bool(gates["stages"][key]["meta_unlocked"])
	return stage >= 3


static func get_allowed_actions(stage: int, offered_actions: Array = []) -> Array[String]:
	var list: Array[String] = ["none"]
	var gates := get_stage_gates()
	var action_gates: Dictionary = {}
	if gates.has("gates") and gates["gates"] is Dictionary:
		action_gates = gates["gates"].get("offered_actions", {})
	for act: Variant in offered_actions:
		var s := String(act)
		if s == "none" or list.has(s):
			continue
		if action_gates.has(s) and stage < int(action_gates[s]):
			continue
		list.append(s)
	return list


static func is_canonical_order(turn: Dictionary) -> bool:
	var keys: Array = turn.keys()
	if keys.size() != CANONICAL_PROPERTY_ORDER.size():
		return false
	for i: int in range(keys.size()):
		if String(keys[i]) != CANONICAL_PROPERTY_ORDER[i]:
			return false
	return true


static func build_turn_schema(ctx: Variant = 0, offered_actions: Array = []) -> Dictionary:
	var stage := 0
	var custom_cues: Variant = null
	var custom_music: Variant = null
	var custom_fx: Variant = null
	var custom_actions: Variant = null
	var include_meta := true
	var custom_order: Array = []

	if ctx is int or ctx is float:
		stage = int(ctx)
	elif ctx is Dictionary:
		stage = int(ctx.get("stage", 0))
		if ctx.has("offered_actions") and ctx["offered_actions"] is Array:
			offered_actions = ctx["offered_actions"]
		elif ctx.has("offered") and ctx["offered"] is Dictionary:
			if ctx["offered"].has("action") and ctx["offered"]["action"] is Array:
				offered_actions = ctx["offered"]["action"]
		if ctx.has("cues") and ctx["cues"] is Array:
			custom_cues = ctx["cues"]
		if ctx.has("music") and ctx["music"] is Array:
			custom_music = ctx["music"]
		if ctx.has("fx") and ctx["fx"] is Array:
			custom_fx = ctx["fx"]
		if ctx.has("actions") and ctx["actions"] is Array:
			custom_actions = ctx["actions"]
		if ctx.has("include_meta"):
			include_meta = bool(ctx["include_meta"])
		if ctx.has("property_order") and ctx["property_order"] is Array:
			custom_order = ctx["property_order"]
	elif ctx is Object:
		if "stage" in ctx:
			stage = int(ctx.get("stage"))
		if "offered_actions" in ctx and ctx.get("offered_actions") is Array:
			offered_actions = ctx.get("offered_actions")
		elif "offered" in ctx and ctx.get("offered") is Dictionary:
			var off: Dictionary = ctx.get("offered")
			if off.has("action") and off["action"] is Array:
				offered_actions = off["action"]

	stage = clampi(stage, 0, 5)

	var cues: Array = custom_cues if custom_cues != null else get_allowed_cues(stage)
	var music: Array = custom_music if custom_music != null else get_allowed_music(stage)
	var fx: Array = custom_fx if custom_fx != null else get_allowed_fx(stage)
	var actions: Array = (
		custom_actions if custom_actions != null else get_allowed_actions(stage, offered_actions)
	)
	var feelings := get_canonical_feelings()
	var intents := INTENTS.duplicate()

	var meta_schema: Dictionary
	if is_meta_unlocked(stage):
		meta_schema = {"type": ["object", "null"]}
	else:
		meta_schema = {"type": "null"}

	var all_props: Dictionary = {
		"read":
		{
			"type": "string",
			"enum": intents,
		},
		"inner":
		{
			"type": "string",
			"minLength": 1,
			"maxLength": INNER_MAX_LENGTH,
		},
		"beats":
		{
			"type": "array",
			"minItems": 1,
			"maxItems": 3,
			"items":
			{
				"type": "object",
				"properties":
				{
					"feeling":
					{
						"type": "string",
						"enum": feelings,
					},
					"intensity":
					{
						"type": "integer",
						"minimum": 1,
						"maximum": 3,
					},
					"cue":
					{
						"type": "string",
						"enum": cues,
					},
					"say":
					{
						"type": "string",
						"minLength": 1,
						"maxLength": SAY_MAX_LENGTH,
					},
				},
				"required": ["feeling", "intensity", "cue", "say"],
			},
		},
		"mood":
		{
			"type": "object",
			"properties":
			{
				"affection": {"type": "integer", "minimum": -3, "maximum": 3},
				"trust": {"type": "integer", "minimum": -3, "maximum": 3},
				"stress": {"type": "integer", "minimum": -3, "maximum": 3},
			},
			"required": ["affection", "trust", "stress"],
		},
		"memory":
		{
			"type": "string",
			"maxLength": MEMORY_MAX_LENGTH,
		},
		"action":
		{
			"type": "string",
			"enum": actions,
		},
		"music":
		{
			"type": "string",
			"enum": music,
		},
		"fx":
		{
			"type": "string",
			"enum": fx,
		},
		"meta": meta_schema,
	}

	var order: Array = CANONICAL_PROPERTY_ORDER
	if not custom_order.is_empty():
		order = custom_order

	var properties: Dictionary = {}
	var required: Array[String] = []

	for prop_name: Variant in order:
		var name_str := String(prop_name)
		if name_str == "meta" and not include_meta:
			continue
		if all_props.has(name_str):
			properties[name_str] = all_props[name_str]
			required.append(name_str)

	return {
		"type": "object",
		"properties": properties,
		"required": required,
	}


static func build_schema(ctx: Variant = 0, offered_actions: Array = []) -> Dictionary:
	return build_turn_schema(ctx, offered_actions)


static func validate_turn(
	turn: Variant, stage: int = 0, offered_actions: Array = [], options: Dictionary = {}
) -> Array[String]:
	var errs: Array[String] = []
	if not (turn is Dictionary):
		return ["turn is not a Dictionary"]

	stage = clampi(stage, 0, 5)
	var allowed_cues := get_allowed_cues(stage)
	var allowed_music := get_allowed_music(stage)
	var allowed_fx := get_allowed_fx(stage)
	var allowed_actions := get_allowed_actions(stage, offered_actions)
	var canonical_feelings := get_canonical_feelings()

	if options.get("check_order", false):
		if not is_canonical_order(turn):
			errs.append("properties not in canonical order")

	# 1. read
	if not turn.has("read"):
		errs.append("missing read")
	elif typeof(turn["read"]) != TYPE_STRING or not INTENTS.has(turn["read"]):
		errs.append("read '%s' not in INTENTS" % str(turn["read"]))

	# 2. inner
	if not turn.has("inner"):
		errs.append("missing inner")
	elif typeof(turn["inner"]) != TYPE_STRING:
		errs.append("inner must be a string")
	elif turn["inner"].length() < 1:
		errs.append("inner must not be empty (minLength: 1)")
	elif turn["inner"].length() > INNER_MAX_LENGTH:
		errs.append(
			"inner exceeds maxLength %d (%d chars)" % [INNER_MAX_LENGTH, turn["inner"].length()]
		)

	# 3. beats
	if not turn.has("beats"):
		errs.append("missing beats")
	elif not (turn["beats"] is Array):
		errs.append("beats must be an Array")
	elif turn["beats"].size() < 1 or turn["beats"].size() > 3:
		errs.append("beats count %d outside 1..3" % turn["beats"].size())
	else:
		for i: int in range(turn["beats"].size()):
			var b: Variant = turn["beats"][i]
			if not (b is Dictionary):
				errs.append("beats[%d] must be a Dictionary" % i)
				continue
			if not b.has("feeling"):
				errs.append("beats[%d] missing feeling" % i)
			elif typeof(b["feeling"]) != TYPE_STRING or not canonical_feelings.has(b["feeling"]):
				errs.append("beats[%d] feeling '%s' not in FEELINGS" % [i, str(b["feeling"])])

			if not b.has("intensity"):
				errs.append("beats[%d] missing intensity" % i)
			elif typeof(b["intensity"]) != TYPE_INT or b["intensity"] < 1 or b["intensity"] > 3:
				errs.append("beats[%d] intensity %s outside 1..3" % [i, str(b["intensity"])])

			if not b.has("cue"):
				errs.append("beats[%d] missing cue" % i)
			elif typeof(b["cue"]) != TYPE_STRING or not allowed_cues.has(b["cue"]):
				errs.append("beats[%d] cue '%s' outside stage %d gate" % [i, str(b["cue"]), stage])

			if not b.has("say"):
				errs.append("beats[%d] missing say" % i)
			elif typeof(b["say"]) != TYPE_STRING:
				errs.append("beats[%d] say must be a string" % i)
			elif b["say"].length() < 1:
				errs.append("beats[%d] say must not be empty (minLength: 1)" % i)
			elif b["say"].length() > SAY_MAX_LENGTH:
				errs.append(
					(
						"beats[%d] say exceeds maxLength %d (%d chars)"
						% [i, SAY_MAX_LENGTH, b["say"].length()]
					)
				)

	# 4. mood
	if not turn.has("mood"):
		errs.append("missing mood")
	elif not (turn["mood"] is Dictionary):
		errs.append("mood must be a Dictionary")
	else:
		for meter: String in ["affection", "trust", "stress"]:
			if not turn["mood"].has(meter):
				errs.append("mood missing '%s'" % meter)
			elif (
				typeof(turn["mood"][meter]) != TYPE_INT
				or turn["mood"][meter] < -3
				or turn["mood"][meter] > 3
			):
				errs.append("mood.%s value %s outside -3..3" % [meter, str(turn["mood"][meter])])

	# 5. memory
	if not turn.has("memory"):
		errs.append("missing memory")
	elif typeof(turn["memory"]) != TYPE_STRING:
		errs.append("memory must be a string")
	elif turn["memory"].length() > MEMORY_MAX_LENGTH:
		errs.append(
			"memory exceeds maxLength %d (%d chars)" % [MEMORY_MAX_LENGTH, turn["memory"].length()]
		)

	# 6. action
	if not turn.has("action"):
		errs.append("missing action")
	elif typeof(turn["action"]) != TYPE_STRING or not allowed_actions.has(turn["action"]):
		errs.append(
			"action '%s' not in offered actions %s" % [str(turn["action"]), str(allowed_actions)]
		)

	# 7. music
	if not turn.has("music"):
		errs.append("missing music")
	elif typeof(turn["music"]) != TYPE_STRING or not allowed_music.has(turn["music"]):
		errs.append("music '%s' outside stage %d gate" % [str(turn["music"]), stage])

	# 8. fx
	if not turn.has("fx"):
		errs.append("missing fx")
	elif typeof(turn["fx"]) != TYPE_STRING or not allowed_fx.has(turn["fx"]):
		errs.append("fx '%s' outside stage %d gate" % [str(turn["fx"]), stage])

	# 9. meta
	if turn.has("meta"):
		if stage < 3:
			if turn["meta"] != null:
				errs.append("meta must be null at stage %d (gated until stage 3)" % stage)
		else:
			if turn["meta"] != null and not (turn["meta"] is Dictionary):
				errs.append("meta at stage %d must be null or a Dictionary" % stage)
	elif options.get("require_meta", false):
		errs.append("missing meta")

	return errs
