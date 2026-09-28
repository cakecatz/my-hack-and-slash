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

func support_index(id: String) -> int:
	for i in range(Skills.SUPPORTS.size()):
		if Skills.SUPPORTS[i].id == id:
			return i
	return -1

func run() -> void:
	var profile = Profile.new()
	check(profile.gain_mastery(99).is_empty() and profile.skill_levels == [1, 1, 1, 1, 1, 1, 1, 1], "XP below threshold does not level")
	check(profile.skill_xp[0] == 99 and profile.skill_xp[4] == 99, "Every equipped slot gains XP")
	var gained: Array = profile.gain_mastery(1)
	check(gained.size() == 5 and "CLEAVE Lv.2" in gained and "EMBER LANCE Lv.2" in gained and profile.skill_levels == [2, 1, 1, 1, 2, 2, 2, 2] and profile.skill_xp[0] == 0, "Every equipped skill levels at the exact threshold")
	profile.stance = 1
	profile.gain_mastery(20)
	check(profile.skill_xp[0] == 0 and profile.skill_xp[1] == 20, "Switching preserves progress and the newly equipped skill trains")
	profile.gain_mastery(100000)
	profile.gain_mastery(100000)
	check(profile.skill_levels[1] == 10 and profile.skill_xp[1] == 0, "Large awards stop at max rank without overflow")
	check(profile.combat_stats(1, true) == profile.combat_stats(1), "Max rank preview remains capped")
	profile.equipment.weapon.rune = 2
	var lance: Dictionary = profile.combat_stats(2)
	profile.equipment.weapon.erase("rune")
	check(is_equal_approx(lance.damage / profile.combat_stats(2).damage, 1.12), "Candidate preview uses candidate rune affinity")

	# Support slots unlock with the equipped skill's level.
	profile.stance = 0
	profile.skill_levels[0] = 1
	check(profile.support_slots() == 2, "Skill level one opens two support slots")
	profile.skill_levels[0] = 4
	check(profile.support_slots() == 3, "Skill level four opens a third slot")
	profile.skill_levels[0] = 7
	check(profile.support_slots() == 4, "Skill level seven opens a fourth slot")
	profile.skill_levels[0] = 10
	check(profile.support_slots() == 5, "Skill level ten opens the fifth slot")

	# Tag gating, duplicates and slot limits.
	profile.set_slot_links(0, [])
	check(profile.add_support(0, "wider"), "An area support links to an area skill")
	check(not profile.add_support(0, "multishot"), "A projectile support is rejected by an area skill")
	check(not profile.add_support(0, "wider"), "The same support cannot be linked twice")
	check(profile.add_support(0, "power") and profile.add_support(0, "haste") and profile.add_support(0, "ignite") and profile.add_support(0, "leech"), "Five supports fill the slot")
	check(not profile.add_support(0, "charged"), "A full link rejects another support")
	check(profile.set_stance(2) and profile.slot_link_ids(0) == ["power", "haste", "ignite", "leech"], "Switching skill prunes supports that no longer apply")
	check(profile.set_stance(0) and profile.slot_link_ids(0) == ["power", "haste", "ignite", "leech"], "Switching back keeps applicable supports")

	# Combat preview reflects supports.
	profile.set_slot_links(0, ["power"])
	var with_power: Dictionary = profile.combat_stats()
	profile.set_slot_links(0, [])
	var plain: Dictionary = profile.combat_stats()
	check(is_equal_approx(with_power.damage / plain.damage, 1.3) and is_equal_approx(with_power.interval / plain.interval, 1.1), "POWER trades speed for damage")
	profile.set_slot_links(0, ["wider"])
	var wide: Dictionary = profile.combat_stats()
	check(is_equal_approx(wide.reach / plain.reach, 1.35) and is_equal_approx(wide.damage / plain.damage, 0.9), "WIDER trades damage for area")
	profile.set_slot_links(0, ["multishot"])
	profile.stance = 3
	check(profile.combat_stats().projectiles == 2, "MULTISHOT adds two projectiles to a projectile skill")

	# Gameplay uses the same numbers as the preview, and projectiles resolve hits.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.panel = "build"
	scene.build_tab = 1
	scene.profile.stance = 0
	scene.profile.skill_levels[0] = 5
	scene.profile.set_slot_links(0, [])
	scene.build_click(scene.support_pool_rect(support_index("wider")).get_center())
	check(scene.profile.has_support("wider"), "Support pool click links a support")
	scene.build_click(scene.support_pool_rect(support_index("wider")).get_center())
	check(not scene.profile.has_support("wider"), "Support pool click unlinks a support")
	scene.build_tab = 0
	scene.slot_focus = 0
	scene.build_click(scene.skill_pool_rect(2).get_center())
	check(scene.profile.stance == 2, "Basic skill equips from the slot UI")
	scene.close_panel()

	scene.enter_map(0)
	scene.enemies.clear()
	scene.profile.stance = 0
	scene.profile.skill_levels[0] = 5
	scene.profile.set_slot_links(0, ["wider"])
	scene.refresh_stats()
	var combat: Dictionary = scene.profile.combat_stats()
	scene.facing = Vector2.RIGHT
	scene.spawn_enemy(scene.player + Vector2(combat.reach + 10, 0))
	scene.enemies[0].hp = 10000
	var old_hp: float = scene.enemies[0].hp
	scene.attack()
	check(is_equal_approx(old_hp - scene.enemies[0].hp, combat.damage), "Actual hit matches the preview and trained range")
	check(is_equal_approx(scene.attack_cooldown, combat.interval), "The support interval is applied")
	check(scene.profile.skill_xp[0] == 0, "Nonlethal hits do not farm mastery")
	scene.enemies.clear()

	# EMBER BOLT fires projectiles that damage the first enemy in the lane.
	scene.profile.stance = 3
	scene.profile.set_slot_links(0, ["multishot", "pierce"])
	scene.refresh_stats()
	scene.facing = Vector2.RIGHT
	scene.spawn_enemy(scene.player + Vector2(220, 0))
	scene.enemies[0].hp = 10000
	old_hp = scene.enemies[0].hp
	scene.attack()
	check(scene.projectiles.size() == 3, "EMBER BOLT fires one bolt plus two from MULTISHOT")
	for i in range(30):
		scene.step_projectiles(0.02)
		if scene.enemies.is_empty() or scene.enemies[0].hp < old_hp:
			break
	check(not scene.enemies.is_empty() and scene.enemies[0].hp < old_hp, "A projectile damages the enemy in its lane")

	scene.return_to_hub()
	scene.profile.set_slot_links(0, ["power", "ignite"])
	scene.profile.stance = 2
	scene.profile.level = 13
	scene.profile.auras.assign(["ash", "fleet"])
	var path := "/tmp/ember_mastery_%d.json" % OS.get_process_id()
	check(scene.profile.save_to(path), "Current version saves")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.skill_levels == scene.profile.skill_levels and loaded.slot_link_ids(0) == scene.profile.slot_link_ids(0) and loaded.auras == scene.profile.auras and loaded.skill_xp == scene.profile.skill_xp and loaded.combat_stats() == scene.profile.combat_stats(), "All mastery, links, auras and combat stats round trip")
	for bad in [[0, 1, 1, 1], [1, 11, 1, 1], [1, 2.5, 1, 1], [1, 1, 1], [1, "bad", 1, 1]]:
		var invalid := saved.duplicate(true)
		invalid.skill_levels = bad
		write_json(path, invalid)
		check(not loaded.load_from(path) and loaded.skill_levels == scene.profile.skill_levels, "Invalid skill levels rejected atomically")
	# Slot 0 is the basic LANCE here, so its links must use attack tags.
	for bad in [[[{"id": "nope", "tier": 3}], [], [], [], []], [[{"id": "power", "tier": 3}, {"id": "power", "tier": 3}], [], [], [], []], [[{"id": "multishot", "tier": 3}], [], [], [], []], [[{"id": "power", "tier": 9}], [], [], [], []]]:
		var invalid := saved.duplicate(true)
		invalid.links = bad
		write_json(path, invalid)
		check(not loaded.load_from(path), "Invalid link build rejected")
	var invalid := saved.duplicate(true)
	invalid.skill_levels = [10, 1, 1, 1, 1, 1, 1, 1]
	invalid.skill_xp = [1, 0, 0, 0, 0, 0, 0, 0]
	write_json(path, invalid)
	check(not loaded.load_from(path), "Max level cannot retain XP")
	var legacy := saved.duplicate(true)
	legacy.version = 7
	legacy.erase("links")
	legacy.skill_levels = [legacy.skill_levels[0], legacy.skill_levels[1], legacy.skill_levels[2]]
	legacy.skill_xp = [legacy.skill_xp[0], legacy.skill_xp[1], legacy.skill_xp[2]]
	legacy.support_levels = [1, 1, 1]
	legacy.support_xp = [0, 0, 0]
	legacy.support = 2
	legacy.talents = [legacy.talents[0], legacy.talents[1], legacy.talents[2]]
	write_json(path, legacy)
	check(loaded.load_from(path) and loaded.skill_levels.size() == 8 and loaded.slot_link_ids(0) == ["leech"] and loaded.stance == 2 and loaded.inventory == scene.profile.inventory, "Version seven migrates the old support choice into a link build")
	DirAccess.remove_absolute(path)

	# Exercise the link board under the drawing pipeline.
	scene.panel = "build"
	scene.queue_redraw()
	await process_frame
	scene.queue_free()
	if not failed:
		print("PASS: skill mastery, support slots, tag gating, projectile combat, link UI, v7 migration and invalid data")
	quit(1 if failed else 0)
