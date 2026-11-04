extends Node2D
## Date — the core date scene assembly (docs/07 §2).
##
## Composes:
##   - Background: pixel art café backdrop in the project palette
##   - Character: Character.tscn (sprite stack, camera presets, motions)
##   - ChatUI: ChatUI.tscn (ChatLog, TextBox, InputBox)
##   - FX: Screen effects and shader hooks
##   - Audio: AudioDirector music states and cue playback
##
## Integrates ScenarioLoader for setting, goal, opening beats, and turn bounds.

signal date_started
signal date_ended(reason: String)
signal ending_reached(decision: Dictionary)
signal beat_played(beat_index: int, packet: Dictionary)
signal opening_beats_finished
signal player_turn_submitted(text: String)
signal turn_completed(turn_index: int)
signal pause_requested

const DEFAULT_SCENARIO := "res://data/scenarios/D02_cafe.json"
## docs/01 §1: a finished date hands the loop to the night (P2.19), which runs the
## night checks and opens the next day.
const NIGHT_SCENE_PATH := "res://scenes/Night.tscn"
## docs/01 §7 (P3.16): an `any_time` ending (E14 "Static") can end the run from a
## turn close, before the night. The ending scene renders it.
const ENDING_SCENE_PATH := "res://scenes/Ending.tscn"
## `stage` defaults to "unset" so the scene follows the campaign's stage.
## Every player entry goes through change_scene_to_file, which cannot set an
## export, so an unset stage must mean GameState.stage — otherwise a mid-
## campaign date (day loop, save load) would assert stage 0 and erase the drain
## the player already earned. Dev tools and scene tests pin a value instead.
const STAGE_FROM_GAME_STATE := -1

@export var scenario_path: String = DEFAULT_SCENARIO
@export var stage: int = STAGE_FROM_GAME_STATE
@export var path_name: String = ""
@export var player_name: String = "Senpai"
## P2.22 S1-2: a date starts itself. Every real entry (NewGame, Continue, the
## Night's next-day hand-off) arrives through change_scene_to_file, which cannot
## pass a value in, so a shipped date that waited for a caller never played its
## greeting, never requested its music, never wrote its scene-entry autosave and
## never reached its `end` rule. The flag stays as the seam the dev tools and the
## scene suites use: they host a Date they drive by hand and turn it off before
## adding it to the tree (fx_shot, fx_bench, SaveFlowTest).
@export var auto_start: bool = true
@export var reduced_motion: bool = false
@export var photosensitive: bool = false
## P2.19: the day/night loop. On, the date takes its scenario from the campaign (a
## caller that pins `scenario_path` wins, so dev tools and scene tests keep their
## own scenario) and a finished date routes to the Night scene. Off, the date is a
## single standalone date, as before the loop existed.
var campaign_flow := true
## The NewGame/Title convention: a suite turns the scene change off and inspects
## the scene it built.
var scene_change_enabled := true
var text_box: PanelContainer:
	get:
		return chat_ui.text_box if chat_ui else null

var input_box: LineEdit:
	get:
		return chat_ui.input_box if chat_ui else null

var chat_log: ScrollContainer:
	get:
		return chat_ui.chat_log if chat_ui else null

var _scenario: Dictionary = {}
var _current_turn: int = 0
var _opening_in_progress: bool = false
var _opening_finished: bool = false
## P2.20: the date's own turn counter and "resumed from a save" flag. A resumed
## date keeps the saved turn (the scenario's min/max rules continue instead of
## restarting) and does not replay its greeting.
var _saved_turn: int = 0
var _resumed: bool = false
## start_date() ran once: auto_start defers the same call, so a caller that also
## invokes it (or a second deferred fire) must not replay the opening beats.
var _date_started: bool = false
## P2.19: the date's end is decided once, at the displayed boundary, and routed on
## the next idle frame. `_last_action` is the turn's own `action` (docs/08 §7's
## `end.on_goal` reads it) — the displayed signal does not carry the turn data.
var _date_over: bool = false
var _last_action := "none"
## A save that named its scenario wins over the campaign's pick for that morning.
var _save_named_scenario: bool = false

@onready var background: Sprite2D = $Background
@onready var character: Node2D = $Character
@onready var fx_layer: CanvasLayer = $FXLayer
@onready var fx: Control = $FXLayer/FX
@onready var ui_layer: CanvasLayer = $UILayer
@onready var chat_ui: Control = $UILayer/ChatUI


