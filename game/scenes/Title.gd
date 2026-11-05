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

## docs/05 §1.1 M06/M07's opacity: the portrait is a bust crop of a stage
## sprite, scaled to this width, pinned bottom-right under the menu.
const META_PORTRAIT_WIDTH := 300.0
const META_SPRITE_SCALE := 2.0  # casting.art.scale: the display art is x2

var scene_change_enabled := true
## Test seam: a suite cannot hover a Control headlessly, so it sets this instead
## of a mouse position; the unlock timer is otherwise driven by hover or focus.
var meta_hover_override := false
var _config := {}
var _title_cfg := {}
## docs/05 §1.1–§1.2 M02/M06/M07 (P3.09): the mounted meta-effect module, the
## New Game lock timer, and the portrait whose crop the eyes shift.
var _meta: Node = null
var _meta_lock_left := 0.0
var _meta_portrait: TextureRect
var _meta_atlas: AtlasTexture
var _meta_base_region := Rect2()
var _meta_eyes_px := 0
var _meta_eyes_follow := false
var _meta_note: Label
@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var subtitle_label: Label = $Margin/VBox/SubtitleLabel
@onready var new_game_button: Button = $Margin/VBox/MenuContainer/NewGameButton
@onready var continue_button: Button = $Margin/VBox/MenuContainer/ContinueButton
@onready var photosensitive_button: Button = $Margin/VBox/MenuContainer/PhotosensitiveButton
@onready var photosensitive_notice: Label = $Margin/VBox/MenuContainer/PhotosensitiveNotice
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
	# docs/05 §1.1 M02/M06/M07: after the focus, because M07 can lock the row
	# and the focus then has to move somewhere the player can still act.
	_apply_meta_events()


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
	if photosensitive_notice != null:
		var notice_key := (
			"notice_photosensitive_active" if Settings.photosensitive else "notice_photosensitive"
		)
		var notice_fallback: String = defaults.get(notice_key, "")
		photosensitive_notice.text = String(_title_cfg.get(notice_key, notice_fallback))


## docs/05 §1.1 M06/M07: the title screen is where she gets a body and where
## New Game can be taken away. Everything is decided by the P3.09 module
## (`title_state()`); this scene only draws it, so the rules live in one place
## and stay testable without a menu.
func _apply_meta_events() -> void:
	_meta = MetaEventsM01.find(MetaDirector)
	if _meta == null:
		return
	var view: Dictionary = _meta.call("title_state")
	_meta_eyes_px = int(view.get("eyes_offset_px", 2))
	_apply_meta_title(view)
	_apply_meta_portrait(view)
	_apply_meta_lock(view)
	_apply_meta_note(view)


## M06 stage 5: the title text is her name.
func _apply_meta_title(view: Dictionary) -> void:
	var text := str(view.get("title_text", ""))
	if not text.is_empty() and title_label != null:
		title_label.text = text


## M06: "Title sprite changes with stage; at 3+ her eyes follow the cursor (bust
## crop + offset)". The crop is the casting `bust_crop_native` rect in display
## (x2) pixels; the follow is a 2 px shift of that rect, disabled by reduced
## motion (a moving image is motion).
func _apply_meta_portrait(view: Dictionary) -> void:
	var sprite := str(view.get("sprite", ""))
	if sprite.is_empty():
		return
	var path := SpriteResolver.sprite_texture_path(sprite)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Title: no title portrait for sprite %s" % sprite)
		return
	var texture := load(path) as Texture2D
	if texture == null:
		return
	_meta_base_region = _bust_region(sprite)
	_meta_atlas = AtlasTexture.new()
	_meta_atlas.atlas = texture
	_meta_atlas.region = _meta_base_region
	_meta_portrait = TextureRect.new()
	_meta_portrait.name = "MetaPortrait"
	_meta_portrait.texture = _meta_atlas
	_meta_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_meta_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_meta_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ratio := _meta_base_region.size.y / maxf(1.0, _meta_base_region.size.x)
	_meta_portrait.custom_minimum_size = Vector2(META_PORTRAIT_WIDTH, META_PORTRAIT_WIDTH * ratio)
	_meta_portrait.size = _meta_portrait.custom_minimum_size
	_meta_portrait.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_meta_portrait.position = Vector2(
		size.x - META_PORTRAIT_WIDTH - 24.0, size.y - _meta_portrait.size.y
	)
	add_child(_meta_portrait)
	move_child(_meta_portrait, 1)
	_meta_eyes_follow = bool(view.get("eyes_follow", false)) and not _reduced_motion()
	set_process(true)


## casting `bust_crop_native` is [left, top, right, bottom] in native px; the
## display textures are x2, so the region is the same rect doubled.
func _bust_region(sprite: String) -> Rect2:
	var sprites: Dictionary = {}
	var casting: Variant = SpriteResolver.get("casting")
	if casting is Dictionary:
		var rows: Variant = (casting as Dictionary).get("sprites", {})
		if rows is Dictionary:
			sprites = rows
	var row: Variant = sprites.get(sprite, {})
	if not row is Dictionary:
		return Rect2(208, 40, 352, 400)
	var crop: Variant = (row as Dictionary).get("bust_crop_native", [104, 20, 280, 220])
	if not crop is Array or (crop as Array).size() < 4:
		return Rect2(208, 40, 352, 400)
	var box := crop as Array
	var left := float(box[0]) * META_SPRITE_SCALE
	var top := float(box[1]) * META_SPRITE_SCALE
	var right := float(box[2]) * META_SPRITE_SCALE
	var bottom := float(box[3]) * META_SPRITE_SCALE
	return Rect2(left, top, maxf(1.0, right - left), maxf(1.0, bottom - top))


