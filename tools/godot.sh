#!/usr/bin/env bash
# Launch the pinned Godot binary (game/.godot-version).
# The binary is a local artifact (gitignored): <main worktree>/tools/godot/, see README "Local artifacts".
# Resolution: $LEILA_GODOT, then <repo>/tools/godot/, then <main worktree>/tools/godot/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "$ROOT/game/.godot-version")"

if [ -n "${LEILA_GODOT:-}" ]; then
	exec "$LEILA_GODOT" "$@"
fi

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*|Windows_NT) BINS=("Godot_v${PIN}_win64.exe") ;;
	Linux*) BINS=("Godot_v${PIN}_linux.x86_64") ;;
	# Official macOS downloads are Godot_v<pin>_macos.universal.zip containing Godot.app.
	# Resolve the binary inside the bundle; fall back to a bare renamed binary.
	Darwin*) BINS=("Godot.app/Contents/MacOS/Godot" "Godot_v${PIN}_macos.universal") ;;
	*) echo "godot.sh: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac

MAIN="$ROOT"
if command -v git >/dev/null 2>&1; then
	while IFS= read -r LINE; do
		if [[ "$LINE" == worktree\ * ]]; then
			MAIN="${LINE#worktree }"
			break
		fi
	done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null || true)
fi

for DIR in "$ROOT/tools/godot" "$MAIN/tools/godot"; do
	for BIN in "${BINS[@]}"; do
		if [ -f "$DIR/$BIN" ]; then
			exec "$DIR/$BIN" "$@"
		fi
	done
done

echo "godot.sh: Godot $PIN not found (looked in $ROOT/tools/godot and $MAIN/tools/godot)." >&2
echo "godot.sh: set LEILA_GODOT=/path/to/godot or see README \"Local artifacts\"." >&2
exit 1