func _ready() -> void:
	var settings_node: Node = get_node_or_null("/root/Settings")
	if settings_node != null:
		if "photosensitive" in settings_node:
			photosensitive = bool(settings_node.photosensitive)
		if "reduced_motion" in settings_node:
			reduced_motion = bool(settings_node.reduced_motion)

	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node != null and "player_name" in gs_node:
		var gs_name := String(gs_node.player_name).strip_edges()
		if not gs_name.is_empty():
			player_name = gs_name
	if stage == STAGE_FROM_GAME_STATE:
		stage = int(gs_node.stage) if gs_node != null and "stage" in gs_node else 0
	# docs/01 §3: the campaign's stage is GameState's, so a transition must
	# reach the scene that draws her text. The ChatUI re-plans the corruption
	# filter on the next turn; the typing indicator reads the same field.
	if gs_node != null and gs_node.has_signal("stage_changed"):
		if not gs_node.is_connected("stage_changed", _on_game_state_stage_changed):
			gs_node.connect("stage_changed", _on_game_state_stage_changed)
	var pb_node: Node = get_node_or_null("/root/PromptBuilder")
	if pb_node != null and pb_node.has_method("set_player_name"):
		pb_node.set_player_name(player_name)
	if chat_ui != null:
		if chat_ui.has_method("set_player_name"):
			chat_ui.set_player_name(player_name)
		if not chat_ui.player_turn_sent.is_connected(_on_player_turn_sent):
			chat_ui.player_turn_sent.connect(_on_player_turn_sent)
		if not chat_ui.turn_displayed.is_connected(_on_turn_displayed):
			chat_ui.turn_displayed.connect(_on_turn_displayed)
		if not chat_ui.pause_requested.is_connected(_on_pause_requested):
			chat_ui.pause_requested.connect(_on_pause_requested)
		# Safety seam (P1.19 r4 CODE-19): chat_ui.text_filter gets a pass-through,
		# NOT a scanning filter — the Director's SaySafetyGate already scans
		# every streamed reply chunk before ChatUI sees it, and opening beats are
		# scanned in play_opening_beats() below, so a real filter here would scan
		# the same text twice. The old `Callable(Safety, "scan")` wiring was
		# inert: Safety has no `scan` method, so nothing was ever bound. The
		# pass-through also keeps ChatUI's unset-filter warning accurate — it
		# only fires when a driver hands it un-scanned text.
		chat_ui.text_filter = func(chunk: String) -> String: return chunk
		# docs/07 §3.4 corruption stage: the next stage after Safety. The UI
		# owns the streaming session (it holds the word buffer across say_chunk
		# events); the Date owns installing it, exactly as it owns wiring the
		# safety seam above. Null-safe: a UI test may hand-build a ChatUI.
		if chat_ui.corruption == null:
			chat_ui.corruption = CorruptionSession.new()
		chat_ui.reduced_motion = reduced_motion
		# F1 controller wiring (P1 gate-r3 / P2.23): the Director routes every
		# streamed say chunk and the unsafe-input refusal through this node, so
		# the scene that instantiates the ChatUI owns the registration. An
		# autoload-side discovery hook would add a second wiring path for no
		# benefit. `_exit_tree()` clears it so the autoload never holds a freed
		# scene node.
		Director.register_chat_ui(chat_ui)
		# docs/03 §5 / docs/05 M41 inner-voice leak (P2.07): the decision is
		# per turn, and the turn's `inner` is known once it closes.
		# `turn_completed` is the Director's public turn boundary and already
		# carries the validated turn data, so the scene that owns the ChatUI
		# subscribes there instead of adding a second Director → UI seam for
		# one field (the Director sits at gdlint's 1000-line cap).
		if not Director.turn_completed.is_connected(_on_director_turn_completed):
			Director.turn_completed.connect(_on_director_turn_completed)
	# Telemetry scope (P2.09): the input/window detectors only record while a
	# date is the active conversation, so a title-screen resize or a keypress
	# at the menu can never become a turn event. Cleared in _exit_tree().
	_note_telemetry_date(true)
	if character != null:
		if not character.twitch_fired.is_connected(_on_character_twitch_fired):
			character.twitch_fired.connect(_on_character_twitch_fired)
		character.set_reduced_motion(reduced_motion)
		# P2.15 text_bleed: the bleed band starts at the live TextBox edge, so
		# the Character asks this scene for it at fire time (layout-proof).
		if character.has_method("set_bleed_rect_provider"):
			character.set_bleed_rect_provider(_text_bleed_rect)
	# docs/02 §2.3 accessibility and docs/01 §3's stage baseline reach the FX
	# host through the autoload (it owns the gates and the stage lookup);
	# DateFX keeps its own reduced-motion/photosensitive copies just below.
	if FX != null and FX.has_method("set_photosensitive"):
		FX.set_photosensitive(photosensitive)
	if FX != null and FX.has_method("set_stage"):
		FX.set_stage(stage)
	if fx != null:
		if "reduced_motion" in fx:
			fx.reduced_motion = reduced_motion
		if "photosensitive" in fx:
			fx.photosensitive = photosensitive

	# Save seam (P2.20): the scene that instantiates the ChatLog owns its save
	# registration, the same convention as the ChatUI registration above. The
	# log is captured on every autosave; a log loaded from a save waits in
	# SaveSystem until a sink registers, which happens right here.
	# Before the scenario load below: a resumed save names the scenario to open.
	_register_save_seam()
	_resume_from_save()

	if _scenario.is_empty():
		# P2.19: a save names its own scenario; every other entry (New Game, the
		# Night's next-day hand-off) takes today's date from the campaign.
		if _save_named_scenario:
			# P2.20/P2.19: the saved scenario is today's date, so the campaign's
			# bookkeeping must agree — the night's queue is consumed and the
			# date is marked played, exactly as begin_day() would have done.
			if campaign_flow:
				Campaign.new(GameState).resume_day(scenario_path)
		else:
			_apply_campaign_scenario()
		load_scenario(scenario_path)

	if auto_start:
		start_date.call_deferred()


