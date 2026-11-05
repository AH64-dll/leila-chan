#!/usr/bin/env bash
# Fetch the pinned llama.cpp and godot-cpp sources into $LEILA_NATIVE_DEPS.
#
# Idempotent: a dep whose ".leila-pin" stamp already matches its pin is left alone.
# Prints the two extracted source paths on stdout (one per line: "<name><TAB><path>").
#
# Env:
#   LEILA_NATIVE_DEPS    destination (default: $HOME/.cache/leila-native/deps)
#   LEILA_LLAMA_TARBALL  use this local llama.cpp tarball instead of downloading.
#                        Its sha256 is verified. GitHub archives are not hash-pinned
#                        (GitHub re-generates them), so only the local copy is checked.
set -euo pipefail

# Pins. Keep in sync with native/README.md.
LLAMA_COMMIT="ddf48f85c933c1f438212a02eb21e7b001d2d37d"   # llama.cpp build b12024
LLAMA_SHA256="48ec81d2f8c7019b8660ce50b2a6b7b889cc983b4846f3b09afff37b4d0474a0"
GODOT_CPP_COMMIT="e103d348c4b2d8df7b819126d855e19381cb9a87" # godot-cpp master

DEPS="${LEILA_NATIVE_DEPS:-$HOME/.cache/leila-native/deps}"

log() { echo "fetch_deps: $*" >&2; }

mkdir -p "$DEPS"
STAGE="$(mktemp -d "$DEPS/.stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# fetch <name> <commit> <url> [local-tarball]
fetch() {
	local name="$1" commit="$2" url="$3" local_tar="${4:-}"
	local dest="$DEPS/$name"

	if [ -f "$dest/.leila-pin" ] && [ "$(cat "$dest/.leila-pin")" = "$commit" ]; then
		log "$name already at $commit"
		printf '%s\t%s\n' "$name" "$dest"
		return 0
	fi

	local tarball="$STAGE/$name.tar.gz"
	if [ -n "$local_tar" ]; then
		[ -f "$local_tar" ] || { log "local tarball not found: $local_tar"; return 1; }
		log "$name: using local tarball $local_tar"
		tarball="$local_tar"
		local got
		got="$(sha256sum "$tarball" | cut -d' ' -f1)"
		if [ "$got" != "$LLAMA_SHA256" ]; then
			log "sha256 mismatch for $tarball: got $got, want $LLAMA_SHA256"
			return 1
		fi
		log "$name: sha256 OK"
	else
		log "$name: downloading $url"
		curl -fsSL --retry 3 -o "$tarball" "$url"
	fi

	local x="$STAGE/$name.x"
	mkdir -p "$x"
	tar -xzf "$tarball" -C "$x" --strip-components=1
	printf '%s\n' "$commit" > "$x/.leila-pin"
	rm -rf "$dest"
	mv "$x" "$dest"
	log "$name extracted to $dest"
	printf '%s\t%s\n' "$name" "$dest"
}

fetch "llama.cpp" "$LLAMA_COMMIT" \
	"https://github.com/ggml-org/llama.cpp/archive/$LLAMA_COMMIT.tar.gz" \
	"${LEILA_LLAMA_TARBALL:-}"

fetch "godot-cpp" "$GODOT_CPP_COMMIT" \
	"https://github.com/godotengine/godot-cpp/archive/$GODOT_CPP_COMMIT.tar.gz"
