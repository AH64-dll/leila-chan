class_name IncrementalJson
extends RefCounted
## IncrementalJson — incremental parser for the streamed Turn object
## (docs/07 §3.2, docs/02 §1). A backend feeds raw text chunks; the parser
## knows nothing about transport and never blocks.
##
## feed() returns the events that chunk completed, in stream (schema) order:
##   {"type": "field",      "name": String, "value": Variant}   a field's value closed
##   {"type": "beat_start", "index": int}                       beats[i] object opened
##   {"type": "beat_field", "index": int, "name": String, "value": Variant}
##   {"type": "say_chunk",  "index": int, "text": String}       partial decoded say text
##   {"type": "error",      "message": String, "offset": int}   syntax error (terminal)
##
## Conventions where the doc is open (fixed here so P1.08/P1.09 can rely on them):
## - `mood` is a leaf object: one field("mood", Dictionary) event when it closes.
## - `beats` never emits a field event: content arrives through beat_* events.
## - `say` streams as say_chunk partials, then closes with beat_field(i, "say",
##   full text) like the other beat scalars — the event order per beat is
##   feeling, intensity, cue, say_chunks..., beat_field("say").
## - Numbers emit int when integral (intensity, mood) and float otherwise;
##   JSON.parse gives float for both, so compare loosely.
## - finish() is terminal: OK only if the root value closed, TRUNCATED if the
##   stream ended mid-structure, ERROR on a syntax violation. Pending
##   unterminated tokens (a number with no trailing delimiter) commit nothing.
## - feed() after finish() or after an error returns an empty Array.
## - get_value() mirrors a full JSON.parse of the completed portion
##   (integral numbers stay int).

enum Status { PARSING, OK, TRUNCATED, ERROR }

enum ParseState { VALUE, OBJ_KEY, OBJ_KEY2, COLON, OBJ_TAIL, ARR_TAIL, STR, NUM, DONE, ERR }
enum ContainerRole { ROOT, BEAT, SUB, BEATS, GEN }

const _Q := 0x22  # "
const _BS := 0x5C  # backslash
const _FS := 0x2F  # /
const _OB := 0x7B  # {
const _CB := 0x7D  # }
const _OS := 0x5B  # [
const _CS := 0x5D  # ]
const _CL := 0x3A  # :
const _CM := 0x2C  # ,
const _MN := 0x2D  # -
const _PL := 0x2B  # +
const _DT := 0x2E  # .
const _B := 0x62  # b
const _F := 0x66  # f
const _N := 0x6E  # n
const _R := 0x72  # r
const _T := 0x74  # t
const _U := 0x75  # u
const _REPL := 0xFFFD

var _buf := ""
var _pos := 0
var _offset := 0
var _s: int = ParseState.VALUE
var _stack: Array[Dictionary] = []
var _str_acc := ""
var _say_pending := ""
var _str_key := false
var _str_say := false
var _say_idx := -1
var _esc := 0
var _hex := ""
var _high := -1
var _num := ""
var _root: Variant = null
var _error_msg := ""
var _error_off := -1
var _status: int = Status.PARSING
var _finished := false