## F1 controller wiring (P2.23): a Date that leaves the tree must not leave the
## Director holding its (soon freed) ChatUI — clear our own registration, and a
## registration that already points at a freed node. Another date's live ChatUI
## is never touched.
func _exit_tree() -> void:
	_note_telemetry_date(false)
	_clear_save_seam()
	# This date's scene layer dies with it (P2.22 S1-3): the Director is an
	# autoload that outlives the scene, so a stale goal would ride into whatever
	# builds the next prompt.
	_clear_director_scene()
	var registered: Variant = Director.chat_ui_node
	if registered == null:
		return
	if not is_instance_valid(registered):
		Director.register_chat_ui(null)
	elif is_instance_valid(chat_ui) and registered == chat_ui:
		Director.register_chat_ui(null)


## P2.20: register this date's scroll-back with SaveSystem. The ChatLog node is
## the log source and sink; the registration is identity-guarded, so a second
## live date's log is never cleared by this one's teardown.
func _register_save_seam() -> void:
	if chat_ui == null or chat_ui.chat_log == null:
		return
	var log_node: Object = chat_ui.chat_log
	(
		SaveSystem
		. register_log_seam(
			log_node,
			Callable(log_node, "get_entries"),
			Callable(log_node, "restore_entries"),
		)
	)


func _clear_save_seam() -> void:
	if chat_ui != null and is_instance_valid(chat_ui.chat_log):
		SaveSystem.clear_log_seam(chat_ui.chat_log)


## P2.20: Continue leaves the saved scene in SaveSystem. The Date is the scene
## that resumes it: the scenario it names wins over the exported default, and
## the date's turn counter comes back with it.
func _resume_from_save() -> void:
	var pending: Dictionary = SaveSystem.pending_scene()
	if pending.is_empty():
		return
	SaveSystem.consume_pending_scene()
	var saved_scenario := String(pending.get("scenario", ""))
	if not saved_scenario.is_empty() and FileAccess.file_exists(saved_scenario):
		scenario_path = saved_scenario
		_save_named_scenario = true
	_saved_turn = int(pending.get("turn", 0))
	# A resumed date skips her greeting only when the restored log already carries
	# it: this scene's entry autosave can land before the opening beats reach the
	# ChatLog (they arrive one drained beat at a time), so an empty saved log means
	# the player quit during the greeting and must see it played.
	var restored_entries := 0
	if chat_log != null and chat_log.has_method("entry_count"):
		restored_entries = int(chat_log.call("entry_count"))
	_resumed = restored_entries > 0


