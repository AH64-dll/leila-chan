extends Node
## Boot — entry scene (docs/07 §2). Will own data loading, schema validation and
## the diegetic loading screen (docs/07 §6). For now it smokes-tests the autoload ring
## and transitions to the Title screen (P1.14).

const TITLE_SCENE_PATH := "res://scenes/Title.tscn"
const DATE_SCENE_PATH := "res://scenes/Date.tscn"

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
			_install_backend()
		_wire_classifier_transport()
		if auto_advance:
			_advance()
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


## P4.04 backend switch. `LEILA_BACKEND` = native or server wins; otherwise an exported
## build uses native (it ships no server) and a dev run keeps the server transport.
static func backend_kind() -> String:
	return backend_kind_for(OS.get_environment("LEILA_BACKEND"), OS.has_feature("template"))


## The decision behind backend_kind(), with the environment and the export flag passed
## in so a test can exercise every case. An unknown value warns and takes the default.
static func backend_kind_for(env_value: String, exported: bool) -> String:
	var fallback := "native" if exported else "server"
	var wanted := env_value.strip_edges().to_lower()
	if wanted == "native" or wanted == "server":
		return wanted
	if not wanted.is_empty():
		push_warning(
			(
				"Boot: unknown LEILA_BACKEND=%s (want native or server); using %s"
				% [env_value, fallback]
			)
		)
	return fallback


## P4.04: install the transport for this launch. `native` without the GDExtension
## falls back to the server transport, as today; the player-facing error is later work.
func _install_backend() -> void:
	if backend_kind() == "native":
		if ClassDB.class_exists("LeilaLLM"):
			LLM.use_native_backend()
			return
		push_warning(
			(
				"Boot: LEILA_BACKEND=native but the LeilaLLM GDExtension is not registered; "
				+ "run native/build_linux.sh. Using the server transport."
			)
		)
	LLM.use_default_backend(prototype_backend_config())


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
	var native: Variant = LLM.get_backend()
	if (
		native is NativeBackend
		and OS.get_environment("LEILA_CLASSIFIER_URL").strip_edges().is_empty()
	):
		## The classifier's context never carries a vector, whatever the turn's dose is,
		## so no launch config can steer it (docs/02 §8, SAF-3).
		gate.call("set_config_provider", Callable())
		gate.call("set_backend", NativeSafetyClassifier.new(native))
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


## docs/05 §1.1 M03: on a cold open the launch goes straight into the date. The
## decision belongs to the P3.09 module (stage gate, once per save); this only
## routes it.
func _advance() -> void:
	if initial_scene_path() == DATE_SCENE_PATH:
		get_tree().change_scene_to_file.call_deferred(DATE_SCENE_PATH)
		return
	_transition_to_title()


## The scene this launch opens on. `initial_scene_path()` also loads the save a
## cold open resumes (there is no title screen in between to press Continue), so
## it is the one call that both decides and prepares; a save that will not load
## falls back to the title, never to a half-loaded game (the P2.20 rule).
func initial_scene_path() -> String:
	var meta := MetaEventsM01.find(MetaDirector)
	if meta == null or not meta.has_method("cold_open_requested"):
		return TITLE_SCENE_PATH
	if not bool(meta.call("cold_open_requested")):
		return TITLE_SCENE_PATH
	var loaded: Dictionary = SaveSystem.load_latest()
	if not bool(loaded.get("ok", false)):
		push_warning("Boot: cold open skipped — %s" % String(loaded.get("message", "")))
		return TITLE_SCENE_PATH
	return DATE_SCENE_PATH


func _transition_to_title() -> void:
	get_tree().change_scene_to_file.call_deferred(TITLE_SCENE_PATH)
