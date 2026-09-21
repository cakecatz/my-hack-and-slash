extends SceneTree

const Profile = preload("res://scripts/profile.gd")
const Event = preload("res://scripts/expedition_event.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)

func gear(profile: RefCounted, rarity: int, favorite: bool = false) -> Dictionary:
	var item: Dictionary = profile.roll_item(1)
	item.rarity = rarity
	item.favorite = favorite
	return item

func run() -> void:
	seed(418)
	var profile = Profile.new()
	profile.inventory.assign([gear(profile, 0, true), gear(profile, 0), gear(profile, 1), gear(profile, 2)])
	var protected: Dictionary = profile.inventory[0]
	var balance: int = profile.embers
	check(not profile.salvage(0) and profile.embers == balance, "Single salvage respects favorite protection")
	check(profile.common_salvage_count() == 1 and profile.salvage_common() == 1 and profile.inventory.size() == 3 and protected in profile.inventory, "Bulk salvage keeps favorites, Magic and Rare")
	profile.sort_inventory()
	check(profile.inventory[0] == protected, "Sort places protected gear first")
	profile.equip(0)
	check(profile.equipment[protected.slot].favorite, "Favorite follows equipped item")
	profile.inventory.append(protected.duplicate())
	profile.transfer_item(profile.inventory.size() - 1, true)
	check(profile.stash[-1].favorite, "Stash preserves favorite flag")
	check(not profile.collect_item(gear(profile, 0), true), "Auto scrap converts Common")
	check(profile.collect_item(gear(profile, 0, true), true) and profile.collect_item(gear(profile, 2), true), "Auto scrap preserves favorites and Rare")
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.enter_map(0)
	check(not scene.start_trial(0), "Trial cannot bypass interaction panel")
	var initial_count: int = scene.enemies.size()
	var target: Dictionary = scene.navigation_target()
	check(not target.is_empty() and not target.brute, "Navigation avoids sealed guardian")
	scene.kills = scene.seal_required
	check(scene.navigation_target().brute, "Navigation points to unsealed guardian")
	scene.kills = 0
	scene.player = scene.trial.position
	scene.interact_field()
	check(scene.panel == "trial", "Nearby cursed cache opens reward choice")
	var pos: Vector2 = scene.player
	Input.action_press("right")
	scene._process(0.1)
	Input.action_release("right")
	check(scene.player == pos, "Reward choice pauses world")
	check(not scene.start_trial(-1), "Invalid reward index rejected")
	scene.player += Vector2(300, 0)
	check(not scene.start_trial(0), "Trial requires proximity")
	scene.player = scene.trial.position
	check(scene.start_trial(1) and scene.trial.reward_slot == "armor" and scene.trial.remaining == 4 and scene.enemies.size() == initial_count + 4, "Choice creates exactly four guards")
	check(not scene.start_trial(2), "Active trial cannot be retriggered")
	scene.hit_enemy(0, 100000)
	check(scene.trial.remaining == 4, "Unmarked kills do not count for trial")
	for i in range(scene.enemies.size() - 1, -1, -1):
		if scene.enemies[i].get("trial_guard", false):
			scene.hit_enemy(i, 100000)
	check(scene.trial.state == Event.State.COMPLETE and scene.profile.inventory.size() == 1, "Trial completion delivers one item directly")
	var reward: Dictionary = scene.profile.inventory[0]
	check(reward.slot == "armor" and reward.rarity == 2 and reward.tier == 2 and reward.rune == scene.profile.stance and reward.favorite, "Reward matches chosen slot, higher tier and current skill")
	check(scene.profile.embers >= 12 and not scene.profile.salvage(0), "Bonus currency and reward protection apply")
	scene.interact_field()
	check(scene.panel.is_empty() and not scene.trial.guard_defeated(), "Completed cache cannot pay twice")
	scene.return_to_hub()
	scene.enter_map(0)
	check(scene.trial.state == Event.State.SEALED, "New expedition resets optional event")
	scene.player = scene.trial.position
	scene.interact_field()
	scene.start_trial(2)
	var kept: int = scene.profile.inventory.size()
	scene.return_to_hub(true)
	check(scene.profile.inventory.size() == kept, "Abandoned trial grants no completion reward")
	# Pickup works through the real simulation loop, but never while paused or dead.
	scene.enter_map(0)
	scene.enemies.clear()
	scene.drops.clear()
	var common := gear(scene.profile, 0)
	scene.drops.append({"pos": scene.player, "item": common})
	scene.profile.loot_mode = 0
	scene._process(0.01)
	check(scene.drops.size() == 1, "Manual mode does not auto pickup")
	scene.profile.loot_mode = 1
	scene.paused = true
	scene._process(0.01)
	check(scene.drops.size() == 1, "Paused game cannot collect")
	scene.paused = false
	scene.panel = "inventory"
	scene._process(0.01)
	check(scene.drops.size() == 1, "Inventory pauses pickup")
	scene.close_panel()
	scene._process(0.01)
	check(scene.drops.is_empty() and common in scene.profile.inventory, "Auto pickup retains nearby Common in normal auto mode")
	scene.profile.loot_mode = 2
	balance = scene.profile.embers
	kept = scene.profile.inventory.size()
	scene.drops.append({"pos": scene.player, "item": gear(scene.profile, 0)})
	scene.drops.append({"pos": scene.player, "item": gear(scene.profile, 2)})
	scene.drops.append({"pos": scene.player + Vector2(400, 0), "item": gear(scene.profile, 0)})
	scene._process(0.01)
	check(scene.drops.size() == 1 and scene.profile.inventory.size() == kept + 1 and scene.profile.embers == balance + 1, "Auto scrap keeps Rare and leaves distant loot")
	scene.drops[0].pos = scene.player
	scene.ended = true
	scene._process(0.01)
	check(scene.drops.size() == 1, "Dead character cannot auto pickup")
	scene.ended = false
	scene.pickup_nearby()
	check(scene.drops.is_empty() and scene.profile.inventory.size() == kept + 2, "Manual pickup overrides auto scrap preference")
	scene.panel = "inventory"
	kept = scene.profile.inventory.size()
	scene.inventory_action(2)
	check(scene.profile.inventory.size() == kept, "Bulk salvage unavailable in combat")
	scene.return_to_hub()
	scene.panel = "inventory"
	scene.profile.inventory.assign([gear(scene.profile, 0), gear(scene.profile, 0), gear(scene.profile, 2)])
	scene.panel_mouse(scene.grid_rect(0).get_center(), MOUSE_BUTTON_MIDDLE, false)
	check(scene.profile.inventory[0].favorite, "Middle click protects hovered item")
	scene.panel_mouse(scene.inventory_action_rect(2).get_center(), MOUSE_BUTTON_LEFT, false)
	check(scene.profile.inventory.size() == 2 and scene.profile.inventory[0].favorite, "Bulk button respects protection")
	scene.inventory_action(0)
	check(scene.profile.loot_mode == 0, "Loot mode button cycles preference")
	var path := "/tmp/ember_qol_%d.json" % OS.get_process_id()
	scene.profile.save_to(path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.loot_mode == 0 and loaded.inventory == scene.profile.inventory, "Version five persists loot mode and protection")
	for mode in [-1, 3, 1.5, "bad"]:
		var invalid := saved.duplicate(true)
		invalid.loot_mode = mode
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid))
		file.close()
		check(not loaded.load_from(path) and loaded.loot_mode == 0, "Bad pickup setting rejected atomically")
	var invalid := saved.duplicate(true)
	invalid.inventory[0].favorite = "yes"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	check(not loaded.load_from(path), "Invalid item protection rejected")
	saved.version = 4
	saved.erase("loot_mode")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	check(loaded.load_from(path) and loaded.loot_mode == 1 and loaded.inventory == scene.profile.inventory, "Version four migrates to nondestructive auto pickup")
	DirAccess.remove_absolute(path)
	scene.queue_free()
	if not failed:
		print("PASS: cursed cache, target rewards, repeat protection, navigation, auto loot, salvage, favorites, v4 migration and v5 saves")
	quit(1 if failed else 0)
