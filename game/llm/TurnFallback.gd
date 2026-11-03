class_name TurnFallback
extends RefCounted
## TurnFallback — the docs/02 §7 turn-recovery shapes: the broken-stream beat, the
## empty-`say` beat, and the per-beat repairs (character-break deflection,
## third-person pronouns, repetition loops). Split out of Director.gd so the
## pipeline file stays inside gdlint's file-size cap, and so §7's shapes are a
## unit the suite can build without a running turn.
##
## These functions are pure with respect to the Director: they return the turn
## data plus the routing facts (which beat to rewrite, which sprite/fx to show),
## and the Director performs the subsystem calls. `TurnValidator` owns the text
## and pool decisions; this owns how a recovered turn is shaped.


## The recovered turn for a stream that died mid-JSON (docs/02 §7 row 1): the
## partial `say` that already reached the screen is kept, wrapped in the
## stage-appropriate fallback beat.
##
## Returns the turn data with two extra routing keys the Director consumes and
## strips: `_sprite` (the fallback sprite to show) and `_say` (the text to
## rewrite the queued beat with).
static func broken_stream_turn(
	partial_say: String, stage: int, player_name: String, current: Dictionary
) -> Dictionary:
	var info: Dictionary = TurnValidator.get_broken_stream_fallback(partial_say, stage, player_name)
	var say_text: String = str(info.get("say", "..."))
	var beat: Dictionary = {
		"feeling": str(info.get("feeling", "confused")),
		"intensity": int(info.get("intensity", 1)),
		"cue": str(info.get("cue", "none")),
		"say": say_text,
	}
	var turn := fill_defaults(current, {"affection": 0, "trust": 0, "stress": 1})
	turn["beats"] = [beat]
	turn["fx"] = str(info.get("fx", "none"))
	# A stream that died mid-thought has no trustworthy memory or action.
	turn["memory"] = ""
	turn["action"] = "none"
	turn["_sprite"] = str(info.get("sprite", "00"))
	turn["_say"] = say_text
	return turn


## The recovered turn for a reply whose `say` is empty at every beat (docs/02 §7
## row 2): the ellipsis beat, which the stage-3+ typing indicator makes diegetic.
static func empty_say_turn(current: Dictionary) -> Dictionary:
	var turn := fill_defaults(current, {"affection": 0, "trust": 0, "stress": 0})
	turn["beats"] = [{"feeling": "empty", "intensity": 1, "cue": "none", "say": "…"}]
	turn["fx"] = "none"
	turn["action"] = "none"
	turn["_sprite"] = ""
	turn["_say"] = "…"
	return turn


## Every field the turn close needs, keeping whatever the stream already closed
## and filling the rest with the fallback values.
static func fill_defaults(current: Dictionary, mood: Dictionary) -> Dictionary:
	return {
		"read": current.get("read", "other"),
		"inner": current.get("inner", "..."),
		"music": current.get("music", "keep"),
		"fx": current.get("fx", "none"),
		"beats": current.get("beats", []),
		"mood": current.get("mood", mood),
		"memory": current.get("memory", ""),
		"action": current.get("action", "none"),
	}


## Apply the docs/02 §7 per-beat repairs. Returns
##   {"beats": Array, "changed": {beat_index: repaired_text},
##    "deflections": int, "text_bleed": bool}
## and never touches the screen: the Director rewrites the queued beats.
static func repair_beats(
	beats: Array, stage: int, player_name: String, player_inputs: Array[String]
) -> Dictionary:
	var repaired: Array = []
	var changed: Dictionary = {}
	var deflections := 0
	var text_bleed := false

	for i in range(beats.size()):
		var variant: Variant = beats[i]
		if not (variant is Dictionary):
			repaired.append(variant)
			continue
		var beat: Dictionary = variant
		var beat_index := int(beat.get("index", i))
		var original_say := str(beat.get("say", ""))
		var say_text := original_say

		if TurnValidator.check_character_break(say_text, stage):
			# docs/02 §7: breaking character early is deflected in-fiction and
			# the profile counter records that the player pushed at the frame.
			deflections += 1
			var deflection: Dictionary = TurnValidator.get_deflection_beat(player_name)
			beat["feeling"] = deflection.get("feeling", beat.get("feeling", "confused"))
			beat["intensity"] = int(deflection.get("intensity", beat.get("intensity", 1)))
			beat["cue"] = deflection.get("cue", beat.get("cue", "none"))
			say_text = str(deflection.get("say", ""))
		else:
			# The last player messages are the referent context: "He" may be a
			# brother or rival the player just mentioned, not the player.
			say_text = TurnValidator.repair_player_pronouns(say_text, player_name, player_inputs)

			var loop: Dictionary = TurnValidator.detect_repetition_loop(say_text)
			if bool(loop.get("has_loop", false)):
				say_text = str(loop.get("clean_text", say_text))
				text_bleed = stage >= 4

		beat["say"] = say_text
		repaired.append(beat)
		if say_text != original_say:
			changed[beat_index] = say_text

	return {
		"beats": repaired,
		"changed": changed,
		"deflections": deflections,
		"text_bleed": text_bleed,
	}
