extends CharacterBody3D
class_name Player

## Capsule outfield / GK. Controlled player receives match input; AI teammates chase/block.

signal possession_changed(has_ball: bool)

const SPEED := 8.5
const AIR_CONTROL := 0.45
const JUMP_VELOCITY := 7.5
const FACE_THRESHOLD := 0.15
const BOB_AMOUNT := 0.04
const BOB_SPEED := 12.0
const PICKUP_COOLDOWN := 0.35

# AI tuning
const AI_CHASE_SPEED_SCALE := 0.92
const AI_BLOCK_SPEED_SCALE := 0.85
const AI_ATTACK_SPEED_SCALE := 0.88
const AI_GK_SPEED_SCALE := 0.7
const AI_SHOOT_RANGE := 11.0
const AI_SHOOT_COOLDOWN := 1.4
const AI_BLOCK_DEPTH := 4.5

@export var team_id: int = 0 ## 0 = home (blue), 1 = away (red)
@export var is_goalkeeper: bool = false
@export var player_index: int = 0
@export var body_color: Color = Color(0.2, 0.45, 0.9)

var controlled: bool = false
var ai_enabled: bool = false
var has_ball: bool = false
var start_position: Vector3 = Vector3.ZERO
var start_yaw: float = 0.0
## Set by MatchController so AI can chase / shoot.
var match_ball: Ball = null
var match_frozen: bool = false

var _bob_phase: float = 0.0
var _pickup_block: float = 0.0
var _ai_shoot_cd: float = 0.0
## AI carry distance — shoot before Phase 2 traveling (~3×1.15 m) fires.
var _ai_carry_dist: float = 0.0
var _ai_carry_last_xz: Vector3 = Vector3.ZERO
var _ai_carry_sampling: bool = false
var _mesh: MeshInstance3D
var _mesh_base_y: float = 0.9

@onready var ball_attach: Marker3D = $BallAttach
@onready var pickup_area: Area3D = $PickupArea


func _ready() -> void:
	start_position = global_position
	start_yaw = rotation.y
	_apply_team_material()
	pickup_area.body_entered.connect(_on_pickup_body_entered)


