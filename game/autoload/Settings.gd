extends Node
## Settings — immersion, photosensitive, content level, volumes (docs/07 §2).
##
## `photosensitive` is a safety accommodation, not a preference (docs/02 §2.3):
## it turns the `flicker` cue into one slow dim and switches `invert_flash` off.
## The player reaches it before any date can strobe — the Title screen's
## accessibility row writes this flag — and it is persisted to
## `user://settings.cfg`, which docs/07 §3.5 keeps when "Reset Everything"
## wipes the rest of `user://`. P3.13's Settings screen takes over the UI and
## writes the same flag.

const PATH := "user://settings.cfg"
const SECTION := "accessibility"

## Test seam: point the store at a scratch file instead of the player's file.
var settings_path := PATH

## docs/02 §2.3: flicker dims instead of strobing, invert_flash never fires.
var photosensitive: bool = false
var reduced_motion: bool = false

## docs/02 §8 content level: `calmer`, `full`, or empty until the player chooses
## (missing/invalid fails closed to the strictest content gates, Safety.gd).
## Read by Safety.gd's gates and Steering.gd's calmer-dose cap; the settings
## menu that writes it is P3.13.
var content_level: String = ""


func _ready() -> void:
	load_settings()


## Settings → "Reset Everything" (docs/07 §3.5, docs/05 M08): deletes ALL of
## `user://` — save slots, the shadow save, letters, diary, debug transcripts —
## EXCEPT this file (a wiped game still honours the photosensitive
## accommodation it already saved). SaveSystem owns the recursive delete and
## the seam paths; this is the screen's entry point. Returns its result
## {ok, removed, errors}; the live flags are NOT cleared — the settings file
## is the one thing kept, on purpose.
func reset_everything() -> Dictionary:
	var saves := get_node_or_null("/root/SaveSystem")
	if saves == null or not saves.has_method("wipe_everything"):
		return {"ok": false, "removed": 0, "errors": ["SaveSystem unavailable"]}
	return saves.wipe_everything([settings_path])


## The player-facing switch: the flag lands on the FX host immediately (a
## running strobe is cut mid-cue, not at the next trigger) and is written to
## disk so the accommodation outlives the session.
func set_photosensitive(enabled: bool) -> void:
	_apply_photosensitive(enabled)
	save_settings()
	# docs/01 §5 T20 "why did you make me quieter?": any player-written setting
	# is an engine event; Telemetry queues the line for the next turn.
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("note_player_action"):
		telemetry.call("note_player_action", "settings_changed", {"setting": "photosensitive"})


## Flips the accommodation and returns its new value (the Title row's label
## reads it back).
func toggle_photosensitive() -> bool:
	set_photosensitive(not photosensitive)
	return photosensitive


## Reads the persisted flags. A missing or unreadable file keeps the defaults;
## photosensitive defaults to off because the Title row is its entry point, and
## a player who needs it turns it on before the first date.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	_apply_photosensitive(bool(cfg.get_value(SECTION, "photosensitive", photosensitive)))


## Writes the flags a player can set today. Only keys this file owns are
## written, so a later section (P3.13) never inherits a stale value from here.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "photosensitive", photosensitive)
	var err := cfg.save(settings_path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [settings_path, err])


func _apply_photosensitive(enabled: bool) -> void:
	photosensitive = enabled
	var fx := get_node_or_null("/root/FX")
	if fx != null and fx.has_method("set_photosensitive"):
		fx.set_photosensitive(enabled)
