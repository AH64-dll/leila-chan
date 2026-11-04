extends Node
## Triggers — keyword/engine/clock triggers (docs/01 §5).
##
## P2.09 owns the engine-event detectors (input & window telemetry); this node
## is the single sink those events go to. Every detection is delivered to
## `handle_engine_event()` in real time, so the P2.08 engine can match it
## against `data/triggers.json` (once / repeatable / escalating, cooldowns,
## model-only = half strength) without the telemetry layer knowing about caps.
##
## Until P2.08 lands this seam records the events (bounded) and re-emits them,
## which is what the tests assert: every telemetry event is *consumed here*,
## not merely queued.

signal engine_event(event: Dictionary)  ## A telemetry event reached the trigger engine.

## The session's engine events, oldest first (bounded — trigger state, not a log).
var received_events: Array[Dictionary] = []


## The P2.09 contract: one normalized event, exactly as Telemetry emits it:
## {trigger, event, stage_min, line, data, seq, ts}. Detection is ungated;
## `stage_min` is the docs/05 gate the engine applies to its effect.
func handle_engine_event(event: Dictionary) -> void:
	var copy := event.duplicate(true)
	received_events.append(copy)
	while received_events.size() > 32:
		received_events.pop_front()
	engine_event.emit(copy)


## Last event of a kind, or {} (debug overlay / tests).
func last_event(kind: String) -> Dictionary:
	for i: int in range(received_events.size() - 1, -1, -1):
		var event: Dictionary = received_events[i]
		if str(event.get("event", "")) == kind:
			return event.duplicate(true)
	return {}


## Session boundary (`Director.reset()` / tests): per-session trigger state.
func clear_engine_events() -> void:
	received_events.clear()
