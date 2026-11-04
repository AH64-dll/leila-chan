class_name InnerLeak
extends RefCounted
## InnerLeak — the docs/03 §5 inner-voice leak (docs/05 M41): her private
## `inner` thought surfaces for a moment, before the spoken words give her away.
##
##     stage 2   → 5% of turns, faint grey italic behind the text box for 1 s
##     stage 3   → 15% of turns (same look)
##     stage 4–5 → 30% of turns, in red, word by word
##
## This file is the pure, deterministic half: the per-stage chances, the
## stage→style mapping, the seeded per-turn roll and the word list the display
## reveals. `InnerLeakLabel` (res://scenes/ui/InnerLeakLabel.gd) draws it and
## the ChatUI owns both; nothing here touches a node or the screen.
##
## Rules that are code, not data:
## - the stage gate (2+) and the per-turn cap (1) are closed: `GATE_MIN` and
##   `MAX_PER_TURN` live here, so a data edit cannot unlock the leak earlier or
##   make it fire twice in one turn;
## - the style per stage is docs-fixed (`STAGE_STYLE`): data tunes each style's
##   colour/timing, never which stage gets which look;
## - `Settings.content_level = calmer` caps the effective stage at 3 (docs/02
##   §8), reusing `Corruption.effective_stage` so the campaign has one rule;
## - reduced motion keeps the whole line instead of revealing it word by word
##   (docs/05 §0.5: every effect keeps an accessibility fallback).
##
## Safety (docs/02 §8, docs/05 §0): the leak is model text, so the line passes
## the Safety filter before it can be displayed. That scan lives in the display
## owner (`ChatUI.leak_inner` → `Safety.filter_text`, fail-closed to bars) —
## this file only ever says *whether* and *how* to leak, never *what* is safe
## to show.

const TABLE_PATH := "res://data/inner_leak.json"

## docs/03 §5: "from stage 2 the game sometimes shows it".
const GATE_MIN := 2
## One leak per turn: `inner` is one thought (docs/02 §3, ≤ 90 chars).
const MAX_PER_TURN := 1
const STAGE_MAX := 5

## docs/03 §5: faint grey italic at 2–3, in red word by word at 4–5.
const STAGE_STYLE := {2: "ghost", 3: "ghost", 4: "red", 5: "red"}

const REVEAL_INSTANT := "instant"
const REVEAL_WORDS := "word_by_word"
const _REVEAL_MODES: Array[String] = [REVEAL_INSTANT, REVEAL_WORDS]
const _ALIGNMENTS: Array[String] = ["left", "center", "right"]

## The docs values as code. Tests pin data/inner_leak.json against this table,
## so tuning one without the other is a red suite rather than a silent drift.
const DOCS_TABLE := {
	"chances": {"2": 0.05, "3": 0.15, "4": 0.3, "5": 0.3},
	"styles":
	{
		"ghost":
		{
			"color": "#b9b9c2",
			"alpha": 0.55,
			"italic": true,
			"font_size": 12,
			"hold": 1.0,
			"reveal": REVEAL_INSTANT,
			"word_interval": 0.18,
			"align": "right",
			"behind_overlap": 2,
		},
		"red":
		{
			"color": "#c0272f",
			"alpha": 0.95,
			"italic": false,
			"font_size": 13,
			"hold": 1.6,
			"reveal": REVEAL_WORDS,
			"word_interval": 0.22,
			"align": "left",
			"behind_overlap": 0,
		},
	},
	"reduced_motion": {"instant_reveal": true},
	"layout": {"margin": 12, "max_lines": 2},
	"debug_sample": "I could keep him here.",
}

static var _table_cache: Dictionary = {}


## Test hook: drop the loaded table so the next call re-reads the data file.
static func clear_cache() -> void:
	_table_cache = {}


## The merged table (data/inner_leak.json overlaid on DOCS_TABLE). READ-ONLY:
## it is shared, and the leak path must not allocate a copy per turn.
static func table() -> Dictionary:
	if _table_cache.is_empty():
		_table_cache = _load_table(TABLE_PATH)
	return _table_cache


