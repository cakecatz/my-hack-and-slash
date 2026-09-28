extends RefCounted
## Hand-built room templates. One is picked at random per expedition and may be
## mirrored, so routes vary while every template stays fully connected.

const CELL := 40
const SIZE := Vector2i(60, 38)
const WORLD := Vector2(2400, 1500)
const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## Rooms are edge-shared with corridors; connecting edges land on cell centres.
const TEMPLATES := [
	{
		"name": "CROSSROADS",
		"rooms": [
			{"rect": Rect2(80, 560, 360, 400), "name": "ARRIVAL"},
			{"rect": Rect2(440, 680, 360, 160), "name": "NARROW PASS"},
			{"rect": Rect2(800, 440, 440, 640), "name": "PILLAR HALL / SEAL I"},
			{"rect": Rect2(1320, 440, 400, 640), "name": "ENCIRCLEMENT / SEAL II"},
			{"rect": Rect2(840, 80, 400, 240), "name": "CURSED VAULT / OPTIONAL"},
			{"rect": Rect2(1760, 280, 560, 960), "name": "GUARDIAN SANCTUM"}
		],
		"corridors": [Rect2(1240, 680, 80, 160), Rect2(1720, 680, 40, 160), Rect2(1000, 320, 120, 120)],
		"pillars": [Rect2(920, 600, 80, 120), Rect2(1120, 840, 80, 120)],
		"chapter_pillars": [[], [Rect2(1440, 600, 80, 80)], [Rect2(1480, 880, 120, 80)]],
		"arrival": Vector2(180, 750),
		"shrine": Vector2(340, 620),
		"boss": Vector2(2130, 750),
		"cache": Vector2(1060, 200),
		"seals": [Vector2(1060, 780), Vector2(1500, 780)],
		"optional": [Vector2(940, 200), Vector2(1140, 200)]
	},
	{
		"name": "RING",
		"rooms": [
			{"rect": Rect2(80, 620, 360, 320), "name": "ARRIVAL"},
			{"rect": Rect2(400, 720, 240, 140), "name": "NARROW PASS"},
			{"rect": Rect2(600, 520, 440, 520), "name": "PILLAR HALL / SEAL I"},
			{"rect": Rect2(1160, 520, 440, 520), "name": "ENCIRCLEMENT / SEAL II"},
			{"rect": Rect2(600, 200, 400, 240), "name": "CURSED VAULT / OPTIONAL"},
			{"rect": Rect2(1760, 520, 560, 520), "name": "GUARDIAN SANCTUM"}
		],
		"corridors": [Rect2(1000, 680, 240, 200), Rect2(1560, 720, 240, 140), Rect2(760, 400, 120, 160)],
		"pillars": [Rect2(700, 600, 80, 120), Rect2(880, 860, 80, 120)],
		"chapter_pillars": [[], [Rect2(1280, 640, 120, 80)], [Rect2(1400, 880, 80, 120)]],
		"arrival": Vector2(180, 780),
		"shrine": Vector2(200, 900),
		"boss": Vector2(2040, 780),
		"cache": Vector2(800, 320),
		"seals": [Vector2(820, 780), Vector2(1380, 780)],
		"optional": [Vector2(800, 320), Vector2(980, 320)]
	},
	{
		"name": "GAUNTLET",
		"rooms": [
			{"rect": Rect2(80, 700, 320, 320), "name": "ARRIVAL"},
			{"rect": Rect2(360, 780, 240, 120), "name": "NARROW PASS"},
			{"rect": Rect2(560, 560, 400, 520), "name": "PILLAR HALL / SEAL I"},
			{"rect": Rect2(1800, 560, 400, 520), "name": "ENCIRCLEMENT / SEAL II"},
			{"rect": Rect2(1120, 80, 400, 320), "name": "CURSED VAULT / OPTIONAL"},
			{"rect": Rect2(2100, 540, 300, 520), "name": "GUARDIAN SANCTUM"}
		],
		"corridors": [Rect2(1120, 520, 520, 560), Rect2(920, 760, 280, 160), Rect2(1560, 760, 280, 160), Rect2(1280, 320, 160, 280)],
		"pillars": [Rect2(1300, 700, 80, 120), Rect2(1440, 900, 80, 120)],
		"chapter_pillars": [[], [Rect2(1880, 700, 80, 80)], [Rect2(1920, 900, 120, 80)]],
		"arrival": Vector2(160, 820),
		"shrine": Vector2(200, 960),
		"boss": Vector2(2280, 800),
		"cache": Vector2(1320, 220),
		"seals": [Vector2(760, 800), Vector2(2000, 800)],
		"optional": [Vector2(1400, 700), Vector2(1320, 220)]
	}
]

