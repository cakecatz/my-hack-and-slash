extends RefCounted
## Persistent character and equipment. Expedition state is deliberately separate.

const SAVE_PATH := "user://character.json"
const RARITIES := ["Common", "Magic", "Rare"]
const SLOTS := ["weapon", "armor", "charm"]
var inventory: Array[Dictionary] = []
var equipment: Dictionary = {
	"weapon": {"name": "Worn sword", "slot": "weapon", "rarity": 0, "tier": 1, "attack": 10, "health": 0, "armor": 0, "haste": 0},
	"armor": {"name": "Traveler coat", "slot": "armor", "rarity": 0, "tier": 1, "attack": 0, "health": 10, "armor": 1, "haste": 0},
	"charm": {}
}
var level := 1
var xp := 0
var unlocked := 1
var save_error := ""

func stats() -> Dictionary:
	var result := {"attack": 8 + (level - 1) * 2, "health": 100 + (level - 1) * 5, "armor": 0, "haste": 0}
	for item in equipment.values():
		for stat in result:
			result[stat] += int(item.get(stat, 0))
	return result

func xp_needed() -> int:
	return 40 + (level - 1) * 25

func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1

func roll_item(tier: int, boss: bool = false) -> Dictionary:
	var rarity := 2 if boss else (1 if randf() < 0.45 else 0)
	if not boss and randf() < 0.08:
		rarity = 2
	var slot: String = SLOTS.pick_random()
	var item := {"name": "", "slot": slot, "rarity": rarity, "tier": tier, "attack": 0, "health": 0, "armor": 0, "haste": 0}
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
		item.name = "Stalwart " + item.name
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

func save_to(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		save_error = "Save failed. Progress is in memory only."
		return false
	file.store_string(JSON.stringify({"version": 1, "inventory": inventory, "equipment": equipment, "level": level, "xp": xp, "unlocked": unlocked}))
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
	return item.rarity <= 2 and item.tier >= 1 and item.tier <= 3

func load_from(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version") != 1:
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
	for slot in SLOTS:
		var item: Variant = data.equipment.get(slot)
		if not item is Dictionary:
			return false
		if not item.is_empty() and (not valid_item(item) or item.slot != slot):
			return false
	# JSON numbers are floats; normalize equipment values before using them.
	var restored: Array[Dictionary] = []
	for item in data.inventory:
		restored.append(normalize_item(item))
	inventory = restored
	for slot in SLOTS:
		equipment[slot] = normalize_item(data.equipment[slot])
	level = int(data.level)
	xp = int(data.xp)
	unlocked = int(data.unlocked)
	return true

func normalize_item(item: Dictionary) -> Dictionary:
	var result := item.duplicate()
	if not result.is_empty():
		for key in ["rarity", "tier", "attack", "health", "armor", "haste"]:
			result[key] = int(result[key])
	return result
