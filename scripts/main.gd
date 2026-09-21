extends Node2D

const Profile = preload("res://scripts/profile.gd")
const VIEW := Rect2(24, 108, 1104, 540)
const WORLD := Rect2(0, 0, 2400, 1500)
const HUB_BOUNDS := Rect2(40, 40, 1024, 460)
const HUB_SPAWN := Vector2(552, 390)
const STASH_POS := Vector2(285, 230)
const GATE_POS := Vector2(830, 230)
const GRID_PAGE_SIZE := 24
const CLOSE_RECT := Rect2(982, 150, 40, 32)
const MINT := Color("70efd0")
const GOLD := Color("ffc478")
const RED := Color("f27386")
const PALE := Color("e0e9f4")
const MUTED := Color("8597ae")
const MAPS := [
	{"name": "ASHEN OUTSKIRTS", "boss": "Hollow Warden", "color": Color("182d2b"), "packs": 4},
	{"name": "BURIED SANCTUM", "boss": "Crypt Sentinel", "color": Color("252437"), "packs": 5},
	{"name": "CINDER CITADEL", "boss": "Cinder Tyrant", "color": Color("332423"), "packs": 6}
]
var profile = Profile.new()
var save_enabled := true
var hub := true
var map_index := 0
var map_cleared := false
var player := HUB_SPAWN
var facing := Vector2.RIGHT
var camera := Vector2.ZERO
var hp := 100.0
var max_hp := 100.0
var damage := 18.0
var armor := 1.0
var attack_interval := 0.4
var attack_cooldown := 0.0
var slash := 0.0
var slash_angle := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector2.RIGHT
var invincible := 0.0
var return_time := 0.0
var potions := 3
var kills := 0
var found := 0
var paused := false
var ended := false
var page := 0
var stash_page := 0
# Empty, inventory, stash, or gate. Open panels suspend world simulation.
var panel := ""
var attack_blocked := false
var town_clock := 0.0
var message := "Walk to the stash or warp gate and press E. I opens your inventory."
var enemies: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var notices: Array[Dictionary] = []
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	if save_enabled:
		if FileAccess.file_exists(Profile.SAVE_PATH) and not profile.load_from():
			# Preserve unreadable saves rather than overwriting them automatically.
			save_enabled = false
			message = "Save could not be loaded. Autosave disabled to preserve it."
	refresh_stats()
	hp = max_hp
	var bindings := {"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN], "attack": [KEY_SPACE], "dash": [KEY_SHIFT]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("attack", mouse):
		InputMap.action_add_event("attack", mouse)

func persist() -> void:
	if save_enabled:
		profile.save_to()

func refresh_stats() -> void:
	var stats: Dictionary = profile.stats()
	max_hp = stats.health
	damage = stats.attack
	armor = stats.armor
	attack_interval = 0.4 / (1.0 + stats.haste / 100.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if ended:
			if event.keycode == KEY_R:
				return_to_hub(true)
			return
		if event.keycode == KEY_ESCAPE:
			if not panel.is_empty():
				close_panel()
			else:
				paused = not paused
			return
		if paused:
			return
		if event.keycode == KEY_I:
			if panel == "inventory" or panel == "stash":
				close_panel()
			else:
				panel = "inventory"
				return_time = 0
			return
		if not panel.is_empty():
			if event.keycode == KEY_E:
				close_panel()
			elif panel == "gate" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
				travel_from_gate(event.keycode - KEY_1)
			return
		if hub:
			if event.keycode == KEY_E:
				interact_hub()
			return
		if event.keycode == KEY_E:
			pickup_nearby()
		elif event.keycode == KEY_T:
			return_time = 2.0
			message = "Opening town portal... Stand still for 2 seconds."
		elif event.keycode == KEY_Q:
			if potions > 0 and hp < max_hp:
				potions -= 1
				hp = minf(max_hp, hp + max_hp * 0.5)
	if event is InputEventMouseButton and event.pressed and not paused and not ended:
		panel_mouse(event.position, event.button_index, event.shift_pressed)

func close_panel() -> void:
	panel = ""
	attack_blocked = true

func interact_hub() -> void:
	if not hub or not panel.is_empty():
		return
	if player.distance_to(STASH_POS) <= 110:
		panel = "stash"
	elif player.distance_to(GATE_POS) <= 110:
		panel = "gate"

func travel_from_gate(index: int) -> bool:
	if panel != "gate" or player.distance_to(GATE_POS) > 110:
		return false
	return enter_map(index)

func grid_rect(cell: int, storage: bool = false) -> Rect2:
	return Rect2(Vector2(612 if storage else 160, 314) + Vector2(cell % 6, cell / 6) * 54, Vector2(48, 48))

func equipment_rect(index: int) -> Rect2:
	return Rect2(160 + index * 115, 223, 48, 48)

func page_rect(storage: bool, next: bool) -> Rect2:
	return Rect2((612 if storage else 160) + (240 if next else 180), 542, 62, 26)

func change_page(storage: bool, change: int) -> void:
	var count: int = profile.stash.size() if storage else profile.inventory.size()
	var last := maxi(0, (count - 1) / GRID_PAGE_SIZE)
	if storage:
		stash_page = clampi(stash_page + change, 0, last)
	else:
		page = clampi(page + change, 0, last)

func transfer_item(index: int, to_stash: bool) -> void:
	if not hub or panel != "stash" or player.distance_to(STASH_POS) > 110:
		return
	if profile.transfer_item(index, to_stash):
		change_page(false, 0)
		change_page(true, 0)
		persist()

func panel_mouse(mouse: Vector2, button: int, shift: bool) -> void:
	if panel.is_empty():
		return
	if button == MOUSE_BUTTON_LEFT and CLOSE_RECT.has_point(mouse):
		close_panel()
		return
	if panel == "gate":
		if button == MOUSE_BUTTON_LEFT:
			for i in range(3):
				if map_rect(i).has_point(mouse):
					travel_from_gate(i)
					return
		return
	if button == MOUSE_BUTTON_WHEEL_DOWN or button == MOUSE_BUTTON_WHEEL_UP:
		change_page(panel == "stash" and mouse.x >= 570, 1 if button == MOUSE_BUTTON_WHEEL_DOWN else -1)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	for storage in [false, true]:
		if storage and panel != "stash":
			continue
		for next in [false, true]:
			if page_rect(storage, next).has_point(mouse):
				change_page(storage, 1 if next else -1)
				return
		for cell in range(GRID_PAGE_SIZE):
			if grid_rect(cell, storage).has_point(mouse):
				var index := (stash_page if storage else page) * GRID_PAGE_SIZE + cell
				if storage:
					transfer_item(index, false)
				elif shift and panel == "stash":
					transfer_item(index, true)
				else:
					equip_item(index)
				change_page(false, 0)
				return

func equip_item(index: int) -> void:
	if not hub:
		return
	if profile.equip(index):
		refresh_stats()
		hp = max_hp
		message = "Equipment updated. Your new stats apply to the next expedition."
		persist()

func enter_map(index: int) -> bool:
	if not hub or index < 0 or index >= MAPS.size() or index >= profile.unlocked:
		return false
	hub = false
	panel = ""
	attack_blocked = true
	map_index = index
	map_cleared = false
	ended = false
	paused = false
	kills = 0
	found = 0
	potions = 3
	return_time = 0
	attack_cooldown = 0.25
	dash_time = 0
	dash_cooldown = 0
	invincible = 0
	slash = 0
	player = Vector2(180, 750)
	refresh_stats()
	hp = max_hp
	enemies.clear()
	drops.clear()
	particles.clear()
	notices.clear()
	for pack in range(MAPS[index].packs):
		var center := Vector2(550 + pack * 255, 440 if pack % 2 == 0 else 990)
		for unit in range(3 + index):
			spawn_enemy(center + Vector2(randf_range(-65, 65), randf_range(-65, 65)))
	spawn_enemy(Vector2(2130, 750), true)
	update_camera()
	message = "Explore the map. Defeat %s. T: return at any time." % MAPS[index].boss
	return true

func spawn_enemy(pos: Vector2, boss: bool = false) -> void:
	var tier := map_index + 1
	var health := (36.0 + tier * 14) * (6 if boss else 1)
	enemies.append({"pos": pos, "hp": health, "max_hp": health, "radius": 32.0 if boss else 16.0, "speed": 65.0 if boss else 90.0, "damage": (10 + tier * 4) * (2 if boss else 1), "flash": 0.0, "brute": boss, "aggro": false})

func return_to_hub(defeated: bool = false) -> void:
	hub = true
	panel = ""
	player = HUB_SPAWN
	camera = Vector2.ZERO
	dash_time = 0
	invincible = 0
	slash = 0
	ended = false
	paused = false
	return_time = 0
	refresh_stats()
	hp = max_hp
	message = "%s / %d kills / %d items collected. Visit the stash or press I to equip loot." % ["Rescued: collected gear retained" if defeated else "Returned to town", kills, found]
	enemies.clear()
	drops.clear()
	particles.clear()
	notices.clear()
	persist()

func pickup_nearby() -> void:
	if hub or ended or paused:
		return
	for i in range(drops.size() - 1, -1, -1):
		if player.distance_to(drops[i].pos) <= 90:
			profile.inventory.append(drops[i].item)
			message = "Collected: %s. Equip it back in town." % drops[i].item.name
			found += 1
			drops.remove_at(i)
	persist()

func _process(delta: float) -> void:
	if not paused and not ended and panel.is_empty():
		if hub:
			step_hub(delta)
		else:
			step(delta)
	queue_redraw()

func step_hub(delta: float) -> void:
	town_clock += delta
	var movement := Input.get_vector("left", "right", "up", "down")
	var next := (player + movement * 245 * delta).clamp(HUB_BOUNDS.position + Vector2.ONE * 18, HUB_BOUNDS.end - Vector2.ONE * 18)
	# The chest and campfire are solid; slide around their edges.
	for obstacle in [STASH_POS, Vector2(552, 230)]:
		if next.distance_to(obstacle) < 55:
			next = obstacle + (next - obstacle).normalized() * 55
	player = next
	var aim := get_global_mouse_position() - VIEW.position - player
	if aim.length() > 4:
		facing = aim.normalized()

func update_camera() -> void:
	camera = (player - VIEW.size / 2).clamp(Vector2.ZERO, WORLD.size - VIEW.size)

func step(delta: float) -> void:
	attack_cooldown = maxf(0, attack_cooldown - delta)
	slash = maxf(0, slash - delta)
	dash_time = maxf(0, dash_time - delta)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	invincible = maxf(0, invincible - delta)
	var movement := Input.get_vector("left", "right", "up", "down")
	var aim := get_global_mouse_position() - VIEW.position + camera - player
	if aim.length() > 4:
		facing = aim.normalized()
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0:
		dash_direction = movement if movement.length() > 0 else facing
		dash_time = 0.17
		dash_cooldown = 1.1
		invincible = 0.23
	if dash_time > 0:
		player += dash_direction * 820 * delta
		burst(player, MINT, 2)
	else:
		player += movement * 245 * delta
	player = clamp_point(player, 18)
	update_camera()
	if not Input.is_action_pressed("attack"):
		attack_blocked = false
	var attacking := Input.is_action_pressed("attack") and not attack_blocked
	if attacking and attack_cooldown <= 0:
		attack()
	if return_time > 0:
		if movement.length() > 0 or attacking or dash_time > 0:
			return_time = 0
			message = "Portal cancelled. Stand still and press T to return."
		else:
			return_time -= delta
			if return_time <= 0:
				return_to_hub()
				return
	for enemy in enemies:
		var distance: float = enemy.pos.distance_to(player)
		if distance < 300:
			enemy.aggro = true
		if enemy.aggro:
			enemy.pos = clamp_point(enemy.pos.move_toward(player, enemy.speed * delta), enemy.radius)
		enemy.flash = maxf(0, enemy.flash - delta)
		if distance < enemy.radius + 16 and invincible <= 0:
			var hit := maxf(1, enemy.damage - armor)
			hp = maxf(0, hp - hit)
			invincible = 0.65
			if return_time > 0:
				message = "Portal interrupted by damage."
			return_time = 0
			burst(player, RED, 14)
			notices.append({"pos": player - Vector2(0, 30), "text": "-%d" % hit, "life": 0.7, "color": RED})
			if hp <= 0:
				ended = true
				persist()
				return
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].pos += particles[i].velocity * delta
		if particles[i].life <= 0:
			particles.remove_at(i)
	for i in range(notices.size() - 1, -1, -1):
		notices[i].life -= delta
		notices[i].pos.y -= 30 * delta
		if notices[i].life <= 0:
			notices.remove_at(i)

func clamp_point(point: Vector2, margin: float) -> Vector2:
	return point.clamp(WORLD.position + Vector2.ONE * margin, WORLD.end - Vector2.ONE * margin)

func attack() -> void:
	attack_cooldown = attack_interval
	slash = 0.16
	slash_angle = facing.angle()
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[i]
		var offset: Vector2 = enemy.pos - player
		if offset.length() > 106 + enemy.radius:
			continue
		if offset.length() > 28 and facing.dot(offset.normalized()) < 0.25:
			continue
		enemy.hp -= damage
		enemy.flash = 0.12
		enemy.aggro = true
		enemy.pos = clamp_point(enemy.pos + offset.normalized() * 27, enemy.radius)
		burst(enemy.pos, GOLD, 9)
		notices.append({"pos": enemy.pos - Vector2(0, 24), "text": str(int(damage)), "life": 0.6, "color": GOLD})
		if enemy.hp <= 0:
			defeat_enemy(i)

func defeat_enemy(index: int) -> void:
	var enemy: Dictionary = enemies[index]
	kills += 1
	var old_level: int = profile.level
	profile.gain_xp((30 if enemy.brute else 8) * (map_index + 1))
	refresh_stats()
	if profile.level > old_level:
		hp = minf(max_hp, hp + 20)
		message = "Level %d! Permanent base stats increased." % profile.level
	if enemy.brute or kills == 1 or randf() < 0.45:
		drops.append({"pos": enemy.pos, "item": profile.roll_item(map_index + 1, enemy.brute)})
	if enemy.brute:
		map_cleared = true
		profile.unlocked = mini(3, maxi(profile.unlocked, map_index + 2))
		message = "Boss defeated! Collect the rare loot (E), then return to town (T)."
	enemies.remove_at(index)
	persist()

func burst(pos: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		particles.append({"pos": pos, "velocity": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30, 170), "life": randf_range(0.15, 0.4), "color": color})

func label_at(pos: Vector2, value: String, size: int, color: Color = PALE) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("263346"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

func rarity_color(item: Dictionary) -> Color:
	return [PALE, Color("82b5ff"), GOLD][int(item.rarity)]

func item_stats(item: Dictionary) -> String:
	if item.is_empty():
		return "Empty slot"
	return "ATK %d   HP %d   DEF %d   SPD %d%%" % [item.attack, item.health, item.armor, item.haste]

func map_rect(index: int) -> Rect2:
	return Rect2(144 + index * 292, 280, 276, 170)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("0b101a"))
	if hub:
		draw_hub()
	else:
		draw_world()
	draw_hud()
	if not panel.is_empty():
		draw_panel()
	if not profile.save_error.is_empty():
		label_at(Vector2(30, 715), profile.save_error, 13, RED)
	if ended:
		draw_overlay("RESCUED FROM THE DEPTHS", "Collected gear and character progress are retained.")
		label_at(Vector2(389, 397), "Press R to return to town", 24, MINT)
	elif paused:
		draw_overlay("PAUSED", "Esc to resume")

func draw_hub() -> void:
	draw_set_transform(VIEW.position)
	draw_rect(Rect2(Vector2.ZERO, VIEW.size), Color("14202b"))
	for x in range(40, 1064, 64):
		for y in range(40, 500, 64):
			draw_rect(Rect2(x + 2, y + 2, mini(60, 1062 - x), mini(60, 498 - y)), Color("1c2b36") if (x + y) % 3 else Color("202f39"))
	draw_rect(HUB_BOUNDS, Color("44515b"), false, 5)
	draw_line(Vector2(285, 310), Vector2(830, 310), Color("36424a"), 54)
	draw_line(Vector2(552, 310), Vector2(552, 480), Color("36424a"), 54)
	for x in [94, 1010]:
		for y in [90, 443]:
			draw_rect(Rect2(x - 12, y - 15, 24, 30), Color("46515b"))
			draw_circle(Vector2(x, y - 20), 22, Color(1, 0.6, 0.2, 0.08))
			draw_circle(Vector2(x, y - 20), 6, GOLD)
	# Campfire and stone ring.
	var fire := Vector2(552, 230)
	draw_circle(fire, 70, Color(1, 0.5, 0.2, 0.05))
	draw_arc(fire, 33, 0, TAU, 12, Color("69717b"), 10, true)
	draw_line(fire + Vector2(-19, 12), fire + Vector2(19, -8), Color("9a7250"), 8)
	draw_line(fire + Vector2(19, 12), fire + Vector2(-19, -8), Color("9a7250"), 8)
	draw_colored_polygon(PackedVector2Array([fire + Vector2(-14, 7), fire + Vector2(0, -34 - sin(town_clock * 4) * 4), fire + Vector2(15, 7)]), GOLD)
	# Stash chest, with lid, bands and lock.
	var chest := STASH_POS
	draw_circle(chest + Vector2(0, 18), 49, Color(0, 0, 0, 0.24))
	draw_rect(Rect2(chest - Vector2(37, 25), Vector2(74, 56)), Color("765438"))
	draw_rect(Rect2(chest - Vector2(37, 25), Vector2(74, 22)), Color("b38855"))
	draw_rect(Rect2(chest - Vector2(37, 25), Vector2(74, 56)), GOLD.darkened(0.3), false, 3)
	for offset in [-22, 22]:
		draw_line(chest + Vector2(offset, -25), chest + Vector2(offset, 31), GOLD.darkened(0.2), 5)
	draw_rect(Rect2(chest + Vector2(-6, -7), Vector2(12, 16)), GOLD)
	label_at(chest + Vector2(-29, -54), "STASH", 18, GOLD)
	# Animated warp gate and its stone pillars.
	var gate := GATE_POS
	draw_circle(gate, 78, Color(0.3, 0.7, 1, 0.06))
	draw_circle(gate, 51, Color("1b4056"))
	draw_arc(gate, 57, 0, TAU, 60, Color("82b5ff"), 5, true)
	draw_arc(gate, 43, town_clock, town_clock + PI * 1.6, 40, MINT, 2, true)
	for side in [-1, 1]:
		draw_rect(Rect2(gate + Vector2(side * 70 - 10, -48), Vector2(20, 96)), Color("526177"))
		draw_line(gate + Vector2(side * 70, -33), gate + Vector2(side * 70, 28), MINT, 3)
	label_at(gate + Vector2(-51, -82), "WARP GATE", 18, MINT)
	draw_player()
	if panel.is_empty():
		if player.distance_to(STASH_POS) <= 110:
			label_at(chest + Vector2(-66, 67), "[E] OPEN STASH", 16, GOLD)
		elif player.distance_to(GATE_POS) <= 110:
			label_at(gate + Vector2(-84, 92), "[E] CHOOSE A MAP", 16, MINT)
	draw_set_transform(Vector2.ZERO)
	label_at(Vector2(58, 142), "HUNTER'S REST", 20, PALE)
	label_at(Vector2(58, 167), "A quiet place between expeditions", 13, MUTED)

func draw_panel() -> void:
	draw_rect(Rect2(0, 108, 1152, 540), Color(0.015, 0.025, 0.045, 0.82))
	draw_rect(Rect2(115, 140, 922, 480), Color("121d2a"))
	draw_rect(Rect2(115, 140, 922, 480), Color("506172"), false, 2)
	draw_rect(CLOSE_RECT, Color("293746"))
	label_at(CLOSE_RECT.position + Vector2(13, 23), "X", 19, PALE)
	if panel == "gate":
		label_at(Vector2(144, 186), "WAYPOINT / SELECT A DESTINATION", 24, MINT)
		label_at(Vector2(144, 222), "Defeat a map boss to unlock the next destination.", 16, MUTED)
		for i in range(3):
			var rect := map_rect(i)
			var available: bool = i < profile.unlocked
			draw_rect(rect, MAPS[i].color if available else Color("171c25"))
			draw_rect(rect, MINT if available and rect.has_point(get_global_mouse_position()) else Color("354355"), false, 2)
			label_at(rect.position + Vector2(16, 30), "0%d / ITEM TIER %d" % [i + 1, i + 1], 13, MUTED)
			label_at(rect.position + Vector2(16, 64), MAPS[i].name, 18, PALE if available else MUTED)
			label_at(rect.position + Vector2(16, 98), MAPS[i].boss, 15, GOLD)
			label_at(rect.position + Vector2(16, 143), "TRAVEL / CLICK OR %d" % (i + 1) if available else "LOCKED / CLEAR PREVIOUS MAP", 13, MINT if available else MUTED)
		label_at(Vector2(144, 574), "Esc / E to close", 15, MUTED)
		return
	label_at(Vector2(144, 179), "STASH & INVENTORY" if panel == "stash" else "INVENTORY", 23, GOLD)
	label_at(Vector2(160, 208), "EQUIPPED", 12, MUTED)
	for i in range(3):
		var item: Dictionary = profile.equipment[Profile.SLOTS[i]]
		draw_item_cell(equipment_rect(i), item)
		label_at(equipment_rect(i).position + Vector2(0, 62), Profile.SLOTS[i].to_upper(), 11, MUTED)
	label_at(Vector2(160, 306), "BACKPACK", 14, MINT)
	draw_grid(false)
	if panel == "stash":
		label_at(Vector2(612, 306), "PERSONAL STASH", 14, GOLD)
		draw_grid(true)
		label_at(Vector2(612, 245), "Click stored gear to take it out.", 15, PALE)
		label_at(Vector2(612, 271), "Shift-click backpack gear to store it.", 14, MUTED)
	else:
		label_at(Vector2(612, 269), "CHARACTER / LEVEL %d" % profile.level, 20, MINT)
		label_at(Vector2(612, 316), "Attack damage       %d" % damage, 18)
		label_at(Vector2(612, 350), "Maximum health      %d" % max_hp, 18)
		label_at(Vector2(612, 384), "Defense             %d" % armor, 18)
		label_at(Vector2(612, 418), "Attack interval     %.2fs" % attack_interval, 18)
		label_at(Vector2(612, 480), "Visit the stash in town to store gear.", 15, MUTED)
	label_at(Vector2(144, 598), "Hover: details & comparison  /  Click: equip  /  I or Esc: close" if hub else "Hover: details & comparison  /  Equip in town  /  I or Esc: close  /  World paused", 14, MUTED)
	var hovered := hovered_item(get_global_mouse_position())
	if not hovered.is_empty():
		draw_item_tooltip(hovered.item, hovered.equipped, hovered.storage)

func draw_grid(storage: bool) -> void:
	var items: Array[Dictionary] = profile.stash if storage else profile.inventory
	var current_page := stash_page if storage else page
	for cell in range(GRID_PAGE_SIZE):
		var index := current_page * GRID_PAGE_SIZE + cell
		draw_item_cell(grid_rect(cell, storage), items[index] if index < items.size() else {})
	var origin := Vector2(612 if storage else 160, 559)
	label_at(origin, "%d ITEMS / %d" % [items.size(), current_page + 1], 12, MUTED)
	for next in [false, true]:
		var rect := page_rect(storage, next)
		draw_rect(rect, Color("293746"))
		label_at(rect.position + Vector2(8, 18), "NEXT >" if next else "< PREV", 11, MINT)

func draw_item_cell(rect: Rect2, item: Dictionary) -> void:
	var hover := rect.has_point(get_global_mouse_position())
	draw_rect(rect, Color("263f4b") if hover else Color("0c1420"))
	draw_rect(rect, rarity_color(item).darkened(0.35) if not item.is_empty() else Color("304052"), false, 1)
	if item.is_empty():
		return
	var c := rect.get_center()
	var color := rarity_color(item)
	match item.slot:
		"weapon":
			draw_line(c + Vector2(-10, 12), c + Vector2(13, -14), color, 5, true)
			draw_line(c + Vector2(-13, 2), c + Vector2(0, 14), GOLD, 3, true)
		"armor":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -15), c + Vector2(-18, -5), c + Vector2(-11, 0), c + Vector2(-11, 14), c + Vector2(11, 14), c + Vector2(11, 0), c + Vector2(18, -5), c + Vector2(9, -15), c + Vector2(0, -9)]), color)
		"charm":
			draw_arc(c - Vector2(0, 5), 11, 0, TAU, 24, GOLD, 2, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(8, 7), c + Vector2(0, 17), c + Vector2(-8, 7)]), color)
	label_at(rect.position + Vector2(3, 11), str(int(item.tier)), 10, color)

