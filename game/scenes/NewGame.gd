extends Control
## NewGame — player name entry and validation scene (P1.14, docs/08 §1.5).
## Enforces name rules: 1–16 chars, letters/spaces/-', Safety scan, empty → "Senpai",
## special reaction for "Leila" (+Fixation). Transitions to Date scene.

signal name_confirmed(player_name: String)
signal validation_failed(error_code: String, message: String)
signal back_requested

const DATE_SCENE_PATH := "res://scenes/Date.tscn"
const TITLE_SCENE_PATH := "res://scenes/Title.tscn"
## Optional injected safety checker for tests or custom moderation.
var safety_checker: Callable = Callable()
## Test seam for the docs/09 opt-in OS username: set directly, "" = resolve
## from Settings (the only reader of `Settings.os_username()` in the game).
var os_username_override: String = ""
var scene_change_enabled := true
var _config := {}
@onready var prompt_label: Label = $Margin/VBox/PromptLabel
@onready var hint_label: Label = $Margin/VBox/HintLabel
@onready var name_input: LineEdit = $Margin/VBox/NameInput
@onready var feedback_label: Label = $Margin/VBox/FeedbackLabel
@onready var confirm_button: Button = $Margin/VBox/ButtonContainer/ConfirmButton
@onready var back_button: Button = $Margin/VBox/ButtonContainer/BackButton


func _ready() -> void:
	_config = UiConfig.load_config()
	apply_config(_config.get("new_game", {}))

	name_input.text_submitted.connect(_on_text_submitted)
	confirm_button.pressed.connect(confirm_name)
	back_button.pressed.connect(_on_back_pressed)

	name_input.grab_focus()


func apply_config(cfg: Dictionary) -> void:
	if prompt_label != null and cfg.has("prompt"):
		prompt_label.text = str(cfg["prompt"])
	if hint_label != null and cfg.has("hint"):
		hint_label.text = str(cfg["hint"])
	if name_input != null:
		if cfg.has("placeholder"):
			name_input.placeholder_text = str(cfg["placeholder"])
		if cfg.has("max_length"):
			name_input.max_length = int(cfg["max_length"])
	if confirm_button != null and cfg.has("btn_confirm"):
		confirm_button.text = str(cfg["btn_confirm"])
	if back_button != null and cfg.has("btn_back"):
		back_button.text = str(cfg["btn_back"])