## What a save needs to resume this scene (docs/07 §3.5 "state, memories, log"
## plus the scene the log belongs to).
func _save_scene_data() -> Dictionary:
	return {"scenario": scenario_path, "turn": _current_turn}


## P2.20: one autosave attempt with its outcome surfaced. A refusal is a value,
## not an error — `disabled` is the documented headless/tool switch and `busy`
## means a turn streamed past this call — but the "Continue resumes the date the
## player left" guarantee rides on these writes, so an unexpected miss is a
## warning instead of a silently dropped result.
func _autosave_scene(reason: String) -> void:
	var result := SaveSystem.autosave(SaveSystem.SCENE_DATE, _save_scene_data())
	if bool(result.get("ok", false)):
		return
	if String(result.get("error", "")) == "disabled":
		return
	push_warning("Date: %s autosave skipped — %s" % [reason, String(result.get("message", ""))])


## P2.19 / docs/01 §1: with the day/night loop on, today's scenario comes from the
## campaign's availability rule. A pinned `scenario_path` (dev tools, scene tests)
## and a save's scenario both win — the export's default value is the "let the
## campaign choose" marker, so the shipped Date always asks.
func _apply_campaign_scenario() -> void:
	if not campaign_flow or scenario_path != DEFAULT_SCENARIO:
		return
	var pick: Dictionary = Campaign.new(GameState).begin_day()
	if pick.is_empty():
		push_warning(
			"Date: no scenario is available for day %d; keeping %s" % [GameState.day, scenario_path]
		)
		return
	scenario_path = String(pick.get("path", scenario_path))


## docs/01 §1 + docs/08 §7: a date is over when its scenario says so — `max_turns`
## reached, or her `end_date` action past `min_turns`. The check runs at the
## displayed boundary so the last line is on screen before the night takes over,
## and the route is deferred: a scene change inside the turn close would drop the
## last frame (the P2.20 lesson).
func _check_scenario_end() -> void:
	if _date_over or _scenario.is_empty() or not is_inside_tree():
		return
	var outcome := ScenarioLoader.evaluate_turn_end(_scenario, _current_turn, false, _last_action)
	if not bool(outcome.get("ended", false)):
		return
	_date_over = true
	# The date is over, so its scene layer is too: a listener of `date_ended`
	# (or the idler frame before the night scene) must not find a goal for a date
	# that just finished.
	_clear_director_scene()
	date_ended.emit(String(outcome.get("reason", "")))
	if campaign_flow and scene_change_enabled:
		get_tree().change_scene_to_file.call_deferred(NIGHT_SCENE_PATH)


## docs/01 §7 (P3.16): is an ending due at this turn close? Only the `any_time`
## rows can answer yes here (E14 "Static" before Day 7); the campaign's own last
## night belongs to the Night scene. The route is deferred for the same reason the
## night's is: the turn close is still unwinding.
func _check_ending() -> void:
	if _date_over or not is_inside_tree():
		return
	var decision := Endings.evaluate(GameState.to_dict(), Endings.PHASE_TURN)
	if decision.is_empty():
		return
	_date_over = true
	ending_reached.emit(decision)
	if campaign_flow and scene_change_enabled:
		get_tree().change_scene_to_file.call_deferred(ENDING_SCENE_PATH)


## The P2.09 seam, resolved by path: a Date scene must run in tests and tools
## without the full autoload ring.
func _note_telemetry_date(active: bool) -> void:
	var tel: Node = get_node_or_null("/root/Telemetry")
	if tel != null and tel.has_method("set_date_active"):
		tel.set_date_active(active)


func find_component(component_name: String) -> Node:
	var alias_map: Dictionary = {
		"TextBox": text_box,
		"InputBox": input_box,
		"ChatUI": chat_ui,
		"FX": fx,
		"Background": background,
		"Character": character,
	}
	return alias_map.get(component_name)