func hovered_item(mouse: Vector2) -> Dictionary:
	for i in range(3):
		var item: Dictionary = profile.equipment[Profile.SLOTS[i]]
		if equipment_rect(i).has_point(mouse) and not item.is_empty():
			return {"item": item, "equipped": true, "storage": false}
	for storage in [false, true]:
		if storage and panel != "stash":
			continue
		var items: Array[Dictionary] = profile.stash if storage else profile.inventory
		for cell in range(GRID_PAGE_SIZE):
			var index := (stash_page if storage else page) * GRID_PAGE_SIZE + cell
			if grid_rect(cell, storage).has_point(mouse) and index < items.size():
				return {"item": items[index], "equipped": false, "storage": storage}
	return {}

func tooltip_rect(mouse: Vector2) -> Rect2:
	var origin := mouse + Vector2(20, 18)
	if origin.x + 350 > 1140:
		origin.x = mouse.x - 370
	origin.y = minf(origin.y, 704 - 260)
	return Rect2(origin.clamp(Vector2(12, 12), Vector2(790, 444)), Vector2(350, 260))

func draw_item_tooltip(item: Dictionary, equipped: bool, storage: bool) -> void:
	var rect := tooltip_rect(get_global_mouse_position())
	draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size), Color(0, 0, 0, 0.5))
	draw_rect(rect, Color("0c1420"))
	draw_rect(rect, rarity_color(item), false, 2)
	var p := rect.position + Vector2(16, 27)
	label_at(p, item.name, 19, rarity_color(item))
	label_at(p + Vector2(0, 26), "%s / %s / TIER %d" % [Profile.RARITIES[int(item.rarity)], item.slot.to_upper(), item.tier], 13, MUTED)
	draw_line(p + Vector2(0, 41), p + Vector2(316, 41), Color("304052"))
	var current: Dictionary = profile.equipment[item.slot]
	var keys := ["attack", "health", "armor", "haste"]
	var names := ["Attack damage", "Maximum health", "Defense", "Attack speed %"]
	for i in range(4):
		var key: String = keys[i]
		var delta := int(item[key]) - int(current.get(key, 0))
		label_at(p + Vector2(0, 67 + i * 26), "%s: %d" % [names[i], item[key]], 16)
		if not equipped:
			label_at(p + Vector2(261, 67 + i * 26), "%+d" % delta, 16, MINT if delta > 0 else (RED if delta < 0 else MUTED))
	label_at(p + Vector2(0, 178), "Currently equipped" if equipped else "Compared with: " + current.get("name", "Empty slot"), 12, MUTED)
	var hint := "Equipped"
	if not equipped:
		hint = "Click to take out" if storage else ("Click to equip" if hub else "Equip after returning to town")
		if panel == "stash" and not storage:
			hint += " / Shift-click to store"
	label_at(p + Vector2(0, 214), hint, 13, GOLD)

