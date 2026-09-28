extends RefCounted
## Persistent character and equipment. Expedition state is deliberately separate.

const Mods = preload("res://scripts/item_mods.gd")
const Skills = preload("res://scripts/skill_catalog.gd")
const PassiveTree = preload("res://scripts/passive_tree.gd")

const Effects = preload("res://scripts/item_effects.gd")

const SAVE_PATH := "user://character.json"
const RARITIES := ["Common", "Magic", "Rare", "Relic"]
const SLOTS := ["weapon", "armor", "charm"]
var inventory: Array[Dictionary] = []
var stash: Array[Dictionary] = []
var equipment: Dictionary = {
	"weapon": {"name": "Worn sword", "slot": "weapon", "rarity": 0, "tier": 1, "attack": 10, "health": 0, "armor": 0, "haste": 0},
	"armor": {"name": "Traveler coat", "slot": "armor", "rarity": 0, "tier": 1, "attack": 0, "health": 10, "armor": 1, "haste": 0},
	"charm": {}
}
var level := 1
var xp := 0
var unlocked := 1
var save_error := ""
var campaign := 0
var depth := 1
var abyss_complete := false
var embers := 0
var stance := 0
# Support links per slot: index 0 = basic attack, 1-4 = active keys 1-4.
# Each entry is {"id": String, "tier": int}. A support may be used only once per character.
var links: Array = [[], [], [], [], []]
var skill_levels: Array[int] = [1, 1, 1, 1, 1, 1, 1, 1]
var skill_xp: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var talents: Array[int] = [0, 0, 0, 0]
var play_seconds := 0.0
# 0: manual, 1: auto pickup, 2: auto pickup and salvage Common drops.
var loot_mode := 1
var relic_hunts: Array[int] = [0, 0, 0]
# Three saved loadouts: {"name", "stance", "supports", "talents"}. Empty dicts are unused slots.
var builds: Array[Dictionary] = [{}, {}, {}]
# Passive tree node ids. Separate from the stat talents; one point per level.
var passives: Array[String] = []
# Skill assigned to each active slot (keys 1-4). Empty string means an empty slot.
var active_slots: Array[String] = ["ember_lance", "cinder_field", "barrier", "rush"]
# Enabled persistent auras. Each reserves spirit from a level-based pool.
var auras: Array[String] = []
const LOOT_MODES := ["MANUAL", "AUTO", "AUTO + SCRAP"]
const STANCES := ["CLEAVE", "NOVA", "LANCE", "EMBER BOLT"]

func reset() -> void:
	## Restore a fresh character. Used by "New Game" without touching the save format.
	inventory.clear()
	stash.clear()
	equipment = {
		"weapon": {"name": "Worn sword", "slot": "weapon", "rarity": 0, "tier": 1, "attack": 10, "health": 0, "armor": 0, "haste": 0},
		"armor": {"name": "Traveler coat", "slot": "armor", "rarity": 0, "tier": 1, "attack": 0, "health": 10, "armor": 1, "haste": 0},
		"charm": {}
	}
	level = 1
	xp = 0
	unlocked = 1
	campaign = 0
	depth = 1
	abyss_complete = false
	embers = 0
	stance = 0
	links = [[], [], [], [], []]
	skill_levels.assign([1, 1, 1, 1, 1, 1, 1, 1])
	skill_xp.assign([0, 0, 0, 0, 0, 0, 0, 0])
	talents.assign([0, 0, 0, 0])
	play_seconds = 0.0
	loot_mode = 1
	relic_hunts.assign([0, 0, 0])
	builds = [{}, {}, {}]
	passives.clear()
	active_slots.assign(["ember_lance", "cinder_field", "barrier", "rush"])
	auras.clear()
	save_error = ""

func support_slots() -> int:
	return Skills.support_slots(skill_levels[stance])

func slot_skill_id(slot: int) -> String:
	if slot <= 0:
		return Skills.id_at(stance)
	var key := slot - 1
	return active_slots[key] if key >= 0 and key < active_slots.size() else ""

func slot_support_capacity(slot: int) -> int:
	var index := Skills.index_of(slot_skill_id(slot))
	if index < 0:
		return 0
	return Skills.support_slots(skill_levels[index])

func slot_link_ids(slot: int) -> Array[String]:
	var ids: Array[String] = []
	if slot < 0 or slot >= links.size():
		return ids
	for entry in links[slot]:
		ids.append(str(entry.get("id", "")))
	return ids

func has_support(id: String) -> bool:
	for entries in links:
		for entry in entries:
			if str(entry.get("id", "")) == id:
				return true
	return false

func support_tier(slot: int, id: String) -> int:
	if slot < 0 or slot >= links.size():
		return 0
	for entry in links[slot]:
		if str(entry.get("id", "")) == id:
			return int(entry.get("tier", 3))
	return 0

func tier_factor(tier: int) -> float:
	return 1.0 + (3 - clampi(tier, 1, 3)) * 0.25

func link_upgrade_cost(tier: int) -> int:
	# Cost to raise a link one tier (3 -> 2 -> 1). -1 means already strongest.
	if tier <= 1:
		return -1
	return 30 * (4 - tier)

func add_support(slot: int, id: String) -> bool:
	if slot < 0 or slot >= links.size():
		return false
	var index := Skills.index_of(slot_skill_id(slot))
	if index < 0 or not Skills.support_applies(index, id):
		return false
	if has_support(id) or links[slot].size() >= slot_support_capacity(slot):
		return false
	links[slot].append({"id": id, "tier": 3})
	return true

