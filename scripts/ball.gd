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
var _trail: Node3D = null
const TRAIL_MIN_SPEED := 3.5


func _ready() -> void:
	start_position = global_position
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	_apply_presentation_material()
	_ensure_trail()


func _physics_process(delta: float) -> void:
	if _trail and _trail.has_method("set_active"):
		var flying := carrier == null and not freeze and linear_velocity.length() >= TRAIL_MIN_SPEED
		_trail.call("set_active", flying)
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
	if _trail and _trail.has_method("set_active"):
		_trail.call("set_active", false)
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
	if _trail and _trail.has_method("set_active"):
		_trail.call("set_active", true)
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
	if _trail:
		if _trail.has_method("clear"):
			_trail.call("clear")
		if _trail.has_method("set_active"):
			_trail.call("set_active", false)


func _ensure_trail() -> void:
	_trail = get_node_or_null("BallTrail") as Node3D
	if _trail == null:
		var trail_script := load("res://scripts/ball_trail.gd") as GDScript
		_trail = Node3D.new()
		_trail.set_script(trail_script)
		_trail.name = "BallTrail"
		add_child(_trail)


func _apply_presentation_material() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	# Classic handball orange — unshaded so it stays vivid under OpenGL3/llvmpipe.
	mat.albedo_color = Color(0.98, 0.38, 0.05)
	mat.roughness = 0.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	# Dark seam band for silhouette readability (engine primitives only).
	if get_node_or_null("SeamBand") == null:
		var band := MeshInstance3D.new()
		band.name = "SeamBand"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.105
		torus.outer_radius = 0.122
		band.mesh = torus
		var seam := StandardMaterial3D.new()
		seam.albedo_color = Color(0.1, 0.06, 0.04)
		seam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		band.material_override = seam
		add_child(band)
