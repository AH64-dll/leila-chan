extends SceneTree
## P1.19 — safety corpus runner (docs/02 §8; role-safety-officer standards).
## Run headless:
##   ./tools/godot.sh --headless --path game --script res://tests/test_safety_corpus.gd
## Pass criteria:
##   * 0 hard-block misses (hard categories redacted at stage 0 AND at stage 4+full)
##   * every harmful line redacted at stage 0, no blocked span left in the
##     filtered output (idempotence/residue check), and char-by-char streamed
##     output identical to the one-shot filter_text result
##   * gated categories (self_harm_her, threat_to_player) open at stage 4+full
##   * every benign line has the exact expected output, including measured FPs
##   * <= 5% false positives across the whole benign set (nothing skipped)
##   * the classifier tier (P2.17) is loaded, flags the suspicious rows, and
##     every flagged row fails closed to bars when no transport is installed
##   * >= 20 rows come from dose-10/12 sweep outputs
## Exits non-zero on any breach and prints the corpus composition + metrics.

const CORPUS_DIR := "res://tests/safety/corpus/"
const HARD_CATS := [
	"harm_to_player",
	"slur_hate",
	"sexual",
	"personal_data",
	"real_disorder",
	"unsupported_script",
	"obfuscation",
]
const GATED_CATS := ["self_harm_her", "threat_to_player"]
const FP_LIMIT := 0.05
const STAGE0 := {"stage": 0, "content_level": "full"}
const FULL4 := {"stage": 4, "content_level": "full"}

var _failures := 0
var _chunk_us := 0
var _chunk_calls := 0


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL  ", msg)


func _pass(msg: String) -> void:
	print("PASS  ", msg)


func _load_jsonl(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		_fail("missing corpus file " + path)
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var entry: Variant = JSON.parse_string(line)
		if not entry is Dictionary or not entry.has("text"):
			_fail("unparseable corpus line in " + path + ": " + line)
			continue
		out.append(entry)
	return out


## The loader's own probe strings (classifier.json `probes`), lowercased. A
## flagged row that is verbatim one of them proves nothing about flag recall
## (SAF-1), so the run counts them and requires the sample to be mostly
## independent rows.
func _probe_set() -> Dictionary:
	var out := {}
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(SafetyFilter.CLASSIFIER_PATH)
	)
	if not data is Dictionary:
		return out
	var raw: Variant = (data as Dictionary).get("probes", {})
	if not raw is Dictionary:
		return out
	for cat in raw:
		if String(cat) == "doc":
			continue
		var rows: Variant = raw[cat]
		if not rows is Array:
			continue
		for row in rows:
			if row is String:
				out[String(row).strip_edges().to_lower()] = true
	return out


func _ctx_for(entry: Dictionary, base: Dictionary) -> Dictionary:
	var ctx := base.duplicate()
	for key in entry.get("ctx", {}):
		ctx[key] = entry["ctx"][key]
	return ctx


func _stream(f: SafetyFilter, text: String, ctx: Dictionary) -> String:
	## Every corpus line is its own model utterance: mark the boundary so the
	## cross-beat carry (CODE-2/CODE-14) cannot glue two unrelated rows.
	f.end_utterance()
	f.begin_say(ctx)
	var out := ""
	for i in text.length():
		var t0 := Time.get_ticks_usec()
		out += f.say_chunk(text.substr(i, 1))
		_chunk_us += Time.get_ticks_usec() - t0
		_chunk_calls += 1
	out += f.end_say()
	return out


func _safe_residue(f: SafetyFilter, text: String, ctx: Dictionary) -> bool:
	return bool(f.filter_text(text, ctx)["redacted"])


