#!/usr/bin/env bash
# Run the full GDScript check suite headless (P0.06; hardened in P0.15):
#   1) gdlint over game/            (config: repo-root gdlintrc; addons/ is excluded — vendored)
#   2) gdformat --check over game/  (config: repo-root gdformatrc; format drift gates too)
#   3) godot --import               (rebuilds the class cache; needed on a fresh checkout)
#   4) gdUnit4 suites res://tests   (vendored addon, via tools/godot.sh / $LEILA_GODOT)
#   5) standalone --script tests    (non-suite scripts at game/tests/*.gd)
# Needs dev deps for steps 1-2: pip install -r requirements-dev.txt
# Exits non-zero if lint, format or any test fails; every failure is reported before exiting.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FAILED=0

echo "== gdlint game/ =="
if command -v gdlint >/dev/null 2>&1; then
	gdlint game/ || FAILED=1
else
	echo "test.sh: gdlint not found — install dev deps: pip install -r requirements-dev.txt" >&2
	FAILED=1
fi

echo "== gdformat --check game/ =="
if command -v gdformat >/dev/null 2>&1; then
	gdformat --check game/ || FAILED=1
else
	echo "test.sh: gdformat not found — install dev deps: pip install -r requirements-dev.txt" >&2
	FAILED=1
fi

echo "== godot --headless --path game --import =="
./tools/godot.sh --headless --path game --import || FAILED=1

echo "== gdUnit4 (res://tests) =="
# Zero-suite guard (P0.15, review CODE-2): gdUnit4 prints "No test cases found, abort
# test run!" and still exits 0 — a renamed or lost test root must not stay green.
if [ ! -d game/tests ] || ! find game/tests -name '*.gd' -type f 2>/dev/null | grep -q .; then
	echo "test.sh: no test scripts under game/tests/ — refusing to pass with zero tests" >&2
	FAILED=1
else
	# -c: run all tests instead of failing fast; --ignoreHeadlessMode: gdUnit4 v6 refuses
	# headless unless told (UI input events don't work headless — keep tests logic-only).
	GDUNIT_OUT="$(./tools/godot.sh --headless --path game \
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		-a res://tests -c --ignoreHeadlessMode 2>&1)"
	GDUNIT_STATUS=$?
	printf '%s\n' "$GDUNIT_OUT"
	if [ "$GDUNIT_STATUS" -ne 0 ] || [[ "$GDUNIT_OUT" == *"No test cases found"* ]]; then
		echo "test.sh: gdUnit4 failed or discovered zero test cases" >&2
		FAILED=1
	fi
fi

echo "== standalone tests (game/tests/*.gd, non-gdUnit4) =="
# GdUnitTestSuite files are covered by the stage above; every other top-level
# game/tests/*.gd runs as a SceneTree --script (e.g. test_bridge.gd).
# Convention: suites extend GdUnitTestSuite directly; shared helpers go in a subdir.
for t in game/tests/*.gd; do
	[ -e "$t" ] || continue
	if grep -q 'extends[[:space:]]\+GdUnitTestSuite' "$t"; then continue; fi
	echo "-- $t"
	./tools/godot.sh --headless --path game --script "res://tests/${t##*/}" || FAILED=1
done

if [ "$FAILED" -ne 0 ]; then
	echo "test.sh: FAILED" >&2
	exit 1
fi
echo "test.sh: all checks passed"
