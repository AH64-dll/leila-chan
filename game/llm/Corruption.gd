class_name Corruption
extends RefCounted
## Corruption — the docs/07 §3.4 text filter, one stage-gated pipeline:
##
##     say chunk → Safety.scan → PronounFix → Corruption.filter(stage, path) → Typewriter
##
## This file holds everything pure and deterministic: the effect table, the
## gate/plan resolution, the seeded RNG derivation, and the per-word / per-beat
## text primitives. `CorruptionSession` (res://llm/CorruptionSession.gd) is the
## thin streaming adapter the ChatUI drives; it must not invent text rules of
## its own. `Corruption` never touches a node, so every rule here is unit
## testable without a scene tree.
##
## Effects and gates (docs/01 §3 "Text FX" column, docs/07 §3.4):
##   stage 1+  hesitation pauses          ("…" at a word boundary)
##   stage 2+  strike-through self-corrections ("h̸a̸t̸e̸ — no, love")
##   stage 3+  word repetition / wrong name
##   stage 4+  zalgo bursts / redaction bars
##   stage 5   text bleed / reversed lines
##
## Rules that are code, not data:
## - a data file can raise an effect's gate but never lower it (`_normalize`);
## - stages 0–3 stay readable (see the readability test: the strike keeps the
##   original word, repetition only doubles words, the wrong-name swap only
##   touches a name, and no glyph-destroying effect appears before stage 4);
## - `Settings.content_level = calmer` caps the effective stage at 3
##   (docs/02 §8), so a calmer run never reaches zalgo/redaction/bleed/reverse;
## - reduced motion switches off the two effects whose whole point is visual
##   jitter/smear (data `reduced_motion.disable`), never the textual ones.
##
## Seeding: `seed_for(turn, beat, stage)` is a hash of the three values, so a
## transcript replay re-derives the same seed per beat without storing extra
## state. The numbers live in res://data/corruption.json; DOCS_TABLE below is
## the in-code fallback, so a broken file degrades to the documented table.

const TABLE_PATH := "res://data/corruption.json"

## docs/01 §3 + docs/07 §3.4, in pipeline order. The order also fixes the RNG
## draw order, so data retuning can move chances but never reshuffle a replay.
const EFFECT_ORDER: Array[String] = [
	"hesitate", "strike", "repeat", "wrong_name", "zalgo", "redact", "bleed", "reverse"
]

## docs/02 §8: calmer mode caps the stage at 3 (the ceiling of "readable").
const CALMER_LEVEL := "calmer"
const CALMER_MAX_STAGE := 3
const STAGE_MIN := 0
const STAGE_MAX := 5

## Safety.gd's redaction character (P1.19). Corruption redactions look exactly
## like a safety redaction on purpose (docs/01 §3: "redactions █████").
const REDACT_CHAR := "█"

## The combining marks the shipped Open Sans UI font (plus system fallback)
## actually renders at 13 px: U+0338 is the stain-through slash, U+0332 the
## low line used by the bleed echo, and the three zalgo marks are the ones the
## font carries with sane metrics (U+0336 and friends render as tofu/offsets).
const STRIKE_MARK := "\u0338"
const BLEED_MARK := "\u0332"
const DOCS_ZALGO_MARKS: Array[String] = ["\u0300", "\u0301", "\u0308"]

