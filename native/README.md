# native/: leila_llm GDExtension (P4.02 scaffold)

Builds `libleila_llm.so`, a Godot 4.7.2 GDExtension, linked against pinned llama.cpp and godot-cpp.
The only class is `LeilaLLM` (RefCounted) with `version()`. Real logic comes in a later task.

## Pins (keep in sync with fetch_deps.sh)
- llama.cpp `ddf48f85c933c1f438212a02eb21e7b001d2d37d` (build b12024)
- godot-cpp `e103d348c4b2d8df7b819126d855e19381cb9a87` (master)
- Godot 4.7.2 (API dump via `tools/godot.sh --dump-extension-api`)

## Build (Linux x86_64)

    bash native/build_linux.sh          # add --clean for a fresh build dir

Needs cmake, Ninja, a C++17 compiler, python3, and network on the first run (deps are cached).

## Outputs
- Build tree: `$HOME/.cache/leila-native/build-linux` (never inside the repo)
- Deps and API dump: `$HOME/.cache/leila-native/{deps,api}`
- Staged libs: `game/addons/leila_llm/bin/linux/` (libleila_llm.so, libllama*, libggml*). Git-ignored. Never commit.
- Descriptor: `game/addons/leila_llm/leila_llm.gdextension`

## Smoke test

    ./tools/godot.sh --headless --path game --import
    ./tools/godot.sh --headless --path game --script "$PWD/native/tests/smoke_load.gd"

## Notes
- godot-cpp: template_release, exceptions off, GODOTCPP_USE_STATIC_CPP=OFF (one shared libstdc++).
- RPATH is `$ORIGIN`, so no LD_LIBRARY_PATH is needed.
- ggml CPU backends are DL modules (libggml-cpu-*.so). They are loaded at runtime, not linked.
