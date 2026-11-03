extends RefCounted
## Shared deterministic PromptBuilder contexts (P1.06) for the golden fixtures
## in res://tests/fixtures/prompts/. The suite compares build() output against
## the committed files; game/tests/tools/prompt_builder_goldens.gd regenerates
## them. One source of truth, so a golden can never drift from the test's input.
##
## The cases are fixed on purpose: same stage/path/name, same scene, same
## memories, same events, same history, same prefill. Any change to the prompt
## files, the assembly order or the debug dict shows up as a golden diff.
##
## The history deliberately mixes both shapes the Director can hand over:
## assistant entries as full Turn JSON (which must reach the model as spoken
## text only, docs/08 §1) and as plain text.

const PLAYER := "Ren"


## The case names, in the order the regen tool writes them.
static func case_names() -> Array[String]:
	return ["stage1_turn", "stage2_prefill"]


## A fresh context per call — build() must never see a shared, mutable one.
static func ctx(name: String) -> Dictionary:
	match name:
		"stage1_turn":
			return _stage1_turn()
		"stage2_prefill":
			return _stage2_prefill()
	return {}


## Stage 1, no path yet (docs/01 §4 assigns one at stage 2), a café scene, three
## memories, two event lines and a four-entry history.
static func _stage1_turn() -> Dictionary:
	return {
		"stage": 1,
		"path": "",
		"player_name": PLAYER,
		"scene":
		{
			"prompt": "You are in a small café after class. Two cups, one window seat.",
			"variant": "The rain outside has not stopped.",
			"event": "the player checked his phone twice",
		},
		"memories": ["gave me a music box", "loves rainy days", "reads old novels"],
		"events":
		[
			"TRIGGER: The player mentioned another girl (Sarah) for the 2nd time.",
			'OPPORTUNITY: The player just tried to close the window. You may set action to "refuse_exit".',
		],
		"history":
		[
			{"role": "user", "text": "Hi Leila-chan! This café is nice."},
			{
				"role": "assistant",
				"beats":
				[
					{
						"feeling": "shy",
						"intensity": 1,
						"cue": "none",
						"say": "Oh! N-no, it's free."
					},
					{"feeling": "warmth", "intensity": 2, "cue": "none", "say": "Sit with me?"},
				],
				"inner": "He talked to me.",
				"music": "keep",
			},
			{"role": "user", "text": "Sorry I'm late. I ran into Sarah on the way here."},
			{"role": "assistant", "text": "Sarah? You talk about her a lot."},
		],
		"player_message": "I have to head home soon, sorry.",
	}


## Stage 2 with a locked path, the runner-up's one line, an offered-enum line
## and the opt-in prefill block. stage_2.md and path_*.md are P2.13, so this
## case also pins what a missing module reports.
static func _stage2_prefill() -> Dictionary:
	return {
		"stage": 2,
		"path": "TSUN",
		"path_runner_up": "SPLIT",
		"player_name": PLAYER,
		"scene": "You are walking home in the rain. You have one small umbrella.",
		"memories": ["has a little sister", "hates the smell of cigarettes"],
		"events": ["EVENT: The player was away for 3 days. You waited."],
		"offered":
		{
			"music": ["keep", "calm", "melancholy"],
			"fx": ["none", "rain"],
			"cue": ["none", "sob", "clock_tick"],
			"action": ["none"],
		},
		"history": [{"role": "user", "text": "It's getting late."}],
		"player_message": "Can I walk with you?",
		"prefill": "\n",
	}
