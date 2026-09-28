extends SceneTree

const Profile = preload("res://scripts/profile.gd")
const PassiveTree = preload("res://scripts/passive_tree.gd")
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
	var p = Profile.new()
	check(p.passive_points() == 0, "No passive points at level one")
	p.level = 5
	check(p.passive_points() == 4, "One passive point per level")
	p.level = 40
	check(p.passive_points() == PassiveTree.MAX_POINTS, "Passive points cap below the node count")
	p.level = 13

	# Allocation needs the parent node, and cannot repeat.
	check(not p.allocate_passive("off_proj"), "A node needs its parent allocated first")
	check(p.allocate_passive("off_dmg"), "A root child allocates")
	check(p.allocate_passive("off_proj"), "A branch node allocates once its parent is in")
	check(not p.allocate_passive("off_dmg"), "A node cannot be allocated twice")
	check(not p.allocate_passive("core"), "The root cannot be bought")

	# Tag-gated nodes only help matching skills.
	p.passives.clear()
	p.stance = 0
	var plain: float = p.combat_stats().damage
	p.allocate_passive("off_dmg")
	check(is_equal_approx(p.combat_stats().damage / plain, 1.08), "A global damage node applies to any skill")
	p.allocate_passive("off_proj")
	check(is_equal_approx(p.combat_stats().damage / plain, 1.08), "A projectile node does not help an area skill")
	p.passives.clear()
	var bolt_plain: float = p.combat_stats(3).damage
	p.allocate_passive("off_dmg")
	p.allocate_passive("off_proj")
	check(is_equal_approx(p.combat_stats(3).damage / bolt_plain, 1.08 * 1.18), "A projectile node helps a projectile skill")

	# Area and projectile behaviour nodes.
	p.passives.clear()
	p.stance = 0
	var cleave_reach: float = p.combat_stats().reach
	p.allocate_passive("off_dmg")
	p.allocate_passive("off_area")
	check(is_equal_approx(p.combat_stats().reach / cleave_reach, 1.15), "An area node widens area skills")
	p.passives.clear()
	p.allocate_passive("off_dmg")
	p.allocate_passive("off_proj")
	p.allocate_passive("off_proj2")
	p.stance = 3
	check(p.combat_stats().projectiles == 1, "A notable node adds a projectile")

	# Defense and utility helpers.
	p.passives.clear()
	var base_hp: int = p.stats().health
	p.allocate_passive("def_hp")
	check(p.stats().health == base_hp + 40, "A life node raises maximum life")
	p.allocate_passive("def_hp2")
	check(p.stats().health == base_hp + 120, "A notable life node stacks")
	p.passives.clear()
	p.allocate_passive("def_hp")
	p.allocate_passive("def_armor")
	p.allocate_passive("def_res")
	check(is_equal_approx(p.incoming_multiplier(), 0.94), "A damage-reduction node applies")
	p.passives.clear()
	p.allocate_passive("def_hp")
	p.allocate_passive("def_hp2")
	p.allocate_passive("def_dash")
	check(is_equal_approx(p.dash_cooldown_multiplier(), 0.8), "A dodge-cooldown node applies")
	p.passives.clear()
	p.allocate_passive("util_move")
	check(is_equal_approx(p.move_speed_multiplier(), 1.06), "A movement node applies")

	# Mana nodes raise the active-skill resource.
	p.passives.clear()
	var baseline: Dictionary = p.stats()
	p.allocate_passive("def_hp")
	p.allocate_passive("def_armor")
	p.allocate_passive("def_mana")
	check(p.stats().mana == int(baseline.mana) + 60, "A mana node raises maximum mana")
	p.reset_passives()
	p.allocate_passive("util_move")
	p.allocate_passive("util_heat")
	p.allocate_passive("util_flow")
	check(is_equal_approx(p.stats().regen, float(baseline.regen) + 2.5), "A flow node raises mana regeneration")
	p.reset_passives()

	# Refunds only remove leaves.
	p.passives.clear()
	p.allocate_passive("off_dmg")
	p.allocate_passive("off_proj")
	p.allocate_passive("off_proj2")
	check(not p.refund_passive("off_dmg"), "A node with allocated children cannot be refunded")
	check(p.refund_passive("off_proj2"), "A leaf node refunds")
	check(p.refund_passive("off_proj"), "Then its parent refunds")
	check(not p.refund_passive("core"), "The root cannot be refunded")
	p.reset_passives()
	check(p.passives.is_empty(), "Reset clears every passive")

	# Persistence and validation.
	p.level = 20
	p.passives.clear()
	p.allocate_passive("off_dmg")
	p.allocate_passive("off_proj")
	p.allocate_passive("def_hp")
	var path := "/tmp/ember_passives_%d.json" % OS.get_process_id()
	check(p.save_to(path), "Save with passives")
	var loaded = Profile.new()
	check(loaded.load_from(path) and loaded.passives == p.passives and loaded.combat_stats() == p.combat_stats(), "Passives round trip")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for bad in [["off_proj"], ["nope"], ["off_dmg", "off_dmg"], ["core"], ["off_dmg", "off_melee"]]:
		var invalid := saved.duplicate(true)
		invalid.passives = bad
		write_json(path, invalid)
		check(not loaded.load_from(path), "Invalid passive set rejected")
	var all_ids: Array[String] = []
	for node in PassiveTree.NODES:
		if node.id != PassiveTree.ROOT:
			all_ids.append(node.id)
	var too_many := saved.duplicate(true)
	too_many.passives = all_ids
	write_json(path, too_many)
	check(not loaded.load_from(path), "Too many passives rejected")
	DirAccess.remove_absolute(path)

	# The passive tab allocates on click and refunds on right-click.
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_enabled = false
	root.add_child(scene)
	scene.set_process(false)
	scene.profile.level = 13
	scene.profile.passives.clear()
	scene.panel = "build"
	scene.build_tab = 3
	scene.build_click(scene.passive_node_rect("off_dmg").get_center())
	check(scene.profile.has_passive("off_dmg"), "A passive node allocates from the UI")
	scene.build_click(scene.passive_node_rect("off_dmg").get_center(), MOUSE_BUTTON_RIGHT)
	check(not scene.profile.has_passive("off_dmg"), "Right-click refunds from the UI")
	scene.build_click(scene.passive_node_rect("off_dmg").get_center())
	scene.build_click(scene.passive_node_rect("off_proj").get_center())
	scene.build_click(Rect2(144, 244, 240, 32).get_center())
	check(scene.profile.passives.is_empty(), "The reset button clears the tree")
	scene.queue_redraw()
	await process_frame
	scene.queue_free()
	if not failed:
		print("PASS: passive points, parent gating, tag gating, behaviour nodes, refunds, persistence and UI")
	quit(1 if failed else 0)
