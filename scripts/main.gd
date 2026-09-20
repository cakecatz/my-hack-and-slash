extends Node2D

const Profile = preload("res://scripts/profile.gd")
const VIEW := Rect2(24, 108, 1104, 540)
const WORLD := Rect2(0, 0, 2400, 1500)
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
var player := Vector2(180, 750)
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
var message := "Choose a destination. Hunt, collect gear, return and equip."
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
		if event.keycode == KEY_ESCAPE and not hub:
			paused = not paused
			return
		if paused:
			return
		if hub:
			if event.keycode >= KEY_1 and event.keycode <= KEY_3:
				enter_map(event.keycode - KEY_1)
		elif event.keycode == KEY_E:
			pickup_nearby()
		elif event.keycode == KEY_T:
			return_time = 2.0
			message = "Opening town portal... Stand still for 2 seconds."
		elif event.keycode == KEY_Q:
			if potions > 0 and hp < max_hp:
				potions -= 1
				hp = minf(max_hp, hp + max_hp * 0.5)
	if event is InputEventMouseButton and event.pressed and hub:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			page = mini(page + 1, maxi(0, (profile.inventory.size() - 1) / 6))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			page = maxi(0, page - 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var mouse := get_global_mouse_position()
			for i in range(3):
				if map_rect(i).has_point(mouse):
					enter_map(i)
					return
			for row in range(6):
				if item_rect(row).has_point(mouse):
					equip_item(page * 6 + row)
					return
			if Rect2(950, 616, 70, 28).has_point(mouse):
				page = maxi(0, page - 1)
			if Rect2(1030, 616, 70, 28).has_point(mouse):
				page = mini(page + 1, maxi(0, (profile.inventory.size() - 1) / 6))

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
	ended = false
	paused = false
	return_time = 0
	refresh_stats()
	hp = max_hp
	message = "%s / %d kills / %d items collected. Equip your loot below." % ["Rescued: collected gear retained" if defeated else "Returned to town", kills, found]
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
	if not hub and not paused and not ended:
		step(delta)
	queue_redraw()

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
	var attacking := Input.is_action_pressed("attack")
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
	return Rect2(44 + index * 365, 143, 340, 132)

func item_rect(row: int) -> Rect2:
	return Rect2(470, 330 + row * 46, 630, 42)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("0b101a"))
	if hub:
		draw_hub()
	else:
		draw_world()
	draw_hud()
	if not profile.save_error.is_empty():
		label_at(Vector2(30, 715), profile.save_error, 13, RED)
	if ended:
		draw_overlay("RESCUED FROM THE DEPTHS", "Collected gear and character progress are retained.")
		label_at(Vector2(389, 397), "Press R to return to town", 24, MINT)
	elif paused:
		draw_overlay("PAUSED", "Esc to resume")

func draw_hub() -> void:
	label_at(Vector2(44, 128), "WAYPOINT / SELECT A MAP", 16, MINT)
	for i in range(3):
		var rect := map_rect(i)
		var available: bool = i < profile.unlocked
		draw_rect(rect, MAPS[i].color if available else Color("171c25"))
		draw_rect(rect, MINT if available and rect.has_point(get_global_mouse_position()) else Color("354355"), false, 1)
		label_at(rect.position + Vector2(18, 29), "%02d / %s" % [i + 1, MAPS[i].name], 18, PALE if available else MUTED)
		label_at(rect.position + Vector2(18, 60), "Item tier %d  /  %s" % [i + 1, MAPS[i].boss], 14, MUTED)
		label_at(rect.position + Vector2(18, 104), "CLICK TO TRAVEL / %d" % (i + 1) if available else "Defeat the previous map boss to unlock", 14, MINT if available else MUTED)
	label_at(Vector2(44, 312), "EQUIPPED / PERMANENT CHARACTER", 16, MINT)
	for i in range(3):
		var slot: String = Profile.SLOTS[i]
		var item: Dictionary = profile.equipment[slot]
		var origin := Vector2(44, 330 + i * 87)
		draw_rect(Rect2(origin, Vector2(400, 77)), Color("172231"))
		label_at(origin + Vector2(14, 20), slot.to_upper(), 12, MUTED)
		label_at(origin + Vector2(14, 43), item.get("name", "None"), 17, rarity_color(item) if not item.is_empty() else MUTED)
		label_at(origin + Vector2(14, 64), item_stats(item), 13)
	label_at(Vector2(44, 626), "ATK %.0f / HP %.0f / DEF %.0f / %.2fs" % [damage, max_hp, armor, attack_interval], 17, GOLD)
	label_at(Vector2(470, 312), "STASH / CLICK AN ITEM TO EQUIP", 16, MINT)
	for row in range(6):
		var index := page * 6 + row
		if index >= profile.inventory.size():
			break
		var item: Dictionary = profile.inventory[index]
		var rect := item_rect(row)
		var hover := rect.has_point(get_global_mouse_position())
		draw_rect(rect, Color("29414a") if hover else Color("172231"))
		label_at(rect.position + Vector2(12, 18), "%s [%s T%d]" % [item.name, Profile.RARITIES[int(item.rarity)], item.tier], 15, rarity_color(item))
		label_at(rect.position + Vector2(12, 35), item_stats(item), 12)
		if hover:
			var current: Dictionary = profile.equipment[item.slot]
			label_at(Vector2(470, 640), "CHANGE: ATK %+d / HP %+d / DEF %+d / SPD %+d%%" % [item.attack - current.get("attack", 0), item.health - current.get("health", 0), item.armor - current.get("armor", 0), item.haste - current.get("haste", 0)], 13, GOLD)
	if profile.inventory.is_empty():
		label_at(Vector2(488, 371), "Your stash is empty. Find equipment on expeditions.", 17, MUTED)
	label_at(Vector2(470, 624), "%d ITEMS / PAGE %d" % [profile.inventory.size(), page + 1], 12, MUTED)
	label_at(Vector2(960, 635), "< PREV", 14, MINT)
	label_at(Vector2(1035, 635), "NEXT >", 14, MINT)

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
	draw_circle(player + Vector2(0, 10), 19, Color(0, 0, 0, 0.3))
	var player_color := Color.WHITE if invincible > 0 and int(invincible * 24) % 2 == 0 else MINT
	draw_colored_polygon(PackedVector2Array([player + Vector2(-14, 14), player + Vector2(-11, -9), player + Vector2(0, -18), player + Vector2(11, -9), player + Vector2(14, 14)]), player_color)
	draw_rect(Rect2(player + Vector2(-8, -7), Vector2(16, 8)), Color("101926"))
	draw_line(player + Vector2(-5, -3), player + Vector2(5, -3), GOLD, 2)
	var hand := player + facing * 21
	draw_line(hand - facing.orthogonal() * 6, hand + facing.orthogonal() * 6, GOLD, 3, true)
	draw_line(hand, player + facing * 47, PALE, 5, true)
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
	label_at(Vector2(920, 32), "%d ITEMS OWNED" % profile.inventory.size(), 14, GOLD)
	label_at(Vector2(920, 58), "MAPS %d / 3" % profile.unlocked if hub else "POTIONS %d / 3 [Q]" % potions, 13, MUTED)
	label_at(Vector2(30, 93), message, 15, MINT)
	label_at(Vector2(30, 683), "Select map: click / 1-3     |     Equip: click stash item     |     Pages: wheel / arrows" if hub else "WASD Move  /  Mouse Aim  /  LMB or Space Attack  /  Shift Dodge  /  E Loot  /  Q Heal  /  T Town  /  Esc Pause", 14, MUTED)

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
