extends Node
## PauseMenu — the docs/05 §0 rule 3 "safe pause": Esc works at any moment,
## including while a meta event owns the screen, because this autoload reads
## `_input` (it runs before every scene's `_unhandled_*`) and pauses the
## whole tree while its overlay stays alive on `PROCESS_MODE_ALWAYS`.
##
## It is also the settings screen of P3.13 — docs/09's one settings surface.
## There is exactly one entry point: the Title row calls `open_settings()`,
## and every Esc opens the pause page whose Settings row leads to the same
## page. `settings.cfg` is written by Settings.gd; this node only calls its
## `set_*` API and reads it back, so a corrupt file still fails closed (the
## gates, the calmer cap and the immersion check live in Settings/Safety).
##
## docs/05 §0 checklist for this node:
##   1. Nothing outside the window / user:// — the overlay is in-game only.
##   2. No real crashes, no network calls — the resources link opens the
##      player's browser via OS.shell_open (docs/01 §4 requires the link).
##   3. Closing always works — the pause page's Quit routes through
##      MetaDirector's close handler, so M01's once-per-session hold and the
##      always-works second press apply verbatim; Esc itself is never held.
##   4. Immersion: Deep stays the documented gate — the selector writes
##      Settings.immersion; default Standard.
##   5. Accessibility fallback — photosensitive and reduced motion are the
##      first rows of the settings page, before anything can strobe.

signal opened  ## The overlay became visible (either page).
signal closed  ## The overlay was dismissed and the tree unpaused.
signal settings_opened  ## The settings page is on screen.

const IMMERSION_LABELS: Array[String] = ["Standard", "Deep"]
const IMMERSION_VALUES: Array[String] = ["standard", "deep"]
const CONTENT_LABELS: Array[String] = ["Not set (safest)", "Calmer mode", "Full"]
const CONTENT_VALUES: Array[String] = ["", "calmer", "full"]

var _config := {}
var _overlay: CanvasLayer
var _dim: ColorRect
var _panel: PanelContainer
var _pause_page: VBoxContainer
var _settings_page: VBoxContainer
var _resume_button: Button
var _back_button: Button
var _photosensitive_button: Button
var _reduced_motion_button: CheckButton
var _calmer_button: CheckButton
var _immersion_option: OptionButton
var _content_option: OptionButton
var _text_speed_slider: HSlider
var _text_speed_label: Label
var _bus_sliders: Dictionary = {}  # bus name -> HSlider
var _dose_row: HBoxContainer
var _open := false
var _was_paused := false
## Where Back on the settings page lands: "pause" re-shows the pause page,
## anything else closes the overlay (the Title entry point).
var _settings_return := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_config = UiConfig.load_config()
	_build_overlay()


## Esc is read in `_input`, not `_unhandled_input`: a meta event that grabs or
## handles input ahead of the scenes must never swallow the panic key
## (docs/05 §0 rule 3). `is_echo` repeats are ignored so holding Esc does not
## strobe the menu.
func _input(event: InputEvent) -> void:
	var pressed := false
	if event.is_action_pressed("ui_cancel"):
		pressed = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		pressed = (
			not key.is_echo() and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE)
		)
	if not pressed:
		return
	toggle()
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## The whole contract in one verb: open → pause + overlay, Esc again → close.
func toggle() -> void:
	if _open:
		close()
	else:
		open_pause()


func open_pause() -> void:
	_open_if_needed()
	_show_page("pause")
	if _resume_button != null:
		_resume_button.grab_focus()


## The one settings surface (docs/09). From Title or a scene Esc comes too
## fast for, Back leaves the game where it was; from the pause page Back
## returns to it.
func open_settings() -> void:
	_settings_return = "pause" if _open else ""
	_open_if_needed()
	_show_page("settings")
	_refresh_settings_rows()
	if _back_button != null:
		_back_button.grab_focus()
	settings_opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_overlay.visible = false
	# Restore the pause state the game was in before Esc — an already-paused
	# screen (a scripted scene, a test) must not be un-paused by the menu.
	get_tree().paused = _was_paused
	closed.emit()


func is_open() -> bool:
	return _open


func showing_settings() -> bool:
	return _open and _settings_page != null and _settings_page.visible


func _open_if_needed() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_overlay.visible = true
	opened.emit()


func _show_page(page: String) -> void:
	if _pause_page != null:
		_pause_page.visible = page == "pause"
	if _settings_page != null:
		_settings_page.visible = page == "settings"


