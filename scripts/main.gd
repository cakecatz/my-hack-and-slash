extends Node2D

const ARENA := Rect2(44, 112, 1064, 546)
const INK := Color("101926")
const MINT := Color("70efd0")
const GOLD := Color("ffc478")
const RED := Color("f27386")
const PALE := Color("e0e9f4")
const MUTED := Color("8597ae")

var player := Vector2(576, 385)
var facing := Vector2.RIGHT
var hp := 100.0
var max_hp := 100.0
var damage := 24.0
var attack_interval := 0.34
var attack_cooldown := 0.0
var slash := 0.0
var slash_angle := 0.0
var dash_time := 0.0
var dash_cooldown := 0.0
var dash_direction := Vector2.RIGHT
var invincible := 0.0
var elapsed := 0.0
var wave := 0
var wave_delay := 1.0
var kills := 0
var level := 1
var xp := 0
var xp_needed := 6
var upgrade_pending := false
var paused := false
var ended := false
var won := false
var enemies: Array[Dictionary] = []
var gems: Array[Vector2] = []
var particles: Array[Dictionary] = []
var notices: Array[Dictionary] = []
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	for action in ["left", "right", "up", "down", "attack", "dash"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	bind_key("left", KEY_A)
	bind_key("left", KEY_LEFT)
	bind_key("right", KEY_D)
	bind_key("right", KEY_RIGHT)
	bind_key("up", KEY_W)
	bind_key("up", KEY_UP)
	bind_key("down", KEY_S)
	bind_key("down", KEY_DOWN)
	bind_key("attack", KEY_SPACE)
	bind_key("dash", KEY_SHIFT)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)

