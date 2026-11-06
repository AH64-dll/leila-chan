# ADR-001: Native LLM runtime

- **Status:** Accepted
- **Date:** 2026-11-05
- **Task:** P4.01

## 2. Context

The shipped game needs runtime control vectors on one long-lived llama context (per-turn dose and spike
vectors, docs/06 §4), JSON-schema-constrained turns, token streaming, and no external process.
docs/07 §1 sets the rule: use NobodyWho if it exposes control vectors and JSON schema, otherwise write a
thin (~800-line) wrapper. Spike P0.09 tested NobodyWho v13.0.0. It has the JSON-schema half but not the
control-vector half, so the rule points to our own wrapper.

## 3. Criteria

| Criterion | NobodyWho v13.0.0 (spike P0.09) | Own GDExtension over llama.cpp |
|---|---|---|
| Control-vector API | **No.** 0 vector/cvec/adapter/dose/lora/steer/control methods on the 16 `NobodyWho*` classes (ClassDB scan). Upstream issue #40 closed 2026-07-14 as stale, not implemented. `llama-cpp-rs` binds only `llama_set_adapters_lora`. | **Yes, by design.** `llama_set_adapter_cvec` per turn on one context (docs/06 §4); signature in §4. Not built or tested. |
| Grammar / JSON schema | **Yes.** `NobodyWhoSamplerBuilder.json_schema(dict)`. Property order kept. 8/8 valid turns in runs 3-5, incl. a boundary turn: `say` clamped at maxLength 200, no stray key. | **Planned** through llama.cpp `common`, for parity with llama-server (§5). Not built or measured. |
| Streaming | **Token streaming yes.** Warm TTFT 209-388 ms (runs 4-5; cold 30.8 s). First `say` content at 2.0-2.2 s at 42-44.6 tok/s, projected 8-12 s at 6.8-10.3 tok/s. The < 1 s first-beat budget was not met in any observed run. | **Planned:** blocking calls on the LLM facade worker thread (§5). Not measured. |
| Platforms | Windows x86_64 DLL tested only. Windows GPU is Vulkan only; no CUDA build. Zip has one binary per platform; others not tested. | **Planned** (§5): Windows and Linux with CUDA and Vulkan, macOS with Metal. No build yet (P4.07). |
| Licence | **EUPL-1.2** (copyleft). A commercial Steam release needs legal review. | Our wrapper, not a fork, so no EUPL-1.2 inheritance. llama.cpp is MIT (`LICENSE` in the pinned tarball). |
| llama.cpp version pinning | **No.** llama.cpp is compiled into the DLL; b12024 cannot be pinned and our build flags cannot be set. | **Yes.** Pinned to b12024 (`ddf48f85`), built with `BUILD_SHARED_LIBS=ON`, `GGML_BACKEND_DL=ON`. |
| Binary weight | 143 MB Windows DLL, including STT, TTS and ONNX code we do not use. | Not measured. No binary exists yet. |
| VRAM | 5.73 GB vs 3.25 GB for llama-server (CUDA) on the RTX 4050 (6 GB card). Tight once the game shares the GPU. | Not measured. |

Rows 1-5 are the required criteria. Rows 6-8 are added because the spike has evidence for them.

## 4. Re-check against llama.cpp

Pinned build: b12024, commit `ddf48f85c933c1f438212a02eb21e7b001d2d37d` (committed 2026-10-31). `llama-server
--version` from the b12024 release reports `build 12024, commit ddf48f85c`, and the source tarball's top directory
is `llama.cpp-ddf48f85c933c1f438212a02eb21e7b001d2d37d/`.

Header read: `include/llama.h` lines 742-748 of that tarball:

```c
    LLAMA_API int32_t llama_set_adapter_cvec(
            struct llama_context * ctx,
                     const float * data,
                          size_t   len,
                         int32_t   n_embd,
                         int32_t   il_start,
                         int32_t   il_end);
```

The symbol exists in that header, and NULL `data` clears the loaded vector. The header comment still says
`llama_control_vector_load`; the real name in `common/common.h:1239` is `common_control_vector_load(load_infos,
n_layer)`. `common_chat_templates_apply` is at `common/chat.h:378` and `common_sampler_init` at
`common/sampling.h:40`.

