extends SceneTree
const Layout = preload("res://scripts/expedition_layout.gd")
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)
func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.profile.unlocked = 3
	for chapter in range(3):
		for expedition in range(3):
			seed(340 + chapter * 3 + expedition)
			scene.profile.campaign = chapter * 3 + expedition
			scene.enter_map(chapter)
			var terrain = scene.layout
			check(terrain.rooms.size() == 6, "Six room types in every expedition")
			terrain.update_flow(scene.player)
			check(terrain.distances.size() == terrain.walkable.size(), "All navigation cells connected to arrival")
			for destination in [terrain.cache, terrain.seals[0], terrain.seals[1], Vector2(2130, 750)]:
				var path: PackedVector2Array = terrain.path(scene.player, destination)
				check(path.size() > 1, "Cache, both seals and boss reachable")
				var point: Vector2 = scene.player
				for waypoint in path:
					point = terrain.move_body(point, waypoint - point, 32)
					check(point.distance_to(waypoint) < 0.1, "Boss-sized body fits the full route")
			for enemy in scene.enemies:
				check(terrain.can_stand(enemy.pos, enemy.radius), "Every enemy spawns outside walls")
				check(not terrain.path(scene.player, enemy.pos).is_empty(), "Every guard has a reachable floor cell")
			var count: int = scene.seal_required
			for i in range(scene.enemies.size() - 1, -1, -1):
				if not scene.enemies[i].brute and scene.enemies[i].get("seal_guard", -1) < 0:
					scene.hit_enemy(i, 100000)
			check(scene.seal_required == count, "Optional kills do not substitute for seal defenders")
			for seal in range(2):
				for i in range(scene.enemies.size() - 1, -1, -1):
					if scene.enemies[i].get("seal_guard", -1) == seal:
						scene.hit_enemy(i, 100000)
				check(scene.seal_guards[seal] == 0, "Each seal breaks after its own guards")
				if seal == 0:
					var boss: Dictionary = scene.enemies[-1]
					var health: float = boss.hp
					scene.hit_enemy(scene.enemies.size() - 1, 100000)
					check(boss.hp == health and scene.seal_required > 0, "One seal alone cannot unlock boss")
			check(scene.seal_required == 0 and scene.navigation_target().brute, "Both seals route to guardian")
			scene.hit_enemy(0, 100000)
			check(scene.map_cleared and scene.trial.state == 0, "Vault encounter remains optional for progression")
			scene.return_to_hub()
	scene.profile.campaign = 0
	scene.enter_map(0)
	var terrain = scene.layout
	var point := Vector2(880, 660)
	var across := Vector2(1040, 660)
	check(not terrain.segment_clear(point, across), "Pillar blocks sight and attacks")
	var stopped: Vector2 = terrain.move_body(point, Vector2(800, 0), 18, false)
	check(stopped.x < 902 and terrain.can_stand(stopped, 18), "Large dash step cannot tunnel through pillar")
	var slid: Vector2 = terrain.move_body(point, Vector2(160, 180), 18)
	check(slid.y > 800 and terrain.can_stand(slid, 18), "Diagonal movement slides past corner")
	for radius in [16.0, 21.0, 32.0]:
		var pursuer := point
		for i in range(600):
			pursuer = terrain.chase(pursuer, across, radius, 4)
		check(pursuer.distance_to(across) < 5, "All enemy sizes route around a pillar")
		pursuer = terrain.cache
		for i in range(1600):
			pursuer = terrain.chase(pursuer, Vector2(1500, 780), radius, 4)
		check(pursuer.distance_to(Vector2(1500, 780)) < 5, "Vault guards traverse narrow branch and return to main route")
	scene.enemies.clear()
	scene.player = point
	scene.facing = Vector2.RIGHT
	scene.spawn_enemy(across)
	var enemy: Dictionary = scene.enemies[0]
	enemy.hp = 10000.0
	for skill in range(3):
		scene.profile.stance = skill
		scene.attack()
	check(enemy.hp == 10000, "All skills respect cover")
	scene.profile.equipment.armor = scene.profile.make_relic(1, 1)
	scene.profile.stance = 1
	scene.attack()
	check(enemy.pos == across, "Relic pull cannot pull through pillar")
	scene.heat = 100
	scene.ember_burst()
	check(enemy.hp == 10000, "Burst cannot pass through cover")
	enemy.kind = 1
	enemy.aggro = true
	enemy.skill_cd = 0
	scene.step(0.01)
	check(scene.hazards.is_empty(), "Ranged enemy cannot cast through pillar")
	scene.invincible = 0
	var health: float = scene.hp
	scene.add_hazard(across, 240, 100, 0.01)
	scene.step(0.02)
	check(scene.hp == health, "Explosion cover uses same wall geometry")
	# Two safe floor positions separated by a 40-pixel wall, within pickup range.
	scene.player = Vector2(1700, 600)
	var item: Dictionary = scene.profile.roll_item(1)
	scene.drops.assign([{"pos": Vector2(1780, 600), "item": item}])
	scene.pickup_nearby()
	scene.pickup_nearby(true)
	check(scene.drops.size() == 1, "Neither manual nor auto pickup crosses wall")
	scene.enemies.clear()
	scene.spawn_enemy(Vector2(1785, 600))
	enemy = scene.enemies[0]
	enemy.hp = 10000.0
	scene.facing = Vector2.RIGHT
	for skill in range(3):
		scene.profile.stance = skill
		scene.attack()
	check(enemy.hp == 10000, "Wall blocks all skills even within melee range")
	# Actual dash uses the shared collision path, including a frame spanning its duration.
	scene.player = point
	scene.dash_direction = Vector2.RIGHT
	scene.dash_time = 0.17
	scene.step(0.1)
	check(scene.player.x < 902, "In-game dodge stops at wall")
	scene.return_to_hub()
	scene.enter_map(0)
	check(scene.seal_guards[0] > 0 and scene.seal_guards[1] > 0, "New expedition resets both encounters")
	for i in range(scene.enemies.size() - 1, -1, -1):
		if scene.enemies[i].get("seal_guard", -1) >= 0:
			scene.hit_enemy(i, 100000)
	var survivors: int = scene.enemies.size()
	scene.hit_enemy(survivors - 1, 100000)
	check(scene.map_cleared and scene.enemies.size() == survivors - 1 and survivors > 1, "Boss clear leaves optional enemies alive")
	# Charge endpoint and summoned wards must remain on reachable floor near walls.
	scene.return_to_hub()
	scene.enter_map(0)
	scene.seal_required = 0
	var boss: Dictionary = scene.enemies[-1]
	boss.pos = Vector2(1800, 600)
	boss.cycle = 1
	scene.player = Vector2(1650, 600)
	scene.BossFight.begin_move(scene, boss)
	check(terrain.can_stand(boss.finish, boss.radius) and boss.finish.x >= 1792, "Boss charge warning stops at the wall")
	var hp: float = scene.hp
	scene.BossFight.step(scene, boss, 1.1)
	scene.BossFight.step(scene, boss, 0.45)
	check(terrain.can_stand(boss.pos, boss.radius) and scene.hp == hp, "Charge cannot cross wall or hit through it")
	scene.map_index = 1
	boss.state = "windup"
	boss.move = "stones"
	boss.timer = 0
	boss.pos = Vector2(1800, 330)
	scene.BossFight.step(scene, boss, 0.01)
	for stone in scene.boss_stones:
		check(terrain.can_stand(stone.pos, 22) and not terrain.path(scene.player, stone.pos).is_empty(), "Summoned wards stay reachable beside room walls")
	scene.queue_free()
	await process_frame
	if not failed:
		print("PASS: all room variants, connectivity, spawn clearance, two seals, optional vault, wall collision, cover and enemy navigation")
	quit(1 if failed else 0)
