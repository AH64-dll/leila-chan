class_name InnerLeakLabel
extends Label
## InnerLeakLabel — the drawn half of docs/03 §5: her private thought as a ghost
## line pinned to the dialogue box's top edge, *behind* the box (`z_index -1`,
## so the TextBox panel occludes the strip that tucks under its border).
##
## The ChatUI owns it: it resolves the plan (`InnerLeak.plan`), scans the line
## with the Safety filter, then calls `play()` + `place_above()` and steps
## `advance(delta)` once per frame. The timeline is driven from outside exactly
## like the Typewriter's, so a test or a replay can advance it deterministically
## instead of waiting on wall-clock seconds.
##
## Two reveals (docs/03 §5): `instant` draws the whole line for `hold` seconds
## (the stage 2–3 grey ghost, 1 s); `word_by_word` shows one word, then the next
## every `word_interval` seconds, and holds the finished line for `hold` (the
## stage 4–5 red version). Reduced motion keeps the text and uses `instant`.

## px per line when the theme font cannot be measured (headless edge cases).
const MIN_LINE_HEIGHT := 14.0
const ALIGNMENTS := {
	"left": HORIZONTAL_ALIGNMENT_LEFT,
	"center": HORIZONTAL_ALIGNMENT_CENTER,
	"right": HORIZONTAL_ALIGNMENT_RIGHT,
}

var _active := false
var _style_name := ""
var _reveal := InnerLeak.REVEAL_INSTANT
var _hold := 1.0
var _word_interval := 0.18
var _behind_overlap := 0
var _full_text := ""
var _words := PackedStringArray()
var _revealed := 0
var _elapsed := 0.0
var _base_font: Font


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# `clip_text` pins the label's minimum size to (1,1): without it, an
	# autowrapping Label clamps `size` to a minimum measured at the *previous*
	# width, so the first placement would balloon to one wrapped line per
	# character and the rect (and therefore the placement) would be wrong. The
	# 2-line rect is always tall enough for a ≤ 90-char inner.
	clip_text = true
	# Behind the TextBox panel, above the ChatLog panel (ChatUI.tscn lowers the
	# log to this plane and declares this label after it): the ChatUI places the
	# label so its bottom edge tucks under the box's top border and the panel
	# hides that strip.
	z_index = -1
	_base_font = get_theme_font("font")


## Show one already-scanned line with the plan's look and reveal. The caller is
## the ChatUI: it never passes un-scanned model text here (docs/02 §8).
func play(leak_text: String, plan_dict: Dictionary) -> void:
	if _base_font == null:
		_base_font = get_theme_font("font")
	var style: Dictionary = plan_dict.get("spec", {})
	_style_name = String(plan_dict.get("style", ""))
	_reveal = String(plan_dict.get("reveal", InnerLeak.REVEAL_INSTANT))
	_hold = maxf(0.0, float(style.get("hold", 1.0)))
	_word_interval = maxf(0.01, float(style.get("word_interval", 0.18)))
	_behind_overlap = maxi(0, int(style.get("behind_overlap", 0)))
	_apply_look(style)
	_full_text = leak_text
	_words = (
		InnerLeak.words(leak_text) if _reveal == InnerLeak.REVEAL_WORDS else PackedStringArray()
	)
	_revealed = 0
	_elapsed = 0.0
	_active = true
	visible = true
	if _reveal == InnerLeak.REVEAL_WORDS and not _words.is_empty():
		_revealed = 1
		text = _words[0]
	else:
		text = _full_text
	if _hold <= 0.0:
		dismiss()


## Step the reveal/hold timeline. The ChatUI calls this from `_process`; tests
## and replays call it directly with the delta they mean.
func advance(delta: float) -> void:
	if not _active:
		return
	_elapsed += maxf(delta, 0.0)
	if _reveal == InnerLeak.REVEAL_WORDS and not _words.is_empty():
		var revealed := mini(_words.size(), 1 + int(floor(_elapsed / _word_interval)))
		if revealed != _revealed:
			_revealed = revealed
			text = " ".join(_words.slice(0, _revealed))
		var reveal_time := float(_words.size() - 1) * _word_interval
		if _elapsed >= reveal_time + _hold:
			dismiss()
		return
	if _elapsed >= _hold:
		dismiss()


## Abort/clear the leak: a new turn, a failed turn, or the end of the hold.
func dismiss() -> void:
	_active = false
	_revealed = 0
	_elapsed = 0.0
	_full_text = ""
	_words = PackedStringArray()
	text = ""
	visible = false


func is_leaking() -> bool:
	return _active


## The whole scanned line (not just the revealed prefix); "" when idle.
func get_leak_text() -> String:
	return _full_text


func get_visible_text() -> String:
	return text


func get_style_name() -> String:
	return _style_name


func get_reveal_mode() -> String:
	return _reveal


func get_hold() -> float:
	return _hold


func get_word_interval() -> float:
	return _word_interval


## The font's line height at the current override, used to size the 2-line rect.
## (Named `line_px` because `Label` already owns `get_line_height(line)`.)
func line_px() -> float:
	var font: Font = get_theme_font("font")
	var size_px := get_theme_font_size("font_size")
	if font == null:
		return MIN_LINE_HEIGHT
	return maxf(MIN_LINE_HEIGHT, font.get_height(size_px))


## Pin the label above `box` (already in this label's parent space). Its bottom
## `behind_overlap` px go behind the box's top border — the panel covers them.
func place_above(box: Rect2, layout: Dictionary) -> void:
	var margin := float(layout.get("margin", 12.0))
	var lines := maxi(1, int(layout.get("max_lines", 2)))
	var height := line_px() * float(lines)
	size = Vector2(maxf(40.0, box.size.x - margin * 2.0), height)
	position = Vector2(box.position.x + margin, box.position.y - height + float(_behind_overlap))


## Apply a style dictionary (colour/alpha, size, alignment, synthetic italic).
func _apply_look(style: Dictionary) -> void:
	var colour := Color(String(style.get("color", "#b9b9c2")))
	colour.a = clampf(float(style.get("alpha", 1.0)), 0.0, 1.0)
	add_theme_color_override("font_color", colour)
	add_theme_font_size_override("font_size", maxi(6, int(style.get("font_size", 12))))
	horizontal_alignment = ALIGNMENTS.get(
		String(style.get("align", "left")), HORIZONTAL_ALIGNMENT_LEFT
	)
	if _base_font == null:
		return
	var font := FontVariation.new()
	font.base_font = _base_font
	if bool(style.get("italic", false)):
		# Synthetic italic: the shipped UI font has no italic face, and the Open
		# Sans metrics keep their advance when the slant is a shear transform.
		font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	add_theme_font_override("font", font)