func remove_support(slot: int, id: String) -> bool:
	if slot < 0 or slot >= links.size():
		return false
	for i in range(links[slot].size() - 1, -1, -1):
		if str(links[slot][i].get("id", "")) == id:
			links[slot].remove_at(i)
			return true
	return false

func upgrade_support(slot: int, id: String) -> bool:
	if slot < 0 or slot >= links.size():
		return false
	for entry in links[slot]:
		if str(entry.get("id", "")) != id:
			continue
		var cost := link_upgrade_cost(int(entry.get("tier", 3)))
		if cost < 0 or embers < cost:
			return false
		embers -= cost
		entry.tier = int(entry.get("tier", 3)) - 1
		return true
	return false

func prune_slot(slot: int) -> void:
	if slot < 0 or slot >= links.size():
		return
	var index := Skills.index_of(slot_skill_id(slot))
	var kept: Array = []
	for entry in links[slot]:
		if index >= 0 and Skills.support_applies(index, str(entry.get("id", ""))):
			kept.append(entry)
	links[slot] = kept

func set_slot_links(slot: int, ids: Array) -> void:
	if slot < 0 or slot >= links.size():
		return
	var entries: Array = []
	for id in ids:
		entries.append({"id": str(id), "tier": 3})
	links[slot] = entries

func spirit_max() -> int:
	return 30 + (level - 1) * 2

func reserved_spirit() -> int:
	var total := 0
	for id in auras:
		total += int(Skills.aura_def(id).get("reserve", 0))
	return total

func has_aura(id: String) -> bool:
	return id in auras

func toggle_aura(id: String) -> bool:
	if not Skills.has_aura(id):
		return false
	if id in auras:
		auras.erase(id)
		return true
	if reserved_spirit() + int(Skills.aura_def(id).get("reserve", 0)) > spirit_max():
		return false
	auras.append(id)
	return true

func aura_value(key: String) -> float:
	var total := 0.0
	for id in auras:
		total += float(Skills.aura_def(id).get(key, 0.0))
	return total

func aura_multiplier(key: String) -> float:
	var mult := 1.0
	for id in auras:
		mult *= float(Skills.aura_def(id).get(key, 1.0))
	return mult

func set_stance(index: int) -> bool:
	if index < 0 or index >= Skills.SKILLS.size():
		return false
	stance = index
	prune_slot(0)
	return true

func save_build(slot: int) -> bool:
	if slot < 0 or slot >= builds.size():
		return false
	builds[slot] = {"name": STANCES[stance], "stance": stance, "links": links.duplicate(true), "talents": talents.duplicate(), "active_slots": active_slots.duplicate(), "auras": auras.duplicate()}
	return true

func load_build(slot: int) -> bool:
	if slot < 0 or slot >= builds.size() or builds[slot].is_empty():
		return false
	var entry: Dictionary = builds[slot]
	set_stance(int(entry.stance))
	talents.assign(entry.talents)
	active_slots.assign(["", "", "", ""])
	if entry.has("active_slots"):
		for i in range(mini(4, entry.active_slots.size())):
			var id := str(entry.active_slots[i])
			if id.is_empty() or not Skills.has_id(id) or id == basic_id() or id in active_slots:
				continue
			active_slots[i] = id
	links = [[], [], [], [], []]
	if entry.has("links"):
		var used: Array[String] = []
		for link_slot in range(mini(5, entry.links.size())):
			var index := Skills.index_of(slot_skill_id(link_slot))
			var kept: Array = []
			for item in entry.links[link_slot]:
				var id := str(item.get("id", ""))
				if index < 0 or not Skills.support_applies(index, id) or id in used or kept.size() >= slot_support_capacity(link_slot):
					continue
				kept.append({"id": id, "tier": clampi(int(item.get("tier", 3)), 1, 3)})
				used.append(id)
			links[link_slot] = kept
	auras.clear()
	if entry.has("auras"):
		for value in entry.auras:
			var aura_id := str(value)
			if Skills.has_aura(aura_id) and not (aura_id in auras) and reserved_spirit() + int(Skills.aura_def(aura_id).get("reserve", 0)) <= spirit_max():
				auras.append(aura_id)
	return true

func build_summary(slot: int) -> String:
	if slot < 0 or slot >= builds.size() or builds[slot].is_empty():
		return ""
	var entry: Dictionary = builds[slot]
	var basic := 0
	if entry.get("links") is Array and entry.links.size() > 0 and entry.links[0] is Array:
		basic = entry.links[0].size()
	return "%s / %d" % [STANCES[int(entry.stance)], basic]

func passive_points() -> int:
	return mini(level - 1, PassiveTree.MAX_POINTS) - passives.size()

func has_passive(id: String) -> bool:
	return id == PassiveTree.ROOT or id in passives

func can_allocate_passive(id: String) -> bool:
	if id == PassiveTree.ROOT or has_passive(id) or passive_points() <= 0 or not PassiveTree.has(id):
		return false
	return has_passive(PassiveTree.def(id).parent)

func allocate_passive(id: String) -> bool:
	if not can_allocate_passive(id):
		return false
	passives.append(id)
	return true

func can_refund_passive(id: String) -> bool:
	if id == PassiveTree.ROOT or not has_passive(id):
		return false
	# A node can only be refunded when nothing downstream depends on it.
	for other in passives:
		if PassiveTree.def(other).parent == id:
			return false
	return true

