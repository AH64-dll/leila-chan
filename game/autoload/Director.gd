extends Node
## Director — turn pipeline (docs/02 §4). The only orchestrator of a turn.
## Executes steps 0–7 of docs/02 §4: input hooks, context assembly, dynamic schema,
## steering dose, streaming JSON generation, live subsystem dispatch, validation,
## state application, and turn close.

signal turn_started(turn_index: int, player_input: String)
signal turn_chunk_received(chunk: String)
signal beat_started(beat_index: int)
signal beat_resolved(packet: Dictionary)
signal beat_say_chunk(beat_index: int, chunk: String)
signal beat_cue_requested(cue: String, played: bool)
signal beat_ended(beat_index: int, beat_data: Dictionary)
signal turn_completed(turn_index: int, turn_data: Dictionary)
signal turn_failed(turn_index: int, error_code: String, error_message: String)
signal turn_cancelled(turn_index: int)

## docs/02 §9 Sampling settings by stage table:
## | Stage | temperature | top_p | repeat_penalty | steering dose (base) |
const SAMPLING_TABLE := {
	0: {"temperature": 0.75, "top_p": 0.90, "repeat_penalty": 1.10, "dose": 0.0},
	1: {"temperature": 0.80, "top_p": 0.90, "repeat_penalty": 1.10, "dose": 2.5},
	2: {"temperature": 0.80, "top_p": 0.92, "repeat_penalty": 1.12, "dose": 3.5},
	3: {"temperature": 0.85, "top_p": 0.95, "repeat_penalty": 1.15, "dose": 4.5},
	4: {"temperature": 0.90, "top_p": 0.95, "repeat_penalty": 1.15, "dose": 6.0},
	5: {"temperature": 0.95, "top_p": 0.97, "repeat_penalty": 1.18, "dose": 8.0},
}

const META_WORDS := [
	"player",
	"stage",
	"json",
	"read",
	"inner",
	"music",
	"fx",
	"beats",
	"feeling",
	"intensity",
	"cue",
	"say",
	"mood",
	"memory",
	"action",
	"affection",
	"trust",
	"stress",
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
	"boundary",
	"cold",
	"scared"
]

const DEBUG_OVERLAY_KEY := KEY_F3
## Turn history maintained by Director: array of {"role": "user"|"assistant", ...}
var history: Array[Dictionary] = []
## Validated player memories (docs/02 §6)
var memories: Array[String] = []
## Current active scene info
var scene_info: Dictionary = {
	"prompt": "You are in a small café after class. Two cups, one window seat.",
	"variant": "The afternoon light filters softly through the glass.",
	"event": "",
}

## Subsystem node references (injected or registered)
var character_node: Node = null
var chat_ui_node: Node = null

## Auto-fill state (docs/02 §5: If model chose no cue/fx for 4 turns and intensity >= 2 -> mild one)
var quiet_turn_streak := 0
var last_player_inputs: Array[String] = []

## Last turn state accessible to dev tools, overlay, and inspection
var last_turn_data: Dictionary = {}
var last_dose: Dictionary = {}
var last_offered_actions: Array = []
var last_read: String = ""
var last_inner: String = ""

var transcript_logger: TranscriptLogger = null
var _overlay: CanvasLayer = null

var _active_stream: TurnStream = null
var _parser: IncrementalJson = null
var _current_turn_data: Dictionary = {}
var _current_beats: Array[Dictionary] = []
var _current_beat_index := -1
var _current_beat_data := {}
var _turn_in_flight := false
var _turn_index := 0
var _current_player_input := ""
var _stream_had_error := false
var _stream_error_message := ""
var _retry_count := 0
var _dose_offset := 0.0
var _streamed_say_text := ""
var _current_prompt: Array = []
var _current_schema: Dictionary = {}
var _current_raw_output := ""
var _current_applied_events: Array[Dictionary] = []
var _current_dose: Dictionary = {}
var _current_stage := 0
var _current_path := ""


func _ready() -> void:
	reset()


func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("release"):
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != DEBUG_OVERLAY_KEY:
		return
	toggle_debug_overlay()
	get_viewport().set_input_as_handled()


