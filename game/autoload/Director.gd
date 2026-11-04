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

const DEBUG_OVERLAY_KEY := KEY_F3
const UNSAFE_INPUT_CODE := "unsafe_input"
const UNSAFE_INPUT_MESSAGE := "Input blocked by safety policy"
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
## The single say scanner (docs/02 §8). Owns the beat boundary calls so no other
## node installs a second filter over the same text.
var _safety := SaySafetyGate.new()
## The transcript redactor (gate r2 B1) — see _wire_safety_redactor(). Held in a
## member because a Callable does not keep its RefCounted target alive.
var _redactor: TranscriptRedactor = null

var _active_stream: TurnStream = null
var _parser: IncrementalJson = null
var _current_turn_data: Dictionary = {}
var _current_beats: Array[Dictionary] = []
var _current_beat_index := -1
var _current_beat_data := {}
var _turn_in_flight := false
var _turn_index := 0
var _current_player_input := ""
var _turn_events: Array = []
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
	_connect_stage()
	reset()


## docs/02 §5 gates are keyed on the stage, so AudioDirector must be told every
## time GameState's derived stage moves — not only at scene install (CODE-2).
func _connect_stage() -> void:
	if not GameState.stage_changed.is_connected(_on_stage_changed):
		GameState.stage_changed.connect(_on_stage_changed)
	_sync_stage()


func _on_stage_changed(_previous: int, current: int) -> void:
	if AudioDirector != null and AudioDirector.has_method("set_stage"):
		AudioDirector.set_stage(current)


func _sync_stage() -> void:
	if AudioDirector != null and AudioDirector.has_method("set_stage"):
		AudioDirector.set_stage(int(GameState.stage))
	_safety.set_filter(Safety)


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
	_sync_stage()


func _init_transcript_logger() -> void:
	if transcript_logger == null:
		transcript_logger = TranscriptLogger.new()
		_wire_safety_redactor()


func _wire_safety_redactor() -> void:
	if transcript_logger == null:
		return
	if _redactor == null:
		_redactor = TranscriptRedactor.new(_safety)
	# TranscriptRedactor (gate r2 B1) scans `output`, every text-bearing event
	# payload and the assistant history in `prompt` through the display filter,
	# so no unredacted model text can reach a transcript line.
	transcript_logger.set_redactor(Callable(_redactor, "redact_record"))


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


## The ChatUI seam (docs/07 §3.4). The scene that instantiates the ChatUI owns
## the registration: `Date._ready()` registers it and `Date._exit_tree()` clears
## it (P1 gate-r3 F1 / P2.23). Installing a `text_filter` here would scan the
## same text twice — the Director scans every say chunk through Safety itself
## before handing it over (review CODE-1).
func register_chat_ui(node: Node) -> void:
	chat_ui_node = node


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
		return Steering.dose_for(build_turn_context(""))
	return {"base": float(sampling_spec(stage).get("dose", 0.0))}


## docs/02 §9 sampling row for `stage` (data-owned, see TurnContext).
func sampling_spec(stage: int) -> Dictionary:
	return TurnContext.sampling_spec(stage)


## The docs/02 §4 step 1 snapshot for this turn (see TurnContext.build).
func build_turn_context(player_text: String, events: Array = []) -> Dictionary:
	return TurnContext.build(
		player_text, events, scene_info, memories, history, get_offered_actions()
	)


## docs/08 §5 "Offered this turn — …": the legal enums of this turn.
func offered_values(stage: int, offered_actions: Array) -> Dictionary:
	return TurnContext.offered_values(stage, offered_actions)


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
		_reject_unsafe_input()
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
	_turn_events.clear()
	# Step 1–4: Prepare and launch generation
	return _start_turn(trimmed)


## docs/02 §4 step 0.1 (P1 gate G1 / playtest F3): a refused line never opens a
## turn, so the submit's input lock and typing indicator would never be released.
## Answer with an in-character refusal through the UI's beat path (docs/02 §8
## refuses the line, it never freezes the game) and log the failed record.
func _reject_unsafe_input() -> void:
	_turn_index = GameState.turn  # the record identity: this never-started turn
	_current_stage = int(GameState.stage)
	_current_path = String(GameState.path)
	_log_turn_record("failed", UNSAFE_INPUT_CODE, UNSAFE_INPUT_MESSAGE)
	var refusal: Dictionary = TurnValidator.get_input_refusal(_current_stage, GameState.player_name)
	_safety.end_utterance()  # reply boundary (P1.19 CODE-19): a new utterance
	if chat_ui_node != null and chat_ui_node.has_method("reject_turn"):
		var scanned := _safety.filter_text(str(refusal.get("say", "")), {"stage": _current_stage})
		chat_ui_node.reject_turn(scanned)
	turn_failed.emit(_turn_index, UNSAFE_INPUT_CODE, UNSAFE_INPUT_MESSAGE)


