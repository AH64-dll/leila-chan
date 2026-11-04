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
		# P1.02: the prototype transport attaches to tools/llm/serve.ps1 by
		# default. A later boot task can pass auto_start=true to own the process.
		if not LLM.has_backend():
			LLM.use_default_backend()
		_wire_classifier_transport()
		if auto_advance:
			_transition_to_title()
	else:
		push_error("Boot: missing autoloads: " + ", ".join(missing))
		get_tree().quit(1)


## docs/02 §8 classifier tier: the same local model, 8 tokens, no control
## vectors bound to the request. `LEILA_CLASSIFIER_URL` names a dedicated
## unsteered server. Without it the shared LLM endpoint is used only while the
## server behind it carries no control vectors: llama-server binds vectors at
## launch (LlamaServerProcess._build_args), so a steered server steers this
## request too, and a "no" verdict *releases* a held span — a steered answer is
## not merely an accuracy problem (SAF-3). With vectors bound and no explicit
## URL the tier stays uninstalled, so every flagged span fails closed to bars.
func _wire_classifier_transport() -> void:
	var gate: Variant = Safety.get("classifier_gate")
	if gate == null:
		return
	var url := OS.get_environment("LEILA_CLASSIFIER_URL").strip_edges()
	if url.is_empty():
		url = _unsteered_shared_url()
	if url.is_empty():
		return
	gate.call("set_backend", SafetyClassifierHttp.new({"base_url": url}))


## The shared endpoint, unless the server behind it is steered (SAF-3).
func _unsteered_shared_url() -> String:
	if not LLM.has_backend():
		return ""
	var raw: Variant = LLM.get_backend().get("config")
	if not raw is Dictionary:
		return ""
	var config: Dictionary = raw
	if _config_is_steered(config):
		push_warning(
			(
				"Boot: classifier tier disabled — the shared LLM server carries control "
				+ "vectors and docs/02 §8 requires dose 0. Set LEILA_CLASSIFIER_URL to an "
				+ "unsteered server; flagged spans fail closed to bars."
			)
		)
		return ""
	return String(config.get("base_url", ""))


## Any bound control vector — a configured one or a hand-added launch flag —
## makes the shared server unusable for the classifier: llama-server applies
## vectors to every request and there is no per-request dose.
static func _config_is_steered(config: Dictionary) -> bool:
	var vectors: Variant = config.get("control_vectors", [])
	if vectors is Array:
		for vector: Variant in vectors:
			if vector is Dictionary and not String(vector.get("path", "")).is_empty():
				return true
	for arg: Variant in config.get("extra_args", PackedStringArray()):
		if String(arg).contains("control-vector"):
			return true
	return false


func _transition_to_title() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE_PATH)
