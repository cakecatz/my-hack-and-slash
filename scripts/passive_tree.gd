extends RefCounted
## Small passive tree. Nodes are bought with passive points (one per level) and
## are separate from the stat talents. Tag-gated nodes only help skills that
## carry the matching tag, so different main skills favour different paths.

const ROOT := "core"
const MAX_POINTS := 12

const NODES := [
	{"id": "core", "name": "EMBER CORE", "parent": "", "pos": Vector2(0, 0), "text": "The root. Three paths branch from here."},
	# Offense
	{"id": "off_dmg", "name": "FOCUSED STRIKES", "parent": "core", "pos": Vector2(-180, 74), "text": "Damage +8%", "damage": 1.08},
	{"id": "off_proj", "name": "SPLINTERED SHOT", "parent": "off_dmg", "pos": Vector2(-264, 152), "text": "Projectile skills deal +18% damage", "damage": 1.18, "tags": ["projectile"]},
	{"id": "off_proj2", "name": "EXTRA SPLINTER", "parent": "off_proj", "pos": Vector2(-324, 234), "text": "Projectiles +1", "projectiles": 1, "notable": true},
	{"id": "off_area", "name": "WIDE ARC", "parent": "off_dmg", "pos": Vector2(-112, 152), "text": "Area skills gain +15% area", "area": 1.15, "tags": ["area"]},
	{"id": "off_melee", "name": "HEAVY BLADE", "parent": "off_area", "pos": Vector2(-48, 234), "text": "Melee skills deal +20% damage", "damage": 1.2, "tags": ["melee"], "notable": true},
	# Defense
	{"id": "def_hp", "name": "TOUGHENED", "parent": "core", "pos": Vector2(0, 74), "text": "Maximum life +40", "health": 40},
	{"id": "def_armor", "name": "IRON SKIN", "parent": "def_hp", "pos": Vector2(-52, 152), "text": "Defense +5", "armor": 5},
	{"id": "def_hp2", "name": "UNBROKEN", "parent": "def_hp", "pos": Vector2(48, 152), "text": "Maximum life +80", "health": 80, "notable": true},
	{"id": "def_res", "name": "EMBER WARD", "parent": "def_armor", "pos": Vector2(-108, 234), "text": "Damage taken -6%", "incoming": 0.94},
	{"id": "def_dash", "name": "QUICK STEP", "parent": "def_hp2", "pos": Vector2(108, 234), "text": "Dodge cooldown -20%", "dash_cd": 0.8, "notable": true},
	{"id": "def_mana", "name": "AZURE WELL", "parent": "def_armor", "pos": Vector2(-190, 234), "text": "Maximum mana +60", "mana": 60, "notable": true},
	# Utility
	{"id": "util_move", "name": "FLEET FOOT", "parent": "core", "pos": Vector2(180, 74), "text": "Movement speed +6%", "move": 1.06},
	{"id": "util_heat", "name": "STOKED FLAME", "parent": "util_move", "pos": Vector2(112, 152), "text": "Heat gained +25%", "heat": 1.25},
	{"id": "util_burn", "name": "LINGERING EMBERS", "parent": "util_move", "pos": Vector2(264, 152), "text": "Burn damage +25%", "burn": 1.25},
	{"id": "util_leech", "name": "LIFEDRINK", "parent": "util_heat", "pos": Vector2(40, 234), "text": "Recover +1.5% life per hit", "leech": 0.015, "notable": true},
	{"id": "util_haste", "name": "RAPID STRIKES", "parent": "util_burn", "pos": Vector2(324, 234), "text": "Attack speed +8%", "interval": 0.92, "notable": true},
	{"id": "util_flow", "name": "EMBER FLOW", "parent": "util_heat", "pos": Vector2(188, 234), "text": "Mana regeneration +2.5/s", "regen": 2.5}
]

static func has(id: String) -> bool:
	return not def(id).is_empty()

static func def(id: String) -> Dictionary:
	for node in NODES:
		if node.id == id:
			return node
	return {}

static func node_ids() -> Array[String]:
	var ids: Array[String] = []
	for node in NODES:
		ids.append(node.id)
	return ids
