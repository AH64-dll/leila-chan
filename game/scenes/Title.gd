extends Control
## Title — main title screen (P1.14).
## Displays the title, subtitle, and menu options:
## New Game, Continue, Photosensitive mode, Settings, Extras, Quit.
## Supports keyboard navigation (Up/Down/Tab/Enter) and Esc handling.
##
## The accessibility row is the player's entry point for the safety
## accommodation of docs/02 §2.3: photosensitive mode must be reachable before
## the first date, because the stage-3 `flicker` cue is the pattern it exists
## for. It writes Settings (which persists the flag and pushes it to FX); the
## P3.13 Settings screen takes the row over.
##
## Extras (P3.16) is the after-a-run gallery: docs/05 §3 puts it after the
## credits, so the row is disabled until the ending log has something to show.

signal new_game_requested
signal continue_requested
signal settings_requested
signal extras_requested
signal quit_requested

const NEW_GAME_SCENE_PATH := "res://scenes/NewGame.tscn"
const DATE_SCENE_PATH := "res://scenes/Date.tscn"
const ENDING_SCENE_PATH := "res://scenes/Ending.tscn"
const EXTRAS_SCENE_PATH := "res://scenes/Extras.tscn"

var scene_change_enabled := true
var _config := {}
var _title_cfg := {}
@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var subtitle_label: Label = $Margin/VBox/SubtitleLabel
@onready var new_game_button: Button = $Margin/VBox/MenuContainer/NewGameButton
@onready var continue_button: Button = $Margin/VBox/MenuContainer/ContinueButton
@onready var photosensitive_button: Button = $Margin/VBox/MenuContainer/PhotosensitiveButton
@onready var settings_button: Button = $Margin/VBox/MenuContainer/SettingsButton
@onready var extras_button: Button = $Margin/VBox/MenuContainer/ExtrasButton
@onready var quit_button: Button = $Margin/VBox/MenuContainer/QuitButton


func _ready() -> void:
	_config = UiConfig.load_config()
	apply_config(_config.get("title", {}))

	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	photosensitive_button.pressed.connect(_on_photosensitive_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	extras_button.pressed.connect(_on_extras_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_refresh_photosensitive_button()
	_refresh_continue()
	_refresh_extras()

	# Focus New Game by default for keyboard play
	new_game_button.grab_focus()


func apply_config(cfg: Dictionary) -> void:
	_title_cfg = cfg
	if title_label != null and cfg.has("game_title"):
		title_label.text = str(cfg["game_title"])
	if subtitle_label != null and cfg.has("subtitle"):
		subtitle_label.text = str(cfg["subtitle"])
	if new_game_button != null and cfg.has("btn_new_game"):
		new_game_button.text = str(cfg["btn_new_game"])
	if continue_button != null and cfg.has("btn_continue"):
		continue_button.text = str(cfg["btn_continue"])
	if settings_button != null and cfg.has("btn_settings"):
		settings_button.text = str(cfg["btn_settings"])
	if extras_button != null and cfg.has("btn_extras"):
		extras_button.text = str(cfg["btn_extras"])
	if quit_button != null and cfg.has("btn_quit"):
		quit_button.text = str(cfg["btn_quit"])
	_refresh_photosensitive_button()


## The row names its own state ("Photosensitive mode: Off") so the player can
## see the accommodation exists before it matters. The strings live in ui.json.
func _refresh_photosensitive_button() -> void:
	if photosensitive_button == null:
		return
	var defaults: Dictionary = UiConfig.DEFAULTS["title"]
	var state_key := "photosensitive_on" if Settings.photosensitive else "photosensitive_off"
	var state_text := String(_title_cfg.get(state_key, defaults[state_key]))
	var label := String(_title_cfg.get("btn_photosensitive", defaults["btn_photosensitive"]))
	photosensitive_button.text = label.format({"state": state_text})


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("ui_cancel")
		or (
			event is InputEventKey
			and event.pressed
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
		)
	):
		_on_esc_pressed()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


func _on_esc_pressed() -> void:
	quit_requested.emit()


func _on_new_game_pressed() -> void:
	new_game_requested.emit()
	if scene_change_enabled:
		get_tree().change_scene_to_file(NEW_GAME_SCENE_PATH)


func _on_continue_pressed() -> void:
	continue_requested.emit()
	# P2.20: Continue resumes the newest readable save. A corrupt or missing save
	# is a warning and an unchanged Title, never a half-loaded game (SaveSystem
	# leaves the state untouched on a failed load).
	var loaded: Dictionary = SaveSystem.load_latest()
	if not bool(loaded.get("ok", false)):
		push_warning("Title: cannot continue — %s" % String(loaded.get("message", "")))
		return
	if scene_change_enabled:
		get_tree().change_scene_to_file(_resume_scene_path())


## P3.16: a save taken on the ending screen is the only one that must not resume
## into a date — the run it belonged to is over. Every other scene id keeps the
## P2.19/P2.20 behaviour (Continue opens the Date, which takes the night's queued
## day from the save's own state).
func _resume_scene_path() -> String:
	var scene := String(SaveSystem.pending_scene().get("id", ""))
	if scene == SaveSystem.SCENE_ENDING:
		return ENDING_SCENE_PATH
	return DATE_SCENE_PATH


## Continue is only offered when a save can actually be read; an absent or
## corrupt save greys the row instead of failing on the click.
func _refresh_continue() -> void:
	if continue_button != null:
		continue_button.disabled = not SaveSystem.has_save()


## docs/05 §3 puts Extras after the credits: before the first ending there is
## nothing in it, so the row is greyed like an unreadable Continue.
func _refresh_extras() -> void:
	if extras_button != null:
		extras_button.disabled = not EndingLog.any_seen()


func _on_extras_pressed() -> void:
	extras_requested.emit()
	if scene_change_enabled:
		get_tree().change_scene_to_file(EXTRAS_SCENE_PATH)


func _on_settings_pressed() -> void:
	settings_requested.emit()


## The accommodation must be toggleable with keyboard only (Enter on the row,
## same as every other menu item), and it must stick for the session and
## beyond: Settings persists it and cuts a running strobe immediately.
func _on_photosensitive_pressed() -> void:
	Settings.toggle_photosensitive()
	_refresh_photosensitive_button()


func _on_quit_pressed() -> void:
	quit_requested.emit()
	get_tree().quit()
