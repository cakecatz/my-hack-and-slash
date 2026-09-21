extends RefCounted
## Optional encounter state is local to an expedition; rewards are persistent.

enum State { SEALED, ACTIVE, COMPLETE }
const LOCATIONS := [Vector2(600, 1240), Vector2(1190, 180), Vector2(1770, 1250)]
const GUARD_COUNT := 4
var state := State.SEALED
var position := Vector2.ZERO
var remaining := 0
var reward_slot := "weapon"

func reset() -> void:
	state = State.SEALED
	position = LOCATIONS.pick_random()
	remaining = 0
	reward_slot = "weapon"

func start(slot: String) -> bool:
	if state != State.SEALED or not slot in ["weapon", "armor", "charm"]:
		return false
	reward_slot = slot
	remaining = GUARD_COUNT
	state = State.ACTIVE
	return true

func guard_defeated() -> bool:
	if state != State.ACTIVE or remaining <= 0:
		return false
	remaining -= 1
	if remaining == 0:
		state = State.COMPLETE
		return true
	return false
