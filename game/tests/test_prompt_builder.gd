extends GdUnitTestSuite
## P1.06 — PromptBuilder: the docs/08 §1 layer order, stage/path injection,
## few-shot selection, the per-layer token report (docs/07 §3.1 budgets, incl.
## P1.05's CON-1 fixed/dynamic split) and the golden fixtures.
##
## The sliding history window and "assistant turns are spoken text" live in
## res://tests/test_prompt_builder_history.gd (gdlint caps a suite at 20 public
## methods). Golden cases: res://tests/helpers/PromptGoldenCases.gd; committed
## fixtures: res://tests/fixtures/prompts/ (regenerate with
## game/tests/tools/prompt_builder_goldens.gd when a prompt change is intended).

const BuilderScript := preload("res://autoload/PromptBuilder.gd")
const Cases := preload("res://tests/helpers/PromptGoldenCases.gd")

const PROMPTS := "res://data/prompts/"
const GOLDENS := "res://tests/fixtures/prompts/"
const SCRATCH := "user://prompt_builder_test"
## The real llama-tokenize numbers P1.05 measured for the fixed stage blocks.
const REAL_STAGE0_TOKENS := 857
const REAL_STAGE1_TOKENS := 873
const ESTIMATE_TOLERANCE := 0.05


func _builder() -> BuilderScript:
	var builder: BuilderScript = auto_free(BuilderScript.new())
	return builder


