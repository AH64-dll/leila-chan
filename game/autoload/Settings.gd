extends Node
## Settings — immersion, photosensitive, content level, volumes, text speed
## (docs/07 §2). Owns the player's flags and pushes each one live to the
## system that honours it; the P3.13 settings screen (the PauseMenu overlay's
## settings page, one entry point) only ever calls the `set_*` API.
##
## `photosensitive` is a safety accommodation, not a preference (docs/02 §2.3):
## it turns the `flicker` cue into one slow dim and switches `invert_flash` off.
## The player reaches it before any date can strobe — the Title screen's
## accessibility row writes this flag — and it is persisted to
## `user://settings.cfg`, which docs/07 §3.5 keeps when "Reset Everything"
## wipes the rest of `user://`.
##
## `content_level` is `calmer`, `full`, or empty until the player chooses
## (missing/invalid fails closed to the strictest gates, Safety.gd). The
## settings screen's "calmer mode" toggle is not a separate flag: it writes
## `content_level = calmer`, the value Safety, Steering (stage ≤ 3 cap) and
## Corruption already read, so the gates and the dose ceiling can never
## disagree. `full` is only ever the result of an explicit selection
## (docs/02 §8 D11): switching the cap OFF restores the level that was in
## force before it was switched on — `content_level_before_calmer`, "" when the
## player never chose one — never `full` on the toggle's own authority.
##
## The persisted file is untrusted input: every value is type- and
## range-checked on load (non-finite numbers, wrong-typed flags and unknown
## enums fall back to the documented default instead of raising or freezing a
## live system), and the `set_*` entry points refuse non-finite numbers for
## the same reason.
##
## `immersion` is `standard` (default) or `deep`: docs/05 §0 rule 4 gates the
## OS-level meta tricks (window moves, transparency, cursor) behind Deep.
## `text_speed` scales the typewriter's chars-per-second; `bus_volumes` holds
## every slider AudioDirector exposes (docs/04 §1), keyed by bus name.

## Emitted after any field changes (saved or not), so an open UI re-reads.
signal changed(key: StringName)

const PATH := "user://settings.cfg"
const SECTION_ACCESSIBILITY := "accessibility"
const SECTION_GAME := "game"
const SECTION_AUDIO := "audio"

## docs/05 §0 rule 4: the immersion ladder a meta event may climb.
const IMMERSION_STANDARD := "standard"
const IMMERSION_DEEP := "deep"
const VALID_IMMERSION: Array[String] = ["standard", "deep"]

## docs/02 §8 / Safety._VALID_LEVELS: the two selectable content levels.
## "" stays a valid stored state — it means "never chosen" and fails closed.
const CONTENT_CALMER := "calmer"
const CONTENT_FULL := "full"
const VALID_CONTENT_LEVELS: Array[String] = ["calmer", "full"]

const TEXT_SPEED_MIN := 0.25
const TEXT_SPEED_MAX := 2.5
const TEXT_SPEED_DEFAULT := 1.0
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const VOLUME_DEFAULT := 1.0

## Test seam: point the store at a scratch file instead of the player's file.
var settings_path := PATH

## docs/02 §2.3: flicker dims instead of strobing, invert_flash never fires.
var photosensitive: bool = false
var reduced_motion: bool = false

## docs/02 §4 typewriter speed as a scale on the configured chars_per_second
## (1.0 = the ui.json rate). Not a safety gate, so it always defaults to 1.
var text_speed: float = TEXT_SPEED_DEFAULT

## docs/02 §8 content level: `calmer`, `full`, or empty until the player
## chooses (missing/invalid fails closed to the strictest content gates,
## Safety.gd). Read by Safety.gd's gates and Steering.gd's calmer-dose cap.
var content_level: String = ""

## docs/05 §0 rule 4: Deep unlocks the OS tricks; Standard is the default and
## everything a Standard player sees stays inside the game window anyway.
var immersion: String = IMMERSION_STANDARD

## docs/04 §1: linear volume per exposed AudioDirector bus ("Music", "SFX", …).
## A missing key means "untouched" — the bus keeps AudioServer's level.
var bus_volumes: Dictionary = {}

