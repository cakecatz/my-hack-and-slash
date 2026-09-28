extends SceneTree

const Profile = preload("res://scripts/profile.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func run() -> void:
	# Build presets store the skill, links and talents, and survive a reload.
	var profile = Profile.new()
	profile.level = 15
	profile.stance = 3
	profile.set_slot_links(0, ["multishot", "pierce"])
	profile.talents.assign([1, 2, 3, 4])
	check(profile.save_build(0), "A preset can be saved")
	check(profile.build_summary(0) == "EMBER BOLT / 2", "Preset summary shows the skill and link count")
	profile.stance = 0
	profile.set_slot_links(0, [])
	profile.talents.assign([0, 0, 0, 0])
	check(profile.load_build(0), "A saved preset can be loaded")
	check(profile.stance == 3 and profile.slot_link_ids(0) == ["multishot", "pierce"] and profile.talents == [1, 2, 3, 4], "Preset restores skill, links and talents")
	check(not profile.load_build(1), "An empty preset cannot be loaded")

	var path := "/tmp/ember_training_%d.json" % OS.get_process_id()
	check(profile.save_to(path), "Profile with presets saves")
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.builds[0].stance == 3 and loaded.builds[0].links[0].size() == 2 and loaded.builds[0].links[0][0].id == "multishot" and loaded.builds[0].talents == [1, 2, 3, 4], "Presets round trip")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for bad in [
		{"name": "x", "stance": 3, "links": [[{"id": "multishot", "tier": 3}, {"id": "multishot", "tier": 3}], [], [], [], []], "talents": [0, 0, 0, 0]},
		{"name": "x", "stance": 0, "links": [[{"id": "multishot", "tier": 3}], [], [], [], []], "talents": [0, 0, 0, 0]},
		{"name": "x", "stance": 9, "links": [[], [], [], [], []], "talents": [0, 0, 0, 0]},
		{"name": "x", "stance": 0, "links": [[], [], [], [], []], "talents": [0, 0, 0, 7]}
	]:
		var invalid := saved.duplicate(true)
		invalid.builds[1] = bad
		write_json(path, invalid)
		check(not loaded.load_from(path), "Invalid preset rejected")
	DirAccess.remove_absolute(path)

	# Training ground: dummies take damage but grant no progression.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.player = scene.TRAINING_POS + Vector2(0, 60)
	scene.interact_hub()
	check(scene.training and not scene.hub, "The training post opens the training ground")
	check(scene.enemies.size() == 6 and scene.enemies[0].get("dummy", false), "Training spawns six dummies")
	check(not scene.shrine_available(), "The bargain shrine is dormant in training")
	scene.profile.stance = 0
	scene.profile.skill_levels[0] = 5
	scene.refresh_stats()
	scene.facing = Vector2.RIGHT
	scene.player = scene.enemies[0].pos + Vector2(-60, 0)
	var before_xp: int = scene.profile.skill_xp[0]
	var before_embers: int = scene.profile.embers
	var before_hp: float = scene.enemies[0].hp
	scene.attack()
	check(scene.training_total > 0 and scene.training_hits >= 1, "Training records damage and hits")
	check(scene.enemies[0].hp < before_hp, "A dummy takes damage")
	check(scene.profile.skill_xp[0] == before_xp and scene.profile.embers == before_embers, "Training grants no mastery or embers")
	scene.return_to_hub()
	check(not scene.training and scene.hub, "Returning to town leaves training")

	# Builds can be changed inside the training ground but not during an expedition.
	scene.profile.level = 13
	scene.enter_training()
	scene.panel = ""
	var build_key := InputEventKey.new()
	build_key.keycode = KEY_B
	build_key.pressed = true
	scene._unhandled_input(build_key)
	check(scene.panel == "build", "B opens the build panel in the training ground")
	scene.build_tab = 0
	scene.slot_focus = 0
	scene.build_click(scene.skill_pool_rect(3).get_center())
	check(scene.profile.stance == 3, "The basic skill can change in the training ground")
	scene.slot_focus = 2
	scene.build_click(scene.skill_pool_rect(2).get_center())
	check(scene.profile.active_skill(1) == "lance", "Attack skills can fill an active slot in the training ground")
	scene.build_tab = 3
	scene.build_click(scene.passive_node_rect("def_hp").get_center())
	check(scene.profile.has_passive("def_hp"), "Passives can change in the training ground")
	scene.build_tab = 0
	scene.build_click(scene.build_tab_rect(4).get_center())
	check(scene.build_tab == 0, "Mod crafting cannot be opened in the training ground")
	scene.close_panel()
	scene.return_to_hub()
	scene.enter_map(0)
	scene.panel = ""
	scene._unhandled_input(build_key)
	check(scene.panel == "", "B does nothing during an expedition")
	scene.return_to_hub()

	# Equipment can be changed and salvaged in the training ground.
	scene.enter_training()
	scene.profile.inventory.clear()
	var gear: Dictionary = scene.profile.roll_item(2, true, "weapon")
	scene.profile.inventory.append(gear)
	var before_attack: int = scene.profile.stats().attack
	scene.equip_item(0)
	check(scene.profile.equipment.weapon == gear, "Equipment can be changed in the training ground")
	check(scene.profile.stats().attack != before_attack, "Equipping refreshes the character stats")
	scene.profile.inventory.clear()
	scene.profile.inventory.append(scene.profile.roll_item(1))
	var embers_before: int = scene.profile.embers
	scene.panel = "inventory"
	scene.panel_mouse(scene.grid_rect(0).get_center(), MOUSE_BUTTON_RIGHT, false)
	check(scene.profile.inventory.is_empty() and scene.profile.embers > embers_before, "Equipment can be salvaged in the training ground")
	scene.close_panel()
	scene.return_to_hub()

	# Equipment is locked during a real expedition.
	scene.enter_map(0)
	scene.profile.inventory.clear()
	scene.profile.inventory.append(scene.profile.roll_item(2, true, "armor"))
	var armor_before: String = scene.profile.equipment.armor.name
	scene.equip_item(0)
	check(scene.profile.equipment.armor.name == armor_before, "Equipment cannot change during an expedition")
	scene.return_to_hub()

	# The preset buttons save and load from the link board.
	scene.panel = "build"
	scene.profile.stance = 2
	scene.profile.set_slot_links(0, ["power"])
	scene.build_click(scene.preset_save_rect(0).get_center())
	check(not scene.profile.builds[0].is_empty(), "The preset save button stores the build")
	scene.profile.stance = 0
	scene.profile.set_slot_links(0, [])
	scene.build_click(scene.preset_load_rect(0).get_center())
	check(scene.profile.stance == 2 and scene.profile.has_support("power"), "The preset load button restores the build")
	scene.close_panel()
	scene.queue_redraw()
	await process_frame
	scene.queue_free()
	if not failed:
		print("PASS: build presets, preset persistence, training ground damage and no-progression")
	quit(1 if failed else 0)