func _physics_process(delta: float) -> void:
	if _pickup_block > 0.0:
		_pickup_block = maxf(0.0, _pickup_block - delta)
	if _ai_shoot_cd > 0.0:
		_ai_shoot_cd = maxf(0.0, _ai_shoot_cd - delta)

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var wish := Vector3.ZERO
	if match_frozen:
		wish = Vector3.ZERO
	elif controlled:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# WASD / left stick are camera-relative: forward = into the screen along
		# the current camera facing projected onto the court plane.
		wish = camera_relative_wish(input_dir)
	elif ai_enabled:
		wish = _ai_wish(delta)

	var target_speed := SPEED * (0.85 if is_goalkeeper else 1.0)
	if ai_enabled and not controlled:
		target_speed *= AI_GK_SPEED_SCALE if is_goalkeeper else AI_CHASE_SPEED_SCALE
	var control := 1.0 if is_on_floor() else AIR_CONTROL
	var desired := wish * target_speed
	velocity.x = lerpf(velocity.x, desired.x, control)
	velocity.z = lerpf(velocity.z, desired.z, control)

	if controlled and not match_frozen and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length() > FACE_THRESHOLD:
		var target_yaw := atan2(planar.x, planar.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	_update_bob(delta, planar.length())


func try_shoot(aim_dir: Vector3, impulse_strength: float, ball: Ball) -> bool:
	if not has_ball or ball == null or ball.carrier != self:
		return false
	_pickup_block = PICKUP_COOLDOWN
	has_ball = false
	possession_changed.emit(false)
	ball.release_and_shoot(aim_dir, impulse_strength)
	return true


func reset_to_start() -> void:
	global_position = start_position
	rotation.y = start_yaw
	velocity = Vector3.ZERO
	has_ball = false
	_pickup_block = 0.0
	_ai_shoot_cd = 0.0
	_ai_carry_dist = 0.0
	_ai_carry_sampling = false
	_bob_phase = 0.0
	if _mesh:
		_mesh.position.y = _mesh_base_y


func face_direction() -> Vector3:
	# With rotation.y = atan2(x, z), local +Z faces the move direction.
	return global_transform.basis.z


## Map stick/WASD into a planar wish vector relative to the active camera.
## input_dir from Input.get_vector: +x = right, +y = back (W is negative y).
func camera_relative_wish(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		var fallback := Vector3(input_dir.x, 0.0, input_dir.y)
		if fallback.length_squared() > 1.0:
			fallback = fallback.normalized()
		return fallback

	# Camera looks along -basis.z; project that onto the court (XZ).
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		# Near top-down: use the camera's projected "up" as forward.
		forward = -cam.global_transform.basis.y
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, 1.0)
	else:
		forward = forward.normalized()

	var right := cam.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	# W / stick-up → into the screen (along camera forward on the court).
	var wish := right * input_dir.x + forward * (-input_dir.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	return wish


func opponent_goal_point() -> Vector3:
	# Home attacks +Z; away attacks -Z.
	var goal_z := 19.5 if team_id == 0 else -19.5
	return Vector3(0.0, 1.2, goal_z)


func own_goal_point() -> Vector3:
	var goal_z := -19.5 if team_id == 0 else 19.5
	return Vector3(0.0, 1.2, goal_z)


func _ai_wish(delta: float) -> Vector3:
	if match_ball == null:
		return _steer_toward(start_position)

	if is_goalkeeper:
		return _ai_gk_wish()

	if has_ball and match_ball.carrier == self:
		return _ai_attack_with_ball(delta)

	var carrier := match_ball.carrier
	if carrier == null:
		return _ai_chase_free_ball()
	if carrier.team_id == team_id:
		return _ai_support_attack(carrier)
	return _ai_defend_block(carrier)


func _ai_gk_wish() -> Vector3:
	var ball_pos := match_ball.global_position
	var home := start_position
	var track_x := clampf(ball_pos.x, -3.2, 3.2)
	# Ease slightly off the line toward the ball when it approaches.
	var gap := absf(ball_pos.z - home.z)
	var approach := clampf(1.0 - gap / 12.0, 0.0, 1.0)
	var toward_court := 1.0 if team_id == 0 else -1.0
	var target := Vector3(track_x, 0.0, home.z + toward_court * approach * 1.5)
	if team_id == 0:
		target.z = clampf(target.z, -18.5, -14.0)
	else:
		target.z = clampf(target.z, 14.0, 18.5)
	return _steer_toward(target)


func _ai_chase_free_ball() -> Vector3:
	var target := match_ball.global_position
	target.y = 0.0
	# Don't chase into either crease as an outfield player.
	target = _keep_outfield_legal(target)
	return _steer_toward(target)


func _ai_defend_block(carrier: Player) -> Vector3:
	# Stand between carrier and own goal (simple block / lane deny).
	var own_goal := own_goal_point()
	own_goal.y = 0.0
	var carrier_pos := carrier.global_position
	carrier_pos.y = 0.0
	var to_goal := own_goal - carrier_pos
	var dist := to_goal.length()
	var dir := to_goal / maxf(dist, 0.001)
	var block_dist := minf(AI_BLOCK_DEPTH, dist * 0.45)
	var slot := carrier_pos + dir * block_dist
	# Spread defenders slightly by index so they don't stack.
	slot.x += (float(player_index) - 2.0) * 1.6
	slot.x = clampf(slot.x, -8.5, 8.5)
	slot = _keep_outfield_legal(slot)
	return _steer_toward(slot) * AI_BLOCK_SPEED_SCALE


func _ai_support_attack(carrier: Player) -> Vector3:
	var goal := opponent_goal_point()
	goal.y = 0.0
	var carrier_pos := carrier.global_position
	carrier_pos.y = 0.0
	var to_goal := goal - carrier_pos
	if to_goal.length_squared() < 0.001:
		return Vector3.ZERO
	var ahead := to_goal.normalized()
	var side := Vector3(ahead.z, 0.0, -ahead.x) # perpendicular on XZ
	var lane := (float(player_index) - 2.0) * 2.4
	var slot := carrier_pos + ahead * 3.5 + side * lane
	slot.x = clampf(slot.x, -8.5, 8.5)
	slot.z = clampf(slot.z, -16.0, 16.0)
	slot = _keep_outfield_legal(slot)
	return _steer_toward(slot) * AI_ATTACK_SPEED_SCALE


func _ai_attack_with_ball(_delta: float) -> Vector3:
	var goal := opponent_goal_point()
	var me := global_position
	var xz := Vector3(me.x, 0.0, me.z)
	if not _ai_carry_sampling:
		_ai_carry_last_xz = xz
		_ai_carry_dist = 0.0
		_ai_carry_sampling = true
	else:
		_ai_carry_dist += xz.distance_to(_ai_carry_last_xz)
		_ai_carry_last_xz = xz
	var flat := Vector3(goal.x - me.x, 0.0, goal.z - me.z)
	var dist := flat.length()
	# Shoot inside range, or early to avoid traveling (3 steps ≈ 3.45 m).
	var must_release := _ai_carry_dist >= 2.6
	if (dist <= AI_SHOOT_RANGE or must_release) and _ai_shoot_cd <= 0.0 and match_ball != null:
		var aim := (goal - (me + Vector3(0, 1.2, 0))).normalized()
		if try_shoot(aim, 15.0, match_ball):
			_ai_shoot_cd = AI_SHOOT_COOLDOWN
			_ai_carry_sampling = false
			_ai_carry_dist = 0.0
			return Vector3.ZERO
	# Approach goal with a slight lateral weave by index — stay outside 6 m.
	var approach := Vector3(goal.x + (float(player_index) - 2.0) * 1.2, 0.0, goal.z)
	approach = _keep_outfield_legal(approach)
	return _steer_toward(approach) * AI_ATTACK_SPEED_SCALE


## Soft clamp so AI outfield targets stay outside both goal areas.
func _keep_outfield_legal(target: Vector3) -> Vector3:
	if is_goalkeeper:
		return target
	var out := target
	if Court.in_goal_area(out, team_id):
		out = Court.eject_from_goal_area(out, team_id, 0.6)
	if Court.in_goal_area(out, 1 - team_id):
		out = Court.eject_from_goal_area(out, 1 - team_id, 0.6)
	return out


func _steer_toward(world_target: Vector3) -> Vector3:
	var delta_xz := Vector3(world_target.x - global_position.x, 0.0, world_target.z - global_position.z)
	var dist := delta_xz.length()
	if dist < 0.35:
		return Vector3.ZERO
	# Ease near target so AI doesn't vibrate on the spot.
	var scale := clampf(dist / 2.0, 0.25, 1.0)
	return delta_xz.normalized() * scale


func _on_pickup_body_entered(body: Node3D) -> void:
	if _pickup_block > 0.0 or has_ball or match_frozen:
		return
	if body is Ball:
		var ball := body as Ball
		if ball.try_pickup(self):
			has_ball = true
			_ai_carry_dist = 0.0
			_ai_carry_sampling = false
			possession_changed.emit(true)


func _apply_team_material() -> void:
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh == null:
		return
	_mesh_base_y = _mesh.position.y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.7
	_mesh.material_override = mat
	var head := get_node_or_null("Head") as MeshInstance3D
	if head:
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = body_color.lightened(0.25)
		head.material_override = head_mat


func _update_bob(delta: float, speed: float) -> void:
	if _mesh == null:
		return
	if is_on_floor() and speed > 0.5:
		_bob_phase += delta * BOB_SPEED * clampf(speed / SPEED, 0.4, 1.2)
		_mesh.position.y = _mesh_base_y + sin(_bob_phase) * BOB_AMOUNT
	else:
		_mesh.position.y = lerpf(_mesh.position.y, _mesh_base_y, 1.0 - exp(-10.0 * delta))