## The explicit level the calmer toggle capped: "" (never chosen) or `full`.
## Persisted as `content_level_before_calmer`, so switching the cap off after a
## relaunch restores the player's own earlier choice instead of guessing.
var _pre_calmer_level: String = ""


func _ready() -> void:
	load_settings()


## ── Photosensitive (P2.15) ────────────────────────────────────────────────


## The player-facing switch: the flag lands on the FX host immediately (a
## running strobe is cut mid-cue, not at the next trigger) and is written to
## disk so the accommodation outlives the session. `changed` lets every open
## view re-read it — the Title row and the settings page show the same flag.
func set_photosensitive(enabled: bool) -> void:
	_apply_photosensitive(enabled)
	save_settings()
	changed.emit(&"photosensitive")


## Flips the accommodation and returns its new value (the Title row's label
## reads it back).
func toggle_photosensitive() -> bool:
	set_photosensitive(not photosensitive)
	return photosensitive


## ── Reduced motion (docs/05 §0 rule 5 fallbacks) ───────────────────────────


## ChatUI/Corruption read this flag live (`is_reduced_motion()`), so a running
## screen honours it the next frame without a push.
func set_reduced_motion(enabled: bool) -> void:
	if reduced_motion == enabled:
		return
	reduced_motion = enabled
	save_settings()
	changed.emit(&"reduced_motion")


## ── Content level and calmer mode (docs/02 §8) ─────────────────────────────


## The settings screen's content selector. Values outside VALID_CONTENT_LEVELS
## are refused loudly: a stale or hostile write must never open the gates —
## "" itself is only ever set by "no choice yet", which is the empty string
## the file stores when the row was never touched.
##
## Choosing `calmer` remembers the explicit level it caps (for `set_calmer`'s
## off path); any other explicit choice replaces that memory, so turning the
## cap off later can never resurrect a level the player has since left.
func set_content_level(level: String) -> bool:
	if not level.is_empty() and not VALID_CONTENT_LEVELS.has(level):
		push_warning("Settings: refusing unknown content_level '%s'" % level)
		return false
	if content_level == level:
		return true
	if level == CONTENT_CALMER:
		if content_level != CONTENT_CALMER:
			_pre_calmer_level = content_level
	else:
		_pre_calmer_level = level
	content_level = level
	save_settings()
	changed.emit(&"content_level")
	return true


## docs/02 §8 "calmer mode (caps stage at 3)": a convenience over the same
## content_level the gates read — on writes `calmer`, off restores the level
## that was in force before it was switched on ("" when the player never chose
## one). docs/02 §8 D11 reserves `full` for an explicit selection, so the
## toggle itself never grants it: a player who only flipped the cap off lands
## on the fail-closed level and must still pick Full in the dropdown to get it.
func set_calmer(enabled: bool) -> bool:
	if enabled:
		return set_content_level(CONTENT_CALMER)
	if content_level != CONTENT_CALMER:
		return true
	return set_content_level(_pre_calmer_level)


func is_calmer() -> bool:
	return content_level == CONTENT_CALMER


## ── Immersion (docs/05 §0 rule 4) ──────────────────────────────────────────


## Deep is opt-in only. Unknown values are refused for the same fail-closed
## reason as the content level: a meta event must never read a permission a
## corrupted file invented.
func set_immersion(level: String) -> bool:
	if not VALID_IMMERSION.has(level):
		push_warning("Settings: refusing unknown immersion '%s'" % level)
		return false
	if immersion == level:
		return true
	immersion = level
	save_settings()
	changed.emit(&"immersion")
	return true


## The gate the M13–M18-style OS tricks ask (P3.09+). Standard is the safe
## default: everything else — including a file that failed to load — is not
## Deep.
func is_deep_immersion() -> bool:
	return immersion == IMMERSION_DEEP


## ── Text speed ────────────────────────────────────────────────────────────


