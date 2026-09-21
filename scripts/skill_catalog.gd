extends RefCounted
## Combat and card previews share this catalog, including rank scaling.

const MAX_LEVEL := 10
const SKILLS := [
	{"name": "CLEAVE", "tags": "MELEE / ARC / BURST", "role": "Punish a guardian's opening.", "flavor": "A blade tempered in the last campfire.", "detail": "Sweeps a forward arc. Enemies behind you are safe.", "base": 1.4, "reach": 106.0, "growth": 2.0},
	{"name": "NOVA", "tags": "MELEE / AREA / CLEAR", "role": "Surround yourself. Cut a way out.", "flavor": "The flame refuses to be surrounded.", "detail": "Hits all nearby enemies, including those behind you.", "base": 0.85, "reach": 135.0, "growth": 3.0},
	{"name": "LANCE", "tags": "RANGED / LINE / PIERCE", "role": "Line up enemies at a safe distance.", "flavor": "A splinter of dawn through the ash.", "detail": "Pierces every enemy in a narrow forward line.", "base": 1.05, "reach": 390.0, "growth": 8.0}
]
const SUPPORTS := [
	{"name": "POWER", "tags": "SUPPORT / DAMAGE", "role": "Heavy blows. Stronger burst windows.", "flavor": "Feed the flame. Make each strike count.", "detail": "Multiplies normal attack damage. No speed penalty.", "growth": "+2 percentage points of damage per level."},
	{"name": "ECHO", "tags": "SUPPORT / SPEED", "role": "Trade hit damage for faster attacks.", "flavor": "The steel remembers its last strike.", "detail": "Shortens attack intervals, but each hit deals 15% less.", "growth": "Attack interval reduction grows 1.5 points per level."},
	{"name": "SIPHON", "tags": "SUPPORT / RECOVERY", "role": "Stay in the fight by landing hits.", "flavor": "From dying embers, a heartbeat returns.", "detail": "Heals once per attack that connects. Deals 10% less.", "growth": "+0.25% of maximum life recovered per level."}
]

static func xp_needed(level: int) -> int:
	return 100 + (level - 1) * 60

static func skill_multiplier(index: int, level: int) -> float:
	return SKILLS[index].base * (1.0 + (level - 1) * 0.06)

static func reach(index: int, level: int) -> float:
	return SKILLS[index].reach + SKILLS[index].growth * (level - 1)

static func support_damage(index: int, level: int) -> float:
	return 1.25 + (level - 1) * 0.02 if index == 0 else (0.85 if index == 1 else 0.9)

static func interval_multiplier(index: int, level: int) -> float:
	return 0.65 - (level - 1) * 0.015 if index == 1 else 1.0

static func recovery(index: int, level: int) -> float:
	return 0.025 + (level - 1) * 0.0025 if index == 2 else 0.0

static func support_effect(index: int, level: int) -> String:
	match index:
		0: return "+%.0f%% attack damage" % ((support_damage(index, level) - 1) * 100)
		1: return "%.1f%% shorter attack interval" % ((1 - interval_multiplier(index, level)) * 100)
		_: return "Recover %.2f%% life on hit" % (recovery(index, level) * 100)
