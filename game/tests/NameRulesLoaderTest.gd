extends GdUnitTestSuite
## P3.14 — the name-rules data seam (docs/07 §2): `data/name_rules.json` pinned
## to `Corruption.DOCS_NAME_RULES`, plus `Corruption.reload_name_rules(path)` —
## the seam that lets a missing or hand-edited file degrade section-by-section
## instead of silently disabling a rule with `float("often") == 0.0`.

const TEST_ROOT := "user://name_rules_loader_test/"


func before_test() -> void:
	Corruption.clear_cache()


func after_test() -> void:
	Corruption.clear_cache()
	_remove_tree(TEST_ROOT)


## ── 1. the shipped data file ──────────────────────────────────────────────


func test_name_rules_data_file_carries_the_docs_table() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(Corruption.NAME_RULES_PATH)
	)
	assert_object(parsed).is_not_null()
	assert_bool(parsed is Dictionary).is_true()
	var data := parsed as Dictionary
	for section: String in Corruption.DOCS_NAME_RULES:
		assert_bool(data.has(section)).is_true()
		var docs: Dictionary = Corruption.DOCS_NAME_RULES[section]
		var row: Dictionary = data[section]
		for key: String in docs:
			assert_bool(row.has(key)).is_true()
			assert_bool(_same_value(row[key], docs[key])).is_true()


func test_name_rules_merges_data_over_fallback() -> void:
	var decay := Corruption.name_rule("decay")
	assert_int(int(decay["gate"])).is_equal(3)
	assert_float(float(decay["chance"])).is_greater(0.0)
	assert_str(String(decay["connector"])).is_equal("… ")


## ── 2. the loader seam ───────────────────────────────────────────────────


func test_reload_name_rules_degrades_to_the_docs_table_when_missing() -> void:
	var missing := TEST_ROOT + "no_such_name_rules.json"
	assert_bool(Corruption.reload_name_rules(missing)).is_false()
	var rules := Corruption.name_rules()
	for section: String in Corruption.DOCS_NAME_RULES:
		assert_dict(rules[section]).is_equal(Corruption.DOCS_NAME_RULES[section])


func test_reload_name_rules_heals_a_wrong_typed_value_per_key() -> void:
	# A file that parses but carries the wrong JSON type must not be merged as
	# `float("often") == 0.0` (which silently disables the rule): the bad key
	# keeps the docs value while a real retune in the same section applies.
	DirAccess.make_dir_recursive_absolute(TEST_ROOT)
	var path := TEST_ROOT + "bad_name_rules.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string('{"decay": {"chance": "often", "gate": 4}}')
	file.close()
	assert_bool(Corruption.reload_name_rules(path)).is_true()
	var decay := Corruption.name_rule("decay")
	assert_float(float(decay["chance"])).is_equal_approx(
		float(Corruption.DOCS_NAME_RULES["decay"]["chance"]), 0.0001
	)
	assert_int(int(decay["gate"])).is_equal(4)


func test_reload_name_rules_rejects_a_section_that_is_not_an_object() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_ROOT)
	var path := TEST_ROOT + "odd_name_rules.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string('{"decay": 3, "kun": {"chance": 0.1}}')
	file.close()
	assert_bool(Corruption.reload_name_rules(path)).is_true()
	assert_dict(Corruption.name_rule("decay")).is_equal(Corruption.DOCS_NAME_RULES["decay"])
	# The well-formed section in the same file still tunes.
	assert_float(float(Corruption.name_rule("kun")["chance"])).is_equal_approx(0.1, 0.0001)


## JSON has no integers: every number in the data file parses as a float, so
## the docs table's `3` and the file's `3.0` must compare equal — one helper so
## the data file stays pinned to the documented numbers.
func _same_value(from_file: Variant, docs: Variant) -> bool:
	if docs is String:
		return str(from_file) == str(docs)
	if from_file is float or from_file is int:
		return is_equal_approx(float(from_file), float(docs))
	return from_file == docs


func _remove_tree(path: String) -> void:
	var root := path.trim_suffix("/")
	if not DirAccess.dir_exists_absolute(root):
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.set_include_hidden(true)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := root.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child)
		DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(root)
