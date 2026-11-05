#include "leila_llm.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/char_string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <exception>
#include <filesystem>
#include <mutex>
#include <stdexcept>
#include <string>
#include <system_error>
#include <unordered_map>
#include <utility>
#include <vector>

#include "build-info.h"
#include "chat.h"
#include "common.h"
#include "ggml-backend.h"
#include "json.h"
#include "llama.h"
#include "sampling.h"

namespace {

using clock_type = std::chrono::steady_clock;
constexpr size_t kNpos = std::string::npos;
constexpr int32_t kBatch = 2048;  // n_batch: max tokens per llama_decode call while decoding the prompt
// classify(): its own context. Its n_ctx and n_ubatch come from the load config (cls_ctx_, cls_ubatch_).
constexpr int64_t kClsMaxPrompt = 1000;

// Error with a stable code, mapped to the API error codes at the boundary.
struct LeilaError : std::runtime_error {
	LeilaError(const char *c, const std::string &msg) : std::runtime_error(msg), code(c) {}
	const char *code;
};

struct Metrics {
	int64_t prompt_tokens = 0;
	int64_t completion_tokens = 0;
	int64_t prompt_ms = 0;
	int64_t ttft_ms = 0;   // generate() start to first sampled token
	int64_t total_ms = 0;  // generate() start to return
	double tok_per_s = 0.0;  // completion tokens over (total - prompt) time
	std::string stop_reason;
};

// ---- string and variant helpers --------------------------------------------

godot::String to_godot(const std::string &s) {
	return godot::String::utf8(s.data(), static_cast<int64_t>(s.size()));
}

std::string from_godot(const godot::String &s) {
	godot::CharString cs = s.utf8();
	return std::string(cs.get_data(), static_cast<size_t>(cs.length()));
}

bool dict_has(const godot::Dictionary &d, const char *key) {
	return d.has(godot::String(key));
}

godot::Variant dict_get(const godot::Dictionary &d, const char *key) {
	return d.get(godot::String(key), godot::Variant());
}

int64_t dict_int(const godot::Dictionary &d, const char *key, int64_t def) {
	return dict_has(d, key) ? static_cast<int64_t>(dict_get(d, key)) : def;
}

double dict_num(const godot::Dictionary &d, const char *key, double def) {
	return dict_has(d, key) ? static_cast<double>(dict_get(d, key)) : def;
}

std::string dict_str(const godot::Dictionary &d, const char *key, const std::string &def) {
	if (!dict_has(d, key)) {
		return def;
	}
	return from_godot(static_cast<godot::String>(dict_get(d, key)));
}

// ---- result builders -------------------------------------------------------

godot::Dictionary metrics_dict(const Metrics &m) {
	godot::Dictionary d;
	d["prompt_tokens"] = m.prompt_tokens;
	d["completion_tokens"] = m.completion_tokens;
	d["prompt_ms"] = m.prompt_ms;
	d["ttft_ms"] = m.ttft_ms;
	d["total_ms"] = m.total_ms;
	d["tok_per_s"] = m.tok_per_s;
	d["stop_reason"] = godot::String(m.stop_reason.c_str());
	return d;
}

godot::Dictionary error_dict(const char *code, const std::string &message) {
	godot::Dictionary err;
	err["code"] = godot::String(code);
	err["message"] = to_godot(message);
	godot::Dictionary out;
	out["ok"] = false;
	out["error"] = err;
	return out;
}

godot::Dictionary fail_dict(const char *code, const std::string &message, const Metrics &m) {
	godot::Dictionary out = error_dict(code, message);
	out["metrics"] = metrics_dict(m);
	return out;
}

int64_t ms_between(clock_type::time_point a, clock_type::time_point b) {
	return std::chrono::duration_cast<std::chrono::milliseconds>(b - a).count();
}

int64_t ms_since(clock_type::time_point a) {
	return ms_between(a, clock_type::now());
}

// Completion tokens per second over the generation phase (total minus prompt time).
// Called on every return path that ran the generation loop, including cancel.
void set_rate(Metrics &m) {
	const int64_t gen_ms = m.total_ms - m.prompt_ms;
	m.tok_per_s = gen_ms > 0 ? static_cast<double>(m.completion_tokens) * 1000.0 / static_cast<double>(gen_ms) : 0.0;
}

// ---- backends and logging --------------------------------------------------

bool g_log_keep_continuation = false;

// Drops llama/ggml log lines below WARN. Anything kept goes to stderr, never stdout.
void log_callback(ggml_log_level level, const char *text, void *) {
	if (level == GGML_LOG_LEVEL_CONT) {
		if (g_log_keep_continuation) {
			fputs(text, stderr);
		}
		return;
	}
	g_log_keep_continuation = level >= GGML_LOG_LEVEL_WARN;
	if (g_log_keep_continuation) {
		fputs(text, stderr);
	}
}

std::once_flag g_backend_once;

// Runs once per process. A later backend_dir is ignored.
void init_backends(const std::string &backend_dir) {
	std::call_once(g_backend_once, [&backend_dir]() {
		llama_log_set(log_callback, nullptr);
		ggml_backend_load_all_from_path(backend_dir.c_str());
		llama_backend_init();
	});
}

// ---- sampling dict ---------------------------------------------------------

// Maps the GDScript `sampling` dictionary onto common_params_sampling. Unset keys keep the
// common_params_sampling defaults, which are the llama-server defaults.
void apply_sampling_dict(const godot::Dictionary &d, common_params_sampling &sp, std::vector<std::string> &stops) {
	sp.temp = static_cast<float>(dict_num(d, "temperature", sp.temp));
	sp.top_p = static_cast<float>(dict_num(d, "top_p", sp.top_p));
	sp.top_k = static_cast<int32_t>(dict_int(d, "top_k", sp.top_k));
	sp.min_p = static_cast<float>(dict_num(d, "min_p", sp.min_p));
	sp.penalty_repeat = static_cast<float>(dict_num(d, "repeat_penalty", sp.penalty_repeat));
	sp.penalty_last_n = static_cast<int32_t>(dict_int(d, "repeat_last_n", sp.penalty_last_n));
	sp.penalty_present = static_cast<float>(dict_num(d, "presence_penalty", sp.penalty_present));
	sp.penalty_freq = static_cast<float>(dict_num(d, "frequency_penalty", sp.penalty_freq));
	sp.seed = static_cast<uint32_t>(dict_int(d, "seed", static_cast<int64_t>(sp.seed)));

	if (dict_has(d, "stop")) {
		godot::Array arr = dict_get(d, "stop");
		for (int64_t i = 0; i < arr.size(); ++i) {
			godot::Variant v = arr[i];
			if (v.get_type() == godot::Variant::STRING) {
				std::string s = from_godot(static_cast<godot::String>(v));
				if (!s.empty()) {
					stops.push_back(s);
				}
			}
		}
	}
}

// ---- stop strings and UTF-8 -----------------------------------------------

// Earliest position in text where any stop string starts and matches fully, or kNpos.
size_t find_stop(const std::string &text, const std::vector<std::string> &stops) {
	size_t best = kNpos;
	for (const auto &s : stops) {
		const size_t p = text.find(s);
		if (p != kNpos && p < best) {
			best = p;
		}
	}
	return best;
}

// Length of the longest suffix of text that is a proper prefix of some stop string.
// Those bytes are held back until the next token shows whether a stop string completes.
size_t stop_hold(const std::string &text, const std::vector<std::string> &stops) {
	size_t hold = 0;
	for (const auto &s : stops) {
		const size_t max_k = std::min(s.size() - 1, text.size());
		for (size_t k = max_k; k > hold; --k) {
			if (text.compare(text.size() - k, k, s, 0, k) == 0) {
				hold = k;
				break;
			}
		}
	}
	return hold;
}

// Length of the prefix of s that contains no incomplete trailing UTF-8 sequence.
size_t utf8_complete_len(const std::string &s) {
	const size_t n = s.size();
	for (size_t back = 1; back <= 3 && back <= n; ++back) {
		const unsigned char c = static_cast<unsigned char>(s[n - back]);
		if ((c & 0xC0) == 0x80) {
			continue;  // continuation byte, keep looking for the lead byte
		}
		const size_t need = (c >= 0xF0) ? 4 : (c >= 0xE0) ? 3 : (c >= 0xC0) ? 2 : 1;
		return need > back ? n - back : n;
	}
	return n;
}

// Moves a cut point back so it does not split a multi-byte character.
size_t utf8_boundary(const std::string &s, size_t cut) {
	while (cut > 0 && cut < s.size() && (static_cast<unsigned char>(s[cut]) & 0xC0) == 0x80) {
		--cut;
	}
	return cut;
}

// ---- prompt construction ---------------------------------------------------

// messages_json -> rendered chat prompt via the model's template (jinja, enable_thinking=false).
// Mirrors the server path: server-common.cpp:1441-1513.
common_chat_session build_session(const common_chat_templates *tmpls, const llama_vocab *vocab,
		const std::string &messages_json, const std::string &schema_json) {
	if (!schema_json.empty()) {
		try {
			(void)common_json::parse(schema_json);
		} catch (const std::exception &e) {
			throw LeilaError("invalid_request", std::string("schema_json is not valid JSON: ") + e.what());
		}
	}

	common_chat_templates_inputs inputs;
	try {
		inputs.messages = common_chat_msgs_parse_oaicompat(common_json::parse(messages_json));
	} catch (const std::exception &e) {
		throw LeilaError("invalid_request", std::string("messages_json: ") + e.what());
	}
	inputs.json_schema = schema_json;
	inputs.use_jinja = true;
	inputs.add_generation_prompt = true;
	inputs.enable_thinking = false;
	inputs.reasoning_format = COMMON_REASONING_FORMAT_DEEPSEEK;  // server default (common.h:666)
	inputs.chat_template_kwargs["enable_thinking"] = "false";    // as the server stores a request kwarg

	try {
		return common_chat_session(tmpls, vocab, inputs);
	} catch (const std::exception &e) {
		// A bad schema fails here when grammar generation rejects it.
		throw LeilaError(schema_json.empty() ? "template_failed" : "invalid_request", e.what());
	}
}

// Mirrors tokenize_mixed (server-common.cpp:991). BOS is added only to the first part.
// User input (is_input) is tokenized with parse_special=false, so typed control tokens stay text.
std::vector<llama_token> tokenize_prompt(const llama_vocab *vocab, const common_chat_prompt &prompt) {
	std::vector<llama_token> out;
	bool first = true;
	for (const auto &part : prompt.parts) {
		const bool add_special = first;
		first = false;
		const auto toks = common_tokenize(vocab, part.text, add_special, !part.is_input);
		out.insert(out.end(), toks.begin(), toks.end());
	}
	return out;
}

} // namespace

