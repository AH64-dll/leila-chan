#!/usr/bin/env bash
# Launch the pinned Godot binary (game/.godot-version).
# The binary is a local artifact: <main tree>/tools/godot/, see README "Local artifacts".
# Override with LEILA_GODOT=/path/to/godot
set -euo pipefail

PIN="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../game/.godot-version")"
if [ -n "${LEILA_GODOT:-}" ]; then
	exec "$LEILA_GODOT" "$@"
fi

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*|Windows_NT) BIN="Godot_v${PIN}_win64.exe" ;;
	Linux*) BIN="Godot_v${PIN}_linux.x86_64" ;;
	Darwin*) BIN="Godot_v${PIN}_macos.universal" ;;
	*) echo "godot.sh: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac

GODOT="/d/lila/tools/godot/$BIN"
if [ ! -x "$GODOT" ]; then
	echo "godot.sh: $GODOT not found — see README \"Local artifacts\"" >&2
	exit 1
fi
exec "$GODOT" "$@"
