extends Node3D
class_name CameraRig

## Elevated attack view behind the team with possession.
## Center corridor = square goal-centered frame (goal in the middle, not skewed).
## Side ball = subtle yaw about the ball — does NOT recenter the ball on screen;
## the far goal stays the visual anchor.
## Wave 6: player nudge (yaw / height / distance) + optional wing-shot cinematic.

## Metres. Pulled in so a 1.90 m player reads on the 40×20 without becoming a giant.
@export var follow_height: float = 11.6
@export var follow_distance: float = 15.2
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

## Wave 6 R5.2 nudge limits (additive on top of the elevated 3/4 base).
@export var nudge_yaw_max: float = 0.42
@export var nudge_height_max: float = 2.8
@export var nudge_distance_max: float = 4.5
@export var nudge_yaw_speed: float = 1.1
@export var nudge_zoom_speed: float = 6.0
@export var nudge_height_speed: float = 4.0

## Wave 6 R5.3 wing cinematic (brief zoom + slow-mo).
@export var wing_cinematic_enabled: bool = true
@export var wing_cinematic_duration: float = 0.72
@export var wing_cinematic_zoom: float = 3.4
@export var wing_cinematic_height: float = -1.2
@export var wing_cinematic_time_scale: float = 0.48

var ball: Node3D
## Smoothed attack facing: +1 home attacks +Z; -1 away attacks -Z.
var attack_sign: float = 1.0
var _target_attack_sign: float = 1.0

## Player nudge state (R5.2).
var nudge_yaw: float = 0.0
var nudge_height: float = 0.0
var nudge_distance: float = 0.0

## Wing cinematic remaining (seconds of scaled time).
var _wing_cine_t: float = 0.0
var _wing_cine_active: bool = false

@onready var camera: Camera3D = $Camera3D


func setup(ball_node: Node3D, home_attacks_positive_z: bool = true) -> void:
	ball = ball_node
	_target_attack_sign = 1.0 if home_attacks_positive_z else -1.0
	attack_sign = _target_attack_sign
	reset_nudge()
	end_wing_cinematic(true)
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


## R5.2: apply stick/key nudge without breaking the elevated ball-yaw base.
## yaw_axis: -1 left … +1 right; zoom_axis: -1 closer … +1 farther; height_axis: -1 lower … +1 higher.
func apply_nudge_input(yaw_axis: float, zoom_axis: float, height_axis: float, delta: float) -> void:
	if _wing_cine_active:
		return
	nudge_yaw = clampf(
		nudge_yaw + yaw_axis * nudge_yaw_speed * delta,
		-nudge_yaw_max,
		nudge_yaw_max
	)
	nudge_distance = clampf(
		nudge_distance + zoom_axis * nudge_zoom_speed * delta,
		-nudge_distance_max,
		nudge_distance_max
	)
	nudge_height = clampf(
		nudge_height + height_axis * nudge_height_speed * delta,
		-nudge_height_max,
		nudge_height_max
	)


func reset_nudge() -> void:
	nudge_yaw = 0.0
	nudge_height = 0.0
	nudge_distance = 0.0


func is_wing_cinematic_active() -> bool:
	return _wing_cine_active


func trigger_wing_cinematic() -> void:
	if not wing_cinematic_enabled:
		return
	_wing_cine_t = wing_cinematic_duration
	if not _wing_cine_active:
		_wing_cine_active = true
		Engine.time_scale = wing_cinematic_time_scale


func end_wing_cinematic(force_restore_time: bool = false) -> void:
	_wing_cine_t = 0.0
	if _wing_cine_active or force_restore_time:
		_wing_cine_active = false
		# Don't stomp an active goal slow-mo (MatchController owns that).
		if absf(Engine.time_scale - wing_cinematic_time_scale) < 0.05 or force_restore_time:
			if Engine.time_scale < 0.95:
				Engine.time_scale = 1.0


func _physics_process(delta: float) -> void:
	if ball == null:
		return

	# Wing cinematic ticks in scaled time; snap back after release window.
	if _wing_cine_active:
		_wing_cine_t = maxf(0.0, _wing_cine_t - delta)
		if _wing_cine_t <= 0.0:
			end_wing_cinematic()

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
	# Wave 6: player nudge + brief wing cinematic zoom sit on top of that base.
	var pivot := pivot_point(ball_pos)
	var yaw := ball_yaw(ball_pos) + nudge_yaw
	var height := follow_height + nudge_height
	var distance := follow_distance + nudge_distance
	if _wing_cine_active:
		# Full pull-in at trigger, ease out as the timer drains (readable, not a flash).
		var remain := clampf(_wing_cine_t / maxf(wing_cinematic_duration, 0.01), 0.0, 1.0)
		var peak := remain * remain * (3.0 - 2.0 * remain) # smoothstep
		height += wing_cinematic_height * peak
		distance -= wing_cinematic_zoom * peak
	var lateral := side_bias * attack_sign * corridor_factor(ball_pos.x)
	var offset := Vector3(lateral, height, -attack_sign * distance)
	return pivot + offset.rotated(Vector3.UP, yaw)


func _look_target(ball_pos: Vector3) -> Vector3:
	# Goal-anchored framing: look X barely tracks the ball so the goal stays
	# near screen center; look Z blends toward the far goal mouth.
	var cf := corridor_factor(ball_pos.x)
	var look_x := ball_pos.x * look_ball_x_blend * lerpf(0.25, 1.0, cf)
	# Nudge yaw slightly shifts look so aim isn't completely broken (R5.2).
	look_x += sin(nudge_yaw) * 2.4
	var goal_z := attack_sign * goal_depth
	var near_lead_z := ball_pos.z + attack_sign * 2.2
	var look_z := lerpf(near_lead_z, goal_z, look_goal_blend)
	var look_y := 1.05 + nudge_height * 0.04
	if _wing_cine_active:
		look_y += 0.25
	return Vector3(look_x, look_y, look_z)
