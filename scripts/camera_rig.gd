extends Node3D
class_name CameraRig

## Elevated 3/4 view behind the attacking team.
## Yaw/orbit pivots around the ball (attack focus), not the far goal.

@export var follow_height: float = 14.0
@export var follow_distance: float = 18.0
@export var side_bias: float = 7.0
## Small lead past the ball along the attack so the goal stays in frame.
@export var look_ahead: float = 2.5
@export var position_lerp: float = 3.5
@export var rotation_lerp: float = 2.8
## How quickly the rig eases to the opposite end when possession flips.
@export var attack_flip_lerp: float = 2.4
## Radians of orbit yaw per metre of ball X (clamped by max_ball_yaw).
@export var ball_yaw_per_meter: float = 0.035
@export var max_ball_yaw: float = 0.35

var ball: Node3D
## Smoothed attack facing: +1 home attacks +Z; -1 away attacks -Z.
var attack_sign: float = 1.0
var _target_attack_sign: float = 1.0

@onready var camera: Camera3D = $Camera3D


func setup(ball_node: Node3D, home_attacks_positive_z: bool = true) -> void:
	ball = ball_node
	_target_attack_sign = 1.0 if home_attacks_positive_z else -1.0
	attack_sign = _target_attack_sign
	if ball:
		global_position = _desired_position(ball.global_position)
		look_at(_look_target(ball.global_position), Vector3.UP)


func set_attack_direction(toward_positive_z: bool) -> void:
	_target_attack_sign = 1.0 if toward_positive_z else -1.0


func get_attack_sign() -> float:
	return attack_sign


func get_target_attack_sign() -> float:
	return _target_attack_sign


## Attack focus used as the orbit / look pivot (ball on the court plane).
func pivot_point(ball_pos: Vector3) -> Vector3:
	return Vector3(ball_pos.x, 0.0, ball_pos.z)


func ball_yaw(ball_pos: Vector3) -> float:
	return clampf(ball_pos.x * ball_yaw_per_meter, -max_ball_yaw, max_ball_yaw)


func _physics_process(delta: float) -> void:
	if ball == null:
		return

	# Ease attack_sign so possession flips orbit smoothly (no snap).
	attack_sign = lerpf(attack_sign, _target_attack_sign, 1.0 - exp(-attack_flip_lerp * delta))

	var ball_pos := ball.global_position
	var desired := _desired_position(ball_pos)
	global_position = global_position.lerp(desired, 1.0 - exp(-position_lerp * delta))

	var look := _look_target(ball_pos)
	var from := global_position
	var to_look := look - from
	if to_look.length_squared() < 0.0001:
		return
	var target_basis := Basis.looking_at(to_look.normalized(), Vector3.UP)
	var current_q := global_transform.basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var blended := current_q.slerp(target_q, 1.0 - exp(-rotation_lerp * delta))
	global_transform.basis = Basis(blended)


func _desired_position(ball_pos: Vector3) -> Vector3:
	# Orbit around the ball: base offset is behind the attack with a 3/4 side bias,
	# then yawed about the ball when it drifts left/right.
	var pivot := pivot_point(ball_pos)
	var yaw := ball_yaw(ball_pos)
	var lateral := side_bias * attack_sign
	var offset := Vector3(lateral, follow_height, -attack_sign * follow_distance)
	return pivot + offset.rotated(Vector3.UP, yaw)


func _look_target(ball_pos: Vector3) -> Vector3:
	# Look at the ball with a short attack-direction lead (same yaw as the orbit),
	# so framing stays ball-centered — the far goal is not the rotation center.
	var yaw := ball_yaw(ball_pos)
	var lead := Vector3(0.0, 0.0, attack_sign * look_ahead).rotated(Vector3.UP, yaw)
	var pivot := pivot_point(ball_pos)
	return Vector3(pivot.x, 0.6, pivot.z) + lead
