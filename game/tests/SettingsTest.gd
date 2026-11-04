extends GdUnitTestSuite
## P2.15 round 2 (SAF-1) — the photosensitive accommodation must be reachable by
## a player and must stick. Settings is the store behind the Title screen's
## accessibility row: it pushes the flag straight to the FX host (so a running
## strobe is cut, not the next one) and persists it to `user://settings.cfg`,
## which docs/07 §3.5 keeps across "Reset Everything".

const TMP := "user://settings_test.cfg"


func before_test() -> void:
	_remove_tmp()
	Settings.settings_path = TMP
	Settings.photosensitive = false
	FX.photosensitive = false


func after_test() -> void:
	_remove_tmp()
	Settings.settings_path = Settings.PATH
	Settings.photosensitive = false
	FX.photosensitive = false


func _remove_tmp() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


## The row's action: on, live (FX hears it at once) and written down.
func test_the_toggle_is_live_and_persisted() -> void:
	assert_bool(FileAccess.file_exists(TMP)).is_false()
	assert_bool(Settings.toggle_photosensitive()).is_true()
	assert_bool(Settings.photosensitive).is_true()
	assert_bool(FX.photosensitive).is_true()  # the host was told, not queued
	assert_bool(FileAccess.file_exists(TMP)).is_true()


## A fresh launch reads it back: the player who needs the accommodation never
## has to find the row again.
func test_a_new_session_loads_the_saved_flag() -> void:
	Settings.set_photosensitive(true)
	Settings.photosensitive = false
	FX.photosensitive = false
	Settings.load_settings()
	assert_bool(Settings.photosensitive).is_true()
	assert_bool(FX.photosensitive).is_true()


## Missing file (first launch) keeps the documented default; the Title row is
## the entry point, so "off" is only ever a starting point a player changes.
func test_a_missing_file_keeps_the_default_off() -> void:
	assert_bool(FileAccess.file_exists(TMP)).is_false()
	Settings.load_settings()
	assert_bool(Settings.photosensitive).is_false()
	assert_bool(FX.photosensitive).is_false()


## Turning it back off is the same switch, and it also persists.
func test_the_toggle_round_trips() -> void:
	Settings.set_photosensitive(true)
	assert_bool(Settings.toggle_photosensitive()).is_false()
	assert_bool(FX.photosensitive).is_false()
	Settings.photosensitive = true
	Settings.load_settings()
	assert_bool(Settings.photosensitive).is_false()