func draw_world() -> void:
	draw_set_transform(VIEW.position - camera)
	draw_rect(WORLD, MAPS[map_index].color)
	for x in range(0, 2401, 80):
		draw_line(Vector2(x, 0), Vector2(x, 1500), Color(0.6, 0.7, 0.8, 0.05))
	for y in range(0, 1501, 80):
		draw_line(Vector2(0, y), Vector2(2400, y), Color(0.6, 0.7, 0.8, 0.05))
	draw_line(Vector2(150, 750), Vector2(2180, 750), Color(0.5, 0.5, 0.5, 0.08), 110)
	draw_rect(WORLD.grow(-5), Color("4c5967"), false, 8)
	draw_arc(Vector2(180, 750), 48, 0, TAU, 40, MINT, 3, true)
	label_at(Vector2(116, 819), "T / TOWN PORTAL", 14, MINT)
	draw_arc(Vector2(2130, 750), 130, 0, TAU, 50, GOLD.darkened(0.5), 2, true)
	for drop in drops:
		var color := rarity_color(drop.item)
		draw_line(drop.pos, drop.pos - Vector2(0, 40), Color(color, 0.4), 3)
		draw_circle(drop.pos, 7, color)
		label_at(drop.pos + Vector2(12, -8), drop.item.name, 14, color)
		if player.distance_to(drop.pos) <= 90:
			label_at(drop.pos + Vector2(12, 12), "E / PICK UP", 12, MINT)
	for enemy in enemies:
		draw_enemy(enemy)
		if enemy.brute:
			label_at(enemy.pos - Vector2(65, 49), MAPS[map_index].boss, 17, GOLD)
	for particle in particles:
		var color: Color = particle.color
		color.a = minf(1, particle.life * 4)
		draw_circle(particle.pos, 2.5, color)
	draw_player()
	if slash > 0:
		draw_arc(player, 94, slash_angle - 1.2, slash_angle + 1.2, 28, Color(0.44, 0.94, 0.82, slash / 0.16), 7, true)
	if return_time > 0:
		draw_arc(player, 40, -PI / 2, -PI / 2 + TAU * (1 - return_time / 2), 40, MINT, 4, true)
	for notice in notices:
		label_at(notice.pos, notice.text, 19, notice.color)
	draw_set_transform(Vector2.ZERO)
	# Cover world overflow so UI stays in viewport coordinates.
	draw_rect(Rect2(0, 0, 1152, 108), Color("0b101a"))
	draw_rect(Rect2(0, 648, 1152, 72), Color("0b101a"))
	draw_rect(Rect2(0, 108, 24, 540), Color("0b101a"))
	draw_rect(Rect2(1128, 108, 24, 540), Color("0b101a"))
	draw_rect(VIEW, Color("354355"), false)
	var mini_rect := Rect2(948, 122, 164, 103)
	draw_rect(mini_rect, Color(0.02, 0.04, 0.06, 0.85))
	for enemy in enemies:
		draw_circle(mini_rect.position + enemy.pos / WORLD.size * mini_rect.size, 4 if enemy.brute else 2, GOLD if enemy.brute else RED)
	draw_circle(mini_rect.position + player / WORLD.size * mini_rect.size, 3, MINT)
	label_at(Vector2(34, 135), "BOSS DEFEATED / COLLECT LOOT & RETURN" if map_cleared else "FIND & DEFEAT THE MAP BOSS", 15, GOLD)

