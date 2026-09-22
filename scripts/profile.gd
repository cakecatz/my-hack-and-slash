extends RefCounted
## Persistent character and equipment. Expedition state is deliberately separate.

const Skills = preload("res://scripts/skill_catalog.gd")

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
var support := 0
var skill_levels: Array[int] = [1, 1, 1]
var skill_xp: Array[int] = [0, 0, 0]
var support_levels: Array[int] = [1, 1, 1]
var support_xp: Array[int] = [0, 0, 0]
var talents: Array[int] = [0, 0, 0]
var play_seconds := 0.0
# 0: manual, 1: auto pickup, 2: auto pickup and salvage Common drops.
var loot_mode := 1
var relic_hunts: Array[int] = [0, 0, 0]
const LOOT_MODES := ["MANUAL", "AUTO", "AUTO + SCRAP"]
const STANCES := ["CLEAVE", "NOVA", "LANCE"]
const SUPPORTS := ["POWER", "ECHO", "SIPHON"]

func support_unlocked(index: int) -> bool:
	return index == 0 or campaign >= 3

func gain_mastery(amount: int) -> Array[String]:
	var gained: Array[String] = []
	if amount <= 0:
		return gained
	for is_support in [false, true]:
		var index := support if is_support else stance
		if is_support and not support_unlocked(index):
			continue
		var levels: Array[int] = support_levels if is_support else skill_levels
		var experience: Array[int] = support_xp if is_support else skill_xp
		if levels[index] >= Skills.MAX_LEVEL:
			continue
		var old_level := levels[index]
		experience[index] += amount
		while levels[index] < Skills.MAX_LEVEL and experience[index] >= Skills.xp_needed(levels[index]):
			experience[index] -= Skills.xp_needed(levels[index])
			levels[index] += 1
		if levels[index] == Skills.MAX_LEVEL:
			experience[index] = 0
		if levels[index] > old_level:
			gained.append("%s Lv.%d" % [SUPPORTS[index] if is_support else STANCES[index], levels[index]])
	return gained

func combat_stats(skill_index: int = -1, support_index: int = -1, next_skill: bool = false, next_support: bool = false) -> Dictionary:
	var active := stance if skill_index < 0 else skill_index
	var linked := support if support_index < 0 else support_index
	var skill_level := mini(Skills.MAX_LEVEL, skill_levels[active] + (1 if next_skill else 0))
	var support_level := mini(Skills.MAX_LEVEL, support_levels[linked] + (1 if next_support else 0))
	var base := stats()
	return {
		"damage": base.attack * Skills.skill_multiplier(active, skill_level) * Skills.support_damage(linked, support_level) * (1 + rune_bonus(active)),
		"interval": 0.4 / (1.0 + base.haste / 100.0) * Skills.interval_multiplier(linked, support_level),
		"reach": Skills.reach(active, skill_level),
		"recovery": Skills.recovery(linked, support_level)
	}

func talent_points() -> int:
	return mini(level - 1, 18) - talents[0] - talents[1] - talents[2]

func spend_talent(index: int) -> bool:
	if index < 0 or index > 2 or talent_points() <= 0 or talents[index] >= 6:
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

func effect_count(id: String) -> int:
	var count := 0
	for item in equipment.values():
		if item.get("affix", "") == id:
			count += 1
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
			result[stat] += int(item.get(stat, 0))
	result.attack += talents[0] * 5
	result.health += talents[1] * 20
	result.armor += talents[1]
	result.haste += talents[2] * 6
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
	var item := {"name": "", "slot": slot, "rarity": rarity, "tier": tier, "attack": 0, "health": 0, "armor": 0, "haste": 0, "rune": randi_range(0, 2) if rarity > 0 else -1, "upgrade": 0}
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
		item.affix = Effects.AFFIXES.keys().pick_random()
		item.name = Effects.AFFIXES[item.affix].name + " " + item.name
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
	file.store_string(JSON.stringify({"version": 6, "relic_hunts": relic_hunts, "loot_mode": loot_mode, "skill_levels": skill_levels, "skill_xp": skill_xp, "support_levels": support_levels, "support_xp": support_xp, "campaign": campaign, "depth": depth, "abyss_complete": abyss_complete, "embers": embers, "stance": stance, "support": support, "talents": talents, "play_seconds": play_seconds, "inventory": inventory, "stash": stash, "equipment": equipment, "level": level, "xp": xp, "unlocked": unlocked}))
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
	return item.rarity <= 3 and item.tier >= 1 and item.tier <= 9 and int(item.get("rune", -1)) in [-1, 0, 1, 2] and int(item.get("upgrade", 0)) in [0, 1, 2, 3]