func refund_passive(id: String) -> bool:
	if not can_refund_passive(id):
		return false
	passives.erase(id)
	return true

func reset_passives() -> void:
	passives.clear()

func move_speed_multiplier() -> float:
	var mult := 1.0
	for id in passives:
		mult *= float(PassiveTree.def(id).get("move", 1.0))
	mult *= aura_multiplier("move")
	return mult

func incoming_multiplier() -> float:
	var mult := 1.0
	for id in passives:
		mult *= float(PassiveTree.def(id).get("incoming", 1.0))
	return mult

func dash_cooldown_multiplier() -> float:
	var mult := 1.0
	for id in passives:
		mult *= float(PassiveTree.def(id).get("dash_cd", 1.0))
	return mult

func ability_unlocked(index: int) -> bool:
	return index >= 0 and index < Skills.SLOT_LEVELS.size() and level >= int(Skills.SLOT_LEVELS[index])

func unlocked_abilities() -> int:
	var count := 0
	for i in range(Skills.SLOT_LEVELS.size()):
		if ability_unlocked(i):
			count += 1
	return count

func basic_id() -> String:
	return Skills.id_at(stance)

func active_skill(slot: int) -> String:
	if slot < 0 or slot >= active_slots.size():
		return ""
	return active_slots[slot]

func assign_active(slot: int, id: String) -> bool:
	if slot < 0 or slot >= active_slots.size() or not ability_unlocked(slot) or not Skills.has_id(id):
		return false
	if id == basic_id() or id in active_slots:
		return false
	active_slots[slot] = id
	prune_slot(slot + 1)
	return true

func clear_active(slot: int) -> bool:
	if slot < 0 or slot >= active_slots.size():
		return false
	active_slots[slot] = ""
	prune_slot(slot + 1)
	return true

func assign_basic(id: String) -> bool:
	var index := Skills.index_of(id)
	if not Skills.is_attack(index) or id in active_slots:
		return false
	return set_stance(index)

func passive_global_multiplier() -> float:
	## Only untagged damage passives help active abilities; tag nodes target the main skill.
	var mult := 1.0
	for id in passives:
		var node := PassiveTree.def(id)
		if not node.get("tags", []).is_empty():
			continue
		mult *= float(node.get("damage", 1.0))
	return mult

func equipped_skill_indices() -> Array[int]:
	var indices: Array[int] = [stance]
	for i in range(active_slots.size()):
		var index := Skills.index_of(active_slots[i])
		if index >= 0 and not (index in indices):
			indices.append(index)
	return indices

func gain_mastery(amount: int) -> Array[String]:
	var gained: Array[String] = []
	if amount <= 0:
		return gained
	# Every equipped slot trains, so active skills level by being carried into fights.
	for index in equipped_skill_indices():
		if skill_levels[index] >= Skills.MAX_LEVEL:
			continue
		var old_level := skill_levels[index]
		skill_xp[index] += amount
		while skill_levels[index] < Skills.MAX_LEVEL and skill_xp[index] >= Skills.xp_needed(skill_levels[index]):
			skill_xp[index] -= Skills.xp_needed(skill_levels[index])
			skill_levels[index] += 1
		if skill_levels[index] == Skills.MAX_LEVEL:
			skill_xp[index] = 0
		if skill_levels[index] > old_level:
			gained.append("%s Lv.%d" % [Skills.SKILLS[index].name, skill_levels[index]])
	return gained

func effect_stack(slot: int, skill_index: int, include_supports: bool) -> Dictionary:
	var more := 1.0
	var interval_mul := 1.0
	var area_mul := 1.0
	var projectiles := 0
	var pierce := 0
	var chain := 0
	var burn_enabled := 0.0
	var burn_mult := 1.0
	var leech := 0.0
	var heat := 0.0
	var heat_mult := 1.0
	if include_supports and slot >= 0 and slot < links.size():
		for entry in links[slot]:
			var id := str(entry.get("id", ""))
			if not Skills.support_applies(skill_index, id):
				continue
			var support := Skills.support_def(id)
			var factor := tier_factor(int(entry.get("tier", 3)))
			more *= 1.0 + (float(support.get("more_damage", 1.0)) - 1.0) * factor
			interval_mul *= 1.0 + (float(support.get("interval", 1.0)) - 1.0) * factor
			area_mul *= 1.0 + (float(support.get("area", 1.0)) - 1.0) * factor
			projectiles += int(support.get("projectiles", 0))
			pierce += int(support.get("pierce", 0))
			chain += int(support.get("chain", 0))
			burn_enabled = maxf(burn_enabled, float(support.get("burn", 0.0)))
			leech = maxf(leech, float(support.get("leech", 0.0)) * factor)
			heat += float(support.get("heat", 0.0)) * factor
	# Passives apply to any skill, but tag-gated nodes only help matching skills.
	var skill: Dictionary = Skills.SKILLS[skill_index]
	for id in passives:
		var node := PassiveTree.def(id)
		if node.is_empty():
			continue
		var node_tags: Array = node.get("tags", [])
		var applies := node_tags.is_empty()
		for tag in node_tags:
			if tag in skill.tags:
				applies = true
		if not applies:
			continue
		more *= float(node.get("damage", 1.0))
		interval_mul *= float(node.get("interval", 1.0))
		area_mul *= float(node.get("area", 1.0))
		projectiles += int(node.get("projectiles", 0))
		pierce += int(node.get("pierce", 0))
		burn_mult *= float(node.get("burn", 1.0))
		leech += float(node.get("leech", 0.0))
		heat_mult *= float(node.get("heat", 1.0))
	# Persistent auras are always on while reserved.
	more *= aura_multiplier("damage")
	return {
		"more": more, "interval": interval_mul, "area": area_mul,
		"projectiles": projectiles, "pierce": pierce, "chain": chain,
		"burn": burn_enabled * burn_mult, "leech": leech,
		"heat": heat, "heat_mult": heat_mult
	}