## Load the leak table. Returns false when the file is missing or malformed; the
## docs table then holds, so a broken file degrades to documented behaviour
## instead of to no leak. Gates and the stage→style map stay code.
static func reload_table(path := TABLE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("InnerLeak: %s missing; using the docs table" % path)
		_table_cache = DOCS_TABLE.duplicate(true)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("InnerLeak: %s is not a JSON object; using the docs table" % path)
		_table_cache = DOCS_TABLE.duplicate(true)
		return false
	var data := parsed as Dictionary
	if not (data.get("chances") is Dictionary and data.get("styles") is Dictionary):
		push_warning("InnerLeak: %s has no chances/styles; using the docs table" % path)
		_table_cache = DOCS_TABLE.duplicate(true)
		return false
	_table_cache = _normalize(data)
	return true


## What the next turn would show: the resolved chance, style and reveal mode
## for this stage. `ctx` carries `reduced_motion` and `content_level` from the
## ChatUI/Settings; an unknown content level never enables the calmer cap.
static func plan(stage: int, ctx: Dictionary = {}) -> Dictionary:
	var requested := _stage_of(stage)
	var calmer_ctx := {"content_level": String(ctx.get("content_level", ""))}
	var effective := Corruption.effective_stage(requested, calmer_ctx)
	var style := stage_style(effective)
	var spec := _style_spec(style)
	var chance := 0.0
	if effective >= GATE_MIN:
		chance = clampf(float(_chances().get(str(effective), 0.0)), 0.0, 1.0)
	var reduced := bool(ctx.get("reduced_motion", false))
	var reveal := String(spec.get("reveal", REVEAL_INSTANT))
	if reduced and bool(table()["reduced_motion"]["instant_reveal"]):
		reveal = REVEAL_INSTANT
	return {
		"stage": requested,
		"effective_stage": effective,
		"calmer": effective < requested,
		"gate": GATE_MIN,
		"eligible": effective >= GATE_MIN and chance > 0.0,
		"chance": chance,
		"style": style,
		"reveal": reveal,
		"reduced_motion": reduced,
		"max_per_turn": MAX_PER_TURN,
		"spec": spec,
	}


## The docs/03 §5 style for a stage (docs-fixed): "ghost" at 2–3, "red" at 4–5.
static func stage_style(stage: int) -> String:
	return String(STAGE_STYLE.get(_stage_of(stage), "ghost"))


## Seeded for replay: the same turn/stage (and salt) always draws the same
## roll, so a transcript replay needs no stored decision. `salt` is the
## test/seed-override knob (ChatUI.inner_leak_salt), not a gameplay input.
static func seed_for(turn: int, stage: int, salt: int = 0) -> int:
	return hash("leila-inner-leak-v1:%d:%d:%d" % [turn, _stage_of(stage), salt])


## Does this turn leak? Deterministic per (turn, effective stage, salt) and
## false whenever the plan says the stage is closed (below the gate, calmer
## capped, or a 0 chance).
static func roll(plan_dict: Dictionary, turn: int, salt: int = 0) -> bool:
	if not bool(plan_dict.get("eligible", false)):
		return false
	var chance := float(plan_dict.get("chance", 0.0))
	if chance <= 0.0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(turn, int(plan_dict.get("effective_stage", 0)), salt)
	return rng.randf() < chance


## The line as the word-by-word reveal shows it: whitespace-separated tokens
## with their punctuation. The inner is one line (Safety collapses whitespace),
## so splitting on spaces is lossless where it matters and has no per-character
## `String.split("")` trap.
static func words(text: String) -> PackedStringArray:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return PackedStringArray()
	return cleaned.split(" ", false)


## One-line F3/debug rendering: `stage 4 · 30% · red · word_by_word`.
static func describe(plan_dict: Dictionary) -> String:
	var stage := int(plan_dict.get("effective_stage", 0))
	if not bool(plan_dict.get("eligible", false)):
		return "off (stage %d)" % stage
	var percent := int(round(float(plan_dict.get("chance", 0.0)) * 100.0))
	return (
		"stage %d · %d%% · %s · %s"
		% [stage, percent, String(plan_dict.get("style", "")), String(plan_dict.get("reveal", ""))]
	)


## The label's geometry knobs (data-driven so ART/QA can retune the placement
## without touching code). READ-ONLY, like `table()`.
static func layout() -> Dictionary:
	var raw: Variant = table().get("layout")
	return raw if raw is Dictionary else DOCS_TABLE["layout"]


## The F3/F4 dev trigger's line. Content lives in data, never in code.
static func debug_sample() -> String:
	return String(table().get("debug_sample", DOCS_TABLE["debug_sample"]))


## ── Internals ──────────────────────────────────────────────────────────────


static func _load_table(path: String) -> Dictionary:
	if not reload_table(path):
		return _table_cache
	return _table_cache


static func _chances() -> Dictionary:
	var raw: Variant = table().get("chances")
	return raw if raw is Dictionary else DOCS_TABLE["chances"]


static func _style_spec(style_name: String) -> Dictionary:
	var styles: Variant = table().get("styles")
	if styles is Dictionary:
		var spec: Variant = (styles as Dictionary).get(style_name)
		if spec is Dictionary:
			return spec
	return (DOCS_TABLE["styles"] as Dictionary).get(style_name, {}).duplicate(true)


## Merge the data file over the docs table, clamping everything that could
## break the display: chances to 0–1, colours/sizes/timings to sane values and
## each style's `reveal`/`align` to the known enums. The stage→style mapping is
## NOT read from the file — see `STAGE_STYLE`.
static func _normalize(data: Dictionary) -> Dictionary:
	var chances := {}
	var raw_chances: Dictionary = data["chances"] as Dictionary
	for stage: int in range(GATE_MIN, STAGE_MAX + 1):
		var fallback := float((DOCS_TABLE["chances"] as Dictionary)[str(stage)])
		chances[str(stage)] = clampf(float(raw_chances.get(str(stage), fallback)), 0.0, 1.0)
	var styles := {}
	var raw_styles: Dictionary = data["styles"] as Dictionary
	for name: String in DOCS_TABLE["styles"] as Dictionary:
		var docs_style: Dictionary = (DOCS_TABLE["styles"] as Dictionary)[name]
		var style := docs_style.duplicate(true)
		var raw: Variant = raw_styles.get(name)
		if raw is Dictionary:
			for key: String in raw as Dictionary:
				(style as Dictionary)[key] = (raw as Dictionary)[key]
		style["color"] = String(style.get("color", docs_style["color"]))
		style["alpha"] = clampf(float(style.get("alpha", docs_style["alpha"])), 0.0, 1.0)
		style["italic"] = bool(style.get("italic", docs_style["italic"]))
		style["font_size"] = maxi(6, int(style.get("font_size", docs_style["font_size"])))
		style["hold"] = maxf(0.1, float(style.get("hold", docs_style["hold"])))
		style["word_interval"] = maxf(
			0.01, float(style.get("word_interval", docs_style["word_interval"]))
		)
		style["behind_overlap"] = maxi(0, int(style.get("behind_overlap", 0)))
		var reveal := String(style.get("reveal", docs_style["reveal"]))
		style["reveal"] = reveal if reveal in _REVEAL_MODES else docs_style["reveal"]
		var align := String(style.get("align", docs_style["align"]))
		style["align"] = align if align in _ALIGNMENTS else docs_style["align"]
		styles[name] = style
	var rm: Dictionary = (DOCS_TABLE["reduced_motion"] as Dictionary).duplicate(true)
	if data.get("reduced_motion") is Dictionary:
		for key: String in data["reduced_motion"] as Dictionary:
			rm[key] = (data["reduced_motion"] as Dictionary)[key]
	var layout: Dictionary = (DOCS_TABLE["layout"] as Dictionary).duplicate(true)
	if data.get("layout") is Dictionary:
		for key: String in data["layout"] as Dictionary:
			layout[key] = (data["layout"] as Dictionary)[key]
	return {
		"chances": chances,
		"styles": styles,
		"reduced_motion": {"instant_reveal": bool(rm.get("instant_reveal", true))},
		"layout": layout,
		"debug_sample": String(data.get("debug_sample", DOCS_TABLE["debug_sample"])),
	}


static func _stage_of(value: Variant) -> int:
	if value is int:
		return clampi(value, 0, STAGE_MAX)
	if value is float:
		return clampi(int(value), 0, STAGE_MAX)
	if value is String and String(value).is_valid_int():
		return clampi(int(String(value)), 0, STAGE_MAX)
	return 0