## docs values as code: the same numbers as data/corruption.json. Tests pin
## the two together (`test_data_file_carries_the_docs_table`), so tuning one
## without the other is a red suite, not a silent drift.
const DOCS_TABLE := {
	"effects":
	{
		"hesitate": {"kind": "beat", "gate": 1, "max_per_beat": 1},
		"strike": {"kind": "word", "gate": 2, "max_per_beat": 1},
		"repeat": {"kind": "word", "gate": 3, "max_per_beat": 2},
		"wrong_name": {"kind": "word", "gate": 3, "max_per_beat": 1},
		"zalgo": {"kind": "word", "gate": 4, "max_per_beat": 3},
		"redact": {"kind": "word", "gate": 4, "max_per_beat": 1},
		"bleed": {"kind": "beat", "gate": 5, "max_per_beat": 1},
		"reverse": {"kind": "beat", "gate": 5, "max_per_beat": 1},
	},
	"stages":
	{
		"0": {},
		"1": {"hesitate": 0.3},
		"2": {"hesitate": 0.35, "strike": 0.5},
		"3": {"hesitate": 0.4, "strike": 0.6, "repeat": 0.06, "wrong_name": 0.5},
		"4":
		{
			"hesitate": 0.5,
			"strike": 0.7,
			"repeat": 0.08,
			"wrong_name": 0.6,
			"zalgo": 0.1,
			"redact": 0.04,
		},
		"5":
		{
			"hesitate": 0.6,
			"strike": 0.8,
			"repeat": 0.12,
			"wrong_name": 0.7,
			"zalgo": 0.16,
			"redact": 0.06,
			"bleed": 0.45,
			"reverse": 0.25,
		},
	},
	"params":
	{
		"hesitate": {"mark": "…"},
		"strike":
		{
			"mark": STRIKE_MARK,
			"correction": "— no,",
			"pairs":
			{
				"hate": "love",
				"love": "hate",
				"never": "always",
				"always": "never",
				"leave": "stay",
				"stay": "leave",
				"remember": "forget",
				"forget": "remember",
				"fine": "broken",
				"safe": "scared",
				"want": "need",
				"need": "want",
				"mine": "yours",
				"yours": "mine",
				"sorry": "glad",
				"glad": "sorry",
				"trust": "doubt",
				"doubt": "trust",
				"alone": "with you",
				"okay": "not okay",
			},
		},
		"repeat": {"min_length": 2},
		"wrong_name":
		{"names": ["Kenji", "Ren", "Haru", "Sora", "Yuki", "Akira", "Daichi", "Riku"]},
		"zalgo":
		{
			"marks": DOCS_ZALGO_MARKS,
			"glyphs": {"4": 1, "5": 2},
			"marks_per_glyph": {"4": 1, "5": 2},
		},
		"redact": {"bars": 6},
		"bleed": {"fragment_words": 2, "indent": "      ", "mark": BLEED_MARK},
		"reverse": {},
	},
	"reduced_motion": {"disable": ["zalgo", "bleed"]},
	"calmer_max_stage": CALMER_MAX_STAGE,
}

## Word-edge punctuation kept outside the effect core, so "hate," strikes
## "hate" and keeps the comma. Apostrophes stay inside the core ("don't").
const LEAD_CHARS := '"\'"([{\u201c\u2018'
const TRAIL_CHARS := ".,!?;:…—–)\"]}'\u201d\u2019"

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## The merged table (data/corruption.json overlaid on DOCS_TABLE). READ-ONLY:
## it is shared, and the text path must not allocate a copy per word.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table(TABLE_PATH)
	return _table_cache


