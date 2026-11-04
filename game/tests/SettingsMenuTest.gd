extends GdUnitTestSuite
## P3.13 — the settings screen: every row writes through Settings (persisted
## to user://settings.cfg, docs/07 §3.5) and is honoured by the system that
## reads it — FX for photosensitive, Safety/Steering/Corruption for content
## level and calmer, AudioServer for volumes, the typewriter for text speed,
## docs/05 §0 rule 4 for immersion. One entry point: the Title row and the
## pause page open the same PauseMenu settings page.

const TMP := "user://settings_menu_test.cfg"
const TextBoxScene := preload("res://scenes/ui/TextBox.tscn")
const TitleScene := preload("res://scenes/Title.tscn")


func before_test() -> void:
	_remove_tmp()
	PauseMenu.close()
	get_tree().paused = false
	Settings.settings_path = TMP
	Settings.photosensitive = false
	Settings.reduced_motion = false
	Settings.text_speed = 1.0
	Settings.content_level = ""
	Settings._pre_calmer_level = ""
	Settings.immersion = "standard"
	Settings.bus_volumes.clear()
	FX.photosensitive = false


func after_test() -> void:
	PauseMenu.close()
	get_tree().paused = false
	Settings.settings_path = Settings.PATH
	Settings.photosensitive = false
	Settings.reduced_motion = false
	Settings.text_speed = 1.0
	Settings.content_level = ""
	Settings._pre_calmer_level = ""
	Settings.immersion = "standard"
	Settings.bus_volumes.clear()
	FX.photosensitive = false
	_remove_tmp()


func _remove_tmp() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _config_value(section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(TMP) != OK:
		return null
	return cfg.get_value(section, key, null)


## ── Persistence: every setting lands in the one file ──────────────────────


func test_every_setting_persists_to_settings_cfg() -> void:
	Settings.set_photosensitive(true)
	Settings.set_reduced_motion(true)
	Settings.set_content_level("calmer")
	Settings.set_immersion("deep")
	Settings.set_text_speed(1.5)
	Settings.set_bus_volume(&"Music", 0.5)

	assert_bool(bool(_config_value("accessibility", "photosensitive"))).is_true()
	assert_bool(bool(_config_value("accessibility", "reduced_motion"))).is_true()
	assert_str(String(_config_value("game", "content_level"))).is_equal("calmer")
	assert_str(String(_config_value("game", "immersion"))).is_equal("deep")
	assert_float(float(_config_value("accessibility", "text_speed"))).is_equal(1.5)
	assert_float(float(_config_value("audio", "Music"))).is_equal(0.5)


## A fresh launch reads them all back — and pushes them live.
func test_a_new_session_restores_every_setting() -> void:
	Settings.set_photosensitive(true)
	Settings.set_reduced_motion(true)
	Settings.set_content_level("full")
	Settings.set_immersion("deep")
	Settings.set_text_speed(2.0)
	Settings.set_bus_volume(&"Music", 0.3)

	Settings.photosensitive = false
	Settings.reduced_motion = false
	Settings.content_level = ""
	Settings.immersion = "standard"
	Settings.text_speed = 1.0
	Settings.bus_volumes.clear()
	AudioDirector.set_bus_volume_linear(&"Music", 1.0)
	FX.photosensitive = false

	Settings.load_settings()

	assert_bool(Settings.photosensitive).is_true()
	assert_bool(Settings.reduced_motion).is_true()
	assert_str(Settings.content_level).is_equal("full")
	assert_bool(Settings.is_deep_immersion()).is_true()
	assert_float(Settings.text_speed).is_equal(2.0)
	assert_float(Settings.bus_volume(&"Music")).is_equal_approx(0.3, 0.001)
	assert_float(AudioDirector.bus_volume_linear(&"Music")).is_equal_approx(0.3, 0.001)


## A corrupt enum value in the file must never open a gate (docs/02 §8 /
## docs/05 §0 rule 4 fail closed on anything unknown).
func test_a_corrupt_enum_fails_closed() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "content_level", "everything")
	cfg.set_value("game", "immersion", "godmode")
	cfg.save(TMP)
	Settings.load_settings()
	assert_str(Settings.content_level).is_equal("")
	assert_bool(Settings.is_deep_immersion()).is_false()
	assert_bool(Steering.is_calmer_mode()).is_false()


## ── Honour: the systems that read each setting ────────────────────────────


## Photosensitive reaches the FX host live (P2.15's accommodation, new UI).
func test_photosensitive_row_reaches_the_fx_host() -> void:
	Settings.set_photosensitive(true)
	assert_bool(FX.photosensitive).is_true()
	Settings.set_photosensitive(false)
	assert_bool(FX.photosensitive).is_false()


