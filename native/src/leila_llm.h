#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

// Scaffold class. The real inference API comes in a later task.
class LeilaLLM : public godot::RefCounted {
	GDCLASS(LeilaLLM, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Returns "leila_llm 0.1 | <llama build info> | <llama system info>".
	godot::String version() const;
};
