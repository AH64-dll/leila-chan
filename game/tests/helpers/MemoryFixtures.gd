extends RefCounted
## Shared fixtures for the memory suites (P2.11). Lives in `tests/helpers/` so
## `tools/test.sh` does not run it as a standalone test (that glob is
## `game/tests/*.gd` only).

const MemoryStoreScript := preload("res://llm/MemoryStore.gd")

## 24 distinct short facts: distinct content words, so none is a near-duplicate
## of another and every eviction assertion has a predictable victim.
const FILLER := [
	"alpha",
	"bravo",
	"charlie",
	"delta",
	"echo",
	"foxtrot",
	"golf",
	"hotel",
	"india",
	"juliet",
	"kilo",
	"lima",
	"mike",
	"november",
	"oscar",
	"papa",
	"quebec",
	"romeo",
	"sierra",
	"tango",
	"uniform",
	"victor",
	"whiskey",
	"xray",
]


## 24 facts for a full store, one per FILLER word.
static func filler() -> Array[String]:
	var facts: Array[String] = []
	for word: String in FILLER:
		facts.append("likes film " + word)
	return facts


## A store holding `texts` at one importance. Fixtures are trusted input: the
## rows go straight into `from_dict()` and the three rules are not applied.
static func store(texts: Array, importance := 1.0, seed := 0) -> MemoryStore:
	var rows: Array = []
	for text: String in texts:
		rows.append({"text": text, "importance": importance, "quotes": 0})
	return store_rows(rows, seed)


static func store_rows(rows: Array, seed := 0) -> MemoryStore:
	var store := MemoryStoreScript.new()
	store.from_dict({"entries": rows})
	store.set_rng_seed(seed)
	return store
