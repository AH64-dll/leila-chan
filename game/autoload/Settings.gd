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

## D20's accommodation set. `text_speed` and `volume` have no live setter yet
## (P3.13's screen owns them; volume writes go through AudioDirector), but they
## are listed here so the classifier already refuses them: the list is the
## contract, not the set of fields that happen to exist today.
const ACCOMMODATION_KEYS: Array[String] = [
	"photosensitive", "reduced_motion", "text_speed", "volume", "master_volume"
]

const TEXT_SPEED_MIN := 0.25
const TEXT_SPEED_MAX := 2.5
const TEXT_SPEED_DEFAULT := 1.0
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const VOLUME_DEFAULT := 1.0
const SECTION_PRIVACY := "privacy"

## Test seam: point the store at a scratch file instead of the player's file.
var settings_path := PATH

## docs/02 §2.3: flicker dims instead of strobing, invert_flash never fires.
var photosensitive: bool = false
var reduced_motion: bool = false

## docs/07 §4 Fast mode: one beat and a shorter reply, enforced by the turn grammar.
## Off by default; a settings file without the key loads as off.
var fast_mode: bool = false

## docs/02 §4 typewriter speed as a scale on the configured chars_per_second
## (1.0 = the ui.json rate). Not a safety gate, so it always defaults to 1.
var text_speed: float = TEXT_SPEED_DEFAULT

## docs/02 §8 content level: `calmer`, `full`, or empty until the player
## chooses (missing/invalid fails closed to the strictest content gates,
## Safety.gd). Read by Safety.gd's gates and Steering.gd's calmer-dose cap.
var content_level: String = ""

## docs/09 privacy + docs/08 §1.5: the OS username reaches the game ONLY when
## the player opts in ("let her call you by your real name"). Defaults off and
## persisted; when on, New Game's name field treats a typed name matching the
## OS account name as "You told me the truth. Good." and M28 may use it. The
## username itself is never written to disk — only the flag is.
var use_os_username: bool = false

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


## The OS account name when the player opted in, "" otherwise — this is the
## only read of the environment the game ever makes, and docs/09's opt-in
## gate means the username is invisible to name rules until `use_os_username`
## is true. USERNAME covers Windows; USER covers Linux/macOS.
func os_username() -> String:
	if not use_os_username:
		return ""
	for var_name: String in ["USERNAME", "USER"]:
		var value := OS.get_environment(var_name).strip_edges()
		if not value.is_empty():
			return value
	return ""


func set_use_os_username(enabled: bool) -> void:
	use_os_username = enabled
	save_settings()


func _ready() -> void:
	load_settings()


## ── Photosensitive (P2.15) ────────────────────────────────────────────────


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


## P4.06: read when the next turn request is finalized, so a turn already in flight
## keeps the mode it started with.
func set_fast_mode(enabled: bool) -> void:
	if fast_mode == enabled:
		return
	fast_mode = enabled
	save_settings()
	changed.emit(&"fast_mode")


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


## One write seam for the settings screen (P3.13) and the tests: apply the
## value, persist it, and emit docs/01 §5 T20's `settings_changed` only when
## the write is a preference. Returns false for a key this build does not own,
## so a typo cannot silently become a setting.
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
			set_reduced_motion(bool(value))
		"content_level":
			if not set_content_level(_heal_content_level(value)):
				return false
		_:
			return false
	if name != "content_level":
		save_settings()
	if is_accommodation(name, value):
		return true
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("note_player_action"):
		telemetry.call("note_player_action", "settings_changed", {"setting": name})
	return true


## D20's classifier: is this write an accessibility/safety accommodation rather
## than a preference? Photosensitive mode, reduced motion, text speed and
## volume always are. `content_level` is one only when the player picks the
## calmer ceiling — the accommodation is choosing less, not choosing full.
static func is_accommodation(key: String, value: Variant) -> bool:
	if key == "content_level":
		return _heal_content_level(value) == CONTENT_CALMER
	return ACCOMMODATION_KEYS.has(key)


## docs/02 §8: a missing or invalid level stays empty, which fails closed to the
## strictest content gates (Safety.gd) — a typo must never open the full ceiling.
static func _heal_content_level(raw: Variant) -> String:
	var level := str(raw).strip_edges().to_lower()
	return level if VALID_CONTENT_LEVELS.has(level) else ""


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
##
## Each flag is read fail-closed through `_stored_bool`: a hand-edited file can
## hold any type where a bool belongs, and `bool("false")` would raise
## `Nonexistent 'bool' constructor` mid-load, so only a real bool is trusted.
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
	fast_mode = _cfg_bool(cfg, SECTION_GAME, "fast_mode", false)
	for bus: StringName in bus_volumes.keys():
		bus_volumes.erase(bus)
	if cfg.has_section(SECTION_AUDIO):
		for bus: String in cfg.get_section_keys(SECTION_AUDIO):
			bus_volumes[StringName(bus)] = _cfg_float(
				cfg, SECTION_AUDIO, bus, VOLUME_DEFAULT, VOLUME_MIN, VOLUME_MAX
			)
	_apply_bus_volumes()
	use_os_username = _stored_bool(cfg, SECTION_PRIVACY, "use_os_username", use_os_username)
	changed.emit(&"all")


## A persisted flag, healed: only a bool is accepted, anything else (a string,
## a number, a list) keeps `fallback` and warns. Both flags default to off, so a
## value the file cannot express leaves the safe state — the opt-in stays off
## and the photosensitive accommodation keeps whatever the Title row set.
static func _stored_bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var stored: Variant = cfg.get_value(section, key, fallback)
	if stored is bool:
		return stored
	push_warning("Settings: [%s] %s is not a bool; keeping %s" % [section, key, fallback])
	return fallback


## Writes every key this file owns. ConfigFile.save() replaces the whole file,
## which is safe here — settings.cfg is wholly owned by Settings (docs/07 §3.5
## keeps it across "Reset Everything").
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_ACCESSIBILITY, "photosensitive", photosensitive)
	cfg.set_value(SECTION_PRIVACY, "use_os_username", use_os_username)
	cfg.set_value(SECTION_ACCESSIBILITY, "reduced_motion", reduced_motion)
	cfg.set_value(SECTION_ACCESSIBILITY, "text_speed", text_speed)
	if VALID_CONTENT_LEVELS.has(content_level):
		cfg.set_value(SECTION_GAME, "content_level", content_level)
	if _pre_calmer_level == CONTENT_FULL:
		cfg.set_value(SECTION_GAME, "content_level_before_calmer", _pre_calmer_level)
	if VALID_IMMERSION.has(immersion):
		cfg.set_value(SECTION_GAME, "immersion", immersion)
	cfg.set_value(SECTION_GAME, "fast_mode", fast_mode)
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
