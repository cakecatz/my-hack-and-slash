extends SceneTree

const Profile = preload("res://scripts/profile.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)

func run() -> void:
	seed(42)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	check(scene.hub and scene.profile.level == 1, "Start in hub")
	var spawn: Vector2 = scene.player
	Input.action_press("right")
	scene._process(0.1)
	Input.action_release("right")
	check(scene.player.x > spawn.x, "Walk in town")
	scene.interact_hub()
	check(scene.panel.is_empty(), "Facilities require proximity")
	var travel_key := InputEventKey.new()
	travel_key.keycode = KEY_1
	travel_key.pressed = true
	scene._unhandled_input(travel_key)
	check(scene.hub, "Map shortcut cannot bypass gate")
	scene.player = scene.STASH_POS + Vector2(0, 80)
	scene.interact_hub()
	check(scene.panel == "stash", "Nearby chest opens stash")
	var standing: Vector2 = scene.player
	Input.action_press("right")
	scene._process(0.1)
	Input.action_release("right")
	check(scene.player == standing, "Panel captures movement")
	scene.close_panel()
	check(not scene.travel_from_gate(0), "Travel requires gate panel")
	scene.player = scene.GATE_POS + Vector2(0, 80)
	scene.interact_hub()
	check(scene.panel == "gate", "Nearby gate opens destinations")
	check(not scene.travel_from_gate(1), "Higher maps locked")
	check(scene.travel_from_gate(0) and scene.panel.is_empty(), "Travel through gate closes panel")
	check(scene.enemies.size() == 13 and not scene.hub, "Finite map population")
	check(not scene.enter_map(0), "Cannot restart active expedition")
	var enemy: Dictionary = scene.enemies[0]
	enemy.pos = scene.player + Vector2(55, 0)
	enemy.hp = 1
	scene.enemies[1].pos = scene.player - Vector2(55, 0)
	var rear_hp: float = scene.enemies[1].hp
	scene.facing = Vector2.RIGHT
	scene.attack()
	check(scene.kills == 1 and scene.enemies[0].hp == rear_hp, "Directional attack")
	check(scene.drops.size() == 1, "First kill guarantees equipment")
	scene.player = scene.drops[0].pos
	scene.pickup_nearby()
	check(scene.profile.inventory.size() == 1 and scene.drops.is_empty(), "Manual pickup into persistent inventory")
	var old_stats: Dictionary = scene.profile.stats()
	scene.equip_item(0)
	check(scene.profile.stats() == old_stats, "Equipment changes only at hub")
	var boss_index: int = scene.enemies.size() - 1
	scene.defeat_enemy(boss_index)
	check(scene.map_cleared and scene.profile.unlocked == 2 and not scene.hub, "Boss unlocks next map without forcing exit")
	check(scene.drops[-1].item.rarity == 2, "Boss guarantees rare loot")
	scene.player = scene.drops[-1].pos
	scene.pickup_nearby()
	var saved_count: int = scene.profile.inventory.size()
	var saved_xp: int = scene.profile.xp
	scene.return_to_hub()
	check(scene.profile.inventory.size() == saved_count and scene.profile.xp == saved_xp, "Return keeps items and XP")
	var item: Dictionary = scene.profile.inventory[0].duplicate()
	var old_equipped: Dictionary = scene.profile.equipment[item.slot].duplicate()
	scene.equip_item(0)
	check(scene.profile.equipment[item.slot] == item, "Equip looted item")
	check(old_equipped.is_empty() or old_equipped in scene.profile.inventory, "Old equipment returns to stash")
	var improved: Dictionary = scene.profile.stats()
	check(improved.attack > old_stats.attack or improved.health > old_stats.health, "Gear improves character")
	check(scene.enter_map(1) and scene.profile.stats() == improved, "New expedition keeps gear stats")
	scene.player = Vector2(180, 750)
	scene.return_time = 0.01
	scene.step(0.02)
	check(scene.hub, "Town portal completes outside combat")
	scene.enter_map(0)
	scene.enemies[0].pos = scene.player
	scene.return_time = 2
	scene.step(0.016)
	check(scene.return_time == 0 and scene.hp < scene.max_hp, "Damage interrupts portal")
	scene.invincible = 0
	scene.hp = 1
	scene.step(0.016)
	check(scene.ended, "Death state")
	scene.return_to_hub(true)
	check(scene.profile.stats() == improved and scene.hp == scene.max_hp, "Death recovery keeps progression")
	check(scene.player == scene.HUB_SPAWN and scene.panel.is_empty(), "Return resets town spawn and panels")
	# Fill more than one grid page and exercise real cell routing.
	for i in range(30):
		scene.profile.inventory.append(scene.profile.roll_item(1))
	scene.player = scene.STASH_POS + Vector2(0, 80)
	scene.interact_hub()
	var count: int = scene.profile.inventory.size()
	var stored: Dictionary = scene.profile.inventory[0].duplicate()
	scene.panel_mouse(scene.grid_rect(0).get_center(), MOUSE_BUTTON_LEFT, true)
	check(scene.profile.stash.size() == 1 and scene.profile.inventory.size() == count - 1, "Shift-click stores without losing items")
	check(scene.hovered_item(scene.grid_rect(0, true).get_center()).item == stored, "Stash hover resolves item")
	scene.panel_mouse(scene.grid_rect(0, true).get_center(), MOUSE_BUTTON_LEFT, false)
	check(scene.profile.stash.is_empty() and scene.profile.inventory[-1] == stored, "Click withdraws item")
	scene.change_page(false, 1)
	check(scene.page == 1, "Grid pagination")
	var later: Dictionary = scene.profile.inventory[24]
	check(scene.hovered_item(scene.grid_rect(0).get_center()).item == later, "Hover respects current page")
	check(scene.hovered_item(scene.grid_rect(23).get_center()).is_empty(), "Empty grid cells have no tooltip")
	scene.panel_mouse(scene.grid_rect(0).get_center(), MOUSE_BUTTON_LEFT, true)
	check(scene.profile.stash[0] == later, "Page two routes to correct item")
	for point in [Vector2.ZERO, Vector2(1151, 719), Vector2(600, 600)]:
		check(Rect2(0, 0, 1152, 720).encloses(scene.tooltip_rect(point)), "Tooltip stays on screen")
	scene.close_panel()
	var inventory_key := InputEventKey.new()
	inventory_key.keycode = KEY_I
	inventory_key.pressed = true
	scene.enter_map(0)
	scene._unhandled_input(inventory_key)
	check(scene.panel == "inventory", "Inventory opens during exploration")
	standing = scene.player
	Input.action_press("right")
	scene._process(0.1)
	Input.action_release("right")
	check(scene.player == standing, "Inventory pauses expedition")
	scene.panel_mouse(scene.grid_rect(0).get_center(), MOUSE_BUTTON_LEFT, false)
	check(scene.profile.stats() == improved, "Inventory cannot equip during expedition")
	scene.return_to_hub()
	# A separate test save never touches the real character.
	var path := "user://smoke_character.json"
	check(scene.profile.save_to(path), "Save character")
	var loaded = Profile.new()
	check(loaded.load_from(path), "Load character")
	check(loaded.stats() == improved and loaded.inventory == scene.profile.inventory and loaded.unlocked == 2 and loaded.stash == scene.profile.stash, "Save round trip including stash")
	var legacy := {"version": 1, "inventory": scene.profile.inventory, "equipment": scene.profile.equipment, "level": scene.profile.level, "xp": scene.profile.xp, "unlocked": scene.profile.unlocked}
	var legacy_file := FileAccess.open(path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	check(loaded.load_from(path) and loaded.stash.is_empty() and loaded.inventory == scene.profile.inventory, "Version 1 migration retains owned gear")
	var invalid := FileAccess.open(path, FileAccess.WRITE)
	invalid.store_string('{"version":1,"inventory":[],"equipment":{},"level":1,"xp":0,"unlocked":1}')
	invalid.close()
	check(not loaded.load_from(path) and loaded.stats() == improved, "Malformed save rejected without mutating profile")
	DirAccess.remove_absolute(path)
	# Exercise panels as well as hub, expedition, pause, and death draw paths.
	for mode in ["inventory", "stash", "gate", ""]:
		scene.panel = mode
		scene.queue_redraw()
		await process_frame
	scene.queue_redraw()
	await process_frame
	scene.enter_map(2) # Locked: should remain in hub.
	check(scene.hub, "Final map remains locked")
	scene.enter_map(1)
	scene.queue_redraw()
	await process_frame
	scene.paused = true
	scene.queue_redraw()
	await process_frame
	scene.paused = false
	scene.ended = true
	scene.queue_redraw()
	await process_frame
	scene.queue_free()
	if not failed:
		print("PASS: hub -> map -> combat -> loot -> boss -> return -> equip -> next map; persistence and recovery")
	quit(1 if failed else 0)
