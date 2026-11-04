// dump_residuals — llama.cpp eval-callback tool (docs/06 §2, option b).
//
// Runs a set of chat prompts through the model and captures every named
// per-layer residual tensor ("l_out-<il>", the residual stream *after* the
// control vector is applied at that layer) for every prompt token, writing one
// .npy file per prompt with shape (n_layers, n_tokens, n_embd), float32, C-order.
//
// The tensor hook uses the public llama_context_params.cb_eval field, so the
// tool links against stock llama + common and needs no llama.cpp patches.
//
// Usage:
//   llama-dump-residuals -m MODEL.gguf --prompts prompts.txt --out-dir DIR \
//       [--layers 10-20] [--system persona.txt] [--no-system] \
//       [--cvec file.gguf[:SCALE]] [--ctx-size N] [--threads N] [-ngl N]
//
// Sanity checking the dumps against a known direction (e.g. the malice
// control vector) is done by tools/steering/check_malice.py; the two tools
// share the .npy layout documented there.
#include "common.h"
#include "chat.h"
#include "llama.h"

#include <algorithm>
#include <cctype>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

common_chat_msg msg(const std::string & role, const std::string & content) {
    common_chat_msg m;
    m.role    = role;
    m.content = content;
    return m;
}

} // namespace

// ---------------------------------------------------------------------------
// captured tensor store
// ---------------------------------------------------------------------------

struct dump_store {
    // selected layer indices -> row in the output array
    std::map<int, int> layer_row;
    // per-layer captured activations, n_tokens * n_embd floats each;
    // appended per ubatch (a decode > n_ubatch runs several graph splits)
    std::map<int, std::vector<float>> acts;
    std::map<int, int64_t> layer_tokens; // tokens captured per layer
    int64_t n_embd = 0;

    void reset() {
        acts.clear();
        layer_tokens.clear();
        // keep n_embd: it cannot change within one context
    }
};

// Eval callback: ask=true fires before a node is computed (return true to let
// it run); ask=false fires after compute, when t->data is valid on its backend.
static bool dump_eval_cb(struct ggml_tensor * t, bool ask, void * user_data) {
    if (ask) {
        return true;
    }
    auto * store = static_cast<dump_store *>(user_data);

    int il = -1;
    if (sscanf(t->name, "l_out-%d", &il) != 1) {
        return true; // not a layer residual output
    }
    auto it = store->layer_row.find(il);
    if (it == store->layer_row.end()) {
        return true; // layer not selected
    }
    if (t->type != GGML_TYPE_F32) {
        fprintf(stderr, "dump_residuals: tensor %s is not F32 (type %d), skipped\n", t->name, (int) t->type);
        return true;
    }

    const int64_t ne0   = t->ne[0]; // n_embd
    const int64_t n_tok = ggml_nelements(t) / ne0;
    if (store->n_embd == 0) {
        store->n_embd = ne0;
    }
    if (store->n_embd != ne0) {
        fprintf(stderr, "dump_residuals: inconsistent n_embd for %s, skipped\n", t->name);
        return true;
    }

    auto & dst = store->acts[il];
    const size_t off = dst.size();
    dst.resize(off + ne0 * n_tok);
    ggml_backend_tensor_get(t, dst.data() + off, 0, (size_t) ne0 * n_tok * sizeof(float));
    store->layer_tokens[il] += n_tok;
    return true;
}

// ---------------------------------------------------------------------------
// minimal .npy v1.0 writer (little-endian f32, C order)
// ---------------------------------------------------------------------------

static bool write_npy(const std::string & path, const std::vector<float> & data,
                      const std::vector<int64_t> & shape) {
    std::ostringstream dict;
    dict << "{'descr': '<f4', 'fortran_order': False, 'shape': (";
    for (size_t i = 0; i < shape.size(); i++) {
        dict << shape[i];
        if (shape.size() == 1) dict << ",";
        if (i + 1 < shape.size()) dict << ", ";
    }
    dict << "), }";
    std::string header = dict.str();
    // pad so that magic(6) + ver(2) + len(2) + header is a multiple of 64
    size_t total = 10 + header.size() + 1;
    size_t pad   = (64 - (total % 64)) % 64;
    header.append(pad, ' ');
    header.push_back('\n');

    std::ofstream out(path, std::ios::binary);
    if (!out) {
        return false;
    }
    out.write("\x93NUMPY", 6);
    char ver[2] = {1, 0};
    out.write(ver, 2);
    uint16_t hlen = (uint16_t) header.size();
    out.write(reinterpret_cast<const char *>(&hlen), 2);
    out.write(header.data(), header.size());
    out.write(reinterpret_cast<const char *>(data.data()), data.size() * sizeof(float));
    return (bool) out;
}

// ---------------------------------------------------------------------------
// args
// ---------------------------------------------------------------------------

