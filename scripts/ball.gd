extends RigidBody3D
class_name Ball

## Handball: follows carrier while held; impulse shot when released.

signal picked_up(player: Player)
signal released(player: Player)

const FOLLOW_LERP := 40.0
const SHOOT_UP_BIAS := 0.16
## Phase B procedural dribble bounce (approx continuous stream, no palm contact).
const DRIBBLE_PERIOD_S := 0.36
const DRIBBLE_BALL_RADIUS := 0.12
const DRIBBLE_FLOOR_PROBE := 2.4

var carrier: Player = null
var start_position: Vector3 = Vector3.ZERO

var _ignore_carrier_until: float = 0.0
var _trail: Node3D = null
const TRAIL_MIN_SPEED := 3.5

var _dribble_phase: float = 0.0
var _dribble_floor_y: float = DRIBBLE_BALL_RADIUS
var _dribble_was_low: bool = false
## Phase F bounce pass: armed until first floor contact redirects toward receiver.
var _bounce_armed: bool = false
var _bounce_done: bool = false


func _ready() -> void:
	start_position = global_position
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	_apply_presentation_material()
	_ensure_trail()
	if not body_entered.is_connected(_on_body_entered_bounce):
		body_entered.connect(_on_body_entered_bounce)


func _physics_process(delta: float) -> void:
	if _trail and _trail.has_method("set_active"):
		var flying := carrier == null and not freeze and linear_velocity.length() >= TRAIL_MIN_SPEED
		_trail.call("set_active", flying)
	if carrier == null:
		_dribble_phase = 0.0
		_dribble_was_low = false
		_try_bounce_floor_redirect()
		_soft_pass_steer(delta)
		return
	# Kinematic follow while possessed — freeze physics.
	freeze = true
	var target: Vector3 = carrier.ball_attach.global_position
	if carrier.dribbling:
		target = _dribble_follow_target(delta, target)
	else:
		_dribble_phase = 0.0
		_dribble_was_low = false
	global_position = global_position.lerp(target, 1.0 - exp(-FOLLOW_LERP * delta))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Fake bounce on the attach point: procedural Y + periodic floor probe at troughs.
func _dribble_follow_target(delta: float, attach: Vector3) -> Vector3:
	_dribble_phase = fmod(_dribble_phase + delta / DRIBBLE_PERIOD_S, 1.0)
	# sin goes 0 → 1 → 0 over one period; troughs are floor contacts.
	var lift := sin(_dribble_phase * PI)
	var low := lift < 0.12
	if low and not _dribble_was_low:
		_dribble_floor_y = _probe_floor_y(attach)
	_dribble_was_low = low
	var hand_y := attach.y
	var floor_y := _dribble_floor_y
	var y := lerpf(floor_y, hand_y, clampf(lift, 0.0, 1.0))
	return Vector3(attach.x, y, attach.z)


func _probe_floor_y(from: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return DRIBBLE_BALL_RADIUS
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3(0.0, 0.2, 0.0),
		from + Vector3(0.0, -DRIBBLE_FLOOR_PROBE, 0.0)
	)
	query.collision_mask = 1  # court
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return DRIBBLE_BALL_RADIUS
	return float(hit.position.y) + DRIBBLE_BALL_RADIUS


## Light in-flight nudge toward the intended pass receiver — catchable, not magnetized.
func _soft_pass_steer(delta: float) -> void:
	if freeze or not bool(last_shot_meta.get("pass", false)):
		return
	# Bounce first hop aims at the floor — don't steer until after the hop.
	if _bounce_armed and not _bounce_done:
		return
	var intended: Variant = last_shot_meta.get("pass_target", null)
	if intended == null or not is_instance_valid(intended):
		return
	if not (intended is Node3D):
		return
	var recv := intended as Node3D
	var catch_y := 1.1
	var pass_type := int(last_shot_meta.get("pass_type", PassCraft.PassType.FLAT))
	if pass_type == PassCraft.PassType.LOB:
		catch_y = 1.45
	elif pass_type == PassCraft.PassType.BOUNCE:
		catch_y = 1.05
	var to_recv := recv.global_position + Vector3(0, catch_y, 0) - global_position
	var dist := to_recv.length()
	var steer_dist := (
		PassCraft.LOB_FLIGHT_STEER_DIST
		if pass_type == PassCraft.PassType.LOB
		else PassCraft.FLIGHT_STEER_DIST
	)
	if dist <= 0.15 or dist > steer_dist:
		return
	var speed := linear_velocity.length()
	if speed < 2.5:
		return
	# Only steer when still generally traveling toward the receiver.
	var toward := to_recv.normalized()
	if linear_velocity.normalized().dot(toward) < 0.15:
		return
	var blend := clampf(PassCraft.FLIGHT_STEER * delta * (1.0 - dist / steer_dist), 0.0, 0.35)
	var steered := linear_velocity.lerp(toward * speed, blend)
	linear_velocity = steered


func is_pass_in_flight() -> bool:
	return carrier == null and bool(last_shot_meta.get("pass", false))


func pass_type() -> int:
	if not is_pass_in_flight():
		return PassCraft.PassType.FLAT
	return int(last_shot_meta.get("pass_type", PassCraft.PassType.FLAT))


