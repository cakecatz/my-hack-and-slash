extends SceneTree
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, title: String) -> void:
	if not ok:
		failed = true
		push_error("FAIL: " + title)
func fresh(scene: Node) -> void:
	if not scene.hub:
		scene.return_to_hub()
	scene.enter_map(0)
	scene.player = scene.shrine.position
	scene.interact_field()
func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	# Force the deterministic first layout so hard-coded coordinates stay valid.
	scene.layout_template = 0
	scene.layout_flip = 0
	check(not scene.choose_shrine(0), "Cannot choose in hub")
	fresh(scene)
	check(scene.panel == "shrine" and scene.shrine.choice == -1, "Nearby shrine opens optional offer")
	var start: Vector2 = scene.player
	Input.action_press("right")
	scene._process(0.1)
	Input.action_release("right")
	check(scene.player == start, "Offer panel pauses combat")
	check(not scene.choose_shrine(-1) and not scene.choose_shrine(3), "Invalid offer rejected")
	scene.close_panel()
	check(scene.shrine.choice == -1 and not scene.choose_shrine(0), "Decline has no effect and panel is required")
	scene.interact_field()
	scene.player += Vector2(500, 0)
	check(not scene.choose_shrine(0), "Remote acceptance rejected")
	scene.player = start
	var base: Dictionary = scene.profile.combat_stats()
	var stats: Dictionary = scene.profile.stats()
	scene.panel_mouse(scene.shrine_card(0).get_center(), MOUSE_BUTTON_LEFT, false)
	check(scene.shrine.choice == 0 and scene.panel.is_empty() and scene.attack_blocked, "Card selects once and blocks held attack")
	check(is_equal_approx(scene.expedition_combat().damage, base.damage * 1.25) and scene.profile.stats() == stats and scene.profile.combat_stats() == base, "Oath modifies live combat without changing saved character")
	check(not scene.choose_shrine(1), "Cannot stack or swap contracts")
	scene.enemies.clear()
	scene.player = Vector2(2000, 750)
	scene.facing = Vector2.RIGHT
	scene.spawn_enemy(scene.player + Vector2(60, 0))
	var enemy: Dictionary = scene.enemies[0]
	enemy.hp = 10000.0
	var hp: float = enemy.hp
	scene.attack()
	check(is_equal_approx(hp - enemy.hp, base.damage * 1.25), "Actual normal hit matches boosted preview")
	scene.hp = 1
	var potions: int = scene.potions
	check(scene.use_potion() and is_equal_approx(scene.hp, 1 + scene.max_hp * 0.25) and scene.potions == potions - 1, "Potion cost applied to actual healing")
	scene.heat = 100
	hp = enemy.hp
	scene.ember_burst()
	check(is_equal_approx(hp - enemy.hp, scene.damage * 4 * (1 + scene.profile.rune_bonus())), "Oath does not boost burst")
	scene.return_to_hub()
	check(scene.shrine.choice == -1 and scene.expedition_combat() == base, "Returning clears pact")
	fresh(scene)
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_2
	scene._unhandled_input(event)
	check(scene.shrine.choice == 1 and scene.heat_per_hit() == 18, "Keyboard choice applies ember heat multiplier")
	scene.enemies.clear()
	scene.player = Vector2(2000, 750)
	scene.facing = Vector2.RIGHT
	for i in range(3):
		scene.spawn_enemy(scene.player + Vector2(50 + i * 5, 0))
	scene.attack()
	check(scene.heat == 18, "Pack hit gains heat once per attack")
	scene.heat = 95
	scene.attack()
	check(scene.heat == 100, "Boosted heat respects cap")
	scene.invincible = 0
	scene.hp = scene.max_hp
	hp = scene.hp
	scene.take_hit(20)
	check(is_equal_approx(hp - scene.hp, 20 * 1.15 * 100 / (100 + scene.armor * 5)), "Incoming damage multiplier composes with armor")
	scene.hp = 1
	scene.invincible = 0
	scene.take_hit(10000)
	check(scene.ended and scene.shrine.choice == -1, "Death clears active contract")
	fresh(scene)
	enemy = scene.enemies[0]
	enemy.hp *= 0.4
	hp = enemy.hp
	var maximum: float = enemy.max_hp
	check(scene.choose_shrine(2), "Greed accepted before boss combat")
	check(is_equal_approx(enemy.hp, hp * 1.25) and is_equal_approx(enemy.max_hp, maximum * 1.25) and is_equal_approx(enemy.hp / enemy.max_hp, 0.4), "Greed preserves wounded enemy health ratio")
	scene.spawn_enemy(Vector2(2000, 750))
	check(is_equal_approx(scene.enemies[-1].max_hp, (72.0 * (2 if scene.enemies[-1].kind == 2 else 1)) * 1.25), "Future spawns get greed penalty exactly once")
	scene.player = scene.trial.position
	scene.interact_field()
	check(scene.start_trial(0), "Cache can be challenged after choosing a pact")
	for guard in scene.enemies:
		if guard.get("trial_guard", false):
			# Original kind may be changed to ranged by the cache; compare the other guards.
			check(guard.max_hp >= 72.0 * 1.25 * 1.6, "Future cache guards include pact and encounter scaling")
	var before: int = scene.profile.inventory.size()
	scene.seal_required = 0
	for i in range(scene.enemies.size()):
		if scene.enemies[i].brute:
			scene.hit_enemy(i, 100000)
			break
	check(scene.map_cleared and scene.profile.inventory.size() == before + 1 and scene.profile.inventory[-1].rarity == 2 and scene.profile.inventory[-1].favorite, "Guardian awards one extra protected Rare directly")
	check(not scene.shrine.claim_reward(), "Bonus cannot pay twice")
	check(scene.drops[-1].item.rarity == 2, "Normal guardian drop preserved")
	fresh(scene)
	var boss: Dictionary = scene.enemies[-1]
	boss.aggro = true
	check(not scene.choose_shrine(2), "Cannot buy bonus after boss engagement")
	boss.aggro = false
	boss.hp -= 1
	check(not scene.choose_shrine(2), "Disengaging wounded boss cannot bypass restriction")
	boss.hp = boss.max_hp
	scene.map_cleared = true
	check(not scene.choose_shrine(2), "No pact after boss death")
	scene.return_to_hub()
	# Every layout can reach the shrine; it does not block or overlap the treasure choice.
	for chapter in range(3):
		for mission in range(3):
			scene.layout.build(chapter, mission)
			check(scene.layout.can_stand(scene.shrine.position, 18) and not scene.layout.path(Vector2(180, 750), scene.shrine.position).is_empty() and scene.shrine.position.distance_to(scene.layout.cache) > 200, "Shrine reachable and distinct from cache in all layouts")
	scene.queue_free()
	await process_frame
	if not failed:
		print("PASS: shrine choices, restrictions, damage, healing, heat, enemy scaling, protected reward and lifecycle")
	quit(1 if failed else 0)