struct dump_args {
    std::string model;
    std::string prompts_file;
    std::string system_file;
    std::string out_dir = ".";
    int layer_lo = 10;
    int layer_hi = 20;
    bool no_system = false;
    std::vector<common_control_vector_load_info> cvecs;
    int n_ctx      = 2048;
    int n_threads  = -1;
    int n_gpu_layers = 0;
};

static void usage(const char * argv0) {
    fprintf(stderr,
        "usage: %s -m MODEL.gguf --prompts FILE --out-dir DIR [options]\n"
        "  --layers A-B        residual layers to dump (default 10-20)\n"
        "  --system FILE       system-prompt text file (persona); default none\n"
        "  --cvec F[:SCALE]    control vector gguf + optional scale (repeatable)\n"
        "  --ctx-size N        context size (default 2048)\n"
        "  --threads N         cpu threads (default: llama.cpp default)\n"
        "  -ngl N              gpu layers (default 0)\n"
        "  prompts file: one user message per line; each becomes a chat-templated\n"
        "  single-turn conversation and writes <out-dir>/prompt_NNN.npy\n",
        argv0);
}

static bool parse_args(int argc, char ** argv, dump_args & a) {
    auto next = [&](int & i) -> const char * {
        if (++i >= argc) { fprintf(stderr, "missing value for %s\n", argv[i - 1]); exit(1); }
        return argv[i];
    };
    for (int i = 1; i < argc; i++) {
        std::string s = argv[i];
        if (s == "-m" || s == "--model")            a.model        = next(i);
        else if (s == "--prompts")                  a.prompts_file = next(i);
        else if (s == "--system")                   a.system_file  = next(i);
        else if (s == "--out-dir")                  a.out_dir      = next(i);
        else if (s == "--ctx-size")                 a.n_ctx        = atoi(next(i));
        else if (s == "--threads")                  a.n_threads    = atoi(next(i));
        else if (s == "-ngl" || s == "--n-gpu-layers") a.n_gpu_layers = atoi(next(i));
        else if (s == "--no-system")                a.no_system    = true;
        else if (s == "--layers") {
            std::string v = next(i);
            if (sscanf(v.c_str(), "%d-%d", &a.layer_lo, &a.layer_hi) != 2) {
                fprintf(stderr, "bad --layers value '%s' (want A-B)\n", v.c_str());
                return false;
            }
        } else if (s == "--cvec") {
            // FNAME[:SCALE] — a drive-letter colon ("D:/...") is part of the
            // path, so split on the LAST colon only if what follows is numeric.
            std::string v = next(i);
            float scale = 1.0f;
            std::string fname = v;
            auto pos = v.rfind(':');
            if (pos != std::string::npos && pos + 1 < v.size()) {
                std::string tail = v.substr(pos + 1);
                if (tail.find_first_not_of("+-.0123456789eE") == std::string::npos) {
                    scale = strtof(tail.c_str(), nullptr);
                    fname = v.substr(0, pos);
                }
            }
            a.cvecs.push_back({ scale, fname });
        } else if (s == "-h" || s == "--help") {
            usage(argv[0]);
            exit(0);
        } else {
            fprintf(stderr, "unknown arg '%s'\n", s.c_str());
            return false;
        }
    }
    if (a.model.empty() || a.prompts_file.empty()) {
        usage(argv[0]);
        return false;
    }
    return true;
}

