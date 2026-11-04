extends GdUnitTestSuite
## SAF-4 / CODE-5 (P3.13 round 2) — `settings.cfg` is untrusted input. It is a
## plain text file a player can edit and a disk can truncate, so every read is
## type- and range-checked and every write entry point refuses non-finite
## numbers: a corrupt file must fall back to the documented default, never
## abort the load half-way and never feed NaN into a live system (a NaN text
## speed freezes the reveal; a NaN volume reaches `linear_to_db`).

const TMP := "user://settings_corruption_test.cfg"


func before_test() -> void:
	_remove_tmp()
	Settings.settings_path = TMP
	Settings.photosensitive = false
	Settings.reduced_motion = false
	Settings.text_speed = Settings.TEXT_SPEED_DEFAULT
	Settings.content_level = ""
	Settings._pre_calmer_level = ""
	Settings.immersion = "standard"
	Settings.bus_volumes.clear()
	FX.photosensitive = false


func after_test() -> void:
	_remove_tmp()
	Settings.settings_path = Settings.PATH
	Settings.photosensitive = false
	Settings.reduced_motion = false
	Settings.text_speed = Settings.TEXT_SPEED_DEFAULT
	Settings.content_level = ""
	Settings._pre_calmer_level = ""
	Settings.immersion = "standard"
	Settings.bus_volumes.clear()
	FX.photosensitive = false
	AudioDirector.set_bus_volume_linear(&"Music", 1.0)


func _remove_tmp() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


## SAF-4 / CODE-5: a corrupt file is untrusted input. `ConfigFile` round-trips
## nan/inf, `clampf` passes NaN through (a NaN text speed freezes the reveal
## forever) and `bool("yes")` raises, which used to abort the load at that line
## and skip every later key. Both now fall back to the documented default and
## the load always runs to the end.
func test_a_corrupt_cfg_fails_closed_without_aborting_the_load() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "photosensitive", "yes")  # wrong type for a bool
	cfg.set_value("accessibility", "reduced_motion", true)  # valid, read after the bad one
	cfg.set_value("accessibility", "text_speed", NAN)
	cfg.set_value("game", "content_level", "everything")
	cfg.set_value("game", "immersion", true)  # wrong type for an enum
	cfg.set_value("audio", "Music", INF)
	cfg.set_value("audio", "Voice", 0.5)  # valid, read last
	assert_int(cfg.save(TMP)).is_equal(OK)

	Settings.load_settings()

	assert_bool(Settings.photosensitive).is_false()  # safe default, no crash
	assert_bool(Settings.reduced_motion).is_true()  # the load kept going
	assert_float(Settings.text_speed).is_equal(Settings.TEXT_SPEED_DEFAULT)
	assert_bool(is_finite(Settings.text_speed)).is_true()
	assert_str(Settings.content_level).is_equal("")
	assert_bool(Settings.is_deep_immersion()).is_false()
	assert_float(Settings.bus_volume(&"Music")).is_equal_approx(Settings.VOLUME_DEFAULT, 0.001)
	assert_float(Settings.bus_volume(&"Voice")).is_equal_approx(0.5, 0.001)


## The setters are entry points as well: NaN/±inf must never reach the
## typewriter or a bus (SAF-4), even from a direct call.
func test_non_finite_writes_are_refused() -> void:
	Settings.set_text_speed(1.5)
	Settings.set_text_speed(NAN)
	Settings.set_text_speed(INF)
	assert_float(Settings.text_speed).is_equal(1.5)

	assert_bool(Settings.set_bus_volume(&"Music", 0.4)).is_true()
	assert_bool(Settings.set_bus_volume(&"Music", NAN)).is_false()
	assert_float(Settings.bus_volume(&"Music")).is_equal_approx(0.4, 0.001)
	assert_bool(is_finite(AudioDirector.bus_volume_linear(&"Music"))).is_true()
	AudioDirector.set_bus_volume_linear(&"Music", 1.0)
