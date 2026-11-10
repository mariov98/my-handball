extends RigidBody3D
class_name Ball

## Handball: follows carrier while held; impulse shot when released.

signal picked_up(player: Player)
signal released(player: Player)

const FOLLOW_LERP := 28.0
const SHOOT_UP_BIAS := 0.18

var carrier: Player = null
var start_position: Vector3 = Vector3.ZERO

var _ignore_carrier_until: float = 0.0


func _ready() -> void:
	start_position = global_position
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true


func _physics_process(delta: float) -> void:
	if carrier == null:
		return
	# Kinematic follow while possessed — freeze physics.
	freeze = true
	var target: Vector3 = carrier.ball_attach.global_position
	global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW_LERP * delta))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func try_pickup(player: Player) -> bool:
	if carrier != null:
		return false
	if Time.get_ticks_msec() < _ignore_carrier_until and player == _last_carrier:
		return false
	carrier = player
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0  # avoid shoving while held
	collision_mask = 0
	picked_up.emit(player)
	return true


var _last_carrier: Player = null


## Optional `up_bias` overrides the default loft (flat vs lob from ShotCraft).
## `shot_meta` is informational for block/GK systems (lob, jump quality, etc.).
var last_shot_meta: Dictionary = {}


func release_and_shoot(
	aim_dir: Vector3,
	impulse_strength: float,
	up_bias: float = -1.0,
	shot_meta: Dictionary = {}
) -> void:
	var shooter := carrier
	_last_carrier = shooter
	carrier = null
	freeze = false
	collision_layer = 4  # layer 3 bit = 4
	collision_mask = 1 | 2 | 4  # court + player + ball (self unused)
	_ignore_carrier_until = Time.get_ticks_msec() + 280
	last_shot_meta = shot_meta.duplicate()
	last_shot_meta["time_msec"] = Time.get_ticks_msec()
	last_shot_meta["shooter"] = shooter
	var dir := aim_dir.normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3(0, 0.2, 1)
	var loft := SHOOT_UP_BIAS if up_bias < 0.0 else up_bias
	dir.y = maxf(dir.y, 0.0) + loft
	dir = dir.normalized()
	last_shot_meta["dir"] = dir
	last_shot_meta["impulse"] = impulse_strength
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	apply_central_impulse(dir * impulse_strength)
	if shooter:
		released.emit(shooter)
	# Restore collision after short delay so ball clears the hand
	get_tree().create_timer(0.25).timeout.connect(_restore_collision)


func _restore_collision() -> void:
	if carrier != null:
		return
	collision_layer = 4
	collision_mask = 1 | 2


func reset_to_start() -> void:
	carrier = null
	_last_carrier = null
	freeze = false
	global_position = start_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 4
	collision_mask = 1 | 2
	_ignore_carrier_until = 0.0
