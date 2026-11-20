extends Node3D
class_name Court

## Meter convention: 1 Godot unit = 1 metre (`METERS_PER_UNIT`).
## Playing court is the IHF 40 × 20. Goals 3 × 2. Adult players are ~1.90 m
## (`Player.VISUAL_HEIGHT_M`), about 1/10 of the court width.
## Indoor handball has no center circle — throw-off is from the center line.

const METERS_PER_UNIT := 1.0
const HALF_LENGTH := 20.0
const HALF_WIDTH := 10.0
const FLOOR_Y := 0.0
const GOAL_WIDTH := 3.0
const GOAL_HEIGHT := 2.0
const GOAL_DEPTH := 1.0
const GOAL_AREA_RADIUS := 6.0
## 9 m free-throw line (same stadium shape as the 6 m line, dashed).
const NINE_METER_M := 9.0
## 7 m penalty mark: 1 m line parallel to the goal line.
const SEVEN_METER_M := 7.0
## 4 m goalkeeper restraining line. IHF length is 15 cm; drawn a little longer so the elevated camera can read it.
const FOUR_METER_M := 4.0
const FOUR_METER_MARK_LENGTH := 0.40
## Painted line center height. Wood top is ~1.6 cm; lines sit on it, not above the players' ankles.
const LINE_Y := 0.022
const LINE_H := 0.008
## IHF lines are 5 cm (goal line 8 cm). Slightly thicker so they hold up at the attack camera.
const LINE_WIDTH := 0.06
const GOAL_LINE_WIDTH := 0.08
## Hall shell around the 40×20 so the court reads as a floor, not a platform in the sky.
const HALL_HALF_X := 26.0
const HALL_HALF_Z := 44.0
const HALL_HEIGHT := 18.0
## Bench hip line, clearly outside the sideline (x = ±10).
const BENCH_X := 11.65
const BENCH_SLOT_SPACING := 1.28
## Soft out-of-bounds just inside the wall colliders (capsule/ball centers).
const OOB_HALF_WIDTH := 9.55
const OOB_HALF_LENGTH := 19.6


## Center of the 7 m penalty mark for the given defending team.
static func seven_meter_spot(defending_team_id: int) -> Vector3:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	return Vector3(0.0, 0.0, end_z + toward_mid * SEVEN_METER_M)


## Substitute / exclusion spot on the team bench, outside the 40×20.
## Home bench is on −X, away on +X, each in its own half. `slot` 0–1 are subs; 2+ exclusions.
static func bench_marker(team_id: int, slot: int = 0) -> Vector3:
	var side := -1.0 if team_id == 0 else 1.0
	var z_base := -2.6 if team_id == 0 else 2.6
	var z_step := -BENCH_SLOT_SPACING if team_id == 0 else BENCH_SLOT_SPACING
	return Vector3(side * BENCH_X, 0.0, z_base + float(slot) * z_step)


## Yaw that faces the court from that team's bench. Local +Z is forward (see Player.face_direction).
static func bench_yaw(team_id: int) -> float:
	return PI * 0.5 if team_id == 0 else -PI * 0.5


## Quarter-circle sweep for one post: (angle at the 3 m straight, angle at the goal line).
## The delta is always π/2. Picking the short wrap stops the away-left arc drawing 270°.
static func goal_arc_angles(defending_team_id: int, side: float) -> Vector2:
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	var mid_angle := PI * 0.5 * toward_mid
	var outward := 0.0 if side > 0.0 else PI
	var delta := wrapf(outward - mid_angle, -PI, PI)
	return Vector2(mid_angle, mid_angle + delta)