## Calmer mode is content_level = "calmer" — Steering's stage-3 cap and
## Safety's gate read the same field, so the toggle can never split them.
func test_calmer_mode_caps_the_dose_schedule() -> void:
	Settings.set_calmer(true)
	assert_bool(Settings.is_calmer()).is_true()
	assert_str(Settings.content_level).is_equal("calmer")
	assert_bool(Steering.is_calmer_mode()).is_true()
	# a stage-5 context binds the stage-3 malice at most (docs/02 §8)
	var dose := Steering.dose_for({"stage": 5})
	assert_float(float(dose.get("malice", 12.0))).is_less_equal(
		float(Steering.FALLBACK_TABLE[3]["malice"])
	)
	Settings.set_calmer(false)
	# SAF-1: off restores the level the cap was covering. This profile never
	# chose one, so it lands on the fail-closed "" — never on "full".
	assert_str(Settings.content_level).is_equal("")
	assert_bool(Steering.is_calmer_mode()).is_false()


## SAF-1 / DES-1 (docs/02 §8 D11): `full` is only ever an explicit selection.
## Two clicks on the calmer checkbox from a fresh profile must leave the stage
## ≥ 4 gated categories closed, not grant them.
func test_two_clicks_on_calmer_never_grant_full() -> void:
	assert_str(Settings.content_level).is_equal("")
	assert_bool(Safety._gate_open("threat_to_player", {"stage": 5, "content_level": ""})).is_false()

	Settings.set_calmer(true)
	Settings.set_calmer(false)

	assert_str(Settings.content_level).is_equal("")
	var gate := {"stage": 5, "content_level": Settings.content_level}
	assert_bool(Safety._gate_open("threat_to_player", gate)).is_false()
	assert_bool(Settings.is_calmer()).is_false()


## The off path restores a level the player had explicitly chosen earlier, and
## the memory is persisted — a relaunch in calmer mode still un-caps correctly.
func test_calmer_off_restores_an_explicit_choice() -> void:
	assert_bool(Settings.set_content_level("full")).is_true()
	Settings.set_calmer(true)
	assert_str(Settings.content_level).is_equal("calmer")
	assert_str(String(_config_value("game", "content_level_before_calmer"))).is_equal("full")

	# relaunch: a fresh in-memory state reading the same file
	Settings.content_level = ""
	Settings._pre_calmer_level = ""
	Settings.load_settings()
	assert_str(Settings.content_level).is_equal("calmer")

	Settings.set_calmer(false)
	assert_str(Settings.content_level).is_equal("full")


## The dropdown route remembers the capped level too, so both entry points to
## the same field behave identically (CODE-1's single source of truth).
func test_the_dropdown_route_also_remembers_the_capped_level() -> void:
	Settings.set_content_level("full")
	Settings.set_content_level("calmer")
	Settings.set_calmer(false)
	assert_str(Settings.content_level).is_equal("full")


## Corruption reads the same level: calmer caps the plan at stage 3.
func test_calmer_caps_the_corruption_plan() -> void:
	Settings.set_content_level("calmer")
	var plan := Corruption.plan(5, {"content_level": Settings.content_level})
	assert_int(int(plan.get("effective_stage", 5))).is_less_equal(3)


## Text speed scales the typewriter live — a running reveal obeys the new
## rate, not just the next scene.
func test_text_speed_scales_a_live_typewriter() -> void:
	var text_box: Node = auto_free(TextBoxScene.instantiate())
	add_child(text_box)
	await get_tree().process_frame
	var base := _writer_cps(text_box)
	Settings.set_text_speed(2.0)
	# no ChatUI on screen → the stored scale applies when one arrives
	assert_float(Settings.text_speed).is_equal(2.0)
	text_box.set_speed_scale(Settings.text_speed)
	assert_float(_writer_cps(text_box)).is_equal(base * 2.0)
	# and it persists
	assert_float(float(_config_value("accessibility", "text_speed"))).is_equal(2.0)


func _writer_cps(text_box: Node) -> float:
	_ensure_writer(text_box)
	return text_box._writer.chars_per_second * text_box._writer.speed_scale


func _ensure_writer(text_box: Node) -> void:
	text_box._ensure_parts()


## Volumes: the slider writes the AudioServer bus through AudioDirector and
## refuses buses AudioDirector does not expose (MusicA/MusicB internals).
func test_volume_sliders_drive_the_audio_buses() -> void:
	assert_bool(Settings.set_bus_volume(&"Music", 0.4)).is_true()
	assert_float(AudioDirector.bus_volume_linear(&"Music")).is_equal_approx(0.4, 0.001)
	assert_bool(Settings.set_bus_volume(&"MusicA", 0.4)).is_false()
	AudioDirector.set_bus_volume_linear(&"Music", 1.0)


## Immersion: Deep is opt-in; Standard is the default and a bad value is
## refused (docs/05 §0 rule 4).
func test_immersion_is_opt_in_and_validated() -> void:
	assert_bool(Settings.is_deep_immersion()).is_false()
	assert_bool(Settings.set_immersion("deep")).is_true()
	assert_bool(Settings.is_deep_immersion()).is_true()
	assert_bool(Settings.set_immersion("everything")).is_false()
	assert_bool(Settings.is_deep_immersion()).is_true()