## docs/02 §4 step 0: typing telemetry (T08 deleted draft, T11 idle) and the
## keyword-trigger layer (K). The trigger layer's lines are this turn's
## docs/08 §6 event layer — they reach the prompt through ctx["events"], not
## into the void (review CODE-8).
func _handle_input_telemetry(input_text: String, telemetry: Dictionary) -> void:
	if telemetry.has("deleted_draft") and not str(telemetry["deleted_draft"]).is_empty():
		GameState.set_flag(&"t08_deleted_draft", telemetry["deleted_draft"])
	if telemetry.has("idle_seconds") and float(telemetry["idle_seconds"]) > 30.0:
		GameState.set_flag(&"t11_idle", true)
	if Triggers != null and Triggers.has_method("check_keyword_triggers"):
		var fired: Variant = Triggers.check_keyword_triggers(input_text)
		if fired is Array:
			for line: Variant in fired:
				var event_line := str(line).strip_edges()
				if not event_line.is_empty() and not _turn_events.has(event_line):
					_turn_events.append(event_line)


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

	# Reply boundary (P1.19 r4 CODE-19): a new model utterance starts here, so
	# the filter's cross-beat carry must not glue the previous reply's tail into
	# this reply's first beat. Beats inside this turn keep sharing the carry.
	_safety.end_utterance()

	turn_started.emit(_turn_index, player_text)

	if AudioDirector != null and AudioDirector.has_method("begin_turn"):
		AudioDirector.begin_turn()

	if chat_ui_node != null and chat_ui_node.has_method("begin_turn_wait"):
		chat_ui_node.begin_turn_wait()

	# Step 1: TurnContext assembly (docs/02 §4 step 1 state snapshot)
	var stage := int(GameState.stage)
	var offered_actions := []
	if MetaDirector != null and MetaDirector.has_method("offers"):
		offered_actions = MetaDirector.offers(stage)
	last_offered_actions = offered_actions.duplicate()  # the ctx's, not last turn's

	var ctx := build_turn_context(player_text, _turn_events)

	# Step 2: Prompt assembly via PromptBuilder
	var prompt_res: Dictionary = PromptBuilder.build(ctx)
	var messages: Array = prompt_res.get("messages", [])

	# Step 3: Schema assembly via TurnSchema. The property order is the
	# docs/02 §3 order — music/fx before beats — because llama.cpp emits in
	# schema order and the face/sound must change exactly when the line starts
	# (docs/02 §1, review CODE-3).
	var schema_ctx := ctx.duplicate()
	schema_ctx["property_order"] = TurnSchema.DOCS_02_PROPERTY_ORDER
	var schema: Dictionary = TurnSchema.build_turn_schema(schema_ctx, offered_actions)
	_current_prompt = messages.duplicate(true)
	_current_schema = schema.duplicate(true)

	# Step 4: Sampling and steering dose (docs/02 §9). The three sampling columns
	# come straight from the data row via TurnContext (P2.05); this file keeps no
	# copy of the table or its defaults, so a retune is a data edit only.
	var sampling_spec := sampling_spec(stage)
	var sampling_dict := TurnContext.request_sampling(stage)

	# Steering owns the dose once it lands (docs/06 §4). Until then the table's
	# docs/02 §9 dose column is the source, because the merged P1.09 retry path
	# pins it (`DirectorFallbackTest` asserts the stage-1 base 2.5 + retry -2.0
	# reaches the request). CODE-7's "leave dose empty" would drop that
	# observable: the facade only fills from set_dose(), which nothing calls
	# yet. The transmission gap (LlamaServerBackend ignores request.dose —
	# control vectors are a server launch flag, docs/06 §4) is P1.02/P2.02 work.
	var dose_dict := {}
	if Steering != null and Steering.has_method("dose_for"):
		dose_dict = Steering.dose_for(ctx)
	if dose_dict.is_empty() and float(sampling_spec.get("dose", 0.0)) > 0.0:
		dose_dict = {"base": float(sampling_spec.get("dose", 0.0))}
	# docs/02 §7 empty-say retry: dose -2 applies to whichever dose source won
	if _dose_offset != 0.0:
		for vector: Variant in dose_dict:
			var name := str(vector)
			dose_dict[name] = maxf(0.0, float(dose_dict[name]) + _dose_offset)
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
			# One scan per beat: Safety holds the streaming state (docs/02 §8).
			# `beat` marks a streamed-beat scan, so the filter can tell it from
			# a whole-text scan (the transcript redactor uses filter_text).
			_safety.begin_beat({"stage": int(GameState.stage), "beat": true})
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
			# Raw text feeds the transcript and the §7 broken-stream fallback;
			# only the scanned text is displayed (docs/02 §4 step 5, §8).
			_streamed_say_text += raw_say
			var filtered_say := _safety.feed(raw_say)
			beat_say_chunk.emit(b_idx, filtered_say)
			if chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
				chat_ui_node.say_chunk(b_idx, filtered_say)

		"error":
			# docs/02 §7: the partial `say` already streamed stays on screen —
			# the parser flushes it before the error, so chunks keep routing.
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
			# The holdback kept a prefix back so no phrase could complete after
			# a partial emission; the beat close is where that tail is safe.
			_flush_say_tail(beat_index)
			if chat_ui_node != null and chat_ui_node.has_method("end_beat"):
				chat_ui_node.end_beat(beat_index)
			_current_beats.append(_current_beat_data.duplicate())
			beat_ended.emit(beat_index, _current_beat_data)