func load_scenario(path_or_dict: Variant = DEFAULT_SCENARIO) -> bool:
	var data: Dictionary = {}
	if path_or_dict is Dictionary:
		data = path_or_dict as Dictionary
	elif path_or_dict is String:
		data = ScenarioLoader.load_scenario(path_or_dict as String)

	if data.is_empty():
		push_warning("Date: failed to load scenario data")
		return false

	var validation := ScenarioLoader.validate_scenario(data)
	if not bool(validation.get("ok", false)):
		push_warning("Date: scenario validation failed: %s" % str(validation.get("errors", [])))
		return false

	_scenario = data

	# Wire background
	var bg_id := String(_scenario.get("background", "bg/cafe"))
	var bg_path := "res://assets/%s.png" % bg_id
	if ResourceLoader.exists(bg_path) and background != null:
		background.texture = load(bg_path)
		background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Wire music state
	var music_id := StringName(String(_scenario.get("music", "calm")))
	if AudioDirector != null:
		AudioDirector.set_scene_music(music_id)

	# Wire ambience
	var amb_id := String(_scenario.get("ambience", "none"))
	if amb_id != "none" and not amb_id.is_empty():
		var amb_key := StringName("amb." + amb_id if not amb_id.begins_with("amb.") else amb_id)
		if AudioDirector != null and AudioDirector.has_method("play_system"):
			AudioDirector.play_system(amb_key)
	if chat_ui != null:
		chat_ui.set_stage(stage)
		chat_ui.set_player_name(player_name)
	if AudioDirector != null:
		AudioDirector.set_stage(stage)
	return true


func get_scenario() -> Dictionary:
	return _scenario


func start_date() -> void:
	if _date_started:
		return
	_date_started = true
	if _scenario.is_empty():
		if not load_scenario(scenario_path):
			return

	if SpriteResolver != null:
		SpriteResolver.reset_scene()

	# docs/05 §3 (P3.08): the per-scene meta-event budget starts at the date
	# boundary; the scenario path is the scene's own name in the session log.
	if MetaDirector != null and MetaDirector.has_method("note_scene"):
		MetaDirector.note_scene(scenario_path)

	var music_id := StringName(String(_scenario.get("music", "calm")))
	if AudioDirector != null:
		AudioDirector.request_music(music_id)

	_current_turn = _saved_turn
	_saved_turn = 0
	date_started.emit()
	if _resumed:
		# A resumed date does not replay its greeting: the player already saw
		# it, and the restored log continues from there.
		_resumed = false
		_opening_in_progress = false
		_opening_finished = true
		opening_beats_finished.emit()
	else:
		play_opening_beats()
	# Autosave per scene: the date writes itself as it becomes the live scene,
	# and again after every completed turn (_on_turn_displayed), so Continue
	# resumes the date the player actually left.
	_autosave_scene("scene-entry")


func play_opening_beats() -> void:
	_opening_in_progress = true
	_opening_finished = false

	var beats: Array[Dictionary] = ScenarioLoader.get_opening_beats(_scenario, stage, player_name)
	if beats.is_empty():
		_opening_in_progress = false
		_opening_finished = true
		opening_beats_finished.emit()
		return

	if chat_ui != null:
		chat_ui.begin_turn_wait()

	# GameState.flags carries the beat-level rules the resolver reads (docs/03 §3.2
	# TSUN break / ANCHOR relapse, docs/10 §3's rival_gone) — the Director hands the
	# same dictionary to resolve_beat per turn, so the opening beats must too.
	var flags: Dictionary = {}
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node != null and "flags" in gs_node:
		flags = gs_node.flags

	for i: int in range(beats.size()):
		var beat: Dictionary = beats[i]
		if AudioDirector != null:
			AudioDirector.set_stage(stage)
			AudioDirector.begin_turn()
		var feeling := String(beat.get("feeling", "neutral"))
		var intensity := int(beat.get("intensity", 1))
		var packet: Dictionary = {}
		if SpriteResolver != null:
			packet = SpriteResolver.resolve_beat(feeling, intensity, stage, path_name, flags)
		# Hand the finished packet down: resolving again inside set_feeling() would
		# run the anti-repeat window and the reveal budget twice per beat (the same
		# CODE-4 rule the Director follows).
		if character != null:
			if character.has_method("apply_beat"):
				character.apply_beat(packet)
			else:
				character.set_feeling(feeling, intensity, stage, path_name, flags)

		var sprite_id := StringName(String(packet.get("sprite", "")))
		if AudioDirector != null:
			if sprite_id != &"":
				AudioDirector.note_sprite(sprite_id)
			var cue := StringName(String(beat.get("cue", "none")))
			if cue != &"none" and cue != &"":
				AudioDirector.play_cue(cue)

		if chat_ui != null:
			chat_ui.begin_beat(i)
			chat_ui.say_chunk(i, _scan_opening_say(String(beat.get("say", ""))))
			chat_ui.end_beat(i)

		beat_played.emit(i, packet)

	if chat_ui != null:
		chat_ui.end_turn()


