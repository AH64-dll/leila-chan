#!/usr/bin/env bash
# Run the full GDScript check suite headless (P0.06):
#   1) gdlint over game/        (config: repo-root gdlintrc; addons/ is excluded — vendored)
#   2) godot --import           (rebuilds the class cache; needed on a fresh checkout)
#   3) gdUnit4 suite res://tests (vendored addon, via tools/godot.sh / $LEILA_GODOT)
# Needs dev deps for step 1: pip install -r requirements-dev.txt
# Exits non-zero if lint or any test fails; every failure is reported before exiting.
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

echo "== godot --headless --path game --import =="
./tools/godot.sh --headless --path game --import || FAILED=1

echo "== gdUnit4 (res://tests) =="
# -c: run all tests instead of failing fast; --ignoreHeadlessMode: gdUnit4 v6 refuses
# headless unless told (UI input events don't work headless — keep tests logic-only).
./tools/godot.sh --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	-a res://tests -c --ignoreHeadlessMode || FAILED=1

if [ "$FAILED" -ne 0 ]; then
	echo "test.sh: FAILED" >&2
	exit 1
fi
echo "test.sh: all checks passed"