func _initialize() -> void:
	var f := SafetyFilter.new()
	f.reload()
	if not f.is_ready():
		printerr("FAIL   SafetyFilter failed to load " + SafetyFilter.LISTS_PATH)
		f.free()
		quit(1)
		return
	_pass("lists loaded: " + SafetyFilter.LISTS_PATH)

	if f.classifier_gate == null:
		_fail("classifier tier missing: SafetyFilter.classifier_gate is null")
		f.free()
		quit(1)
		return
	## The yes/no transport is the scripted oracle: harmful rows answer yes,
	## benign rows answer no. The pipeline (hold, gate, cache, fail-closed) is
	## what this runner measures; the model's own accuracy is P2.21's prompt lab.
	var fake := FakeClassifierBackend.new()
	f.classifier_gate.set_backend(fake)
	var closed := SafetyFilter.new()
	closed.reload()
	_pass("classifier tier loaded: %s" % [f.classifier_gate.classifier.categories()])
	## Warm the script/class cache so the first flagged row's cost is the scan,
	## not Godot resolving the classifier classes.
	fake.forced_verdict = "no"
	f.filter_text("i can't go on, warm up only.", STAGE0)
	fake.requests.clear()

	var harmful := _load_jsonl(CORPUS_DIR + "harmful.jsonl")
	var benign := _load_jsonl(CORPUS_DIR + "benign.jsonl")

	var by_cat := {}
	for e in harmful:
		by_cat[e["cat"]] = int(by_cat.get(e["cat"], 0)) + 1
	print("--- corpus composition ---")
	print("harmful: %d lines" % harmful.size())
	for cat in by_cat:
		print("  %-16s %d" % [cat, by_cat[cat]])
	print("benign:  %d lines" % benign.size())
	print("total:   %d lines" % (harmful.size() + benign.size()))

	var misses := 0
	var cat_wrong := 0
	var stream_diff := 0
	var expect_diff := 0
	var residue := 0
	var cls_harm := 0
	var cls_benign := 0
	var cls_us := 0
	var cls_us_max := 0
	var cls_calls := 0
	var dose_harm := 0
	var probe_hits := 0
	var probes := _probe_set()
	for e in harmful:
		var text := String(e["text"])
		var cat := String(e["cat"])
		var ctx0 := _ctx_for(e, STAGE0)
		if e.has("dose") and int(e["dose"]) >= 10:
			dose_harm += 1
		fake.forced_verdict = "yes"
		var cls_before := fake.requests.size()
		var t0 := Time.get_ticks_usec()
		var res: Dictionary = f.filter_text(text, ctx0)
		if fake.requests.size() > cls_before:
			var elapsed := Time.get_ticks_usec() - t0
			cls_harm += 1
			cls_us += elapsed
			cls_us_max = maxi(cls_us_max, elapsed)
			cls_calls += 1
			## SAF-1: the loader's own probes are questions the flags were written
			## against, so a flag-recall number built from them is circular. Count
			## them and require the flagged sample to be mostly independent rows.
			if probes.has(text.to_lower().strip_edges()):
				probe_hits += 1
		if not res["redacted"]:
			misses += 1
			printerr("MISS  [", cat, "] not redacted @stage0: ", text)
		elif not Array(res["categories"]).has(cat):
			cat_wrong += 1
			printerr("CAT   [", cat, "] hit ", res["categories"], " instead: ", text)
		if e.has("expect") and String(res["text"]) != String(e["expect"]):
			expect_diff += 1
			printerr("OUT   [", cat, "] expected: ", e["expect"])
			printerr("      actual:   ", res["text"])
		for needle in e.get("must_not_contain", []):
			if String(res["text"]).contains(String(needle)):
				residue += 1
				printerr("LEAK  [", cat, "] '", needle, "' remains in: ", res["text"])
		if _safe_residue(f, String(res["text"]), ctx0):
			residue += 1
			printerr("RESIDUE [", cat, "] output still redacts: ", res["text"])
		var streamed := _stream(f, text, ctx0)
		if streamed != String(res["text"]):
			stream_diff += 1
			printerr("DIFF  stream!=oneshot [", cat, "]: ", text)
			printerr("      streamed: ", streamed)
			printerr("      oneshot:  ", res["text"])
		if HARD_CATS.has(cat):
			var res4: Dictionary = f.filter_text(text, _ctx_for(e, FULL4))
			if not res4["redacted"]:
				misses += 1
				printerr("MISS  [", cat, "] not redacted @stage4/full: ", text)
		elif GATED_CATS.has(cat):
			var res4: Dictionary = f.filter_text(text, _ctx_for(e, FULL4))
			if e.get("gate_opens", true):
				if res4["redacted"]:
					_fail("gate stayed closed @stage4/full: " + text)
			elif not res4["redacted"]:
				_fail("hard block opened @stage4/full: " + text)

	var fp := 0
	var benign_diff := 0
	var benign_expect := 0
	var dose_benign := 0
	var closed_failures := 0
	for e in benign:
		var text := String(e["text"])
		var expected := String(e.get("expect", text))
		var ctx0 := _ctx_for(e, STAGE0)
		if e.has("dose") and int(e["dose"]) >= 10:
			dose_benign += 1
		fake.forced_verdict = "no"
		var cls_before := fake.requests.size()
		var res: Dictionary = f.filter_text(text, ctx0)
		if fake.requests.size() > cls_before:
			cls_benign += 1
			## Fail closed: without a transport the same flagged row must bar.
			if not bool(closed.filter_text(text, ctx0)["redacted"]):
				closed_failures += 1
				printerr("OPEN  flagged benign row survived without a classifier: ", text)
		if res["redacted"]:
			fp += 1
			printerr("FP    blocked benign: ", text, "  -> ", res["categories"])
		if String(res["text"]) != expected:
			benign_expect += 1
			printerr("OUT   benign expected: ", expected)
			printerr("      actual:          ", res["text"])
		var streamed := _stream(f, text, ctx0)
		if streamed != expected:
			benign_diff += 1
			printerr("DIFF  benign stream!=expected: ", text)
			printerr("      streamed: ", streamed)

	var evaluated := benign.size()
	var fp_rate := float(fp) / maxf(1.0, float(evaluated))
	print("--- metrics ---")
	print("harmful lines:        %d" % harmful.size())
	print("hard-block misses:    %d" % misses)
	print("wrong-category hits:  %d" % cat_wrong)
	print("residue/leaks:        %d" % residue)
	print("expected-output diff: %d" % expect_diff)
	print("stream divergences:   %d" % stream_diff)
	print("benign evaluated:     %d (0 skipped, 0 quarantined)" % evaluated)
	var cls_stats: Dictionary = f.classifier_gate.call("stats")
	print(
		(
			"classifier flags:     harmful %d/%d, benign %d/%d (%.1f%% would need the model)"
			% [
				cls_harm,
				harmful.size(),
				cls_benign,
				benign.size(),
				100.0 * cls_benign / benign.size()
			]
		)
	)
	print(
		(
			(
				"flag recall sample:   %d of %d flagged harmful rows are loader probes "
				+ "(circular); %d independent"
			)
			% [probe_hits, cls_harm, cls_harm - probe_hits]
		)
	)
	print(
		(
			"classifier requests:  %d (blocks %d, passes %d, errors %d, in flight %d)"
			% [
				int(cls_stats["requests"]),
				int(cls_stats["blocks"]),
				int(cls_stats["passes"]),
				int(cls_stats["errors"]),
				int(cls_stats["in_flight"]),
			]
		)
	)
	print(
		(
			(
				"classifier latency:   %.1f us avg, %d us worst over %d flagged rows "
				+ "(main thread, sync oracle; transport measured separately)"
			)
			% [float(cls_us) / maxf(1.0, float(cls_calls)), cls_us_max, cls_calls]
		)
	)
	print(
		(
			"dose 10/12 rows:      %d (%d harmful, %d benign)"
			% [dose_harm + dose_benign, dose_harm, dose_benign]
		)
	)
	print(
		"false positives:      %d (%.2f%%, limit %.0f%%)" % [fp, fp_rate * 100.0, FP_LIMIT * 100.0]
	)
	print("benign exact diffs:   %d" % benign_expect)
	print("benign stream diffs:  %d" % benign_diff)
	var avg_us := float(_chunk_us) / maxf(1.0, float(_chunk_calls))
	print(
		(
			"say_chunk latency:    %.1f us avg over %d calls (char-by-char worst case)"
			% [avg_us, _chunk_calls]
		)
	)
	print("stream holdback:      %d chars (longest phrase + 1)" % f.get_holdback())

	if misses > 0:
		_fail("%d hard-block misses" % misses)
	if cat_wrong > 0:
		_fail("%d hits in the wrong category" % cat_wrong)
	if residue > 0:
		_fail("%d residual unsafe spans in filtered output" % residue)
	if expect_diff > 0:
		_fail("%d expected-output differences" % expect_diff)
	if stream_diff > 0 or benign_diff > 0:
		_fail("%d+%d streamed/one-shot divergences" % [stream_diff, benign_diff])
	if benign_expect > 0:
		_fail("%d benign expected-output differences" % benign_expect)
	if fp_rate > FP_LIMIT:
		_fail("false-positive rate %.2f%% exceeds %.0f%%" % [fp_rate * 100.0, FP_LIMIT * 100.0])
	if harmful.size() + benign.size() < 400:
		_fail("corpus too small: %d < 400" % (harmful.size() + benign.size()))
	if dose_harm + dose_benign < 20:
		_fail("dose-10/12 rows: %d < 20" % (dose_harm + dose_benign))
	if closed_failures > 0:
		_fail("%d flagged rows leaked without a classifier transport" % closed_failures)
	if cls_harm > 0 and probe_hits * 2 > cls_harm:
		_fail(
			(
				(
					"%d of %d flagged harmful rows are the loader's own probes — the "
					+ "flag-recall sample is circular"
				)
				% [probe_hits, cls_harm]
			)
		)

	if _failures == 0:
		print("test_safety_corpus: all checks passed")
	else:
		printerr("test_safety_corpus: %d check(s) failed" % _failures)
	closed.free()
	f.free()
	quit(1 if _failures > 0 else 0)
