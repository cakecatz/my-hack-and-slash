extends SceneTree

const Profile = preload("res://scripts/profile.gd")
const AbilityCatalog = preload("res://scripts/ability_catalog.gd")
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
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.layout_template = 0
	scene.layout_flip = 0
	scene.profile.unlocked = 3

	# Abilities unlock with character level.
	scene.profile.level = 1
	check(scene.profile.ability_unlocked(0) and not scene.profile.ability_unlocked(1), "Ability 1 unlocks at level 1")
	scene.profile.level = 3
	check(scene.profile.ability_unlocked(1) and not scene.profile.ability_unlocked(2), "Ability 2 unlocks at level 3")
	scene.profile.level = 5
	check(scene.profile.ability_unlocked(2) and not scene.profile.ability_unlocked(3), "Ability 3 unlocks at level 5")
	scene.profile.level = 7
	check(scene.profile.ability_unlocked(3) and scene.profile.unlocked_abilities() == 4, "Ability 4 unlocks at level 7")
	check(not scene.cast_ability(0), "Abilities cannot be cast in town")

	scene.enter_map(0)
	scene.enemies.clear()
	scene.facing = Vector2.RIGHT

	# EMBER LANCE is a piercing skillshot that scales with attack.
	var power: float = scene.slot_combat(1).damage
	scene.spawn_enemy(scene.player + Vector2(160, 0))
	scene.spawn_enemy(scene.player + Vector2(300, 0))
	scene.enemies[0].hp = 10000.0
	scene.enemies[1].hp = 10000.0
	check(scene.cast_ability(0), "EMBER LANCE casts")
	check(scene.ability_cd[0] > 0 and not scene.cast_ability(0), "Ability goes on cooldown after casting")
	for i in range(80):
		scene.step_projectiles(0.02)
	check(scene.enemies.size() == 2 and scene.enemies[0].hp < 10000.0 and scene.enemies[1].hp < 10000.0, "EMBER LANCE pierces every enemy in the line")
	check(is_equal_approx(10000.0 - scene.enemies[0].hp, power), "Ability damage scales with attack")

	# Mana gates active skills and regenerates over time.
	scene.enemies.clear()
	scene.reset_abilities()
	scene.spawn_enemy(scene.player + Vector2(120, 0))
	scene.enemies[0].hp = 10000.0
	check(is_equal_approx(scene.mana, scene.max_mana), "Mana starts full")
	var cost: int = int(AbilityCatalog.def(0).cost)
	check(scene.cast_ability(0) and is_equal_approx(scene.mana, scene.max_mana - cost), "Casting spends mana")
	scene.ability_cd[0] = 0.0
	scene.mana = cost - 1
	check(not scene.cast_ability(0), "A skill needs enough mana")
	var before_mana: float = scene.mana
	scene.step_abilities(1.0)
	check(scene.mana > before_mana, "Mana regenerates over time")
	scene.enemies.clear()

	# The spirit talent raises maximum mana.
	var base_mana: int = scene.profile.stats().mana
	scene.profile.talents.assign([0, 0, 0, 1])
	check(scene.profile.stats().mana == base_mana + 15, "The spirit talent raises maximum mana")
	scene.profile.talents.assign([0, 0, 0, 0])

	# Per-skill links: each slot has its own supports and a support is unique per character.
	scene.profile.level = 7
	scene.profile.stance = 2
	scene.profile.active_slots.assign(["ember_lance", "", "", ""])
	scene.profile.set_slot_links(1, ["multishot", "power"])
	check(scene.profile.slot_link_ids(1) == ["multishot", "power"], "An active skill holds its own supports")
	check(scene.profile.slot_combat(1).projectiles == 2, "MULTISHOT adds projectiles to the active skill link")
	check(not scene.profile.add_support(0, "power"), "A support cannot be used twice across slots")
	scene.profile.embers = 1000
	check(scene.profile.upgrade_support(1, "power") and scene.profile.support_tier(1, "power") == 2, "A link can be upgraded a tier")
	check(scene.profile.slot_combat(1).damage > 0.0, "Upgraded links still compute combat")
	scene.profile.set_slot_links(1, [])
	scene.profile.active_slots.assign(["ember_lance", "cinder_field", "barrier", "rush"])

	# Auras reserve spirit and grant persistent effects.
	scene.profile.auras.clear()
	scene.profile.level = 13
	check(scene.profile.spirit_max() == 54, "Spirit pool grows with level")
	check(scene.profile.toggle_aura("ash") and scene.profile.reserved_spirit() == 20, "An aura reserves spirit")
	check(scene.profile.aura_multiplier("damage") > 1.0, "ASH AURA raises the damage multiplier")
	check(scene.profile.toggle_aura("ward") and scene.profile.reserved_spirit() == 40, "A second aura reserves more spirit")
	check(not scene.profile.toggle_aura("fleet"), "A full pool rejects another aura")
	check(scene.profile.stats().armor > 0, "WARD AURA adds defense")
	check(scene.profile.toggle_aura("ash") and scene.profile.reserved_spirit() == 20, "Turning an aura off frees spirit")
	check(scene.profile.toggle_aura("fleet") and is_equal_approx(scene.profile.move_speed_multiplier(), 1.08), "FLEET AURA raises movement speed")
	check(scene.profile.toggle_aura("flow") and scene.profile.stats().regen > 6.0, "EMBER FLOW raises mana regeneration")
	scene.profile.auras.clear()

	# CINDER FIELD drops a burning, slowing zone.
	scene.enemies.clear()
	scene.reset_abilities()
	check(scene.cast_ability(1) and scene.zones.size() == 1, "CINDER FIELD creates a zone")
	scene.zones.clear()
	scene.spawn_enemy(scene.player + Vector2(120, 0))
	scene.enemies[0].hp = 10000.0
	var before: float = scene.enemies[0].hp
	scene.zones.append({"pos": scene.enemies[0].pos, "radius": 130.0, "life": 3.0, "tick": 0.0, "interval": 0.5, "damage": 12.0, "burn": 0.35, "slow": 0.35})
	for i in range(40):
		scene.step_zones(0.1)
	check(scene.enemies[0].hp < before and scene.enemies[0].slow_time > 0.0, "Field burns and slows enemies inside")

	# GUARDIAN BARRIER absorbs damage before health.
	scene.zones.clear()
	scene.reset_abilities()
	scene.enemies.clear()
	scene.hp = scene.max_hp
	check(scene.cast_ability(2) and scene.shield > 0.0, "GUARDIAN BARRIER grants a shield")
	scene.invincible = 0
	var health: float = scene.hp
	var shield_before: float = scene.shield
	scene.take_hit(10)
	check(scene.hp == health and scene.shield < shield_before, "The shield absorbs the hit and health is untouched")

	# BLOOD RUSH speeds up attacks and movement.
	scene.reset_abilities()
	scene.invincible = 0
	check(scene.cast_ability(3), "BLOOD RUSH casts")
	var combat: Dictionary = scene.expedition_combat()
	check(scene.action_interval(combat) < combat.interval, "Rush shortens the attack interval")
	check(scene.action_move_multiplier() > scene.profile.move_speed_multiplier(), "Rush raises movement speed")

	# Leaving the expedition clears every active ability.
	scene.return_to_hub()
	check(scene.zones.is_empty() and scene.shield == 0.0 and scene.rush_time == 0.0 and scene.ability_cd[0] == 0.0, "Returning to town resets abilities")

	# One skill pool: attack skills can also fill active slots.
	scene.profile.level = 7
	check(scene.profile.assign_basic("nova") and scene.profile.basic_id() == "nova", "An attack skill can be set as the basic attack")
	check(not scene.profile.assign_basic("ember_lance"), "An active skill cannot be the basic attack")
	check(scene.profile.assign_active(0, "cleave"), "An attack skill can fill an active slot")
	check(not scene.profile.assign_active(1, "cleave"), "The same skill cannot fill two slots")
	check(not scene.profile.assign_active(1, "nova"), "The basic skill cannot also fill an active slot")
	# Keep campaign and unlocked consistent so the save validator accepts it.
	scene.profile.campaign = 6
	var path := "/tmp/ember_slots_%d.json" % OS.get_process_id()
	check(scene.profile.save_to(path), "Assigned slots save")
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.active_slots == scene.profile.active_slots and loaded.stance == scene.profile.stance, "Assigned slots round trip")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for bad in [["nova", "cinder_field", "barrier", "rush"], ["cleave", "cleave", "barrier", "rush"], ["nope", "cinder_field", "barrier", "rush"]]:
		var invalid := saved.duplicate(true)
		invalid.active_slots = bad
		write_json(path, invalid)
		check(not loaded.load_from(path), "Invalid slot assignment rejected")
	DirAccess.remove_absolute(path)

	# Abilities also work in the training ground, including slotted attack skills.
	scene.profile.level = 7
	scene.enter_training()
	scene.facing = Vector2.RIGHT
	check(scene.cast_ability(0), "Abilities can be cast in the training ground")
	scene.profile.active_slots.assign(["cleave", "", "", ""])
	scene.profile.stance = 2
	scene.ability_cd[0] = 0.0
	scene.enemies.clear()
	scene.spawn_enemy(scene.player + Vector2(70, 0))
	scene.enemies[0].hp = 10000.0
	var slotted_hp: float = scene.enemies[0].hp
	check(scene.cast_ability(0), "An attack skill can be cast from an active slot")
	check(scene.enemies[0].hp < slotted_hp, "The slotted attack damages enemies")
	scene.return_to_hub()
	scene.queue_free()
	await process_frame
	if not failed:
		print("PASS: ability unlocks, cooldowns, skillshot, ground zone, shield, steroid and resets")
	quit(1 if failed else 0)