## Scales the typewriter. The live TextBox is pushed through ChatUI's
## `set_text_speed_scale`, so a slider drag is heard mid-reveal, not on the
## next scene. ChatUI stays the single path — the PauseMenu calls this and
## this alone. NaN/±inf are refused: `clampf` passes them through, and a NaN
## `chars_per_second` freezes the reveal forever (SAF-4).
func set_text_speed(scale: float) -> void:
	if not is_finite(scale):
		push_warning("Settings: refusing non-finite text_speed %s" % scale)
		return
	var clamped := clampf(scale, TEXT_SPEED_MIN, TEXT_SPEED_MAX)
	if is_equal_approx(text_speed, clamped):
		return
	text_speed = clamped
	_push_text_speed()
	save_settings()
	changed.emit(&"text_speed")


func _push_text_speed() -> void:
	var chat_ui := _find_chat_ui()
	if chat_ui != null and chat_ui.has_method("set_text_speed_scale"):
		chat_ui.set_text_speed_scale(text_speed)


func _find_chat_ui() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(&"chat_ui"):
		return node
	return null


## ── Volumes (docs/04 §1) ───────────────────────────────────────────────────


## The slider's setter: the level lands on the AudioServer bus immediately
## (AudioDirector owns the dB mapping) and the value is persisted per bus, so
## the player's mix survives a session. Buses AudioDirector does not expose
## (MusicA/MusicB — the crossfade pair internals) are refused, and so are
## NaN/±inf levels: `clampf` passes NaN through, and a NaN bus level reaches
## `linear_to_db` as a meaningless value (SAF-4).
func set_bus_volume(bus: StringName, linear: float) -> bool:
	if not is_finite(linear):
		push_warning("Settings: refusing non-finite volume for bus '%s'" % bus)
		return false
	var audio := get_node_or_null("/root/AudioDirector")
	if audio == null or not audio.has_method("set_bus_volume_linear"):
		return false
	if not audio.bus_names().has(String(bus)):
		push_warning("Settings: refusing unexposed bus '%s'" % bus)
		return false
	var clamped := clampf(linear, VOLUME_MIN, VOLUME_MAX)
	bus_volumes[bus] = clamped
	audio.set_bus_volume_linear(bus, clamped)
	save_settings()
	changed.emit(&"bus_volumes")
	return true


## What the slider shows: the stored choice, else AudioServer's live level,
## else full — so a first-launch menu reads the real mix, not a guess.
func bus_volume(bus: StringName) -> float:
	if bus_volumes.has(bus):
		return clampf(float(bus_volumes[bus]), VOLUME_MIN, VOLUME_MAX)
	var audio := get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("bus_volume_linear"):
		return clampf(float(audio.bus_volume_linear(bus)), VOLUME_MIN, VOLUME_MAX)
	return VOLUME_DEFAULT


## The buses the settings screen may draw sliders for (docs/04 §1: expose flag).
func audio_buses() -> PackedStringArray:
	var audio := get_node_or_null("/root/AudioDirector")
	if audio == null or not audio.has_method("bus_names"):
		return PackedStringArray()
	return audio.bus_names()


## ── Persistence ───────────────────────────────────────────────────────────

## ── Reading untrusted values ──────────────────────────────────────────────
## `settings.cfg` can be hand-edited or truncated: every read is type- and
## range-checked, so a corrupt file falls back to the documented default
## instead of raising mid-load or feeding NaN into a live system (SAF-4).


## A stored number, or `fallback` when the value is not a number at all or is
## NaN/±inf. `clampf` alone is not enough — it passes NaN straight through.
func _cfg_float(
	cfg: ConfigFile, section: String, key: String, fallback: float, lo: float, hi: float
) -> float:
	var value: Variant = cfg.get_value(section, key, fallback)
	if not (value is float or value is int):
		return clampf(fallback, lo, hi)
	var number := float(value)
	return clampf(number, lo, hi) if is_finite(number) else clampf(fallback, lo, hi)


## A stored flag, or `fallback` for anything that is not a bool. `bool()` on a
## String raises in GDScript, which used to abort the whole load at that line.
func _cfg_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = cfg.get_value(section, key, fallback)
	if value is bool:
		return value
	return fallback


## A stored enum member, or `fallback` for a wrong-typed or unknown value, so
## the gates only ever see a member of `valid`.
func _cfg_enum(
	cfg: ConfigFile, section: String, key: String, valid: Array[String], fallback: String
) -> String:
	var value: Variant = cfg.get_value(section, key, fallback)
	if not value is String:
		return fallback
	var text := String(value)
	return text if valid.has(text) else fallback