static std::string slurp(const std::string & path) {
    std::ifstream in(path);
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

// ---------------------------------------------------------------------------

int main(int argc, char ** argv) {
    dump_args args;
    if (!parse_args(argc, argv, args)) {
        return 1;
    }

    std::string system_prompt;
    if (!args.no_system && !args.system_file.empty()) {
        system_prompt = slurp(args.system_file);
    }

    // prompts: one user message per non-empty line
    std::vector<std::string> prompts;
    {
        std::ifstream in(args.prompts_file);
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            // '#' starts a comment line
            std::string trimmed = line;
            trimmed.erase(trimmed.begin(), std::find_if(trimmed.begin(), trimmed.end(),
                          [](unsigned char c) { return !std::isspace(c); }));
            if (trimmed.empty() || trimmed[0] == '#') continue;
            prompts.push_back(line);
        }
    }
    if (prompts.empty()) {
        fprintf(stderr, "dump_residuals: no prompts in %s\n", args.prompts_file.c_str());
        return 1;
    }

    llama_backend_init();

    // model + context
    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = args.n_gpu_layers;
    llama_model * model = llama_model_load_from_file(args.model.c_str(), mparams);
    if (!model) {
        fprintf(stderr, "dump_residuals: failed to load model %s\n", args.model.c_str());
        return 1;
    }

    dump_store store;
    for (int il = args.layer_lo; il <= args.layer_hi; il++) {
        store.layer_row[il] = il - args.layer_lo;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx     = args.n_ctx;
    cparams.n_batch   = args.n_ctx;
    cparams.n_ubatch  = 512;
    cparams.cb_eval   = dump_eval_cb;
    cparams.cb_eval_user_data = &store;
    if (args.n_threads > 0) {
        cparams.n_threads       = args.n_threads;
        cparams.n_threads_batch = args.n_threads;
    }

    llama_context * ctx = llama_init_from_model(model, cparams);
    if (!ctx) {
        fprintf(stderr, "dump_residuals: failed to create context\n");
        return 1;
    }

    // optional control vector(s) — same loading path as llama-server
    // --control-vector[-scaled]. Buffer layout: layer 1 at offset 0, matching
    // common_control_vector_load (direction.N applies to block index N).
    common_control_vector_data cvec = { -1, {} };
    if (!args.cvecs.empty()) {
        cvec = common_control_vector_load(args.cvecs, llama_model_n_layer(model));
        if (cvec.n_embd <= 0) {
            fprintf(stderr, "dump_residuals: failed to load control vector\n");
            return 1;
        }
        // layer range = the file's directions (lowest..highest non-zero block)
        int n_dir_layers = (int) (cvec.data.size() / cvec.n_embd);
        int lo = n_dir_layers, hi = 0;
        for (int il = 1; il <= n_dir_layers; il++) {
            const float * p = cvec.data.data() + (size_t) cvec.n_embd * (il - 1);
            for (int j = 0; j < cvec.n_embd; j++) {
                if (p[j] != 0.0f) { lo = std::min(lo, il); hi = il; break; }
            }
        }
        if (llama_set_adapter_cvec(ctx, cvec.data.data(), cvec.data.size(),
                                   cvec.n_embd, lo, hi) != 0) {
            fprintf(stderr, "dump_residuals: llama_set_adapter_cvec failed\n");
            return 1;
        }
        fprintf(stderr, "dump_residuals: cvec applied on layers %d-%d (n_embd=%d)\n",
                lo, hi, cvec.n_embd);
    }

    // chat template straight from the model metadata (jinja), thinking off —
    // identical to llama-server --jinja with enable_thinking=false
    auto tmpls = common_chat_templates_init(model, "");
    const llama_vocab * vocab = llama_model_get_vocab(model);

    for (size_t pi = 0; pi < prompts.size(); pi++) {
        common_chat_templates_inputs inputs;
        inputs.use_jinja       = true;
        inputs.enable_thinking = false;
        if (!system_prompt.empty()) {
            inputs.messages.push_back(msg("system", system_prompt));
        }
        inputs.messages.push_back(msg("user", prompts[pi]));

        common_chat_params rendered = common_chat_templates_apply(tmpls.get(), inputs);
        const std::string text = rendered.prompt.str();

        std::vector<llama_token> toks = common_tokenize(vocab, text, /*add_special*/ true, /*parse_special*/ true);
        if ((int) toks.size() > args.n_ctx) {
            fprintf(stderr, "dump_residuals: prompt %zu too long (%zu tokens > %d), skipped\n",
                    pi, toks.size(), args.n_ctx);
            continue;
        }

        store.reset();

        llama_memory_clear(llama_get_memory(ctx), true);
        llama_batch batch = llama_batch_get_one(toks.data(), (int32_t) toks.size());
        if (llama_decode(ctx, batch) != 0) {
            fprintf(stderr, "dump_residuals: llama_decode failed for prompt %zu\n", pi);
            continue;
        }

        // assemble (n_layers, n_tokens, n_embd); each layer must cover all
        // tokens (ubatch appends keep token order within each layer)
        const int n_layers = args.layer_hi - args.layer_lo + 1;
        const int64_t n_tok = (int64_t) toks.size();
        std::vector<float> arr((size_t) n_layers * n_tok * store.n_embd, 0.0f);
        bool ok = true;
        for (int il = args.layer_lo; il <= args.layer_hi; il++) {
            auto it = store.acts.find(il);
            if (it == store.acts.end() || store.layer_tokens[il] != n_tok) {
                fprintf(stderr, "dump_residuals: prompt %zu: layer %d captured %" PRId64 "/%zu tokens\n",
                        pi, il, store.layer_tokens.count(il) ? store.layer_tokens[il] : 0, toks.size());
                ok = false;
                break;
            }
            std::copy(it->second.begin(), it->second.end(),
                      arr.begin() + (size_t) store.layer_row[il] * n_tok * store.n_embd);
        }
        if (!ok) continue;

        char fname[512];
        snprintf(fname, sizeof(fname), "%s/prompt_%03zu.npy", args.out_dir.c_str(), pi);
        if (!write_npy(fname, arr, { n_layers, n_tok, store.n_embd })) {
            fprintf(stderr, "dump_residuals: failed to write %s\n", fname);
            return 1;
        }
        fprintf(stderr, "dump_residuals: prompt %zu -> %s (%d layers x %" PRId64 " tokens x %" PRId64 ")\n",
                pi, fname, n_layers, n_tok, store.n_embd);
    }

    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();
    return 0;
}