## M07: "New Game is greyed out: 'Why would you want a new one?' Hover for 5 s
## and it becomes clickable." Focus counts as hover, so keyboard play can unlock
## it too; Continue/Settings/Quit stay live the whole time.
func _apply_meta_lock(view: Dictionary) -> void:
	if not bool(view.get("new_game_locked", false)):
		return
	_meta_lock_left = maxf(0.1, float(view.get("unlock_seconds", 5.0)))
	new_game_button.disabled = true
	new_game_button.tooltip_text = str(view.get("lock_line", ""))
	if new_game_button.has_focus():
		if not continue_button.disabled:
			continue_button.grab_focus()
		elif not quit_button.disabled:
			quit_button.grab_focus()


## M02's line ("You came back. I closed it…") or M07's question, under the
## subtitle. Authored text, still scanned: the safety path must stay single for
## every string the game displays.
func _apply_meta_note(view: Dictionary) -> void:
	var line := str(view.get("line", ""))
	var lock_line := str(view.get("lock_line", ""))
	var text := line if not line.is_empty() else lock_line
	var subtitle := str(view.get("subtitle", ""))
	if not subtitle.is_empty() and subtitle_label != null:
		subtitle_label.text = subtitle
	if text.is_empty():
		return
	_meta_note = Label.new()
	_meta_note.name = "MetaLine"
	_meta_note.text = _scan_title_text(text)
	_meta_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_note.add_theme_font_size_override("font_size", 13)
	_meta_note.add_theme_color_override("font_color", Color(0.86, 0.3, 0.34))
	var column := subtitle_label.get_parent()
	if column != null:
		column.add_child(_meta_note)
		column.move_child(_meta_note, subtitle_label.get_index() + 1)


func _scan_title_text(text: String) -> String:
	var safety := get_node_or_null("/root/Safety")
	if safety == null or not safety.has_method("filter_text"):
		return SaySafetyGate.redact(text)
	var res: Variant = safety.call("filter_text", text, {"stage": int(GameState.stage)})
	if res is Dictionary and (res as Dictionary).has("text"):
		return str((res as Dictionary)["text"])
	return SaySafetyGate.redact(text)


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and bool(settings.get("reduced_motion"))


## The meta timeline: M06's eye shift and M07's 5 s unlock. One tick, so a suite
## can advance the hover by hand (`advance_meta`).
func _process(delta: float) -> void:
	_tick_meta(delta)


## Test seam: step the title's meta timeline without waiting in real time.
func advance_meta(seconds: float) -> void:
	_tick_meta(seconds)


func _tick_meta(delta: float) -> void:
	if _meta_eyes_follow and _meta_atlas != null and _meta_portrait != null:
		_shift_eyes()
	if _meta_lock_left <= 0.0:
		return
	if not (meta_hover_override or new_game_button.is_hovered() or new_game_button.has_focus()):
		return
	_meta_lock_left = maxf(0.0, _meta_lock_left - delta)
	if _meta_lock_left <= 0.0:
		_unlock_new_game()


## The crop follows the cursor by `eyes_offset_px` native px: the face stays put
## in the panel while the frame moves, which is what reads as eyes looking.
func _shift_eyes() -> void:
	var rect := _meta_portrait.get_global_rect()
	var middle := rect.position + rect.size * 0.5
	var away := get_global_mouse_position() - middle
	var limit := _meta_eyes_px * META_SPRITE_SCALE
	var step := Vector2.ZERO
	if absf(away.x) > 6.0:
		step.x = signf(away.x) * limit
	if absf(away.y) > 6.0:
		step.y = signf(away.y) * limit * 0.5
	_meta_atlas.region = Rect2(_meta_base_region.position + step, _meta_base_region.size)


func _unlock_new_game() -> void:
	_meta_lock_left = 0.0
	new_game_button.disabled = false
	new_game_button.tooltip_text = ""
	if _meta_note != null:
		_meta_note.text = ""


## docs/05 §0 rule 3: `PauseMenu._input` owns Esc and opens the safe pause
## before this `_unhandled_*` handler ever runs, so a shipping build never
## reaches this path. It stays as the documented fallback for tests and for a
## build without the autoload — do not add a second Esc consumer in `_input`.
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
	# docs/09: one settings surface — the PauseMenu overlay's settings page.
	# The accommodation row above stays the pre-date toggle; this opens the
	# same flag's documented home instead of a second screen.
	if has_node("/root/PauseMenu"):
		get_node("/root/PauseMenu").open_settings()


## The accommodation must be toggleable with keyboard only (Enter on the row,
## same as every other menu item), and it must stick for the session and
## beyond: Settings persists it and cuts a running strobe immediately.
func _on_photosensitive_pressed() -> void:
	Settings.toggle_photosensitive()
	_refresh_photosensitive_button()


func _on_quit_pressed() -> void:
	quit_requested.emit()
	# docs/05 §1.1 M04: this Quit does not raise `close_requested`, so it says
	# how the player left before the tree goes down.
	if _meta != null and _meta.has_method("record_quit"):
		_meta.call("record_quit", "button")
	get_tree().quit()