## Reads the persisted settings. A missing or unreadable file keeps the
## documented defaults; photosensitive defaults to off because the Title row
## is its entry point, and a player who needs it turns it on before the first
## date. Invalid or wrong-typed values are dropped back to the documented
## default — a corrupt file can neither open a gate (Safety/Steering fail
## closed on "" / "standard") nor abort the load half-way.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	_apply_photosensitive(_cfg_bool(cfg, SECTION_ACCESSIBILITY, "photosensitive", photosensitive))
	_apply_reduced_motion(_cfg_bool(cfg, SECTION_ACCESSIBILITY, "reduced_motion", reduced_motion))
	text_speed = _cfg_float(
		cfg, SECTION_ACCESSIBILITY, "text_speed", TEXT_SPEED_DEFAULT, TEXT_SPEED_MIN, TEXT_SPEED_MAX
	)
	content_level = _cfg_enum(cfg, SECTION_GAME, "content_level", VALID_CONTENT_LEVELS, "")
	# Only `full` is ever a meaningful remembered level: the memory exists to
	# restore an explicit choice, and "" means the player never made one.
	_pre_calmer_level = (
		CONTENT_FULL
		if (
			_cfg_enum(cfg, SECTION_GAME, "content_level_before_calmer", VALID_CONTENT_LEVELS, "")
			== CONTENT_FULL
		)
		else ""
	)
	immersion = _cfg_enum(cfg, SECTION_GAME, "immersion", VALID_IMMERSION, IMMERSION_STANDARD)
	for bus: StringName in bus_volumes.keys():
		bus_volumes.erase(bus)
	if cfg.has_section(SECTION_AUDIO):
		for bus: String in cfg.get_section_keys(SECTION_AUDIO):
			bus_volumes[StringName(bus)] = _cfg_float(
				cfg, SECTION_AUDIO, bus, VOLUME_DEFAULT, VOLUME_MIN, VOLUME_MAX
			)
	_apply_bus_volumes()
	changed.emit(&"all")


## Writes every key this file owns. ConfigFile.save() replaces the whole file,
## which is safe here — settings.cfg is wholly owned by Settings (docs/07 §3.5
## keeps it across "Reset Everything").
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_ACCESSIBILITY, "photosensitive", photosensitive)
	cfg.set_value(SECTION_ACCESSIBILITY, "reduced_motion", reduced_motion)
	cfg.set_value(SECTION_ACCESSIBILITY, "text_speed", text_speed)
	if VALID_CONTENT_LEVELS.has(content_level):
		cfg.set_value(SECTION_GAME, "content_level", content_level)
	if _pre_calmer_level == CONTENT_FULL:
		cfg.set_value(SECTION_GAME, "content_level_before_calmer", _pre_calmer_level)
	if VALID_IMMERSION.has(immersion):
		cfg.set_value(SECTION_GAME, "immersion", immersion)
	for bus: StringName in bus_volumes:
		cfg.set_value(SECTION_AUDIO, String(bus), float(bus_volumes[bus]))
	var err := cfg.save(settings_path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [settings_path, err])


func _apply_photosensitive(enabled: bool) -> void:
	photosensitive = enabled
	var fx := get_node_or_null("/root/FX")
	if fx != null and fx.has_method("set_photosensitive"):
		fx.set_photosensitive(enabled)


func _apply_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled


## Restores the saved mix on launch. Buses AudioDirector no longer exposes are
## skipped rather than forced, so a stale key can never unmute an internal bus;
## a non-finite level is skipped instead of reaching `linear_to_db` (SAF-4).
func _apply_bus_volumes() -> void:
	var audio := get_node_or_null("/root/AudioDirector")
	if audio == null or not audio.has_method("set_bus_volume_linear"):
		return
	for bus: StringName in bus_volumes:
		var linear := float(bus_volumes[bus])
		if is_finite(linear) and audio.bus_names().has(String(bus)):
			audio.set_bus_volume_linear(bus, linear)