// ---- class -----------------------------------------------------------------

void LeilaLLM::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("load_model", "config"), &LeilaLLM::load_model);
	godot::ClassDB::bind_method(godot::D_METHOD("is_loaded"), &LeilaLLM::is_loaded);
	godot::ClassDB::bind_method(godot::D_METHOD("unload"), &LeilaLLM::unload);
	godot::ClassDB::bind_method(godot::D_METHOD("set_control_vectors", "vectors"), &LeilaLLM::set_control_vectors);
	godot::ClassDB::bind_method(
			godot::D_METHOD("generate", "messages_json", "schema_json", "sampling", "max_tokens", "on_token", "is_cancelled"),
			&LeilaLLM::generate);
	godot::ClassDB::bind_method(godot::D_METHOD("count_special_tokens", "messages_json"), &LeilaLLM::count_special_tokens);
	godot::ClassDB::bind_method(godot::D_METHOD("classify", "messages_json", "max_tokens"), &LeilaLLM::classify);
	godot::ClassDB::bind_method(godot::D_METHOD("version"), &LeilaLLM::version);
}

LeilaLLM::LeilaLLM() {}

LeilaLLM::~LeilaLLM() {
	std::lock_guard<std::mutex> lock(mu_);
	std::lock_guard<std::mutex> cls_lock(cls_mu_);
	free_locked();
}

