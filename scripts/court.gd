extends Node3D
class_name Court

## IHF-ish court in meters (1 unit = 1 m): 40 × 20, goals 3 × 2.

const HALF_LENGTH := 20.0
const HALF_WIDTH := 10.0
const FLOOR_Y := 0.0
const GOAL_WIDTH := 3.0
const GOAL_HEIGHT := 2.0
const GOAL_DEPTH := 1.0
const GOAL_AREA_RADIUS := 6.0
## 7 m penalty mark distance from the goal end line (IHF).
const SEVEN_METER_M := 7.0
## Soft out-of-bounds just inside the wall colliders (capsule/ball centers).
const OOB_HALF_WIDTH := 9.55
const OOB_HALF_LENGTH := 19.6


## Center of the 7 m penalty mark for the given defending team.
static func seven_meter_spot(defending_team_id: int) -> Vector3:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	return Vector3(0.0, 0.0, end_z + toward_mid * SEVEN_METER_M)


## Sideline bench parking for a 2-min exclusion (lite). `slot` spreads multiple exclusions.
static func bench_marker(team_id: int, slot: int = 0) -> Vector3:
	var side := -1.0 if team_id == 0 else 1.0
	var z_base := -6.0 if team_id == 0 else 6.0
	return Vector3(side * (HALF_WIDTH - 0.55), 0.0, z_base + float(slot) * 1.35)


## True if `pos` is inside the defending team's 6 m goal area.
## IHF shape: 3 m straight parallel to the goal line + two 6 m quarter-circles
## centered on the goal posts (stadium / capsule), court side of the end line.
static func in_goal_area(pos: Vector3, defending_team_id: int) -> bool:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	# Must be on the court side of the goal line.
	if (pos.z - end_z) * toward_mid < 0.0:
		return false
	var half_goal := GOAL_WIDTH * 0.5
	var nearest_x := clampf(pos.x, -half_goal, half_goal)
	var dx := pos.x - nearest_x
	var dz := pos.z - end_z
	return dx * dx + dz * dz <= GOAL_AREA_RADIUS * GOAL_AREA_RADIUS


## Push a court position just outside the 6 m goal-area boundary (AI / soft eject).
static func eject_from_goal_area(pos: Vector3, defending_team_id: int, margin: float = 0.35) -> Vector3:
	if not in_goal_area(pos, defending_team_id):
		return pos
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var half_goal := GOAL_WIDTH * 0.5
	var nearest_x := clampf(pos.x, -half_goal, half_goal)
	var from := Vector3(pos.x - nearest_x, 0.0, pos.z - end_z)
	if from.length_squared() < 0.0001:
		# Dead center of goal line — push toward midfield.
		var toward_mid := 1.0 if defending_team_id == 0 else -1.0
		return Vector3(pos.x, pos.y, end_z + toward_mid * (GOAL_AREA_RADIUS + margin))
	var pushed := Vector3(nearest_x, 0.0, end_z) + from.normalized() * (GOAL_AREA_RADIUS + margin)
	pushed.y = pos.y
	pushed.x = clampf(pushed.x, -HALF_WIDTH + 0.5, HALF_WIDTH - 0.5)
	pushed.z = clampf(pushed.z, -HALF_LENGTH + 0.5, HALF_LENGTH - 0.5)
	return pushed


static func is_sideline_oob(pos: Vector3) -> bool:
	return absf(pos.x) >= OOB_HALF_WIDTH


## End-line OOB for a free ball (excludes the goal mouth so GoalArea can score).
static func is_endline_oob(pos: Vector3) -> bool:
	if absf(pos.z) < OOB_HALF_LENGTH:
		return false
	# Inside the posts + a little height → leave for the goal trigger.
	if absf(pos.x) <= GOAL_WIDTH * 0.55 and pos.y <= GOAL_HEIGHT + 0.35:
		return false
	return true


static func clamp_to_court_xz(pos: Vector3, inset: float = 0.6) -> Vector3:
	return Vector3(
		clampf(pos.x, -HALF_WIDTH + inset, HALF_WIDTH - inset),
		pos.y,
		clampf(pos.z, -HALF_LENGTH + inset, HALF_LENGTH - inset)
	)


