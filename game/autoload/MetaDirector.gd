extends Node
## MetaDirector — docs/05 meta/system events: what she may do outside the text
## box. P2.10 ships the first event, docs/05 §1.1 **M01 Refuse exit**: a window
## close request is held ONCE per session from the T10 row's stage gate upwards,
## she gets one line (the docs/05 §2 OPPORTUNITY that offers the model
## `refuse_exit`), and the second press always closes.
##
## The gate is read from data/triggers.json through `Triggers.stage_min_of()`,
## never copied: the T10 row and data/telemetry.json's `close_requested` entry
## already have to agree, and the intercept follows them.
##
## docs/05 §0 hard rules — the reason every request this node does not hold
## quits immediately:
##   1. closing works within ONE extra press. Taking over `auto_accept_quit` is
##      what makes an intercept possible at all; an unheld request calls the
##      quit on the same press, so the default path is still one press.
##   2. `Esc` is untouched: this node reads no input, and `ChatUI`'s pause path
##      is unchanged.
##   3. The quit goes through one injected Callable, so a scripted test can press
##      close without ending the test run.

signal close_held  ## The session's first close request was held (M01).
signal offer_changed  ## The `refuse_exit` offer opened or was consumed.

const CLOSE_TRIGGER := "T10"
const EXIT_OFFER := "refuse_exit"
## docs/05 §2, verbatim: the reason the action is available. Testing showed the
## model never picks a meta action on its own (0%), so the offer is the whole
## mechanism (docs/02 §2.4). The gates data holds the line ("prompts live in
## data", docs/07 §2); this constant is the documented fallback, like
## Telemetry's event lines.
const OPPORTUNITY_LINE := (
	"OPPORTUNITY (optional): The player just tried to close the window. "
	+ 'You may set action to "refuse_exit". If you do, your reply is the last thing '
	+ "they hear before the game decides."
)
## docs/05 §1.1 M01 "Gate: St 3" — only for a catalogue that lost its T10 row.
const CLOSE_GATE_FALLBACK := 3

## M01 is once per session; the flag is cleared by GameState.reset().
var _held := false
var _offer_open := false
var _refused := false
var _quit: Callable = Callable()


func _ready() -> void:
	if GameState != null and not GameState.state_reset.is_connected(reset_session):
		GameState.state_reset.connect(reset_session)
	_take_over_close()
	if get_tree() != null:
		_quit = Callable(get_tree(), "quit")


## docs/05 §1.1 M01: may THIS close request be held? Sets the state and queues
## the offer when it may. Pure with respect to the trigger engine: Telemetry's
## own close listener records the event and fires T10 in the same dispatch, and
## the row's `once` cap must not be what decides the first press.
func hold_close_requested() -> bool:
	if _held:
		return false  # the second press always closes (docs/05 §1.1 M01)
	if int(GameState.stage) < close_gate():
		return false
	_held = true
	_offer_open = true
	GameState.queue_event(_opportunity_line())
	close_held.emit()
	offer_changed.emit()
	return true


## docs/05 §2: the offer sentence, from the gates data (TurnSchema reads
## data/stage_gates.json) with the documented fallback, so a broken gates file
## still offers the action instead of silently dropping M01's line.
func _opportunity_line() -> String:
	var line := TurnSchema.opportunity_line(EXIT_OFFER)
	return line if not line.is_empty() else OPPORTUNITY_LINE


## docs/05 §1.1 M01's gate, read from the T10 row (docs/07 §2: data, not code).
func close_gate() -> int:
	if Triggers != null and Triggers.has_method("stage_min_of"):
		var gate := int(Triggers.stage_min_of(CLOSE_TRIGGER))
		if gate >= 0:
			return gate
	return CLOSE_GATE_FALLBACK


## docs/02 §2.4: meta actions are offered, never free. Empty unless a close was
## actually held. docs/05 §2 puts the reason on every turn with an offer, so the
## sentence is queued again here: the pending-event queue drains once per submit,
## and an offer that outlived its one line would leave the enum without a why.
## `_close_offer()` drops the copy waiting in the queue, so the sentence never
## rides a turn after the offer it explains.
func offers(stage: int) -> Array:
	if not _offer_open or stage < close_gate():
		return []
	GameState.queue_event(_opportunity_line())
	return [EXIT_OFFER]


## docs/02 §4 step 7 / docs/05 §2: the model used the offer. One close request
## buys one refusal and one line, so the offer is consumed here; the quit stays
## with the player's next close press (docs/05 §0 rule 1 — the game never ends
## the session on its own while they are reading).
func execute_after_text(action: String) -> void:
	if action != EXIT_OFFER:
		return
	_refused = true
	_close_offer()


## The F3 overlay and the tests read the whole event state in one call.
func state() -> Dictionary:
	return {
		"close_held": _held,
		"offer_open": _offer_open,
		"exit_refused": _refused,
		"gate": close_gate(),
	}


## A fresh session (`GameState.reset()`, or a test): M01 may be held again.
func reset_session() -> void:
	_held = false
	_refused = false
	_close_offer()


## Test seam (docs/05 §0 rule 3): `quit_callable` runs instead of the tree's
## quit, so a scripted close request never terminates the test run.
func set_quit_callable(quit_callable: Callable) -> void:
	_quit = quit_callable


func _take_over_close() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	if not tree.root.close_requested.is_connected(_on_close_requested):
		tree.root.close_requested.connect(_on_close_requested)
	# Only after the handler is connected: a window whose close nobody handles
	# would never close, which is the one thing docs/05 §0 forbids.
	tree.auto_accept_quit = false


func _on_close_requested() -> void:
	# Telemetry's listener may run before or after this one; the decision does
	# not depend on the order, only on this node's own once-per-session flag.
	if hold_close_requested():
		return
	_request_quit()


func _request_quit() -> void:
	if _quit.is_valid():
		_quit.call()
		return
	var tree := get_tree()
	if tree != null:
		tree.quit()


## Consumes the offer. The queued copy of the docs/05 §2 sentence goes with it:
## `offers()` queues the line for the NEXT submit, so a refusal would otherwise
## leave one turn promising an action the schema's enum no longer carries, and a
## `reset_session()` would carry it into the new session.
func _close_offer() -> void:
	if not _offer_open:
		return
	_offer_open = false
	GameState.pending_events.erase(_opportunity_line())
	offer_changed.emit()
