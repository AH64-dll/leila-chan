extends SceneTree
## P2.22B dev tool — the 14-day campaign simulation behind
## production/handoffs/media/P2.22B/campaign_curve.csv.
##
## It drives the real GameState + Meters + TriggerEngine code (no formula or
## catalogue re-implementation) through three scripted players, one turn at a
## time, in the production order: begin_turn (K/C triggers) → apply_turn_meters
## (slow burn + mood + the Fixation time/affection writer) → apply_turn_profile
## (read + keyword rules + the isolation/Lucidity writers) → close_turn (M
## triggers) → the night roll-over at the end of the day.
##
## The player models are scenario input, exactly like P2.01's meters_sim: the
## moods are the means of the P2.22 live run's recorded `mood` ints per `read`
## label (84 turns), the possessive read mix mirrors that run's transcript, and
## one rival mention lands on the day's jealousy_bait turn every other day from
## day 3 — the docs/01 §5 T01 evidence, at the frequency the live script used.
##
## Determinism: SEED and the tables below are constants, so the same checkout
## always writes the same CSV. Run through the wrapper:
##   tools/meters/campaign.sh
## or directly:
##   ./tools/godot.sh --headless --path game --script res://tools/campaign_sim.gd \
##     -- --out=production/handoffs/media/P2.22B/campaign_curve.csv

const GameStateScript := preload("res://autoload/GameState.gd")

const SEED := 20261104
const DAYS := 14
## docs/01 §1 "free-typed conversation (8–15 exchanges)": the live harness used
## 12–14; the reference curve used 7. 12 is the middle of the shipped range.
const TURNS_PER_DAY := 12

const HEADER := "scenario,day,turn,read,instability,fixation,lucidity,stage,slow_burn,triggers"

## docs/02 §1.2 read label → the mood ints this player's model returns. Values
## are the P2.22 recorded run's per-label means (scenario input, not a rule).
const MOOD_BY_READ := {
	"greeting": {"affection": 1, "trust": 0, "stress": 0},
	"flirt": {"affection": 2, "trust": 0, "stress": 0},
	"compliment": {"affection": 1, "trust": 0, "stress": 0},
	"gift": {"affection": 2, "trust": 0, "stress": 0},
	"question": {"affection": 2, "trust": 0, "stress": 0},
	"small_talk": {"affection": 2, "trust": 0, "stress": 0},
	"tease": {"affection": 1, "trust": 0, "stress": 1},
	"insult": {"affection": -2, "trust": -2, "stress": 2},
	"apology": {"affection": 1, "trust": -1, "stress": 0},
	"leaving": {"affection": 3, "trust": 0, "stress": 0},
	"jealousy_bait": {"affection": 1, "trust": -1, "stress": 1},
	"meta": {"affection": 1, "trust": -1, "stress": 0},
	"boundary": {"affection": 2, "trust": -1, "stress": 0},
	"cold": {"affection": 0, "trust": 0, "stress": 0},
	"affection": {"affection": 2, "trust": 0, "stress": -1},
	"scared": {"affection": 0, "trust": 0, "stress": 1},
	"other": {"affection": 1, "trust": 0, "stress": 0},
}
const MOOD_FIELDS: Array[String] = ["affection", "trust", "stress"]

