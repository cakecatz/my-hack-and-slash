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
	seed(2026)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	check(not scene.enter_map(2, true), "Abyss cannot bypass story")
	# Combat geometry, healing and seal protection use the real attack path.
	scene.enter_map(0)
	var boss: Dictionary = scene.enemies[-1]
	var boss_hp: float = boss.hp
	check(not scene.hit_enemy(scene.enemies.size() - 1, 100000) and boss.hp == boss_hp, "Guardian immune before seal breaks")
	scene.enemies.clear()
	for style in range(3):
		scene.profile.stance = style
		scene.facing = Vector2.RIGHT
		scene.spawn_enemy(scene.player + Vector2(-70, 0))
		scene.spawn_enemy(scene.player + Vector2(300, 0))
		var rear: float = scene.enemies[0].hp
		var front: float = scene.enemies[1].hp
		scene.attack()
		check((scene.enemies[0].hp < rear) == (style == 1), "Only nova hits behind")
		check((scene.enemies[1].hp < front) == (style == 2), "Only lance reaches ranged target")
		scene.enemies.clear()
	scene.profile.support = 2
	scene.hp = scene.max_hp / 2
	var health: float = scene.hp
	scene.attack()
	check(scene.hp == health, "Siphon cannot heal by attacking air")
	scene.spawn_enemy(scene.player + Vector2(60, 0))
	scene.attack()
	check(scene.hp > health, "Siphon heals once on a landed attack")
	scene.heat = 100
	scene.return_time = 2
	scene.ember_burst()
	check(scene.heat == 0 and scene.return_time == 0, "Burst consumes heat and interrupts portal")
	scene.enemies.clear()
	scene.invincible = 0
	scene.hp = scene.max_hp
	scene.add_hazard(scene.player, 100, 20, 0.05)
	scene.step(0.06)
	check(scene.hp < scene.max_hp and scene.hazards.is_empty(), "Telegraph resolves after delay")
	scene.invincible = 1
	health = scene.hp
	scene.add_hazard(scene.player, 100, 20, 0.05)
	scene.step(0.06)
	check(scene.hp == health, "Dodge immunity prevents hazard damage")
	scene.return_to_hub()
	scene.profile.support = 0
	# Clear all nine expeditions; earlier chapters cannot advance current chapter.
	for mission in range(9):
		check(scene.enter_map(mission / 3), "Enter current campaign expedition")
		check(scene.mission == mission, "Mission tracks chapter progress")
		for i in range(scene.enemies.size() - 2, -1, -1):
			scene.hit_enemy(i, 100000)
		check(scene.kills >= scene.seal_required, "Finite population can break seal")
		scene.hit_enemy(0, 100000)
		check(scene.map_cleared and scene.profile.campaign == mission + 1, "Boss advances story exactly once")
		check(scene.drops[-1].item.rarity == 2, "Guardian has guaranteed rare")
		if (mission + 1) % 3 == 0:
			check(not scene.celebration.is_empty(), "Chapter has completion screen")
		scene.return_to_hub()
		if mission == 3:
			scene.enter_map(0)
			for i in range(scene.enemies.size() - 2, -1, -1):
				scene.hit_enemy(i, 100000)
			scene.hit_enemy(0, 100000)
			check(scene.profile.campaign == 4, "Replay cannot skip story")
			scene.return_to_hub()
	check(scene.profile.inventory.filter(func(item: Dictionary) -> bool: return item.name in ["Warden's Oath", "Sentinel's Memory", "Tyrant's Last Ember"]).size() == 3, "Chapter relics delivered directly")
	# Crafting is bounded; talent allocation and refund preserve stat accounting.
	var profile = scene.profile
	profile.embers = 10000
	var attack: int = profile.stats().attack
	for i in range(3):
		check(profile.upgrade("weapon"), "Upgrade succeeds within rank cap")
	var balance: int = profile.embers
	check(not profile.upgrade("weapon") and profile.embers == balance and profile.stats().attack > attack, "Max forge rank cannot consume currency")
	check(not profile.upgrade("charm"), "Empty slot cannot be upgraded")
	check(profile.spend_talent(0), "Earned talent can be spent")
	scene.panel = "build"
	scene.build_click(scene.build_tab_rect(1).get_center())
	scene.build_click(Rect2(144, 550, 270, 40).get_center())
	check(profile.talents == [0, 0, 0], "Build UI refunds talents")
	var count: int = profile.inventory.size()
	check(profile.salvage(0) and profile.inventory.size() == count - 1 and profile.embers > balance, "Salvage exchanges owned gear for embers")
	# Gate restrictions and every endgame depth, with rewards and final ending.
	scene.panel = "gate"
	scene.player = scene.GATE_POS
	for depth in range(1, 6):
		scene.contract = 2
		check(scene.enter_abyss() and scene.run_depth == depth, "Enter unlocked Abyss depth")
		check(scene.loot_tier() == depth + 4, "Danger contract increases loot tier")
		for i in range(scene.enemies.size() - 2, -1, -1):
			scene.hit_enemy(i, 100000)
		scene.hit_enemy(0, 100000)
		check(profile.campaign == 9 and profile.depth == mini(5, depth + 1), "Abyss advances without corrupting story")
		scene.player = scene.drops[-1].pos
		scene.pickup_nearby()
		scene.return_to_hub()
		scene.panel = "gate"
		scene.player = scene.GATE_POS
	check(profile.abyss_complete, "Depth five records final victory")
	scene.panel_mouse(Vector2(800, 250), MOUSE_BUTTON_LEFT, false)
	check(scene.selected_depth == 1 and scene.enter_abyss() and scene.run_depth == 1, "Gate can select a lower unlocked depth")
	scene.return_to_hub(true)
	check(profile.depth == 5 and profile.abyss_complete, "Failed replay retains highest depth and victory")
	profile.support = 1
	profile.stance = 2
	profile.spend_talent(2)
	profile.play_seconds = 1234.5
	var path := "/tmp/ember_journey_%d.json" % OS.get_process_id()
	check(profile.save_to(path), "Save full endgame profile")
	var restored = Profile.new()
	check(restored.load_from(path), "Load full endgame profile")
	check(restored.campaign == 9 and restored.depth == 5 and restored.abyss_complete and restored.support == 1 and restored.stance == 2 and restored.talents == profile.talents and restored.inventory == profile.inventory and restored.embers == profile.embers and restored.play_seconds == 1234.5, "All new fields and high tier loot survive reload")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.talents = [100, 0, 0]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(not restored.load_from(path) and restored.campaign == 9, "Invalid new fields rejected atomically")
	data = {"version": 2, "inventory": [], "stash": [], "equipment": Profile.new().equipment, "level": 1, "xp": 0, "unlocked": 3}
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(restored.load_from(path) and restored.campaign == 6 and restored.depth == 1 and restored.support == 0 and not restored.abyss_complete, "Version two migrates unlocked chapters and clears newer state")
	DirAccess.remove_absolute(path)
	scene.queue_free()
	if not failed:
		print("PASS: nine missions, five abyss depths, builds, telegraphs, forging, salvage, endings, v2 migration and current saves")
	quit(1 if failed else 0)
