extends RefCounted
## Four explicit slots: two prefixes and two suffixes. T1 is strongest.
const Loc = preload("res://scripts/loc.gd")
const DEFINITIONS := {
	"might": {"name": "Might", "side": 0, "stat": "attack", "ranges": [[3, 5], [6, 8], [9, 12]], "unit": "attack"},
	"vitality": {"name": "Vitality", "side": 0, "stat": "health", "ranges": [[8, 12], [16, 22], [28, 36]], "unit": "life"},
	"guard": {"name": "Guard", "side": 0, "stat": "armor", "ranges": [[1, 2], [3, 4], [5, 6]], "unit": "defense"},
	"tempo": {"name": "Tempo", "side": 1, "stat": "haste", "ranges": [[2, 3], [4, 5], [6, 8]], "unit": "% speed"},
	"scorch": {"name": "Scorching", "side": 1, "stat": "", "ranges": [[100, 100], [125, 125], [150, 150]], "unit": "% effect"},
	"frost": {"name": "Frostbound", "side": 1, "stat": "", "ranges": [[100, 100], [125, 125], [150, 150]], "unit": "% effect"},
	"charge": {"name": "Charged", "side": 1, "stat": "", "ranges": [[100, 100], [125, 125], [150, 150]], "unit": "% effect"}
}
static func capacity(item: Dictionary) -> int:
	return 2 if item.get("rarity", 0) == 2 else (1 if item.get("rarity", 0) == 1 else 0)
static func best_tier(item: Dictionary) -> int:
	return maxi(1, 4 - int(item.get("tier", 1)))
static func pool(side: int) -> Array[String]:
	var ids: Array[String] = []
	for id in DEFINITIONS:
		if DEFINITIONS[id].side == side:
			ids.append(id)
	return ids
static func roll(id: String, tier: int) -> Dictionary:
	var limits: Array = DEFINITIONS[id].ranges[3 - tier]
	return {"id": id, "tier": tier, "value": randi_range(limits[0], limits[1]), "locked": false}
static func generate(item: Dictionary) -> Array:
	var mods: Array = [{}, {}, {}, {}]
	for side in range(2):
		var available := pool(side)
		available.shuffle()
		for slot in range(capacity(item)):
			mods[side * 2 + slot] = roll(available[slot], randi_range(best_tier(item), 3))
	return mods
static func entries(item: Dictionary) -> Array:
	if item.has("mods"):
		return item.mods.duplicate(true)
	var result: Array = [{}, {}, {}, {}]
	# Legacy effects are represented at exactly their original strength.
	if item.has("affix") and capacity(item) > 0:
		result[2] = {"id": item.affix, "tier": 3, "value": 100, "locked": false}
	return result
static func totals(item: Dictionary) -> Dictionary:
	var result := {"attack": int(item.get("attack", 0)), "health": int(item.get("health", 0)), "armor": int(item.get("armor", 0)), "haste": int(item.get("haste", 0))}
	for mod in entries(item):
		if not mod.is_empty():
			var stat: String = DEFINITIONS[mod.id].stat
			if not stat.is_empty():
				result[stat] += int(mod.value)
	return result
static func effect(item: Dictionary, id: String) -> float:
	if not item.has("mods"):
		return 1.0 if item.get("affix", "") == id else 0.0
	var result := 0.0
	for mod in item.mods:
		if mod.get("id", "") == id:
			result += float(mod.value) / 100.0
	return result
static func valid(item: Dictionary) -> bool:
	if not item.has("mods"):
		return true
	if item.has("affix") or not item.mods is Array or item.mods.size() != 4 or capacity(item) == 0:
		return false
	var seen: Array[String] = []
	for i in range(4):
		var mod: Variant = item.mods[i]
		if not mod is Dictionary:
			return false
		if mod.is_empty():
			continue
		if i % 2 >= capacity(item) or not mod.get("id") is String or not DEFINITIONS.has(mod.id) or mod.id in seen:
			return false
		seen.append(mod.id)
		if DEFINITIONS[mod.id].side != i / 2 or not mod.get("locked") is bool:
			return false
		for key in ["tier", "value"]:
			if not (mod.get(key) is int or mod.get(key) is float) or not is_finite(float(mod[key])) or mod[key] != int(mod[key]):
				return false
		if mod.tier < best_tier(item) or mod.tier > 3:
			return false
		var limits: Array = DEFINITIONS[mod.id].ranges[3 - int(mod.tier)]
		if mod.value < limits[0] or mod.value > limits[1]:
			return false
	return true
static func cost(item: Dictionary, index: int, id: String, tier: int) -> int:
	if item.is_empty() or index < 0 or index >= 4 or index % 2 >= capacity(item) or not DEFINITIONS.has(id) or DEFINITIONS[id].side != index / 2 or tier < best_tier(item) or tier > 3:
		return -1
	var mods := entries(item)
	if mods[index].get("locked", false):
		return -1
	for i in range(4):
		if i != index and mods[i].get("id", "") == id:
			return -1
	return (4 + int(item.tier) * 2) * (4 - tier)
static func describe(mod: Dictionary) -> String:
	if mod.is_empty():
		return Loc.t("Empty Mod slot")
	var lock := Loc.t(" [LOCK]") if mod.locked else ""
	if mod.id in ["scorch", "frost", "charge"]:
		var effect_text: String = {"scorch": Loc.t("Burn %.0f%%/s (2s)") % (mod.value * 0.2), "frost": Loc.t("Slow %.1f%% (1.5s)") % (100.0 * (1.0 - pow(0.85, mod.value / 100.0))), "charge": Loc.t("+%.0f heat / hit") % (mod.value * 0.04)}[mod.id]
		return Loc.t("%s T%d / %s%s") % [Loc.t(DEFINITIONS[mod.id].name), mod.tier, effect_text, lock]
	return Loc.t("%s T%d / +%d %s%s") % [Loc.t(DEFINITIONS[mod.id].name), mod.tier, mod.value, Loc.t(DEFINITIONS[mod.id].unit), lock]
