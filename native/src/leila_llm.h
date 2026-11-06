#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

// llama.cpp types stay out of this header; they are included in leila_llm.cpp only.
struct llama_model;
struct llama_context;
struct common_chat_templates;

// In-process LLM. load_model, generate and count_special_tokens block the caller's thread.
// Never call from the main thread while a generation is running; use a worker thread.
class LeilaLLM : public godot::RefCounted {
	GDCLASS(LeilaLLM, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	LeilaLLM();
	~LeilaLLM();

	// config: model_path (required), backend_dir (required), device="auto" (see below), n_gpu_layers=99,
	// n_ctx=8192, n_ubatch=128, n_threads=-1 (<=0 means common_cpu_get_num_math()), classifier_n_ctx=512,
	// classifier_n_ubatch=64, prompt_cache=1.
	// device "auto": the GPU with the most total memory (a CUDA name wins a tie); an IGPU with at least 3 GB only when
	// no GPU exists; else the CPU. device "cpu": no device, n_gpu_layers 0. Any other name must be a registered device
	// (see list_devices), which is used alone; an unknown name fails with invalid_request.
	// Returns {ok, load_ms, n_layer, n_embd, n_ctx, n_ubatch, n_threads, gpu_offload, devices, device, device_type,
	// vram_total_mb, vram_free_mb, gpu_layers, classifier_ready} or {ok:false, error:{code,message}}.
	// device is the chosen name, or "cpu". device_type is "gpu", "igpu" or "cpu". vram_total_mb and vram_free_mb are
	// that device's memory, read before the load (0 on the CPU). gpu_layers is the value used. devices lists every
	// registered device. classifier_ready is false when the classifier context could not be made at load; classify()
	// then retries it. Error codes: invalid_request, model_missing, model_load_failed, context_failed, already_loaded,
	// cancelled. A failed or cancelled load frees everything it allocated.
	godot::Dictionary load_model(const godot::Dictionary &config);

	// Registered ggml backend devices, after loading backends from backend_dir:
	// [{name, description, type, total_mb, free_mb}]. type is "gpu", "igpu", "cpu", "accel" or "meta".
	// Takes no model lock.
	godot::Array list_devices(const godot::String &backend_dir);

	// Asks a load_model running on another thread to stop. Only sets a flag, so it takes no lock and is safe from any
	// thread. The load then returns {ok:false, error:{code:"cancelled"}}. load_model clears the flag when it returns,
	// never when it starts, so a cancel that arrives just before a load begins still applies to that load.
	void cancel_load();

	bool is_loaded() const;

	// Waits for any running generate() to finish, then frees context, templates and model.
	void unload();

	// Per-turn control vectors. vectors: [{"path": String, "scale": float}, ...]; [] clears them.
	// Returns {ok:true, applied, set_ms, n_vectors} or {ok:false, error:{code,message}}.
	// applied is false when the list equals the one already bound. On any error the previously
	// bound vectors stay in place. Never reloads the model or recreates the context.
	godot::Dictionary set_control_vectors(const godot::Array &vectors);

	// Drops the prompt-prefix KV cache and its checkpoints, so the next generate() decodes its whole prompt. Uses try_lock on
	// mu_, as set_control_vectors does. Returns false when busy; true when no model is loaded.
	bool clear_prompt_cache();

	// Load progress in [0, 1], written by load_model's progress callback. Lock-free: safe to poll from the
	// main thread while load_model runs on another thread. Reset to 0 at the start of load_model, 1 once
	// the context exists.
	float load_progress() const;

	// Returns {ok:true, text, metrics} or {ok:false, error:{code,message}, metrics}.
	// on_token(String chunk) receives complete UTF-8 chunks. is_cancelled() is polled before each token.
	godot::Dictionary generate(const godot::String &messages_json, const godot::String &schema_json,
			const godot::Dictionary &sampling, int64_t max_tokens,
			const godot::Callable &on_token, const godot::Callable &is_cancelled);

	// Debug helper. Returns the number of control (special) tokens in the prompt that
	// generate() would build for these messages, or -1 on error or when busy or not loaded.
	int64_t count_special_tokens(const godot::String &messages_json);

	// Classifier pass for the output filter (docs/02 §8). Runs on its own llama_context over the
	// same model, which never gets a control vector: dose 0 by construction. Greedy, no grammar,
	// no thinking, prompt <= 1000 tokens. Queues on cls_mu_ only, so it runs while generate() holds mu_.
	// Returns {ok:true, text, metrics} or {ok:false, error:{code,message}, metrics}.
	godot::Dictionary classify(const godot::String &messages_json, int64_t max_tokens);

	// Returns "leila_llm 0.1 | <llama build info> | <llama system info>".
	godot::String version() const;

private:
	// Frees everything. The caller must hold mu_ and cls_mu_, in that order.
	void free_locked();

	// Creates ctx_cls_ on the loaded model. Returns false when llama.cpp cannot create it; ctx_cls_ then stays null.
	// The caller must hold mu_ and cls_mu_, in that order, or cls_mu_ alone when a model is loaded (classify()).
	bool init_classifier_locked();

	// Mirror of llama.cpp's common_control_vector_data, so llama.cpp types stay out of this header.
	struct CvecUnit {
		int32_t n_embd = -1;
		std::vector<float> data;  // layers [1, n_layer] at strength 1.0
	};

	std::mutex mu_;      // held by load_model, unload, generate, set_control_vectors
	std::mutex cls_mu_;  // held by classify; load_model and unload take mu_ then cls_mu_
	std::atomic<bool> loaded_{ false };
	std::atomic<bool> load_cancel_{ false };  // set by cancel_load(); read by the load progress callback and load_model's checks
	llama_model *model_ = nullptr;
	llama_context *ctx_ = nullptr;      // the turn's context; the only one that may carry a control vector
	llama_context *ctx_cls_ = nullptr;  // classifier context, created by load_model (classify() retries); never gets a vector
	int32_t cls_ctx_ = 512;             // classifier n_ctx (also its n_batch), from config classifier_n_ctx
	int32_t cls_ubatch_ = 64;           // classifier n_ubatch, from config classifier_n_ubatch
	std::shared_ptr<common_chat_templates> tmpls_;
	int32_t n_ctx_ = 0;
	int32_t n_layer_ = 0;
	int32_t n_embd_ = 0;
	bool gpu_offload_ = false;
	std::vector<std::string> devices_;
	std::unordered_map<std::string, CvecUnit> cvec_cache_;     // path -> unit vector; never re-read from disk
	std::vector<std::pair<std::string, float>> cvec_current_;  // (path, scale) list bound to ctx_; empty = none
	int32_t n_ubatch_ = 128;    // main context n_ubatch, from config n_ubatch (default 128, P4.05; clamped to [16, kBatch])
	bool prompt_cache_ = true;  // config prompt_cache: 0 turns prompt-prefix reuse off
	// Prompt tokens whose KV the main context holds from the last generate(); never generated tokens.
	// int32_t is llama_token (llama.h), spelled out so that llama.h stays out of this header.
	std::vector<int32_t> cache_tokens_;
	// Recurrent state of sequence 0 after the first n_tokens prompt tokens (P4.05). Qwen3.5 cannot roll back its
	// recurrent layers, so reuse restarts from a checkpoint. n_tokens is a multiple of n_ubatch_ and below the prompt
	// length. Sorted by n_tokens. Built during prompt decode; cleared wherever cache_tokens_ is cleared.
	struct PromptCheckpoint {
		int64_t n_tokens = 0;
		std::vector<uint8_t> state;  // llama_state_seq_get_data_ext with LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY
	};
	std::vector<PromptCheckpoint> checkpoints_;
	std::atomic<float> load_progress_{ 0.0f };
};