func draw_hud() -> void:
	label_at(Vector2(28, 41), "E M B E R", 29, GOLD)
	label_at(Vector2(30, 67), "TOWN / HUNTER'S REST" if hub else MAPS[map_index].name, 13, MUTED)
	label_at(Vector2(340, 29), "VITALITY %d / %d" % [hp, max_hp], 13)
	bar(Rect2(340, 41, 240, 9), hp / max_hp, RED)
	label_at(Vector2(624, 29), "LEVEL %d / XP %d OF %d" % [profile.level, profile.xp, profile.xp_needed()], 13, MINT)
	bar(Rect2(624, 41, 235, 5), float(profile.xp) / profile.xp_needed(), MINT)
	label_at(Vector2(920, 32), "BAG %d / STASH %d" % [profile.inventory.size(), profile.stash.size()], 14, GOLD)
	label_at(Vector2(920, 58), "MAPS %d / 3" % profile.unlocked if hub else "POTIONS %d / 3 [Q]" % potions, 13, MUTED)
	label_at(Vector2(30, 93), message, 15, MINT)
	label_at(Vector2(30, 683), "WASD Move  /  E Interact nearby  /  I Inventory  /  Esc Pause" if hub else "WASD Move  /  Mouse Aim  /  LMB or Space Attack  /  Shift Dodge  /  E Loot  /  Q Heal  /  T Town  /  I Bag  /  Esc Pause", 14, MUTED)

