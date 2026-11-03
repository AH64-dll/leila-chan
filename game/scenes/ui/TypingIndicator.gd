class_name TypingIndicator
extends RefCounted
## The diegetic "Leila is typing…" line (docs/02 §4). Shown from the moment the
## player's message is sent until the first say token arrives. Pure RefCounted
## so tests can drive it without a scene: feed time through advance(delta)
## and read display_text().
##
## Stage behaviour (all thresholds in res://data/ui.json):
##  stage ≥ 3 → the dots stutter instead of a steady beat
##  stage ≥ 5 → sometimes the line becomes "Leila is typing… *you*"

var base_template := "{name} is typing"
var dots_period_ms := 400.0
var stutter_min_stage := 3
var stutter_pattern_ms: Array = [160, 160, 520, 120, 120, 600]
var you_suffix := " *you*"
var you_min_stage := 5
var you_chance := 0.2

var stage := 0
var active := false

var _rendered_base := ""
var _elapsed_ms := 0.0
var _dots := 0
var _rng := RandomNumberGenerator.new()
var _you := false


func configure(config: Dictionary) -> void:
	base_template = str(config.get("base_text", base_template))
	_rendered_base = base_template
	dots_period_ms = float(config.get("dots_period_ms", dots_period_ms))
	stutter_min_stage = int(config.get("stutter_min_stage", stutter_min_stage))
	var pattern: Variant = config.get("stutter_pattern_ms")
	if pattern is Array and not pattern.is_empty():
		stutter_pattern_ms = pattern
	you_suffix = str(config.get("you_suffix", you_suffix))
	you_min_stage = int(config.get("you_min_stage", you_min_stage))
	you_chance = float(config.get("you_chance", you_chance))


func begin(speaker_name: String, at_stage: int) -> void:
	_rendered_base = base_template.replace("{name}", speaker_name)
	stage = at_stage
	active = true
	_elapsed_ms = 0.0
	_dots = 0
	_you = stage >= you_min_stage and _rng.randf() < you_chance


func stop() -> void:
	active = false


func advance(delta: float) -> void:
	if not active:
		return
	_elapsed_ms += delta * 1000.0
	_dots = _dots_for(_elapsed_ms)


func display_text() -> String:
	var tail := ".".repeat(maxi(_dots, 1))
	if _you:
		return _rendered_base + tail + you_suffix
	return _rendered_base + tail


## A fixed seed makes the stage-5 "*you*" roll and stutter timing
## deterministic in tests and replays.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func is_you_variant() -> bool:
	return _you


## Number of dots for an elapsed time: a steady 1-2-3 beat normally, a clipped
## stutter cadence at stage ≥ 3 (docs/02 §4 "the dots stutter").
func _dots_for(elapsed_ms: float) -> int:
	if stage < stutter_min_stage or stutter_pattern_ms.is_empty():
		return int(elapsed_ms / dots_period_ms) % 3 + 1
	var total := 0.0
	for slot: Variant in stutter_pattern_ms:
		total += float(slot)
	var pos := fmod(elapsed_ms, total)
	var acc := 0.0
	var dots := 0
	for slot: Variant in stutter_pattern_ms:
		acc += float(slot)
		if pos >= acc:
			dots += 1
	return mini(dots + 1, 3)
