class_name MetaDemoM01
extends RefCounted
## MetaDemoM01 — the F3 overlay's previews for docs/05 §1.1–§1.2 M01–M12
## (P3.09). Dev builds only: `MetaEventsM01.debug_fire()` refuses in release, and
## this file is never called from gameplay.
##
## A preview runs the *effect*, not the scheduling: gates, scene budget and the
## `meta_seen` ledger are bypassed the way `MetaDirector.debug_offer` bypasses
## them, so a reviewer can walk all twelve events inside one scene. Two effects
## are records rather than drawings (M02's "she closed it" marker, M04's quit
## memory) and those are written, because the record is the whole event; M02
## still quits, which is what the second half of its demo proves on relaunch.
##
## Everything here goes through the module's public API only, so the demo can
## never show something the game itself could not do.

const DETAIL := {
	"M02": "black-out, then the app quits; next launch the title is altered",
	"M03": "cold-open line played (needs a date on screen)",
	"M08": "shadow-memory line played (needs Day 1 and a sealed run)",
	"M09": "in-game crash replica shown — every button leads back in",
	"M10": "in-game update screen stalling at 99% — [Later] is always there",
	"M11": 'credits roll, then "That\'s not how it ends."',
}


## Run one preview. Returns `{ok, detail}`; the module stores the detail for the
## overlay's demo line.
static func run(module: Node, id: String) -> Dictionary:
	match id:
		"M01":
			return _close_request(module)
		"M04":
			return _quit_memory(module)
		"M05":
			return _away_time(module)
		"M06", "M07":
			return _title(module, id)
		"M12":
			module.call("fire", id, "")
			return {"ok": true, "detail": _detail(module, id)}
		_:
			if not DETAIL.has(id):
				return {"ok": false, "detail": "%s: no F3 preview" % id}
			module.call("fire", id, "")
			return {"ok": true, "detail": _detail(module, id)}


## M01's demo presses the real close path: the first press is held (her one line
## is offered) and the second closes — the acceptance criterion, live.
static func _close_request(module: Node) -> Dictionary:
	var tree := module.get_tree()
	if tree == null or tree.root == null:
		return {"ok": false, "detail": "no window to close"}
	tree.root.emit_signal(&"close_requested")
	var held := false
	var host := module.get_parent()
	if host != null and host.has_method("state"):
		var view: Variant = host.call("state")
		if view is Dictionary:
			held = bool((view as Dictionary).get("close_held", false))
	var how := "held (refuse_exit offered)" if held else "passed straight through"
	return {"ok": true, "detail": "M01: close request %s — press again to quit" % how}


## M04 records a real quit memory and prints the sentence the next session would
## carry; the path clause comes from the live game path, so the preview is
## path-specific the same way the event is.
static func _quit_memory(module: Node) -> Dictionary:
	module.call("record_quit", "window_x")
	var note := str(module.call("session_note_preview", -1, "window_x"))
	return {"ok": true, "detail": "M04: recorded quit=window_x; next session note: %s" % note}


## M05 needs a measured gap; a machine that has never played gets the reunion
## bucket as a clearly-labelled preview so the reviewer still sees the shape.
static func _away_time(module: Node) -> Dictionary:
	var view: Variant = module.call("state")
	var away := -1
	if view is Dictionary:
		away = int((view as Dictionary).get("away_seconds", -1))
	var measured := away >= 0
	var gap := away if measured else 86400
	var note := str(module.call("session_note_preview", gap, ""))
	var detail := "M05: away %s; note: %s" % [MetaEventsM01.human_duration(gap), note]
	if not measured:
		detail += " (no recorded session — preview)"
	return {"ok": true, "detail": detail}


## M06/M07 live on the Title screen, so the preview prints the decision and, in
## a real build, opens the title screen itself — the reviewer sees the drift.
static func _title(module: Node, id: String) -> Dictionary:
	var view: Variant = module.call("state")
	if not view is Dictionary:
		return {"ok": false, "detail": "%s: no title state" % id}
	var title: Dictionary = (view as Dictionary).get("title", {})
	var sprite := str(title.get("sprite", ""))
	var detail := (
		"M06: stage %d, sprite %s, eyes %s, title %s"
		% [
			int(title.get("stage", 0)),
			sprite if not sprite.is_empty() else "(unchanged)",
			"follow" if bool(title.get("eyes_follow", false)) else "fixed",
			(
				str(title.get("title_text", ""))
				if not str(title.get("title_text", "")).is_empty()
				else "(unchanged)"
			),
		]
	)
	if id == "M07":
		detail = (
			"M07: stage %d, New Game %s (%s)"
			% [
				int(title.get("stage", 0)),
				"locked" if bool(title.get("new_game_locked", false)) else "open",
				str(title.get("lock_line", "")),
			]
		)
	var tree := module.get_tree()
	if tree != null and DisplayServer.get_name() != "headless":
		tree.change_scene_to_file.call_deferred("res://scenes/Title.tscn")
	return {"ok": true, "detail": detail}


static func _detail(module: Node, id: String) -> String:
	if id == "M12":
		var view: Variant = module.call("state")
		var shown := ""
		if view is Dictionary:
			shown = str((view as Dictionary).get("last_window_title", ""))
		return "M12: window title = %s" % shown
	return "%s: %s" % [id, str(DETAIL.get(id, "fired"))]
