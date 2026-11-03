class_name TurnRequest
extends RefCounted
## One generation request (docs/07 §3.1):
## {messages, schema, sampling, dose, max_tokens}. Built by SYS per turn
## (PromptBuilder + schema builder, docs/02 §3-4).
##
## Request ownership: TurnRequest instances are single-use per turn and owned
## by the in-flight turn once passed to LLM.generate(). Callers must not reuse
## or mutate a TurnRequest after passing it to generate() — the worker thread
## reads it.

const DEFAULT_MAX_TOKENS := 600  # docs/07 §3.1: output budget <= 600 tokens

var messages: Array[Dictionary] = []  # [{"role": "system"|"user"|"assistant", "content": String}]
var schema := {}  # turn JSON schema, compiled to a grammar per request (docs/02 §3)
var sampling := {}  # temperature, top_p, repeat_penalty, seed... (docs/02 §9)
var dose := {}  # {"malice": 4.5} — control-vector scales; LLM.set_dose() fills it when left empty
var max_tokens := DEFAULT_MAX_TOKENS


func to_dict() -> Dictionary:
	return {
		"messages": messages,
		"schema": schema,
		"sampling": sampling,
		"dose": dose,
		"max_tokens": max_tokens,
	}
