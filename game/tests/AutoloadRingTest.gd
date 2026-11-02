extends GdUnitTestSuite
## Seed test for the headless suite (P0.06): the autoload ring from docs/07 §2.
## Shares the contract list with Boot.gd so both checks stay in sync.

const BootScene := preload("res://scenes/Boot.gd")


func test_all_autoloads_registered() -> void:
	for autoload_name: String in BootScene.EXPECTED_AUTOLOADS:
		(
			assert_object(get_node_or_null("/root/" + autoload_name))
			. is_not_null()
			. append_failure_message("autoload not registered: " + autoload_name)
		)


func test_declared_autoloads_match_contract() -> void:
	var declared: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with("autoload/"):
			declared.append(property_name.trim_prefix("autoload/"))
	assert_array(declared).contains_exactly_in_any_order(Array(BootScene.EXPECTED_AUTOLOADS))