func _flush_say_tail(beat_index: int) -> void:
	var tail := _safety.finish()
	if tail.is_empty():
		return
	beat_say_chunk.emit(beat_index, tail)
	if chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
		chat_ui_node.say_chunk(beat_index, tail)


## docs/03 §3: resolve the beat exactly once. `SpriteResolver` is stateful (the
## anti-repeat window), so resolving here AND again inside
## `Character.set_feeling()` double-counts every beat and can show a different
## sprite than the packet logged (review CODE-4). The packet is passed down
## instead, and the resolver stays the only `beat_resolved` emitter.
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
	# Flags reach the resolver so the flag-gated sprite pool (docs/10 §3) can
	# fire from this route (review CODE-4/DES-6).
	var flags: Dictionary = GameState.flags

	var packet: Dictionary = SpriteResolver.resolve_beat(feeling, intensity, stage, path, flags)
	beat_resolved.emit(packet)
	var sprite_id := StringName(str(packet.get("sprite", "")))
	if sprite_id != &"":
		# docs/04 §3: AudioDirector tracks sprites 21/30 for knife_draw.
		if AudioDirector != null and AudioDirector.has_method("note_sprite"):
			AudioDirector.note_sprite(sprite_id)

	if character_node != null and character_node.has_method("apply_beat"):
		character_node.apply_beat(packet)
	elif character_node != null and character_node.has_method("set_feeling"):
		character_node.set_feeling(feeling, intensity, stage, path, flags)
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
	var recovered := TurnFallback.broken_stream_turn(
		_streamed_say_text, stage, GameState.player_name, _current_turn_data
	)
	var fallback_say := str(recovered.get("_say", "..."))
	var target_sprite := str(recovered.get("_sprite", "00"))
	recovered.erase("_say")
	recovered.erase("_sprite")
	_current_turn_data = recovered
	# Route sprite 29 (stage >= 3) or 00; glitch fx only exists from stage 3
	if not target_sprite.is_empty():
		if character_node != null and character_node.has_method("set_sprite"):
			character_node.set_sprite(target_sprite)
	var fallback_fx := str(_current_turn_data.get("fx", "none"))
	if fallback_fx != "none" and FX != null and FX.has_method("trigger"):
		FX.trigger(fallback_fx, stage)

	# Overwrite the beat whose partial say is already queued on screen — a
	# second say_chunk would duplicate the partial text. The Director owns the
	# scan, so the text is filtered here, before the UI (review CODE-1).
	_show_replacement_beat(0, fallback_say)
	beat_ended.emit(0, (_current_turn_data["beats"] as Array)[0])
	_close_turn_success(_current_turn_data)


