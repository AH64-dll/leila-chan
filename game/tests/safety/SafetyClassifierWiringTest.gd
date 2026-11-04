extends GdUnitTestSuite
## P2.17 round 3 — the Boot ↔ classifier wiring (SAF-12). Which shared endpoint
## the tier may use is decided from the launched server's config, and the gate
## re-reads that config on every ask, so the refusal cannot go stale.
##
## The suite touches the shared Safety/LLM autoloads, so `after_test` restores
## exactly what it found: a leaked transport here would change every later suite.

const BootScript := preload("res://scenes/Boot.gd")
const SHARED := "http://127.0.0.1:8089"

var _old_backend: Variant
var _old_provider: Callable
var _old_llm: LLMBackend
var _old_env := ""


func before_test() -> void:
	var gate := Safety.classifier_gate
	_old_backend = gate.backend
	_old_provider = gate.config_provider
	_old_llm = LLM.get_backend()
	_old_env = OS.get_environment("LEILA_CLASSIFIER_URL")
	OS.set_environment("LEILA_CLASSIFIER_URL", "")


func after_test() -> void:
	var gate := Safety.classifier_gate
	if gate != null:
		var installed: Variant = gate.backend
		if installed != _old_backend and installed is SafetyClassifierHttp:
			(installed as SafetyClassifierHttp).shutdown()
		gate.set_backend(_old_backend)
		gate.set_config_provider(_old_provider)
	LLM.set_backend(_old_llm)
	OS.set_environment("LEILA_CLASSIFIER_URL", _old_env)


## Only a server the app launches itself (`auto_start`) has launch flags the app
## can read: an external `serve.sh --vector` applies its vector to every request
## and is invisible, so an unmanaged 8089 is refused and the tier stays
## uninstalled — flagged spans then fail closed to bars (SAF-3/SAF-12).
func test_shared_endpoint_requires_an_app_launched_unsteered_server() -> void:
	assert_str(BootScript._shared_classifier_url({})).is_equal("")
	assert_str(BootScript._shared_classifier_url({"base_url": SHARED})).is_equal("")
	(
		assert_str(BootScript._shared_classifier_url({"base_url": SHARED, "auto_start": true}))
		. is_equal(SHARED)
	)
	(
		assert_str(
			(
				BootScript
				. _shared_classifier_url(
					{
						"base_url": SHARED,
						"auto_start": true,
						"control_vectors": [{"path": "evil_qwen_unit.gguf", "scale": 4}],
					}
				)
			)
		)
		. is_equal("")
	)
	(
		assert_str(
			(
				BootScript
				. _shared_classifier_url(
					{
						"base_url": SHARED,
						"auto_start": true,
						"extra_args": PackedStringArray(["--control-vector-scaled", "v.gguf:4"]),
					}
				)
			)
		)
		. is_equal("")
	)


## SAF-12: the refuse path has to fire on the gate that is actually installed. An
## unmanaged server leaves the tier uninstalled; an app-launched unsteered one
## installs the transport and registers the live config source the gate re-reads.
func test_wiring_refuses_an_unmanaged_server_and_installs_a_managed_one() -> void:
	var gate := Safety.classifier_gate
	assert_object(gate).is_not_null()
	var boot: Node = auto_free(BootScript.new())
	## The default boot: an external `serve.sh` whose flags are invisible.
	LLM.set_backend(LlamaServerBackend.new({}))
	boot.call("_wire_classifier_transport")
	assert_bool(gate.backend == null).is_true().append_failure_message(
		"an unmanaged shared server must not receive the classifier"
	)
	## The app owns the server and its config carries no vector.
	LLM.set_backend(LlamaServerBackend.new({"auto_start": true}))
	boot.call("_wire_classifier_transport")
	assert_bool(gate.backend is SafetyClassifierHttp).is_true().append_failure_message(
		"an app-launched unsteered server must install the transport"
	)
	assert_bool(gate.config_provider.is_valid()).is_true().append_failure_message(
		"the gate must be able to re-read the live launch config"
	)


## A dedicated URL is the operator's assertion: it is used even while the shared
## LLM server is steered, and that server's launch config no longer applies.
func test_dedicated_url_overrides_the_shared_config() -> void:
	var gate := Safety.classifier_gate
	var boot: Node = auto_free(BootScript.new())
	LLM.set_backend(
		LlamaServerBackend.new(
			{"auto_start": true, "control_vectors": [{"path": "evil_qwen_unit.gguf", "scale": 4}]}
		)
	)
	OS.set_environment("LEILA_CLASSIFIER_URL", "http://127.0.0.1:8099")
	boot.call("_wire_classifier_transport")
	assert_bool(gate.backend is SafetyClassifierHttp).is_true()
	assert_str((gate.backend as SafetyClassifierHttp).base_url).is_equal("http://127.0.0.1:8099")
	assert_bool(gate.config_provider.is_valid()).is_false().append_failure_message(
		"a dedicated endpoint must not read the shared server's config"
	)
