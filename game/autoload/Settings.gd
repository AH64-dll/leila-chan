extends Node
## Settings — immersion, photosensitive, content level, volumes (docs/07 §2).
##
## `photosensitive` is a safety accommodation, not a preference (docs/02 §2.3):
## it turns the `flicker` cue into one slow dim and switches `invert_flash` off.
## The player reaches it before any date can strobe — the Title screen's
## accessibility row writes this flag — and it is persisted to
## `user://settings.cfg`, which docs/07 §3.5 keeps when "Reset Everything"
## wipes the rest of `user://`. P3.13's Settings screen takes over the UI and
## writes the same flag through `set_preference`.
##
## D20 (DECISIONS.md, hard rule): accessibility and safety accommodations must
## never be narratively punished. Accessibility input is not player behaviour,
## so a write to an accommodation is never an engine event, never a trigger and
## never a path-weight change — `is_accommodation()` is the one classifier, and
## `set_preference()` is the one write seam that consults it. T20 therefore only
## ever fires on a preference (today: choosing the full content ceiling).

const PATH := "user://settings.cfg"
const SECTION := "accessibility"
const CALMER_CONTENT := "calmer"
const CONTENT_LEVELS: Array[String] = ["", CALMER_CONTENT, "full"]
## D20's accommodation set. `text_speed` and `volume` have no live setter yet
## (P3.13's screen owns them; volume writes go through AudioDirector), but they
## are listed here so the classifier already refuses them: the list is the
## contract, not the set of fields that happen to exist today.
const ACCOMMODATION_KEYS: Array[String] = [
	"photosensitive", "reduced_motion", "text_speed", "volume", "master_volume"
]

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
##
## D20: it is NOT an engine event. It used to emit `settings_changed`, which
## fired docs/01 §5 T20's AWAKE/TSUN guilt line — the game punished a player
## for turning on the strobe-safe mode. See `set_preference` for the seam that
## still reaches T20 on a real preference.
func set_photosensitive(enabled: bool) -> void:
	_apply_photosensitive(enabled)
	save_settings()


## Flips the accommodation and returns its new value (the Title row's label
## reads it back).
func toggle_photosensitive() -> bool:
	set_photosensitive(not photosensitive)
	return photosensitive


## One write seam for the settings screen (P3.13) and the tests: apply the
## value, persist it, and emit docs/01 §5 T20's `settings_changed` only when the
## write is a preference. Returns false for a key this build does not own, so a
## typo cannot silently become a setting.
##
## D20: `is_accommodation()` decides. A photosensitive/reduced-motion/calmer/
## text-speed/volume write returns true without touching Telemetry, so it can
## never reach a trigger, a meta event or a path-weight change.
func set_preference(key: String, value: Variant) -> bool:
	var name := key.strip_edges()
	match name:
		"photosensitive":
			_apply_photosensitive(bool(value))
		"reduced_motion":
			reduced_motion = bool(value)
		"content_level":
			content_level = _heal_content_level(value)
		_:
			return false
	save_settings()
	if is_accommodation(name, value):
		return true
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("note_player_action"):
		telemetry.call("note_player_action", "settings_changed", {"setting": name})
	return true


## D20's classifier: is this write an accessibility/safety accommodation rather
## than a preference? Photosensitive mode, reduced motion, text speed and volume
## always are. `content_level` is one only when the player picks the calmer
## ceiling — the accommodation is choosing less, not choosing the full content.
static func is_accommodation(key: String, value: Variant) -> bool:
	if key == "content_level":
		return _heal_content_level(value) == CALMER_CONTENT
	return ACCOMMODATION_KEYS.has(key)


## Reads the persisted flags. A missing or unreadable file keeps the defaults;
## photosensitive defaults to off because the Title row is its entry point, and
## a player who needs it turns it on before the first date.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	_apply_photosensitive(bool(cfg.get_value(SECTION, "photosensitive", photosensitive)))
	reduced_motion = bool(cfg.get_value(SECTION, "reduced_motion", reduced_motion))
	content_level = _heal_content_level(cfg.get_value(SECTION, "content_level", content_level))


## Writes the flags a player can set today. Only keys this file owns are
## written, so a later section (P3.13) never inherits a stale value from here.
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "photosensitive", photosensitive)
	cfg.set_value(SECTION, "reduced_motion", reduced_motion)
	cfg.set_value(SECTION, "content_level", content_level)
	var err := cfg.save(settings_path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [settings_path, err])


func _apply_photosensitive(enabled: bool) -> void:
	photosensitive = enabled
	var fx := get_node_or_null("/root/FX")
	if fx != null and fx.has_method("set_photosensitive"):
		fx.set_photosensitive(enabled)


## docs/02 §8: a missing or invalid level stays empty, which fails closed to the
## strictest content gates (Safety.gd) — a typo must never open the full ceiling.
static func _heal_content_level(raw: Variant) -> String:
	var level := str(raw).strip_edges().to_lower()
	return level if CONTENT_LEVELS.has(level) else ""
