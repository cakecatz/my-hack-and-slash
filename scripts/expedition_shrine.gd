extends RefCounted
## Local to one expedition; never included in the character save.
const OFFERS := [
	{"name": "BERSERKER'S OATH", "benefit": "Normal attacks +25%", "cost": "Potion healing -50%", "hint": "Strike harder; rely on dodging.", "attack": 1.25, "potion": 0.5, "heat": 1.0, "incoming": 1.0, "health": 1.0},
	{"name": "EMBER PACT", "benefit": "Heat gained +50%", "cost": "Damage taken +15%", "hint": "Burst more often; take more risk.", "attack": 1.0, "potion": 1.0, "heat": 1.5, "incoming": 1.15, "health": 1.0},
	{"name": "MARK OF GREED", "benefit": "Guardian: +1 protected Rare", "cost": "Enemy life +25%", "hint": "A longer fight for extra gear.", "attack": 1.0, "potion": 1.0, "heat": 1.0, "incoming": 1.0, "health": 1.25}
]
var position := Vector2(340, 620)
var choice := -1
var reward_claimed := false

func reset() -> void:
	choice = -1
	reward_claimed = false

func multiplier(key: String, option: int = -2) -> float:
	if option == -2:
		option = choice
	return float(OFFERS[option][key]) if option >= 0 and option < OFFERS.size() else 1.0

func choose(option: int) -> bool:
	if choice >= 0 or option < 0 or option >= OFFERS.size():
		return false
	choice = option
	return true

func claim_reward() -> bool:
	if choice != 2 or reward_claimed:
		return false
	reward_claimed = true
	return true
