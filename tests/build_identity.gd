extends SceneTree

const Profile = preload("res://scripts/profile.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)

func target(scene: Node, offset: Vector2, boss: bool = false) -> Dictionary:
	scene.spawn_enemy(scene.player + offset, boss)
	var enemy: Dictionary = scene.enemies[-1]
	enemy.hp = 10000.0
	enemy.max_hp = enemy.hp
	enemy.elite_mod = -1
	enemy.kind = 3 if boss else 0
	enemy.speed = 100.0
	return enemy

func reset(scene: Node) -> void:
	scene.player = Vector2(2000, 750)
	scene.profile = Profile.new()
	scene.enemies.clear()
	scene.hazards.clear()
	scene.drops.clear()
	scene.seal_required = 0
	scene.cleave_chain = 0
	scene.heat = 0
	scene.kills = 0
	scene.celebration = ""
	scene.facing = Vector2.RIGHT
	scene.refresh_stats()

func run() -> void:
	seed(901)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	# Force the deterministic first layout so hard-coded coordinates stay valid.
	scene.layout_template = 0
	scene.layout_flip = 0
	scene.enter_map(0)
	reset(scene)
	scene.profile.equipment.weapon = scene.profile.make_relic(0, 1)
	var hit: float = scene.profile.combat_stats().damage
	var front := target(scene, Vector2(60, 0))
	var far := target(scene, Vector2(270, 0))
	var rear := target(scene, Vector2(-60, 0))
	scene.attack()
	scene.attack()
	check(far.hp == 10000 and scene.cleave_chain == 2, "Cleave wave requires two prior landed attacks")
	scene.attack()
	check(is_equal_approx(front.hp, 10000 - hit * 3) and is_equal_approx(far.hp, 10000 - hit * 0.75) and rear.hp == 10000, "Third attack adds a forward wave without duplicate damage")
	check(scene.cleave_chain == 0 and scene.wave_flash > 0, "Wave resets charge and has visual feedback")
	scene.enemies.clear()
	scene.cleave_chain = 2
	scene.attack()
	check(scene.cleave_chain == 2, "Air attacks cannot charge or spend the wave")
	scene.profile.equipment.weapon = {}
	far = target(scene, Vector2(270, 0))
	scene.attack()
	check(far.hp == 10000 and scene.cleave_chain == 0, "Unequipping disables relic behavior")
	reset(scene)
	scene.profile.stance = 1
	scene.profile.equipment.armor = scene.profile.make_relic(1, 2)
	var pulled := target(scene, Vector2(210, 0))
	var boss := target(scene, Vector2(210, 0), true)
	far = target(scene, Vector2(300, 0))
	scene.attack()
	check(is_equal_approx(pulled.pos.distance_to(scene.player), 120) and pulled.hp < 10000, "Nova pulls before resolving its hit")
	check(is_equal_approx(boss.pos.distance_to(scene.player), 210) and far.hp == 10000, "Pull respects boss immunity and maximum range")
	reset(scene)
	scene.profile.stance = 2
	scene.profile.equipment.charm = scene.profile.make_relic(2, 3)
	hit = scene.profile.combat_stats().damage
	front = target(scene, Vector2(60, 0))
	var left := target(scene, Vector2.RIGHT.rotated(deg_to_rad(-22)) * 300)
	var right := target(scene, Vector2.RIGHT.rotated(deg_to_rad(22)) * 300)
	scene.attack()
	check(is_equal_approx(front.hp, 10000 - hit), "Overlapping lance rays hit a target only once")
	check(is_equal_approx(left.hp, 10000 - hit * 0.6) and is_equal_approx(right.hp, 10000 - hit * 0.6), "Fork has two lower-damage side rays")
	reset(scene)
	scene.profile.equipment.weapon.affix = "scorch"
	scene.profile.equipment.armor.affix = "frost"
	front = target(scene, Vector2(60, 0))
	hit = scene.profile.combat_stats().damage
	scene.attack()
	check(front.burn_time == 2 and is_equal_approx(front.burn_dps, hit * 0.2) and is_equal_approx(front.slow_factor, 0.85), "Equipment effects apply on normal attacks")
	scene.update_enemy_statuses(0.5)
	check(is_equal_approx(front.hp, 10000 - hit * 1.1), "Burn deals time-scaled damage")
	scene.attack()
	check(is_equal_approx(front.burn_dps, hit * 0.2), "Repeated hits refresh rather than infinitely stacking burn")
	scene.update_enemy_statuses(5.0)
	check(front.burn_time == 0 and front.slow_factor == 1.0, "Statuses expire even after a large timestep")
	front.hp = 1
	front.burn_time = 2.0
	front.burn_dps = 10.0
	scene.update_enemy_statuses(0.2)
	check(scene.enemies.is_empty() and scene.kills == 1, "Burn death awards the kill exactly once")
	scene.update_enemy_statuses(0.2)
	check(scene.kills == 1, "Expired burn cannot award duplicate kill")
	boss = target(scene, Vector2(60, 0), true)
	scene.seal_required = 100
	scene.attack()
	check(boss.hp == 10000 and boss.burn_time == 0 and boss.slow_time == 0, "Sealed bosses reject status application")
	reset(scene)
	scene.profile.equipment.weapon.affix = "charge"
	for i in range(4):
		target(scene, Vector2(50 + i * 5, 0))
	scene.attack()
	check(scene.heat == 16, "Charged gear grants heat once per swing, not once per target")
	reset(scene)
	front = target(scene, Vector2(80, 0))
	front.elite_mod = 0
	scene.hit_enemy(0, 100000)
	check(scene.hazards.size() == 1 and scene.hazards[0].time > 1.0, "Volatile elite death is telegraphed, not instant")
	reset(scene)
	front = target(scene, Vector2(250, 0))
	front.elite_mod = 1
	front.skill_cd = 0
	scene.step(0.01)
	check(scene.hazards.size() == 1 and scene.hazards[0].radius == 82, "Stormcaller creates an avoidable targeted hazard")
	reset(scene)
	front = target(scene, Vector2(250, 0))
	front.elite_mod = 2
	front.aggro = true
	scene.step(0.1)
	check(is_equal_approx(front.pos.distance_to(scene.player), 235.5), "Swift elite moves 45 percent faster")
	var profile = Profile.new()
	check(not profile.record_relic_hunt(0, 1), "Relic farming requires chapter completion")
	for i in range(3):
		profile.complete_mission(i)
	check(profile.inventory.size() == 1 and profile.inventory[0].rarity == 3 and profile.inventory[0].relic == "cleave_wave" and profile.inventory[0].favorite, "First chapter guarantees its protected skill relic")
	check(not profile.record_relic_hunt(0, 3) and not profile.record_relic_hunt(0, 3) and profile.record_relic_hunt(0, 3), "Three repeats guarantee another relic")
	check(profile.inventory[-1].tier == 3 and profile.relic_hunts[0] == 0, "Repeat relic uses encounter tier and resets counter")
	profile.record_relic_hunt(0, 2)
	profile.equip(0)
	profile.inventory.append(profile.roll_item(2, true))
	var path := "/tmp/ember_identity_%d.json" % OS.get_process_id()
	profile.save_to(path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.has_relic("cleave_wave") and loaded.relic_hunts == [1, 0, 0] and loaded.inventory == profile.inventory, "Relics, affixes and hunt counter survive reload")
	for mutation in ["relic", "affix", "slot", "counter"]:
		var invalid := saved.duplicate(true)
		match mutation:
			"relic": invalid.equipment.weapon.relic = "unknown"
			"affix": invalid.inventory[-1].affix = "unknown"
			"slot": invalid.equipment.weapon.slot = "armor"
			"counter": invalid.relic_hunts = [3, 0, 0]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid))
		file.close()
		check(not loaded.load_from(path) and loaded.relic_hunts == [1, 0, 0], "Invalid new data rejected atomically")
	var legacy := saved.duplicate(true)
	legacy.version = 5
	legacy.erase("relic_hunts")
	# Pre-v8 saves predate the link system: 3 skills and per-support levels.
	legacy.erase("supports")
	legacy.skill_levels = [legacy.skill_levels[0], legacy.skill_levels[1], legacy.skill_levels[2]]
	legacy.skill_xp = [legacy.skill_xp[0], legacy.skill_xp[1], legacy.skill_xp[2]]
	legacy.support_levels = [1, 1, 1]
	legacy.support_xp = [0, 0, 0]
	legacy.support = 0
	legacy.talents = [legacy.talents[0], legacy.talents[1], legacy.talents[2]]
	# Old gear retains its old stats rather than silently changing item identity.
	legacy.equipment.weapon = Profile.new().equipment.weapon
	legacy.inventory = []
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check(loaded.load_from(path) and loaded.relic_hunts == [0, 0, 0] and loaded.campaign == 3 and not loaded.has_relic("cleave_wave"), "Version five migration retains progress and starts hunt counters at zero")
	DirAccess.remove_absolute(path)
	# Exercise the actual boss-reward route, including the existing Rare drop.
	scene.return_to_hub()
	scene.profile = Profile.new()
	scene.profile.campaign = 3
	scene.profile.unlocked = 2
	for i in range(3):
		scene.enter_map(0)
		scene.seal_required = 0
		scene.hit_enemy(scene.enemies.size() - 1, 100000)
		check(scene.drops[-1].item.rarity == 2, "Relic farming retains the normal guaranteed Rare")
		scene.return_to_hub()
	check(scene.profile.inventory.size() == 1 and scene.profile.inventory[0].relic == "cleave_wave" and scene.profile.campaign == 3, "Real repeat bosses award the target relic without advancing story")
	scene.queue_free()
	if not failed:
		print("PASS: relic combat geometry, non-overlap, equipment statuses, elite mechanics, deterministic hunts and v6 saves")
	quit(1 if failed else 0)
