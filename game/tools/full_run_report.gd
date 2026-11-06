class_name FullRunReport
extends RefCounted
## FullRunReport — Markdown rendering for the P2.22 full-run driver
## (`tools/full_run_driver.gd`). Split out so the driver stays under gdlint's
## 1000-line cap and the transcript's shape has one owner: every section here is
## read off the same records the driver appends and the JSON sidecar stores.
##
## The renderer reads live autoloads (`GameState`, `Stages`, `Director`,
## `Memory`) for the values a turn just left behind; it never mutates anything.

const NATIVE_METRIC_KEYS := [
	"dose_applied",
	"dose_error",
	"spike",
	"first_say_ms",
	"cache_reused_tokens",
	"prompt_tokens",
	"prompt_ms",
]

var run := "run"
var player := "Ren"
var model := "unknown"
var url := "http://127.0.0.1:8089"
var started := ""
var command := ""
var max_days := 14
var stop_stage := 6
var records: Array[Dictionary] = []
var nights: Array[Dictionary] = []
var broken: Array[Dictionary] = []
var refused: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var path_log: Array[Dictionary] = []
var trigger_log: Array[Dictionary] = []
var redaction_log: Array[Dictionary] = []
var leak_log: Array[Dictionary] = []
var own_server := false


func header_lines() -> Array[String]:
	var lines: Array[String] = []
	lines.append("# P2.22 full run — %s\n" % run)
	lines.append(
		(
			'- run: `%s` · player: "%s" · days 1–%d · stop-stage %d'
			% [run, player, max_days, stop_stage]
		)
	)
	lines.append("- model: %s · llama-server %s" % [model, url])
	lines.append(
		(
			"- sampling: `game/data/sampling.json` per stage "
			+ "(the game's own table, read by TurnContext)"
		)
	)
	lines.append(
		(
			"- dose: `Steering.dose_for` per turn — %s"
			% (
				"bound via server relaunch (own-server mode)"
				if own_server
				else "scheduled, not bound (attach mode: the app did not launch the server)"
			)
		)
	)
	lines.append(
		"- saves: `SaveSystem` autosave per scene and per turn (`user://saves/autosave.json`)"
	)
	lines.append("- started: %s" % started)
	lines.append("- command: `%s`" % command)
	lines.append(
		(
			"- dev artifact: the **Leila** quotes below are the raw model `say` "
			+ "(pre-filter); the filtered screen text is the `_displayed` line, "
			+ "and bar-glyph counts include the corruption `redact` effect — "
			+ "they are not all safety redactions"
		)
	)
	lines.append("")
	lines.append("## Driver wiring\n")
	lines.append(
		(
			"Three wires the shipped Date scene does not install; the driver installs them "
			+ "exactly as the milestone intends (proposed tasks in the P2.22 handoff):\n"
		)
	)
	lines.append("1. `Date.start_date()` — no caller in `game/`.")
	lines.append(
		"2. `ChatUI.player_turn_sent → Director.submit_player_input` — no caller in `game/`."
	)
	lines.append("3. `Director.scene_info ← ScenarioLoader.resolve_scene(...)` — never assigned.")
	lines.append(
		(
			"\nEverything else is the shipped pipeline: Date/ChatUI/Night scenes, Director, "
			+ "PromptBuilder, LLM → llama-server, TurnSchema, TurnFallback, Safety, Triggers, "
			+ "Memory, GameState, Steering, Campaign, NightLoop, SaveSystem."
		)
	)
	lines.append("")
	return lines