func _handle_empty_say_fallback() -> void:
	_current_turn_data = TurnFallback.empty_say_turn(_current_turn_data)
	_current_turn_data.erase("_sprite")
	var say_text := str(_current_turn_data.get("_say", "…"))
	_current_turn_data.erase("_say")
	# Show "…" (docs/02 §7: stage >= 3 gets a stuck typing indicator).
	# The player can't respond to nothing, so the turn still closes cleanly.
	# replace_beat is the single text path — the beat is rewritten, not
	# appended, so no second chunk is emitted for the same literal.
	_show_replacement_beat(0, say_text)
	beat_ended.emit(0, (_current_turn_data["beats"] as Array)[0])
	_close_turn_success(_current_turn_data)


## Rewrite an already-queued beat with scanned text: the scan runs here, the UI
## seam is never given a second filter to apply (review CODE-1).
func _show_replacement_beat(beat_index: int, text: String) -> void:
	var scanned := _safety.filter_text(text, {"stage": int(GameState.stage)})
	if chat_ui_node != null and chat_ui_node.has_method("replace_beat"):
		chat_ui_node.replace_beat(beat_index, scanned)
	elif chat_ui_node != null and chat_ui_node.has_method("say_chunk"):
		chat_ui_node.say_chunk(beat_index, scanned)


func _apply_turn_repairs_and_deflections(turn_data: Dictionary, stage: int) -> void:
	var result := TurnFallback.repair_beats(
		turn_data.get("beats", []), stage, GameState.player_name, last_player_inputs
	)
	turn_data["beats"] = result["beats"]
	if int(result["deflections"]) > 0:
		GameState.bump_profile(&"meta_curiosity", int(result["deflections"]))
	if bool(result["text_bleed"]) and FX != null and FX.has_method("trigger"):
		FX.trigger("text_bleed", stage)
	# The streamed chunks are already queued on screen; a repaired beat must
	# rewrite what is queued, or the screen keeps the raw line. Scanned here.
	var changed: Dictionary = result["changed"]
	for beat_index: Variant in changed:
		_show_replacement_beat(int(beat_index), str(changed[beat_index]))


func _close_turn_success(turn_data: Dictionary) -> void:
	var stage := int(GameState.stage)

	# Validate turn semantics (docs/02 §7). The offered actions are passed so a
	# legitimately offered `action` is not reported as unoffered (review CODE-6);
	# violations stay warnings until P1.09 gates them hard.
	var val_errors: Array[String] = TurnSchema.validate_turn(turn_data, stage, last_offered_actions)
	if not val_errors.is_empty():
		push_warning("Director: semantic validation warnings: %s" % str(val_errors))

	# Auto-fill check (docs/02 §5: If model chose no cue/fx for 4 turns and intensity >= 2 -> mild one)
	_handle_auto_fill(turn_data, stage)

	last_turn_data = turn_data.duplicate(true)
	last_read = str(turn_data.get("read", ""))
	last_inner = str(turn_data.get("inner", ""))

	# Step 7: Apply to GameState. The advance comes FIRST: the per-turn mood
	# budget inside GameState._apply_mood_meter() is keyed on GameState.turn, so
	# the state of a turn lands under that turn's index and the next turn opens
	# with a cleared budget (P1.04/P1.29 handoff call order, review CODE-12).
	GameState.advance_turn()
	GameState.apply_slow_burn()

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
	_safety.finish()