var floors: Array[Rect2] = []
var walls: Array[Rect2] = []
var pillars: Array[Rect2] = []
var rooms: Array[Dictionary] = []
var seals: Array[Vector2] = []
var seal_centers: Array[Vector2] = []
var optional_centers: Array[Vector2] = []
var arrival := Vector2(180, 750)
var shrine_point := Vector2(340, 620)
var boss_point := Vector2(2130, 750)
var cache := Vector2(1060, 200)
var flipped := false
var walkable: Dictionary = {}
var distances: Dictionary = {}
var flow_goal := Vector2i(-1, -1)
var grid := AStarGrid2D.new()

func template_count() -> int:
	return TEMPLATES.size()

func template_name(index: int) -> String:
	return TEMPLATES[posmod(index, TEMPLATES.size())].name

func mirror_rect(rect: Rect2) -> Rect2:
	return Rect2(WORLD.x - rect.end.x, rect.position.y, rect.size.x, rect.size.y) if flipped else rect

func mirror_point(point: Vector2) -> Vector2:
	return Vector2(WORLD.x - point.x, point.y) if flipped else point

func build(chapter: int, expedition: int, template_index: int = 0, mirror: bool = false) -> void:
	floors.clear()
	walls.clear()
	pillars.clear()
	rooms.clear()
	seals.clear()
	seal_centers.clear()
	optional_centers.clear()
	walkable.clear()
	distances.clear()
	flow_goal = Vector2i(-1, -1)
	flipped = mirror
	var template: Dictionary = TEMPLATES[posmod(template_index, TEMPLATES.size())]
	for room in template.rooms:
		var rect := mirror_rect(room.rect)
		rooms.append({"rect": rect, "name": room.name})
		floors.append(rect)
	for corridor in template.corridors:
		floors.append(mirror_rect(corridor))
	for pillar in template.pillars:
		pillars.append(mirror_rect(pillar))
	var chapter_pillars: Array = template.chapter_pillars
	if chapter >= 0 and chapter < chapter_pillars.size():
		for pillar in chapter_pillars[chapter]:
			pillars.append(mirror_rect(pillar))
	arrival = mirror_point(template.arrival)
	shrine_point = mirror_point(template.shrine)
	boss_point = mirror_point(template.boss)
	cache = mirror_point(template.cache)
	for point in template.seals:
		seal_centers.append(mirror_point(point))
	seals.assign(seal_centers)
	for point in template.optional:
		optional_centers.append(mirror_point(point))
	# Merge horizontal runs of solid cells into rectangles for collision and drawing.
	for y in range(SIZE.y):
		var start := -1
		for x in range(SIZE.x + 1):
			var solid: bool = x < SIZE.x and not is_floor(Vector2(x * CELL + 20, y * CELL + 20))
			if solid and start < 0:
				start = x
			elif not solid and start >= 0:
				walls.append(Rect2(start * CELL, y * CELL, (x - start) * CELL, CELL))
				start = -1
	var merged: Array[Rect2] = []
	for wall in walls:
		var joined := false
		for i in range(merged.size()):
			if merged[i].position.x == wall.position.x and merged[i].size.x == wall.size.x and merged[i].end.y == wall.position.y:
				merged[i].size.y += wall.size.y
				joined = true
				break
		if not joined:
			merged.append(wall)
	walls = merged
	walls.append_array(pillars)
	grid.region = Rect2i(Vector2i.ZERO, SIZE)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(20, 20)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var cell := Vector2i(x, y)
			var clear: bool = can_stand(center(cell), 33)
			grid.set_point_solid(cell, not clear)
			if clear:
				walkable[cell] = true

