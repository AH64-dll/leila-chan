extends GdUnitTestSuite
## P3.14 — the pure special-name rules (docs/08 §1.5): "Leila", the opt-in OS
## username (matched through the characters the field cannot type) and the six
## ui.json lines they render. The scene-level flows live in
## `NewGameNameRulesTest.gd`; no fixture is needed here — the rules are pure and
## the Safety autoload is exercised in place.


func test_validate_os_username_match_when_opted_in() -> void:
	var res := PlayerNameRules.validate("amr", Callable(), {"os_username": "amr"})
	assert_bool(bool(res["valid"])).is_true()
	assert_bool(bool(res["is_os_username"])).is_true()
	assert_str(String(res["message"])).is_equal("You told me the truth. Good.")
	assert_str(String(res["resolved_name"])).is_equal("amr")


func test_validate_os_username_not_offered_is_just_a_name() -> void:
	# Opt-in off = the caller passes "" (Settings.os_username() never leaks
	# it); the same typed name is an ordinary valid name, no special line.
	var res := PlayerNameRules.validate("amr", Callable(), {"os_username": ""})
	assert_bool(bool(res["valid"])).is_true()
	assert_bool(bool(res["is_os_username"])).is_false()
	assert_str(String(res["message"])).is_equal("")


func test_validate_leila_beats_os_username_special() -> void:
	var res := PlayerNameRules.validate("Leila", Callable(), {"os_username": "Leila"})
	assert_bool(bool(res["is_special_leila"])).is_true()
	assert_str(String(res["message"])).is_equal("That's *my* name. …Do you want to be me?")


func test_os_username_with_underscore_or_digits_is_reachable() -> void:
	# The field rejects "_" and digits (docs/08 §1.5), so an account name like
	# "john_doe" or "jdoe123" can never be typed verbatim — the match compares
	# the letters-only projection of both sides, or the truth line is
	# unreachable for those players (DES-4).
	var underscore := PlayerNameRules.validate("John Doe", Callable(), {"os_username": "john_doe"})
	assert_bool(bool(underscore["is_os_username"])).is_true()
	assert_str(String(underscore["message"])).is_equal("You told me the truth. Good.")
	assert_str(String(underscore["resolved_name"])).is_equal("John Doe")
	var digits := PlayerNameRules.validate("Jdoe", Callable(), {"os_username": "jdoe123"})
	assert_bool(bool(digits["is_os_username"])).is_true()
	# Any other name still gets no line.
	var other := PlayerNameRules.validate("Ren", Callable(), {"os_username": "jdoe123"})
	assert_bool(bool(other["is_os_username"])).is_false()


func test_name_lines_come_from_ui_json() -> void:
	# docs/07 §2: the writer's lines live in data/ui.json, not in code. The six
	# §1.5 lines exist in both the file and UiConfig.DEFAULTS, and the file's
	# values are what PlayerNameRules ships (DES-5).
	var section: Dictionary = UiConfig.load_config().get("new_game", {})
	var defaults: Dictionary = UiConfig.DEFAULTS.get("new_game", {})
	for key: String in [
		"pout_unsafe",
		"leila_special",
		"os_username_special",
		"shadow_name",
		"invalid_characters",
		"too_long",
	]:
		assert_bool(section.has(key)).is_true()
		assert_bool(defaults.has(key)).is_true()
		assert_bool(String(section.get(key, "")).is_empty()).is_false()
	assert_str(String(section["os_username_special"])).is_equal(
		PlayerNameRules.MSG_SPECIAL_OS_USERNAME
	)
	assert_str(String(section["shadow_name"])).is_equal(PlayerNameRules.MSG_SHADOW_NAME)