func _ready() -> void:
	_build_floor()
	_build_lines()
	_build_walls()
	_build_goal(Vector3(0, 0, -HALF_LENGTH), 0) # home defends -Z
	_build_goal(Vector3(0, 0, HALF_LENGTH), 1)  # away defends +Z
	_build_lights()


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(HALF_WIDTH * 2.0, 0.2, HALF_LENGTH * 2.0)
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0, -0.1, 0)
	var mat := StandardMaterial3D.new()
	# Indoor hall wood — warm parquet tone, readable under ACES.
	mat.albedo_color = Color(0.62, 0.42, 0.26)
	mat.roughness = 0.55
	mat.metallic = 0.0
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_WIDTH * 2.0, 0.2, HALF_LENGTH * 2.0)
	col.shape = shape
	col.position = Vector3(0, -0.1, 0)
	body.add_child(col)

	# Soft crease tints (mid rectangle + post wedges) so the D reads at a glance.
	_add_crease_tint(0, Color(0.22, 0.38, 0.72, 0.20))
	_add_crease_tint(1, Color(0.72, 0.28, 0.24, 0.20))


func _add_crease_tint(defending_team_id: int, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	var half_goal := GOAL_WIDTH * 0.5
	# Center strip under the 3 m straight.
	_add_line_box(
		self,
		Vector3(GOAL_WIDTH, 0.008, GOAL_AREA_RADIUS),
		Vector3(0.0, 0.004, end_z + toward_mid * (GOAL_AREA_RADIUS * 0.5)),
		mat
	)
	# Coarse quarter-circle wedges (visual only) matching the D outline.
	var mid_angle := PI * 0.5 * toward_mid
	for side in [-1.0, 1.0]:
		var post := Vector3(side * half_goal, 0.0, end_z)
		var goal_line_angle := 0.0 if side > 0.0 else PI
		for i in range(5):
			var t := (float(i) + 0.5) / 5.0
			var ang := lerpf(mid_angle, goal_line_angle, t)
			var mid := post + Vector3(cos(ang), 0.0, sin(ang)) * (GOAL_AREA_RADIUS * 0.55)
			_add_line_box(self, Vector3(1.15, 0.008, 1.15), Vector3(mid.x, 0.004, mid.z), mat)


func _build_lines() -> void:
	var lines := Node3D.new()
	lines.name = "Lines"
	add_child(lines)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.98, 0.98, 0.96)
	line_mat.roughness = 0.7
	line_mat.emission_enabled = true
	line_mat.emission = Color(0.85, 0.85, 0.8)
	line_mat.emission_energy_multiplier = 0.25

	# Perimeter: sidelines + goal lines (visual; walls handle collision).
	_add_line_box(lines, Vector3(0.1, 0.02, HALF_LENGTH * 2.0), Vector3(-HALF_WIDTH, 0.01, 0), line_mat)
	_add_line_box(lines, Vector3(0.1, 0.02, HALF_LENGTH * 2.0), Vector3(HALF_WIDTH, 0.01, 0), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.1), Vector3(0, 0.01, -HALF_LENGTH), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.1), Vector3(0, 0.01, HALF_LENGTH), line_mat)
	# Center line
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.1), Vector3(0, 0.01, 0), line_mat)
	# Center circle (~1.5 m radius — throw-off reference).
	_add_circle_line(lines, Vector3.ZERO, 1.5, 28, line_mat, 0.07, false)

	# 6 m goal-area D (solid): 3 m straight + quarter-circles at posts.
	_add_goal_area_marking(lines, 0, GOAL_AREA_RADIUS, line_mat, false, 0.09)
	_add_goal_area_marking(lines, 1, GOAL_AREA_RADIUS, line_mat, false, 0.09)

	# 9 m free-throw line (dashed): same IHF stadium geometry.
	var dashed := line_mat.duplicate() as StandardMaterial3D
	dashed.albedo_color = Color(0.94, 0.94, 0.92)
	_add_goal_area_marking(lines, 0, 9.0, dashed, true, 0.07)
	_add_goal_area_marking(lines, 1, 9.0, dashed, true, 0.07)

	# 7 m penalty marks (short cross at each end).
	var seven_mat := line_mat.duplicate() as StandardMaterial3D
	seven_mat.albedo_color = Color(1.0, 0.95, 0.75)
	seven_mat.emission = Color(0.95, 0.85, 0.45)
	seven_mat.emission_energy_multiplier = 0.35
	_add_seven_meter_mark(lines, seven_meter_spot(0), seven_mat)
	_add_seven_meter_mark(lines, seven_meter_spot(1), seven_mat)