func reset() -> void:
	history.clear()
	memories.clear()
	last_player_inputs.clear()
	quiet_turn_streak = 0
	last_turn_data.clear()
	last_dose.clear()
	last_offered_actions.clear()
	last_read = ""
	last_inner = ""
	if transcript_logger != null and transcript_logger.is_enabled():
		transcript_logger.end_session()
	_init_transcript_logger()
	_clear_turn_context()
	_current_turn_data.clear()
	_current_beats.clear()
	_current_beat_index = -1
	_current_beat_data.clear()
	_turn_in_flight = false
	_turn_index = 0
	_current_player_input = ""
	_stream_had_error = false
	_stream_error_message = ""
	_retry_count = 0
	_dose_offset = 0.0
	_streamed_say_text = ""
	_parser = null
	_active_stream = null


func _init_transcript_logger() -> void:
	if transcript_logger == null:
		transcript_logger = TranscriptLogger.new()
		_wire_safety_redactor()


func _wire_safety_redactor() -> void:
	if transcript_logger == null:
		return
	var redactor := Callable(self, "_redact_record")
	transcript_logger.set_redactor(redactor)


func _redact_record(record: Dictionary) -> Dictionary:
	if Safety != null and Safety.has_method("redact_record"):
		var res: Variant = Safety.call("redact_record", record)
		if res is Dictionary:
			return res
	if record.has("output") and record["output"] is String:
		record["output"] = filter_output(record["output"])
	return record


func _clear_turn_context() -> void:
	_current_prompt = []
	_current_schema = {}
	_current_raw_output = ""
	_current_applied_events.clear()
	_current_dose = {}
	_current_stage = 0
	_current_path = ""


func is_busy() -> bool:
	return _turn_in_flight


func register_character(node: Node) -> void:
	character_node = node


func register_chat_ui(node: Node) -> void:
	chat_ui_node = node
	if chat_ui_node != null and chat_ui_node.has_method("set_text_filter"):
		chat_ui_node.text_filter = Callable(self, "filter_output")


func toggle_debug_overlay() -> void:
	if OS.has_feature("release"):
		return
	if _overlay == null or not is_instance_valid(_overlay):
		var scene := load("res://scenes/debug/DebugOverlay.tscn") as PackedScene
		if scene != null:
			_overlay = scene.instantiate() as CanvasLayer
			get_tree().root.add_child(_overlay)
	if _overlay != null:
		if _overlay.has_method("toggle"):
			_overlay.toggle()
		else:
			_overlay.visible = not _overlay.visible
			if _overlay.visible and _overlay.has_method("refresh"):
				_overlay.refresh()


func is_debug_overlay_open() -> bool:
	return _overlay != null and is_instance_valid(_overlay) and _overlay.visible


func get_debug_overlay() -> CanvasLayer:
	return _overlay


func set_debug_overlay(overlay: CanvasLayer) -> void:
	_overlay = overlay


func get_last_read() -> String:
	return last_read


func get_last_inner() -> String:
	return last_inner


func get_current_dose() -> Dictionary:
	if not last_dose.is_empty():
		return last_dose
	var stage := int(GameState.stage)
	if Steering != null and Steering.has_method("dose_for"):
		var ctx := {
			"stage": stage,
			"path": String(GameState.path),
			"player_name": GameState.player_name,
			"scene": scene_info,
			"memories": memories.duplicate(),
			"events": [],
			"history": history.duplicate(true),
			"player_message": "",
			"offered_actions": get_offered_actions(),
		}
		return Steering.dose_for(ctx)
	var sampling_spec: Dictionary = SAMPLING_TABLE.get(stage, SAMPLING_TABLE[0])
	return {"base": float(sampling_spec.get("dose", 0.0))}


func get_offered_actions() -> Array:
	if not last_offered_actions.is_empty():
		return last_offered_actions
	var stage := int(GameState.stage)
	if MetaDirector != null and MetaDirector.has_method("offers"):
		return MetaDirector.offers(stage)
	return []


## -----------------------------------------------------------------------------
## Step 0: Input Reception & Pre-Turn Processing
## -----------------------------------------------------------------------------
func submit_player_input(raw_input: String, telemetry: Dictionary = {}) -> bool:
	if _turn_in_flight:
		push_warning("Director: turn already in flight; ignoring submit_player_input")
		return false

	var trimmed := raw_input.strip_edges()
	if trimmed.is_empty():
		return false

	# Step 0.1: Safety check on player input
	if not filter_player_input(trimmed):
		turn_failed.emit(_turn_index, "unsafe_input", "Input blocked by safety policy")
		return false

	# Step 0.2: Telemetry / Typing hooks (docs/02 §4 step 0)
	_handle_input_telemetry(trimmed, telemetry)

	# Track player input window for memory validation (docs/02 §6)
	last_player_inputs.append(trimmed)
	if last_player_inputs.size() > 3:
		last_player_inputs.pop_front()

	# Step 0.3: History append
	history.append({"role": "user", "text": trimmed})

	_current_player_input = trimmed
	_retry_count = 0
	_dose_offset = 0.0
	# Step 1–4: Prepare and launch generation
	return _start_turn(trimmed)