void LeilaLLM::free_locked() {
	loaded_ = false;
	tmpls_.reset();
	// The classifier context goes before the model it was created from.
	if (ctx_cls_) {
		llama_free(ctx_cls_);
		ctx_cls_ = nullptr;
	}
	if (ctx_) {
		llama_free(ctx_);
		ctx_ = nullptr;
	}
	if (model_) {
		llama_model_free(model_);
		model_ = nullptr;
	}
	n_ctx_ = 0;
	n_layer_ = 0;
	n_embd_ = 0;
	gpu_offload_ = false;
	devices_.clear();
	cvec_cache_.clear();
	cvec_current_.clear();
}

godot::Dictionary LeilaLLM::load_model(const godot::Dictionary &config) {
	const auto t0 = clock_type::now();
	// Lock order: mu_, then cls_mu_. classify() takes only cls_mu_, so it never waits on a turn.
	std::lock_guard<std::mutex> lock(mu_);
	std::lock_guard<std::mutex> cls_lock(cls_mu_);

	if (loaded_) {
		return error_dict("already_loaded", "a model is already loaded; call unload() first");
	}

	try {
		const std::string model_path = dict_str(config, "model_path", "");
		const std::string backend_dir = dict_str(config, "backend_dir", "");
		std::error_code ec;
		if (model_path.empty() || !std::filesystem::is_regular_file(model_path, ec)) {
			throw LeilaError("model_missing", "model file not found: " + model_path);
		}
		if (backend_dir.empty()) {
			throw LeilaError("model_load_failed", "backend_dir is required");
		}

		init_backends(backend_dir);

		llama_model_params mp = llama_model_default_params();
		mp.n_gpu_layers = static_cast<int32_t>(dict_int(config, "n_gpu_layers", 99));
		model_ = llama_model_load_from_file(model_path.c_str(), mp);
		if (!model_) {
			throw LeilaError("model_load_failed", "llama_model_load_from_file failed: " + model_path);
		}

		// n_threads <= 0 means all math cores, as llama-server does.
		int64_t n_threads = dict_int(config, "n_threads", -1);
		if (n_threads <= 0) {
			n_threads = common_cpu_get_num_math();
		}
		// Classifier context sizes, read here so classify() creates its lazy context with them.
		// 512/64 costs 152 MiB of VRAM against 604 MiB at 1024/512 (P4.04, RTX 4050). n_ubatch is
		// the main cost. The real prompt is about 198 tokens; an overflow fails closed to bars.
		cls_ctx_ = static_cast<int32_t>(std::max<int64_t>(64, dict_int(config, "classifier_n_ctx", 512)));
		cls_ubatch_ = static_cast<int32_t>(std::max<int64_t>(16, dict_int(config, "classifier_n_ubatch", 64)));
		llama_context_params cp = llama_context_default_params();
		cp.n_ctx = static_cast<uint32_t>(dict_int(config, "n_ctx", 8192));
		cp.n_batch = kBatch;
		cp.n_ubatch = 512;
		cp.no_perf = false;
		cp.n_threads = static_cast<int32_t>(n_threads);
		cp.n_threads_batch = static_cast<int32_t>(n_threads);
		ctx_ = llama_init_from_model(model_, cp);
		if (!ctx_) {
			throw LeilaError("context_failed", "llama_init_from_model failed");
		}

		try {
			tmpls_ = common_chat_templates_init(model_, "");
		} catch (const std::exception &e) {
			throw LeilaError("template_failed", std::string("chat template init failed: ") + e.what());
		}

		n_ctx_ = static_cast<int32_t>(cp.n_ctx);
		n_layer_ = llama_model_n_layer(model_);
		n_embd_ = llama_model_n_embd(model_);

		// devices lists every ggml backend device that was registered, not the model's split.
		devices_.clear();
		gpu_offload_ = false;
		const size_t n_dev = ggml_backend_dev_count();
		for (size_t i = 0; i < n_dev; ++i) {
			ggml_backend_dev_t dev = ggml_backend_dev_get(i);
			devices_.emplace_back(ggml_backend_dev_name(dev));
			if (ggml_backend_dev_type(dev) == GGML_BACKEND_DEVICE_TYPE_GPU) {
				gpu_offload_ = true;
			}
		}
		gpu_offload_ = gpu_offload_ && mp.n_gpu_layers != 0;

		loaded_ = true;

		godot::Dictionary out;
		out["ok"] = true;
		out["load_ms"] = ms_since(t0);
		out["n_layer"] = static_cast<int64_t>(n_layer_);
		out["n_embd"] = static_cast<int64_t>(n_embd_);
		out["n_ctx"] = static_cast<int64_t>(n_ctx_);
		out["n_threads"] = static_cast<int64_t>(n_threads);
		out["gpu_offload"] = gpu_offload_;
		godot::Array devs;
		for (const auto &name : devices_) {
			devs.push_back(to_godot(name));
		}
		out["devices"] = devs;
		return out;
	} catch (const LeilaError &e) {
		free_locked();
		return error_dict(e.code, e.what());
	} catch (const std::exception &e) {
		free_locked();
		return error_dict("model_load_failed", e.what());
	}
}

