class_name InputHook
extends RefCounted
## InputHook — docs/02 §4 step 0: the engine-event drain (P2.09), the deleted
## draft's memory-only hand-off, the docs/01 §5 keyword layer ("K") and the
## non-textual GameState markers. Split out of Director.gd for the same reason
## TurnContext/Meters were: the pipeline file stays inside gdlint's file cap.
##
## Division of labour: Telemetry owns detection and the memory-only draft,
## Triggers owns matching/caps (P2.08), and this owns what one submit
## contributes to the turn — the docs/08 §6 lines plus the private terms the
## caller must scrub from anything it persists (docs/05 §0).

const DELETED_DRAFT_BAR := "[deleted draft]"


## Runs the step-0 hooks for one submit. `telemetry` is the /root/Telemetry
## seam (null only before the autoload ring finishes booting or in a stripped
## test scene); `payload` is the caller's submit telemetry dict. Returns
## {"lines": Array[String], "private": Array[String]}: `lines` is this turn's
## event layer, `private` the deleted-draft words to scrub before persisting.
static func apply(
	telemetry: Node, input_text: String, stage: int, payload: Dictionary
) -> Dictionary:
	var lines: Array[String] = []
	var private_terms: Array[String] = []
	if telemetry != null:
		if payload.has("deleted_draft"):
			telemetry.call("note_draft_deleted", str(payload["deleted_draft"]))
		if payload.has("idle_seconds"):
			telemetry.call("note_idle_seconds", float(payload["idle_seconds"]))
		telemetry.call("note_player_message", input_text)
		var taken: Variant = telemetry.call("take_turn_events", stage)
		if taken is Dictionary:
			var taken_dict: Dictionary = taken
			private_terms = (taken_dict.get("private", []) as Array).duplicate()
			_append_all(lines, taken_dict.get("lines", []))
	if payload.has("deleted_draft") and not str(payload["deleted_draft"]).strip_edges().is_empty():
		# Non-textual marker only: a flag is part of the save snapshot, so the
		# P1.08 text-valued flag quietly persisted the deleted draft (docs/05 §0).
		GameState.set_flag(&"t08_deleted_draft", true)
	if payload.has("idle_seconds") and float(payload["idle_seconds"]) > 30.0:
		GameState.set_flag(&"t11_idle", true)
	if Triggers != null and Triggers.has_method("begin_turn"):
		var fired: Variant = Triggers.begin_turn(input_text)
		if fired is Array:
			_append_all(lines, fired)
	return {"lines": lines, "private": private_terms}


## Deleted-draft privacy (docs/05 §0): the words may reach the prompt once —
## that is how docs/05 M21 quotes them at stage ≥ 3 — but nothing the game
## persists may hold them. Returns a rewritten copy of `value`.
static func scrub(value: Variant, terms: Array[String]) -> Variant:
	if terms.is_empty():
		return value
	if value is String:
		var out := str(value)
		for term: String in terms:
			if not term.is_empty():
				out = out.replace(term, DELETED_DRAFT_BAR)
		return out
	if value is Array:
		var out_array: Array = []
		for item: Variant in value:
			out_array.append(scrub(item, terms))
		return out_array
	if value is Dictionary:
		var out_dict: Dictionary = {}
		for key: Variant in value:
			out_dict[key] = scrub(value[key], terms)
		return out_dict
	return value


## Session boundary: per-session caps, pending events and the memory-only draft
## die here (docs/05 §3), and the trigger engine's event state follows.
static func reset_session(telemetry: Node) -> void:
	if telemetry != null and telemetry.has_method("reset_session"):
		telemetry.call("reset_session")
	if Triggers != null and Triggers.has_method("clear_engine_events"):
		Triggers.clear_engine_events()


## Appends non-empty, deduplicated lines from a Variant that should be an Array.
static func _append_all(lines: Array[String], source: Variant) -> void:
	if not (source is Array):
		return
	for item: Variant in source:
		var line := str(item).strip_edges()
		if not line.is_empty() and not lines.has(line):
			lines.append(line)