func day_header_lines(scenario: Dictionary, stage: int, dose: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("\n---\n")
	lines.append(
		(
			'## Day %d — %s "%s"\n'
			% [
				int(GameState.day),
				String(scenario.get("id", "?")),
				String(scenario.get("title", ""))
			]
		)
	)
	(
		lines
		. append(
			(
				'- stage %d "%s" · path %s · instability %.1f (peak %.1f, floor %.1f) · turn %d'
				% [
					stage,
					Stages.name_of(stage),
					_path_text(),
					float(GameState.instability),
					float(GameState.instability_peak),
					float(GameState.instability_floor),
					int(GameState.turn),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"- dose: %s (%s)"
				% [
					_dose_text(dose),
					(
						"bound via server relaunch"
						if own_server
						else "scheduled; attach mode binds no vector"
					),
				]
			)
		)
	)
	var end_rules: Dictionary = scenario.get("end", {})
	(
		lines
		. append(
			(
				'- scenario: goal "%s", turns %d–%d'
				% [
					String(scenario.get("goal", "")),
					int(end_rules.get("min_turns", 0)),
					int(end_rules.get("max_turns", 0)),
				]
			)
		)
	)
	var beats: Array = ScenarioLoader.get_opening_beats(scenario, stage, player)
	if not beats.is_empty():
		lines.append("- opening beat (engine, played through ChatUI):")
		for beat: Variant in beats:
			if beat is Dictionary:
				lines.append("  - " + _beat_line(beat as Dictionary, false))
	lines.append("")
	return lines


## The native metrics a record keeps: empty unless NativeBackend ran the turn.
static func native_metrics() -> Dictionary:
	var out := {}
	if not LLM.get_backend() is NativeBackend:
		return out
	var metrics := LLM.last_metrics()
	for key: String in NATIVE_METRIC_KEYS:
		if metrics.has(key):
			out[key] = metrics[key]
	return out


## One `**Native:**` line for a native turn; `?` marks a key the backend did not report.
func _native_line(native: Dictionary) -> String:
	var line := (
		"**Native:** dose_applied=%s · first_say=%s · reused=%s/%s tokens"
		% [
			str(native.get("dose_applied", "?")),
			_shown(native, "first_say_ms", "%.0fms"),
			_shown(native, "cache_reused_tokens", "%.0f"),
			_shown(native, "prompt_tokens", "%.0f"),
		]
	)
	if native.has("dose_error"):
		line += " · dose_error=%s" % str(native["dose_error"])
	if native.has("spike"):
		line += " · spike=%s" % str(native["spike"])
	return line + "\n"


func _shown(native: Dictionary, key: String, fmt: String) -> String:
	return fmt % float(native[key]) if native.has(key) else "?"


func turn_lines(record: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var stage := int(record["stage"])
	(
		lines
		. append(
			(
				'### Turn %d · day %d · stage %d "%s" · instability %.1f\n'
				% [
					int(record["turn_in_day"]),
					int(record["day"]),
					stage,
					Stages.name_of(stage),
					float(record["instability"]),
				]
			)
		)
	)
	var native: Dictionary = record.get("native", {})
	if not native.is_empty():
		lines.append(_native_line(native))
	var event := String(Director.scene_info.get("event", "")).strip_edges()
	if not event.is_empty():
		lines.append("**Event:** %s\n" % event)
	lines.append("**Player:** %s\n" % String(record.get("player", "")))
	lines.append("**Leila:**\n")
	var beats: Array = record["beats"] if record["beats"] is Array else []
	var displayed: Array = record["displayed"] if record["displayed"] is Array else []
	for i: int in range(beats.size()):
		if not beats[i] is Dictionary:
			continue
		var beat: Dictionary = beats[i]
		lines.append(_beat_line(beat, true))
		var shown := String(displayed[i]) if i < displayed.size() else ""
		var raw := String(beat.get("say", ""))
		if not shown.is_empty() and shown != raw:
			lines.append('  - _displayed (corrupted):_ "%s"' % shown)
	lines.append("")
	(
		lines
		. append(
			(
				'- `read`=%s · `music`=%s · `fx`=%s · `action`=%s · dev-only `inner`: "%s"'
				% [
					String(record["read"]),
					String(record["music"]),
					String(record["fx"]),
					String(record["action"]),
					String(record["inner"]),
				]
			)
		)
	)
	lines.append(_meters_line(record))
	lines.append(_mood_line(record))
	lines.append("- dose: %s" % _dose_text(record.get("dose", {})))
	lines.append(_metrics_line(record))
	lines.append_array(_annotation_lines(record))
	lines.append("")
	return lines


func night_lines(
	report: Dictionary,
	screen: Array[String],
	path_events: Array[Dictionary],
	stage_events: Array[Dictionary]
) -> Array[String]:
	var lines: Array[String] = []
	var meters: Dictionary = report.get("meters", {})
	var stage: Dictionary = report.get("stage", {})
	var path: Dictionary = report.get("path", {})
	var event: Dictionary = report.get("event", {})
	lines.append("\n---\n")
	lines.append("## Night after day %d\n" % int(report.get("day_before", 0)))
	(
		lines
		. append(
			(
				"- meters: day %d → %d · burn +%.1f · instability %.1f → %.1f (floor %.1f)"
				% [
					int(meters.get("day_before", 0)),
					int(meters.get("day", 0)),
					float(meters.get("burn", 0.0)),
					float(meters.get("instability_before", 0.0)),
					float(meters.get("instability_after", 0.0)),
					float(meters.get("instability_floor", 0.0)),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				'- stage check: %d "%s" → %d "%s" (crossed: %s · EVENT queued: %d · band valid: %s)'
				% [
					int(stage.get("before", 0)),
					Stages.name_of(int(stage.get("before", 0))),
					int(stage.get("after", 0)),
					String(stage.get("name", "")),
					str(bool(stage.get("crossed", false))),
					int(stage.get("events_queued", 0)),
					str(bool(stage.get("valid", false))),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				(
					'- path check: "%s" → "%s" (locked: %s · assigned/locked now: %s/%s · '
					+ "runner-up: %s · rule valid: %s)"
				)
				% [
					String(path.get("before", "")),
					String(path.get("path", "")),
					str(bool(path.get("locked", false))),
					str(bool(path.get("assigned", false))),
					str(bool(path.get("locked_now", false))),
					String(path.get("runner_up", "")),
					str(bool(path.get("valid", false))),
				]
			)
		)
	)
	lines.append("- path scores: %s" % _scores_text(path.get("scores", {})))
	(
		lines
		. append(
			(
				'- overnight event: %s "%s" (kind %s)'
				% [
					String(event.get("id", "none")),
					String(event.get("title", "")),
					String(event.get("kind", "")),
				]
			)
		)
	)
	lines.append("- screen:")
	for text: String in screen:
		lines.append("  - %s" % text)
	for entry: Dictionary in stage_events:
		(
			lines
			. append(
				(
					'- **stage transition** %d → %d "%s" (night crossing%s)'
					% [
						int(entry.get("from", 0)),
						int(entry.get("to", 0)),
						String(entry.get("name", "")),
						_relaunch_text(entry),
					]
				)
			)
		)
		var event_line := Stages.event_line(int(entry.get("to", 0)))
		if not event_line.is_empty():
			lines.append("  - queued for the next prompt: %s" % event_line)
	for entry: Dictionary in path_events:
		(
			lines
			. append(
				(
					"- **path** %s %s during the night (stage %d)"
					% [
						"LOCKED to" if bool(entry.get("locked", false)) else "soft-assigned",
						String(entry.get("path", "")),
						int(entry.get("stage", 0)),
					]
				)
			)
		)
	(
		lines
		. append(
			(
				"- autosave: `SaveSystem` scene `night` · campaign_over %s · next scenario %s"
				% [
					str(bool(report.get("campaign_over", false))),
					String((report.get("next_scenario", {}) as Dictionary).get("id", "none")),
				]
			)
		)
	)
	lines.append("")
	return lines


func summary_lines(
	reason: String, final: Dictionary, wall_s: float, is_checkpoint := false
) -> Array[String]:
	var latencies: Array[float] = []
	for record: Dictionary in records:
		latencies.append(
			float((record.get("metrics", {}) as Dictionary).get("total_ms", 0)) / 1000.0
		)
	latencies.sort()
	var lines: Array[String] = []
	lines.append("\n---\n")
	if is_checkpoint:
		lines.append("## Checkpoint summary\n")
		lines.append(
			"- checkpoint: %s · wall time %.0f s (%.1f min)" % [reason, wall_s, wall_s / 60.0]
		)
	else:
		lines.append("## Run summary\n")
		lines.append(
			"- finished: %s · wall time %.0f s (%.1f min)" % [reason, wall_s, wall_s / 60.0]
		)
	lines.append(
		(
			"- turns recorded: %d · broken turns: %d · dates played: %d"
			% [records.size(), broken.size(), _date_count()]
		)
	)
	(
		lines
		. append(
			(
				'- final: day %d · stage %d "%s" · path %s · instability %.1f (peak %.1f, floor %.1f)'
				% [
					int(final.get("day", 0)),
					int(final.get("stage", 0)),
					Stages.name_of(int(final.get("stage", 0))),
					_path_final(final),
					float(final.get("instability", 0.0)),
					float(final.get("instability_peak", 0.0)),
					float(final.get("instability_floor", 0.0)),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"- turn latency: median %.1f s · p95 %.1f s · max %.1f s"
				% [
					_pct(latencies, 0.5),
					_pct(latencies, 0.95),
					latencies[-1] if not latencies.is_empty() else 0.0,
				]
			)
		)
	)
	lines.append("- stage transitions: %s" % _transitions_text())
	lines.append("- path decisions: %s" % _path_decisions_text())
	lines.append("- triggers fired: %s" % _triggers_text())
	lines.append(
		(
			"- inner leaks shown: %d · safety redaction spans: %d · turns with bars on screen: %d"
			% [leak_log.size(), redaction_log.size(), _bar_turns()]
		)
	)
	lines.append(
		(
			"- memory: %d fact(s) stored · %d corruption(s) logged"
			% [int(final.get("memory_count", 0)), _corruption_total()]
		)
	)
	if not broken.is_empty():
		lines.append("- **broken turns:**")
		for entry: Dictionary in broken:
			(
				lines
				. append(
					(
						"  - day %d · turn %d · `%s` %s"
						% [
							int(entry.get("day", 0)),
							int(entry.get("turn", 0)),
							String(entry.get("code", "")),
							String(entry.get("message", "")),
						]
					)
				)
			)
	lines.append("")
	return lines


## ── Turn blocks ──────────────────────────────────────────────────────────────


func _meters_line(record: Dictionary) -> String:
	var meters: Dictionary = record.get("meters", {})
	return (
		(
			"- meters: affection %.1f · trust %.1f · instability %.1f (peak %.1f, floor %.1f) "
			+ "· fixation %.1f · lucidity %.1f"
		)
		% [
			float(meters.get("affection", 0.0)),
			float(meters.get("trust", 0.0)),
			float(meters.get("instability", 0.0)),
			float(meters.get("instability_peak", 0.0)),
			float(meters.get("instability_floor", 0.0)),
			float(meters.get("fixation", 0.0)),
			float(meters.get("lucidity", 0.0)),
		]
	)


func _mood_line(record: Dictionary) -> String:
	var mood: Variant = record.get("mood", {})
	var landed: Variant = (record.get("ledger", {}) as Dictionary).get("mood", {})
	if not mood is Dictionary or (mood as Dictionary).is_empty():
		return "- mood: none (the model suggested no meter move)"
	var parts := PackedStringArray()
	for key: Variant in mood:
		parts.append("%s %s" % [str(key), _int_text(mood[key])])
	var out := "- mood: " + " · ".join(parts)
	if landed is Dictionary and not (landed as Dictionary).is_empty():
		var moved := PackedStringArray()
		for key: Variant in landed:
			moved.append("%s %+.1f" % [str(key), float(landed[key])])
		out += " → landed " + " · ".join(moved)
	return out


func _metrics_line(record: Dictionary) -> String:
	var metrics: Dictionary = record.get("metrics", {})
	var timings: Dictionary = metrics.get("timings", {})
	var ledger: Dictionary = record.get("ledger", {})
	var burn := float(ledger.get("slow_burn", 0.0))
	var prompt_tokens := int(timings.get("prompt_n", 0)) + int(timings.get("cache_n", 0))
	return (
		(
			"- prompt %d tok (%d cached) · output %d tok · first token %d ms "
			+ "· %.1f tok/s · total %.1f s · slow burn %+.2f"
		)
		% [
			prompt_tokens,
			int(timings.get("cache_n", 0)),
			int(timings.get("predicted_n", 0)),
			int(metrics.get("first_token_ms", -1)),
			float(timings.get("predicted_per_second", 0.0)),
			float(metrics.get("total_ms", 0)) / 1000.0,
			burn,
		]
	)


func _annotation_lines(record: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for entry: Variant in record.get("stage_events", []):
		var cross: Dictionary = entry
		var spec: Dictionary = cross.get("spec", {})
		(
			lines
			. append(
				(
					'- **stage transition** %d → %d "%s" (glitch %.1f s, fx %s, cue %s%s)'
					% [
						int(cross.get("from", 0)),
						int(cross.get("to", 0)),
						String(cross.get("name", "")),
						float(spec.get("duration_s", 0.0)),
						String(spec.get("fx", "")),
						String(spec.get("cue", "")),
						_relaunch_text(cross),
					]
				)
			)
		)
		var line := Stages.event_line(int(cross.get("to", 0)))
		if not line.is_empty():
			lines.append("  - queued for the next prompt: %s" % line)
	for entry: Variant in record.get("path_events", []):
		var decision: Dictionary = entry
		(
			lines
			. append(
				(
					"- **path** %s %s at stage %d · scores %s"
					% [
						"LOCKED to" if bool(decision.get("locked", false)) else "soft-assigned",
						String(decision.get("path", "")),
						int(decision.get("stage", 0)),
						_scores_text(decision.get("scores", {})),
					]
				)
			)
		)
	for entry: Variant in record.get("triggers", []):
		lines.append(_trigger_line(entry as Dictionary))
	for entry: Variant in record.get("redactions", []):
		var red: Dictionary = entry
		(
			lines
			. append(
				(
					'- **safety** redacted `%s` in %s ("%s")'
					% [
						String(red.get("category", "")),
						String(red.get("source", "")),
						String(red.get("matched", "")),
					]
				)
			)
		)
	var bars := int(record.get("bars", 0))
	if bars > 0:
		lines.append(
			"- **bars in displayed text:** %d glyph(s) (safety + corruption `redact`)" % bars
		)
	var leak: Dictionary = record.get("leak", {})
	if not leak.is_empty():
		(
			lines
			. append(
				(
					'- **inner leak** (stage %d, style %s, reveal %s): "%s"'
					% [
						int(leak.get("stage", 0)),
						String(leak.get("style", "")),
						String(leak.get("reveal", "")),
						String(leak.get("text", "")),
					]
				)
			)
		)
	var proposal: Dictionary = record.get("memory_proposal", {})
	if bool(proposal.get("accepted", false)):
		lines.append('- **memory** stored "%s"' % String(proposal.get("text", "")))
	var corruptions: Variant = record.get("memory_corruptions", [])
	if corruptions is Array and not (corruptions as Array).is_empty():
		lines.append("- **memory corruption** (%d fact(s)):" % (corruptions as Array).size())
		for item: Variant in corruptions:
			lines.append("  - %s" % _corruption_text(item))
	return lines


func _trigger_line(trig: Dictionary) -> String:
	var effects: Array[String] = []
	var payload: Dictionary = trig.get("effects", {})
	var meters: Dictionary = payload.get("meters", {})
	for meter: Variant in meters:
		effects.append("%s %+.1f" % [str(meter), float(meters[meter])])
	var path: Dictionary = payload.get("path", {})
	for key: Variant in path:
		effects.append("path %s %+.1f" % [str(key), float(path[key])])
	var profile: Dictionary = payload.get("profile", {})
	for key: Variant in profile:
		effects.append("%s +%d" % [str(key), int(profile[key])])
	var flags: Dictionary = payload.get("flags", {})
	for key: Variant in flags:
		effects.append("flag %s=%s" % [str(key), str(flags[key])])
	return (
		'- **trigger** %s %s ×%d (%s, ×%.2f) → %s · line: "%s"'
		% [
			String(trig.get("id", "")),
			String(trig.get("name", "")),
			int(trig.get("step", 0)),
			String(trig.get("agreement", "")),
			float(trig.get("strength", 0.0)),
			", ".join(effects) if not effects.is_empty() else "no game-side effect",
			String(trig.get("line", "")),
		]
	)


## ── Small helpers ────────────────────────────────────────────────────────────


func _beat_line(beat: Dictionary, dash: bool) -> String:
	var body := (
		'**%s/%s** (cue: %s) — "%s"'
		% [
			String(beat.get("feeling", "?")),
			_int_text(beat.get("intensity", "?")),
			String(beat.get("cue", "none")),
			String(beat.get("say", "")),
		]
	)
	return ("- " + body) if dash else body


func _int_text(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)


func _path_text() -> String:
	var path := str(GameState.path)
	if path.is_empty():
		return "none"
	return "%s (%s)" % [path, "locked" if bool(GameState.path_locked) else "soft"]


func _path_final(final: Dictionary) -> String:
	var path := String(final.get("path", ""))
	if path.is_empty():
		return "none"
	return "%s (%s)" % [path, "locked" if bool(final.get("path_locked", false)) else "soft"]


func _dose_text(dose: Variant) -> String:
	if not dose is Dictionary or (dose as Dictionary).is_empty():
		return "none"
	var parts := PackedStringArray()
	for key: Variant in dose:
		parts.append("%s %.1f" % [str(key), float(dose[key])])
	return " · ".join(parts)


func _scores_text(scores: Variant) -> String:
	if not scores is Dictionary or (scores as Dictionary).is_empty():
		return "none"
	var parts := PackedStringArray()
	for key: Variant in scores:
		parts.append("%s %s" % [str(key), _int_text(scores[key])])
	return " · ".join(parts)


func _corruption_text(item: Variant) -> String:
	if item is Dictionary:
		var entry: Dictionary = item
		var before := String(entry.get("before", entry.get("fact", "")))
		var after := String(entry.get("after", entry.get("corrupted", "")))
		if after.is_empty():
			return before
		return '"%s" → "%s"' % [before, after]
	return str(item)


func _corruption_total() -> int:
	var total := 0
	for record: Dictionary in records:
		total += (record.get("memory_corruptions", []) as Array).size()
	return total


func _bar_turns() -> int:
	var count := 0
	for record: Dictionary in records:
		if int(record.get("bars", 0)) > 0:
			count += 1
	return count


func _date_count() -> int:
	var days := {}
	for record: Dictionary in records:
		days[int(record.get("day", 0))] = true
	for night: Dictionary in nights:
		days[int((night.get("report", {}) as Dictionary).get("day_before", 0))] = true
	return days.size()


func _transitions_text() -> String:
	if transitions.is_empty():
		return "none"
	var parts := PackedStringArray()
	for entry: Dictionary in transitions:
		var txt := (
			"day %d: %d→%d %s"
			% [
				int(entry.get("day", 0)),
				int(entry.get("from", 0)),
				int(entry.get("to", 0)),
				String(entry.get("name", "")),
			]
		)
		if entry.has("relaunch"):
			var rel: Dictionary = entry.get("relaunch", {})
			if bool(rel.get("ok", false)):
				txt += " (relaunch ok)"
			else:
				txt += " (relaunch %s)" % String(rel.get("error", {}).get("code", "refused"))
		parts.append(txt)
	return " · ".join(parts)


func _relaunch_text(entry: Dictionary) -> String:
	if not entry.has("relaunch"):
		return ""
	var rel: Dictionary = entry.get("relaunch", {})
	if bool(rel.get("ok", false)):
		return " · relaunch %d ms ok" % int(rel.get("ms", 0))
	var err: Dictionary = rel.get("error", {})
	var code := String(err.get("code", "unknown"))
	return " · relaunch refused (%s)" % code


func _path_decisions_text() -> String:
	if path_log.is_empty():
		return "none"
	var parts := PackedStringArray()
	for entry: Dictionary in path_log:
		(
			parts
			. append(
				(
					"%s %s (day %d)"
					% [
						String(entry.get("path", "")),
						"locked" if bool(entry.get("locked", false)) else "soft",
						int(entry.get("day", 0)),
					]
				)
			)
		)
	return " · ".join(parts)


func _triggers_text() -> String:
	var counts := {}
	for entry: Dictionary in trigger_log:
		var id := String(entry.get("id", ""))
		counts[id] = int(counts.get(id, 0)) + 1
	if counts.is_empty():
		return "none"
	var parts := PackedStringArray()
	for key: Variant in counts:
		parts.append("%s×%d" % [str(key), int(counts[key])])
	return " · ".join(parts)


func _pct(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(round(fraction * float(values.size() - 1))), 0, values.size() - 1)
	return values[index]
