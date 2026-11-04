class_name OvernightEvents
extends RefCounted
## OvernightEvents — docs/01 §6.3's between-days screens: which night event plays,
## and the per-stage lines it renders.
##
## Split from the night loop the way Stages was split from GameState: NightLoop
## owns the order of the night's checks, this owns the content and the selection
## rule, and both the numbers and the prose live in res://data/night.json.
## Everything here is pure except the table load.
##
## A missing or broken file degrades to NO event (the night still passes): the
## loader never guesses prose, so a hand-edited table can lose an event but can
## never invent one.

const TABLE_PATH := "res://data/night.json"

## The docs/01 §6.3 catalogue, verbatim. This phase ships N01 and N12 (P5.03/P5.04
## own the other ten and their generated content), so the ids are the contract a
## row is validated against: a typo cannot invent a thirteenth overnight.
const DOCS_IDS: Array[String] = [
	"N01",
	"N02",
	"N03",
	"N04",
	"N05",
	"N06",
	"N07",
	"N08",
	"N09",
	"N10",
	"N11",
	"N12",
]

## The renderers this phase ships: "messages" (a feed of timed texts) and "black"
## (a held black screen, then the morning line). A row with any other kind is
## dropped with a warning rather than rendered as nothing.
const KINDS: Array[String] = ["messages", "black"]

## Used when the data file carries no usable number: the night still advances
## after a short beat instead of freezing the loop. Prose has no fallback.
const DEFAULT_SKIP_AFTER_S := 3.0
const DEFAULT_HOLD_S := 2.5
const DEFAULT_MESSAGE_INTERVAL_S := 1.6

const EMPTY_TABLE := {
	"screen":
	{
		"day_label": "",
		"night_label": "",
		"morning_line": "",
		"skip_hint": "",
		"message_format": "",
		"skip_after_s": DEFAULT_SKIP_AFTER_S,
		"hold_s": DEFAULT_HOLD_S,
	},
	"events": [],
}

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## Test hook: install a parsed document as the live table. A synthetic night whose
## rows are stage-gated is how the tests prove the event is chosen from the state
## the night's own checks produced; clear_cache() restores the shipped file.
static func use_document(parsed: Variant) -> void:
	_table_cache = parse_document(parsed)


## The merged table. READ-ONLY: it is shared, and a night reads it once.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table()
	return _table_cache


## The chrome every night shares (labels, skip hint, hold). READ-ONLY.
static func screen() -> Dictionary:
	return table()["screen"]


## Every usable event row, in file order. READ-ONLY.
static func events() -> Array:
	return table()["events"]


## One event by id, as a copy ("" when the table has no such row).
static func get_event(id: String) -> Dictionary:
	var key := id.strip_edges().to_upper()
	for event: Dictionary in events():
		if String(event.get("id", "")) == key:
			return event.duplicate(true)
	return {}


## docs/01 §6.3 availability: the same contract as a scenario's (`days`, `stages`,
## `paths`), matched against the day the night closed and the state the night's
## checks produced. Delegated to ScenarioLoader so a scenario and an overnight
## can never disagree about what "available" means.
static func is_available(event: Dictionary, day: int, stage: int, path := "") -> bool:
	return ScenarioLoader.is_available(event, day, stage, path)