## A scratch prompt dir, wiped first: a test never writes the shipped content
## and never inherits another test's files.
func _scratch_dir(case: String) -> String:
	var dir := SCRATCH.path_join(case)
	_wipe(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _wipe(dir: String) -> void:
	var handle := DirAccess.open(dir)
	if handle == null:
		return
	for file: String in handle.get_files():
		handle.remove(file)
	for sub: String in handle.get_directories():
		_wipe(dir.path_join(sub))
		DirAccess.remove_absolute(dir.path_join(sub))


func _write_file(dir: String, name: String, text: String) -> void:
	var file := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	assert_object(file).override_failure_message("cannot write " + name).is_not_null()
	file.store_string(text)
	file.close()


func _system(result: Dictionary) -> String:
	return String(result["messages"][0]["content"])


func _roles(result: Dictionary) -> Array:
	var roles: Array = []
	for message: Dictionary in result["messages"]:
		roles.append(String(message["role"]))
	return roles


func _entry(role: String, text: String) -> Dictionary:
	return {"role": role, "text": text}


## A context with every layer populated, for the assembly-order assertions.
func _full_ctx() -> Dictionary:
	return {
		"stage": 1,
		"path": "",
		"player_name": "Ren",
		"scene": "You are in a small café after class.",
		"memories": ["gave me a music box"],
		"events": ["TRIGGER: The player mentioned another girl (Sarah)."],
		"history": [_entry("user", "Hello."), _entry("assistant", "Hi!")],
		"player_message": "So, about that book...",
	}


# --- acceptance criterion 1: assembly order exactly docs/08 §1 ---------------


func test_system_layers_follow_docs08_order_without_gaps() -> void:
	var result := _builder().build(_full_ctx())
	var system := _system(result)
	var persona := FileAccess.get_file_as_string(PROMPTS + "persona.md").strip_edges()
	var stage := FileAccess.get_file_as_string(PROMPTS + "stage_1.md").strip_edges()
	var rules := FileAccess.get_file_as_string(PROMPTS + "rules.md").strip_edges()
	var glosses := FileAccess.get_file_as_string(PROMPTS + "glosses.md").strip_edges()
	var marks := {
		"persona": system.find(persona.substr(0, 40)),
		"player": system.find("The player is a boy called Ren."),
		"stage": system.find(stage.substr(0, 40)),
		"scene": system.find("You are in a small café after class."),
		"memories": system.find("Things you know about Ren:"),
		"events": system.find("TRIGGER: The player mentioned another girl (Sarah)."),
		"rules": system.find(rules.substr(0, 40)),
		"glosses": system.find(glosses.substr(0, 40)),
	}
	var previous := -1
	for key: String in [
		"persona", "player", "stage", "scene", "memories", "events", "rules", "glosses"
	]:
		var at := int(marks[key])
		var missing_message := "%s is missing from the system message" % key
		assert_int(at).override_failure_message(missing_message).is_greater_equal(0)
		var order_message := "%s is out of docs/08 §1 order" % key
		assert_int(at).override_failure_message(order_message).is_greater(previous)
		previous = at
	var order: Array = result["debug"]["layer_order"]
	var expected := ["persona", "player", "stage", "path", "scene", "memories", "events", "rules"]
	assert_array(order).is_equal(expected)
	# Empty layers leave no gap and no stray blank line.
	var bare := _full_ctx()
	bare["memories"] = []
	bare["events"] = []
	var bare_system := _system(_builder().build(bare))
	assert_str(bare_system).not_contains("Things you know about")
	assert_str(bare_system).not_contains("TRIGGER:")
	assert_str(bare_system).not_contains("\n\n")


func test_scene_layer_composes_prompt_variant_and_event() -> void:
	var ctx := _full_ctx()
	ctx["scene"] = {
		"prompt": "Rainy walk.",
		"variant": "It is raining inside too.",
		"event": "the umbrella tilts",
	}
	var system := _system(_builder().build(ctx))
	assert_str(system).contains("Rainy walk.")
	assert_str(system).contains("It is raining inside too.")
	assert_str(system).contains("EVENT: the umbrella tilts")
	var prompt_at := system.find("Rainy walk.")
	var event_at := system.find("EVENT: the umbrella tilts")
	assert_int(prompt_at).is_less(event_at)


func test_memories_keep_the_newest_eight() -> void:
	var ctx := _full_ctx()
	var facts: Array[String] = []
	for i: int in 11:
		facts.append("fact_%d" % i)
	ctx["memories"] = facts
	var result := _builder().build(ctx)
	var system := _system(result)
	assert_str(system).contains("fact_10")
	assert_str(system).not_contains("fact_0 ")
	assert_int(system.count("- fact_")).is_equal(8)
	assert_array(result["debug"]["warnings"]).contains("memories_trimmed_to_8")


# --- acceptance criterion 3: per-layer token budget in a debug dict ---------


func test_debug_reports_tokens_for_every_layer() -> void:
	var result := _builder().build(_full_ctx())
	var debug: Dictionary = result["debug"]
	var layers := ["persona", "player", "stage", "path", "scene", "memories", "events", "rules"]
	assert_dict(debug["layers"]).contains_keys(layers)
	var sum := 0
	for name: String in debug["layer_order"]:
		var layer: Dictionary = debug["layers"][name]
		assert_dict(layer).contains_keys(["tokens", "chars", "present", "group", "files"])
		assert_int(int(layer["tokens"])).is_greater_equal(0)
		assert_int(int(layer["chars"])).is_greater_equal(0)
		if bool(layer["present"]):
			assert_int(int(layer["tokens"])).is_greater(0)
		sum += int(layer["tokens"])
	assert_int(int(debug["tokens"]["system_message"])).is_equal(sum)
	assert_int(int(debug["tokens"]["fixed"]) + int(debug["tokens"]["dynamic"])).is_equal(sum)
	var total := sum + int(debug["tokens"]["history"])
	assert_int(int(debug["tokens"]["total"])).is_equal(total)
	assert_dict(debug["budgets"]).contains_keys(
		["system", "memories", "scene", "history", "output"]
	)
	assert_str(String(debug["token_counter"])).is_equal("estimate")
	assert_str(String(debug["layers"]["persona"]["files"][0])).is_equal("persona.md")
	assert_array(debug["layers"]["rules"]["files"]).is_equal(["rules.md", "glosses.md"])
	# The absent path layer is reported as absent, not as an empty file.
	assert_bool(bool(debug["layers"]["path"]["present"])).is_false()
	assert_array(debug["layers"]["path"]["files"]).is_empty()


func test_fixed_and_dynamic_totals_answer_the_p1_05_carry_over() -> void:
	var builder := _builder()
	var result := builder.build(_full_ctx())
	var debug: Dictionary = result["debug"]
	var fixed := 0
	var dynamic := 0
	for name: String in debug["layer_order"]:
		var layer: Dictionary = debug["layers"][name]
		if String(layer["group"]) == "fixed":
			fixed += int(layer["tokens"])
		else:
			dynamic += int(layer["tokens"])
	assert_int(int(debug["tokens"]["fixed"])).is_equal(fixed)
	assert_int(int(debug["tokens"]["dynamic"])).is_equal(dynamic)
	var fixed_total := int(debug["tokens"]["fixed"])
	var dynamic_total := int(debug["tokens"]["dynamic"])
	assert_int(fixed_total).is_greater(dynamic_total)
	# The fixed block is the one P1.05 measured at 857/873 real tokens.
	var stage1_real := float(REAL_STAGE1_TOKENS)
	assert_float(float(fixed_total)).is_equal_approx(stage1_real, stage1_real * ESTIMATE_TOLERANCE)
	# A clean assembly stays inside every doc line; a fat one names the lines.
	assert_array(debug["over_budget"]).is_empty()
	var fat_ctx := _full_ctx()
	fat_ctx["scene"] = "x ".repeat(400)
	fat_ctx["memories"] = ["a very long memory ".repeat(40)]
	var fat := _builder().build(fat_ctx)
	assert_array(fat["debug"]["over_budget"]).contains(["memories", "scene"])


func test_injected_token_counter_replaces_the_estimate() -> void:
	var builder := _builder()
	var calls := [0]
	builder.set_token_counter(
		func(text: String) -> int:
			calls[0] += 1
			return text.split(" ").size()
	)
	var result := builder.build(_full_ctx())
	assert_str(String(result["debug"]["token_counter"])).is_equal("injected")
	assert_int(calls[0]).is_greater(0)
	# "The player is a boy called Ren." is seven space-separated words.
	assert_int(int(result["debug"]["layers"]["player"]["tokens"])).is_equal(7)
	var system_tokens := int(result["debug"]["tokens"]["system_message"])
	var parts := int(result["debug"]["tokens"]["fixed"]) + int(result["debug"]["tokens"]["dynamic"])
	assert_int(system_tokens).is_equal(parts)


func test_token_estimate_is_calibrated_against_the_real_tokenizer() -> void:
	# P1.05 measured 857 (stage 0) and 873 (stage 1) tokens with llama-tokenize
	# for the same fixed assembly; the estimate must stay within 5%.
	var builder := _builder()
	for stage: int in [0, 1]:
		var result := builder.build({"stage": stage, "player_name": "Ren"})
		var estimated := float(result["debug"]["tokens"]["fixed"])
		var real := float(REAL_STAGE0_TOKENS if stage == 0 else REAL_STAGE1_TOKENS)
		var drift := "stage %d estimate %.0f vs real %.0f" % [stage, estimated, real]
		assert_float(estimated).override_failure_message(drift).is_equal_approx(
			real, real * ESTIMATE_TOLERANCE
		)


# --- acceptance criterion 4: golden files ----------------------------------


func test_goldens_match_the_committed_fixtures() -> void:
	for name: String in Cases.case_names():
		var path := GOLDENS + name + ".json"
		var exists_message := "missing golden " + path
		assert_bool(FileAccess.file_exists(path)).override_failure_message(exists_message).is_true()
		var expected := FileAccess.get_file_as_string(path)
		var actual := JSON.stringify(_builder().build(Cases.ctx(name)), "  ") + "\n"
		var hint := "regenerate with game/tests/tools/prompt_builder_goldens.gd"
		var drifted := "golden %s drifted — %s" % [name, hint]
		assert_str(actual).override_failure_message(drifted).is_equal(expected)


# --- stage / path injection, few-shot selection -----------------------------


func test_stage_injection_selects_the_stage_module() -> void:
	var builder := _builder()
	var stage0 := _system(builder.build({"stage": 0, "player_name": "Ren"}))
	var stage1 := _system(builder.build({"stage": 1, "player_name": "Ren"}))
	assert_str(stage0).contains("STAGE 0 — Honeymoon.")
	assert_str(stage0).not_contains("STAGE 1")
	assert_str(stage1).contains("STAGE 1 — Hairline cracks.")
	assert_str(stage1).not_contains("STAGE 0")
	# docs/08 §3: each stage file carries its two few-shot exchanges.
	assert_int(stage0.count("Player: ")).is_equal(2)
	assert_int(stage1.count("Player: ")).is_equal(2)


func test_player_name_reaches_persona_and_the_few_shots() -> void:
	var system := _system(_builder().build({"stage": 0, "player_name": "Ren"}))
	assert_str(system).not_contains("{player_name}")
	assert_str(system).contains("Ren calls you Leila-chan.")
	assert_str(system).contains("I love them, Ren.")
	var empty := _system(_builder().build({"stage": 0, "player_name": "   "}))
	assert_str(empty).contains("Senpai calls you Leila-chan.")


func test_path_layer_needs_stage_two_and_reports_the_runner_up() -> void:
	var dir := _scratch_dir("path_layer")
	_write_file(dir, "persona.md", "You are Leila.")
	_write_file(dir, "stage_2.md", "STAGE 2 — Leaks.")
	_write_file(dir, "rules.md", "Respond ONLY with JSON.")
	_write_file(dir, "glosses.md", "Feelings:")
	_write_file(dir, "path_TSUN.md", "TSUN   You act cold and superior.\nPlayer: Hmph.\nYou: {}")
	_write_file(
		dir,
		"path_SPLIT.md",
		"SPLIT   The player is either perfect or a traitor.\nPlayer: Runner-up example."
	)
	var builder := _builder()
	builder.prompt_dir = dir
	var early := builder.build({"stage": 1, "path": "TSUN", "player_name": "Ren"})
	assert_str(_system(early)).not_contains("TSUN")
	assert_array(early["debug"]["layers"]["path"]["files"]).is_empty()
	var late := builder.build({"stage": 2, "path": "TSUN", "path_runner_up": "SPLIT"})
	var system := _system(late)
	assert_str(system).contains("TSUN   You act cold and superior.")
	assert_str(system).contains("SPLIT   The player is either perfect or a traitor.")
	# docs/08 §1: one line from the runner-up, not its examples.
	assert_str(system).not_contains("Runner-up example.")
	# The primary path module is included whole (its own examples belong to it).
	assert_str(system).contains("Player: Hmph.")
	var path_at := system.find("TSUN   You act")
	var runner_at := system.find("SPLIT   The player")
	assert_int(path_at).is_less(runner_at)


func test_missing_modules_are_reported_never_invented() -> void:
	var dir := _scratch_dir("missing")
	_write_file(dir, "persona.md", "You are Leila.")
	var builder := _builder()
	builder.prompt_dir = dir
	var result := builder.build({"stage": 4, "path": "", "player_name": "Ren"})
	assert_array(result["debug"]["missing"]).contains(["stage_4.md", "rules.md", "glosses.md"])
	assert_array(result["debug"]["warnings"]).contains("path_unassigned_at_stage_4")
	assert_str(_system(result)).not_contains("STAGE 4")
	assert_bool(bool(result["debug"]["layers"]["stage"]["present"])).is_false()
	assert_bool(bool(result["debug"]["layers"]["persona"]["present"])).is_true()


func test_offered_values_reach_the_rules_layer() -> void:
	var ctx := _full_ctx()
	ctx["offered"] = {
		"music": ["keep", "calm"],
		"fx": ["none", "rain"],
		"cue": ["none", "sob"],
		"action": ["none", "refuse_exit"],
	}
	var system := _system(_builder().build(ctx))
	assert_str(system).contains("Offered this turn — ")
	assert_str(system).contains("music: keep, calm")
	assert_str(system).contains("cue: none, sob")
	assert_str(system).contains("action: none, refuse_exit")
	var plain := _system(_builder().build(_full_ctx()))
	assert_str(plain).not_contains("Offered this turn")


# --- the message array, the prefill block and purity ------------------------


func test_message_array_is_system_history_player_then_prefill() -> void:
	var ctx := _full_ctx()
	var plain := _builder().build(ctx)
	assert_array(_roles(plain)).is_equal(["system", "user", "assistant", "user"])
	assert_str(String(plain["messages"][3]["content"])).is_equal("So, about that book...")
	assert_str(String(plain["debug"]["prefill"])).is_empty()
	ctx["prefill"] = BuilderScript.PREFILL_NEWLINE
	var prefilled := _builder().build(ctx)
	var expected := ["system", "user", "assistant", "user", "assistant"]
	assert_array(_roles(prefilled)).is_equal(expected)
	assert_str(String(prefilled["messages"][4]["content"])).is_equal("\n")
	assert_str(String(prefilled["debug"]["prefill"])).is_equal("\n")
	# An empty player turn warns and is not sent as an empty message.
	var empty_ctx := _full_ctx()
	empty_ctx["player_message"] = "   "
	var empty := _builder().build(empty_ctx)
	assert_array(_roles(empty)).is_equal(["system", "user", "assistant"])
	assert_array(empty["debug"]["warnings"]).contains("player_message_empty")


func test_build_is_pure_and_repeatable() -> void:
	var builder := _builder()
	var ctx := Cases.ctx("stage1_turn")
	var before := ctx.duplicate(true)
	var first := builder.build(ctx)
	var second := builder.build(ctx)
	assert_dict(ctx).is_equal(before)
	assert_str(JSON.stringify(first, "  ")).is_equal(JSON.stringify(second, "  "))
	builder.clear_cache()
	assert_str(JSON.stringify(builder.build(ctx), "  ")).is_equal(JSON.stringify(first, "  "))


# --- P2.13: the shipped stage_2..5 and path_YANDERE/AWAKE modules -----------


func test_shipped_stage_and_path_modules_fill_the_budget() -> void:
	# Every stage 2-5 × shipped path builds without a missing module, carries the
	# two few-shots a stage × path assembly must show, and stays inside docs/07
	# §3.1's 900-token fixed budget even with the runner-up line docs/08 §1 adds.
	var builder := _builder()
	for stage: int in [2, 3, 4, 5]:
		for path: String in ["YANDERE", "AWAKE"]:
			var runner_up := "AWAKE" if path == "YANDERE" else "YANDERE"
			var ctx := {
				"stage": stage,
				"path": path,
				"player_name": "Ren",
				"path_runner_up": runner_up,
			}
			var result := builder.build(ctx)
			var label := "stage %d %s" % [stage, path]
			assert_array(result["debug"]["missing"]).override_failure_message(label).is_empty()
			var system := _system(result)
			assert_bool(system.contains("STAGE %d" % stage)).is_true()
			assert_bool(system.contains(path)).override_failure_message(label).is_true()
			assert_int(system.count("Player: ")).override_failure_message(label).is_equal(2)
			var tokens := int(result["debug"]["tokens"]["system"])
			var message := "%s system layer = %d tokens (budget 900)" % [label, tokens]
			assert_int(tokens).override_failure_message(message).is_less_equal(900)
