extends RefCounted
## One skill pool. Attack skills (indices 0-3) drive the basic attack slot and
## receive supports; active skills (4-7) are cooldown abilities. Any skill can be
## assigned to an active slot, and attack skills can also sit in the basic slot.

const Loc = preload("res://scripts/loc.gd")
const MAX_LEVEL := 10
const MAX_SUPPORTS := 5
# Level required to unlock active slots 1-4.
const SLOT_LEVELS := [1, 3, 5, 7]

const SKILLS := [
	{"id": "cleave", "name": "CLEAVE", "type": "attack", "cost": 15, "tags": ["attack", "melee", "area", "physical"], "tag_text": "MELEE / ARC / BURST", "role": "Punish a guardian's opening.", "flavor": "A blade tempered in the last campfire.", "detail": "Sweeps a forward arc. Enemies behind you are safe.", "base": 1.4, "reach": 106.0, "growth": 2.0, "cooldown": 5.0},
	{"id": "nova", "name": "NOVA", "type": "attack", "cost": 18, "tags": ["attack", "melee", "area", "physical"], "tag_text": "MELEE / AREA / CLEAR", "role": "Surround yourself. Cut a way out.", "flavor": "The flame refuses to be surrounded.", "detail": "Hits all nearby enemies, including those behind you.", "base": 0.85, "reach": 135.0, "growth": 3.0, "cooldown": 6.0},
	{"id": "lance", "name": "LANCE", "type": "attack", "cost": 15, "tags": ["attack", "pierce", "physical"], "tag_text": "RANGED / LINE / PIERCE", "role": "Line up enemies at a safe distance.", "flavor": "A splinter of dawn through the ash.", "detail": "Pierces every enemy in a narrow forward line.", "base": 1.05, "reach": 390.0, "growth": 8.0, "cooldown": 5.0},
	{"id": "bolt", "name": "EMBER BOLT", "type": "attack", "cost": 15, "tags": ["attack", "projectile", "fire"], "tag_text": "RANGED / PROJECTILE / FIRE", "role": "Fire bolts down a safe lane.", "flavor": "A spark that refuses to die.", "detail": "Fires a bolt of embers. Projectile supports change how it flies.", "base": 1.15, "reach": 420.0, "growth": 6.0, "cooldown": 5.0},
	{"id": "ember_lance", "name": "EMBER LANCE", "type": "active", "cost": 20, "tags": ["spell", "projectile", "fire"], "text": "Pierce a line of enemies with a burning spear.", "cooldown": 5.0, "damage": 1.8, "range": 560.0, "pierce": 99, "speed": 720.0, "burn": 0.6},
	{"id": "cinder_field", "name": "CINDER FIELD", "type": "active", "cost": 35, "tags": ["spell", "area", "fire"], "text": "Scorch the ground, burning and slowing enemies inside.", "cooldown": 10.0, "damage": 0.7, "radius": 130.0, "range": 420.0, "duration": 3.0, "tick": 0.5, "burn": 0.35, "slow": 0.35},
	{"id": "barrier", "name": "GUARDIAN BARRIER", "type": "active", "cost": 40, "tags": ["spell", "guard"], "text": "Gain a shield that absorbs damage for 5 seconds.", "cooldown": 16.0, "shield": 0.35, "duration": 5.0},
	{"id": "rush", "name": "BLOOD RUSH", "type": "active", "cost": 45, "tags": ["spell", "buff"], "text": "Gain attack speed and movement speed for 5 seconds.", "cooldown": 18.0, "haste": 0.4, "move": 0.3, "duration": 5.0}
]

const AURAS := [
	{"id": "ash", "name": "ASH AURA", "text": "Damage +15%", "reserve": 20, "damage": 1.15},
	{"id": "ward", "name": "WARD AURA", "text": "Defense +8", "reserve": 20, "armor": 8},
	{"id": "flow", "name": "EMBER FLOW", "text": "Mana regeneration +3/s", "reserve": 15, "regen": 3.0},
	{"id": "fleet", "name": "FLEET AURA", "text": "Movement speed +8%", "reserve": 15, "move": 1.08}
]

