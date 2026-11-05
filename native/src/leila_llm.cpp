#include "leila_llm.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>

#include "build-info.h"
#include "common.h"
#include "llama.h"

void LeilaLLM::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("version"), &LeilaLLM::version);
}

godot::String LeilaLLM::version() const {
	// string_format is a non-inline llama-common symbol. Calling it proves llama-common links.
	std::string s = string_format("leila_llm 0.1 | %s | %s", llama_build_info(), llama_print_system_info());
	return godot::String(s.c_str());
}