func pass_intended_receiver() -> Player:
	if not is_pass_in_flight():
		return null
	var intended: Variant = last_shot_meta.get("pass_target", null)
	if intended != null and is_instance_valid(intended) and intended is Player:
		return intended as Player
	return null


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
	_bounce_armed = false
	_bounce_done = false
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
	var is_pass := bool(shot_meta.get("pass", false))
	var pass_type := int(shot_meta.get("pass_type", PassCraft.PassType.FLAT))
	_bounce_armed = is_pass and pass_type == PassCraft.PassType.BOUNCE
	_bounce_done = false
	# Passes clear the passer quickly but stay catchable for teammates sooner.
	var ignore_ms := 100 if is_pass else 200
	_ignore_carrier_until = Time.get_ticks_msec() + ignore_ms
	last_shot_meta = shot_meta.duplicate()
	last_shot_meta["time_msec"] = Time.get_ticks_msec()
	last_shot_meta["shooter"] = shooter
	last_shot_meta["pass_type"] = pass_type
	var dir := aim_dir.normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3(0, 0.2, 1)
	var loft := SHOOT_UP_BIAS if up_bias < 0.0 else up_bias
	if is_pass:
		match pass_type:
			PassCraft.PassType.LOB:
				loft = clampf(loft, PassCraft.LOB_LOFT_MIN, PassCraft.LOB_LOFT_MAX)
				dir.y = maxf(dir.y, 0.0) + loft
				dir = dir.normalized()
			PassCraft.PassType.BOUNCE:
				# Keep downward/floor aim — do not force positive loft on first hop.
				if dir.y > 0.05:
					dir.y = 0.02
				dir = dir.normalized()
			_:
				loft = clampf(loft, PassCraft.LOFT_MIN, PassCraft.LOFT_MAX)
				dir.y = maxf(dir.y, 0.0) + loft
				dir = dir.normalized()
	else:
		dir.y = maxf(dir.y, 0.0) + loft
		dir = dir.normalized()
	last_shot_meta["dir"] = dir
	last_shot_meta["impulse"] = impulse_strength
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Passes skip player rigid collisions briefly so the throw doesn't die in the
	# passer capsule; Area pickup / sticky catch still see the ball layer.
	if is_pass:
		collision_mask = 1
		var lo := PassCraft.IMPULSE_MIN
		var hi := PassCraft.IMPULSE_MAX
		match pass_type:
			PassCraft.PassType.LOB:
				lo = PassCraft.LOB_IMPULSE_MIN
				hi = PassCraft.LOB_IMPULSE_MAX
			PassCraft.PassType.BOUNCE:
				lo = PassCraft.BOUNCE_IMPULSE_MIN
				hi = PassCraft.BOUNCE_IMPULSE_MAX
		# Direct velocity keeps soft-pass pace readable (mass 0.45 would amplify impulse).
		linear_velocity = dir * clampf(impulse_strength, lo, hi)
	else:
		apply_central_impulse(dir * impulse_strength)
	if _trail and _trail.has_method("set_active"):
		_trail.call("set_active", true)
	if shooter:
		released.emit(shooter)
	# Restore collision after short delay so ball clears the hand
	var restore_s := 0.22 if is_pass else 0.25
	if is_pass and pass_type == PassCraft.PassType.BOUNCE:
		restore_s = 0.35  # stay court-only until after the floor hop
	get_tree().create_timer(restore_s).timeout.connect(_restore_collision)


func _on_body_entered_bounce(body: Node) -> void:
	if not _bounce_armed or _bounce_done or carrier != null:
		return
	# Court StaticBody / floor collision — hop toward receiver.
	if body is StaticBody3D or body is CSGShape3D or body.name == "Floor":
		_redirect_bounce_pass()


## Fallback when contact signal misses (soft floor y probe).
func _try_bounce_floor_redirect() -> void:
	if not _bounce_armed or _bounce_done or carrier != null or freeze:
		return
	if global_position.y <= DRIBBLE_BALL_RADIUS + 0.08 and linear_velocity.y <= 0.5:
		_redirect_bounce_pass()


func _redirect_bounce_pass() -> void:
	if _bounce_done:
		return
	_bounce_done = true
	_bounce_armed = false
	last_shot_meta["bounce_hopped"] = true
	var intended: Variant = last_shot_meta.get("pass_target", null)
	var to := Vector3(0.0, 1.1, 1.0 if _last_carrier == null or _last_carrier.team_id == 0 else -1.0)
	if intended != null and is_instance_valid(intended) and intended is Node3D:
		var recv := intended as Node3D
		to = recv.global_position + Vector3(0.0, 1.1, 0.0) - global_position
	if to.length_squared() < 0.01:
		to = Vector3(0.0, 0.4, 1.0)
	to = to.normalized()
	to.y = maxf(to.y, 0.0) + PassCraft.BOUNCE_HOP_LOFT
	to = to.normalized()
	var speed := clampf(
		linear_velocity.length() * PassCraft.BOUNCE_HOP_SPEED_SCALE,
		PassCraft.BOUNCE_IMPULSE_MIN * 0.75,
		PassCraft.BOUNCE_IMPULSE_MAX
	)
	# Lift slightly off the floor so the hop clears immediately.
	global_position.y = maxf(global_position.y, DRIBBLE_BALL_RADIUS + 0.05)
	linear_velocity = to * speed
	angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	# Allow sticky catch / player collision after the hop.
	collision_mask = 1 | 2


func _restore_collision() -> void:
	if carrier != null:
		return
	collision_layer = 4
	# Bounce first hop keeps court-only until redirect finishes.
	if _bounce_armed and not _bounce_done:
		collision_mask = 1
		return
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
	_bounce_armed = false
	_bounce_done = false
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
