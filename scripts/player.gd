extends CharacterBody3D
class_name Player

## Capsule outfield / GK. Controlled player receives match input; others idle.

signal possession_changed(has_ball: bool)

const SPEED := 8.5
const AIR_CONTROL := 0.45
const JUMP_VELOCITY := 7.5
const FACE_THRESHOLD := 0.15
const BOB_AMOUNT := 0.04
const BOB_SPEED := 12.0
const PICKUP_COOLDOWN := 0.35

@export var team_id: int = 0 ## 0 = home (blue), 1 = away (red)
@export var is_goalkeeper: bool = false
@export var player_index: int = 0
@export var body_color: Color = Color(0.2, 0.45, 0.9)

var controlled: bool = false
var has_ball: bool = false
var start_position: Vector3 = Vector3.ZERO
var start_yaw: float = 0.0

var _bob_phase: float = 0.0
var _pickup_block: float = 0.0
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

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var input_dir := Vector2.ZERO
	if controlled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var wish := Vector3(input_dir.x, 0.0, input_dir.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	var target_speed := SPEED * (0.85 if is_goalkeeper else 1.0)
	var control := 1.0 if is_on_floor() else AIR_CONTROL
	var desired := wish * target_speed
	velocity.x = lerpf(velocity.x, desired.x, control)
	velocity.z = lerpf(velocity.z, desired.z, control)

	if controlled and Input.is_action_just_pressed("jump") and is_on_floor():
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
	_bob_phase = 0.0
	if _mesh:
		_mesh.position.y = _mesh_base_y


func face_direction() -> Vector3:
	# With rotation.y = atan2(x, z), local +Z faces the move direction.
	return global_transform.basis.z


func _on_pickup_body_entered(body: Node3D) -> void:
	if _pickup_block > 0.0 or has_ball:
		return
	if body is Ball:
		var ball := body as Ball
		if ball.try_pickup(self):
			has_ball = true
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
