extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.spawn_wave()
	assert(scene.wave == 1 and scene.enemies.size() == 6, "First wave")
	scene.enemies.clear()
	scene.facing = Vector2.RIGHT
	var enemy = {"pos": scene.player + Vector2(55, 0), "hp": 20.0, "max_hp": 20.0, "radius": 15.0, "speed": 0.0, "damage": 10, "flash": 0.0, "brute": false}
	scene.enemies.append(enemy.duplicate())
	enemy.pos = scene.player - Vector2(55, 0)
	scene.enemies.append(enemy.duplicate())
	scene.attack()
	assert(scene.kills == 1 and scene.enemies.size() == 1, "Attack only hits facing arc")
	assert(scene.gems.size() == 1, "Enemy drops essence")
	scene.gems[0] = scene.player
	scene.xp = scene.xp_needed - 1
	scene.step(0.016)
	assert(scene.upgrade_pending and scene.level == 2, "Pickup triggers level up")
	var old_damage: float = scene.damage
	scene.choose_upgrade(0)
	assert(scene.damage == old_damage + 12 and not scene.upgrade_pending, "Damage upgrade")
	scene.choose_upgrade(2)
	assert(scene.max_hp == 125 and scene.hp == 125, "Vitality heals")
	scene.enemies[0].pos = scene.player
	scene.hp = 10
	scene.invincible = 1
	scene.step(0.016)
	assert(scene.hp == 10, "Invulnerability blocks contact damage")
	scene.invincible = 0
	scene.step(0.016)
	assert(scene.ended and not scene.won, "Lethal damage ends run")
	scene.enemies.clear()
	scene.ended = false
	scene.wave = 10
	scene.step(0.016)
	assert(scene.ended and scene.won, "Final wave victory")
	scene.queue_free()
	print("PASS: wave, directional attack, loot, level, upgrades, invulnerability, defeat, victory")
	quit()
