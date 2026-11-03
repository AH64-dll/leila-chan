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
signal beat_played(beat_index: int, packet: Dictionary)
signal opening_beats_finished
signal player_turn_submitted(text: String)
signal turn_completed(turn_index: int)
signal pause_requested

const DEFAULT_SCENARIO := "res://data/scenarios/D02_cafe.json"

@export var scenario_path: String = DEFAULT_SCENARIO
@export var stage: int = 0
@export var path_name: String = ""
@export var player_name: String = "Senpai"
@export var auto_start: bool = false
@export var reduced_motion: bool = false
@export var photosensitive: bool = false
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

	if chat_ui != null:
		if not chat_ui.player_turn_sent.is_connected(_on_player_turn_sent):
			chat_ui.player_turn_sent.connect(_on_player_turn_sent)
		if not chat_ui.turn_displayed.is_connected(_on_turn_displayed):
			chat_ui.turn_displayed.connect(_on_turn_displayed)
		if not chat_ui.pause_requested.is_connected(_on_pause_requested):
			chat_ui.pause_requested.connect(_on_pause_requested)
		var safety_node: Node = get_node_or_null("/root/Safety")
		if safety_node != null and safety_node.has_method("scan"):
			chat_ui.text_filter = Callable(safety_node, "scan")
	if character != null:
		if not character.twitch_fired.is_connected(_on_character_twitch_fired):
			character.twitch_fired.connect(_on_character_twitch_fired)
		character.set_reduced_motion(reduced_motion)
	if fx != null:
		if "reduced_motion" in fx:
			fx.reduced_motion = reduced_motion
		if "photosensitive" in fx:
			fx.photosensitive = photosensitive

	if _scenario.is_empty():
		load_scenario(scenario_path)

	if auto_start:
		start_date.call_deferred()


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
	if _scenario.is_empty():
		if not load_scenario(scenario_path):
			return

	if SpriteResolver != null:
		SpriteResolver.reset_repeat()

	var music_id := StringName(String(_scenario.get("music", "calm")))
	if AudioDirector != null:
		AudioDirector.request_music(music_id)

	_current_turn = 0
	date_started.emit()
	play_opening_beats()


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

	for i: int in range(beats.size()):
		var beat: Dictionary = beats[i]
		if AudioDirector != null:
			AudioDirector.set_stage(stage)
			AudioDirector.begin_turn()
		var feeling := String(beat.get("feeling", "neutral"))
		var intensity := int(beat.get("intensity", 1))
		var packet: Dictionary = {}
		if SpriteResolver != null:
			packet = SpriteResolver.resolve_beat(feeling, intensity, stage, path_name)
		if character != null:
			character.set_feeling(feeling, intensity, stage, path_name)

		var sprite_id := StringName(String(packet.get("sprite", "")))
		if AudioDirector != null:
			if sprite_id != &"":
				AudioDirector.note_sprite(sprite_id)
			var cue := StringName(String(beat.get("cue", "none")))
			if cue != &"none" and cue != &"":
				AudioDirector.play_cue(cue)

		if chat_ui != null:
			chat_ui.begin_beat(i)
			chat_ui.say_chunk(i, String(beat.get("say", "")))
			chat_ui.end_beat(i)

		beat_played.emit(i, packet)

	if chat_ui != null:
		chat_ui.end_turn()


func is_opening_finished() -> bool:
	return _opening_finished


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if character != null:
		character.set_reduced_motion(enabled)
	if text_box != null:
		text_box.set_instant(enabled)
	if fx != null and "reduced_motion" in fx:
		fx.reduced_motion = enabled


func set_photosensitive(enabled: bool) -> void:
	photosensitive = enabled
	if fx != null and "photosensitive" in fx:
		fx.photosensitive = enabled


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


func _on_player_turn_sent(text: String) -> void:
	_current_turn += 1
	player_turn_submitted.emit(text)


func _on_turn_displayed() -> void:
	if _opening_in_progress:
		_opening_in_progress = false
		_opening_finished = true
		opening_beats_finished.emit()
	turn_completed.emit(_current_turn)


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