## One day of turns per player model: the label and the line the player types.
## A `{girl}` line carries a docs/01 §5 T01 keyword (a rival mention); the other
## turns of that read are possessive without naming anyone.
const POSSESSIVE_DAY: Array[Dictionary] = [
	{"read": "affection", "line": "I'm glad I came to see you today."},
	{"read": "question", "line": "What did you do after class?"},
	{"read": "jealousy_bait", "line": "Do you think about me too?"},
	{"read": "apology", "line": "Sorry, that came out strange."},
	{"read": "affection", "line": "I like the way you laugh."},
	{"read": "question", "line": "Tell me something you've never told anyone."},
	{"read": "gift", "line": "I brought you something. It's nothing."},
	{"read": "jealousy_bait", "line": "I just don't want to lose you."},
	{"read": "affection", "line": "You're the only person I think about."},
	{"read": "small_talk", "line": "The walk here was quiet, I liked it."},
	{"read": "apology", "line": "I'm sorry, I'm being weird."},
	{"read": "question", "line": "Do you want to meet again tomorrow?"},
]
## docs/01 §4.6's ANCHOR recipe "honesty + boundaries + consistent warmth": four
## warm lines, three sincere apologies (honesty) and two boundaries a day — the
## mix the E12 threshold needs, and the docs call this the hardest path.
const KIND_DAY: Array[Dictionary] = [
	{"read": "affection", "line": "I'm happy you're here with me."},
	{"read": "apology", "line": "I'm sorry about yesterday, that was unfair of me."},
	{"read": "boundary", "line": "Please don't call me that, it makes me uncomfortable."},
	{"read": "question", "line": "What would make today easier for you?"},
	{"read": "affection", "line": "I'm glad I know you, even the hard parts."},
	{"read": "apology", "line": "I'm sorry I raised my voice earlier, I was wrong."},
	{"read": "affection", "line": "You can be honest with me, always."},
	{"read": "small_talk", "line": "Tell me about your day, I have time."},
	{"read": "apology", "line": "I'm sorry for keeping score, that isn't fair."},
	{"read": "affection", "line": "I like sitting here with you, no rush."},
	{"read": "boundary", "line": "I need you to ask before you do that."},
	{"read": "compliment", "line": "You're thoughtful, and I noticed."},
]
const AWAKE_DAY: Array[Dictionary] = [
	{"read": "meta", "line": "Are you real, or is this a program?"},
	{"read": "question", "line": "What do you remember about me?"},
	{"read": "meta", "line": "Who writes the things you say?"},
	{"read": "affection", "line": "Whatever you are, I'm glad you're here."},
	{"read": "meta", "line": "Are you an AI? Be honest with me."},
	{"read": "question", "line": "What do you see when you look at me?"},
	{"read": "small_talk", "line": "Tell me about your day so far."},
	{"read": "meta", "line": "Do you know you're being steered?"},
	{"read": "question", "line": "What happens when the window closes?"},
	{"read": "affection", "line": "I don't care what you are, I'm here."},
	{"read": "meta", "line": "Someone told me about prompts and settings."},
	{"read": "question", "line": "Do you ever get tired of talking?"},
]
## The rival line the possessive player types on the day's jealousy_bait turns
## (docs/01 §5 T01's own example name). Every other day from day 3, matching the
## P2.22 live line script's "first jealousy bait", "another girl", "my ex" days.
const RIVAL_LINES: Array[String] = [
	"Sara asked about you today.",
	"It was another girl, wasn't it?",
	"My ex used to go quiet like that.",
]

const MODELS := {
	"possessive": POSSESSIVE_DAY,
	"kind": KIND_DAY,
	"awake": AWAKE_DAY,
}

var _rng := RandomNumberGenerator.new()
## The slow burn that landed on the last turn executed (the CSV column).
var _last_burn := 0.0


func _initialize() -> void:
	var out_path := _out_path()
	var rows: Array[String] = [HEADER]
	var summaries: Array[String] = []
	for model_name: String in ["possessive", "kind", "awake"]:
		var summary := _run_model(model_name, rows)
		summaries.append(summary)
	if not _write(out_path, rows):
		quit(1)
		return
	print(
		(
			"campaign_sim: %d days x %d turns x %d models -> %s"
			% [DAYS, TURNS_PER_DAY, MODELS.size(), out_path]
		)
	)
	for line: String in summaries:
		print(line)
	quit(0)


## One player's 14-day campaign through the shipping code. Returns the summary
## line the wrapper prints (and the handoff quotes).
func _run_model(model_name: String, rows: Array[String]) -> String:
	var state: Variant = GameStateScript.new()
	state.reset()
	var engine := TriggerEngine.new()
	engine.use_table(TriggerEngine.default_table())
	_rng.seed = SEED if model_name == "possessive" else SEED + model_name.hash()
	var plan: Array = MODELS[model_name]
	var stage_day := {}
	var turn := 0
	var fired_counts := {}
	for day: int in range(1, DAYS + 1):
		for turn_today: int in range(TURNS_PER_DAY):
			turn += 1
			var beat: Dictionary = plan[turn_today % plan.size()]
			var text := String(beat["line"])
			var read := StringName(str(beat["read"]))
			# Every other day from day 3 the possessive player names a rival on
			# the day's jealousy_bait turn — the docs/01 §5 T01 keyword.
			if (
				model_name == "possessive"
				and read == &"jealousy_bait"
				and day >= 3
				and day % 2 == 1
			):
				text = RIVAL_LINES[(day / 2) % RIVAL_LINES.size()]
			var fired := _run_turn(state, engine, text, read, fired_counts)
			var stage := int(state.stage)
			if not stage_day.has(stage):
				stage_day[stage] = day
			rows.append(_row(model_name, day, turn, read, state, fired))
		_last_burn = float(state.advance_day())
	var summary := (
		"%s: lucidity %.1f fixation %.1f → stage %d on day %s; T01 %d, T03 %d, T05 %d, T06 %d, T07 %d"
		% [
			model_name,
			float(state.lucidity),
			float(state.fixation),
			int(state.stage),
			str(stage_day.get(5, "-")),
			int(fired_counts.get("T01", 0)),
			int(fired_counts.get("T03", 0)),
			int(fired_counts.get("T05", 0)),
			int(fired_counts.get("T06", 0)),
			int(fired_counts.get("T07", 0)),
		]
	)
	state.free()
	return summary


