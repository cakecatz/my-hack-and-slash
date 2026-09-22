extends RefCounted
## Boss state machines and shared telegraph geometry. No persistent state.

static func setup(boss: Dictionary, id: int) -> void:
	boss.boss_id = id
	boss.state = "approach"
	boss.timer = 0.6
	boss.cycle = 0
	boss.phase = 1
	boss.weak_time = 0.0
	boss.charge_hit = false
	boss.move_name = "APPROACH"

static func warning(scene: Node, boss: Dictionary, shape: String, duration: float, extra: Dictionary) -> void:
	var hazard := {"pos": boss.pos, "radius": 160.0, "damage": boss.damage * 1.5, "time": duration, "duration": duration, "shape": shape, "owner": boss.boss_id}
	hazard.merge(extra, true)
	scene.hazards.append(hazard)

static func recover(boss: Dictionary, duration: float) -> void:
	boss.state = "recovery"
	boss.timer = duration
	boss.move_name = "OPENING / ATTACK NOW"

static func stone_count(scene: Node, boss: Dictionary) -> int:
	var count := 0
	for stone in scene.boss_stones:
		if stone.owner == boss.boss_id:
			count += 1
	return count

static func multiplier(scene: Node, boss: Dictionary) -> float:
	if boss.weak_time > 0:
		return 1.35
	return 0.7 if stone_count(scene, boss) > 0 else 1.0

static func begin_move(scene: Node, boss: Dictionary) -> void:
	var direction: Vector2 = (scene.player - boss.pos).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	boss.state = "windup"
	boss.cycle += 1
	match scene.map_index:
		0:
			if boss.cycle % 2 == 1:
				boss.move_name = "SWEEP / GET BEHIND"
				boss.move = "sweep"
				boss.timer = 0.9
				warning(scene, boss, "sector", 0.9, {"direction": direction, "half_angle": 1.15, "radius": 175.0})
			else:
				boss.move_name = "CHARGE / DODGE SIDEWAYS"
				boss.move = "charge"
				boss.timer = 1.1
				boss.start = boss.pos
				boss.finish = scene.layout.move_body(boss.pos, direction * minf(450, boss.pos.distance_to(scene.player) + 120), boss.radius, false)
				warning(scene, boss, "line", 1.1, {"end": boss.finish, "radius": boss.radius, "preview_only": true})
		1:
			if boss.cycle % 3 == 2 and stone_count(scene, boss) == 0:
				boss.move = "stones"
				boss.move_name = "WARD STONES / BREAK TO EXPOSE"
				boss.timer = 1.0
				warning(scene, boss, "circle", 1.0, {"radius": 130.0, "preview_only": true})
			else:
				boss.move = "beam"
				boss.move_name = "SOUL BEAM / LEAVE THE LINE"
				boss.timer = 1.05
				warning(scene, boss, "line", 1.05, {"end": scene.layout.move_body(boss.pos, direction * 650, 1, false), "radius": 23.0})
		2:
			boss.timer = 1.4
			if boss.cycle % 2 == 1:
				boss.move = "ring"
				boss.move_name = "FIRE RING / FIND THE GREEN GAP"
				warning(scene, boss, "ring", 1.4, {"radius": 300.0, "inner": 95.0, "direction": direction.rotated(PI / 2), "half_angle": 0.7})
				if boss.phase == 2:
					warning(scene, boss, "circle", 1.0, {"pos": scene.player, "radius": 65.0})
			else:
				boss.move = "marks"
				boss.move_name = "CINDER MARKS / KEEP MOVING"
				warning(scene, boss, "circle", 1.0, {"pos": scene.player, "radius": 85.0})
				if boss.phase == 2:
					warning(scene, boss, "circle", 1.4, {"pos": scene.player + direction.orthogonal() * 140, "radius": 75.0})
					warning(scene, boss, "circle", 1.8, {"pos": scene.player - direction.orthogonal() * 140, "radius": 75.0})
					boss.timer = 1.8

