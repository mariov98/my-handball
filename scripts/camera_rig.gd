extends Node3D
class_name CameraRig

## Elevated 3/4 view behind the attack; lightly tracks / rotates with the ball.

@export var follow_height: float = 14.0
@export var follow_distance: float = 18.0
@export var side_bias: float = 7.0
@export var look_ahead: float = 4.0
@export var position_lerp: float = 3.5
@export var rotation_lerp: float = 2.8

var ball: Node3D
var attack_sign: float = 1.0 ## +1 home attacks +Z; -1 away attacks -Z

@onready var camera: Camera3D = $Camera3D


func setup(ball_node: Node3D, home_attacks_positive_z: bool = true) -> void:
	ball = ball_node
	attack_sign = 1.0 if home_attacks_positive_z else -1.0
	if ball:
		global_position = _desired_position(ball.global_position)
		look_at(_look_target(ball.global_position), Vector3.UP)


func set_attack_direction(toward_positive_z: bool) -> void:
	attack_sign = 1.0 if toward_positive_z else -1.0


func _physics_process(delta: float) -> void:
	if ball == null:
		return
	var ball_pos := ball.global_position
	var desired := _desired_position(ball_pos)
	global_position = global_position.lerp(desired, 1.0 - exp(-position_lerp * delta))

	var look := _look_target(ball_pos)
	var from := global_position
	var target_basis := Basis.looking_at((look - from).normalized(), Vector3.UP)
	var current_q := global_transform.basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var blended := current_q.slerp(target_q, 1.0 - exp(-rotation_lerp * delta))
	global_transform.basis = Basis(blended)


func _desired_position(ball_pos: Vector3) -> Vector3:
	# Behind the attack: sit on the defensive side of the ball along Z.
	var back := -attack_sign * follow_distance
	return Vector3(
		ball_pos.x * 0.35 + side_bias,
		follow_height,
		ball_pos.z + back
	)


func _look_target(ball_pos: Vector3) -> Vector3:
	return Vector3(ball_pos.x * 0.5, 0.6, ball_pos.z + attack_sign * look_ahead)