## docs/05 §0 rule 3: `PauseMenu._input` owns Esc (safe pause) and runs first,
## so a shipping build never reaches this path; it stays as the documented
## fallback for tests and for a build without the autoload.
func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("ui_cancel")
		or (
			event is InputEventKey
			and event.pressed
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		_on_back_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _on_text_submitted(_text: String) -> void:
	confirm_name()


func confirm_name() -> void:
	var raw := name_input.text if name_input != null else ""
	# docs/09 privacy: the OS username reaches the rules ONLY through the
	# opt-in flag — Settings.os_username() itself returns "" when off.
	var opts := {"os_username": _resolved_os_username()}
	var result := PlayerNameRules.validate(raw, safety_checker, opts)

	if not bool(result.get("valid", false)):
		var error_msg := str(result.get("message", ""))
		var err_code := str(result.get("error", ""))
		if feedback_label != null:
			feedback_label.text = error_msg
			feedback_label.modulate = Color(1.0, 0.4, 0.4, 1.0)
		validation_failed.emit(err_code, error_msg)
		return

	var resolved_name := str(result.get("resolved_name", "Senpai"))
	var is_special_leila := bool(result.get("is_special_leila", false))

	# Apply game state updates (docs/08 §1.5)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var shadow_first := ""
	var shadow_names: Array = []
	var stored_stage := 0
	var live_stage := 0
	var run_in_progress := false
	# The stage the shadow-name line gates on (assigned below, before the seal).
	var prev_stage := 0
	# docs/01 §5 T19 "Delete save / start New Game … Stage 3+ only": the ended
	# run's stage, carried out of `begin_new_game` because the live one is gone
	# by the time she can speak. −1 = there was no run to remember.
	var ended_stage := -1
	if tree != null and tree.root != null:
		# docs/08 §1.5 shadow name memory (P3.14): read the ended run's stage
		# and the first name she ever knew BEFORE begin_new_game seals the run
		# — that call records the name being confirmed right now, so reading
		# the shadow first would make the comparison always match.
		if tree.root.has_node("GameState"):
			var gs_node: Node = tree.root.get_node("GameState")
			live_stage = int(gs_node.get("stage"))
			run_in_progress = ShadowStore.has_run(
				int(gs_node.get("day")), int(gs_node.get("turn")), live_stage
			)
		if tree.root.has_node("SaveSystem"):
			var saves_node: Node = tree.root.get_node("SaveSystem")
			# One shadow read serves every value: the first name ever typed,
			# every name she has known, and the stage the last sealed run
			# reached (the only stage a fresh process still knows).
			if saves_node.has_method("shadow_data"):
				var record: Variant = saves_node.call("shadow_data")
				if record is Dictionary:
					shadow_first = str((record as Dictionary).get("first_name", ""))
					var raw_names: Variant = (record as Dictionary).get("names", [])
					if raw_names is Array:
						shadow_names = raw_names
					stored_stage = int((record as Dictionary).get("last_stage", 0))
			elif saves_node.has_method("shadow_first_name"):
				shadow_first = String(saves_node.call("shadow_first_name"))
		# The gate is the run that just ended: its live stage while this
		# process had one, otherwise the stage the shadow sealed.
		# `GameState.stage` is 0 in a fresh process, so reading it alone would
		# silence the quit-and-relaunch flow the shadow save exists for (DES-2).
		prev_stage = live_stage if run_in_progress else stored_stage
		# docs/05 M08: seal the ending run and record this name in the shadow
		# save BEFORE the reset below erases the run's memories and name —
		# this is the one write point, so the shadow only ever learns what a
		# confirmed run and a typed name proved (P3.12).
		if tree.root.has_node("SaveSystem"):
			var saves: Node = tree.root.get_node("SaveSystem")
			if saves.has_method("begin_new_game"):
				var sealed: Variant = saves.call("begin_new_game", resolved_name)
				if sealed is Dictionary and bool((sealed as Dictionary).get("had_run", false)):
					ended_stage = int((sealed as Dictionary).get("ended_stage", -1))

		if tree.root.has_node("GameState"):
			var gs: Node = tree.root.get_node("GameState")
			if gs.has_method("reset"):
				gs.call("reset")
			gs.set("player_name", resolved_name)
			if is_special_leila and gs.has_method("adjust_meter"):
				gs.call("adjust_meter", &"fixation", 5.0)

		if tree.root.has_node("PromptBuilder"):
			var pb: Node = tree.root.get_node("PromptBuilder")
			if pb.has_method("set_player_name"):
				pb.call("set_player_name", resolved_name)

		# P2.20: a New Game is a new session. The Director clears its history,
		# the memory store and the transcript session, so a save loaded before
		# this screen can never carry facts or log lines into the fresh run.
		if tree.root.has_node("Director"):
			var director: Node = tree.root.get_node("Director")
			if director.has_method("reset"):
				director.call("reset")
		# docs/01 §5 T19, AFTER the resets on purpose: this is the note the
		# Director's reset used to swallow, and Telemetry now holds it for the
		# new run's first turn instead of queueing it for a turn that never
		# comes (P3.07 r2 CODE-2).
		if ended_stage >= 0 and tree.root.has_node("Telemetry"):
			var telemetry: Node = tree.root.get_node("Telemetry")
			if telemetry.has_method("note_player_action"):
				telemetry.call(
					"note_player_action",
					"save_gone",
					{"kind": "new_game", "gate_stage": ended_stage}
				)

	# Special-name + shadow feedback (docs/08 §1.5): "That's *my* name…" and
	# "You told me the truth." use her warm pink; the shadow line — "That's not
	# what you were called last time." — only surfaces after a stage-3+ run
	# under a different name and overrides the specials (it is the stronger
	# tell).
	var special_msg := str(result.get("message", ""))
	var shadow_msg := PlayerNameRules.shadow_name_message(
		resolved_name, shadow_first, prev_stage, shadow_names
	)
	var shown_msg := shadow_msg if not shadow_msg.is_empty() else special_msg
	if not shown_msg.is_empty() and feedback_label != null:
		feedback_label.text = shown_msg
		feedback_label.modulate = (
			Color(0.9, 0.45, 0.55, 1.0) if not shadow_msg.is_empty() else Color(1.0, 0.6, 0.8, 1.0)
		)

	name_confirmed.emit(resolved_name)
	if scene_change_enabled:
		get_tree().change_scene_to_file(DATE_SCENE_PATH)


func _on_back_pressed() -> void:
	back_requested.emit()
	if scene_change_enabled:
		get_tree().change_scene_to_file(TITLE_SCENE_PATH)


## docs/09 privacy: the opt-in'd OS username ("" when the flag is off or the
## env carries none). The override exists so tests never depend on the CI
## account's USER.
func _resolved_os_username() -> String:
	if not os_username_override.is_empty():
		return os_username_override
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("os_username"):
		return String(settings.call("os_username"))
	return ""