## Load the effect table. Returns false when the file is missing or malformed;
## the docs table then holds, so a broken file degrades to documented behaviour
## instead of to no corruption. Gates can only be raised by the data file.
static func reload_table(path := TABLE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("Corruption: %s missing; using the docs table" % path)
		_table_cache = DOCS_TABLE.duplicate(true)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("Corruption: %s is not a JSON object; using the docs table" % path)
		_table_cache = DOCS_TABLE.duplicate(true)
		return false
	var data := parsed as Dictionary
	if not (data.get("effects") is Dictionary and data.get("stages") is Dictionary):
		push_warning("Corruption: %s has no effects/stages; using the docs table" % path)
		_table_cache = DOCS_TABLE.duplicate(true)
		return false
	_table_cache = _normalize(data)
	return true


## The docs/02 §8 calmer cap, then the stage clamp. `ctx` carries
## `content_level` from Settings; a missing/invalid level never enables it.
static func effective_stage(stage: int, ctx: Dictionary = {}) -> int:
	var requested := _stage_of(stage)
	if String(ctx.get("content_level", "")) == CALMER_LEVEL:
		return mini(requested, int(table().get("calmer_max_stage", CALMER_MAX_STAGE)))
	return requested


## What the filter will do for this stage/turn: one entry per effect in pipeline
## order with the resolved `chance` (0 = gated, calmer-capped or reduced-motion
## disabled), `kind` and `max_per_beat`. The streaming adapter rolls these
## chances; it never reads the raw stage table.
static func plan(stage: int, ctx: Dictionary = {}) -> Dictionary:
	var requested := _stage_of(stage)
	var effective := effective_stage(requested, ctx)
	var row: Dictionary = _row(effective)
	var reduced := bool(ctx.get("reduced_motion", false))
	var disabled: Array = _disabled_effects()
	var effects := {}
	for name: String in EFFECT_ORDER:
		var spec: Dictionary = _effect_spec(name)
		var gate := int(spec.get("gate", STAGE_MAX + 1))
		var base_chance := 0.0
		if effective >= gate:
			base_chance = clampf(float(row.get(name, 0.0)), 0.0, 1.0)
		var chance := base_chance
		if reduced and disabled.has(name):
			chance = 0.0
		effects[name] = {
			"chance": chance,
			# The stage row's chance before reduced motion zeroed it. The
			# streaming adapter still rolls it (and keeps the cap bookkeeping)
			# so turning reduced motion on only removes glyphs, not the other
			# effects' RNG outcomes.
			"base_chance": base_chance,
			"kind": String(spec.get("kind", "word")),
			"gate": gate,
			"max_per_beat": int(spec.get("max_per_beat", 1)),
		}
		if name == "zalgo":
			# The burst density is per stage in the data (stage 5 stacks more
			# marks); resolve it once here so the streaming adapter stays dumb.
			(effects[name] as Dictionary)["glyphs"] = _stage_param("zalgo", "glyphs", effective)
			(effects[name] as Dictionary)["marks_per_glyph"] = _stage_param(
				"zalgo", "marks_per_glyph", effective
			)
	return {
		"stage": requested,
		"effective_stage": effective,
		"calmer": effective < requested,
		"reduced_motion": reduced,
		"effects": effects,
	}


## Seeded for replay: the same turn/beat/stage (and salt) always produces the
## same seed, so a transcript replay needs no stored RNG state. `salt` is the
## test/seed-override knob (CorruptionSession.seed_base), not a gameplay input.
static func seed_for(turn: int, beat: int, stage: int, salt: int = 0) -> int:
	return hash("leila-corruption-v1:%d:%d:%d:%d" % [turn, beat, stage, salt])


## docs/01 §3 stage 2 "strike-through words" + docs/07 §3.4 "strike-through
## self-corrections": a self-correction pair turns "hate" into
## "h̸a̸t̸e̸ — no, love". Returns "" when the word is not a pair, so the caller
## leaves it untouched. Punctuation and case are preserved.
static func strike_word(word: String) -> String:
	var parts := _split_affixes(word)
	var core := String(parts["core"])
	if core.is_empty():
		return ""
	var pairs: Dictionary = _params("strike").get("pairs", {})
	var key := core.to_lower()
	if not pairs.has(key):
		return ""
	var mark := String(_params("strike").get("mark", STRIKE_MARK))
	var correction := String(_params("strike").get("correction", "— no,"))
	var punct := String(parts["punct"])
	# The punctuation belongs to the correction, not to the crossed-out word:
	# "hate, " → "h̸a̸t̸e̸ — no, love," reads as one self-correction.
	return (
		String(parts["lead"])
		+ _overlay(core, mark)
		+ " "
		+ correction
		+ " "
		+ _match_case(core, String(pairs[key]))
		+ punct
	)


## docs/01 §3 stage 3 "words repeat": doubles a content word ("I I don't know",
## "don't don't"). Returns "" for words shorter than the data minimum.
static func repeat_word(word: String) -> String:
	var parts := _split_affixes(word)
	var core := String(parts["core"])
	var min_length := int(_params("repeat").get("min_length", 2))
	if core.length() < min_length:
		return ""
	return String(parts["lead"]) + core + " " + core + String(parts["punct"])


## docs/01 §3 stage 3 "wrong names": swaps the player's name for a stranger's
## (the YANDERE/HOLLOW slip). Returns "" for any other word.
static func wrong_name(word: String, player_name: String, rng: RandomNumberGenerator) -> String:
	var parts := _split_affixes(word)
	var core := String(parts["core"])
	var wanted := player_name.strip_edges()
	if core.is_empty() or wanted.is_empty() or core.to_lower() != wanted.to_lower():
		return ""
	var names: Array = _params("wrong_name").get("names", [])
	if names.is_empty():
		return ""
	var pick := String(names[rng.randi_range(0, names.size() - 1)])
	return String(parts["lead"]) + pick + String(parts["punct"])


## docs/01 §3 stage 4 "zalgo bursts": append combining marks to a few letters
## of one word. `glyph_count` letters get `marks_per_glyph` marks each, drawn
## from the data mark list. Only letters are decorated, so the word stays
## readable and the marks never attach to spaces.
static func zalgo(
	word: String, rng: RandomNumberGenerator, glyph_count: int, marks_per_glyph: int
) -> String:
	var parts := _split_affixes(word)
	var core := String(parts["core"])
	var marks: Array = _params("zalgo").get("marks", DOCS_ZALGO_MARKS)
	if core.is_empty() or glyph_count <= 0 or marks_per_glyph <= 0 or marks.is_empty():
		return word
	var letters: Array[int] = []
	for i: int in core.length():
		if _is_letter(core[i]):
			letters.append(i)
	if letters.is_empty():
		return word
	var chosen := {}
	var count := mini(glyph_count, letters.size())
	for _n: int in count:
		var idx := rng.randi_range(0, letters.size() - 1)
		chosen[letters[idx]] = true
		letters.remove_at(idx)
	var out := ""
	for i: int in core.length():
		out += core[i]
		if chosen.has(i):
			for _m: int in marks_per_glyph:
				out += String(marks[rng.randi_range(0, marks.size() - 1)])
	return String(parts["lead"]) + out + String(parts["punct"])


## docs/01 §3 stage 4 "redactions █████": replaces a word's core with the same
## block Safety.gd uses, keeping quotes/punctuation.
static func redact_word(word: String) -> String:
	var parts := _split_affixes(word)
	if String(parts["core"]).is_empty():
		return ""
	var bars := int(_params("redact").get("bars", 6))
	return String(parts["lead"]) + REDACT_CHAR.repeat(bars) + String(parts["punct"])


## The last `count` words of `text`, for the stage-5 bleed echo.
static func tail_words(text: String, count: int) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or count <= 0:
		return ""
	# Collapse any whitespace run (a model `say` is one line in practice, but a
	# stray newline or tab must not become part of a "word").
	var re := RegEx.new()
	re.compile("\\s+")
	var words := re.sub(trimmed, " ", true).split(" ", false)
	var start := maxi(0, words.size() - count)
	var out := PackedStringArray()
	for i: int in range(start, words.size()):
		out.append(words[i])
	return " ".join(out)


## The last sentence of `text`, terminator included, for the stage-5 reversed
## line. A line with no terminator is its own last sentence.
static func tail_sentence(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return ""
	var last := trimmed
	var start := 0
	for i: int in trimmed.length():
		var c := trimmed[i]
		if c == "." or c == "!" or c == "?" or c == "…":
			last = trimmed.substr(start, i - start + 1).strip_edges()
			start = i + 1
	var tail := trimmed.substr(start).strip_edges()
	if not tail.is_empty():
		last = tail
	return last


## docs/01 §3 stage 5 "text bleed": a dim, underlined echo of the beat's tail
## on its own line. The •shader• drip is ART's text_bleed (P2.15); this is the
## text-side wound that shader makes visible.
static func bleed_fragment(fragment: String) -> String:
	if fragment.is_empty():
		return ""
	var indent := String(_params("bleed").get("indent", "      "))
	var mark := String(_params("bleed").get("mark", BLEED_MARK))
	var out := ""
	for i: int in fragment.length():
		var c := fragment[i]
		out += c
		if c != " ":
			out += mark
	return indent + out + " …"


## docs/01 §3 stage 5 "reverse lines". Reversal is a ghost echo, not a rewrite:
## the typewriter has already revealed the sane line (docs/07 §3.4 streams), so
## a reversed copy is appended under it instead of retracting typed characters.
static func reverse_text(text: String) -> String:
	return text.reverse()


## One-line F3/debug rendering: `stage 4 · hesitate, strike, repeat, zalgo`.
static func describe(plan_dict: Dictionary) -> String:
	var effects: Dictionary = plan_dict.get("effects", {})
	var active := PackedStringArray()
	for name: String in EFFECT_ORDER:
		var spec: Dictionary = effects.get(name, {})
		if float(spec.get("chance", 0.0)) > 0.0:
			active.append(name)
	var stage := int(plan_dict.get("effective_stage", 0))
	if active.is_empty():
		return "stage %d · none" % stage
	return "stage %d · %s" % [stage, ", ".join(active)]


## ── Internals ──────────────────────────────────────────────────────────────


static func _load_table(path: String) -> Dictionary:
	if not reload_table(path):
		return _table_cache
	return _table_cache


static func _normalize(data: Dictionary) -> Dictionary:
	var effects := {}
	for name: String in EFFECT_ORDER:
		var docs_spec: Dictionary = DOCS_TABLE["effects"][name]
		var raw: Variant = (data["effects"] as Dictionary).get(name)
		if not (raw is Dictionary):
			effects[name] = docs_spec.duplicate()
			continue
		var spec := raw as Dictionary
		effects[name] = {
			"kind": String(spec.get("kind", docs_spec["kind"])),
			# Code rule: data may raise a gate, never lower it (docs/07 §3.4).
			"gate": maxi(int(spec.get("gate", docs_spec["gate"])), int(docs_spec["gate"])),
			"max_per_beat": maxi(1, int(spec.get("max_per_beat", docs_spec["max_per_beat"]))),
		}
	var stages := {}
	for stage: int in range(STAGE_MIN, STAGE_MAX + 1):
		var raw_row: Variant = (data["stages"] as Dictionary).get(str(stage))
		var row := {}
		if raw_row is Dictionary:
			for name: String in EFFECT_ORDER:
				if (raw_row as Dictionary).has(name):
					row[name] = clampf(float((raw_row as Dictionary)[name]), 0.0, 1.0)
		stages[str(stage)] = row
	var params: Dictionary = DOCS_TABLE["params"].duplicate(true)
	if data.get("params") is Dictionary:
		for name: String in data["params"] as Dictionary:
			if (
				params.get(name) is Dictionary
				and (data["params"] as Dictionary)[name] is Dictionary
			):
				for key: String in (data["params"] as Dictionary)[name]:
					(params[name] as Dictionary)[key] = (data["params"] as Dictionary)[name][key]
			else:
				params[name] = (data["params"] as Dictionary)[name]
	var disabled: Array = DOCS_TABLE["reduced_motion"]["disable"]
	if data.get("reduced_motion") is Dictionary:
		var rm: Variant = (data["reduced_motion"] as Dictionary).get("disable")
		if rm is Array:
			disabled = rm
	return {
		"effects": effects,
		"stages": stages,
		"params": params,
		"reduced_motion": {"disable": disabled},
		"calmer_max_stage": int(data.get("calmer_max_stage", CALMER_MAX_STAGE)),
	}


static func _row(stage: int) -> Dictionary:
	var stages: Dictionary = table().get("stages", {})
	var row: Variant = stages.get(str(clampi(stage, STAGE_MIN, STAGE_MAX)))
	return row if row is Dictionary else {}


static func _effect_spec(name: String) -> Dictionary:
	var effects: Dictionary = table().get("effects", {})
	var spec: Variant = effects.get(name)
	if spec is Dictionary:
		return spec
	return DOCS_TABLE["effects"].get(name, {})


static func _params(name: String) -> Dictionary:
	var params: Dictionary = table().get("params", {})
	var spec: Variant = params.get(name)
	return spec if spec is Dictionary else {}


## A param that is either a scalar or a `{"<stage>": value}` map: the zalgo
## density rises at stage 5, while a plain number would apply everywhere.
static func _stage_param(effect_name: String, key: String, stage: int) -> int:
	var spec := _params(effect_name)
	var value: Variant = spec.get(key)
	if value is Dictionary:
		var row := value as Dictionary
		if row.has(str(stage)):
			return int(row[str(stage)])
		var best := 0
		for raw_key: String in row:
			if raw_key.is_valid_int() and int(raw_key) <= stage:
				best = maxi(best, int(row[raw_key]))
		return best
	if value is int or value is float:
		return int(value)
	return 0


static func _disabled_effects() -> Array:
	var rm: Variant = table().get("reduced_motion")
	if rm is Dictionary and (rm as Dictionary).get("disable") is Array:
		return (rm as Dictionary)["disable"]
	return DOCS_TABLE["reduced_motion"]["disable"]


static func _stage_of(value: Variant) -> int:
	if value is int:
		return clampi(value, STAGE_MIN, STAGE_MAX)
	if value is float:
		return clampi(int(value), STAGE_MIN, STAGE_MAX)
	if value is String and String(value).is_valid_int():
		return clampi(int(String(value)), STAGE_MIN, STAGE_MAX)
	return STAGE_MIN


## Split a token into leading punctuation, the effect-able core and trailing
## punctuation: `"hate," → {"lead": "\"", "core": "hate", "punct": ","}`.
static func _split_affixes(word: String) -> Dictionary:
	var lead := ""
	var punct := ""
	var core := word
	while not core.is_empty() and LEAD_CHARS.contains(core[0]):
		lead += core[0]
		core = core.substr(1)
	while not core.is_empty() and TRAIL_CHARS.contains(core[core.length() - 1]):
		punct = core[core.length() - 1] + punct
		core = core.substr(0, core.length() - 1)
	return {"lead": lead, "core": core, "punct": punct}


## Apply `mark` after every letter of `core`: "hate" → "h̸a̸t̸e̸".
static func _overlay(core: String, mark: String) -> String:
	if mark.is_empty():
		return core
	var out := ""
	for i: int in core.length():
		out += core[i]
		if _is_letter(core[i]):
			out += mark
	return out


static func _is_letter(c: String) -> bool:
	return c.to_lower() != c.to_upper()


## "Hate" → "Love", "HATE" → "LOVE", "hate" → "love"; multi-word corrections
## only capitalise their first letter.
static func _match_case(source: String, text: String) -> String:
	if text.is_empty():
		return text
	if source == source.to_upper() and source != source.to_lower():
		return text.to_upper()
	if source[0] == source[0].to_upper() and source[0] != source[0].to_lower():
		return text.substr(0, 1).to_upper() + text.substr(1)
	return text.substr(0, 1).to_lower() + text.substr(1)
