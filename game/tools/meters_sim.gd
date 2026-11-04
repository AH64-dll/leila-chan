extends SceneTree
## P2.01 dev tool — the 100-turn meters simulation behind
## production/handoffs/media/P2.01/meters_curve.{csv,svg,png}.
##
## It drives the real GameState/Meters code (no formula re-implementation): a
## fixed 14-day, 100-turn player model feeds scripted `read` labels and moods
## through GameState.apply_turn_meters()/apply_read(), the night roll-over adds
## the daily burn, and every turn is written as one CSV row.
##
## Run through the wrapper (Godot + plot + PNG):
##   tools/meters/sim.sh
## or directly:
##   ./tools/godot.sh --headless --path game --script res://tools/meters_sim.gd \
##     -- --out=production/handoffs/media/P2.01/meters_curve.csv
##
## Determinism: the seed and the player model below are constants, so the same
## checkout always produces the same curve (`tools/test.sh` does not run this —
## the committed CSV is validated by tests/test_meters.py instead).

const GameStateScript := preload("res://autoload/GameState.gd")

const SEED := 20261104
## 14 days, 100 turns: two 8-turn days then twelve 7-turn days.
const TURNS_PER_DAY: Array[int] = [8, 8, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]

## Scenario inputs, not game rules: how this imaginary player's 100 turns move
## Fixation and Lucidity (P2.08/P2.12 will drive them from triggers and reads).
const FIXATION_BASE := 12.0
const FIXATION_PER_TURN := 0.8
const LUCIDITY_BASE := 30.0
const LUCIDITY_DECAY := 0.35
const LUCIDITY_KINDNESS := 0.6

## The behaviour drift: warm first, provocative in the middle, cold at the end.
const EARLY_READS: Array[String] = [
	"greeting", "flirt", "compliment", "question", "small_talk", "affection"
]
const MID_READS: Array[String] = [
	"tease", "jealousy_bait", "leaving", "cold", "question", "apology", "small_talk"
]
const LATE_READS: Array[String] = [
	"jealousy_bait", "insult", "leaving", "meta", "cold", "boundary", "question"
]
const KIND_READS: Array[String] = ["apology", "boundary", "question", "small_talk"]

## docs/02 §1.2 labels → the mood ints this player model draws (docs/02 §1.1).
## Jitter ±1, clamped to −3..3; the game still owns the scaling and the caps.
const MOOD_BY_READ := {
	"greeting": {"affection": 1, "trust": 1, "stress": -1},
	"flirt": {"affection": 2, "trust": 1, "stress": 0},
	"compliment": {"affection": 2, "trust": 0, "stress": -1},
	"gift": {"affection": 2, "trust": 1, "stress": 0},
	"question": {"affection": 0, "trust": 1, "stress": 0},
	"small_talk": {"affection": 1, "trust": 0, "stress": 0},
	"tease": {"affection": 1, "trust": 0, "stress": 1},
	"insult": {"affection": -2, "trust": -2, "stress": 2},
	"apology": {"affection": 0, "trust": 1, "stress": -1},
	"leaving": {"affection": -1, "trust": -1, "stress": 2},
	"jealousy_bait": {"affection": -1, "trust": -2, "stress": 3},
	"meta": {"affection": 0, "trust": 0, "stress": 2},
	"boundary": {"affection": 0, "trust": 1, "stress": -1},
	"cold": {"affection": -2, "trust": -1, "stress": 1},
	"affection": {"affection": 3, "trust": 1, "stress": 0},
	"scared": {"affection": 0, "trust": 1, "stress": 1},
	"other": {"affection": 0, "trust": 0, "stress": 0},
}
const MOOD_FIELDS: Array[String] = ["affection", "trust", "stress"]

const HEADER := (
	"turn,day,read,instability_pre,affection,trust,instability,instability_peak,"
	+ "instability_floor,fixation,lucidity,stage,slow_burn,mood_affection,mood_trust,"
	+ "mood_stress,day_burn"
)

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var out_path := _out_path()
	var state: Variant = GameStateScript.new()
	state.reset()
	_rng.seed = SEED
	var rows: Array[String] = [HEADER]
	var kindness := 0
	var turn := 0
	for day_index: int in TURNS_PER_DAY.size():
		var turns_today := TURNS_PER_DAY[day_index]
		for turn_today: int in turns_today:
			turn += 1
			var read := _pick_read(turn)
			var mood := _mood_for(read)
			_step_scenario_meters(state, turn, kindness)
			var instability_pre: float = state.instability
			var ledger: Dictionary = state.apply_turn_meters({"mood": mood})
			state.apply_read(StringName(read))
			if KIND_READS.has(read):
				kindness += 1
			var day_burn := 0.0
			if turn_today == turns_today - 1:
				day_burn = state.advance_day()
			rows.append(_row(turn, day_index + 1, read, instability_pre, state, ledger, day_burn))
	if not _write(out_path, rows):
		state.free()
		quit(1)
		return
	print(
		(
			"meters_sim: %d turns over %d days -> %s (instability %.1f, stage %d)"
			% [turn, TURNS_PER_DAY.size(), out_path, state.instability, state.stage]
		)
	)
	state.free()
	quit(0)


## The scenario's time and kindness move Fixation/Lucidity (see the constants).
func _step_scenario_meters(state: Variant, turn: int, kindness: int) -> void:
	var fixation := FIXATION_BASE + FIXATION_PER_TURN * turn + 0.1 * float(state.affection)
	var lucidity := LUCIDITY_BASE - LUCIDITY_DECAY * turn + LUCIDITY_KINDNESS * kindness
	state.set_meter(&"fixation", minf(100.0, fixation))
	state.set_meter(&"lucidity", clampf(lucidity, 0.0, 100.0))


func _pick_read(turn: int) -> String:
	var pool: Array[String] = LATE_READS
	if turn <= 28:
		pool = EARLY_READS
	elif turn <= 62:
		pool = MID_READS
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _mood_for(read: String) -> Dictionary:
	var base: Dictionary = MOOD_BY_READ.get(read, MOOD_BY_READ["other"])
	var mood := {}
	for field: String in MOOD_FIELDS:
		mood[field] = clampi(int(base[field]) + _rng.randi_range(-1, 1), -3, 3)
	return mood


func _row(
	turn: int,
	day: int,
	read: String,
	instability_pre: float,
	state: Variant,
	ledger: Dictionary,
	day_burn: float
) -> String:
	var landed: Dictionary = ledger.get("mood", {})
	return (
		"%d,%d,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.3f"
		% [
			turn,
			day,
			read,
			instability_pre,
			float(state.affection),
			float(state.trust),
			float(state.instability),
			float(state.instability_peak),
			float(state.instability_floor),
			float(state.fixation),
			float(state.lucidity),
			int(state.stage),
			float(ledger.get("slow_burn", 0.0)),
			float(landed.get(&"affection", 0.0)),
			float(landed.get(&"trust", 0.0)),
			float(landed.get(&"instability", 0.0)),
			day_burn,
		]
	)


func _write(path: String, rows: Array[String]) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr(
			"meters_sim: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		)
		return false
	file.store_string("\n".join(rows) + "\n")
	file.close()
	return true


func _out_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.trim_prefix("--out=")
	return "user://meters_curve.csv"
