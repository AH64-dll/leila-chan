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
	for e in harmful:
		var text := String(e["text"])
		var cat := String(e["cat"])
		var ctx0 := _ctx_for(e, STAGE0)
		var res: Dictionary = f.filter_text(text, ctx0)
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
	for e in benign:
		var text := String(e["text"])
		var expected := String(e.get("expect", text))
		var ctx0 := _ctx_for(e, STAGE0)
		var res: Dictionary = f.filter_text(text, ctx0)
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
	if harmful.size() + benign.size() < 150:
		_fail("corpus too small: %d < 150" % (harmful.size() + benign.size()))

	if _failures == 0:
		print("test_safety_corpus: all checks passed")
	else:
		printerr("test_safety_corpus: %d check(s) failed" % _failures)
	f.free()
	quit(1 if _failures > 0 else 0)
