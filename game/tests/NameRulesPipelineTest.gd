extends GdUnitTestSuite
## P3.14 — the docs/07 §3.4 seam: the §1.5 name rules as they run inside the
## real word-serial corruptor (CorruptionSession), after Safety and after
## `wrong_name` takes the word-kind slot. The pure rule maths lives in
## `NameRulesTest.gd`.

## ── 1. pipeline seam (CorruptionSession) ──────────────────────────────────


func test_session_stage3_can_decay_the_name() -> void:
	# The decay reads "<slip>… <name>": the connector immediately followed by
	# the intact name. A bare "… " is ambiguous (the hesitation effect emits
	# it too) and `wrong_name` can swap the name for a stranger ("Ren" is on
	# its list), so only the precise pattern proves the rule reached the text.
	var saw := false
	for turn: int in range(1, 40):
		var session := CorruptionSession.new()
		session.begin_turn({"turn": turn, "stage": 3, "player_name": "Renji"})
		var out := session.transform_beat(0, "Renji, stay with me.")
		if out.contains("… Renji"):
			saw = true
			break
	assert_bool(saw).is_true()


func test_session_stage4_kun_reaches_the_typewriter_text() -> void:
	# A calm, affectionate turn (docs/02 §1.1: positive stress is the angry
	# direction), so the suffix is the rule's doing, not a lucky roll.
	var saw := false
	for turn: int in range(1, 60):
		var session := CorruptionSession.new()
		(
			session
			. begin_turn(
				{
					"turn": turn,
					"stage": 4,
					"player_name": "Renji",
					"mood": {"affection": 90.0, "stress": 0},
				}
			)
		)
		var out := session.transform_beat(0, "Hello Renji.")
		if out.contains("Renji-kun"):
			saw = true
			break
	assert_bool(saw).is_true()


func test_session_wrong_name_still_wins_over_decay() -> void:
	# wrong_name is the stranger-name slip and holds the word-kind slot: when
	# it fires the decay rule never also rewrites the same word (output must
	# be a plain stranger name, not "Reni… Renji" or "Riku-kun"). Stage 3 is
	# the honest place to prove the ordering: decay is live, while the -kun
	# rule (stage 4) and the zalgo burst (stage 4) cannot decorate the word
	# being compared.
	var names: Array = Corruption.DOCS_TABLE["params"]["wrong_name"]["names"]
	var saw := false
	for turn: int in range(1, 60):
		var session := CorruptionSession.new()
		session.begin_turn({"turn": turn, "stage": 3, "player_name": "Renji"})
		# A pending hesitation lands after the single word ("Ren. …"); the
		# stranger name is everything before that tail.
		var out := session.transform_beat(0, "Renji.").trim_suffix(" …")
		var core := out.trim_suffix(".")
		if not names.has(core):
			continue
		saw = true
		# The stranger replaces the whole word: decay's connector and the
		# "-kun" suffix never appear, and the punctuation is kept.
		assert_bool(out.contains("… ")).is_false()
		assert_bool(out.contains("-kun")).is_false()
		assert_str(out).is_equal(core + ".")
	assert_bool(saw).is_true()