func slot_combat(slot: int) -> Dictionary:
	var index := Skills.index_of(slot_skill_id(slot))
	if index < 0:
		return {"damage": 0.0, "interval": 0.4, "reach": 0.0, "area": 1.0, "projectiles": 0, "pierce": 0, "chain": 0, "burn": 0.0, "leech": 0.0, "heat": 0.0, "heat_mult": 1.0}
	var base := stats()
	var stack := effect_stack(slot, index, true)
	var skill: Dictionary = Skills.SKILLS[index]
	var damage := 0.0
	var reach := 0.0
	var interval := 0.0
	if Skills.is_attack(index):
		var level: int = skill_levels[index]
		damage = base.attack * Skills.skill_multiplier(index, level) * float(stack.more) * (1 + rune_bonus(index))
		reach = Skills.reach(index, level) * float(stack.area)
		interval = 0.4 / (1.0 + base.haste / 100.0) * float(stack.interval)
	else:
		damage = base.attack * Skills.active_damage(index, skill_levels[index]) * float(stack.more)
		reach = float(skill.get("range", 400.0)) * float(stack.area)
		interval = float(skill.get("cooldown", 1.0))
	return {
		"damage": damage, "interval": interval, "reach": reach, "area": stack.area,
		"projectiles": stack.projectiles, "pierce": stack.pierce, "chain": stack.chain,
		"burn": stack.burn, "leech": stack.leech, "heat": stack.heat, "heat_mult": stack.heat_mult
	}

func combat_stats(skill_index: int = -1, next_skill: bool = false) -> Dictionary:
	var active := stance if skill_index < 0 else skill_index
	var base := stats()
	# Supports belong to a slot; a candidate skill previews without them.
	var stack := effect_stack(0 if active == stance else -1, active, active == stance)
	var skill: Dictionary = Skills.SKILLS[active]
	var damage := 0.0
	var reach := 0.0
	var interval := 0.0
	if Skills.is_attack(active):
		var level := mini(Skills.MAX_LEVEL, skill_levels[active] + (1 if next_skill else 0))
		damage = base.attack * Skills.skill_multiplier(active, level) * float(stack.more) * (1 + rune_bonus(active))
		reach = Skills.reach(active, level) * float(stack.area)
		interval = 0.4 / (1.0 + base.haste / 100.0) * float(stack.interval)
	else:
		damage = base.attack * Skills.active_damage(active, mini(Skills.MAX_LEVEL, skill_levels[active] + (1 if next_skill else 0))) * float(stack.more)
		reach = float(skill.get("range", 400.0)) * float(stack.area)
		interval = float(skill.get("cooldown", 1.0))
	return {
		"damage": damage, "interval": interval, "reach": reach, "area": stack.area,
		"projectiles": stack.projectiles, "pierce": stack.pierce, "chain": stack.chain,
		"burn": stack.burn, "leech": stack.leech, "heat": stack.heat, "heat_mult": stack.heat_mult
	}

func talent_points() -> int:
	return mini(level - 1, 18) - talents[0] - talents[1] - talents[2] - talents[3]

func spend_talent(index: int) -> bool:
	if index < 0 or index > 3 or talent_points() <= 0 or talents[index] >= 6:
		return false
	talents[index] += 1
	return true

func salvage(index: int) -> bool:
	if index < 0 or index >= inventory.size():
		return false
	if inventory[index].get("favorite", false):
		return false
	embers += salvage_value(inventory[index])
	inventory.remove_at(index)
	return true

func salvage_value(item: Dictionary) -> int:
	return (int(item.rarity) + 1) * int(item.tier)

func common_salvage_count() -> int:
	var count := 0
	for item in inventory:
		if item.rarity == 0 and not item.get("favorite", false):
			count += 1
	return count

func salvage_common() -> int:
	var count := 0
	for i in range(inventory.size() - 1, -1, -1):
		if inventory[i].rarity == 0 and salvage(i):
			count += 1
	return count

func collect_item(item: Dictionary, auto_scrap: bool = false) -> bool:
	if auto_scrap and item.rarity == 0 and not item.get("favorite", false):
		embers += salvage_value(item)
		return false
	inventory.append(item)
	return true

func sort_inventory() -> void:
	inventory.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.get("favorite", false)) != bool(b.get("favorite", false)):
			return bool(a.get("favorite", false))
		if a.slot != b.slot:
			return SLOTS.find(a.slot) < SLOTS.find(b.slot)
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		if a.tier != b.tier:
			return a.tier > b.tier
		return a.name < b.name
	)

func upgrade_cost(slot: String) -> int:
	var item: Dictionary = equipment.get(slot, {})
	return 8 * (int(item.get("upgrade", 0)) + 1) * int(item.get("tier", 1))