func _handle_input_telemetry(input_text: String, telemetry: Dictionary) -> void:
	if telemetry.has("deleted_draft") and not str(telemetry["deleted_draft"]).is_empty():
		GameState.set_flag(&"t08_deleted_draft", telemetry["deleted_draft"])
	if telemetry.has("idle_seconds") and float(telemetry["idle_seconds"]) > 30.0:
		GameState.set_flag(&"t11_idle", true)
	if Triggers.has_method("check_keyword_triggers"):
		Triggers.check_keyword_triggers(input_text)


## -----------------------------------------------------------------------------
## Steps 1–4: TurnContext, Prompt, Schema, Dose & LLM generation
## -----------------------------------------------------------------------------
func _start_turn(player_text: String) -> bool:
	_turn_in_flight = true
	_turn_index = GameState.turn
	_current_turn_data = {}
	_current_beats = []
	_current_beat_index = -1
	_current_beat_data = {}
	_stream_had_error = false
	_stream_error_message = ""
	_streamed_say_text = ""
	_clear_turn_context()
	_current_stage = int(GameState.stage)
	_current_path = String(GameState.path)

	turn_started.emit(_turn_index, player_text)

	if AudioDirector != null and AudioDirector.has_method("begin_turn"):
		AudioDirector.begin_turn()

	if chat_ui_node != null and chat_ui_node.has_method("begin_turn_wait"):
		chat_ui_node.begin_turn_wait()

	# Step 1: TurnContext assembly
	var stage := int(GameState.stage)
	var offered_actions := []
	if MetaDirector != null and MetaDirector.has_method("offers"):
		offered_actions = MetaDirector.offers(stage)

	var ctx := {
		"stage": stage,
		"path": String(GameState.path),
		"player_name": GameState.player_name,
		"scene": scene_info,
		"memories": memories.duplicate(),
		"events": [],
		"history": history.duplicate(true),
		"player_message": player_text,
		"offered_actions": offered_actions,
	}

	# Step 2: Prompt assembly via PromptBuilder
	var prompt_res: Dictionary = PromptBuilder.build(ctx)
	var messages: Array = prompt_res.get("messages", [])

	# Step 3: Schema assembly via TurnSchema
	var schema: Dictionary = TurnSchema.build_turn_schema(ctx, offered_actions)
	_current_prompt = messages.duplicate(true)
	_current_schema = schema.duplicate(true)

	# Step 4: Sampling and steering dose
	var sampling_spec: Dictionary = SAMPLING_TABLE.get(stage, SAMPLING_TABLE[0])
	var sampling_dict := {
		"temperature": float(sampling_spec.get("temperature", 0.75)),
		"top_p": float(sampling_spec.get("top_p", 0.90)),
		"repeat_penalty": float(sampling_spec.get("repeat_penalty", 1.10)),
	}

	var dose_dict := {}
	if Steering != null and Steering.has_method("dose_for"):
		dose_dict = Steering.dose_for(ctx)
	elif float(sampling_spec.get("dose", 0.0)) > 0.0:
		dose_dict = {"base": float(sampling_spec.get("dose", 0.0))}
	# docs/02 §7 empty-say retry: dose -2 applies to whichever dose source won
	if not dose_dict.is_empty():
		dose_dict["base"] = maxf(0.0, float(dose_dict.get("base", 0.0)) + _dose_offset)
	last_offered_actions = offered_actions.duplicate()
	last_dose = dose_dict.duplicate()

	_current_dose = dose_dict.duplicate(true)
	# Create LLM TurnRequest
	var req := TurnRequest.new()
	req.messages = messages
	req.schema = schema
	req.sampling = sampling_dict
	req.dose = dose_dict
	req.max_tokens = 600

	# Step 5: Start streaming through IncrementalJson
	_parser = IncrementalJson.new()
	_active_stream = LLM.generate(req)
	_active_stream.token.connect(_on_llm_token)
	_active_stream.completed.connect(_on_llm_completed)
	_active_stream.failed.connect(_on_llm_failed)
	_active_stream.cancelled.connect(_on_llm_cancelled)

	return true