## Picks the night's event from everything available at this state: a `once` row
## that already played is out, weight 0 is out, and one row is drawn by weight.
## Deterministic for a given rng (a fixed seed when none is injected), so a night
## replays identically from the same state. {} when nothing is available.
static func select(
	day: int, stage: int, path := "", rng: RandomNumberGenerator = null, played: Array = []
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total := 0.0
	for event: Dictionary in events():
		if not is_available(event, day, stage, path):
			continue
		if bool(event.get("once", false)) and _has(played, String(event.get("id", ""))):
			continue
		var weight := _weight_of(event)
		if weight <= 0.0:
			continue
		candidates.append(event)
		total += weight
	if candidates.is_empty():
		return {}
	var picker := rng
	if picker == null:
		picker = RandomNumberGenerator.new()
		picker.seed = day
	var roll := picker.randf() * total
	for event: Dictionary in candidates:
		roll -= _weight_of(event)
		if roll <= 0.0:
			return event.duplicate(true)
	return candidates[candidates.size() - 1].duplicate(true)


## The rows one event shows at `stage` on `path`: the highest stage variant that
## is not above the current stage (the scenario stage_variants fallback), plus the
## path's extra line when the data has one. `{player_name}` is resolved here.
static func messages(
	event: Dictionary, stage: int, path := "", player_name := "Senpai"
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var variants: Variant = event.get("stage_variants", {})
	if variants is Dictionary:
		var key := _stage_key_for(variants, stage)
		if not key.is_empty():
			for item: Variant in (variants as Dictionary)[key]:
				out.append(_row(item, player_name))
	var path_variants: Variant = event.get("path_variants", {})
	if path_variants is Dictionary and (path_variants as Dictionary).has(path):
		var row := _row((path_variants as Dictionary)[path], player_name)
		if not String(row["text"]).is_empty():
			out.append(row)
	return out


## Parses a night document into the canonical table — data-driven on purpose: a
## test hands it a synthetic document and proves the loader (not a hard-coded
## copy) decides availability and selection. Shape:
## {"screen": {labels, morning_line, skip_hint, skip_after_s, hold_s},
## "events": [{id, title, kind, available, weight, once, …kind payload}]}.
## An unusable row is dropped with a warning; the rest of the night still works.
static func parse_document(parsed: Variant) -> Dictionary:
	var out: Dictionary = EMPTY_TABLE.duplicate(true)
	if not parsed is Dictionary:
		push_warning("OvernightEvents: %s is not a JSON object; no overnight events" % TABLE_PATH)
		return out
	var document: Dictionary = parsed
	_merge_screen(out["screen"], document.get("screen"))
	var rows: Array = out["events"]
	var raw_events: Variant = document.get("events")
	if raw_events is Array:
		for item: Variant in raw_events:
			var event := _parse_event(item)
			if not event.is_empty():
				rows.append(event)
	out["events"] = rows
	return out


static func _load_table() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		push_warning("OvernightEvents: %s missing; the night passes with no event" % TABLE_PATH)
		return EMPTY_TABLE.duplicate(true)
	return parse_document(JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH)))


