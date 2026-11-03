extends Control
## Title — main title screen (P1.14).
## Displays the title, subtitle, and menu options:
## New Game, Continue, Settings, Quit.
## Supports keyboard navigation (Up/Down/Tab/Enter) and Esc handling.

signal new_game_requested
signal continue_requested
signal settings_requested
signal quit_requested

const NEW_GAME_SCENE_PATH := "res://scenes/NewGame.tscn"

var scene_change_enabled := true
var _config := {}
@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var subtitle_label: Label = $Margin/VBox/SubtitleLabel
@onready var new_game_button: Button = $Margin/VBox/MenuContainer/NewGameButton
@onready var continue_button: Button = $Margin/VBox/MenuContainer/ContinueButton
@onready var settings_button: Button = $Margin/VBox/MenuContainer/SettingsButton
@onready var quit_button: Button = $Margin/VBox/MenuContainer/QuitButton


func _ready() -> void:
	_config = UiConfig.load_config()
	apply_config(_config.get("title", {}))

	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Focus New Game by default for keyboard play
	new_game_button.grab_focus()


func apply_config(cfg: Dictionary) -> void:
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
	if quit_button != null and cfg.has("btn_quit"):
		quit_button.text = str(cfg["btn_quit"])


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


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
	get_tree().quit()