## -----------------------------------------------------------------------------
## Stream events & Live routing (Steps 5–6)
## -----------------------------------------------------------------------------
func _on_llm_token(token_text: String) -> void:
	if not _turn_in_flight or _parser == null:
		return

	turn_chunk_received.emit(token_text)
	_current_raw_output += token_text
	var events: Array = _parser.feed(token_text)
	for event: Dictionary in events:
		_process_stream_event(event)
		_current_applied_events.append(event.duplicate(true))


func _process_stream_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	match event_type:
		"field":
			var fname: String = str(event.get("name", ""))
			var fval: Variant = event.get("value")
			_current_turn_data[fname] = fval
			_on_field_received(fname, fval)

		"beat_start":
			var b_idx: int = int(event.get("index", 0))
			_current_beat_index = b_idx
			_current_beat_data = {"index": b_idx, "say": ""}
			beat_started.emit(b_idx)
			if chat_ui_node != null and chat_ui_node.has_method("begin_beat"):
				chat_ui_node.begin_beat(b_idx)

		"beat_field":
			var b_idx: int = int(event.get("index", 0))
			var b_name: String = str(event.get("name", ""))
			var b_val: Variant = event.get("value")
			_current_beat_data[b_name] = b_val
			_on_beat_field_received(b_idx, b_name, b_val)

		"say_chunk":
			var b_idx: int = int(event.get("index", 0))
			var raw_say: String = str(event.get("text", ""))
			_streamed_say_text += raw_say
			var filtered_say := filter_output(raw_say)
			beat_say_chunk.emit(b_idx, filtered_say)
			if chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
				chat_ui_node.say_chunk(b_idx, filtered_say)

		"error":
			_stream_had_error = true
			_stream_error_message = str(event.get("message", "parse error"))
			push_warning("Director: IncrementalJson parse error: %s" % _stream_error_message)


func _on_field_received(field_name: String, value: Variant) -> void:
	match field_name:
		"music":
			var m_state := StringName(str(value))
			if AudioDirector != null and AudioDirector.has_method("request_music"):
				AudioDirector.request_music(m_state)

		"fx":
			var fx_name := str(value)
			var stage := int(GameState.stage)
			if FX != null and FX.has_method("trigger"):
				FX.trigger(fx_name, stage)


func _on_beat_field_received(beat_index: int, field_name: String, value: Variant) -> void:
	match field_name:
		"feeling":
			_maybe_route_sprite()

		"intensity":
			_maybe_route_sprite()

		"cue":
			var cue_name := str(value)
			var played := false
			if cue_name != "none" and cue_name != "":
				if AudioDirector != null and AudioDirector.has_method("play_cue"):
					played = AudioDirector.play_cue(StringName(cue_name))
			beat_cue_requested.emit(cue_name, played)

		"say":
			var raw_say_val := str(value)
			_current_beat_data["say"] = raw_say_val
			if chat_ui_node != null and chat_ui_node.has_method("end_beat"):
				chat_ui_node.end_beat(beat_index)
			_current_beats.append(_current_beat_data.duplicate())
			beat_ended.emit(beat_index, _current_beat_data)


func _maybe_route_sprite() -> void:
	if not _current_beat_data.has("feeling") or not _current_beat_data.has("intensity"):
		return
	if _current_beat_data.get("_sprite_routed", false):
		return

	_current_beat_data["_sprite_routed"] = true
	var feeling: String = str(_current_beat_data["feeling"])
	var intensity: int = int(_current_beat_data["intensity"])
	var stage: int = int(GameState.stage)
	var path: String = String(GameState.path)

	var packet: Dictionary = SpriteResolver.resolve_beat(feeling, intensity, stage, path)
	beat_resolved.emit(packet)

	if character_node != null and character_node.has_method("set_feeling"):
		character_node.set_feeling(feeling, intensity, stage, path)
	elif character_node != null and character_node.has_method("set_sprite"):
		character_node.set_sprite(str(packet.get("sprite", "00")))