## Feed one text chunk; returns the events it completed (possibly empty).
func feed(chunk: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _finished or _s == ParseState.ERR:
		return out
	_buf += chunk
	while _pos < _buf.length() and _s != ParseState.ERR:
		var c := _buf.unicode_at(_pos)
		if _s == ParseState.STR:
			_step_str(c, out)
			continue
		if _s == ParseState.NUM:
			if _is_num_char(c):
				_num += String.chr(c)
				_pos += 1
			else:
				_commit_number(out)
			continue
		if _is_ws(c):
			_pos += 1
			continue
		if not _step(c, out):
			break
	_offset += _pos
	_buf = _buf.substr(_pos)
	_pos = 0
	_flush_say(out)
	return out


## End of stream. Returns Status: OK if the document closed, TRUNCATED if it
## ended mid-structure, ERROR if a syntax error was hit. Terminal — further
## feed() calls return no events.
func finish() -> int:
	_finished = true
	if _s == ParseState.DONE:
		_status = Status.OK
	elif _s == ParseState.ERR:
		_status = Status.ERROR
	else:
		_status = Status.TRUNCATED
	return _status


## The assembled value of the completed portion (Dictionary for a Turn).
func get_value() -> Variant:
	return _root


func get_status() -> int:
	return _status


func has_error() -> bool:
	return _s == ParseState.ERR


func get_error() -> String:
	return _error_msg


## Absolute character offset of the error in the stream, or -1.
func get_error_offset() -> int:
	return _error_off


# --- state machine -----------------------------------------------------------


func _step(c: int, out: Array[Dictionary]) -> bool:
	var ok := true
	if _s == ParseState.VALUE:
		ok = _step_value(c, out)
	elif _s == ParseState.OBJ_KEY or _s == ParseState.OBJ_KEY2:
		if c == _Q:
			_begin_str(true)
			_s = ParseState.STR
			_pos += 1
		elif c == _CB and _s == ParseState.OBJ_KEY:
			_close_container(out)
			_pos += 1
		else:
			_fail("expected a key or '}'", out)
	elif _s == ParseState.COLON:
		if c == _CL:
			_s = ParseState.VALUE
			_pos += 1
		else:
			_fail("expected ':'", out)
	elif _s == ParseState.OBJ_TAIL or _s == ParseState.ARR_TAIL:
		var closer := _CB if _s == ParseState.OBJ_TAIL else _CS
		var next_s := ParseState.OBJ_KEY2 if _s == ParseState.OBJ_TAIL else ParseState.VALUE
		if c == _CM:
			_s = next_s
			_pos += 1
		elif c == closer:
			_close_container(out)
			_pos += 1
		else:
			_fail("expected ',' or a closing bracket", out)
	elif _s == ParseState.DONE:
		_fail("data after end of document", out)
	return ok


func _step_value(c: int, out: Array[Dictionary]) -> bool:
	var ok := true
	if c == _OB:
		_push_obj(out)
		_s = ParseState.OBJ_KEY
		_pos += 1
	elif c == _OS:
		_push_arr()
		_s = ParseState.VALUE
		_pos += 1
	elif c == _Q:
		_begin_str(false)
		_s = ParseState.STR
		_pos += 1
	elif (
		c == _CS
		and not _stack.is_empty()
		and _stack.back()["arr"]
		and _stack.back()["val"].is_empty()
	):
		_close_container(out)
		_pos += 1
	elif _is_digit(c) or c == _MN:
		_s = ParseState.NUM
		_num = ""
	elif c == _T:
		ok = _lit("true", true, out)
	elif c == _F:
		ok = _lit("false", false, out)
	elif c == _N:
		ok = _lit("null", null, out)
	else:
		_fail("expected a value", out)
	return ok


func _lit(text: String, v: Variant, out: Array[Dictionary]) -> bool:
	var left := _buf.length() - _pos
	var part := _buf.substr(_pos, mini(left, text.length()))
	if not text.begins_with(part):
		_fail("invalid literal", out)
	elif left < text.length():
		return false
	else:
		_pos += text.length()
		_attach(v, out)
	return true


func _step_str(c: int, out: Array[Dictionary]) -> void:
	if _esc == 2:
		if not _is_hex(c):
			_fail("bad \\u escape", out)
		else:
			_hex += String.chr(c)
			_pos += 1
			if _hex.length() == 4:
				_emit_cp(_hex.hex_to_int())
				_hex = ""
				_esc = 0
	elif _esc == 1:
		_pos += 1
		if c == _U:
			_esc = 2
			_hex = ""
		else:
			if _high >= 0:
				_ap_str(String.chr(_REPL))
				_high = -1
			_esc = 0
			match c:
				_Q:
					_ap_str('"')
				_BS:
					_ap_str("\\")
				_FS:
					_ap_str("/")
				_B:
					_ap_str("\b")
				_F:
					_ap_str("\f")
				_N:
					_ap_str("\n")
				_R:
					_ap_str("\r")
				_T:
					_ap_str("\t")
				_:
					_fail("invalid escape", out)
	elif c == _BS:
		_esc = 1
		_pos += 1
	elif c == _Q:
		if _high >= 0:
			_ap_str(String.chr(_REPL))
			_high = -1
		_pos += 1
		_end_str(out)
	elif c < 0x20:
		_fail("unescaped control character in string", out)
	else:
		if _high >= 0:
			_ap_str(String.chr(_REPL))
			_high = -1
		_ap_str(String.chr(c))
		_pos += 1


func _emit_cp(code: int) -> void:
	if code >= 0xD800 and code <= 0xDBFF:
		if _high >= 0:
			_ap_str(String.chr(_REPL))
		_high = code
		return
	if code >= 0xDC00 and code <= 0xDFFF:
		if _high >= 0:
			_ap_str(String.chr(0x10000 + ((_high - 0xD800) << 10) + code - 0xDC00))
			_high = -1
		else:
			_ap_str(String.chr(_REPL))
		return
	if _high >= 0:
		_ap_str(String.chr(_REPL))
		_high = -1
	_ap_str(String.chr(code))


func _begin_str(is_key: bool) -> void:
	_str_acc = ""
	_say_pending = ""
	_str_key = is_key
	_str_say = false
	_say_idx = -1
	_esc = 0
	_hex = ""
	_high = -1
	if not is_key and not _stack.is_empty():
		var top: Dictionary = _stack.back()
		if not top["arr"] and top["role"] == ContainerRole.BEAT and top["key"] == "say":
			_str_say = true
			_say_idx = top["idx"]


func _end_str(out: Array[Dictionary]) -> void:
	if _str_key:
		_stack.back()["key"] = _str_acc
		_s = ParseState.COLON
		return
	if _str_say:
		_flush_say(out)
	_attach(_str_acc, out)


func _ap_str(s: String) -> void:
	_str_acc += s
	if _str_say:
		_say_pending += s


func _flush_say(out: Array[Dictionary]) -> void:
	if not _say_pending.is_empty():
		out.append({"type": "say_chunk", "index": _say_idx, "text": _say_pending})
		_say_pending = ""


func _push_obj(out: Array[Dictionary]) -> void:
	var role := ContainerRole.SUB
	var idx := -1
	if _stack.is_empty():
		role = ContainerRole.ROOT
	else:
		var p: Dictionary = _stack.back()
		if p["arr"] and p["role"] == ContainerRole.BEATS:
			role = ContainerRole.BEAT
			idx = p["n"]
			p["n"] += 1
	_stack.push_back({"arr": false, "role": role, "key": "", "val": {}, "idx": idx})
	if role == ContainerRole.BEAT:
		out.append({"type": "beat_start", "index": idx})


func _push_arr() -> void:
	var role := ContainerRole.GEN
	if not _stack.is_empty():
		var p: Dictionary = _stack.back()
		if not p["arr"] and p["role"] == ContainerRole.ROOT and p["key"] == "beats":
			role = ContainerRole.BEATS
	_stack.push_back({"arr": true, "role": role, "key": "", "val": [], "n": 0})


func _attach(v: Variant, out: Array[Dictionary]) -> void:
	if _stack.is_empty():
		_root = v
		_s = ParseState.DONE
		return
	var top: Dictionary = _stack.back()
	if top["arr"]:
		top["val"].append(v)
		_s = ParseState.ARR_TAIL
		if top["role"] == ContainerRole.BEATS:
			_fail("beats element must be an object", out)
		return
	top["val"][top["key"]] = v
	if top["role"] == ContainerRole.ROOT:
		out.append({"type": "field", "name": top["key"], "value": v})
	elif top["role"] == ContainerRole.BEAT:
		out.append({"type": "beat_field", "index": top["idx"], "name": top["key"], "value": v})
	_s = ParseState.OBJ_TAIL


func _close_container(out: Array[Dictionary]) -> void:
	var c: Dictionary = _stack.pop_back()
	if _stack.is_empty():
		_root = c["val"]
		_s = ParseState.DONE
		return
	var top: Dictionary = _stack.back()
	if top["arr"]:
		if top["role"] == ContainerRole.BEATS and c["role"] != ContainerRole.BEAT:
			_fail("beats element must be an object", out)
		top["val"].append(c["val"])
		_s = ParseState.ARR_TAIL
		return
	top["val"][top["key"]] = c["val"]
	if top["role"] == ContainerRole.ROOT:
		if top["key"] != "beats" or c["role"] != ContainerRole.BEATS:
			out.append({"type": "field", "name": top["key"], "value": c["val"]})
	elif top["role"] == ContainerRole.BEAT:
		out.append(
			{"type": "beat_field", "index": top["idx"], "name": top["key"], "value": c["val"]}
		)
	_s = ParseState.OBJ_TAIL


func _commit_number(out: Array[Dictionary]) -> void:
	if not _valid_number(_num):
		_fail("invalid number literal", out)
		return
	if _num.find(".") == -1 and _num.find("e") == -1 and _num.find("E") == -1:
		_attach(_num.to_int(), out)
		return
	_attach(_num.to_float(), out)


func _fail(msg: String, out: Array[Dictionary]) -> void:
	if _s != ParseState.ERR:
		_s = ParseState.ERR
		_error_msg = msg
		_error_off = _offset + _pos
		out.append({"type": "error", "message": msg, "offset": _error_off})


# --- character classes --------------------------------------------------------


static func _is_ws(c: int) -> bool:
	return c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D


static func _is_digit(c: int) -> bool:
	return c >= 0x30 and c <= 0x39


static func _is_digit19(c: int) -> bool:
	return c >= 0x31 and c <= 0x39


static func _is_num_char(c: int) -> bool:
	return _is_digit(c) or c == _MN or c == _PL or c == _DT or c == 0x65 or c == 0x45


static func _is_hex(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x46) or (c >= 0x61 and c <= 0x66)


static func _valid_number(t: String) -> bool:
	var i := 0
	var n := t.length()
	if i < n and t.unicode_at(i) == _MN:
		i += 1
	if i < n and t.unicode_at(i) == 0x30:
		i += 1
	elif i < n and _is_digit19(t.unicode_at(i)):
		while i < n and _is_digit(t.unicode_at(i)):
			i += 1
	else:
		return false
	if i < n and t.unicode_at(i) == _DT:
		i += 1
		if i >= n or not _is_digit(t.unicode_at(i)):
			return false
		while i < n and _is_digit(t.unicode_at(i)):
			i += 1
	if i < n and (t.unicode_at(i) == 0x65 or t.unicode_at(i) == 0x45):
		i += 1
		if i < n and (t.unicode_at(i) == _PL or t.unicode_at(i) == _MN):
			i += 1
		if i >= n or not _is_digit(t.unicode_at(i)):
			return false
		while i < n and _is_digit(t.unicode_at(i)):
			i += 1
	return i == n
