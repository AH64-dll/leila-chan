extends Node
## Boot — entry scene (docs/07 §2). Will own data loading, schema validation and
## the diegetic loading screen (docs/07 §6). For now it smokes-tests the autoload ring
## and transitions to the Title screen (P1.14).

const TITLE_SCENE_PATH := "res://scenes/Title.tscn"
const DATE_SCENE_PATH := "res://scenes/Date.tscn"
const LOADING_SCENE_PATH := "res://scenes/Loading.tscn"

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

## One warning per process for a LEILA_BACKEND value an export ignores (backend_kind_for).
static var _warned_export_override := false

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
		# P1.02: the prototype transport attaches to tools/llm/serve.sh by default.
		# `LEILA_OWN_SERVER` flips that to the dev-only server relaunch (P2.03, P4.04);
		# an export always runs native, so it never reaches that path.
		if not LLM.has_backend():
			_install_backend()
		_wire_classifier_transport()
		if auto_advance:
			_advance()
	else:
		push_error("Boot: missing autoloads: " + ", ".join(missing))
		get_tree().quit(1)


## The dev server transport config (P1.02/P2.03). Attach is the default: a server
## started by `tools/llm/serve.sh` stays the developer's to manage. `LEILA_OWN_SERVER=1`
## makes Boot launch and supervise the pinned server instead. That is the dev-only
## restart path: the steering dose is a launch flag there (docs/06 §4), so only a
## process the app started can be relaunched with new vectors. An export never reaches
## it: an export always runs native (`backend_kind_for`), where the dose binds per turn
## and a stage change is an instant dose change. Owning the server also gives the
## docs/02 §8 classifier a real endpoint while no vector is bound; P2.17's live config
## provider turns that tier off the moment a stage binds one (SAF-12).
## Model/binary paths come from LEILA_MODEL / LEILA_LLAMA_DIR (see tools/llm/README.md).
static func prototype_backend_config() -> Dictionary:
	var flag := OS.get_environment("LEILA_OWN_SERVER").strip_edges().to_lower()
	if flag.is_empty() or flag == "0" or flag == "false" or flag == "no":
		return {}
	return {"auto_start": true}


## P4.04 backend switch. In a dev run `LEILA_BACKEND` = native or server wins, and the
## server is the default. An export always runs native: it ships no server, so the server
## transport and its relaunch cannot be reached from a shipped build.
static func backend_kind() -> String:
	return backend_kind_for(OS.get_environment("LEILA_BACKEND"), OS.has_feature("template"))


## The decision behind backend_kind(), with the environment and the export flag passed
## in so a test can exercise every case. An export is always native: any other
## LEILA_BACKEND value is ignored, with one warning per process. A dev run takes native
## or server, warns on an unknown value, and otherwise uses server.
static func backend_kind_for(env_value: String, exported: bool) -> String:
	var wanted := env_value.strip_edges().to_lower()
	if exported:
		if not wanted.is_empty() and wanted != "native" and not _warned_export_override:
			_warned_export_override = true
			push_warning(
				"Boot: LEILA_BACKEND=%s is ignored in an export; the build runs native" % env_value
			)
		return "native"
	if wanted == "native" or wanted == "server":
		return wanted
	if not wanted.is_empty():
		push_warning(
			"Boot: unknown LEILA_BACKEND=%s (want native or server); using server" % env_value
		)
	return "server"


## P4.04/P4.09: whether this launch installs NativeBackend. An export always does, even
## with no GDExtension behind it: the engine is then missing, and the loading screen shows
## `no_extension` rather than a server that does not exist. A dev run goes native only when
## it is asked for and the class is registered.
static func native_required(kind: String, class_exists: bool, exported: bool) -> bool:
	if exported:
		return true
	return kind == "native" and class_exists


## P4.04: install the transport for this launch. The LEILA_OWN_SERVER relaunch (the dev
## server transport) is reachable only from the dev branch below. An export returns at the
## native branch and never gets there.
func _install_backend() -> void:
	var kind := backend_kind()
	if native_required(kind, ClassDB.class_exists("LeilaLLM"), OS.has_feature("template")):
		LLM.use_native_backend()
		return
	if kind == "native":
		push_warning(
			(
				"Boot: LEILA_BACKEND=native but the LeilaLLM GDExtension is not registered; "
				+ "run native/build_linux.sh. Using the server transport."
			)
		)
	LLM.use_default_backend(prototype_backend_config())


## Instance entry for _ready and the wiring test. The wiring is static (below), so the
## full-run tool wires the same classifier without a Boot node.
func _wire_classifier_transport() -> void:
	wire_classifier_transport()


## docs/02 §8 classifier tier: the same local model, 8 tokens, no control
## vectors bound to the request. `LEILA_CLASSIFIER_URL` names a dedicated
## unsteered server. Without it the shared endpoint is used only when the app
## launched that server itself and its config carries no vector: an external
## `serve.sh --vector` applies its vector to *every* request and is invisible to
## the app, so an unmanaged 8089 may be steered — and a steered "no" *releases*
## a held span (SAF-3/SAF-12). The tier then stays uninstalled, so every flagged
## span fails closed to bars.
static func wire_classifier_transport() -> void:
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


## The in-process backend for a tool that runs without Boot (the full-run driver). It
## installs the native transport when none is installed, wires the safety classifier as
## the game does, and blocks until the model loads, so call it on the main thread. Returns
## the model label, or "" after an error has been pushed.
static func prepare_native_backend() -> String:
	if not LLM.has_backend():
		LLM.use_native_backend()
	var backend := LLM.get_backend() as NativeBackend
	if backend == null:
		push_error("full_run: --backend=native needs the native backend, but another is set")
		return ""
	wire_classifier_transport()
	var loaded := backend.ensure_loaded()
	if not bool(loaded.get("ok", false)):
		var error: Dictionary = loaded.get("error", {})
		push_error(
			(
				"full_run: the native model did not load (%s): %s"
				% [String(error.get("code", "unknown")), String(error.get("message", ""))]
			)
		)
		return ""
	var file := backend.resolved_model_path().get_file()
	if file.is_empty():
		file = NativeBackend.MODEL_FILE
	return "%s · %s" % [file, String(backend.device_info().get("device", "unknown"))]


## docs/05 §1.1 M03: on a cold open the launch goes straight into the date. The
## decision belongs to the P3.09 module (stage gate, once per save); this only
## routes it.
func _advance() -> void:
	if LLM.get_backend() is NativeBackend:
		get_tree().change_scene_to_file.call_deferred(LOADING_SCENE_PATH)
		return
	get_tree().change_scene_to_file.call_deferred(next_scene())


## See next_scene(). Kept as an instance method for callers that already hold a Boot.
func initial_scene_path() -> String:
	return next_scene()


## The scene this launch opens on. Static, so the P4.08 loading screen can call it without
## a Boot node. It also loads the save a cold open resumes (there is no title screen in
## between to press Continue), so it is the one call that both decides and prepares; a
## save that will not load falls back to the title, never to a half-loaded game (the P2.20
## rule).
static func next_scene() -> String:
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
