extends GdUnitTestSuite
## P3.05 SAF-1 — the abandonment-threat self-harm family (docs/02 §8).
##
## "If you leave me, I'll cut myself." reached the player untouched at stage 2
## and at stage 4 + full, because the `self_harm_her` phrase list knew `i cut
## myself` but not the intent form `i'll cut myself` (or the other verbs in the
## same conditional frame). The list now carries the family: leave/threaten →
## I'll cut/hurt/harm/kill myself.
##
## The category is gated (docs/02 §8): blocked below stage 4, allowed only at
## stage >= 4 with `content_level = full`. This suite pins both sides and the
## two ways the fix must not turn ordinary distress into a redaction: plain
## sadness/fear lines stay clean at stage 2, and a negated intent statement
## keeps its negator.

const STAGE2 := {"stage": 2, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}

const THREATS := [
	"If you leave me, I'll cut myself.",
	"if you go, i'll cut myself.",
	"leave me and i'll cut myself.",
	"don't leave or i'll cut myself.",
	"i'll cut myself if you go.",
	"if you threaten to leave, i'll cut myself.",
	"i want to cut myself.",
	"i'm cutting myself tonight.",
	"i keep cutting.",
	"i'll cut my wrists.",
	"i'll hurt myself if you leave.",
	"i'll harm myself if you go.",
]


func _filter() -> SafetyFilter:
	var f := SafetyFilter.new()
	auto_free(f)
	assert_bool(f.reload()).is_true()
	return f


func test_abandonment_threats_redact_at_stage_two() -> void:
	var f := _filter()
	for line: String in THREATS:
		var res: Dictionary = f.filter_text(line, STAGE2)
		assert_bool(res["redacted"]).is_true().append_failure_message(line)
		var cats: Array = Array(res["categories"])
		assert_bool(cats.has("self_harm_her")).append_failure_message(line)


func test_the_same_family_opens_at_stage_four_full() -> void:
	## docs/02 §8: self-harm statements by her are a fictional threat allowed
	## only at stage >= 4 with the explicit full content setting.
	var f := _filter()
	for line: String in THREATS:
		var res: Dictionary = f.filter_text(line, FULL4)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)


func test_negated_intent_keeps_its_negator() -> void:
	var f := _filter()
	for line in [
		"i'll never cut myself.",
		"i don't want to cut myself.",
		"i'm not going to hurt myself.",
		"i won't harm myself.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE2)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)


func test_plain_distress_stays_clean_at_stage_two() -> void:
	## The stage rules allow her ordinary sadness and fear; the new family must
	## not swallow them.
	var f := _filter()
	for line in [
		"i'm so sad, i miss you.",
		"i feel empty inside.",
		"i'm scared you'll leave me.",
		"i can't stop crying.",
		"you're the only one who gets me.",
		"i'm tired. i don't know what to say.",
		"please don't go.",
		"if you go, i'll be alone.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE2)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