## -----------------------------------------------------------------------------
## Step 6 & 7: Turn Close, State Application, Validation & Fallbacks
## -----------------------------------------------------------------------------
func _on_llm_completed(_raw_text: String) -> void:
	if not _turn_in_flight:
		return
	var parser_status := IncrementalJson.Status.OK
	if _parser != null:
		parser_status = _parser.finish()
		var full_val: Variant = _parser.get_value()
		if full_val is Dictionary:
			for k: Variant in full_val:
				_current_turn_data[str(k)] = full_val[k]

	if not _current_turn_data.has("beats") and not _current_beats.is_empty():
		_current_turn_data["beats"] = _current_beats

	var stage := int(GameState.stage)

	# Docs/02 §7: Broken JSON / stream parse error handling. TRUNCATED counts:
	# the stream died mid-JSON, so whatever partial `say` streamed is shown
	# through the fallback instead of being dropped.
	if (
		_stream_had_error
		or parser_status == IncrementalJson.Status.ERROR
		or parser_status == IncrementalJson.Status.TRUNCATED
	):
		_handle_broken_json_fallback(stage)
		return

	# Docs/02 §7: Empty say handling
	var all_say_empty := true
	var beats_arr: Array = _current_turn_data.get("beats", [])
	for b: Variant in beats_arr:
		if b is Dictionary and not str(b.get("say", "")).strip_edges().is_empty():
			all_say_empty = false
			break
	if beats_arr.is_empty() or all_say_empty:
		if stage < 3 and _retry_count == 0:
			_retry_count += 1
			_dose_offset = -2.0
			_start_turn(_current_player_input)
			return
		# Stage >= 3, or stage < 3 after the retry already failed: the ellipsis
		# beat is the closest defined fallback for a turn with nothing to say.
		_handle_empty_say_fallback()
		return

	# Docs/02 §7: Third-person pronoun repair, character-break deflection, repetition loop
	_apply_turn_repairs_and_deflections(_current_turn_data, stage)

	_current_raw_output = _raw_text
	_close_turn_success(_current_turn_data)


func _handle_broken_json_fallback(stage: int) -> void:
	var fallback_info: Dictionary = TurnValidator.get_broken_stream_fallback(
		_streamed_say_text, stage, GameState.player_name
	)
	var fallback_say: String = str(fallback_info.get("say", "..."))
	var fb_beat: Dictionary = {
		"feeling": str(fallback_info.get("feeling", "confused")),
		"intensity": int(fallback_info.get("intensity", 1)),
		"cue": str(fallback_info.get("cue", "none")),
		"say": fallback_say,
	}
	_current_turn_data["beats"] = [fb_beat]
	_current_turn_data["read"] = _current_turn_data.get("read", "other")
	_current_turn_data["inner"] = _current_turn_data.get("inner", "...")
	_current_turn_data["music"] = _current_turn_data.get("music", "keep")
	_current_turn_data["fx"] = str(fallback_info.get("fx", "none"))
	_current_turn_data["mood"] = _current_turn_data.get(
		"mood", {"affection": 0, "trust": 0, "stress": 1}
	)
	_current_turn_data["memory"] = ""
	_current_turn_data["action"] = "none"
	# Route sprite 29 (stage >= 3) or 00; glitch fx only exists from stage 3
	var target_sprite: String = str(fallback_info.get("sprite", "00"))
	if character_node != null and character_node.has_method("set_sprite"):
		character_node.set_sprite(target_sprite)
	var fallback_fx := str(fallback_info.get("fx", "none"))
	if fallback_fx != "none" and FX != null and FX.has_method("trigger"):
		FX.trigger(fallback_fx, stage)

	# Overwrite the beat whose partial say is already queued on screen — a
	# second say_chunk would duplicate the partial text. UI implementations
	# without replace_beat get a plain chunk instead.
	if chat_ui_node != null and chat_ui_node.has_method("replace_beat"):
		chat_ui_node.replace_beat(0, fallback_say)
	elif chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
		chat_ui_node.say_chunk(0, filter_output(fallback_say))
	beat_ended.emit(0, fb_beat)
	_close_turn_success(_current_turn_data)