## ── Overlay construction ──────────────────────────────────────────────────
## Built in code, like the rest of game/scenes/ui: the layout mirrors
## Title.tscn's Margin/VBox/MenuContainer idiom; strings come from ui.json
## ("pause" and "settings" sections) with UiConfig.DEFAULTS fallbacks.


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 128
	_overlay.visible = false
	_overlay.name = "PauseMenuOverlay"
	add_child(_overlay)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.02, 0.03, 0.85)
	_overlay.add_child(_dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right"]:
		margin.add_theme_constant_override(side, 24)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	_overlay.add_child(margin)

	_panel = PanelContainer.new()
	margin.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation", 16)
	scroll.add_child(pages)

	_pause_page = _build_pause_page()
	pages.add_child(_pause_page)
	_settings_page = _build_settings_page()
	_settings_page.visible = false
	pages.add_child(_settings_page)


func _cfg(section: String, key: String, fallback: String) -> String:
	var table: Variant = _config.get(section, {})
	if table is Dictionary and table.has(key):
		return str(table[key])
	return fallback


func _build_pause_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = _cfg("pause", "title", "Paused")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	page.add_child(title)

	_resume_button = _menu_button(_cfg("pause", "btn_resume", "Resume"))
	_resume_button.pressed.connect(close)
	page.add_child(_resume_button)

	var settings_button := _menu_button(_cfg("pause", "btn_settings", "Settings"))
	settings_button.pressed.connect(func() -> void: open_settings())
	page.add_child(settings_button)

	var quit_button := _menu_button(_cfg("pause", "btn_quit", "Quit game"))
	quit_button.pressed.connect(_on_quit_pressed)
	page.add_child(quit_button)

	_wire_focus_chain([_resume_button, settings_button, quit_button])
	return page


func _build_settings_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = _cfg("settings", "title", "Settings")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	page.add_child(title)

	# docs/01 §4 + docs/02 §8: the content warning sits above every choice, and
	# the resources link is one row away — never buried.
	var warning := Label.new()
	warning.text = _cfg(
		"settings",
		"content_warning",
		"Content warning: horror themes, obsession and psychological distress."
	)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(warning)

	var resources := _menu_button(_cfg("settings", "btn_resources", "Mental health resources"))
	resources.tooltip_text = _cfg("settings", "resources_url", "")
	resources.pressed.connect(_on_resources_pressed)
	page.add_child(resources)

	page.add_child(HSeparator.new())

	# Accessibility first (docs/05 §0 rule 5): the accommodation that protects
	# the player is the first interactive row.
	_photosensitive_button = _menu_button("Photosensitive mode: Off")
	_photosensitive_button.pressed.connect(
		func() -> void:
			Settings.toggle_photosensitive()
			_refresh_settings_rows()
	)
	page.add_child(_photosensitive_button)

	_reduced_motion_button = CheckButton.new()
	_reduced_motion_button.text = _cfg("settings", "reduced_motion", "Reduced motion")
	_reduced_motion_button.toggled.connect(func(on: bool) -> void: Settings.set_reduced_motion(on))
	page.add_child(_reduced_motion_button)

	_calmer_button = CheckButton.new()
	_calmer_button.text = _cfg("settings", "calmer_mode", "Calmer mode (caps stage at 3)")
	_calmer_button.toggled.connect(func(on: bool) -> void: Settings.set_calmer(on))
	page.add_child(_calmer_button)

	_content_option = _option_row(
		page,
		_cfg("settings", "content_level", "Content level"),
		CONTENT_LABELS,
		func(idx: int) -> void: Settings.set_content_level(CONTENT_VALUES[idx])
	)

	_immersion_option = _option_row(
		page,
		_cfg("settings", "immersion", "Immersion"),
		IMMERSION_LABELS,
		func(idx: int) -> void: Settings.set_immersion(IMMERSION_VALUES[idx])
	)
	var immersion_hint := Label.new()
	immersion_hint.text = _cfg(
		"settings", "immersion_hint", "Deep lets her reach outside the window."
	)
	immersion_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	immersion_hint.add_theme_font_size_override("font_size", 11)
	page.add_child(immersion_hint)

	page.add_child(HSeparator.new())

	_text_speed_label = Label.new()
	_text_speed_label.text = _cfg("settings", "text_speed", "Text speed")
	page.add_child(_text_speed_label)
	_text_speed_slider = HSlider.new()
	_text_speed_slider.min_value = Settings.TEXT_SPEED_MIN
	_text_speed_slider.max_value = Settings.TEXT_SPEED_MAX
	_text_speed_slider.step = 0.05
	_text_speed_slider.value_changed.connect(func(v: float) -> void: Settings.set_text_speed(v))
	page.add_child(_text_speed_slider)

	# docs/04 §1: one slider per exposed bus — AudioDirector.bus_names() decides
	# which exist, so the crossfade internals (MusicA/MusicB) never leak here.
	var audio_label := Label.new()
	audio_label.text = _cfg("settings", "audio", "Volume")
	page.add_child(audio_label)
	for bus: String in Settings.audio_buses():
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = bus
		name_label.custom_minimum_size.x = 80
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = Settings.VOLUME_MIN
		slider.max_value = Settings.VOLUME_MAX
		slider.step = 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bus_name := StringName(bus)
		slider.value_changed.connect(func(v: float) -> void: Settings.set_bus_volume(bus_name, v))
		row.add_child(slider)
		_bus_sliders[bus_name] = slider
		page.add_child(row)

	# docs/05 §1.3 M26 "settings sabotage" anchor: at stage 4 her dose row
	# appears, locked — display only until docs/06 makes it a real slider.
	_dose_row = HBoxContainer.new()
	var dose_label := Label.new()
	dose_label.text = _cfg("settings", "her_dose", "Her dose")
	dose_label.custom_minimum_size.x = 80
	_dose_row.add_child(dose_label)
	var dose_slider := HSlider.new()
	dose_slider.min_value = 0.0
	dose_slider.max_value = 1.0
	dose_slider.value = 0.8
	dose_slider.editable = false
	dose_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dose_row.add_child(dose_slider)
	_dose_row.visible = false
	page.add_child(_dose_row)

	_back_button = _menu_button(_cfg("settings", "btn_back", "Back"))
	_back_button.pressed.connect(_on_settings_back)
	page.add_child(_back_button)
	return page


func _option_row(
	parent: Control, label_text: String, items: Array[String], on_select: Callable
) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 80
	row.add_child(label)
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(on_select)
	row.add_child(option)
	parent.add_child(row)
	return option


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	return button


func _wire_focus_chain(buttons: Array) -> void:
	for i in buttons.size():
		var button: Control = buttons[i]
		var prev: Control = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next: Control = buttons[(i + 1) % buttons.size()]
		button.focus_neighbor_top = button.get_path_to(prev)
		button.focus_neighbor_bottom = button.get_path_to(next)
		button.focus_previous = button.get_path_to(prev)
		button.focus_next = button.get_path_to(next)


## Re-reads Settings into the widgets — the menu must show the player's real
## state (the Title row may have toggled photosensitive while the menu was
## away), and toggles written through Settings land back here too.
func _refresh_settings_rows() -> void:
	var on_text := _cfg("settings", "state_on", "On")
	var off_text := _cfg("settings", "state_off", "Off")
	_photosensitive_button.text = (
		_cfg("settings", "photosensitive", "Photosensitive mode: {state}")
		. format({"state": on_text if Settings.photosensitive else off_text})
	)
	_reduced_motion_button.set_pressed_no_signal(Settings.reduced_motion)
	_calmer_button.set_pressed_no_signal(Settings.is_calmer())
	var content_idx := CONTENT_VALUES.find(Settings.content_level)
	_content_option.select(content_idx if content_idx >= 0 else 0)
	_immersion_option.select(maxi(IMMERSION_VALUES.find(Settings.immersion), 0))
	_text_speed_slider.set_value_no_signal(Settings.text_speed)
	for bus: StringName in _bus_sliders:
		(_bus_sliders[bus] as HSlider).set_value_no_signal(Settings.bus_volume(bus))
	# M26's locked dose row appears only from stage 4 (docs/05 §1.3).
	var stage := 0
	var gs := get_node_or_null("/root/GameState")
	if gs != null and "stage" in gs:
		stage = int(gs.stage)
	_dose_row.visible = stage >= 4


func _on_settings_back() -> void:
	if _settings_return == "pause":
		open_pause()
	else:
		close()


## docs/05 §0 rule 1: Quit goes through the same close path as the window's X,
## so M01 may hold it once and a held request still leaves the second press
## working. If nobody held it, MetaDirector quits for us.
func _on_quit_pressed() -> void:
	var root_window := get_tree().root
	if root_window != null and root_window.has_signal(&"close_requested"):
		root_window.emit_signal(&"close_requested")
	else:
		get_tree().quit()


## docs/01 §4: the resources link opens the player's browser. The URL lives in
## data (ui.json), so a bogus table cannot send the player anywhere the
## content did not name.
func _on_resources_pressed() -> void:
	var url := _cfg("settings", "resources_url", "")
	if url.is_empty():
		push_warning("PauseMenu: no resources_url configured — link does nothing")
		return
	OS.shell_open(url)