func upgrade(slot: String) -> bool:
	var item: Dictionary = equipment.get(slot, {})
	if item.is_empty() or int(item.get("upgrade", 0)) >= 3 or embers < upgrade_cost(slot):
		return false
	embers -= upgrade_cost(slot)
	item.upgrade = int(item.get("upgrade", 0)) + 1
	match slot:
		"weapon": item.attack += 5 + int(item.tier) * 2
		"armor": item.health += 15 + int(item.tier) * 3
		"charm": item.haste += 4
	return true

func rune_bonus(skill_index: int = -1) -> float:
	var active := stance if skill_index < 0 else skill_index
	var bonus := 0.0
	for item in equipment.values():
		if int(item.get("rune", -1)) == active:
			bonus += 0.12
	return bonus

func complete_mission(mission: int) -> bool:
	if mission != campaign or campaign >= 9:
		return false
	campaign += 1
	unlocked = mini(3, 1 + campaign / 3)
	embers += 12 + campaign * 2
	if campaign % 3 == 0:
		inventory.append(make_relic(campaign / 3 - 1, campaign / 3))
	return true

func effect_count(id: String) -> float:
	var count := 0.0
	for item in equipment.values():
		count += Mods.effect(item, id)
	return count

func has_relic(id: String) -> bool:
	for item in equipment.values():
		if item.get("relic", "") == id:
			return true
	return false

func make_relic(index: int, tier: int) -> Dictionary:
	var definition: Dictionary = Effects.RELICS[index]
	var item := roll_item(clampi(tier, 1, 9), true, definition.slot)
	item.erase("affix")
	item.erase("mods")
	item.name = definition.name
	item.rarity = 3
	item.relic = definition.id
	item.rune = definition.skill
	item.favorite = true
	# A special behavior trades away some of the raw stats of a comparable Rare.
	item.attack = int(item.attack * 0.8)
	item.health = int(item.health * 0.85)
	return item

func record_relic_hunt(chapter: int, tier: int) -> bool:
	if chapter < 0 or chapter >= 3 or campaign < (chapter + 1) * 3:
		return false
	relic_hunts[chapter] += 1
	if relic_hunts[chapter] < 3:
		return false
	relic_hunts[chapter] = 0
	inventory.append(make_relic(chapter, tier))
	return true

func stats() -> Dictionary:
	var result := {"attack": 8 + (level - 1) * 2, "health": 100 + (level - 1) * 5, "armor": 0, "haste": 0}
	for item in equipment.values():
		for stat in result:
			result[stat] += Mods.totals(item)[stat]
	result.attack += talents[0] * 5
	result.health += talents[1] * 20
	result.armor += talents[1]
	result.haste += talents[2] * 6
	for id in passives:
		var node := PassiveTree.def(id)
		result.health += int(node.get("health", 0))
		result.armor += int(node.get("armor", 0))
		result.haste += int(node.get("haste", 0))
	# Mana feeds the active skills; level, the spirit talent and passives raise it.
	var mana_bonus := 0
	var regen_bonus := 0.0
	for id in passives:
		var node := PassiveTree.def(id)
		mana_bonus += int(node.get("mana", 0))
		regen_bonus += float(node.get("regen", 0.0))
	result.mana = 80 + (level - 1) * 6 + talents[3] * 15 + mana_bonus
	result.regen = 6.0 + (level - 1) * 0.4 + talents[3] * 1.0 + regen_bonus
	result.armor += int(aura_value("armor"))
	result.regen += aura_value("regen")
	return result

func xp_needed() -> int:
	return 40 + (level - 1) * 25

func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1

func roll_item(tier: int, boss: bool = false, target_slot: String = "") -> Dictionary:
	var rarity := 2 if boss else (1 if randf() < 0.45 else 0)
	if not boss and randf() < 0.08:
		rarity = 2
	var slot: String = target_slot if target_slot in SLOTS else SLOTS.pick_random()
	var item := {"name": "", "slot": slot, "rarity": rarity, "tier": tier, "attack": 0, "health": 0, "armor": 0, "haste": 0, "rune": randi_range(0, 3) if rarity > 0 else -1, "upgrade": 0}
	match slot:
		"weapon":
			item.attack = 12 + tier * 6 + rarity * 5 + randi_range(0, 5)
			item.name = "Iron cleaver"
		"armor":
			item.health = 12 + tier * 10 + rarity * 8 + randi_range(0, 8)
			item.armor = tier * 2 + rarity
			item.name = "Warden mail"
		"charm":
			item.attack = tier * 2 + rarity * 2
			item.haste = 3 + tier * 2 + rarity * 3
			item.name = "Ember charm"
	if rarity >= 1:
		item.health += randi_range(5, 12) * tier
		item.mods = Mods.generate(item)
	if rarity == 2:
		item.attack += tier * 3
		item.haste += 4
	return item

func equip(index: int) -> bool:
	if index < 0 or index >= inventory.size():
		return false
	var item: Dictionary = inventory[index]
	var previous: Dictionary = equipment[item.slot]
	equipment[item.slot] = item
	inventory.remove_at(index)
	if not previous.is_empty():
		inventory.insert(index, previous)
	return true

func transfer_item(index: int, to_stash: bool) -> bool:
	var source: Array[Dictionary] = inventory if to_stash else stash
	var target: Array[Dictionary] = stash if to_stash else inventory
	if index < 0 or index >= source.size():
		return false
	target.append(source[index])
	source.remove_at(index)
	return true