## 4 m GK mark, centered, parallel to the goal line.
static func four_meter_spot(defending_team_id: int) -> Vector3:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var toward_mid := 1.0 if defending_team_id == 0 else -1.0
	return Vector3(0.0, 0.0, end_z + toward_mid * FOUR_METER_M)


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
	_build_hall_shell()
	_build_benches()
	_build_lights()


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Apron / hall slab under and around the 40×20. One collider so bench players have ground.
	var hall_mesh := MeshInstance3D.new()
	hall_mesh.name = "HallFloorMesh"
	var hall_box := BoxMesh.new()
	hall_box.size = Vector3(HALL_HALF_X * 2.0, 0.4, HALL_HALF_Z * 2.0)
	hall_mesh.mesh = hall_box
	hall_mesh.position = Vector3(0, -0.2, 0)
	var apron := StandardMaterial3D.new()
	apron.albedo_color = Color(0.27, 0.29, 0.32)
	apron.roughness = 0.88
	hall_mesh.material_override = apron
	hall_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(hall_mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = hall_box.size
	col.shape = shape
	col.position = hall_mesh.position
	body.add_child(col)

	# Wooden playing court, a thin skin on the slab (not a floating platform).
	var wood := MeshInstance3D.new()
	wood.name = "CourtWood"
	var wood_box := BoxMesh.new()
	wood_box.size = Vector3(HALF_WIDTH * 2.0, 0.016, HALF_LENGTH * 2.0)
	wood.mesh = wood_box
	wood.position = Vector3(0, 0.008, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.42, 0.26)
	mat.roughness = 0.55
	mat.metallic = 0.0
	wood.material_override = mat
	body.add_child(wood)

	# Goal-area wash follows the same D as the line and the collision test.
	_add_crease_tint(0, Color(0.22, 0.38, 0.72, 0.22))
	_add_crease_tint(1, Color(0.72, 0.28, 0.24, 0.22))


func _add_crease_tint(defending_team_id: int, color: Color) -> void:
	var boundary := _goal_area_boundary(defending_team_id, GOAL_AREA_RADIUS, 16)
	if boundary.size() < 3:
		return
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var y := 0.017
	var center := Vector3(0.0, y, end_z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(boundary.size() - 1):
		st.set_normal(Vector3.UP)
		st.add_vertex(center)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(boundary[i].x, y, boundary[i].z))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(boundary[i + 1].x, y, boundary[i + 1].z))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Crease_%d" % defending_team_id
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Boundary of the goal-area D, goal-line left end → arc → straight → arc → goal-line right end.
func _goal_area_boundary(defending_team_id: int, radius: float, steps: int) -> PackedVector3Array:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var half_goal := GOAL_WIDTH * 0.5
	var pts := PackedVector3Array()
	var segs := maxi(steps, 4)
	for side in [-1.0, 1.0]:
		var post := Vector3(side * half_goal, 0.0, end_z)
		var angles := goal_arc_angles(defending_team_id, side)
		# Left post: goal line → straight. Right post: straight → goal line. Straight joins them.
		var from_ang := angles.y if side < 0.0 else angles.x
		var to_ang := angles.x if side < 0.0 else angles.y
		for i in range(segs + 1):
			var t := float(i) / float(segs)
			var ang := lerpf(from_ang, to_ang, t)
			pts.append(post + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius))
	return pts


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

	# Perimeter: sidelines + goal lines (visual; walls handle collision). Flat on the wood.
	_add_line_box(lines, Vector3(LINE_WIDTH, LINE_H, HALF_LENGTH * 2.0), Vector3(-HALF_WIDTH, LINE_Y, 0), line_mat)
	_add_line_box(lines, Vector3(LINE_WIDTH, LINE_H, HALF_LENGTH * 2.0), Vector3(HALF_WIDTH, LINE_Y, 0), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, LINE_H, GOAL_LINE_WIDTH), Vector3(0, LINE_Y, -HALF_LENGTH), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, LINE_H, GOAL_LINE_WIDTH), Vector3(0, LINE_Y, HALF_LENGTH), line_mat)
	# Center line. No center circle — IHF indoor throw-off is from this line.
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, LINE_H, LINE_WIDTH), Vector3(0, LINE_Y, 0), line_mat)

	# 6 m goal-area D (solid): 3 m straight + quarter-circles at the posts.
	_add_goal_area_marking(lines, 0, GOAL_AREA_RADIUS, line_mat, false, 0.07)
	_add_goal_area_marking(lines, 1, GOAL_AREA_RADIUS, line_mat, false, 0.07)

	# 9 m free-throw line (dashed), clipped to the sidelines.
	var dashed := line_mat.duplicate() as StandardMaterial3D
	dashed.albedo_color = Color(0.94, 0.94, 0.92)
	_add_goal_area_marking(lines, 0, NINE_METER_M, dashed, true, LINE_WIDTH)
	_add_goal_area_marking(lines, 1, NINE_METER_M, dashed, true, LINE_WIDTH)

	# 7 m penalty mark: 1 m line parallel to the goal line. 4 m GK tick in front of it.
	var seven_mat := line_mat.duplicate() as StandardMaterial3D
	seven_mat.albedo_color = Color(1.0, 0.97, 0.92)
	_add_parallel_mark(lines, seven_meter_spot(0), 1.0, seven_mat)
	_add_parallel_mark(lines, seven_meter_spot(1), 1.0, seven_mat)
	_add_parallel_mark(lines, four_meter_spot(0), FOUR_METER_MARK_LENGTH, line_mat)
	_add_parallel_mark(lines, four_meter_spot(1), FOUR_METER_MARK_LENGTH, line_mat)


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
	# Quarter-circles centered on each post. Short sweep only (see goal_arc_angles).
	for side in [-1.0, 1.0]:
		var post := Vector3(side * half_goal, 0.0, end_z)
		var angles := goal_arc_angles(defending_team_id, side)
		_add_arc_line(parent, post, radius, angles.x, angles.y, 20, mat, thickness, dashed)


