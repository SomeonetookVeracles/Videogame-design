class_name PlayerStateMachine
extends Node

## Finite state machine for player state management.
## Handles transitions and state-specific logic cleanly.
## Note: Combat (attack/parry) overlays movement and doesn't have its own state.

signal state_changed(from_state: State, to_state: State)

enum State {
	IDLE,
	RUN,
	JUMP,
	FALL,
	DASH,
	HURT,
	DEAD,
}

const STATE_NAMES: Dictionary = {
	State.IDLE: "idle",
	State.RUN: "run",
	State.JUMP: "jump",
	State.FALL: "fall",
	State.DASH: "dash",
	State.HURT: "hurt",
	State.DEAD: "dead",
}

var current_state: State = State.IDLE : set = _set_state
var previous_state: State = State.IDLE

var _locked: bool = false
var _lock_timer: float = 0.0


func _process(delta: float) -> void:
	if _locked:
		_lock_timer -= delta
		if _lock_timer <= 0.0:
			_locked = false


func _set_state(new_state: State) -> void:
	if new_state == current_state:
		return
	
	if _locked and new_state not in [State.DEAD, State.HURT]:
		return
	
	previous_state = current_state
	current_state = new_state
	state_changed.emit(previous_state, current_state)


func lock_state(duration: float) -> void:
	_locked = true
	_lock_timer = duration


func unlock_state() -> void:
	_locked = false
	_lock_timer = 0.0


func is_locked() -> bool:
	return _locked


func get_state_name() -> String:
	return STATE_NAMES.get(current_state, "unknown")


func is_grounded_state() -> bool:
	return current_state in [State.IDLE, State.RUN]


func is_airborne_state() -> bool:
	return current_state in [State.JUMP, State.FALL]


func can_move() -> bool:
	return current_state not in [State.HURT, State.DEAD]


func can_attack() -> bool:
	return current_state not in [State.HURT, State.DEAD]


func can_dash() -> bool:
	return current_state not in [State.DASH, State.HURT, State.DEAD]


func can_jump() -> bool:
	return current_state not in [State.HURT, State.DEAD]


func can_parry() -> bool:
	return current_state not in [State.HURT, State.DEAD]