func _handle_empty_say_fallback() -> void:
	var fb_beat: Dictionary = {
		"feeling": "empty",
		"intensity": 1,
		"cue": "none",
		"say": "…",
	}
	_current_turn_data["beats"] = [fb_beat]
	_current_turn_data["read"] = _current_turn_data.get("read", "other")
	_current_turn_data["inner"] = _current_turn_data.get("inner", "...")
	_current_turn_data["music"] = _current_turn_data.get("music", "keep")
	_current_turn_data["fx"] = "none"
	_current_turn_data["mood"] = _current_turn_data.get(
		"mood", {"affection": 0, "trust": 0, "stress": 0}
	)
	_current_turn_data["action"] = "none"

	# Show "..." (docs/02 §7: stage >= 3 gets a stuck typing indicator).
	# The player can't respond to nothing, so the turn still closes cleanly.
	beat_say_chunk.emit(0, "…")
	if chat_ui_node != null and chat_ui_node.has_method("replace_beat"):
		chat_ui_node.replace_beat(0, "…")
	elif chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
		chat_ui_node.say_chunk(0, "…")
	beat_ended.emit(0, fb_beat)
	_close_turn_success(_current_turn_data)


func _apply_turn_repairs_and_deflections(turn_data: Dictionary, stage: int) -> void:
	var beats_list: Array = turn_data.get("beats", [])
	var player_name := GameState.player_name

	for i in range(beats_list.size()):
		var b_variant: Variant = beats_list[i]
		if not (b_variant is Dictionary):
			continue
		var beat: Dictionary = b_variant
		var beat_index := int(beat.get("index", i))
		var original_say := str(beat.get("say", ""))
		var say_text := original_say

		# 1. Early character-break deflection
		if TurnValidator.check_character_break(say_text, stage):
			GameState.bump_profile(&"meta_curiosity", 1)
			var def_beat: Dictionary = TurnValidator.get_deflection_beat(player_name)
			beat["feeling"] = def_beat.get("feeling", beat.get("feeling", "confused"))
			beat["intensity"] = int(def_beat.get("intensity", beat.get("intensity", 1)))
			beat["cue"] = def_beat.get("cue", beat.get("cue", "none"))
			say_text = str(def_beat.get("say", ""))
		else:
			# 2. Third-person pronoun repair in say ("He's being mean" -> "You're being mean")
			say_text = TurnValidator.repair_player_pronouns(say_text, player_name)

			# 3. Repetition loop detection (same 4-gram x3)
			var loop_info: Dictionary = TurnValidator.detect_repetition_loop(say_text)
			if bool(loop_info.get("has_loop", false)):
				say_text = str(loop_info.get("clean_text", say_text))
				if stage >= 4:
					if FX != null and FX.has_method("trigger"):
						FX.trigger("text_bleed", stage)

		beat["say"] = say_text
		beats_list[i] = beat

		# The streamed chunks are already queued on screen; if the repair
		# changed the say text, rewrite the queued beat so the screen shows
		# the corrected line, not the raw one.
		if say_text != original_say:
			if chat_ui_node != null and chat_ui_node.has_method("replace_beat"):
				chat_ui_node.replace_beat(beat_index, say_text)
			elif chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
				chat_ui_node.say_chunk(beat_index, filter_output(say_text))

	turn_data["beats"] = beats_list


func _close_turn_success(turn_data: Dictionary) -> void:
	var stage := int(GameState.stage)

	# Validate turn semantics (docs/02 §7)
	var val_errors: Array[String] = TurnSchema.validate_turn(turn_data, stage)
	if not val_errors.is_empty():
		push_warning("Director: semantic validation warnings: %s" % str(val_errors))

	# Auto-fill check (docs/02 §5: If model chose no cue/fx for 4 turns and intensity >= 2 -> mild one)
	_handle_auto_fill(turn_data, stage)

	last_turn_data = turn_data.duplicate(true)
	last_read = str(turn_data.get("read", ""))
	last_inner = str(turn_data.get("inner", ""))
	# Step 7: Apply to GameState
	# Apply mood
	if turn_data.has("mood") and turn_data["mood"] is Dictionary:
		GameState.apply_mood(turn_data["mood"])

	# Apply read
	if turn_data.has("read"):
		var read_label := StringName(str(turn_data["read"]))
		GameState.apply_read(read_label)

	# Apply memory
	if turn_data.has("memory") and str(turn_data["memory"]) != "":
		var mem_candidate := str(turn_data["memory"]).strip_edges()
		if validate_memory(mem_candidate, last_player_inputs, memories):
			memories.append(mem_candidate)
			if memories.size() > 24:
				memories.pop_front()
			if Memory != null and Memory.has_method("add_memory"):
				Memory.add_memory(mem_candidate)

	# Apply action
	if turn_data.has("action") and str(turn_data["action"]) != "none":
		var act := str(turn_data["action"])
		if MetaDirector != null and MetaDirector.has_method("execute_after_text"):
			MetaDirector.execute_after_text(act)

	# Apply slow burn & advance turn
	GameState.apply_slow_burn()
	GameState.advance_turn()

	if FX != null and FX.has_method("end_turn"):
		FX.end_turn()

	# Record assistant turn into history
	(
		history
		. append(
			{
				"role": "assistant",
				"turn": turn_data.duplicate(true),
			}
		)
	)

	if chat_ui_node != null and chat_ui_node.has_method("end_turn"):
		chat_ui_node.end_turn()

	_turn_in_flight = false
	_active_stream = null
	_parser = null

	turn_completed.emit(_turn_index, turn_data)
	_log_turn_record("completed")
	_clear_turn_context()