func save_to(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		save_error = "Save failed. Progress is in memory only."
		return false
	file.store_string(JSON.stringify({"version": 8, "relic_hunts": relic_hunts, "loot_mode": loot_mode, "skill_levels": skill_levels, "skill_xp": skill_xp, "links": links, "builds": builds, "passives": passives, "active_slots": active_slots, "auras": auras, "campaign": campaign, "depth": depth, "abyss_complete": abyss_complete, "embers": embers, "stance": stance, "talents": talents, "play_seconds": play_seconds, "inventory": inventory, "stash": stash, "equipment": equipment, "level": level, "xp": xp, "unlocked": unlocked}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		save_error = "Save failed. Progress is in memory only."
		return false
	save_error = ""
	return true

func valid_item(item: Variant) -> bool:
	if not item is Dictionary or not item.get("slot", "") in SLOTS or not item.get("name") is String:
		return false
	for key in ["rarity", "tier", "attack", "health", "armor", "haste"]:
		if not item.get(key) is float and not item.get(key) is int:
			return false
		if item[key] < 0 or item[key] > 100000:
			return false
	if item.has("favorite") and not item.favorite is bool:
		return false
	for key in ["rune", "upgrade"]:
		if item.has(key) and (not (item[key] is float or item[key] is int) or item[key] != int(item[key])):
			return false
	if not Mods.valid(item):
		return false
	if item.has("affix") and (not item.affix is String or not Effects.AFFIXES.has(item.affix)):
		return false
	if item.has("relic"):
		if not item.relic is String:
			return false
		var index := Effects.relic_index(item.relic)
		if index < 0 or item.slot != Effects.RELICS[index].slot or item.rarity != 3:
			return false
	elif item.rarity == 3:
		return false
	return item.rarity <= 3 and item.tier >= 1 and item.tier <= 9 and int(item.get("rune", -1)) in [-1, 0, 1, 2, 3] and int(item.get("upgrade", 0)) in [0, 1, 2, 3]

func load_from(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not (data.get("version") is float or data.get("version") is int) or not int(data.get("version")) in [1, 2, 3, 4, 5, 6, 7, 8]:
		return false
	if not data.get("inventory") is Array or not data.get("equipment") is Dictionary:
		return false
	for key in ["level", "xp", "unlocked"]:
		if not data.get(key) is float and not data.get(key) is int:
			return false
	if data.level < 1 or data.level > 100000 or data.xp < 0 or data.xp >= 40 + (data.level - 1) * 25 or data.unlocked < 1 or data.unlocked > 3:
		return false
	for item in data.inventory:
		if not valid_item(item):
			return false
	var saved_stash: Variant = data.get("stash", []) if data.version >= 2 else []
	if not saved_stash is Array:
		return false
	for item in saved_stash:
		if not valid_item(item):
			return false
	for slot in SLOTS:
		var item: Variant = data.equipment.get(slot)
		if not item is Dictionary:
			return false
		if not item.is_empty() and (not valid_item(item) or item.slot != slot):
			return false
	if data.version >= 3:
		for key in ["campaign", "depth", "embers", "stance"]:
			if not (data.get(key) is float or data.get(key) is int):
				return false
			if data[key] != int(data[key]):
				return false
		if data.campaign < 0 or data.campaign > 9 or data.depth < 1 or data.depth > 5 or data.embers < 0 or data.embers > 100000000 or not int(data.stance) in [0, 1, 2, 3]:
			return false
		if data.version < 8 and (not (data.get("support") is float or data.get("support") is int) or not int(data.support) in [0, 1, 2]):
			return false
		if not data.get("abyss_complete") is bool or not (data.get("play_seconds") is float or data.get("play_seconds") is int) or data.play_seconds < 0:
			return false
		var expected_talents := 4 if data.version >= 8 else 3
		if not data.get("talents") is Array or data.talents.size() != expected_talents:
			return false
		var spent := 0
		for value in data.talents:
			if not (value is float or value is int) or value != int(value) or value < 0 or value > 6:
				return false
			spent += int(value)
		if spent > mini(int(data.level) - 1, 18):
			return false
		if data.unlocked != mini(3, 1 + int(data.campaign) / 3) or (data.campaign < 9 and (data.depth != 1 or data.abyss_complete)) or (data.abyss_complete and data.depth != 5):
			return false
	if data.version >= 8:
		if not _valid_mastery(data.get("skill_levels"), data.get("skill_xp"), 8):
			return false
		if not data.get("builds") is Array or data.builds.size() != 3:
			return false
		for entry in data.builds:
			if not entry is Dictionary:
				return false
			if entry.is_empty():
				continue
			if not (entry.get("stance") is int or entry.get("stance") is float) or not int(entry.stance) in [0, 1, 2, 3]:
				return false
			if not entry.get("talents") is Array or entry.talents.size() != 4:
				return false
			var build_spent := 0
			for value in entry.talents:
				if not (value is int or value is float) or value != int(value) or value < 0 or value > 6:
					return false
				build_spent += int(value)
			if build_spent > 18:
				return false
			var entry_active: Array = ["", "", "", ""]
			if entry.has("active_slots"):
				if not entry.active_slots is Array or entry.active_slots.size() != 4:
					return false
				var slot_seen: Array[String] = []
				for i in range(4):
					var value: Variant = entry.active_slots[i]
					if not value is String:
						return false
					if value == "":
						continue
					if not Skills.has_id(value) or value in slot_seen or value == Skills.id_at(int(entry.stance)):
						return false
					slot_seen.append(value)
					entry_active[i] = str(value)
			if not entry.get("links") is Array or entry.links.size() != 5:
				return false
			var build_used: Array[String] = []
			for slot in range(5):
				var entries: Variant = entry.links[slot]
				if not entries is Array or entries.size() > Skills.MAX_SUPPORTS:
					return false
				var slot_id: String = Skills.id_at(int(entry.stance)) if slot == 0 else str(entry_active[slot - 1])
				var index := Skills.index_of(slot_id)
				for item in entries:
					if not item is Dictionary:
						return false
					var id: Variant = item.get("id")
					var tier: Variant = item.get("tier")
					if not id is String or not Skills.has_support(id) or index < 0 or not Skills.support_applies(index, id) or id in build_used:
						return false
					if not (tier is int or tier is float) or tier != int(tier) or int(tier) < 1 or int(tier) > 3:
						return false
					build_used.append(id)
			if entry.has("auras"):
				if not entry.auras is Array:
					return false
				var build_auras: Array[String] = []
				var build_reserved := 0
				for value in entry.auras:
					if not value is String or not Skills.has_aura(value) or value in build_auras:
						return false
					build_auras.append(value)
					build_reserved += int(Skills.aura_def(value).get("reserve", 0))
				if build_reserved > 30 + (int(data.level) - 1) * 2:
					return false
		if not data.get("passives") is Array or data.passives.size() > PassiveTree.MAX_POINTS:
			return false
		var allocated: Array[String] = []
		for value in data.passives:
			if not value is String or value == PassiveTree.ROOT or not PassiveTree.has(value) or value in allocated:
				return false
			allocated.append(value)
		for id in allocated:
			var parent: String = PassiveTree.def(id).parent
			if parent != PassiveTree.ROOT and not parent in allocated:
				return false
		if not data.get("active_slots") is Array or data.active_slots.size() != 4:
			return false
		var assigned: Array[String] = []
		for value in data.active_slots:
			if not value is String:
				return false
			if value == "":
				continue
			if not Skills.has_id(value) or value in assigned or value == Skills.id_at(int(data.stance)):
				return false
			assigned.append(value)
		if not data.get("links") is Array or data.links.size() != 5:
			return false
		var used: Array[String] = []
		for slot in range(5):
			var entries: Variant = data.links[slot]
			if not entries is Array or entries.size() > Skills.MAX_SUPPORTS:
				return false
			var slot_id: String = Skills.id_at(int(data.stance)) if slot == 0 else str(data.active_slots[slot - 1])
			var index := Skills.index_of(slot_id)
			for item in entries:
				if not item is Dictionary:
					return false
				var id: Variant = item.get("id")
				var tier: Variant = item.get("tier")
				if not id is String or not Skills.has_support(id) or index < 0 or not Skills.support_applies(index, id) or id in used:
					return false
				if not (tier is int or tier is float) or tier != int(tier) or int(tier) < 1 or int(tier) > 3:
					return false
				used.append(id)
		if not data.get("auras") is Array:
			return false
		var aura_seen: Array[String] = []
		var reserved := 0
		for value in data.auras:
			if not value is String or not Skills.has_aura(value) or value in aura_seen:
				return false
			aura_seen.append(value)
			reserved += int(Skills.aura_def(value).get("reserve", 0))
		if reserved > 30 + (int(data.level) - 1) * 2:
			return false
	elif data.version >= 4:
		if not _valid_mastery(data.get("skill_levels"), data.get("skill_xp"), 3):
			return false
		if not _valid_mastery(data.get("support_levels"), data.get("support_xp"), 3):
			return false
	if data.version >= 5:
		var saved_mode: Variant = data.get("loot_mode")
		if not (saved_mode is int or saved_mode is float) or saved_mode != int(saved_mode) or not int(saved_mode) in [0, 1, 2]:
			return false
	if data.version >= 6:
		if not data.get("relic_hunts") is Array or data.relic_hunts.size() != 3:
			return false
		for value in data.relic_hunts:
			if not (value is int or value is float) or value != int(value) or value < 0 or value > 2:
				return false
	# JSON numbers are floats; normalize equipment values before using them.
	var restored: Array[Dictionary] = []
	for item in data.inventory:
		restored.append(normalize_item(item))
	inventory = restored
	stash.clear()
	for item in saved_stash:
		stash.append(normalize_item(item))
	for slot in SLOTS:
		equipment[slot] = normalize_item(data.equipment[slot])
	level = int(data.level)
	xp = int(data.xp)
	unlocked = int(data.unlocked)
	campaign = int(data.get("campaign", (unlocked - 1) * 3))
	depth = int(data.get("depth", 1))
	abyss_complete = bool(data.get("abyss_complete", false))
	embers = int(data.get("embers", 0))
	stance = int(data.get("stance", 0))
	if data.version >= 8:
		talents.assign(data.talents)
	else:
		var legacy_talents: Array[int] = []
		for value in data.get("talents", [0, 0, 0]):
			legacy_talents.append(int(value))
		while legacy_talents.size() < 4:
			legacy_talents.append(0)
		talents.assign(legacy_talents)
	play_seconds = float(data.get("play_seconds", 0))
	loot_mode = int(data.loot_mode) if data.version >= 5 else 1
	relic_hunts.assign(data.relic_hunts if data.version >= 6 else [0, 0, 0])
	if data.version >= 8:
		skill_levels.assign(data.skill_levels)
		skill_xp.assign(data.skill_xp)
		links = [[], [], [], [], []]
		for slot in range(5):
			var entries: Array = []
			for item in data.links[slot]:
				entries.append({"id": str(item.get("id", "")), "tier": int(item.get("tier", 3))})
			links[slot] = entries
		builds.clear()
		for entry in data.builds:
			builds.append(normalize_build(entry))
		passives.clear()
		for value in data.passives:
			passives.append(str(value))
		active_slots.clear()
		for value in data.active_slots:
			active_slots.append(str(value))
		auras.clear()
		for value in data.auras:
			auras.append(str(value))
	else:
		var legacy_levels: Array[int] = [1, 1, 1]
		var legacy_xp: Array[int] = [0, 0, 0]
		if data.version >= 4:
			legacy_levels.assign(data.skill_levels)
			legacy_xp.assign(data.skill_xp)
		skill_levels.assign([legacy_levels[0], legacy_levels[1], legacy_levels[2], 1, 1, 1, 1, 1])
		skill_xp.assign([legacy_xp[0], legacy_xp[1], legacy_xp[2], 0, 0, 0, 0, 0])
		links = [[], [], [], [], []]
		if data.version >= 3:
			var mapped: String = ["power", "haste", "leech"][clampi(int(data.get("support", 0)), 0, 2)]
			if Skills.support_applies(stance, mapped):
				links[0] = [{"id": mapped, "tier": 3}]
		builds.clear()
		builds.append({})
		builds.append({})
		builds.append({})
		passives.clear()
		active_slots.assign(["ember_lance", "cinder_field", "barrier", "rush"])
		auras.clear()
	return true

func normalize_build(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var result := {"name": str(entry.get("name", "")), "stance": int(entry.stance)}
	var saved_links: Array = []
	for slot in range(5):
		var entries: Array = []
		if entry.get("links") is Array and slot < entry.links.size() and entry.links[slot] is Array:
			for item in entry.links[slot]:
				if item is Dictionary:
					entries.append({"id": str(item.get("id", "")), "tier": clampi(int(item.get("tier", 3)), 1, 3)})
		saved_links.append(entries)
	result.links = saved_links
	var saved_talents: Array[int] = []
	for value in entry.talents:
		saved_talents.append(int(value))
	result.talents = saved_talents
	if entry.has("active_slots") and entry.active_slots is Array:
		var saved_slots: Array[String] = []
		for value in entry.active_slots:
			saved_slots.append(str(value))
		result.active_slots = saved_slots
	if entry.has("auras") and entry.auras is Array:
		var saved_auras: Array[String] = []
		for value in entry.auras:
			saved_auras.append(str(value))
		result.auras = saved_auras
	return result

func _valid_mastery(levels: Variant, experience: Variant, size: int) -> bool:
	if not levels is Array or not experience is Array or levels.size() != size or experience.size() != size:
		return false
	for i in range(size):
		for value in [levels[i], experience[i]]:
			if not (value is int or value is float) or not is_finite(float(value)) or value != int(value):
				return false
		if levels[i] < 1 or levels[i] > Skills.MAX_LEVEL or experience[i] < 0 or experience[i] >= Skills.xp_needed(int(levels[i])):
			return false
		if levels[i] == Skills.MAX_LEVEL and experience[i] != 0:
			return false
	return true

func normalize_item(item: Dictionary) -> Dictionary:
	var result := item.duplicate(true)
	if not result.is_empty():
		for key in ["rarity", "tier", "attack", "health", "armor", "haste"]:
			result[key] = int(result[key])
		for key in ["rune", "upgrade"]:
			if result.has(key):
				result[key] = int(result[key])
		if result.has("mods"):
			for mod in result.mods:
				if not mod.is_empty():
					mod.tier = int(mod.tier)
					mod.value = int(mod.value)
	return result

func craft_quote(slot: String, index: int, id: String, tier: int) -> Dictionary:
	var item: Dictionary = equipment.get(slot, {})
	var price := Mods.cost(item, index, id, tier)
	if price < 0:
		return {}
	return {"cost": price, "snapshot": item.duplicate(true), "slot": slot, "index": index, "id": id, "tier": tier}

func begin_craft(quote: Dictionary) -> Dictionary:
	if quote.is_empty():
		return {}
	var current := craft_quote(quote.slot, quote.index, quote.id, quote.tier)
	if current != quote or embers < int(quote.cost):
		return {}
	embers -= int(quote.cost)
	var result := quote.duplicate(true)
	result.item = quote.snapshot.duplicate(true)
	result.item.mods = Mods.entries(result.item)
	result.item.erase("affix")
	result.item.mods[quote.index] = Mods.roll(quote.id, quote.tier)
	return result

func accept_craft(result: Dictionary) -> bool:
	if result.is_empty() or equipment.get(result.slot, {}) != result.snapshot or not valid_item(result.item):
		return false
	equipment[result.slot] = result.item.duplicate(true)
	return true

func toggle_mod_lock(slot: String, index: int) -> bool:
	var item: Dictionary = equipment.get(slot, {})
	if index < 0 or index >= 4 or Mods.capacity(item) == 0:
		return false
	var mods := Mods.entries(item)
	if mods[index].is_empty():
		return false
	mods[index].locked = not mods[index].locked
	item.mods = mods
	item.erase("affix")
	return true
