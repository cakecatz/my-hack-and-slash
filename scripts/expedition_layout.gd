extends RefCounted
## Six connected room types. A shared wall model drives movement, sight and navigation.
const CELL := 40
const SIZE := Vector2i(60, 38)
const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var floors: Array[Rect2] = []
var walls: Array[Rect2] = []
var pillars: Array[Rect2] = []
var rooms: Array[Dictionary] = []
var seals: Array[Vector2] = [Vector2(1060, 780), Vector2(1500, 780)]
var cache := Vector2(1060, 200)
var walkable: Dictionary = {}
var distances: Dictionary = {}
var flow_goal := Vector2i(-1, -1)
var grid := AStarGrid2D.new()

func build(chapter: int, expedition: int) -> void:
	floors.clear()
	walls.clear()
	pillars.clear()
	rooms.clear()
	walkable.clear()
	distances.clear()
	flow_goal = Vector2i(-1, -1)
	var bottom := (chapter + expedition) % 2 == 1
	cache = Vector2(1060, 1320 if bottom else 200)
	rooms.assign([
		{"rect": Rect2(80, 560, 360, 400), "name": "ARRIVAL"},
		{"rect": Rect2(440, 680, 360, 160), "name": "NARROW PASS"},
		{"rect": Rect2(800, 440, 440, 640), "name": "PILLAR HALL / SEAL I"},
		{"rect": Rect2(1320, 440, 400, 640), "name": "ENCIRCLEMENT / SEAL II"},
		{"rect": Rect2(840, 1200 if bottom else 80, 400, 240), "name": "CURSED VAULT / OPTIONAL"},
		{"rect": Rect2(1760, 280, 560, 960), "name": "GUARDIAN SANCTUM"}
	])
	for room in rooms:
		floors.append(room.rect)
	floors.append(Rect2(1240, 680, 80, 160))
	floors.append(Rect2(1720, 680, 40, 160))
	floors.append(Rect2(1000, 1080 if bottom else 320, 120, 120))
	# Cover differs by chapter; every layout retains both sides of each pillar.
	pillars.assign([Rect2(920, 600, 80, 120), Rect2(1120, 840, 80, 120)])
	if chapter == 1:
		pillars.append(Rect2(1440, 600, 80, 80))
	elif chapter == 2:
		pillars.append(Rect2(1480, 880, 120, 80))
	# Merge horizontal runs of solid cells into rectangles for collision and drawing.
	for y in range(SIZE.y):
		var start := -1
		for x in range(SIZE.x + 1):
			var solid := x < SIZE.x and not is_floor(Vector2(x * CELL + 20, y * CELL + 20))
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
			var clear := can_stand(center(cell), 33)
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