bool LeilaLLM::is_loaded() const {
	return loaded_.load();
}

void LeilaLLM::unload() {
	std::lock_guard<std::mutex> lock(mu_);
	std::lock_guard<std::mutex> cls_lock(cls_mu_);
	free_locked();
}

godot::Dictionary LeilaLLM::set_control_vectors(const godot::Array &vectors) {
	const auto t_start = clock_type::now();
	auto elapsed_ms = [t_start]() {
		return std::chrono::duration<double, std::milli>(clock_type::now() - t_start).count();
	};

	std::unique_lock<std::mutex> lock(mu_, std::try_to_lock);
	if (!lock.owns_lock()) {
		return error_dict("busy", "another generate() or load is in progress");
	}
	if (!loaded_) {
		return error_dict("not_loaded", "no model loaded; call load_model() first");
	}

	try {
		// Validate the whole list before touching any state.
		std::vector<std::pair<std::string, float>> wanted;
		wanted.reserve(static_cast<size_t>(vectors.size()));
		for (int64_t i = 0; i < vectors.size(); ++i) {
			const std::string where = "control vector entry " + std::to_string(i);
			const godot::Variant entry_v = vectors[i];
			if (entry_v.get_type() != godot::Variant::DICTIONARY) {
				return error_dict("invalid_request", where + " is not a Dictionary");
			}
			const godot::Dictionary entry = entry_v;
			const std::string path = dict_str(entry, "path", "");
			if (path.empty()) {
				return error_dict("invalid_request", where + " has an empty path");
			}
			if (!entry.has("scale")) {
				return error_dict("invalid_request", where + " has no scale");
			}
			const godot::Variant scale_v = entry["scale"];
			if (scale_v.get_type() != godot::Variant::FLOAT && scale_v.get_type() != godot::Variant::INT) {
				return error_dict("invalid_request", where + " scale is not a number");
			}
			const float scale = static_cast<float>(static_cast<double>(scale_v));
			if (!std::isfinite(scale)) {
				return error_dict("invalid_request", where + " scale is not finite");
			}
			wanted.emplace_back(path, scale);
		}

		// Same list as currently bound (same order, paths and scales): nothing to do.
		if (wanted == cvec_current_) {
			godot::Dictionary out;
			out["ok"] = true;
			out["applied"] = false;
			out["set_ms"] = elapsed_ms();
			out["n_vectors"] = static_cast<int64_t>(wanted.size());
			return out;
		}

		// Load every unit before anything changes. Each path is read from disk once, then cached.
		std::vector<const CvecUnit *> units;
		units.reserve(wanted.size());
		for (const auto &item : wanted) {
			auto it = cvec_cache_.find(item.first);
			if (it == cvec_cache_.end()) {
				std::vector<common_control_vector_load_info> infos{ common_control_vector_load_info{ 1.0f, item.first } };
				common_control_vector_data loaded = common_control_vector_load(infos, n_layer_);
				if (loaded.n_embd == -1 || loaded.n_embd != n_embd_) {
					return error_dict("control_vector_load_failed", "could not load control vector: " + item.first);
				}
				it = cvec_cache_.emplace(item.first, CvecUnit{ loaded.n_embd, std::move(loaded.data) }).first;
			}
			units.push_back(&it->second);
		}

		// Mix: sum of scale * unit over all entries, zero-padded to the longest unit.
		std::vector<float> mixed;
		for (size_t k = 0; k < wanted.size(); ++k) {
			const std::vector<float> &data = units[k]->data;
			if (mixed.size() < data.size()) {
				mixed.resize(data.size(), 0.0f);
			}
			const float scale = wanted[k].second;
			for (size_t i = 0; i < data.size(); ++i) {
				mixed[i] += scale * data[i];
			}
		}

		// Apply to the existing context. Layer range 1..n_layer as common_init_from_params does.
		int32_t rc = 0;
		if (wanted.empty()) {
			rc = llama_set_adapter_cvec(ctx_, nullptr, 0, n_embd_, 1, n_layer_);
		} else {
			if (mixed.empty()) {
				return error_dict("control_vector_load_failed", "control vectors are empty");
			}
			rc = llama_set_adapter_cvec(ctx_, mixed.data(), mixed.size(), n_embd_, 1, n_layer_);
		}
		if (rc != 0) {
			return error_dict("control_vector_load_failed", "llama_set_adapter_cvec failed");
		}
		cvec_current_ = std::move(wanted);

		godot::Dictionary out;
		out["ok"] = true;
		out["applied"] = true;
		out["set_ms"] = elapsed_ms();
		out["n_vectors"] = static_cast<int64_t>(cvec_current_.size());
		return out;
	} catch (const std::exception &e) {
		return error_dict("control_vector_load_failed", e.what());
	}
}