The spike requires a build at or after upstream PR #20381 ("Reset graph on control vector change", merged
2026-03-18 as `a69d54f9`). The GitHub compare `a69d54f9...ddf48f85` reports `ahead_by 3623, behind_by 0`, so the
pin contains the fix. The P4.03 test proves the behaviour at runtime.

The official b12024 Linux release ships `libggml-cuda.so` and `libggml-vulkan.so`, and both list the RTX 4050
(`--list-devices`, Fedora 44, driver 615.71.09). Official Windows and macOS assets were not inspected.

## 5. Decision

Ship our own thin C++ GDExtension `libleila_llm` wrapping llama.cpp. Do not use NobodyWho. Keep `llama-server`
for the prompt lab and as a dev backend.

Binding implementation choices:

- **Names:** library `libleila_llm`, GDScript class `LeilaLLM`. No brand name in shipped identifiers. This
  resolves the spike's DCR on docs/07 §1, which names `libqwenchan_llm`.
- **Build:** llama.cpp and common are compiled from the pinned source with `BUILD_SHARED_LIBS=ON` and
  `GGML_BACKEND_DL=ON`. GPU backends are loaded at runtime. On Linux and Windows the CUDA and Vulkan backends
  can come from the official release of the same commit, so no GPU SDK is needed to build the extension.
  macOS uses Metal.
- **Parity:** prompt formatting and grammar go through llama.cpp `common` (`common_chat_templates_apply`,
  `enable_thinking=false`), and sampling through `common_sampler`, to match `llama-server` behaviour.
- **Threading:** blocking extension calls run on the existing LLM facade worker thread. Nothing blocks the
  main thread.
- **Control vectors:** mixed with `common_control_vector_load` and applied per turn with `llama_set_adapter_cvec`.

## 6. Consequences

Positive:

- Per-turn control vectors on one long-lived context, which NobodyWho v13.0.0 cannot offer.
- llama.cpp is pinned and upgraded deliberately, not through a plugin release.
- The build covers llama.cpp and common only, not the STT, TTS or ONNX code in NobodyWho's bundle.
- No EUPL-1.2 inheritance from NobodyWho.

Negative:

- We own a C++ build per platform (P4.07): Windows, Linux and macOS.
- `common` is a less stable API than `llama.h`. Mitigation: pin b12024 and upgrade on purpose.
- macOS signing risk, not yet assessed (§8).
- The < 1 s first-beat budget stays open. The spike found ~85 tokens of pretty-printed JSON before the first
  `say` content and flagged a P1.x re-measurement. The own runtime inherits that item.
- docs/07 §1 still reads `libqwenchan_llm` until it is edited.

## 7. Alternatives rejected

- **NobodyWho v13.0.0:** no control-vector method (§3, row 1). Also: Windows GPU is Vulkan only, with
  3.7-44.6 tok/s run-to-run and one 995 s stall; 5.73 GB VRAM vs 3.25 GB; llama.cpp not pinnable; 143 MB
  bundle; EUPL-1.2 needs legal review for a commercial Steam build. Useful later as a fallback prompt-lab
  backend and as a reference for P4.02 plumbing (spike).
- **Forking NobodyWho to add cvec:** a fork carrying the cvec patch would itself be EUPL-1.2 and would lose the
  licence escape hatch (spike).
- **llama-server only:** its control vectors are a launch flag (`--control-vector-scaled`), so each stage change
  restarts the server (~3 s) and per-turn spikes are not possible. It is also an external process (docs/06 §4).

## 8. Not verified by this ADR

- Whether a newer llama.cpp would change this decision: not checked. The pin is deliberate.
- That an official same-commit GPU backend loads into our own source build: not yet run (P4.02 proves it).
- Official Windows and macOS backend assets for this commit: not inspected (P4.07).
- No Windows, Linux or macOS build exists. Linux GPU load and the Windows and macOS builds are unproven.
- Parity with llama-server (grammar, sampling, chat template) is unproven.
- Per-turn cvec on one context in our build is untested. Own-build streaming, first-beat < 1 s, VRAM and
  binary size are unmeasured.
- The spike's Vulkan run-to-run variance and 995 s stall are unexplained and untested on our build.
- macOS signing: not assessed.
