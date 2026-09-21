extends SceneTree

const Profile = preload("res://scripts/profile.gd")
const Skills = preload("res://scripts/skill_catalog.gd")
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
	var profile = Profile.new()
	check(profile.gain_mastery(99).is_empty() and profile.skill_levels == [1, 1, 1], "XP below threshold does not level")
	check(profile.gain_mastery(1).size() == 2 and profile.skill_levels == [2, 1, 1] and profile.support_levels == [2, 1, 1] and profile.skill_xp[0] == 0, "Both equipped gems level at exact threshold")
	profile.stance = 1
	profile.gain_mastery(20)
	check(profile.skill_xp == [0, 20, 0] and profile.support_xp == [20, 0, 0], "Switching preserves progress and only active pair trains")
	profile.support = 1
	profile.gain_mastery(20)
	check(profile.support_xp[1] == 0, "Locked support cannot gain XP")
	profile.campaign = 3
	profile.unlocked = 2
	profile.gain_mastery(100)
	check(profile.support_levels[1] == 2, "Unlocked support can train independently")
	profile.gain_mastery(100000)
	profile.gain_mastery(100000)
	check(profile.skill_levels[1] == 10 and profile.support_levels[1] == 10 and profile.skill_xp[1] == 0 and profile.support_xp[1] == 0, "Large awards stop at max rank without overflow")
	var next: Dictionary = profile.combat_stats(1, 1, true, true)
	check(next == profile.combat_stats(1, 1), "Max rank preview remains capped")
	profile.equipment.weapon.rune = 2
	var lance: Dictionary = profile.combat_stats(2, 0)
	profile.equipment.weapon.erase("rune")
	check(is_equal_approx(lance.damage / profile.combat_stats(2, 0).damage, 1.12), "Candidate preview uses candidate rune affinity")
	# Gameplay uses the same damage, interval, range, and recovery as card previews.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.panel = "build"
	scene.build_click(scene.mastery_rect(true, 1).get_center())
	check(scene.profile.support == 0, "Locked card cannot equip")
	scene.build_click(scene.mastery_rect(false, 2).get_center())
	check(scene.profile.stance == 2, "Skill card equips from UI")
	scene.profile.campaign = 3
	scene.profile.unlocked = 2
	scene.build_click(scene.mastery_rect(true, 1).get_center())
	check(scene.profile.support == 1, "Unlocked support card equips")
	scene.close_panel()
	scene.enter_map(0)
	scene.enemies.clear()
	scene.profile.skill_levels[2] = 5
	scene.profile.support_levels[1] = 5
	scene.refresh_stats()
	var combat: Dictionary = scene.profile.combat_stats()
	scene.facing = Vector2.RIGHT
	scene.spawn_enemy(scene.player + Vector2(combat.reach + 10, 0))
	scene.enemies[0].hp = 10000
	var old_hp: float = scene.enemies[0].hp
	scene.attack()
	check(is_equal_approx(old_hp - scene.enemies[0].hp, combat.damage), "Actual hit matches preview and trained range")
	check(is_equal_approx(scene.attack_cooldown, combat.interval), "Echo's trained interval is applied")
	check(scene.profile.skill_xp[2] == 0, "Nonlethal hits do not farm mastery")
	scene.enemies[0].pos.x = scene.player.x + combat.reach + 100
	old_hp = scene.enemies[0].hp
	scene.attack()
	check(scene.enemies[0].hp == old_hp, "Targets outside trained range are not hit")
	scene.profile.support = 2
	scene.profile.support_levels[2] = 6
	scene.enemies[0].pos = scene.player + Vector2(60, 0)
	scene.hp = 10
	var expected: float = scene.max_hp * scene.profile.combat_stats().recovery
	scene.attack()
	check(is_equal_approx(scene.hp, 10 + expected), "Siphon heals trained amount on a landed attack")
	scene.enemies.clear()
	old_hp = scene.hp
	scene.attack()
	check(scene.hp == old_hp and scene.profile.skill_xp[2] == 0, "Air attacks grant neither healing nor XP")
	scene.profile.skill_xp[2] = Skills.xp_needed(5) - 8
	scene.profile.support_xp[2] = Skills.xp_needed(6) - 8
	scene.spawn_enemy(scene.player + Vector2(60, 0))
	scene.enemies[0].hp = 1
	scene.attack()
	check(scene.profile.skill_levels[2] == 6 and scene.profile.support_levels[2] == 7 and scene.mastery_time > 0, "Real kill trains selected pair and shows notification")
	scene.panel = "build"
	scene.build_click(scene.mastery_rect(false, 0).get_center())
	check(scene.profile.stance == 2, "Build cannot switch during expedition")
	scene.return_to_hub()
	var path := "/tmp/ember_mastery_%d.json" % OS.get_process_id()
	check(scene.profile.save_to(path), "Current version saves")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.skill_levels == scene.profile.skill_levels and loaded.support_levels == scene.profile.support_levels and loaded.skill_xp == scene.profile.skill_xp and loaded.support_xp == scene.profile.support_xp and loaded.combat_stats() == scene.profile.combat_stats(), "All mastery and combat stats round trip")
	for bad in [[0, 1, 1], [1, 11, 1], [1, 2.5, 1], [1, 1], [1, "bad", 1]]:
		var invalid := saved.duplicate(true)
		invalid.skill_levels = bad
		write_json(path, invalid)
		check(not loaded.load_from(path) and loaded.skill_levels == scene.profile.skill_levels, "Invalid skill levels rejected atomically")
	for bad in [[-1, 0, 0], [100000, 0, 0], [0.5, 0, 0]]:
		var invalid := saved.duplicate(true)
		invalid.support_xp = bad
		write_json(path, invalid)
		check(not loaded.load_from(path), "Invalid support XP rejected")
	var invalid := saved.duplicate(true)
	invalid.skill_levels = [10, 1, 1]
	invalid.skill_xp = [1, 0, 0]
	write_json(path, invalid)
	check(not loaded.load_from(path), "Max level cannot retain XP")
	var legacy := saved.duplicate(true)
	legacy.version = 3
	for key in ["skill_levels", "skill_xp", "support_levels", "support_xp"]:
		legacy.erase(key)
	write_json(path, legacy)
	check(loaded.load_from(path) and loaded.skill_levels == [1, 1, 1] and loaded.support_xp == [0, 0, 0] and loaded.campaign == scene.profile.campaign and loaded.stance == 2 and loaded.support == 2 and loaded.inventory == scene.profile.inventory, "V3 migration retains loadout and starts individual mastery at level one")
	DirAccess.remove_absolute(path)
	# Exercise both tabs under the drawing pipeline; visual QA covers all tooltips.
	scene.panel = "build"
	for tab in range(2):
		scene.build_click(scene.build_tab_rect(tab).get_center())
		scene.queue_redraw()
		await process_frame
	scene.queue_free()
	if not failed:
		print("PASS: individual mastery, cap, real combat, skill cards, locks, v3 migration, current persistence and invalid data")
	quit(1 if failed else 0)