func bind_key(action: String, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and ended:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE and not ended and not upgrade_pending:
			paused = not paused
		elif upgrade_pending:
			if event.keycode == KEY_1:
				choose_upgrade(0)
			elif event.keycode == KEY_2:
				choose_upgrade(1)
			elif event.keycode == KEY_3:
				choose_upgrade(2)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and upgrade_pending:
		for i in range(3):
			if upgrade_rect(i).has_point(get_global_mouse_position()):
				choose_upgrade(i)
				break

func _process(delta: float) -> void:
	if not paused and not upgrade_pending and not ended:
		step(delta)
	queue_redraw()

func step(delta: float) -> void:
	elapsed += delta
	attack_cooldown = maxf(0, attack_cooldown - delta)
	slash = maxf(0, slash - delta)
	dash_time = maxf(0, dash_time - delta)
	dash_cooldown = maxf(0, dash_cooldown - delta)
	invincible = maxf(0, invincible - delta)
	var movement := Input.get_vector("left", "right", "up", "down")
	var aim := get_global_mouse_position() - player
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
	if Input.is_action_pressed("attack") and attack_cooldown <= 0:
		attack()
	for enemy in enemies:
		var direction: Vector2 = enemy.pos.direction_to(player)
		enemy.pos = clamp_point(enemy.pos + direction * enemy.speed * delta, enemy.radius)
		enemy.flash = maxf(0, enemy.flash - delta)
		if enemy.pos.distance_to(player) < enemy.radius + 16 and invincible <= 0:
			hp = maxf(0, hp - enemy.damage)
			invincible = 0.65
			burst(player, RED, 14)
			notices.append({"pos": player - Vector2(0, 30), "text": "-%d" % enemy.damage, "life": 0.7, "color": RED})
			if hp <= 0:
				ended = true
				return
	for i in range(gems.size() - 1, -1, -1):
		var distance := gems[i].distance_to(player)
		if distance < 135:
			gems[i] = gems[i].move_toward(player, 440 * delta)
		if gems[i].distance_to(player) < 23:
			gems.remove_at(i)
			xp += 1
			check_level()
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
	if enemies.is_empty():
		if wave >= 10:
			ended = true
			won = true
		else:
			wave_delay -= delta
			if wave_delay <= 0:
				spawn_wave()

func clamp_point(point: Vector2, margin: float) -> Vector2:
	return point.clamp(ARENA.position + Vector2.ONE * margin, ARENA.end - Vector2.ONE * margin)

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
		enemy.pos = clamp_point(enemy.pos + offset.normalized() * 27, enemy.radius)
		burst(enemy.pos, GOLD, 9)
		notices.append({"pos": enemy.pos - Vector2(0, 24), "text": str(int(damage)), "life": 0.6, "color": GOLD})
		if enemy.hp <= 0:
			gems.append(enemy.pos)
			kills += 1
			enemies.remove_at(i)

func spawn_wave() -> void:
	wave += 1
	wave_delay = 2.0
	hp = minf(max_hp, hp + 10)
	for i in range(4 + wave * 2):
		var pos := Vector2.ZERO
		match i % 4:
			0: pos = Vector2(randf_range(65, 1087), 137)
			1: pos = Vector2(1085, randf_range(138, 630))
			2: pos = Vector2(randf_range(65, 1087), 631)
			3: pos = Vector2(66, randf_range(138, 630))
		if pos.distance_to(player) < 220:
			pos = Vector2(1152, 770) - pos
		var brute := wave >= 3 and i % 4 == 0
		var health := (30.0 + wave * 7) * (2.2 if brute else 1.0)
		enemies.append({"pos": pos, "hp": health, "max_hp": health, "radius": 23.0 if brute else 15.0, "speed": 57.0 + wave * 3 if brute else 88.0 + wave * 4, "damage": 19 if brute else 10, "flash": 0.0, "brute": brute})

func check_level() -> void:
	if xp >= xp_needed and not upgrade_pending:
		xp -= xp_needed
		level += 1
		xp_needed += 4
		upgrade_pending = true

func choose_upgrade(choice: int) -> void:
	match choice:
		0: damage += 12
		1: attack_interval = maxf(0.12, attack_interval * 0.85)
		2:
			max_hp += 25
			hp = minf(max_hp, hp + 60)
	upgrade_pending = false
	check_level()

func burst(pos: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		particles.append({"pos": pos, "velocity": Vector2.RIGHT.rotated(randf() * TAU) * randf_range(30, 170), "life": randf_range(0.15, 0.4), "color": color})

func label_at(pos: Vector2, value: String, size: int, color: Color = PALE) -> void:
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("263346"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

func upgrade_rect(index: int) -> Rect2:
	return Rect2(191 + index * 266, 315, 246, 158)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color("0b101a"))
	draw_rect(ARENA, Color("121d2a"))
	for x in range(44, 1109, 38):
		draw_line(Vector2(x, 112), Vector2(x, 658), Color("1b2836"))
	for y in range(112, 659, 38):
		draw_line(Vector2(44, y), Vector2(1108, y), Color("1b2836"))
	draw_arc(Vector2(576, 385), 176, 0, TAU, 80, Color("233342"), 2, true)
	draw_arc(Vector2(576, 385), 185, 0, TAU, 80, Color("1d2b3b"), 1, true)
	draw_rect(ARENA, Color("354355"), false, 2)
	for corner in [Vector2(44, 112), Vector2(1108, 112), Vector2(44, 658), Vector2(1108, 658)]:
		draw_circle(corner, 7, GOLD)
	for gem in gems:
		draw_circle(gem, 12, Color(0.3, 0.9, 0.8, 0.08))
		draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -7), gem + Vector2(5, 0), gem + Vector2(0, 7), gem + Vector2(-5, 0)]), MINT)
	for enemy in enemies:
		draw_enemy(enemy)
	for particle in particles:
		var color: Color = particle.color
		color.a = minf(1, particle.life * 4)
		draw_circle(particle.pos, 2.5, color)
	draw_circle(player + Vector2(0, 10), 19, Color(0, 0, 0, 0.3))
	var player_color := MINT
	if invincible > 0 and int(invincible * 24) % 2 == 0:
		player_color = Color.WHITE
	draw_circle(player, 21, Color(0.3, 0.9, 0.8, 0.09))
	draw_colored_polygon(PackedVector2Array([player + Vector2(-14, 14), player + Vector2(-11, -9), player + Vector2(0, -18), player + Vector2(11, -9), player + Vector2(14, 14)]), player_color)
	draw_rect(Rect2(player + Vector2(-8, -7), Vector2(16, 8)), INK)
	draw_line(player + Vector2(-5, -3), player + Vector2(5, -3), GOLD, 2)
	var hand := player + facing * 21
	draw_line(hand - facing.orthogonal() * 6, hand + facing.orthogonal() * 6, GOLD, 3, true)
	draw_line(hand, player + facing * 47, PALE, 5, true)
	if slash > 0:
		var alpha := slash / 0.16
		draw_arc(player, 94, slash_angle - 1.2, slash_angle + 1.2, 28, Color(0.44, 0.94, 0.82, alpha), 7, true)
		draw_arc(player, 106, slash_angle - 1.1, slash_angle + 1.1, 28, Color(0.9, 1, 0.95, alpha * 0.7), 2, true)
	for notice in notices:
		label_at(notice.pos, notice.text, 19, notice.color)
	draw_hud()
	if upgrade_pending:
		draw_overlay("CHOOSE YOUR POWER", "LEVEL %02d  /  Select an upgrade" % level)
		var titles := ["01  /  SHARPEN", "02  /  FRENZY", "03  /  VITALITY"]
		var descriptions := ["Attack damage +12", "Attack interval -15%", "Max HP +25 / Heal 60"]
		for i in range(3):
			var rect := upgrade_rect(i)
			var hover := rect.has_point(get_global_mouse_position())
			draw_rect(rect, Color("253d43") if hover else Color("182535"))
			draw_rect(rect, MINT if hover else Color("425266"), false, 2)
			label_at(rect.position + Vector2(20, 45), titles[i], 20, MINT)
			label_at(rect.position + Vector2(20, 87), descriptions[i], 16)
			label_at(rect.position + Vector2(20, 128), "CLICK OR PRESS %d" % (i + 1), 13, MUTED)
	elif ended:
		draw_overlay("DAWN BREAKS" if won else "THE EMBER FADES", "VICTORY" if won else "DEFEATED")
		label_at(Vector2(402, 363), "%d KILLS    /    LEVEL %d" % [kills, level], 24, GOLD)
		label_at(Vector2(435, 422), "Press R to play again", 23, MINT)
	elif paused:
		draw_overlay("PAUSED", "Press Esc to resume")

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

