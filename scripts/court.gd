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
	mat.albedo_color = Color(0.18, 0.55, 0.32)
	mat.roughness = 0.85
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_WIDTH * 2.0, 0.2, HALF_LENGTH * 2.0)
	col.shape = shape
	col.position = Vector3(0, -0.1, 0)
	body.add_child(col)


func _build_lines() -> void:
	var lines := Node3D.new()
	lines.name = "Lines"
	add_child(lines)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.95, 0.92)
	line_mat.roughness = 0.9

	# Center line
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.08), Vector3(0, 0.01, 0), line_mat)
	# Sidelines + end lines as thin raised strips (visual only; walls handle collision)
	_add_line_box(lines, Vector3(0.08, 0.02, HALF_LENGTH * 2.0), Vector3(-HALF_WIDTH, 0.01, 0), line_mat)
	_add_line_box(lines, Vector3(0.08, 0.02, HALF_LENGTH * 2.0), Vector3(HALF_WIDTH, 0.01, 0), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.08), Vector3(0, 0.01, -HALF_LENGTH), line_mat)
	_add_line_box(lines, Vector3(HALF_WIDTH * 2.0, 0.02, 0.08), Vector3(0, 0.01, HALF_LENGTH), line_mat)
	# 6 m goal-area arcs approximated as bars
	_add_line_box(lines, Vector3(GOAL_WIDTH + 6.0, 0.02, 0.08), Vector3(0, 0.01, -HALF_LENGTH + 6.0), line_mat)
	_add_line_box(lines, Vector3(GOAL_WIDTH + 6.0, 0.02, 0.08), Vector3(0, 0.01, HALF_LENGTH - 6.0), line_mat)
	# 9 m free-throw lines
	_add_line_box(lines, Vector3(GOAL_WIDTH + 9.0, 0.02, 0.06), Vector3(0, 0.01, -HALF_LENGTH + 9.0), line_mat)
	_add_line_box(lines, Vector3(GOAL_WIDTH + 9.0, 0.02, 0.06), Vector3(0, 0.01, HALF_LENGTH - 9.0), line_mat)


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

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.92, 0.92, 0.95)
	post_mat.metallic = 0.2
	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.85, 0.85, 0.9, 0.35)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var facing := 1.0 if owner_team_id == 0 else -1.0
	# Posts + crossbar
	_add_goal_box(goal_root, Vector3(0.12, GOAL_HEIGHT, 0.12), Vector3(-GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, 0), post_mat)
	_add_goal_box(goal_root, Vector3(0.12, GOAL_HEIGHT, 0.12), Vector3(GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, 0), post_mat)
	_add_goal_box(goal_root, Vector3(GOAL_WIDTH + 0.12, 0.12, 0.12), Vector3(0, GOAL_HEIGHT, 0), post_mat)
	# Back net / depth
	_add_goal_box(goal_root, Vector3(GOAL_WIDTH, GOAL_HEIGHT, 0.08), Vector3(0, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH), net_mat)
	_add_goal_box(goal_root, Vector3(0.08, GOAL_HEIGHT, GOAL_DEPTH), Vector3(-GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH * 0.5), net_mat)
	_add_goal_box(goal_root, Vector3(0.08, GOAL_HEIGHT, GOAL_DEPTH), Vector3(GOAL_WIDTH * 0.5, GOAL_HEIGHT * 0.5, facing * GOAL_DEPTH * 0.5), net_mat)

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
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.62, 0.78)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.65)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = environment
	add_child(env)