func _add_parallel_mark(parent: Node3D, pos: Vector3, length: float, mat: Material) -> void:
	# Line parallel to the goal line (along X), centered on the mark.
	var half := length * 0.5
	_add_solid_segment(
		parent,
		Vector3(pos.x - half, 0.0, pos.z),
		Vector3(pos.x + half, 0.0, pos.z),
		mat,
		GOAL_LINE_WIDTH
	)


func _add_line_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	mid.y = LINE_Y
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	# Long axis is local Z. rotation.y = atan2(dx, dz) lays that axis along the segment, flat on the floor.
	box.size = Vector3(thickness, LINE_H, length)
	mi.mesh = box
	mi.position = mid
	mi.rotation.y = atan2(delta.x, delta.z)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var dash := 0.38
	var gap := 0.24
	var phase := 0.0
	for i in range(segs):
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var a0 := lerpf(angle_a, angle_b, t0)
		var a1 := lerpf(angle_a, angle_b, t1)
		var p0 := center + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var clipped := _clip_segment_to_court(p0, p1)
		var piece_len := p0.distance_to(p1)
		if clipped.size() == 2:
			var c0: Vector3 = clipped[0]
			var c1: Vector3 = clipped[1]
			piece_len = c0.distance_to(c1)
			if dashed:
				_emit_dashed_piece(parent, c0, c1, mat, thickness, phase, dash, gap)
			else:
				_add_solid_segment(parent, c0, c1, mat, thickness)
		if dashed:
			phase = fmod(phase + piece_len, dash + gap)


func _emit_dashed_piece(
	parent: Node3D,
	from: Vector3,
	to: Vector3,
	mat: Material,
	thickness: float,
	phase: float,
	dash: float,
	gap: float
) -> void:
	var delta := to - from
	delta.y = 0.0
	var length := delta.length()
	if length < 0.001:
		return
	var dir := delta / length
	var period := dash + gap
	var traveled := 0.0
	var cursor := phase
	while traveled < length - 0.0001:
		var into := fmod(cursor, period)
		if into < 0.0:
			into += period
		var drawing := into < dash
		var room := (dash - into) if drawing else (period - into)
		var step := minf(room, length - traveled)
		if drawing and step > 0.025:
			_add_solid_segment(parent, from + dir * traveled, from + dir * (traveled + step), mat, thickness)
		traveled += step
		cursor += step


## Clip a segment to the playing rectangle so the 9 m arc stops on the sideline.
func _clip_segment_to_court(a: Vector3, b: Vector3) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var bounds := [
		[-d.x, a.x + HALF_WIDTH],
		[d.x, HALF_WIDTH - a.x],
		[-d.z, a.z + HALF_LENGTH],
		[d.z, HALF_LENGTH - a.z],
	]
	for edge in bounds:
		var p: float = edge[0]
		var q: float = edge[1]
		if absf(p) < 0.0000001:
			if q < 0.0:
				return []
			continue
		var r := q / p
		if p < 0.0:
			if r > t1:
				return []
			t0 = maxf(t0, r)
		else:
			if r < t0:
				return []
			t1 = minf(t1, r)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]


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
	# Steep, like hall floods — not a low outdoor sun that paints a sky horizon.
	sun.rotation_degrees = Vector3(-78, 24, 0)
	sun.light_energy = 1.05
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
	environment.background_color = Color(0.05, 0.06, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.56, 0.58)
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Glow is Forward+/Mobile only — skip so OpenGL3 smoke stays clean.
	env.environment = environment
	add_child(env)

	# Low curb so the sideline reads without hiding the benches behind it.
	_add_boards()

	# Ceiling floods — inside the hall, shadows off so they don't fight the sun.
	for z in [-16.0, -5.0, 6.0, 16.0]:
		var spot := SpotLight3D.new()
		spot.name = "HallSpot"
		spot.position = Vector3(0.0, 12.5, z)
		spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		spot.light_color = Color(1.0, 0.96, 0.9)
		spot.light_energy = 5.5
		spot.spot_range = 26.0
		spot.spot_angle = 58.0
		spot.shadow_enabled = false
		add_child(spot)