static func step(scene: Node, boss: Dictionary, delta: float) -> void:
	boss.weak_time = maxf(0, boss.weak_time - delta)
	boss.flash = maxf(0, boss.flash - delta)
	boss.phase = 2 if scene.map_index == 2 and boss.hp <= boss.max_hp * 0.5 else 1
	if not boss.aggro:
		if boss.pos.distance_to(scene.player) > 400 or not scene.layout.segment_clear(boss.pos, scene.player):
			return
		boss.aggro = true
	boss.timer = maxf(0, boss.timer - delta)
	match boss.state:
		"approach":
			var desired := 150.0 if scene.map_index == 0 else 230.0
			if boss.pos.distance_to(scene.player) > desired:
				boss.pos = scene.layout.chase(boss.pos, scene.player, boss.radius, boss.speed * boss.slow_factor * delta)
			if boss.timer <= 0 and boss.pos.distance_to(scene.player) <= 400 and scene.layout.segment_clear(boss.pos, scene.player):
				begin_move(scene, boss)
		"windup":
			if boss.timer <= 0:
				if boss.move == "charge":
					boss.state = "charge"
					boss.timer = 0.45
					boss.charge_hit = false
				elif boss.move == "stones":
					for offset in [Vector2(0, -130), Vector2(0, 130)]:
						var health: float = maxf(65, boss.max_hp * 0.05)
						scene.boss_stones.append({"owner": boss.boss_id, "pos": scene.layout.safe_position(boss.pos + offset, 22), "hp": health, "max_hp": health})
					recover(boss, 1.3)
				else:
					recover(boss, 1.2 if scene.map_index == 0 else 1.6)
		"charge":
			var previous: Vector2 = boss.pos
			boss.pos = boss.start.lerp(boss.finish, 1 - boss.timer / 0.45)
			var nearest := Geometry2D.get_closest_point_to_segment(scene.player, previous, boss.pos)
			if not boss.charge_hit and nearest.distance_to(scene.player) <= boss.radius + 16:
				scene.take_hit(boss.damage * 1.6)
				boss.charge_hit = true
			if boss.timer <= 0:
				recover(boss, 2.0)
		"recovery":
			if boss.timer <= 0:
				boss.state = "approach"
				boss.move_name = "APPROACH"
				boss.timer = 0.35

static func contains(hazard: Dictionary, point: Vector2, body_radius: float = 16.0) -> bool:
	if hazard.get("preview_only", false):
		return false
	var offset: Vector2 = point - hazard.pos
	match hazard.get("shape", "circle"):
		"line":
			return Geometry2D.get_closest_point_to_segment(point, hazard.pos, hazard.end).distance_to(point) <= hazard.radius + body_radius
		"sector":
			return offset.length() <= hazard.radius + body_radius and (offset.length() <= body_radius or absf(hazard.direction.angle_to(offset)) <= hazard.half_angle + asin(minf(1, body_radius / offset.length())))
		"ring":
			if offset.length() + body_radius < hazard.inner or offset.length() > hazard.radius + body_radius:
				return false
			return absf(hazard.direction.angle_to(offset)) > hazard.half_angle - asin(minf(1, body_radius / maxf(1, offset.length())))
		_:
			return offset.length() <= hazard.radius + body_radius

static func draw_warning(scene: Node2D, hazard: Dictionary) -> void:
	var color := Color("a998f5") if hazard.get("preview_only", false) and hazard.get("shape", "circle") == "circle" else Color("f27386")
	var fill := Color(color, 0.16)
	var progress: float = 1 - float(hazard.time) / hazard.duration
	match hazard.get("shape", "circle"):
		"line":
			scene.draw_line(hazard.pos, hazard.end, fill, hazard.radius * 2, true)
			var normal: Vector2 = (hazard.end - hazard.pos).normalized().orthogonal() * hazard.radius
			for side in [-1, 1]:
				scene.draw_line(hazard.pos + normal * side, hazard.end + normal * side, color, 2, true)
			scene.draw_line(hazard.pos, hazard.pos.lerp(hazard.end, progress), Color("ffc478"), 3, true)
		"sector":
			var points := PackedVector2Array([hazard.pos])
			for i in range(33):
				points.append(hazard.pos + hazard.direction.rotated(lerpf(-hazard.half_angle, hazard.half_angle, i / 32.0)) * hazard.radius)
			scene.draw_colored_polygon(points, fill)
			points.append(hazard.pos)
			scene.draw_polyline(points, color, 2, true)
			scene.draw_arc(hazard.pos, hazard.radius * progress, hazard.direction.angle() - hazard.half_angle, hazard.direction.angle() + hazard.half_angle, 32, Color("ffc478"), 2, true)
		"ring":
			var start: float = hazard.direction.angle() + hazard.half_angle
			var finish: float = hazard.direction.angle() + TAU - hazard.half_angle
			var points := PackedVector2Array()
			for i in range(49):
				points.append(hazard.pos + Vector2.RIGHT.rotated(lerpf(start, finish, i / 48.0)) * hazard.radius)
			for i in range(48, -1, -1):
				points.append(hazard.pos + Vector2.RIGHT.rotated(lerpf(start, finish, i / 48.0)) * hazard.inner)
			scene.draw_colored_polygon(points, fill)
			scene.draw_arc(hazard.pos, hazard.radius, start, finish, 48, color, 2, true)
			scene.draw_arc(hazard.pos, lerpf(hazard.inner, hazard.radius, progress), start, finish, 48, Color("ffc478"), 2, true)
			for angle in [-hazard.half_angle, hazard.half_angle]:
				scene.draw_line(hazard.pos + hazard.direction.rotated(angle) * hazard.inner, hazard.pos + hazard.direction.rotated(angle) * hazard.radius, Color("70efd0"), 4, true)
		_:
			scene.draw_circle(hazard.pos, hazard.radius, fill)
			scene.draw_arc(hazard.pos, hazard.radius, 0, TAU, 48, color, 2, true)
			scene.draw_arc(hazard.pos, hazard.radius * progress, 0, TAU, 40, Color("ffc478"), 3, true)