const SUPPORTS := [
	{"id": "multishot", "name": "MULTISHOT", "requires": ["projectile"], "requires_text": "PROJECTILE", "text": "Projectiles +2, each 40% less damage", "more_damage": 0.6, "projectiles": 2},
	{"id": "pierce", "name": "PIERCE", "requires": ["projectile"], "requires_text": "PROJECTILE", "text": "Projectiles pierce 2 extra enemies", "more_damage": 0.85, "pierce": 2},
	{"id": "chain", "name": "CHAIN", "requires": ["projectile"], "requires_text": "PROJECTILE", "text": "Hits chain to 2 nearby enemies", "more_damage": 0.8, "chain": 2},
	{"id": "wider", "name": "WIDER", "requires": ["area"], "requires_text": "AREA", "text": "Area +35%, 10% less damage", "more_damage": 0.9, "area": 1.35},
	{"id": "concentrated", "name": "CONCENTRATED", "requires": ["area"], "requires_text": "AREA", "text": "Area -30%, 25% more damage", "more_damage": 1.25, "area": 0.7},
	{"id": "power", "name": "POWER", "requires": ["attack", "spell"], "requires_text": "ATTACK / SPELL", "text": "30% more damage, 10% slower attacks", "more_damage": 1.3, "interval": 1.1},
	{"id": "haste", "name": "HASTE", "requires": ["attack", "spell"], "requires_text": "ATTACK / SPELL", "text": "25% faster attacks, 10% less damage", "more_damage": 0.9, "interval": 0.8},
	{"id": "ignite", "name": "IGNITE", "requires": ["physical", "fire"], "requires_text": "PHYSICAL / FIRE", "text": "Hits burn for 20% damage/sec for 2s", "more_damage": 0.95, "burn": 1.0},
	{"id": "leech", "name": "LEECH", "requires": ["attack", "spell"], "requires_text": "ATTACK / SPELL", "text": "Recover 2% of maximum life per hit", "more_damage": 0.95, "leech": 0.02},
	{"id": "charged", "name": "CHARGED", "requires": ["attack", "spell"], "requires_text": "ATTACK / SPELL", "text": "+4 heat per hit", "more_damage": 0.95, "heat": 4}
]

static func xp_needed(level: int) -> int:
	return 100 + (level - 1) * 60

static func count() -> int:
	return SKILLS.size()

static func attack_count() -> int:
	var total := 0
	for skill in SKILLS:
		if skill.type == "attack":
			total += 1
	return total

static func def(id: String) -> Dictionary:
	for skill in SKILLS:
		if skill.id == id:
			return skill
	return {}

static func index_of(id: String) -> int:
	for i in range(SKILLS.size()):
		if SKILLS[i].id == id:
			return i
	return -1

static func is_attack(index: int) -> bool:
	return index >= 0 and index < SKILLS.size() and SKILLS[index].type == "attack"

static func id_at(index: int) -> String:
	return SKILLS[index].id if index >= 0 and index < SKILLS.size() else ""

static func has_id(id: String) -> bool:
	return not def(id).is_empty()

static func level_multiplier(level: int) -> float:
	return 1.0 + (level - 1) * 0.06

static func skill_multiplier(index: int, level: int) -> float:
	return SKILLS[index].base * level_multiplier(level)

static func active_damage(index: int, level: int) -> float:
	return float(SKILLS[index].get("damage", 0.0)) * level_multiplier(level)

static func reach(index: int, level: int) -> float:
	return SKILLS[index].reach + SKILLS[index].growth * (level - 1)

static func support_slots(level: int) -> int:
	var slots := 2
	if level >= 4:
		slots += 1
	if level >= 7:
		slots += 1
	if level >= 10:
		slots += 1
	return slots

static func support_def(id: String) -> Dictionary:
	for support in SUPPORTS:
		if support.id == id:
			return support
	return {}

static func has_support(id: String) -> bool:
	return not support_def(id).is_empty()

static func aura_def(id: String) -> Dictionary:
	for aura in AURAS:
		if aura.id == id:
			return aura
	return {}

static func has_aura(id: String) -> bool:
	return not aura_def(id).is_empty()

static func support_applies(skill_index: int, id: String) -> bool:
	if skill_index < 0 or skill_index >= SKILLS.size():
		return false
	var skill: Dictionary = SKILLS[skill_index]
	var support := support_def(id)
	if support.is_empty():
		return false
	for tag in support.requires:
		if tag in skill.tags:
			return true
	return false
