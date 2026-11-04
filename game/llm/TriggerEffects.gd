class_name TriggerEffects
extends RefCounted
## TriggerEffects — the effect arithmetic a docs/01 §5 trigger's firing lands
## with: the docs/02 §1.2 strength scaling, the P2.22B first-firing merge and
## the path-point ledger the engine folds into its scores.
##
## Split out of TriggerEngine (P2.22B) so the engine stays inside gdlint's
## file cap while the effect vocabulary keeps one definition. Everything here
## is static and pure except `add_path`, which mutates the caller's ledger:
## the engine owns the running path scores, this only knows how a parsed effect
## group becomes points. A row's effects are data (data/triggers.json), never
## names hard-coded here — an unknown meter still passes through and fails
## loudly in GameState, where the meter ranges live.


## Scales one row's effects by the firing's strength. Meters stay fractional;
## profile counters and path points are integers and round half away from zero,
## so a data author who needs an exact halving uses an even value.
static func scale(effects: Dictionary, strength: float) -> Dictionary:
	var out := {"meters": {}, "profile": {}, "path": {}, "flags": {}}
	var meters: Dictionary = effects.get("meters", {})
	for name: Variant in meters:
		var value := float(meters[name]) * strength
		if not is_zero_approx(value):
			out["meters"][str(name)] = value
	for group: String in ["profile", "path"]:
		var points: Dictionary = effects.get(group, {})
		for name: Variant in points:
			var value := roundi(float(points[name]) * strength)
			if value != 0:
				out[group][str(name)] = value
	var flags: Dictionary = effects.get("flags", {})
	for name: Variant in flags:
		out["flags"][str(name)] = flags[name]
	return out


## Adds one scaled effects dictionary into another, group by group — how
## `first_effects` folds into `effects` on a row's first firing (P2.22B).
static func merge(target: Dictionary, extra: Dictionary) -> void:
	for group: String in ["meters", "profile", "path"]:
		var values: Dictionary = extra.get(group, {})
		for name: Variant in values:
			var key := str(name)
			target[group][key] = float(target[group].get(key, 0.0)) + float(values[key])
	for group: String in ["profile", "path"]:
		for name: Variant in target[group]:
			target[group][name] = roundi(float(target[group][name]))
	var flags: Dictionary = extra.get("flags", {})
	for name: Variant in flags:
		target["flags"][str(name)] = flags[name]


## Folds one firing's path points into the caller's running score ledger.
static func add_path(scores: Dictionary, effects: Dictionary) -> void:
	var points: Dictionary = effects.get("path", {})
	for name: Variant in points:
		var key := str(name)
		scores[key] = int(scores.get(key, 0)) + int(points[name])