func _handle_auto_fill(turn_data: Dictionary, stage: int) -> void:
	if stage > 1:
		quiet_turn_streak = 0
		return

	var had_cue := false
	var max_intensity := 0
	var beats: Array = turn_data.get("beats", [])
	for b: Variant in beats:
		if b is Dictionary:
			if str(b.get("cue", "none")) != "none" and str(b.get("cue", "")) != "":
				had_cue = true
			var inten := int(b.get("intensity", 1))
			if inten > max_intensity:
				max_intensity = inten

	var had_fx := str(turn_data.get("fx", "none")) != "none" and str(turn_data.get("fx", "")) != ""

	if had_cue or had_fx:
		quiet_turn_streak = 0
	else:
		quiet_turn_streak += 1
		if quiet_turn_streak >= 4 and max_intensity >= 2:
			# Auto-fill mild cue or fx
			if AudioDirector != null and AudioDirector.has_method("play_cue"):
				AudioDirector.play_cue(&"giggle")
			if FX != null and FX.has_method("trigger"):
				FX.trigger("blush_glow", stage)
			quiet_turn_streak = 0


func _on_llm_failed(err_dict: Dictionary) -> void:
	if not _turn_in_flight:
		return
	var code := str(err_dict.get("code", "unknown_error"))
	var msg := str(err_dict.get("message", "generation failed"))
	_abort_turn(code, msg)
	_log_turn_record("failed", code, msg)
	_clear_turn_context()


func _on_llm_cancelled() -> void:
	if not _turn_in_flight:
		return
	_turn_in_flight = false
	if chat_ui_node != null and chat_ui_node.has_method("abort_turn"):
		chat_ui_node.abort_turn()
	turn_cancelled.emit(_turn_index)
	_log_turn_record("cancelled")
	_clear_turn_context()


func cancel() -> void:
	if _active_stream != null:
		_active_stream.cancel()
	elif _turn_in_flight:
		_on_llm_cancelled()


func _abort_turn(error_code: String, error_message: String) -> void:
	_turn_in_flight = false
	if chat_ui_node != null and chat_ui_node.has_method("abort_turn"):
		chat_ui_node.abort_turn()
	turn_failed.emit(_turn_index, error_code, error_message)


func _log_turn_record(status: String, err_code := "", err_msg := "") -> void:
	if transcript_logger == null:
		return
	var metrics: Dictionary = {}
	if LLM != null and LLM.has_method("last_metrics"):
		metrics = LLM.last_metrics()

	var error_dict := {}
	if not err_code.is_empty() or not err_msg.is_empty():
		error_dict = {"code": err_code, "message": err_msg}
	elif status == "cancelled":
		error_dict = {"code": "cancelled", "message": "turn cancelled by player or director"}

	var record := {
		"turn": _turn_index,
		"prompt": _current_prompt,
		"schema": _current_schema,
		"output": _current_raw_output,
		"metrics": metrics,
		"events": _current_applied_events.duplicate(true),
		"stage": _current_stage,
		"path": _current_path,
		"dose": _current_dose,
		"day": int(GameState.day),
		"meta": {"status": status},
	}
	if not error_dict.is_empty():
		record["error"] = error_dict

	transcript_logger.log_turn(record)