## IHF goal-area / free-throw outline: straight between posts at `radius` + quarter-circles.
func _add_goal_area_marking(
	parent: Node3D,
	defending_team_id: int,
	radius: float,
	mat: Material,
	dashed: bool,
	thickness: float
) -> void:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	var half_goal := GOAL_WIDTH * 0.5
	var line_z := end_z + toward_mid * radius
	# Straight 3 m segment parallel to the goal line.
	_add_segment_line(
		parent,
		Vector3(-half_goal, 0.012, line_z),
		Vector3(half_goal, 0.012, line_z),
		mat,
		thickness,
		dashed
	)
	# Quarter-circles centered on each post, sweeping from goal line to the straight.
	var mid_angle := PI * 0.5 * toward_mid
	for side in [-1.0, 1.0]:
		var post := Vector3(side * half_goal, 0.012, end_z)
		var goal_line_angle := 0.0 if side > 0.0 else PI
		_add_arc_line(parent, post, radius, mid_angle, goal_line_angle, 14, mat, thickness, dashed)


func _add_seven_meter_mark(parent: Node3D, pos: Vector3, mat: Material) -> void:
	# Small cross so the 7 m spot reads clearly from the elevated camera.
	_add_line_box(parent, Vector3(0.9, 0.025, 0.08), Vector3(pos.x, 0.015, pos.z), mat)
	_add_line_box(parent, Vector3(0.08, 0.025, 0.9), Vector3(pos.x, 0.015, pos.z), mat)


func _add_line_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


## Oriented strip between two XZ points (procedural line segment).
func _add_segment_line(
	parent: Node3D,
	from: Vector3,
	to: Vector3,
	mat: Material,
	thickness: float,
	dashed: bool = false
) -> void:
	var delta := to - from
	delta.y = 0.0
	var length := delta.length()
	if length < 0.001:
		return
	if dashed:
		var dash := 0.55
		var gap := 0.35
		var dir := delta / length
		var traveled := 0.0
		var draw := true
		while traveled < length - 0.001:
			var chunk := minf(dash if draw else gap, length - traveled)
			if draw and chunk > 0.04:
				var a := from + dir * traveled
				var b := from + dir * (traveled + chunk)
				_add_solid_segment(parent, a, b, mat, thickness)
			traveled += chunk
			draw = not draw
		return
	_add_solid_segment(parent, from, to, mat, thickness)


func _add_solid_segment(parent: Node3D, from: Vector3, to: Vector3, mat: Material, thickness: float) -> void:
	var delta := to - from
	delta.y = 0.0
	var length := delta.length()
	if length < 0.001:
		return
	var mid := (from + to) * 0.5
	mid.y = 0.012
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, 0.02, length)
	mi.mesh = box
	mi.position = mid
	mi.rotation.y = atan2(delta.x, delta.z)
	mi.material_override = mat
	parent.add_child(mi)


func _add_arc_line(
	parent: Node3D,
	center: Vector3,
	radius: float,
	angle_a: float,
	angle_b: float,
	segments: int,
	mat: Material,
	thickness: float,
	dashed: bool = false
) -> void:
	var segs := maxi(segments, 4)
	for i in range(segs):
		if dashed and (i % 2) == 1:
			continue
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var a0 := lerpf(angle_a, angle_b, t0)
		var a1 := lerpf(angle_a, angle_b, t1)
		var p0 := center + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		p0.y = 0.012
		p1.y = 0.012
		_add_solid_segment(parent, p0, p1, mat, thickness)


func _add_circle_line(
	parent: Node3D,
	center: Vector3,
	radius: float,
	segments: int,
	mat: Material,
	thickness: float,
	dashed: bool = false
) -> void:
	var segs := maxi(segments, 8)
	for i in range(segs):
		if dashed and (i % 2) == 1:
			continue
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := center + Vector3(cos(a0) * radius, 0.012, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.012, sin(a1) * radius)
		_add_solid_segment(parent, p0, p1, mat, thickness)


func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	# Invisible side / end colliders slightly outside court
	_add_wall(walls, Vector3(0.4, 3.0, HALF_LENGTH * 2.0 + 2.0), Vector3(-HALF_WIDTH - 0.2, 1.5, 0))
	_add_wall(walls, Vector3(0.4, 3.0, HALF_LENGTH * 2.0 + 2.0), Vector3(HALF_WIDTH + 0.2, 1.5, 0))
	_add_wall(walls, Vector3(HALF_WIDTH * 2.0 + 2.0, 3.0, 0.4), Vector3(0, 1.5, -HALF_LENGTH - 0.2))
	_add_wall(walls, Vector3(HALF_WIDTH * 2.0 + 2.0, 3.0, 0.4), Vector3(0, 1.5, HALF_LENGTH + 0.2))


