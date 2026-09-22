extends SceneTree
const BossFight = preload("res://scripts/boss_fight.gd")
var failed := false
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, title: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + title)
func boss_for(scene: Node, chapter: int) -> Dictionary:
	if not scene.hub:
		scene.return_to_hub()
	scene.profile.unlocked = 3
	scene.enter_map(chapter)
	var boss: Dictionary = scene.enemies[-1]
	scene.enemies.assign([boss])
	scene.seal_required = 0
	scene.player = Vector2(1800, 750)
	boss.pos = Vector2(2000, 750)
	boss.aggro = true
	boss.timer = 0
	return boss
func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	var boss := boss_for(scene, 0)
	scene.step(0.01)
	check(boss.state == "windup" and boss.move == "sweep", "Warden starts with a readable sweep")
	var sweep: Dictionary = scene.hazards[0]
	check(BossFight.contains(sweep, boss.pos + Vector2(-100, 0)) and not BossFight.contains(sweep, boss.pos + Vector2(100, 0)), "Sweep has a safe rear and dangerous front")
	scene.player = boss.pos + Vector2(70, 0)
	var hp: float = scene.hp
	scene.step(0.95)
	check(scene.hp == hp and boss.state == "recovery", "Standing behind avoids sweep and opens a punish window")
	scene.hazards.clear()
	boss.state = "approach"
	boss.timer = 0
	scene.player = boss.pos + Vector2(-200, 0)
	scene.step(0.01)
	check(boss.move == "charge" and scene.hazards[0].preview_only, "Charge line warns before moving")
	var start: Vector2 = boss.pos
	var finish: Vector2 = boss.finish
	scene.step(1.1)
	check(boss.state == "charge" and boss.pos == start, "Charge does not teleport during warning")
	scene.player = start.lerp(finish, 0.5)
	scene.invincible = 0
	hp = scene.hp
	scene.step(0.45)
	check(scene.hp < hp and boss.pos == finish and boss.state == "recovery" and boss.timer == 2, "Swept collision catches crossing path even in a large timestep")
	hp = scene.hp
	scene.player = boss.pos
	scene.invincible = 0
	scene.step(0.2)
	check(scene.hp == hp, "Boss has no contact damage during recovery")
	# The same charge can be dodged using the existing invulnerability path.
	boss.state = "charge"
	boss.timer = 0.45
	boss.pos = start
	boss.start = start
	boss.finish = finish
	boss.charge_hit = false
	scene.player = start.lerp(finish, 0.5)
	scene.invincible = 1
	scene.step(0.45)
	check(scene.hp == hp, "Dodge immunity prevents charge hit")
	boss = boss_for(scene, 1)
	scene.step(0.01)
	var beam: Dictionary = scene.hazards[0]
	check(boss.move == "beam" and BossFight.contains(beam, scene.player) and not BossFight.contains(beam, scene.player + Vector2(0, 80)), "Sentinel line shot has a sidestep escape")
	scene.hazards.clear()
	boss.state = "approach"
	boss.timer = 0
	scene.step(0.01)
	scene.step(1.0)
	check(scene.boss_stones.size() == 2 and BossFight.multiplier(scene, boss) == 0.7, "Sentinel stones reduce damage without granting immunity")
	var health: float = boss.hp
	scene.hit_enemy(0, 100)
	check(is_equal_approx(health - boss.hp, 70), "Ward reduction applies to actual damage")
	var kills: int = scene.kills
	var xp: int = scene.profile.xp
	scene.hit_stone(1, 100000)
	scene.hit_stone(0, 100000)
	check(scene.boss_stones.is_empty() and boss.state == "recovery" and boss.timer == 2.5 and boss.weak_time == 3, "Breaking both stones grants a safe exposed window")
	check(scene.kills == kills and scene.profile.xp == xp, "Stones cannot farm kills or experience")
	health = boss.hp
	scene.hit_enemy(0, 100)
	check(is_equal_approx(health - boss.hp, 135), "Exposed bonus applies to real damage")
	# All skills can damage stones through their normal attack geometry.
	for style in range(3):
		scene.profile.stance = style
		scene.facing = Vector2.RIGHT
		scene.boss_stones.assign([{"owner": boss.boss_id, "pos": scene.player + Vector2(60, 0), "hp": 10000.0, "max_hp": 10000.0}])
		scene.attack()
		check(scene.boss_stones[0].hp < 10000, "Each skill can break a stone")
	boss = boss_for(scene, 2)
	scene.step(0.01)
	var ring: Dictionary = scene.hazards[0]
	check(ring.shape == "ring" and boss.phase == 1, "Tyrant introduces ring on its own")
	check(not BossFight.contains(ring, ring.pos + ring.direction * 180) and BossFight.contains(ring, ring.pos - ring.direction * 180), "Green wedge is safe while opposite annulus is dangerous")
	check(not BossFight.contains(ring, ring.pos) and not BossFight.contains(ring, ring.pos + Vector2(500, 0)), "Ring respects inner and outer boundaries")
	scene.hazards.clear()
	boss.hp = boss.max_hp * 0.49
	boss.state = "approach"
	boss.timer = 0
	scene.step(0.01)
	check(boss.phase == 2 and boss.move == "marks" and scene.hazards.size() == 3, "Half health adds staggered marks")
	var targets: Array = scene.hazards.map(func(h: Dictionary) -> Vector2: return h.pos)
	scene.player += Vector2(300, 0)
	scene.step(0.1)
	check(scene.hazards.map(func(h: Dictionary) -> Vector2: return h.pos) == targets, "Marked attacks lock targets instead of chasing through windup")
	# Defeating the owner cancels every pending boss attack and ward.
	scene.boss_stones.append({"owner": boss.boss_id, "pos": boss.pos, "hp": 20.0, "max_hp": 20.0})
	scene.hit_enemy(0, 1000000)
	check(scene.hazards.is_empty() and scene.boss_stones.is_empty() and scene.map_cleared, "Boss death removes its attacks and stones")
	boss = boss_for(scene, 0)
	scene.seal_required = 100
	scene.step(1.0)
	check(boss.state == "approach" and scene.hazards.is_empty(), "Seal blocks new boss mechanics")
	scene.seal_required = 0
	scene.step(0.01)
	scene.panel = "inventory"
	var timer: float = boss.timer
	scene._process(0.5)
	check(boss.timer == timer, "Inventory pauses boss telegraphs")
	scene.return_to_hub()
	check(scene.hazards.is_empty() and scene.boss_stones.is_empty(), "Return clears transient encounter state")
	scene.queue_free()
	if not failed:
		print("PASS: three boss patterns, telegraph geometry, punish windows, dodge, stones, phase change and cleanup")
	quit(1 if failed else 0)