## ── The one settings surface ──────────────────────────────────────────────


## Title's Settings row opens the same overlay page the pause menu owns —
## one settings screen, not two (docs/09's P3.13 screen).
func test_title_settings_row_opens_the_shared_screen() -> void:
	var title: Control = auto_free(TitleScene.instantiate())
	title.scene_change_enabled = false
	add_child(title)
	await get_tree().process_frame
	title.settings_button.pressed.emit()
	assert_bool(PauseMenu.is_open()).is_true()
	assert_bool(PauseMenu.showing_settings()).is_true()


## Opening the screen shows the player's real state, so the Title row's
## photosensitive choice is already reflected when the menu appears.
func test_the_screen_reflects_the_current_settings() -> void:
	Settings.set_photosensitive(true)
	Settings.set_reduced_motion(true)
	Settings.set_calmer(true)
	Settings.set_immersion("deep")
	PauseMenu.open_settings()
	assert_str(PauseMenu._photosensitive_button.text).is_equal("Photosensitive mode: On")
	assert_bool(PauseMenu._reduced_motion_button.button_pressed).is_true()
	assert_bool(PauseMenu._calmer_button.button_pressed).is_true()
	assert_int(PauseMenu._immersion_option.selected).is_equal(1)
	assert_int(PauseMenu._content_option.selected).is_equal(1)


## The widgets drive the same API the tests drive — the screen is a view,
## never a second store.
func test_the_widgets_write_through_settings() -> void:
	PauseMenu.open_settings()
	PauseMenu._photosensitive_button.pressed.emit()
	assert_bool(Settings.photosensitive).is_true()
	assert_bool(FX.photosensitive).is_true()
	PauseMenu._calmer_button.toggled.emit(true)
	assert_str(Settings.content_level).is_equal("calmer")
	PauseMenu._text_speed_slider.value_changed.emit(1.75)
	assert_float(Settings.text_speed).is_equal(1.75)


## CODE-1: calmer mode and the content dropdown are two views of one stored
## field, so every write re-renders both — the screen can never claim a level
## the store does not have (safety-significant: the checkbox is the cap).
func test_the_calmer_toggle_and_content_dropdown_stay_in_sync() -> void:
	var calmer_idx := PauseMenu.CONTENT_VALUES.find("calmer")
	var unset_idx := PauseMenu.CONTENT_VALUES.find("")
	PauseMenu.open_settings()

	# dropdown → calmer: the checkbox follows
	PauseMenu._content_option.item_selected.emit(calmer_idx)
	assert_str(Settings.content_level).is_equal("calmer")
	assert_bool(PauseMenu._calmer_button.button_pressed).is_true()

	# checkbox off → the dropdown follows to the level it landed on (SAF-1: "")
	PauseMenu._calmer_button.toggled.emit(false)
	assert_str(Settings.content_level).is_equal("")
	assert_bool(PauseMenu._calmer_button.button_pressed).is_false()
	assert_int(PauseMenu._content_option.selected).is_equal(unset_idx)

	# and back on → both agree again
	PauseMenu._calmer_button.toggled.emit(true)
	assert_bool(PauseMenu._calmer_button.button_pressed).is_true()
	assert_int(PauseMenu._content_option.selected).is_equal(calmer_idx)


## CODE-6: the option labels are data (ui.json `settings.content_options` /
## `immersion_options`), so a writer tunes the safety copy without a code
## change. A table whose array length no longer matches the value list falls
## back to the canonical labels — a shifted list would write the wrong level.
func test_option_labels_come_from_the_string_table() -> void:
	var original: Dictionary = PauseMenu._config
	var patched: Dictionary = original.duplicate(true)
	(patched["settings"] as Dictionary)["content_options"] = ["A", "B", "C"]
	PauseMenu._config = patched
	var labels := PauseMenu._cfg_labels("content_options", PauseMenu.CONTENT_LABELS)
	var shifted := PauseMenu._cfg_labels("content_options", ["x", "y"])
	PauseMenu._config = original
	assert_array(labels).is_equal(["A", "B", "C"])
	assert_array(shifted).is_equal(["x", "y"])
	assert_int(PauseMenu.CONTENT_LABELS.size()).is_equal(PauseMenu.CONTENT_VALUES.size())
	assert_int(PauseMenu.IMMERSION_LABELS.size()).is_equal(PauseMenu.IMMERSION_VALUES.size())


## docs/01 §4: the content warning and the resources link live on the screen.
func test_content_warning_and_resources_are_present() -> void:
	PauseMenu.open_settings()
	var warning_text := ""
	var resources_found := false
	for child: Node in PauseMenu._settings_page.get_children():
		if child is Label and String((child as Label).text).contains("Content warning"):
			warning_text = (child as Label).text
		if child is Button and String((child as Button).text).contains("resources"):
			resources_found = true
	assert_str(warning_text).contains("horror")
	assert_bool(resources_found).is_true()
	assert_str(PauseMenu._cfg("settings", "resources_url", "")).contains("https://")
