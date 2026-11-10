extends Node3D
class_name CameraRig

## Elevated attack view behind the team with possession.
## Center corridor = square goal-centered frame (goal in the middle, not skewed).
## Side ball = subtle yaw about the ball — does NOT recenter the ball on screen;
## the far goal stays the visual anchor.

@export var follow_height: float = 14.0
@export var follow_distance: float = 17.5
## Soft 3/4 bias that only grows as the ball leaves the center corridor.
@export var side_bias: float = 2.4
## |ball.x| half-width treated as "center" (square attack view).
@export var center_corridor_half: float = 2.0
## How far look X tracks the ball (low = goal stays framed; ball drifts off-center).
@export var look_ball_x_blend: float = 0.16
## Blend look Z from a short lead past the ball toward the far goal (goal anchor).
@export var look_goal_blend: float = 0.58
@export var goal_depth: float = 19.5
@export var position_lerp: float = 4.2
@export var rotation_lerp: float = 3.4
## How quickly the rig eases to the opposite end when possession flips.
@export var attack_flip_lerp: float = 2.4
## Radians of orbit yaw per metre of ball X past the yaw deadzone.
@export var ball_yaw_per_meter: float = 0.016
@export var max_ball_yaw: float = 0.13
## Metres of |ball.x| before any yaw starts (keeps center square).
@export var yaw_deadzone: float = 1.6

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


## 0 in the center corridor → 1 well outside (drives side bias / look soften).
func corridor_factor(ball_x: float) -> float:
	return clampf((absf(ball_x) - center_corridor_half) / 4.5, 0.0, 1.0)


func ball_yaw(ball_pos: Vector3) -> float:
	var ax := absf(ball_pos.x)
	if ax <= yaw_deadzone:
		return 0.0
	var excess := ax - yaw_deadzone
	var signed := signf(ball_pos.x) * excess
	return clampf(signed * ball_yaw_per_meter, -max_ball_yaw, max_ball_yaw)


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
	# Orbit around the ball: square behind the attack in the center corridor;
	# subtle yaw + soft side bias only as the ball drifts wide.
	var pivot := pivot_point(ball_pos)
	var yaw := ball_yaw(ball_pos)
	var lateral := side_bias * attack_sign * corridor_factor(ball_pos.x)
	var offset := Vector3(lateral, follow_height, -attack_sign * follow_distance)
	return pivot + offset.rotated(Vector3.UP, yaw)


func _look_target(ball_pos: Vector3) -> Vector3:
	# Goal-anchored framing: look X barely tracks the ball so the goal stays
	# near screen center; look Z blends toward the far goal mouth.
	var cf := corridor_factor(ball_pos.x)
	var look_x := ball_pos.x * look_ball_x_blend * lerpf(0.25, 1.0, cf)
	var goal_z := attack_sign * goal_depth
	var near_lead_z := ball_pos.z + attack_sign * 2.2
	var look_z := lerpf(near_lead_z, goal_z, look_goal_blend)
	return Vector3(look_x, 0.85, look_z)
