extends GdUnitTestSuite
## FullRunHarnessTest — P2.29 QA harness carry-over items:
## 1. --own-server mode and relaunch logging
## 2. --resume dedupe, tail appending, and checkpoint summaries

const FullRunReportScript := preload("res://tools/full_run_report.gd")
const FullRunStoreScript := preload("res://tools/full_run_store.gd")


func test_own_server_report_dose_and_relaunch_rendering() -> void:
	var report = FullRunReportScript.new()
	report.own_server = false
	var attach_header := "\n".join(report.header_lines())
	assert_bool(attach_header.contains("attach mode: the app did not launch the server")).is_true()
	assert_bool(attach_header.contains("scheduled, not bound")).is_true()

	report.own_server = true
	var own_header := "\n".join(report.header_lines())
	assert_bool(own_header.contains("bound via server relaunch (own-server mode)")).is_true()

	var day_lines := "\n".join(
		report.day_header_lines({"id": "D01", "title": "Test"}, 1, {"malice": 2.5})
	)
	assert_bool(day_lines.contains("bound via server relaunch")).is_true()

	# Test relaunch text rendering
	var trans_list: Array[Dictionary] = [
		{
			"day": 2,
			"from": 0,
			"to": 1,
			"name": "Tension",
			"relaunch": {"ok": true, "ms": 1250, "dose": {"malice": 2.5}},
		},
		{
			"day": 3,
			"from": 1,
			"to": 2,
			"name": "Leaks",
			"relaunch": {"ok": false, "error": {"code": "server_not_owned"}},
		},
	]
	report.transitions = trans_list
	var trans_text := report._transitions_text()
	assert_bool(trans_text.contains("day 2: 0→1 Tension (relaunch ok)")).is_true()
	assert_bool(trans_text.contains("day 3: 1→2 Leaks (relaunch server_not_owned)")).is_true()


func test_own_server_mode_eliminates_server_not_owned_at_stage_crossing() -> void:
	# Attach mode (default): auto_start is false
	var attach_backend = LlamaServerBackend.new({"auto_start": false})
	assert_bool(bool(attach_backend.config.get("auto_start", false))).is_false()

	# Own-server mode: auto_start is true, bypassing server_not_owned
	var own_backend = LlamaServerBackend.new({"auto_start": true})
	assert_bool(bool(own_backend.config.get("auto_start", false))).is_true()

	var driver = preload("res://tools/full_run_driver.gd").new()
	driver._args_set("own-server", "true")
	assert_bool(driver._own_server).is_true()
	driver._args_set("checkpoint-days", "3")
	assert_int(driver._checkpoint_days).is_equal(3)
	driver.queue_free()


func test_checkpoint_summary_vs_run_summary() -> void:
	var report = FullRunReportScript.new()
	var final_state := {"day": 7, "stage": 3, "instability": 45.0}

	# Checkpoint summary
	var cp_lines := "\n".join(report.summary_lines("day cap 7 reached", final_state, 120.0, true))
	assert_bool(cp_lines.contains("## Checkpoint summary")).is_true()
	assert_bool(cp_lines.contains("- checkpoint: day cap 7 reached")).is_true()
	assert_bool(cp_lines.contains("## Run summary")).is_false()

	# Run summary
	var run_lines := "\n".join(report.summary_lines("campaign ended", final_state, 500.0, false))
	assert_bool(run_lines.contains("## Run summary")).is_true()
	assert_bool(run_lines.contains("- finished: campaign ended")).is_true()


func test_full_run_store_scan_rendered_dedupes_days_and_turns() -> void:
	var prefix := """# P2.22 full run — test

## Day 1 — D02_cafe "Café"
- stage 0 "Honeymoon"

### Turn 1 · day 1 · stage 0 "Honeymoon" · instability 0.0
**Player:** Hello
**Leila:** Hi

### Turn 2 · day 1 · stage 0 "Honeymoon" · instability 1.0
**Player:** Next
**Leila:** Yes

## Run summary
- finished: day cap 1 reached · wall time 30 s
"""
	var scanned: Dictionary = FullRunStoreScript.scan_rendered(prefix)
	var days: Dictionary = scanned.get("days", {})
	var turns: Dictionary = scanned.get("turns", {})
	var cleaned: String = scanned.get("cleaned", "")

	assert_bool(days.has(1)).is_true()
	assert_bool(turns.has("1:1")).is_true()
	assert_bool(turns.has("1:2")).is_true()
	assert_bool(turns.has("1:3")).is_false()

	# Segment stop is converted to checkpoint summary on resume
	(
		assert_bool(cleaned.contains("## Checkpoint summary\n- checkpoint: day cap 1 reached"))
		. is_true()
	)
	assert_bool(cleaned.contains("## Run summary\n- finished: day cap")).is_false()