func _add_wall(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


func _build_goal(origin: Vector3, owner_team_id: int) -> void:
	var goal_root := Node3D.new()
	goal_root.name = "Goal_Team%d" % owner_team_id
	goal_root.position = origin
	add_child(goal_root)

	# Classic handball red posts + white net (unshaded posts stay red under OpenGL3).
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.92, 0.08, 0.08)
	post_mat.metallic = 0.0
	post_mat.roughness = 0.55
	post_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.92, 0.94, 0.97, 0.32)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	net_mat.roughness = 0.9
	net_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var facing := 1.0 if owner_team_id == 0 else -1.0
	# Posts + crossbar (slightly thicker for readability)
	_add_goal_box(goal_root, Vector3(0.14, GOAL_HEIGHT, 0.14), Vector3(-GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, 0), post_mat)
	_add_goal_box(goal_root, Vector3(0.14, GOAL_HEIGHT, 0.14), Vector3(GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, 0), post_mat)
	_add_goal_box(goal_root, Vector3(GOAL_WIDTH + 0.14, 0.14, 0.14), Vector3(0, GOAL_HEIGHT, 0), post_mat)
	# Back net / depth
	_add_goal_box(goal_root, Vector3(GOAL_WIDTH, GOAL_HEIGHT, 0.06), Vector3(0, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH), net_mat)
	_add_goal_box(goal_root, Vector3(0.06, GOAL_HEIGHT, GOAL_DEPTH), Vector3(-GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH * 0.5), net_mat)
	_add_goal_box(goal_root, Vector3(0.06, GOAL_HEIGHT, GOAL_DEPTH), Vector3(GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH * 0.5), net_mat)
	_add_goal_box(goal_root, Vector3(GOAL_WIDTH, 0.06, GOAL_DEPTH), Vector3(0, GOAL_HEIGHT, facing * GOAL_DEPTH * 0.5), net_mat)

	# Trigger mouth just inside the goal line toward net
	var area := Area3D.new()
	area.name = "GoalMouth"
	area.set_script(load("res://scripts/goal_area.gd"))
	area.owner_team_id = owner_team_id
	area.collision_layer = 8
	area.collision_mask = 4  # ball
	area.monitoring = true
	area.monitorable = false
	area.position = Vector3(0, GOAL_HEIGHT * 0.5, facing * 0.35)
	area.add_to_group("goals")
	goal_root.add_child(area)
	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(GOAL_WIDTH * 0.95, GOAL_HEIGHT * 0.95, 0.5)
	shape_node.shape = box_shape
	area.add_child(shape_node)

	# Static backboard collider so ball doesn't leave through net infinitely
	var net_body := StaticBody3D.new()
	net_body.collision_layer = 1
	net_body.collision_mask = 0
	net_body.position = Vector3(0, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH)
	goal_root.add_child(net_body)
	var net_col := CollisionShape3D.new()
	var net_shape := BoxShape3D.new()
	net_shape.size = Vector3(GOAL_WIDTH, GOAL_HEIGHT, 0.1)
	net_col.shape = net_shape
	net_body.add_child(net_col)


func _add_goal_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, 28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	add_child(sun)

	# Soft fill so away-side capsules don't flatten into the wood.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-30, -140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 0.95)
	fill.shadow_enabled = false
	add_child(fill)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.28, 0.34, 0.42)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.64, 0.68)
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Glow is Forward+/Mobile only — skip so OpenGL3 smoke stays clean.
	env.environment = environment
	add_child(env)

	# Low sideline boards — color cue for home/away ends without blocking vision.
	_add_boards()


func _add_boards() -> void:
	var boards := Node3D.new()
	boards.name = "Boards"
	add_child(boards)
	var home_mat := StandardMaterial3D.new()
	home_mat.albedo_color = Color(0.15, 0.32, 0.72)
	home_mat.roughness = 0.75
	var away_mat := StandardMaterial3D.new()
	away_mat.albedo_color = Color(0.72, 0.18, 0.16)
	away_mat.roughness = 0.75
	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_color = Color(0.85, 0.86, 0.88)
	side_mat.roughness = 0.8
	_add_line_box(boards, Vector3(HALF_WIDTH * 2.0 + 0.4, 0.9, 0.12), Vector3(0, 0.45, -HALF_LENGTH - 0.35), home_mat)
	_add_line_box(boards, Vector3(HALF_WIDTH * 2.0 + 0.4, 0.9, 0.12), Vector3(0, 0.45, HALF_LENGTH + 0.35), away_mat)
	_add_line_box(boards, Vector3(0.12, 0.9, HALF_LENGTH * 2.0 + 0.8), Vector3(-HALF_WIDTH - 0.35, 0.45, 0), side_mat)
	_add_line_box(boards, Vector3(0.12, 0.9, HALF_LENGTH * 2.0 + 0.8), Vector3(HALF_WIDTH + 0.35, 0.45, 0), side_mat)
