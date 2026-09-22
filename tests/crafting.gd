extends SceneTree
const Profile = preload("res://scripts/profile.gd")
const Mods = preload("res://scripts/item_mods.gd")
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, title: String) -> void:
	if not ok:
		failed = true
		push_error("FAIL: " + title)
func run() -> void:
	seed(127)
	var p = Profile.new()
	for tier in range(1, 10):
		for i in range(40):
			var item: Dictionary = p.roll_item(tier)
			check(p.valid_item(item), "Generated Mod pools, capacity and tiers are valid")
	p.equipment.weapon = p.roll_item(3, true, "weapon")
	p.equipment.weapon.mods = [{}, {}, {}, {}]
	p.equipment.weapon.favorite = true
	p.embers = 100
	var old: Dictionary = p.equipment.weapon.duplicate(true)
	var base: Dictionary = p.stats()
	var quote: Dictionary = p.craft_quote("weapon", 0, "might", 1)
	check(quote.cost == 30, "Price is known before rolling")
	var pending: Dictionary = p.begin_craft(quote)
	check(p.embers == 70 and p.equipment.weapon == old, "Attempt spends cost while old equipment remains equipped")
	check(p.accept_craft(pending) and p.stats().attack == base.attack + pending.item.mods[0].value, "Accept applies exactly one Mod to actual stats")
	check(p.equipment.weapon.favorite and p.equipment.weapon.tier == old.tier, "Craft preserves item identity and salvage protection")
	check(p.toggle_mod_lock("weapon", 0) and p.craft_quote("weapon", 0, "vitality", 3).is_empty(), "Locked Mod cannot be replaced")
	check(p.craft_quote("weapon", 1, "might", 3).is_empty(), "Duplicate families rejected")
	check(p.craft_quote("weapon", 0, "tempo", 3).is_empty(), "Prefix cannot receive suffix")
	var locked: Dictionary = p.equipment.weapon.mods[0].duplicate(true)
	pending = p.begin_craft(p.craft_quote("weapon", 2, "scorch", 1))
	check(p.accept_craft(pending) and p.equipment.weapon.mods[0] == locked and p.effect_count("scorch") == 1.5, "Other slots preserved and Tier scales actual combat effect")
	var before: Dictionary = p.equipment.weapon.duplicate(true)
	quote = p.craft_quote("weapon", 1, "guard", 2)
	pending = p.begin_craft(quote)
	pending.clear()
	check(p.equipment.weapon == before and p.embers == 20, "Discard keeps original Mod with paid cost")
	p.embers = 0
	check(p.begin_craft(quote).is_empty() and p.embers == 0, "Insufficient materials cannot mutate gear")
	p.embers = 100
	p.equipment.weapon.upgrade = 1
	check(p.begin_craft(quote).is_empty() and p.embers == 100, "Stale quote rejected without cost")
	var low: Dictionary = p.roll_item(1, true, "armor")
	p.equipment.armor = low
	check(p.craft_quote("armor", 0, "might", 1).is_empty(), "Low bases cannot craft T1")
	p.equipment.charm = p.make_relic(2, 3)
	check(p.craft_quote("charm", 0, "might", 3).is_empty(), "Relics excluded from random Mod crafting")
	# Existing one-affix items retain all stats and original effect strength.
	p.equipment.weapon = {"name": "Old sword", "slot": "weapon", "rarity": 2, "tier": 2, "attack": 38, "health": 9, "armor": 0, "haste": 4, "affix": "charge", "upgrade": 2, "rune": 0}
	base = p.stats()
	check(p.effect_count("charge") >= 1, "Legacy special effect retained")
	pending = p.begin_craft(p.craft_quote("weapon", 0, "might", 3))
	check(p.accept_craft(pending) and p.equipment.weapon.attack == 38 and p.equipment.weapon.mods[2].id == "charge" and p.equipment.weapon.upgrade == 2, "First craft migrates legacy effect without rebalancing old base")
	var path := "/tmp/ember-craft-test.json"
	check(p.save_to(path), "Save Mod gear")
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.equipment == p.equipment and loaded.stats() == p.stats(), "Nested Mods normalize and round trip")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var original: Dictionary = loaded.equipment.duplicate(true)
	for fault in ["tier", "value", "id", "locked"]:
		var bad := data.duplicate(true)
		bad.equipment.weapon.mods[0][fault] = {"tier": 0, "value": 999, "id": "unknown", "locked": "yes"}[fault]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(bad))
		file.close()
		check(not loaded.load_from(path) and loaded.equipment == original, "Invalid Mod data rejected atomically")
	DirAccess.remove_absolute(path)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.profile = p
	scene.panel = "build"
	scene.build_tab = 2
	scene.craft_slot = "weapon"
	scene.craft_index = 1
	scene.craft_id = "guard"
	scene.craft_tier = 3
	scene.craft_click(Vector2(700, 505))
	check(not scene.craft_pending.is_empty(), "Actual forge UI starts a craft")
	var money: int = p.embers
	scene.close_panel()
	check(scene.craft_pending.is_empty() and p.embers == money, "Closing cancels proposal without refund")
	scene.enter_map(0)
	scene.panel = "build"
	scene.craft_click(Vector2(700, 505))
	check(scene.craft_pending.is_empty() and p.embers == money, "Crafting unavailable outside hub")
	scene.panel = ""
	scene.enemies.clear()
	scene.player = Vector2(2000, 750)
	scene.facing = Vector2.RIGHT
	p.equipment.weapon = p.roll_item(3, true, "weapon")
	p.equipment.weapon.mods = [{}, {}, {"id": "scorch", "tier": 1, "value": 150, "locked": false}, {"id": "frost", "tier": 1, "value": 150, "locked": false}]
	p.equipment.armor = {}
	p.equipment.charm = {}
	scene.refresh_stats()
	scene.spawn_enemy(scene.player + Vector2(50, 0))
	var enemy: Dictionary = scene.enemies[-1]
	enemy.hp = 100000.0
	var hit: float = p.combat_stats().damage
	scene.attack()
	check(is_equal_approx(enemy.burn_dps, hit * 0.3) and is_equal_approx(enemy.slow_factor, pow(0.85, 1.5)), "T1 suffix values reach actual burn and slow calculations")
	scene.queue_free()
	await process_frame
	if not failed:
		print("PASS: Mod pools, tiers, targeted crafting, locks, costs, keep/discard, migration, validation and forge UI")
	quit(1 if failed else 0)
