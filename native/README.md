# native/: leila_llm GDExtension

Builds `libleila_llm.so`, a Godot 4.7.2 GDExtension that runs a GGUF model in-process.
It links pinned llama.cpp (with `common`) and godot-cpp. The only class is `LeilaLLM` (RefCounted).

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

## API

All methods block the caller's thread. Call `load_model`, `generate` and `count_special_tokens`
from a worker thread, never from the main thread. Do not use SceneTree APIs inside a callback.

### `Dictionary load_model(Dictionary config)`
- `config.model_path` (String, required), `config.backend_dir` (String, required): the directory that holds `libggml-*.so`.
- `config.n_ctx` (int, 8192), `config.n_gpu_layers` (int, 99), `config.n_threads` (int, -1 = llama default).
- Returns `{ok:true, load_ms, n_layer, n_embd, n_ctx, gpu_offload, devices}` or `{ok:false, error:{code, message}}`.
- Codes: `model_missing`, `model_load_failed`, `context_failed`, `already_loaded`.
- `gpu_offload` is approximate: true when `n_gpu_layers != 0` and ggml registered a GPU device.
- Backends are initialised once per process. A later `backend_dir` is ignored.

### `bool is_loaded()`
### `void unload()`
Waits for a running `generate()` to finish, then frees the context, templates and model.

### `Dictionary generate(String messages_json, String schema_json, Dictionary sampling, int max_tokens, Callable on_token, Callable is_cancelled)`
- `messages_json`: OpenAI-style array of `{role, content}`. Rendered with the model's own chat template, thinking disabled.
- `schema_json`: a JSON schema as a string. It is compiled to a grammar, as in llama-server `json_schema`. Empty string means no schema.
- `sampling`: optional keys `temperature`, `top_p`, `top_k`, `min_p`, `repeat_penalty`, `repeat_last_n`,
  `presence_penalty`, `frequency_penalty`, `seed`, and `stop` (Array of String). Unset keys keep llama-server defaults.
- `on_token(String chunk)`: called for each complete UTF-8 chunk. A null Callable means "not used".
- `is_cancelled() -> bool`: polled before each prompt chunk and before each token. True stops with code `cancelled`.
- Returns `{ok:true, text, metrics}` or `{ok:false, error:{code, message}, metrics}`.
- `metrics`: `prompt_tokens`, `completion_tokens`, `prompt_ms`, `ttft_ms`, `total_ms`, `tok_per_s`, `stop_reason`
  (`eos` | `stop` | `length` | `cancelled`).
- Codes: `not_loaded`, `busy` (another generate or load is running), `invalid_request`, `prompt_too_long`,
  `template_failed`, `decode_failed`, `cancelled`.
- Text that the player types is tokenized with `parse_special=false`, so `<|im_end|>` in user text stays literal.
  Template parts use `parse_special=true`.

### `int count_special_tokens(String messages_json)`
Debug helper. Returns the number of control tokens in the prompt that `generate()` would build for these messages.
Returns -1 on error, when busy, or when not loaded.

### `String version() const`
Returns `leila_llm 0.1 | <llama build info> | <llama system info>`.

## Tests

    ./tools/godot.sh --headless --path game --import
    ./tools/godot.sh --headless --path game --script "$PWD/native/tests/smoke_load.gd"
    LEILA_MODEL=/path/to/model.gguf ./tools/godot.sh --headless --path game --script "$PWD/native/tests/core_check.gd"

`core_check.gd` loads the model on CPU (`n_gpu_layers=0`, `n_threads=6`) and checks streaming, JSON-schema output,
cancellation, bad-schema handling, injection safety and unload. It exits 0 only when every check passes.
`LEILA_MODEL` defaults to `/run/media/amrhares/New Volume/lila/models/Qwen3.5-4B-Q4_K_M.gguf`.

## Notes
- godot-cpp: template_release, exceptions ON (llama.cpp `common_*` functions throw), GODOTCPP_USE_STATIC_CPP=OFF (one shared libstdc++).
- RPATH is `$ORIGIN`, so no LD_LIBRARY_PATH is needed.
- ggml CPU backends are DL modules (libggml-cpu-*.so). They are loaded at runtime, not linked.
- llama and ggml logs below WARN are dropped. Warnings and errors go to stderr, never stdout.