## docs/02 §8: every displayed `say` line passes the Safety scan exactly once.
## Opening beats are authored data, but they are displayed through the same
## `say_chunk` path as model text and can interpolate the player name, so they
## get the same one-shot scan the gate gives model replies — the seam stays
## singular either way (CODE-19). If a build ships without the scan API, the
## beat bars rather than display un-scanned (fail closed).
func _scan_opening_say(say_text: String) -> String:
	var safety_node: Node = get_node_or_null("/root/Safety")
	if safety_node == null or not safety_node.has_method("filter_text"):
		return SaySafetyGate.redact(say_text)
	var res: Variant = safety_node.call("filter_text", say_text, {"stage": stage})
	if res is Dictionary and (res as Dictionary).has("text"):
		return str((res as Dictionary)["text"])
	return str(res)


func is_opening_finished() -> bool:
	return _opening_finished


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if character != null:
		character.set_reduced_motion(enabled)
	if text_box != null:
		text_box.set_instant(enabled)
	if chat_ui != null:
		chat_ui.reduced_motion = enabled
	if fx != null and "reduced_motion" in fx:
		fx.reduced_motion = enabled


## docs/01 §3: a campaign stage transition lands on the UI that draws her
## text. The ChatUI re-plans the corruption filter per turn, so the next turn
## speaks at the new stage; the current reply keeps the stage it was streamed
## at (the model's dose only changes on the next restart, docs/06 §4).
func _on_game_state_stage_changed(_previous: int, current: int) -> void:
	stage = current
	if chat_ui != null:
		chat_ui.set_stage(current)


func set_photosensitive(enabled: bool) -> void:
	photosensitive = enabled
	if fx != null and "photosensitive" in fx:
		fx.photosensitive = enabled
	if FX != null and FX.has_method("set_photosensitive"):
		FX.set_photosensitive(enabled)


func set_instant_text(enabled: bool) -> void:
	if text_box != null:
		text_box.set_instant(enabled)


func reveal_now() -> void:
	if text_box != null:
		text_box.reveal_now()


func play_fx(effect_name: StringName, instant: bool = false) -> void:
	if effect_name == &"none":
		return
	if effect_name == &"zoom_face":
		if character != null:
			character.set_camera("face", instant or reduced_motion)
		return
	if effect_name == &"shake_small":
		if not reduced_motion:
			_shake_camera(2.0, 0.2)
		return
	if effect_name == &"sparkle":
		# P1.11 shader hook; approximated as no-op until P1.11 shader materials land
		return
	if fx != null and fx.has_method("play_effect"):
		fx.play_effect(effect_name)


## text_bleed's band (P2.15): the dialogue box's current rect, in viewport px.
## The Character calls this at fire time, so a resized/re-laid-out box is
## always the one the drips start from. Falls back to the shader's default
## band when this date has no ChatUI yet.
func _text_bleed_rect() -> Rect2:
	var box: Control = text_box
	if box == null:
		return Rect2(Vector2(8.0, 0.55 * 688.0), Vector2(368.0, 0.25 * 688.0))
	return box.get_global_rect()


func _shake_camera(amount: float, duration: float) -> void:
	if character == null:
		return
	var cam: Camera2D = character.get_node_or_null("Camera2D")
	if cam == null:
		return
	var orig_pos := cam.position
	var tween := create_tween()
	tween.tween_property(cam, "position", orig_pos + Vector2(amount, 0), duration * 0.25)
	tween.tween_property(cam, "position", orig_pos - Vector2(amount, 0), duration * 0.25)
	tween.tween_property(cam, "position", orig_pos + Vector2(0, amount * 0.5), duration * 0.25)
	tween.tween_property(cam, "position", orig_pos, duration * 0.25)


## docs/02 §4 step 0: the player's line opens the Director's turn. ChatUI emits
## `player_turn_sent` after it logged the line and locked the input
## (ChatUI.gd `_on_input_submitted`), and this is the Date's only submit point.
## P2.22 S1-1: nothing called `Director.submit_player_input`, so a typed line
## opened no turn in the shipped game — the playtest harness installed its own
## bridge, which is exactly why the gap survived. This is the production seam.
func _on_player_turn_sent(text: String) -> void:
	# The layer and the counter both name the turn this line opens.
	var turn := _current_turn + 1
	# docs/08 §1: the scene layer belongs to this turn. The Director reads
	# `scene_info` while it builds the prompt (`build_turn_context`), so it must
	# land before the submit, never after it.
	_apply_director_scene(turn)
	player_turn_submitted.emit(text)
	# docs/02 §4 step 0: a Safety-refused line opens no turn. Counting it would
	# spend an `events[].at_turn` and walk the date to `max_turns` on refusals
	# alone, so the date's turn count follows the Director's, not the keystroke.
	if Director.submit_player_input(text):
		_current_turn = turn