godot::Dictionary LeilaLLM::generate(const godot::String &messages_json_g, const godot::String &schema_json_g,
		const godot::Dictionary &sampling, int64_t max_tokens,
		const godot::Callable &on_token, const godot::Callable &is_cancelled) {
	const auto t_start = clock_type::now();
	Metrics m;

	std::unique_lock<std::mutex> lock(mu_, std::try_to_lock);
	if (!lock.owns_lock()) {
		m.total_ms = ms_since(t_start);
		return fail_dict("busy", "another generate() or load is in progress", m);
	}
	if (!loaded_) {
		m.total_ms = ms_since(t_start);
		return fail_dict("not_loaded", "no model loaded; call load_model() first", m);
	}
	if (max_tokens < 1) {
		m.total_ms = ms_since(t_start);
		return fail_dict("invalid_request", "max_tokens must be >= 1", m);
	}

	auto cancelled_now = [&is_cancelled]() -> bool {
		if (!is_cancelled.is_valid()) {
			return false;
		}
		godot::Variant v = is_cancelled.call();
		return static_cast<bool>(v);
	};

	std::string text;
	auto emit = [&text, &on_token](const std::string &chunk) {
		if (chunk.empty()) {
			return;
		}
		text += chunk;
		if (on_token.is_valid()) {
			on_token.call(to_godot(chunk));
		}
	};

	try {
		const llama_vocab *vocab = llama_model_get_vocab(model_);
		common_chat_session session = build_session(tmpls_.get(), vocab, from_godot(messages_json_g), from_godot(schema_json_g));

		const std::vector<llama_token> prompt_tokens = tokenize_prompt(vocab, session.prompt());
		m.prompt_tokens = static_cast<int64_t>(prompt_tokens.size());
		if (prompt_tokens.empty()) {
			throw LeilaError("invalid_request", "rendered prompt is empty");
		}
		if (static_cast<int64_t>(prompt_tokens.size()) + max_tokens > static_cast<int64_t>(n_ctx_)) {
			throw LeilaError("prompt_too_long", "prompt_tokens + max_tokens exceeds n_ctx");
		}

		// Sampling: user keys first, then the chat session's grammar and stop settings.
		// Mirrors server-task.h:304-313 (apply_chat_session).
		common_params_sampling sp;
		std::vector<std::string> stops = session.additional_stops();
		apply_sampling_dict(sampling, sp, stops);
		sp.n_prev = std::max(sp.n_prev, sp.penalty_last_n);
		session.apply_sampling(sp);

		common_sampler_ptr smpl(common_sampler_init(model_, sp));
		if (!smpl) {
			throw LeilaError("invalid_request", "could not create sampler (bad grammar or sampling settings)");
		}
		// Prompt tokens feed the repetition-penalty history but not the grammar (accept_grammar=false).
		// Mirrors init_sampler, server-context.cpp:478-485.
		for (llama_token t : prompt_tokens) {
			common_sampler_accept(smpl.get(), t, false);
		}

		// Prompt decode, in chunks of n_batch, with a cancel check between chunks.
		llama_memory_clear(llama_get_memory(ctx_), true);
		const auto t_prompt0 = clock_type::now();
		for (size_t i = 0; i < prompt_tokens.size(); i += static_cast<size_t>(kBatch)) {
			if (cancelled_now()) {
				m.stop_reason = "cancelled";
				m.total_ms = ms_since(t_start);
				return fail_dict("cancelled", "cancelled by is_cancelled()", m);
			}
			const size_t n = std::min(static_cast<size_t>(kBatch), prompt_tokens.size() - i);
			llama_batch batch = llama_batch_get_one(const_cast<llama_token *>(prompt_tokens.data() + i), static_cast<int32_t>(n));
			if (llama_decode(ctx_, batch) != 0) {
				throw LeilaError("decode_failed", "llama_decode failed while processing the prompt");
			}
		}
		m.prompt_ms = ms_between(t_prompt0, clock_type::now());

		// Generation loop.
		std::string pending;  // generated bytes not yet emitted (stop-prefix or incomplete UTF-8)
		int64_t n_gen = 0;
		std::string stop_reason = "length";
		while (true) {
			if (cancelled_now()) {
				m.completion_tokens = n_gen;
				m.stop_reason = "cancelled";
				m.total_ms = ms_since(t_start);
				set_rate(m);
				return fail_dict("cancelled", "cancelled by is_cancelled()", m);
			}
			if (n_gen >= max_tokens) {
				stop_reason = "length";
				break;
			}

			const llama_token tok = common_sampler_sample(smpl.get(), ctx_, -1);
			common_sampler_accept(smpl.get(), tok, true);
			if (llama_vocab_is_eog(vocab, tok)) {
				stop_reason = "eos";
				break;
			}
			++n_gen;
			if (n_gen == 1) {
				m.ttft_ms = ms_since(t_start);
			}
			pending += common_token_to_piece(vocab, tok, false);

			const size_t hit = find_stop(pending, stops);
			if (hit != kNpos) {
				const std::string head = pending.substr(0, hit);
				emit(head.substr(0, utf8_complete_len(head)));
				pending.clear();
				stop_reason = "stop";
				break;
			}

			const size_t hold = stop_hold(pending, stops);
			const size_t cut = utf8_boundary(pending, std::min(pending.size() - hold, utf8_complete_len(pending)));
			emit(pending.substr(0, cut));
			pending.erase(0, cut);

			llama_token t = tok;
			llama_batch batch = llama_batch_get_one(&t, 1);
			if (llama_decode(ctx_, batch) != 0) {
				throw LeilaError("decode_failed", "llama_decode failed during generation");
			}
		}

		// Flush held-back bytes. Stop strings were already removed, and only complete UTF-8 is emitted.
		if (!pending.empty()) {
			emit(pending.substr(0, utf8_complete_len(pending)));
		}

		m.completion_tokens = n_gen;
		m.stop_reason = stop_reason;
		m.total_ms = ms_since(t_start);
		set_rate(m);

		godot::Dictionary out;
		out["ok"] = true;
		out["text"] = to_godot(text);
		out["metrics"] = metrics_dict(m);
		return out;
	} catch (const LeilaError &e) {
		m.total_ms = ms_since(t_start);
		return fail_dict(e.code, e.what(), m);
	} catch (const std::exception &e) {
		m.total_ms = ms_since(t_start);
		return fail_dict("template_failed", e.what(), m);
	}
}