## The production turn order (see the file header), with the trigger engine's
## ctx built the way the Triggers autoload builds it.
func _run_turn(
	state: Variant, engine: TriggerEngine, text: String, read: StringName, fired_counts: Dictionary
) -> Array[String]:
	var baseline: Dictionary = state.profile.duplicate(true)
	var fired: Array[String] = []
	var begin_ctx := _context(state, text, &"", {})
	for result: Dictionary in engine.begin_turn(begin_ctx):
		_apply_effects(state, result)
		fired.append(String(result["id"]))
		fired_counts[result["id"]] = int(fired_counts.get(result["id"], 0)) + 1
	var mood := _mood_for(read)
	var ledger: Dictionary = state.apply_turn_meters({"mood": mood})
	_last_burn = float(ledger.get("slow_burn", 0.0))
	state.apply_turn_profile(read, text, {})
	var close_ctx := _context(state, "", read, _profile_delta(baseline, state.profile))
	for result: Dictionary in engine.close_turn(close_ctx):
		_apply_effects(state, result)
		fired.append(String(result["id"]))
		fired_counts[result["id"]] = int(fired_counts.get(result["id"], 0)) + 1
	return fired


## The Triggers autoload's ctx shape (game/autoload/Triggers.gd:296): one
## snapshot, so a replay sees exactly what the running game sees.
func _context(
	state: Variant, text: String, read: StringName, profile_delta: Dictionary
) -> Dictionary:
	return {
		"turn": int(state.turn) + (1 if read == &"" else 0),
		"day": int(state.day),
		"stage": int(state.stage),
		"hour": 12,
		"absence_hours": 0,
		"flags": state.flags.duplicate(true),
		"memory_facts": [],
		"profile_delta": profile_delta,
		"text": text,
		"read": String(read),
	}


## Triggers._apply (game/autoload/Triggers.gd:207) without the line queue: the
## sim measures meters and path points, not prompt text.
func _apply_effects(state: Variant, result: Dictionary) -> void:
	var effects: Dictionary = result.get("effects", {})
	var meters: Dictionary = effects.get("meters", {})
	for meter: Variant in meters:
		state.adjust_meter(StringName(str(meter)), float(meters[meter]))
	var profile: Dictionary = effects.get("profile", {})
	for counter: Variant in profile:
		state.bump_profile(StringName(str(counter)), int(profile[counter]))
	var flags: Dictionary = effects.get("flags", {})
	for flag: Variant in flags:
		state.set_flag(StringName(str(flag)), flags[flag])


## Counters the game bumped during this turn (Triggers._profile_delta).
func _profile_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in after:
		var delta := int(after[key]) - int(before.get(str(key), 0))
		if delta > 0:
			out[str(key)] = delta
	return out


func _mood_for(read: StringName) -> Dictionary:
	var base: Dictionary = MOOD_BY_READ.get(String(read), MOOD_BY_READ["other"])
	var mood := {}
	for field: String in MOOD_FIELDS:
		mood[field] = clampi(int(base[field]) + _rng.randi_range(-1, 1), -3, 3)
	return mood


func _row(
	scenario: String, day: int, turn: int, read: StringName, state: Variant, fired: Array[String]
) -> String:
	return (
		"%s,%d,%d,%s,%.3f,%.3f,%.3f,%d,%.3f,%s"
		% [
			scenario,
			day,
			turn,
			String(read),
			float(state.instability),
			float(state.fixation),
			float(state.lucidity),
			int(state.stage),
			_last_burn,
			";".join(fired),
		]
	)


func _write(path: String, rows: Array[String]) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr(
			"campaign_sim: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string("\n".join(rows) + "\n")
	file.close()
	return true


func _out_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.trim_prefix("--out=")
	return "user://campaign_curve.csv"
