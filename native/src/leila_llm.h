#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
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

	// config: model_path (required), backend_dir (required), n_ctx=8192, n_gpu_layers=99, n_threads=-1.
	// Returns {ok, load_ms, n_layer, n_embd, n_ctx, gpu_offload, devices} or {ok:false, error:{code,message}}.
	godot::Dictionary load_model(const godot::Dictionary &config);

	bool is_loaded() const;

	// Waits for any running generate() to finish, then frees context, templates and model.
	void unload();

	// Returns {ok:true, text, metrics} or {ok:false, error:{code,message}, metrics}.
	// on_token(String chunk) receives complete UTF-8 chunks. is_cancelled() is polled before each token.
	godot::Dictionary generate(const godot::String &messages_json, const godot::String &schema_json,
			const godot::Dictionary &sampling, int64_t max_tokens,
			const godot::Callable &on_token, const godot::Callable &is_cancelled);

	// Debug helper. Returns the number of control (special) tokens in the prompt that
	// generate() would build for these messages, or -1 on error or when busy or not loaded.
	int64_t count_special_tokens(const godot::String &messages_json);

	// Returns "leila_llm 0.1 | <llama build info> | <llama system info>".
	godot::String version() const;

private:
	// Frees everything. The caller must hold mu_.
	void free_locked();

	std::mutex mu_;
	std::atomic<bool> loaded_{ false };
	llama_model *model_ = nullptr;
	llama_context *ctx_ = nullptr;
	std::shared_ptr<common_chat_templates> tmpls_;
	int32_t n_ctx_ = 0;
	int32_t n_layer_ = 0;
	int32_t n_embd_ = 0;
	bool gpu_offload_ = false;
	std::vector<std::string> devices_;
};