int64_t LeilaLLM::count_special_tokens(const godot::String &messages_json_g) {
	std::unique_lock<std::mutex> lock(mu_, std::try_to_lock);
	if (!lock.owns_lock() || !loaded_) {
		return -1;
	}
	try {
		const llama_vocab *vocab = llama_model_get_vocab(model_);
		common_chat_session session = build_session(tmpls_.get(), vocab, from_godot(messages_json_g), "");
		const std::vector<llama_token> toks = tokenize_prompt(vocab, session.prompt());
		int64_t n = 0;
		for (llama_token t : toks) {
			if (llama_vocab_is_control(vocab, t)) {
				++n;
			}
		}
		return n;
	} catch (const std::exception &e) {
		fprintf(stderr, "leila_llm: count_special_tokens: %s\n", e.what());
		return -1;
	}
}

godot::Dictionary LeilaLLM::classify(const godot::String &messages_json_g, int64_t max_tokens) {
	const auto t_start = clock_type::now();
	Metrics m;

	// Holds only cls_mu_, never mu_: a running generate() holds mu_ for the whole turn and the
	// classifier must not wait for it. Plain blocking lock, so concurrent calls queue.
	std::lock_guard<std::mutex> lock(cls_mu_);
	if (!loaded_) {
		m.total_ms = ms_since(t_start);
		return fail_dict("not_loaded", "no model loaded; call load_model() first", m);
	}
	if (max_tokens < 1) {
		m.total_ms = ms_since(t_start);
		return fail_dict("invalid_request", "max_tokens must be >= 1", m);
	}

	try {
		const llama_vocab *vocab = llama_model_get_vocab(model_);
		// Player text is tokenized with parse_special=false (tokenize_prompt), so it cannot become control tokens.
		common_chat_session session = build_session(tmpls_.get(), vocab, from_godot(messages_json_g), "");
		const std::vector<llama_token> prompt_tokens = tokenize_prompt(vocab, session.prompt());
		m.prompt_tokens = static_cast<int64_t>(prompt_tokens.size());
		if (prompt_tokens.empty()) {
			throw LeilaError("invalid_request", "rendered prompt is empty");
		}
		if (m.prompt_tokens > kClsMaxPrompt) {
			throw LeilaError("prompt_too_long", "classifier prompt is over 1000 tokens");
		}
		if (m.prompt_tokens + max_tokens > static_cast<int64_t>(cls_ctx_)) {
			throw LeilaError("prompt_too_long", "prompt_tokens + max_tokens exceeds the classifier context");
		}

		// Created on the first call. A failure leaves ctx_cls_ null, so a later call retries.
		// Same model, its own context, no control vector. Never call llama_set_adapter_cvec on
		// ctx_cls_: an unbound context is the dose-0 guarantee of docs/02 §8 (SAF-3).
		if (!ctx_cls_) {
			llama_context_params cp = llama_context_default_params();
			cp.n_ctx = static_cast<uint32_t>(cls_ctx_);
			cp.n_batch = static_cast<uint32_t>(cls_ctx_);
			cp.n_ubatch = static_cast<uint32_t>(cls_ubatch_);
			cp.no_perf = false;
			cp.n_threads = llama_n_threads(ctx_);
			cp.n_threads_batch = llama_n_threads(ctx_);
			ctx_cls_ = llama_init_from_model(model_, cp);
			if (!ctx_cls_) {
				throw LeilaError("context_failed", "llama_init_from_model failed for the classifier context");
			}
		}

		// Prompt decode from an empty cache, in chunks of n_batch.
		llama_memory_clear(llama_get_memory(ctx_cls_), true);
		for (size_t i = 0; i < prompt_tokens.size(); i += static_cast<size_t>(cls_ctx_)) {
			const size_t n = std::min(static_cast<size_t>(cls_ctx_), prompt_tokens.size() - i);
			llama_batch batch = llama_batch_get_one(const_cast<llama_token *>(prompt_tokens.data() + i), static_cast<int32_t>(n));
			if (llama_decode(ctx_cls_, batch) != 0) {
				throw LeilaError("decode_failed", "llama_decode failed while processing the classifier prompt");
			}
		}

		// Greedy: temp 0 and top_k 1. No grammar and no stop strings. Only end-of-generation or max_tokens stops it.
		common_params_sampling sp;
		sp.temp = 0.0f;
		sp.top_k = 1;
		common_sampler_ptr smpl(common_sampler_init(model_, sp));
		if (!smpl) {
			throw LeilaError("invalid_request", "could not create classifier sampler");
		}
		for (llama_token t : prompt_tokens) {
			common_sampler_accept(smpl.get(), t, false);
		}

		std::string text;
		int64_t n_gen = 0;
		std::string stop_reason = "length";
		while (true) {
			if (n_gen >= max_tokens) {
				stop_reason = "length";
				break;
			}
			const llama_token tok = common_sampler_sample(smpl.get(), ctx_cls_, -1);
			common_sampler_accept(smpl.get(), tok, true);
			if (llama_vocab_is_eog(vocab, tok)) {
				stop_reason = "eos";
				break;
			}
			++n_gen;
			text += common_token_to_piece(vocab, tok, false);

			llama_token t = tok;
			llama_batch batch = llama_batch_get_one(&t, 1);
			if (llama_decode(ctx_cls_, batch) != 0) {
				throw LeilaError("decode_failed", "llama_decode failed during classification");
			}
		}
		// A cut at max_tokens can split a UTF-8 sequence; drop the incomplete tail.
		text.erase(utf8_complete_len(text));

		m.completion_tokens = n_gen;
		m.stop_reason = stop_reason;
		m.total_ms = ms_since(t_start);

		godot::Dictionary out;
		out["ok"] = true;
		out["text"] = to_godot(text);
		out["metrics"] = metrics_dict(m);
		return out;
	} catch (const LeilaError &e) {
		m.total_ms = ms_since(t_start);
		return fail_dict(e.code, e.what(), m);
	} catch (const std::exception &e) {
		m.total_ms = ms_since(t_start);
		return fail_dict("template_failed", e.what(), m);
	}
}

godot::String LeilaLLM::version() const {
	// string_format is a non-inline llama-common symbol. Calling it proves llama-common links.
	std::string s = string_format("leila_llm 0.1 | %s | %s", llama_build_info(), llama_print_system_info());
	return to_godot(s);
}