## One row, or {} when it cannot be rendered: an id docs/01 §6.3 does not name, a
## kind this build has no renderer for, or a payload the renderer cannot use.
static func _parse_event(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var source: Dictionary = item
	var id := String(source.get("id", "")).strip_edges().to_upper()
	if not DOCS_IDS.has(id):
		push_warning("OvernightEvents: dropping event with unknown id '%s'" % id)
		return {}
	var kind := String(source.get("kind", "")).strip_edges()
	if not KINDS.has(kind):
		push_warning("OvernightEvents: dropping %s — unknown kind '%s'" % [id, kind])
		return {}
	var title := String(source.get("title", "")).strip_edges()
	if title.is_empty():
		push_warning("OvernightEvents: dropping %s — no title" % id)
		return {}
	var available: Variant = source.get("available")
	if not available is Dictionary:
		push_warning("OvernightEvents: dropping %s — no available block" % id)
		return {}
	var event := {
		"id": id,
		"title": title,
		"kind": kind,
		"available": (available as Dictionary).duplicate(true),
		"weight": _weight_of(source),
		"once": bool(source.get("once", false)),
	}
	if kind == "messages":
		var variants := _parse_variants(source.get("stage_variants"))
		if variants.is_empty():
			push_warning("OvernightEvents: dropping %s — no usable stage_variants" % id)
			return {}
		event["stage_variants"] = variants
		event["message_interval_s"] = _seconds(
			source.get("message_interval_s"), DEFAULT_MESSAGE_INTERVAL_S
		)
		var path_rows := _parse_path_rows(source.get("path_variants"))
		if not path_rows.is_empty():
			event["path_variants"] = path_rows
	else:
		var duration := _seconds(source.get("duration_s"), 0.0)
		if duration <= 0.0:
			push_warning("OvernightEvents: dropping %s — the black screen has no duration" % id)
			return {}
		event["duration_s"] = duration
	# A present-but-null skip_after_s means "not skippable" (docs/01 §6.3's N12 is
	# a ten-second wait and the wait IS the event); an absent key uses the table's.
	if source.has("skip_after_s"):
		var raw_skip: Variant = source.get("skip_after_s")
		event["skip_after_s"] = (
			null if raw_skip == null else _seconds(raw_skip, DEFAULT_SKIP_AFTER_S)
		)
	var morning: Variant = source.get("morning_line")
	if morning is String and not String(morning).strip_edges().is_empty():
		event["morning_line"] = String(morning).strip_edges()
	return event


static func _merge_screen(target: Dictionary, source: Variant) -> void:
	if not source is Dictionary:
		return
	var spec: Dictionary = source
	for key: String in ["day_label", "night_label", "morning_line", "skip_hint", "message_format"]:
		var value: Variant = spec.get(key)
		if value is String:
			target[key] = value
	target["skip_after_s"] = _seconds(spec.get("skip_after_s"), DEFAULT_SKIP_AFTER_S)
	target["hold_s"] = _seconds(spec.get("hold_s"), DEFAULT_HOLD_S)


## {"0"…"5": [{time, text}, …]} — a stage key outside 0..5 or a row without text
## is skipped, so one bad block costs those lines only.
static func _parse_variants(value: Variant) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	for key: Variant in value:
		var stage := _stage_key(key)
		if stage < 0:
			continue
		var rows := _parse_rows(value[key])
		if not rows.is_empty():
			out[str(stage)] = rows
	return out


## {path_id: {time, text}} for the six canonical path ids only.
static func _parse_path_rows(value: Variant) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	for key: Variant in value:
		var path := String(key).strip_edges()
		if not ScenarioLoader.CANONICAL_PATHS.has(path):
			push_warning("OvernightEvents: dropping path variant '%s'" % path)
			continue
		var row := _row(value[key], "")
		if not String(row["text"]).is_empty():
			out[path] = row
	return out


static func _parse_rows(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not value is Array:
		return out
	for item: Variant in value:
		var row := _row(item, "")
		if not String(row["text"]).is_empty():
			out.append(row)
	return out


static func _row(item: Variant, player_name: String) -> Dictionary:
	if not item is Dictionary:
		return {"time": "", "text": ""}
	var source: Dictionary = item
	var text := String(source.get("text", ""))
	if not player_name.is_empty():
		text = text.replace("{player_name}", player_name)
	return {"time": String(source.get("time", "")).strip_edges(), "text": text.strip_edges()}


## The highest stage variant not above `stage` (the scenario fallback rule), or ""
## when the data defines none that low.
static func _stage_key_for(variants: Dictionary, stage: int) -> String:
	for candidate: int in range(clampi(stage, 0, Stages.max_stage()), -1, -1):
		var known := str(candidate)
		if variants.has(known):
			return known
	return ""


static func _stage_key(key: Variant) -> int:
	var text := str(key).strip_edges()
	if not text.is_valid_int():
		return -1
	var stage := int(text)
	if stage < 0 or stage > Stages.max_stage():
		return -1
	return stage


static func _weight_of(event: Dictionary) -> float:
	var weight: Variant = event.get("weight", 1.0)
	if weight is int or weight is float:
		var number := float(weight)
		if is_finite(number):
			return maxf(number, 0.0)
	return 1.0


static func _seconds(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		var number := float(value)
		if is_finite(number) and number >= 0.0:
			return number
	return fallback


static func _has(played: Array, id: String) -> bool:
	for item: Variant in played:
		if String(item) == id:
			return true
	return false