func is_floor(point: Vector2) -> bool:
	for floor_rect in floors:
		if floor_rect.has_point(point):
			return true
	return false

func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2.ONE * 20

func can_stand(point: Vector2, radius: float) -> bool:
	if point.x < radius or point.y < radius or point.x > 2400 - radius or point.y > 1500 - radius:
		return false
	for wall in walls:
		# Conservative square clearance avoids corner clipping during axis sliding.
		if wall.grow(radius).has_point(point):
			return false
	return true

func nearest_cell(point: Vector2) -> Vector2i:
	var cell := Vector2i((point / CELL).floor())
	if walkable.has(cell):
		return cell
	var closest := Vector2i(-1, -1)
	var best := INF
	for candidate: Vector2i in walkable:
		var distance := center(candidate).distance_squared_to(point)
		if distance < best:
			best = distance
			closest = candidate
	return closest

func safe_position(point: Vector2, radius: float) -> Vector2:
	if can_stand(point, radius):
		return point
	return center(nearest_cell(point))

func segment_clear(from: Vector2, to: Vector2, radius: float = 0) -> bool:
	var bounds := Rect2(from, Vector2.ZERO).expand(to).grow(radius + 0.01)
	for wall in walls:
		if not wall.intersects(bounds, true):
			continue
		var rect := wall.grow(radius)
		if rect.has_point(from) or rect.has_point(to):
			return false
		var a := rect.position
		var b := Vector2(rect.end.x, rect.position.y)
		var c := rect.end
		var d := Vector2(rect.position.x, rect.end.y)
		if Geometry2D.segment_intersects_segment(from, to, a, b) != null or Geometry2D.segment_intersects_segment(from, to, b, c) != null or Geometry2D.segment_intersects_segment(from, to, c, d) != null or Geometry2D.segment_intersects_segment(from, to, d, a) != null:
			return false
	return true

func move_body(from: Vector2, displacement: Vector2, radius: float, slide: bool = true) -> Vector2:
	var steps := maxi(1, ceili(displacement.length() / 8.0))
	var increment := displacement / steps
	var point := from
	for i in range(steps):
		var next := point + increment
		if can_stand(next, radius):
			point = next
		elif slide:
			if can_stand(point + Vector2(increment.x, 0), radius):
				point.x += increment.x
			if can_stand(point + Vector2(0, increment.y), radius):
				point.y += increment.y
		else:
			break
	return point

func update_flow(target: Vector2) -> void:
	var goal := nearest_cell(target)
	if goal == flow_goal:
		return
	flow_goal = goal
	distances.clear()
	distances[goal] = 0
	var queue: Array[Vector2i] = [goal]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for step: Vector2i in STEPS:
			var next := cell + step
			if walkable.has(next) and not distances.has(next):
				distances[next] = int(distances[cell]) + 1
				queue.append(next)

func chase(from: Vector2, target: Vector2, radius: float, distance: float) -> Vector2:
	if segment_clear(from, target, radius + 1):
		return move_body(from, from.direction_to(target) * minf(distance, from.distance_to(target)), radius)
	update_flow(target)
	var cell := nearest_cell(from)
	var best: int = distances.get(cell, 99999)
	var waypoint := center(cell)
	for step: Vector2i in STEPS:
		var next := cell + step
		var cost: int = distances.get(next, 99999)
		if cost < best and segment_clear(from, center(next), radius + 1):
			best = cost
			waypoint = center(next)
	return move_body(from, from.direction_to(waypoint) * minf(distance, from.distance_to(waypoint)), radius)

func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return grid.get_point_path(nearest_cell(from), nearest_cell(to))

func guide(from: Vector2, to: Vector2) -> Vector2:
	if segment_clear(from, to, 20):
		return to
	var points := path(from, to)
	var waypoint := from
	for point in points:
		if not segment_clear(from, point, 20):
			break
		waypoint = point
	return waypoint
