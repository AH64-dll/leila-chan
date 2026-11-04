extends Node
## Boot — entry scene (docs/07 §2). Will own data loading, schema validation and
## the diegetic loading screen (docs/07 §6). For now it smokes-tests the autoload ring
## and transitions to the Title screen (P1.14).

const TITLE_SCENE_PATH := "res://scenes/Title.tscn"

const EXPECTED_AUTOLOADS: PackedStringArray = [
	"GameState",
	"Director",
	"LLM",
	"PromptBuilder",
	"SpriteResolver",
	"AudioDirector",
	"FX",
	"MetaDirector",
	"Triggers",
	"Memory",
	"Safety",
	"Steering",
	"SaveSystem",
	"Settings",
	"PauseMenu",
	"Telemetry",
]

var auto_advance := true


func _ready() -> void:
	var missing: PackedStringArray = []
	for autoload_name: String in EXPECTED_AUTOLOADS:
		if not has_node("/root/" + autoload_name):
			missing.append(autoload_name)
	if missing.is_empty():
		print(
			(
				"Boot: %d/%d autoloads registered"
				% [EXPECTED_AUTOLOADS.size() - missing.size(), EXPECTED_AUTOLOADS.size()]
			)
		)
		# P1.02: the prototype transport attaches to tools/llm/serve.sh by
		# default. `LEILA_OWN_SERVER` flips that to launching the pinned server,
		# which is what makes a stage-change dose possible (P2.03).
		if not LLM.has_backend():
			LLM.use_default_backend(prototype_backend_config())
		_wire_classifier_transport()
		if auto_advance:
			_transition_to_title()
	else:
		push_error("Boot: missing autoloads: " + ", ".join(missing))
		get_tree().quit(1)


## The prototype transport config (P1.02/P2.03). Attach is the default: a server
## started by `tools/llm/serve.sh` stays the developer's to manage. `LEILA_OWN_SERVER=1`
## makes Boot launch and supervise the pinned server instead, because the steering
## dose is a launch flag (docs/06 §4) — only a process the app started can be
## relaunched with new vectors. Owning the server also gives the docs/02 §8
## classifier a real endpoint while no vector is bound; P2.17's live config
## provider turns that tier off the moment a stage binds one (SAF-12).
## Model/binary paths come from LEILA_MODEL / LEILA_LLAMA_DIR (see tools/llm/README.md).
static func prototype_backend_config() -> Dictionary:
	var flag := OS.get_environment("LEILA_OWN_SERVER").strip_edges().to_lower()
	if flag.is_empty() or flag == "0" or flag == "false" or flag == "no":
		return {}
	return {"auto_start": true}


## docs/02 §8 classifier tier: the same local model, 8 tokens, no control
## vectors bound to the request. `LEILA_CLASSIFIER_URL` names a dedicated
## unsteered server. Without it the shared endpoint is used only when the app
## launched that server itself and its config carries no vector: an external
## `serve.sh --vector` applies its vector to *every* request and is invisible to
## the app, so an unmanaged 8089 may be steered — and a steered "no" *releases*
## a held span (SAF-3/SAF-12). The tier then stays uninstalled, so every flagged
## span fails closed to bars.
func _wire_classifier_transport() -> void:
	var gate: Variant = Safety.get("classifier_gate")
	if gate == null:
		return
	var url := OS.get_environment("LEILA_CLASSIFIER_URL").strip_edges()
	if not url.is_empty():
		## A dedicated endpoint is the operator's assertion that its server is
		## unsteered, so no launch config applies to it (SAF-3).
		gate.call("set_config_provider", Callable())
		gate.call("set_backend", SafetyClassifierHttp.new({"base_url": url}))
		return
	url = _shared_classifier_url(LLM.get_backend_config())
	if url.is_empty():
		## Expected in the prototype: the server is started by hand. An
		## informational line, not a warning — the filter is simply on tier 1.
		print(
			(
				"Boot: classifier tier disabled — the shared LLM server is launched "
				+ "outside the app (so its control vectors are unknown) or carries a "
				+ "vector, and docs/02 §8 requires dose 0. Set LEILA_CLASSIFIER_URL to "
				+ "an unsteered server; flagged spans fail closed to bars."
			)
		)
		return
	## Live, not a snapshot: the gate re-reads the config on every ask, so a vector
	## P2.03 binds after boot disables the tier instead of steering it (SAF-12).
	gate.call("set_config_provider", Callable(LLM, "get_backend_config"))
	gate.call("set_backend", SafetyClassifierHttp.new({"base_url": url}))


## The shared endpoint, or "" when the app cannot vouch for the server behind it:
## only a server the app launches itself has launch flags the config can describe,
## and only an unsteered one may answer the classifier's question.
static func _shared_classifier_url(config: Dictionary) -> String:
	if config.is_empty() or not bool(config.get("auto_start", false)):
		return ""
	if SafetyClassifierGate.is_steered_config(config):
		return ""
	return String(config.get("base_url", ""))


func _transition_to_title() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE_PATH)