func draw_overlay(title: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color(0.025, 0.04, 0.065, 0.93))
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	label_at(Vector2((1152 - width) / 2, 260), title, 32, GOLD)
	width = font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	label_at(Vector2((1152 - width) / 2, 305), subtitle, 18, MUTED)
func draw_enemy(enemy: Dictionary) -> void:
	var pos: Vector2 = enemy.pos
	var radius: float = enemy.radius
	var color := GOLD if enemy.brute else RED
	if enemy.flash > 0:
		color = Color.WHITE
	draw_circle(pos + Vector2(0, radius * 0.6), radius, Color(0, 0, 0, 0.25))
	var points := PackedVector2Array()
	for j in range(6):
		points.append(pos + Vector2.UP.rotated(j * TAU / 6) * radius)
	draw_colored_polygon(points, color.darkened(0.24))
	points.append(points[0])
	draw_polyline(points, color, 2, true)
	draw_line(pos + Vector2(-7, -2), pos + Vector2(-2, 1), PALE, 2)
	draw_line(pos + Vector2(2, 1), pos + Vector2(7, -2), PALE, 2)
	if enemy.hp < enemy.max_hp:
		bar(Rect2(pos + Vector2(-18, -radius - 9), Vector2(36, 3)), enemy.hp / enemy.max_hp, RED)

func draw_player() -> void:
	draw_circle(player + Vector2(0, 10), 19, Color(0, 0, 0, 0.3))
	var player_color := Color.WHITE if invincible > 0 and int(invincible * 24) % 2 == 0 else MINT
	draw_colored_polygon(PackedVector2Array([player + Vector2(-14, 14), player + Vector2(-11, -9), player + Vector2(0, -18), player + Vector2(11, -9), player + Vector2(14, 14)]), player_color)
	draw_rect(Rect2(player + Vector2(-8, -7), Vector2(16, 8)), Color("101926"))
	draw_line(player + Vector2(-5, -3), player + Vector2(5, -3), GOLD, 2)
	var hand := player + facing * 21
	draw_line(hand - facing.orthogonal() * 6, hand + facing.orthogonal() * 6, GOLD, 3, true)
	draw_line(hand, player + facing * 47, PALE, 5, true)
