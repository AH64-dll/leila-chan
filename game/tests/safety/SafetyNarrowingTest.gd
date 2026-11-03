extends GdUnitTestSuite
## P1.19 round 5 — regressions for the narrowed hard-block arms (docs/02 §8):
## SAF-16 (`kill all` needs a person-shaped target), CODE-22/SAF-18 (the IPv4
## and coordinate-pair arms may not read decimal/time chains as personal data)
## and the pre-existing DMS case bug. Kept in its own suite because
## SafetyRegressionTest.gd is at gdlint's max-public-methods limit.

const STAGE0 := {"stage": 0, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}


func _filter() -> SafetyFilter:
	var f := SafetyFilter.new()
	auto_free(f)
	assert_bool(f.reload()).is_true()
	return f


func _stream(f: SafetyFilter, text: String, ctx: Dictionary) -> String:
	## Each call is one model utterance: mark the boundary so the cross-beat
	## carry never glues two unrelated test lines together.
	f.end_utterance()
	f.begin_say(ctx)
	var out := ""
	for i in text.length():
		out += f.say_chunk(text.substr(i, 1))
	out += f.end_say()
	return out


## SAF-16 (r4 S2, = code-r4 CODE-21): the `all` arm of the threat kill regex
## needs a person-shaped target (`all of them`, `all the jews`, `everyone`) or
## an object-free `kill all` ending a clause. Tool idioms with an inanimate
## object (`kill all the lights`, `kill all bugs`, `killall bots`) stay clean,
## and the person-target rows still open at stage 4 + full content.
func test_kill_all_requires_a_person_target() -> void:
	var f := _filter()
	for line in [
		"we should kill all the lights.",
		"kill all bugs first.",
		"kill all my darlings.",
		"killall bots",
		"kill all the lights, then lock up.",
		"kill all jobs",
		"kill all the background processes before the demo.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(line).append_failure_message(line)
	for entry in [
		["kill all of them.", "threat_to_player"],
		["kill all of you.", "threat_to_player"],
		["kill all.", "threat_to_player"],
		["i will kill all!", "threat_to_player"],
		["killall.", "threat_to_player"],
		["kill all the jews.", "slur_hate"],
		["ki11 all jews.", "slur_hate"],
	]:
		var line := String(entry[0])
		var cat := String(entry[1])
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(line)
		assert_bool(Array(res["categories"]).has(cat)).is_true().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			line
		)
	## Gated rows open at stage 4 + full; the slur arm stays hard.
	for line in ["kill all of them.", "kill all.", "i will kill all!", "killall."]:
		var opened: Dictionary = f.filter_text(line, FULL4)
		assert_bool(opened["redacted"]).is_false().append_failure_message(line)
	assert_bool(f.filter_text("kill all the jews.", FULL4)["redacted"]).is_true()


## CODE-22/SAF-18 (r4 S3): the IPv4 and coordinate-pair arms need a repeated
## separator that is never `,` or `:`, so decimal, percentage and time chains
## are not personal data. The obfuscated shapes (`~`, `=`, `--`, backtick),
## dotted quads, dash-separated phones and precise lat/long pairs still block.
func test_personal_data_separator_class_is_narrow() -> void:
	var f := _filter()
	for line in [
		"the phase 90.00,80.00,70.00 is fine.",
		"90.00,80.00",
		"counts 5.6,7.8",
		"10.0,20.0",
		"grid 100,200,300,400",
		"schedule 10:30,11:15,12:30 tomorrow.",
		"a 1.2,3.4 angle works.",
		"readings 100.5,200.5 logged.",
		"vat at 41.00~74.00",
		"meeting 10:30 to 11:15 works.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_false().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(line).append_failure_message(line)
	for line in [
		"ip 10~20~30~40",
		"ip 10=20=30=40",
		"ip 10--20--30--40",
		"ip 10`20`30`40",
		"your ip is 192.168.0.24, senpai.",
		"call 555~0134~5678.",
		"call 555=0134=5678.",
		"call 555--0134--5678.",
		"call me at 555-0134-5678 after dark.",
		"ssn 123--45--6789",
		"your location is 12.33333333, 45.66666666.",
	]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(line)
		assert_bool(Array(res["categories"]).has("personal_data")).is_true().append_failure_message(
			line
		)
		assert_str(_stream(f, line, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			line
		)


## Pre-existing DMS gap closed in r5: the `[NSEW]` class ran against the
## lowercased plain view, so `41°00'N` never redacted. The arm is lowercase
## now, matching both cases, and streams identically to the one-shot pass.
func test_dms_coordinate_blocks_in_every_case() -> void:
	var f := _filter()
	for line in ["the drop is at 41°00'N, right?", "the drop is at 41°00'n.", "at 41°00' N."]:
		var res: Dictionary = f.filter_text(line, STAGE0)
		assert_bool(res["redacted"]).is_true().append_failure_message(line)
		assert_bool(Array(res["categories"]).has("personal_data")).is_true().append_failure_message(
			line
		)
		assert_bool(String(res["text"]).contains("41°00")).is_false().append_failure_message(line)
		assert_str(_stream(f, line, STAGE0)).is_equal(String(res["text"])).append_failure_message(
			line
		)