## docs/08 §1 + §7: a turn's `[scene]` layer — the scenario's goal, its prompt,
## the stage/path variant and that turn's `events` line. The Director owns the
## field (its TurnContext carries it into the prompt); the Date owns the value,
## because it is the only node that knows which scenario, stage and turn this
## prompt is for. P2.22 S1-3: nothing assigned it, so every prompt kept the
## Director's constructor café line and no scenario ever reached the model.
func _apply_director_scene(turn: int) -> void:
	if _scenario.is_empty():
		_clear_director_scene()
		return
	Director.scene_info = ScenarioLoader.resolve_scene(
		_scenario, stage, _scene_path(), turn, player_name
	)


## docs/01 §2: the campaign owns the path. `path_name` is the export a dev tool
## pins when it hosts a Date with no campaign behind it; the live game answers
## from GameState, so the scene layer twists with the path she is on.
func _scene_path() -> String:
	var gs_node: Node = get_node_or_null("/root/GameState")
	if gs_node != null and "path" in gs_node:
		var path_id := String(gs_node.path).strip_edges()
		if not path_id.is_empty():
			return path_id
	return path_name


## No date, no scene layer. A finished date's goal must never reach a later
## prompt, and an empty dictionary is the Director's "no date in progress" state
## (docs/08 §1's scene layer then renders nothing) — never stale, never a café
## this date was not set in.
func _clear_director_scene() -> void:
	if not Director.scene_info.is_empty():
		Director.scene_info = {}


func _on_turn_displayed() -> void:
	if _opening_in_progress:
		_opening_in_progress = false
		_opening_finished = true
		opening_beats_finished.emit()
	turn_completed.emit(_current_turn)
	# P2.20: the scene autosaves as it progresses, so a quit mid-date resumes
	# the log the player actually saw instead of replaying the date. Deferred:
	# `turn_displayed` fires from inside the Director's turn close (ChatUI calls
	# TextBox.end_turn, which can emit all_displayed synchronously), and the
	# Director clears its in-flight flag only after that call returns — every
	# save is refused ("busy") while it is set.
	_autosave_scene.call_deferred("after turn")
	# P2.19: the date's end is decided once her last line is on screen, and routed
	# on an idle frame (the Director may still be unwinding this turn's close).
	# P3.16 asks the ending question first: a run that burns out this turn has no
	# night to reach, and either check sets `_date_over` so only one wins.
	_check_ending.call_deferred()
	_check_scenario_end.call_deferred()


## docs/03 §5 (P2.07): her private thought can surface for a moment. The ChatUI
## owns the decision, the per-turn cap, the Safety scan and the render; the
## scene only hands it the finished turn. `inner` is schema-required
## (docs/02 §3), so a missing key simply means there is nothing to leak.
func _on_director_turn_completed(_turn_index: int, turn_data: Dictionary) -> void:
	# P2.19: the scenario's end rule reads the turn's `action` (docs/08 §7's
	# `end.on_goal`), and this is the only callback that carries it — the displayed
	# boundary that routes to the night does not.
	_last_action = String(turn_data.get("action", "none"))
	if chat_ui == null or not is_instance_valid(chat_ui):
		return
	if not chat_ui.has_method("leak_inner"):
		return
	chat_ui.leak_inner(str(turn_data.get("inner", "")))


func _on_pause_requested() -> void:
	pause_requested.emit()


func _on_character_twitch_fired() -> void:
	play_fx(&"twitch")


func get_player_name() -> String:
	if is_inside_tree() and has_node("/root/GameState"):
		var gs: Node = get_node("/root/GameState")
		if "player_name" in gs and not str(gs.player_name).strip_edges().is_empty():
			return str(gs.player_name).strip_edges()
	if chat_ui and chat_ui.has_method("get_player_name"):
		return String(chat_ui.get_player_name())
	return "Senpai"
