#!/usr/bin/env bash
# Run the full GDScript check suite headless (P0.06; hardened in P0.15):
#   1) gdlint over game/            (config: repo-root gdlintrc; addons/ is excluded — vendored)
#   2) gdformat --check over game/  (config: repo-root gdformatrc; format drift gates too)
#   3) godot --import               (rebuilds the class cache; needed on a fresh checkout)
#   4) gdUnit4 suites res://tests   (vendored addon, via tools/godot.sh / $LEILA_GODOT;
#                                   streamed transcript in game/reports/gdunit_console.log)
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
# Zero-suite guard (P0.15, review CODE-2; reworked P0.18, review CODE-1):
# gdUnit4 exits 0 when it discovers zero test cases, so its exit code alone
# cannot be trusted. The check asserts on the JUnit report artifact, not on
# console text: the zero-case path quits before a session starts, so no
# results.xml is written. The report must also be FRESH — a stale one must
# never fake a pass (P0.18 round 2, review CODE-1): the wipe runs first, a
# wipe failure is fatal (a results.xml held open by an editor is readable but
# not deletable on Windows), and the accepted results.xml must be newer than
# .pre_run_marker, so freshness never depends on the wipe alone.
# Upgrade note: if gdUnit4 changes where/whether it writes
# reports/report_*/results.xml or the <testsuites tests="N"> attribute,
# re-verify this guard — a missing or unreadable report fails red, never green.
if ! rm -rf game/reports; then
	echo "test.sh: cannot clear game/reports — close whatever holds it open (a stale report could fake a pass)" >&2
	FAILED=1
elif ! mkdir -p game/reports || ! touch game/reports/.pre_run_marker; then
	echo "test.sh: cannot write to game/reports — refusing to trust any report" >&2
	FAILED=1
elif [ ! -d game/tests ] || ! find game/tests -name '*.gd' -type f 2>/dev/null | grep -q .; then
	echo "test.sh: no test scripts under game/tests/ — refusing to pass with zero tests" >&2
	FAILED=1
else
	# tee streams the transcript to the console AND captures it in
	# game/reports/gdunit_console.log (P0.18, review CODE-1): a hung suite no
	# longer leaves zero output — everything up to the kill is already visible.
	# -c: run all tests instead of failing fast; --ignoreHeadlessMode: gdUnit4 v6
	# refuses headless unless told (UI input events don't work headless — keep
	# tests logic-only).
	./tools/godot.sh --headless --path game \
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		-a res://tests -c --ignoreHeadlessMode 2>&1 | tee game/reports/gdunit_console.log
	GDUNIT_STATUS=${PIPESTATUS[0]}
	RESULTS_XML="$(find game/reports -name results.xml -type f -newer game/reports/.pre_run_marker 2>/dev/null | head -n1)"
	GDUNIT_TESTS="$(sed -n 's/.*<testsuites[^>]*tests="\([0-9][0-9]*\)".*/\1/p' "$RESULTS_XML" 2>/dev/null | head -n1)"
	if [ "$GDUNIT_STATUS" -ne 0 ] || [ "${GDUNIT_TESTS:-0}" -eq 0 ]; then
		echo "test.sh: gdUnit4 failed or discovered zero test cases (transcript: game/reports/gdunit_console.log)" >&2
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
