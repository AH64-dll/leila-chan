extends RefCounted
## docs/10 §3: hand one sprite's on-enter effects to the engine systems.
##
## The SpriteResolver has already applied the below-stage variants and the budget
## ("1 reveal per scene", "terminal climax only"), so this class only dispatches:
## engine cues through AudioDirector.play_engine_cue (never the model's cue budget),
## sound groups through play_system, the visual through FX.trigger and the music bed
## through request_music. Every subsystem decides for itself — the returned report is
## what it answered, which is also what tests and the dev overlay read.
##
## It lives outside the Director because the Director's cq is at the gdlint file and
## method caps, and because the dispatch has nothing to do with the turn pipeline.


## Fire one resolved entry-event dictionary; returns the dispatch report.
func fire(events: Dictionary) -> Dictionary:
	var stage := int(events.get("stage", 0))
	var report := {
		"cue": "",
		"cue_ok": false,
		"system": [],
		"system_ok": [],
		"fx": "",
		"fx_ok": false,
		"music": "",
		"music_ok": false,
	}
	var cue := String(events.get("cue", ""))
	if not cue.is_empty():
		report["cue"] = cue
		if AudioDirector != null and AudioDirector.has_method("play_engine_cue"):
			report["cue_ok"] = AudioDirector.play_engine_cue(StringName(cue))
	for group: Variant in events.get("system", []):
		var key := StringName(str(group))
		var played := false
		if AudioDirector != null and AudioDirector.has_method("play_system"):
			played = AudioDirector.play_system(key)
		(report["system"] as Array).append(String(key))
		(report["system_ok"] as Array).append(played)
	var fx_name := String(events.get("fx", ""))
	if not fx_name.is_empty():
		report["fx"] = fx_name
		if FX != null and FX.has_method("trigger"):
			report["fx_ok"] = FX.trigger(fx_name, stage)
	var music := String(events.get("music", ""))
	if not music.is_empty():
		report["music"] = music
		if AudioDirector != null and AudioDirector.has_method("request_music"):
			report["music_ok"] = AudioDirector.request_music(StringName(music))
	return report