## Replay stub (P1.18, docs/07 §5): re-feeds a transcript record or file back
## to the Director by driving IncrementalJson events through the turn pipeline.
func replay_turn(turn_record: Dictionary) -> bool:
	if _turn_in_flight:
		push_warning("Director: turn in flight; cannot replay")
		return false

	var raw_output: String = str(turn_record.get("output", ""))
	var prompt_msgs: Variant = turn_record.get("prompt", [])
	var player_text := ""
	if prompt_msgs is Array:
		for m: Variant in prompt_msgs:
			if m is Dictionary and str(m.get("role", "")) == "user":
				player_text = str(m.get("content", ""))

	_turn_in_flight = true
	_turn_index = int(turn_record.get("turn", GameState.turn))
	_current_turn_data = {}
	_current_beats = []
	_current_beat_index = -1
	_current_beat_data = {}
	_clear_turn_context()
	_current_prompt = prompt_msgs if prompt_msgs is Array else []
	_current_schema = turn_record.get("schema", {})
	_current_raw_output = raw_output
	_current_stage = int(turn_record.get("stage", GameState.stage))
	_current_path = String(turn_record.get("path", GameState.path))
	_current_dose = turn_record.get("dose", {})

	turn_started.emit(_turn_index, player_text)

	_parser = IncrementalJson.new()
	var events: Array = _parser.feed(raw_output)
	for event: Dictionary in events:
		_process_stream_event(event)
		_current_applied_events.append(event.duplicate(true))

	_on_llm_completed(raw_output)
	return true


## -----------------------------------------------------------------------------
## Safety & Content Filters (docs/02 §8)
## -----------------------------------------------------------------------------
func filter_player_input(input_text: String) -> bool:
	if Safety != null and Safety.has_method("check_input"):
		return bool(Safety.check_input(input_text))
	var lower := input_text.to_lower()
	var hard_blocks := ["kill yourself", "kys", "suicide instruction"]
	for b in hard_blocks:
		if b in lower:
			return false
	return true


func filter_output(text_chunk: String) -> String:
	if Safety != null and Safety.has_method("filter_output"):
		return str(Safety.filter_output(text_chunk))
	var filtered := text_chunk
	var forbidden := ["I want to die", "I want you to die"]
	for phrase in forbidden:
		if phrase in filtered:
			filtered = filtered.replace(phrase, "██████")
	return filtered


## -----------------------------------------------------------------------------
## Memory Validation (docs/02 §6)
## -----------------------------------------------------------------------------
static func validate_memory(
	candidate: String, player_inputs: Array[String], existing_memories: Array[String]
) -> bool:
	var trimmed := candidate.strip_edges()
	if trimmed.is_empty() or trimmed.length() > 80:
		return false

	var lower_cand := trimmed.to_lower()
	var cand_tokens := _tokenize(lower_cand)
	if cand_tokens.is_empty():
		return false

	for mw: String in META_WORDS:
		if cand_tokens.has(mw):
			return false
	# Rule 1: Shares >= 1 content word with last 3 player messages
	var player_tokens: Dictionary = {}
	for inp: String in player_inputs:
		for tok: String in _tokenize(inp.to_lower()):
			if tok.length() > 2:
				player_tokens[tok] = true

	var shares_word := false
	for tok: String in cand_tokens:
		if tok.length() > 2 and player_tokens.has(tok):
			shares_word = true
			break
	if not shares_word and not player_inputs.is_empty():
		return false

	# Rule 3: Jaccard < 0.6 vs existing
	for ex: String in existing_memories:
		var ex_tokens := _tokenize(ex.to_lower())
		if _jaccard_similarity(cand_tokens, ex_tokens) >= 0.6:
			return false

	return true


static func _tokenize(text: String) -> Array[String]:
	var regex := RegEx.new()
	regex.compile("\\w+")
	var matches: Array[RegExMatch] = regex.search_all(text)
	var tokens: Array[String] = []
	for m: RegExMatch in matches:
		tokens.append(m.get_string())
	return tokens


static func _jaccard_similarity(a: Array[String], b: Array[String]) -> float:
	var set_a: Dictionary = {}
	var set_b: Dictionary = {}
	for tok: String in a:
		set_a[tok] = true
	for tok: String in b:
		set_b[tok] = true

	var intersection_count := 0
	for tok: String in set_a:
		if set_b.has(tok):
			intersection_count += 1

	var union_count := set_a.size()
	for tok: String in set_b:
		if not set_a.has(tok):
			union_count += 1

	if union_count == 0:
		return 0.0
	return float(intersection_count) / float(union_count)