func load_from(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2 and data.get("version") != 3 and data.get("version") != 4 and data.get("version") != 5 and data.get("version") != 6):
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
		for key in ["campaign", "depth", "embers", "stance", "support"]:
			if not (data.get(key) is float or data.get(key) is int):
				return false
			if data[key] != int(data[key]):
				return false
		if data.campaign < 0 or data.campaign > 9 or data.depth < 1 or data.depth > 5 or data.embers < 0 or data.embers > 100000000 or not int(data.stance) in [0, 1, 2] or not int(data.support) in [0, 1, 2]:
			return false
		if not data.get("abyss_complete") is bool or not (data.get("play_seconds") is float or data.get("play_seconds") is int) or data.play_seconds < 0:
			return false
		if not data.get("talents") is Array or data.talents.size() != 3:
			return false
		var spent := 0
		for value in data.talents:
			if not (value is float or value is int) or value != int(value) or value < 0 or value > 6:
				return false
			spent += int(value)
		if spent > mini(int(data.level) - 1, 18) or (data.campaign < 3 and data.support != 0):
			return false
		if data.unlocked != mini(3, 1 + int(data.campaign) / 3) or (data.campaign < 9 and (data.depth != 1 or data.abyss_complete)) or (data.abyss_complete and data.depth != 5):
			return false
	if data.version >= 4:
		for kind in ["skill", "support"]:
			var levels: Variant = data.get(kind + "_levels")
			var experience: Variant = data.get(kind + "_xp")
			if not levels is Array or not experience is Array or levels.size() != 3 or experience.size() != 3:
				return false
			for i in range(3):
				for value in [levels[i], experience[i]]:
					if not (value is int or value is float) or not is_finite(float(value)) or value != int(value):
						return false
				if levels[i] < 1 or levels[i] > Skills.MAX_LEVEL or experience[i] < 0 or experience[i] >= Skills.xp_needed(int(levels[i])):
					return false
				if levels[i] == Skills.MAX_LEVEL and experience[i] != 0:
					return false
				if kind == "support" and i > 0 and data.campaign < 3 and (levels[i] != 1 or experience[i] != 0):
					return false
	if data.version >= 5:
		var saved_mode: Variant = data.get("loot_mode")
		if not (saved_mode is int or saved_mode is float) or saved_mode != int(saved_mode) or not int(saved_mode) in [0, 1, 2]:
			return false
	if data.version == 6:
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
	support = int(data.get("support", 0))
	talents.assign(data.get("talents", [0, 0, 0]))
	play_seconds = float(data.get("play_seconds", 0))
	loot_mode = int(data.loot_mode) if data.version >= 5 else 1
	relic_hunts.assign(data.relic_hunts if data.version == 6 else [0, 0, 0])
	skill_levels.assign(data.skill_levels if data.version >= 4 else [1, 1, 1])
	skill_xp.assign(data.skill_xp if data.version >= 4 else [0, 0, 0])
	support_levels.assign(data.support_levels if data.version >= 4 else [1, 1, 1])
	support_xp.assign(data.support_xp if data.version >= 4 else [0, 0, 0])
	return true

func normalize_item(item: Dictionary) -> Dictionary:
	var result := item.duplicate()
	if not result.is_empty():
		for key in ["rarity", "tier", "attack", "health", "armor", "haste"]:
			result[key] = int(result[key])
		for key in ["rune", "upgrade"]:
			if result.has(key):
				result[key] = int(result[key])
	return result