## docs/02 §5 auto-fill: after 4 turns with no cue/fx and a beat at intensity
## >= 2, the Director adds a mild one. Both picks are engine-owned, so they must
## not be eaten by the model's cue budget: `AudioDirector.play_engine_cue` is the
## un-budgeted engine path (docs/04 §3), and the streak only resets when the mild
## fill actually landed (review CODE-11).
func _handle_auto_fill(turn_data: Dictionary, stage: int) -> void:
	if stage > 1:
		quiet_turn_streak = 0
		return

	var had_cue := false
	var max_intensity := 0
	var beats: Array = turn_data.get("beats", [])
	for b: Variant in beats:
		if not (b is Dictionary):
			continue
		if str(b.get("cue", "none")) != "none" and str(b.get("cue", "")) != "":
			had_cue = true
		# Only a real integer intensity counts toward the docs/02 §5 gate
		# (review DES-3): a malformed beat must not trip it by accident.
		if typeof(b.get("intensity")) == TYPE_INT:
			max_intensity = maxi(max_intensity, int(b["intensity"]))

	var had_fx := str(turn_data.get("fx", "none")) != "none" and str(turn_data.get("fx", "")) != ""

	if had_cue or had_fx:
		quiet_turn_streak = 0
		return

	quiet_turn_streak += 1
	if quiet_turn_streak < 4 or max_intensity < 2:
		return

	var filled := false
	if AudioDirector != null and AudioDirector.has_method("play_engine_cue"):
		filled = AudioDirector.play_engine_cue(&"giggle") or filled
	elif AudioDirector != null and AudioDirector.has_method("play_cue"):
		filled = AudioDirector.play_cue(&"giggle") or filled
	if FX != null and FX.has_method("trigger"):
		filled = FX.trigger("blush_glow", stage) or filled
	# Keep counting while nothing could be played, so the mild fill is not
	# spent on a silent turn and then skipped for another four.
	if filled:
		quiet_turn_streak = 0


func _on_llm_failed(err_dict: Dictionary) -> void:
	if not _turn_in_flight:
		return
	var code := str(err_dict.get("code", "unknown_error"))
	var msg := str(err_dict.get("message", "generation failed"))
	# The record is built from the turn-scoped context, so it is written before
	# the teardown clears it (P1.18 contract: one JSONL line per turn).
	_log_turn_record("failed", code, msg)
	_abort_turn(code, msg)


func _on_llm_cancelled() -> void:
	if not _turn_in_flight:
		return
	_log_turn_record("cancelled")
	_teardown_turn()
	if chat_ui_node != null and chat_ui_node.has_method("abort_turn"):
		chat_ui_node.abort_turn()
	turn_cancelled.emit(_turn_index)


func cancel() -> void:
	if _active_stream != null:
		_active_stream.cancel()
	elif _turn_in_flight:
		_on_llm_cancelled()


func _abort_turn(error_code: String, error_message: String) -> void:
	_teardown_turn()
	if chat_ui_node != null and chat_ui_node.has_method("abort_turn"):
		chat_ui_node.abort_turn()
	turn_failed.emit(_turn_index, error_code, error_message)


## One teardown for every exit (completed / failed / cancelled): the stream, the
## parser and the turn-scoped state must not survive into the next turn, or a
## later cancel() would act on a terminal stream and a stale `_current_turn_data`
## would leak into the next close (review CODE-9).
##
## The player's unanswered line stays in `history` and `last_player_inputs`: the
## player did say it, the model simply never answered, and the docs/02 §6 rule-1
## window is about what the player actually typed. AudioDirector/FX keep their
## per-turn counters — the turn *was* opened, so the budget it accrued is spent;
## rewinding it would let a retry loop mint cue tokens.
func _teardown_turn() -> void:
	_turn_in_flight = false
	_active_stream = null
	_parser = null
	_current_turn_data.clear()
	_current_beats.clear()
	_current_beat_index = -1
	_current_beat_data.clear()
	_safety.finish()
	_clear_turn_context()


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

	# Reply boundary (P1.19 r5 CODE-23/SAF-17): a replayed turn re-streams a
	# model utterance through the same say path, so it must cut the cross-beat
	# carry exactly like `_start_turn` does. Without this the first replayed
	# beat could be matched together with the previous reply's displayed tail.
	_safety.end_utterance()

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
## The player's own line. The filter owns the decision when it implements an
## input check; the Director keeps no local phrase list (review CODE-1/DES-7).
func filter_player_input(input_text: String) -> bool:
	return _safety.check_input(input_text)


## Scan one whole model line (a repaired beat, an inner line) and return only
## what is safe to display. Streaming say text goes through the beat boundary
## calls instead, so Safety's holdback state stays consistent.
func filter_output(text_chunk: String) -> String:
	return _safety.filter_text(text_chunk, {"stage": int(GameState.stage)})


## -----------------------------------------------------------------------------
## Memory Validation (docs/02 §6)
## -----------------------------------------------------------------------------
## The three docs/02 §6 rules live in MemoryRules; this is the Director-facing
## name the suite and P1.09's follow-ups call.
static func validate_memory(
	candidate: String, player_inputs: Array[String], existing_memories: Array[String]
) -> bool:
	return MemoryRules.validate(candidate, player_inputs, existing_memories)