func draw_hud() -> void:
	label_at(Vector2(44, 45), "E M B E R", 30, GOLD)
	label_at(Vector2(45, 72), "THE HOLLOW TRIAL", 13, MUTED)
	label_at(Vector2(310, 38), "VITALITY", 12, MUTED)
	bar(Rect2(310, 49, 244, 10), hp / max_hp, RED)
	label_at(Vector2(310, 81), "%d / %d" % [hp, max_hp], 14)
	label_at(Vector2(602, 38), "LEVEL %02d" % level, 12, MINT)
	bar(Rect2(602, 49, 182, 5), float(xp) / xp_needed, MINT)
	label_at(Vector2(602, 81), "%d / %d ESSENCE" % [xp, xp_needed], 13, MUTED)
	label_at(Vector2(845, 43), "WAVE %02d / 10" % wave, 21)
	label_at(Vector2(845, 76), "%03d KILLS  /  %02d:%02d" % [kills, int(elapsed) / 60, int(elapsed) % 60], 14, MUTED)
	label_at(Vector2(44, 695), "WASD  MOVE     /     MOUSE  AIM     /     LMB or SPACE  ATTACK", 13, MUTED)
	label_at(Vector2(669, 695), "SHIFT  DODGE", 13, MINT if dash_cooldown <= 0 else MUTED)
	bar(Rect2(790, 687, 90, 4), 1 - dash_cooldown / 1.1, MINT)
	label_at(Vector2(970, 695), "ESC  PAUSE", 13, MUTED)
	if enemies.is_empty() and not ended:
		label_at(Vector2(451, 180), "WAVE %02d INCOMING" % (wave + 1), 22, GOLD)

func draw_overlay(title: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, 1152, 720), Color(0.025, 0.04, 0.065, 0.93))
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	label_at(Vector2((1152 - title_width) / 2, 240), title, 38, GOLD)
	var subtitle_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	label_at(Vector2((1152 - subtitle_width) / 2, 277), subtitle, 18, MUTED)
