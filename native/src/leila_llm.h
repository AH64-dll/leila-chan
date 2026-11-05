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

	// config: model_path (required), backend_dir (required), n_ctx=8192, n_gpu_layers=99,
	// n_threads=-1 (<=0 means common_cpu_get_num_math()).
	// Returns {ok, load_ms, n_layer, n_embd, n_ctx, n_threads, gpu_offload, devices} or {ok:false, error:{code,message}}.
	godot::Dictionary load_model(const godot::Dictionary &config);

	bool is_loaded() const;

	// Waits for any running generate() to finish, then frees context, templates and model.
	void unload();

	// Per-turn control vectors. vectors: [{"path": String, "scale": float}, ...]; [] clears them.
	// Returns {ok:true, applied, set_ms, n_vectors} or {ok:false, error:{code,message}}.
	// applied is false when the list equals the one already bound. On any error the previously
	// bound vectors stay in place. Never reloads the model or recreates the context.
	godot::Dictionary set_control_vectors(const godot::Array &vectors);

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

	// Mirror of llama.cpp's common_control_vector_data, so llama.cpp types stay out of this header.
	struct CvecUnit {
		int32_t n_embd = -1;
		std::vector<float> data;  // layers [1, n_layer] at strength 1.0
	};

	std::mutex mu_;      // held by load_model, unload, generate, set_control_vectors
	std::mutex cls_mu_;  // held by classify; load_model and unload take mu_ then cls_mu_
	std::atomic<bool> loaded_{ false };
	llama_model *model_ = nullptr;
	llama_context *ctx_ = nullptr;      // the turn's context; the only one that may carry a control vector
	llama_context *ctx_cls_ = nullptr;  // classifier context, created lazily by classify(); never gets a vector
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
};
