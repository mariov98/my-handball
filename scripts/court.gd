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
## Soft out-of-bounds just inside the wall colliders (capsule/ball centers).
const OOB_HALF_WIDTH := 9.55
const OOB_HALF_LENGTH := 19.6


## True if `pos` is inside the defending team's 6 m goal area (semicircle approx).
static func in_goal_area(pos: Vector3, defending_team_id: int) -> bool:
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var nearest_x := clampf(pos.x, -GOAL_WIDTH * 0.5, GOAL_WIDTH * 0.5)
	var dx := pos.x - nearest_x
	var dz := pos.z - end_z
	return dx * dx + dz * dz <= GOAL_AREA_RADIUS * GOAL_AREA_RADIUS


## Push a court position just outside the 6 m arc (for AI / soft eject).
static func eject_from_goal_area(pos: Vector3, defending_team_id: int, margin: float = 0.35) -> Vector3:
	if not in_goal_area(pos, defending_team_id):
		return pos
	var end_z := -HALF_LENGTH if defending_team_id == 0 else HALF_LENGTH
	var nearest_x := clampf(pos.x, -GOAL_WIDTH * 0.5, GOAL_WIDTH * 0.5)
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

	# Soft painted crease tints so the 6 m area reads at a glance.
	_add_crease_tint(Vector3(0, 0.005, -HALF_LENGTH + 3.0), Color(0.22, 0.38, 0.72, 0.22))
	_add_crease_tint(Vector3(0, 0.005, HALF_LENGTH - 3.0), Color(0.72, 0.28, 0.24, 0.22))


func _add_crease_tint(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(GOAL_WIDTH + 6.2, 0.01, 6.0)
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)


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

	# Center line
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.1), Vector3(0, 0.01, 0), line_mat)
	# Sidelines + end lines as thin raised strips (visual only; walls handle collision)
	_add_line_box(lines, Vector3(0.1, 0.02, HALF_LENGTH * 2.0), Vector3(-HALF_WIDTH, 0.01, 0), line_mat)
	_add_line_box(lines, Vector3(0.1, 0.02, HALF_LENGTH * 2.0), Vector3(HALF_WIDTH, 0.01, 0), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.1), Vector3(0, 0.01, -HALF_LENGTH), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.1), Vector3(0, 0.01, HALF_LENGTH), line_mat)
	# 6 m goal-area arcs approximated as bars
	_add_line_box(lines, Vector3(GOAL_WIDTH + 6.0, 0.02, 0.1), Vector3(0, 0.01, -HALF_LENGTH + 6.0), line_mat)
	_add_line_box(lines, Vector3(GOAL_WIDTH + 6.0, 0.02, 0.1), Vector3(0, 0.01, HALF_LENGTH - 6.0), line_mat)
	# 9 m free-throw lines (slightly thinner / dashed feel via narrower strip)
	var dashed := line_mat.duplicate() as StandardMaterial3D
	dashed.albedo_color = Color(0.92, 0.92, 0.9)
	_add_line_box(lines, Vector3(GOAL_WIDTH + 9.0, 0.02, 0.07), Vector3(0, 0.01, -HALF_LENGTH + 9.0), dashed)
	_add_line_box(lines, Vector3(GOAL_WIDTH + 9.0, 0.02, 0.07), Vector3(0, 0.01, HALF_LENGTH - 9.0), dashed)
	# Center circle hint
	_add_line_box(lines, Vector3(3.6, 0.015, 0.08), Vector3(0, 0.012, 1.8), line_mat)
	_add_line_box(lines, Vector3(3.6, 0.015, 0.08), Vector3(0, 0.012, -1.8), line_mat)
	_add_line_box(lines, Vector3(0.08, 0.015, 3.6), Vector3(1.8, 0.012, 0), line_mat)
	_add_line_box(lines, Vector3(0.08, 0.015, 3.6), Vector3(-1.8, 0.012, 0), line_mat)


func _add_line_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


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