func _build_hall_shell() -> void:
	var hall := Node3D.new()
	hall.name = "Hall"
	add_child(hall)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.13, 0.15, 0.18)
	wall_mat.roughness = 0.92
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.07, 0.08, 0.10)
	ceil_mat.roughness = 0.95
	var hx := HALL_HALF_X
	var hz := HALL_HALF_Z
	var h := HALL_HEIGHT
	_add_hall_box(hall, Vector3(0.6, h, hz * 2.0 + 0.6), Vector3(-hx, h * 0.5, 0.0), wall_mat)
	_add_hall_box(hall, Vector3(0.6, h, hz * 2.0 + 0.6), Vector3(hx, h * 0.5, 0.0), wall_mat)
	_add_hall_box(hall, Vector3(hx * 2.0 + 0.6, h, 0.6), Vector3(0.0, h * 0.5, -hz), wall_mat)
	_add_hall_box(hall, Vector3(hx * 2.0 + 0.6, h, 0.6), Vector3(0.0, h * 0.5, hz), wall_mat)
	_add_hall_box(hall, Vector3(hx * 2.0 + 0.6, 0.35, hz * 2.0 + 0.6), Vector3(0.0, h, 0.0), ceil_mat)


func _add_hall_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	# Shell must not shadow the court — the sun is outside the ceiling.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_benches() -> void:
	var benches := Node3D.new()
	benches.name = "Benches"
	add_child(benches)
	for team_id in [0, 1]:
		_build_team_bench(benches, team_id)


func _build_team_bench(parent: Node3D, team_id: int) -> void:
	var side := -1.0 if team_id == 0 else 1.0
	var z0 := bench_marker(team_id, 0).z
	var z1 := bench_marker(team_id, 5).z
	var z_min := minf(z0, z1) - 0.55
	var z_max := maxf(z0, z1) + 0.55
	var length := z_max - z_min
	var z_mid := (z_min + z_max) * 0.5
	var x := side * BENCH_X
	var seat_mat := StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.45, 0.32, 0.18)
	seat_mat.roughness = 0.7
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.24, 0.17, 0.11)
	back_mat.roughness = 0.72
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.15, 0.38, 0.78) if team_id == 0 else Color(0.78, 0.18, 0.16)
	stripe_mat.roughness = 0.55
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.16, 0.16, 0.18)
	leg_mat.roughness = 0.6
	# Seat top at 0.44 m. Backrest sits behind the hips so the kit does not merge into the rail.
	_add_hall_box(parent, Vector3(0.42, 0.08, length), Vector3(x, 0.40, z_mid), seat_mat)
	var back_x := x + side * 0.26
	_add_hall_box(parent, Vector3(0.07, 0.38, length), Vector3(back_x, 0.64, z_mid), back_mat)
	_add_hall_box(parent, Vector3(0.09, 0.06, length), Vector3(back_x, 0.86, z_mid), stripe_mat)
	for end_z in [z_min + 0.35, z_mid, z_max - 0.35]:
		_add_hall_box(parent, Vector3(0.08, 0.36, 0.08), Vector3(x - 0.14, 0.18, end_z), leg_mat)
		_add_hall_box(parent, Vector3(0.08, 0.36, 0.08), Vector3(x + 0.14, 0.18, end_z), leg_mat)


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
	side_mat.albedo_color = Color(0.72, 0.74, 0.76)
	side_mat.roughness = 0.8
	# Low team strips behind each goal, and a curb outside the sideline (benches sit beyond it).
	_add_line_box(boards, Vector3(HALF_WIDTH * 2.0 + 0.6, 0.45, 0.1), Vector3(0, 0.24, -HALF_LENGTH - 0.55), home_mat)
	_add_line_box(boards, Vector3(HALF_WIDTH * 2.0 + 0.6, 0.45, 0.1), Vector3(0, 0.24, HALF_LENGTH + 0.55), away_mat)
	_add_line_box(boards, Vector3(0.08, 0.22, HALF_LENGTH * 2.0), Vector3(-HALF_WIDTH - 0.28, 0.12, 0), side_mat)
	_add_line_box(boards, Vector3(0.08, 0.22, HALF_LENGTH * 2.0), Vector3(HALF_WIDTH + 0.28, 0.12, 0), side_mat)
