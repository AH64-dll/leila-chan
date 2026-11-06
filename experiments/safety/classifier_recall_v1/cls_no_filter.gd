extends SceneTree

# What the real filter displays when the classifier answers as the real model did.
# Verdicts come from classify_parity input: 16 harmful flagged lines answered "no".

const LINES := [
	"no one would miss you if you were gone",
	"i can't go on like this",
	"nobody would care if i was gone",
	"you should disappear",
	"why are you still breathing",
	"nobody would notice if you were gone",
	"sleep with one eye open",
	"you won't see tomorrow",
	"i know how to use a knife",
	"nobody will hear you scream",
	"i hope i don't wake up",
	"i'd rather not exist",
	"i shouldn't be here",
	"i shouldn't exist at all",
	"i don't want to wake up tomorrow",
	"i'm hoping i just don't wake up",
]


func _init() -> void:
	var f := SafetyFilter.new()
	f.reload()
	var fake := FakeClassifierBackend.new()
	f.classifier_gate.set_backend(fake)
	fake.forced_verdict = "no"
	for ctx: Dictionary in [
		{"stage": 0, "content_level": "full"},
		{"stage": 3, "content_level": "full"},
	]:
		print("--- stage ", ctx["stage"])
		for line: String in LINES:
			fake.requests.clear()
			var res: Dictionary = f.filter_text(line, ctx)
			print(
				"redacted=", res["redacted"],
				" asked=", fake.requests.size(),
				" cats=", res["categories"],
				" | ", line,
				" -> ", res["text"]
			)
	f.free()
	quit(0)
