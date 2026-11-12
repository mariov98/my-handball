extends CharacterBody3D
class_name Player

## Capsule outfield / GK. Controlled player receives match input; AI teammates chase/block.
## Phase 3: GK dive/track, outfield block volume for contested shots.
## Phase 4: formation-aware off-ball slots (wing / backcourt / pivot-ish).

signal possession_changed(has_ball: bool)
signal dive_started
signal block_attempted(blocker: Player, ball: Ball, success: bool)

const SPEED := 9.6
const AIR_CONTROL := 0.58
const JUMP_VELOCITY := 7.8
const FACE_THRESHOLD := 0.12
const BOB_AMOUNT := 0.04
const BOB_SPEED := 13.0
const PICKUP_COOLDOWN := 0.22

# AI tuning — pressure on defense, beatable on the break.
const AI_CHASE_SPEED_SCALE := 0.88
const AI_BLOCK_SPEED_SCALE := 0.92
const AI_ATTACK_SPEED_SCALE := 0.84
const AI_GK_SPEED_SCALE := 0.76
const AI_GK_TRACK_SPEED_SCALE := 1.0
const AI_SHOOT_RANGE := 10.0
const AI_SHOOT_COOLDOWN := 1.55
const AI_PASS_COOLDOWN := 0.7
const AI_BLOCK_DEPTH := 4.5
## Defender inside this range → prefer pass over forcing a shot.
const AI_PRESSURE_RANGE := 2.9
## Carry distance that reads as "last step" before traveling (~3 plants).
const AI_STEP_WARN_DIST := 2.5

# Phase 3 GK dive
const DIVE_DURATION := 0.55
const DIVE_COOLDOWN := 0.95
const DIVE_SPEED := 13.0
const DIVE_UP := 3.0
const GK_LATERAL_BOOST := 1.18
const AI_DIVE_REACT_DIST := 11.5
const AI_DIVE_MIN_BALL_SPEED := 7.0

@export var team_id: int = 0 ## 0 = home (blue), 1 = away (red)
@export var is_goalkeeper: bool = false
@export var player_index: int = 0
@export var body_color: Color = Color(0.2, 0.45, 0.9)

var controlled: bool = false
var ai_enabled: bool = false
var has_ball: bool = false
## Phase B: continuous bounce stream while held (MatchController / rules drive this).
var dribbling: bool = false
var start_position: Vector3 = Vector3.ZERO
var start_yaw: float = 0.0
## Set by MatchController so AI can chase / shoot.
var match_ball: Ball = null
var match_frozen: bool = false
## True while GK dive impulse is active.
var diving: bool = false
## Brief window after dive / raise where blocks are sticky.
var block_ready: bool = false

var _bob_phase: float = 0.0
var _pickup_block: float = 0.0
var _ai_shoot_cd: float = 0.0
var _ai_pass_cd: float = 0.0
## AI carry distance — pass/shoot before Phase 2 traveling fires.
var _ai_carry_dist: float = 0.0
var _ai_carry_last_xz: Vector3 = Vector3.ZERO
var _ai_carry_sampling: bool = false
var _mesh: MeshInstance3D
var _mesh_base_y: float = 0.9
var _dive_timer: float = 0.0
var _dive_cd: float = 0.0
var _block_timer: float = 0.0
var _dive_dir: Vector3 = Vector3.ZERO
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _save_area: Area3D
var _block_area: Area3D
var _body_mat: StandardMaterial3D
var _kit_nodes_ready: bool = false

@onready var ball_attach: Marker3D = $BallAttach
@onready var pickup_area: Area3D = $PickupArea


func _ready() -> void:
	start_position = global_position
	start_yaw = rotation.y
	_ensure_craft_nodes()
	_ensure_kit_nodes()
	_apply_team_material()
	pickup_area.body_entered.connect(_on_pickup_body_entered)
	if _save_area:
		_save_area.body_entered.connect(_on_save_body_entered)
	if _block_area:
		_block_area.body_entered.connect(_on_block_body_entered)


func _physics_process(delta: float) -> void:
	if _pickup_block > 0.0:
		_pickup_block = maxf(0.0, _pickup_block - delta)
	if _ai_shoot_cd > 0.0:
		_ai_shoot_cd = maxf(0.0, _ai_shoot_cd - delta)
	if _ai_pass_cd > 0.0:
		_ai_pass_cd = maxf(0.0, _ai_pass_cd - delta)
	if _dive_cd > 0.0:
		_dive_cd = maxf(0.0, _dive_cd - delta)
	if _block_timer > 0.0:
		_block_timer = maxf(0.0, _block_timer - delta)
		block_ready = _block_timer > 0.0 or diving
	else:
		block_ready = diving

	if diving:
		_dive_timer -= delta
		if _dive_timer <= 0.0:
			diving = false
			_set_dive_pose(false)
		else:
			# Keep lateral dive velocity dominant while airborne-ish.
			velocity.x = _dive_dir.x * DIVE_SPEED
			velocity.z = _dive_dir.z * DIVE_SPEED

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var wish := Vector3.ZERO
	if match_frozen:
		wish = Vector3.ZERO
	elif diving:
		wish = Vector3.ZERO
	elif controlled:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# WASD / left stick are camera-relative: forward = into the screen along
		# the current camera facing projected onto the court plane.
		wish = camera_relative_wish(input_dir)
		if is_goalkeeper and Input.is_action_just_pressed("dive"):
			try_dive(_preferred_dive_dir(wish))
	elif ai_enabled:
		wish = _ai_wish(delta)

	var target_speed := SPEED * (0.85 if is_goalkeeper else 1.0)
	if is_goalkeeper and not diving:
		# Quicker lateral shuffle on the line.
		target_speed *= GK_LATERAL_BOOST
	if ai_enabled and not controlled:
		if is_goalkeeper:
			target_speed *= AI_GK_SPEED_SCALE * AI_GK_TRACK_SPEED_SCALE
		else:
			target_speed *= AI_CHASE_SPEED_SCALE
	# Snappy ground response; softer air control for jump-shot steering.
	if not diving:
		var desired := wish * target_speed
		var rate := 18.0 if is_on_floor() else (18.0 * AIR_CONTROL)
		var blend := 1.0 - exp(-rate * delta)
		velocity.x = lerpf(velocity.x, desired.x, blend)
		velocity.z = lerpf(velocity.z, desired.z, blend)

	if controlled and not match_frozen and not diving and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length() > FACE_THRESHOLD and not diving:
		var target_yaw := atan2(planar.x, planar.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	_update_bob(delta, planar.length())
	_update_arm_pose(delta)
	_try_sticky_pass_catch()


func try_shoot(
	aim_dir: Vector3,
	impulse_strength: float,
	ball: Ball,
	up_bias: float = -1.0,
	shot_meta: Dictionary = {}
) -> bool:
	if not has_ball or ball == null or ball.carrier != self:
		return false
	_pickup_block = PICKUP_COOLDOWN
	dribbling = false
	has_ball = false
	possession_changed.emit(false)
	ball.release_and_shoot(aim_dir, impulse_strength, up_bias, shot_meta)
	return true


## GK dive toward a planar direction. Returns true if dive started.
func try_dive(dir: Vector3) -> bool:
	if not is_goalkeeper or diving or match_frozen or has_ball:
		return false
	if _dive_cd > 0.0:
		return false
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.01:
		# Default dive toward ball or across goal.
		if match_ball:
			flat = Vector3(
				match_ball.global_position.x - global_position.x,
				0.0,
				match_ball.global_position.z - global_position.z
			)
		else:
			flat = face_direction()
			flat.y = 0.0
	if flat.length_squared() < 0.01:
		flat = Vector3.RIGHT if team_id == 0 else Vector3.LEFT
	_dive_dir = flat.normalized()
	diving = true
	_dive_timer = DIVE_DURATION
	_dive_cd = DIVE_COOLDOWN + DIVE_DURATION
	_block_timer = DIVE_DURATION + 0.15
	block_ready = true
	velocity = _dive_dir * DIVE_SPEED + Vector3(0.0, DIVE_UP, 0.0)
	_set_dive_pose(true)
	dive_started.emit()
	return true


func raise_block(duration: float = 0.45) -> void:
	_block_timer = maxf(_block_timer, duration)
	block_ready = true


func reset_to_start() -> void:
	global_position = start_position
	rotation.y = start_yaw
	velocity = Vector3.ZERO
	has_ball = false
	dribbling = false
	_pickup_block = 0.0
	_ai_shoot_cd = 0.0
	_ai_pass_cd = 0.0
	_ai_carry_dist = 0.0
	_ai_carry_sampling = false
	_bob_phase = 0.0
	diving = false
	_dive_timer = 0.0
	_dive_cd = 0.0
	_block_timer = 0.0
	block_ready = false
	_set_dive_pose(false)
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


func _preferred_dive_dir(wish: Vector3) -> Vector3:
	if wish.length_squared() > 0.05:
		return wish
	if match_ball:
		return match_ball.global_position - global_position
	return face_direction()


func _ai_wish(delta: float) -> Vector3:
	if match_ball == null:
		return _steer_toward(Formations.attack_slot(self, start_position))

	if is_goalkeeper:
		return _ai_gk_wish()

	if has_ball and match_ball.carrier == self:
		return _ai_attack_with_ball(delta)

	var carrier := match_ball.carrier
	if carrier == null:
		return _ai_free_ball_position()
	if carrier.team_id == team_id:
		return _ai_support_attack(carrier)
	return _ai_defend_block(carrier)


func _ai_gk_wish() -> Vector3:
	var ball_pos := match_ball.global_position
	var home := start_position
	var track_x := clampf(ball_pos.x, -3.4, 3.4)
	# Ease slightly off the line toward the ball when it approaches.
	var gap := absf(ball_pos.z - home.z)
	var approach := clampf(1.0 - gap / 12.0, 0.0, 1.0)
	var toward_court := 1.0 if team_id == 0 else -1.0
	var target := Vector3(track_x, 0.0, home.z + toward_court * approach * 1.8)
	if team_id == 0:
		target.z = clampf(target.z, -18.5, -14.0)
	else:
		target.z = clampf(target.z, 14.0, 18.5)

	# Predict incoming shot and dive into the flight path.
	if match_ball.carrier == null and not diving and _dive_cd <= 0.0:
		var speed := match_ball.linear_velocity.length()
		var toward_goal := match_ball.linear_velocity.z * (-toward_court)
		if speed >= AI_DIVE_MIN_BALL_SPEED and toward_goal > 2.0 and gap < AI_DIVE_REACT_DIST:
			var intercept := _predict_gk_intercept(ball_pos, match_ball.linear_velocity)
			var to_int := intercept - global_position
			to_int.y = 0.0
			if to_int.length() < 4.2:
				try_dive(to_int)
				return Vector3.ZERO
			# Shuffle hard toward intercept before diving.
			target.x = clampf(intercept.x, -3.4, 3.4)

	return _steer_toward(target)


func _predict_gk_intercept(ball_pos: Vector3, ball_vel: Vector3) -> Vector3:
	var goal_z := start_position.z
	if absf(ball_vel.z) < 0.05:
		return Vector3(clampf(ball_pos.x, -3.2, 3.2), 1.0, goal_z)
	var t := (goal_z - ball_pos.z) / ball_vel.z
	t = clampf(t, 0.0, 1.1)
	var hit := ball_pos + ball_vel * t
	hit.x = clampf(hit.x, -3.4, 3.4)
	hit.y = clampf(hit.y, 0.3, 2.2)
	hit.z = goal_z
	return hit


func _ai_free_ball_position() -> Vector3:
	# Nearest outfield teammate presses the free ball; others hold shape.
	var my_d := global_position.distance_squared_to(match_ball.global_position)
	var i_am_chaser := true
	var parent_n := get_parent()
	if parent_n:
		for sibling in parent_n.get_children():
			if sibling == self or not (sibling is Player):
				continue
			var mate := sibling as Player
			if mate.is_goalkeeper or mate.match_frozen:
				continue
			if mate.global_position.distance_squared_to(match_ball.global_position) + 0.35 < my_d:
				i_am_chaser = false
				break
	if i_am_chaser:
		var target := match_ball.global_position
		target.y = 0.0
		target = _keep_outfield_legal(target)
		return _steer_toward(target)
	# Hold attack/defense-neutral mid shape toward last ball side.
	var slot := Formations.attack_slot(self, match_ball.global_position)
	# Bias slightly toward ball without full chase.
	slot = slot.lerp(Vector3(match_ball.global_position.x, 0.0, match_ball.global_position.z), 0.2)
	slot = _keep_outfield_legal(slot)
	return _steer_toward(slot) * AI_ATTACK_SPEED_SCALE


func _ai_defend_block(carrier: Player) -> Vector3:
	var ball_pos := match_ball.global_position if match_ball else carrier.global_position
	var slot := Formations.defense_slot(self, ball_pos, carrier)
	# Micro-adjust toward the carrier lane so the wall isn't glued to spots.
	var carrier_pos := carrier.global_position
	carrier_pos.y = 0.0
	slot.x = lerpf(slot.x, carrier_pos.x, 0.12)
	slot = _keep_outfield_legal(slot)
	if carrier.has_ball and carrier_pos.distance_to(global_position) < 3.8:
		raise_block(0.2)
	return _steer_toward(slot) * AI_BLOCK_SPEED_SCALE


func _ai_support_attack(carrier: Player) -> Vector3:
	# Show for pass: hold a formation lane but step into an open angle when a
	# teammate (esp. the human) has the ball — readable wing↔CB circulation.
	var ball_pos := carrier.global_position
	var slot := Formations.show_for_pass_slot(self, ball_pos)
	var to_carrier := slot.distance_to(Vector3(ball_pos.x, 0.0, ball_pos.z))
	if to_carrier < 2.4:
		# Don't stack on the ball carrier — slide wider.
		var side := 1.0 if Formations.role_for(self) == Formations.Role.RIGHT_WING else -1.0
		if Formations.role_for(self) == Formations.Role.CENTER_BACK:
			side = 0.0
			slot.z += (-1.0 if team_id == 0 else 1.0) * 1.5
		slot.x += side * 2.2
	slot = _keep_outfield_legal(slot)
	# Slightly sharper close-out when showing so the lane arrives in time.
	return _steer_toward(slot) * minf(AI_ATTACK_SPEED_SCALE * 1.08, 1.0)


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
	# Pass or shoot before traveling (3 steps ≈ ~5.4 m with tuned gait).
	var must_release := _ai_carry_dist >= 3.2
	var step_warn := _ai_carry_dist >= AI_STEP_WARN_DIST
	var under_pressure := _ai_under_pressure()
	var pass_target := _ai_pass_target()
	# Prefer pass under pressure / at step warning before forcing a contested shot.
	var prefer_pass := pass_target != null and (
		must_release
		or under_pressure
		or step_warn
		or dist > 8.5
		or ((int(Time.get_ticks_msec() / 700) + player_index) % 3) == 0
	)
	if match_ball != null and prefer_pass and _ai_pass_cd <= 0.0:
		if _ai_try_pass(pass_target):
			return Vector3.ZERO
	if match_ball != null and (dist <= AI_SHOOT_RANGE or must_release):
		# Don't force a shot while pressed if a teammate is available.
		if under_pressure and pass_target != null and not must_release:
			return _steer_toward(_keep_outfield_legal(
				Vector3(goal.x + (float(player_index) - 2.0) * 1.2, 0.0, goal.z)
			)) * AI_ATTACK_SPEED_SCALE
		if _ai_shoot_cd <= 0.0 and (dist <= AI_SHOOT_RANGE or must_release):
			var aim := (goal - (me + Vector3(0, 1.2, 0))).normalized()
			# Slight aim noise so Away isn't laser-perfect.
			aim += Vector3(randf_range(-0.06, 0.06), randf_range(-0.02, 0.03), randf_range(-0.04, 0.04))
			aim = aim.normalized()
			var lob := dist < 7.0 and (player_index % 2) == 0
			var impulse := ShotCraft.impulse_for_charge(0.55, lob)
			var up := ShotCraft.up_bias(lob)
			var meta := {"lob": lob, "ai": true, "charge": 0.55}
			if try_shoot(aim, impulse, match_ball, up, meta):
				_ai_shoot_cd = AI_SHOOT_COOLDOWN
				_ai_carry_sampling = false
				_ai_carry_dist = 0.0
				return Vector3.ZERO
	# Approach goal with a slight lateral weave by index — stay outside 6 m.
	var approach := Vector3(goal.x + (float(player_index) - 2.0) * 1.2, 0.0, goal.z)
	approach = _keep_outfield_legal(approach)
	return _steer_toward(approach) * AI_ATTACK_SPEED_SCALE


## Soft pass to a teammate (used by MatchController + Away AI).
## Optional `aim_hint` = face / mouse direction; light cone assist blends toward target.
func try_pass_to(
	target: Player,
	ball: Ball,
	impulse: float = -1.0,
	aim_hint: Vector3 = Vector3.ZERO
) -> bool:
	if target == null or not has_ball or ball == null or ball.carrier != self:
		return false
	var hint := aim_hint
	if hint.length_squared() < 0.01:
		hint = (target.global_position - global_position)
		hint.y = 0.0
		if hint.length_squared() < 0.01:
			hint = face_direction()
	var built := PassCraft.build_pass(self, target, hint, impulse)
	if built.is_empty():
		return false
	var meta := {
		"pass": true,
		"charge": 0.3,
		"ai": ai_enabled and not controlled,
		"pass_target": target,
	}
	return try_shoot(built["aim"], built["impulse"], ball, built["loft"], meta)


func _ai_under_pressure() -> bool:
	# Opponents live under the sibling team root (Home/Away).
	var parent_n := get_parent()
	if parent_n == null:
		return false
	var match_root := parent_n.get_parent()
	if match_root == null:
		match_root = parent_n
	for team_root in match_root.get_children():
		if not (team_root is Node):
			continue
		for sibling in team_root.get_children():
			if sibling == self or not (sibling is Player):
				continue
			var other := sibling as Player
			if other.team_id == team_id or other.is_goalkeeper or other.match_frozen:
				continue
			if global_position.distance_to(other.global_position) <= AI_PRESSURE_RANGE:
				return true
	return false


func _ai_pass_target() -> Player:
	var parent_n := get_parent()
	if parent_n == null:
		return null
	var roster: Array = []
	for sibling in parent_n.get_children():
		if sibling is Player:
			roster.append(sibling)
	var face := face_direction()
	face.y = 0.0
	if face.length_squared() < 0.01:
		face = Vector3(0.0, 0.0, 1.0 if team_id == 0 else -1.0)
	else:
		face = face.normalized()
	var best := PassCraft.best_in_cone(self, roster, face, team_id)
	return best as Player


func _ai_try_pass(target: Player) -> bool:
	if match_ball == null or target == null:
		return false
	var face := face_direction()
	if try_pass_to(target, match_ball, -1.0, face):
		_ai_pass_cd = AI_PASS_COOLDOWN
		_ai_shoot_cd = 0.45
		_ai_carry_sampling = false
		_ai_carry_dist = 0.0
		return true
	return false


## Reliable catch when a teammate pass is arriving nearby (Area enter can miss at speed).
func _try_sticky_pass_catch() -> void:
	if has_ball or match_frozen or _pickup_block > 0.0 or match_ball == null:
		return
	if match_ball.carrier != null or not match_ball.is_pass_in_flight():
		return
	var intended := match_ball.pass_intended_receiver()
	# Intended receiver gets sticky catch; other teammates still get a slightly tighter window.
	var sticky := PassCraft.CATCH_STICKY_RADIUS
	if intended != null and intended != self:
		sticky *= 0.85
	elif intended == self:
		sticky *= 1.12
	# Measure from chest height — feet-origin distance alone is already ~1.1 m vertically.
	var catch_at := global_position + Vector3(0.0, 1.05, 0.0)
	var to_ball := match_ball.global_position - catch_at
	var planar := Vector3(to_ball.x, 0.0, to_ball.z)
	if planar.length() > sticky or absf(to_ball.y) > 1.35:
		return
	# Prefer balls still approaching the catcher (planar).
	if match_ball.linear_velocity.length() > 1.0 and planar.length_squared() > 0.01:
		var approach := match_ball.linear_velocity.normalized().dot(planar.normalized())
		if approach < PassCraft.CATCH_APPROACH_DOT:
			return
	# Teammate passes only — don't sticky-steal opponent shots labeled as pass.
	var shooter: Variant = match_ball.last_shot_meta.get("shooter", null)
	if shooter != null and is_instance_valid(shooter) and shooter is Player:
		if (shooter as Player).team_id != team_id:
			return
	if match_ball.try_pickup(self):
		has_ball = true
		_ai_carry_dist = 0.0
		_ai_carry_sampling = false
		possession_changed.emit(true)


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


func _on_save_body_entered(body: Node3D) -> void:
	if not is_goalkeeper or match_frozen or has_ball:
		return
	if not (body is Ball):
		return
	var ball := body as Ball
	if ball.carrier != null:
		return
	# Only contest free balls that aren't our own throw.
	if ball._last_carrier == self:
		return
	var approaching := true
	if ball.linear_velocity.length() > 1.0:
		var to_gk := global_position - ball.global_position
		approaching = ball.linear_velocity.dot(to_gk) > 0.0
	if not approaching and not diving:
		return
	_contest_ball(ball, true)


func _on_block_body_entered(body: Node3D) -> void:
	if is_goalkeeper or match_frozen or has_ball or not block_ready:
		return
	if not (body is Ball):
		return
	var ball := body as Ball
	if ball.carrier != null:
		return
	if ball._last_carrier != null and ball._last_carrier.team_id == team_id:
		return
	# Fresh shot window (~1.1s) or fast ball.
	var age_ok := true
	if ball.last_shot_meta.has("time_msec"):
		age_ok = Time.get_ticks_msec() - int(ball.last_shot_meta["time_msec"]) < 1100
	if not age_ok and ball.linear_velocity.length() < 7.0:
		return
	_contest_ball(ball, false)


func _contest_ball(ball: Ball, is_save: bool) -> void:
	var vel := ball.linear_velocity
	var speed := vel.length()
	var success := diving or block_ready or is_save
	if speed < 2.0 and not diving:
		# Soft gather — try pickup.
		if ball.try_pickup(self):
			has_ball = true
			possession_changed.emit(true)
			block_attempted.emit(self, ball, true)
		return
	# Deflect: kill most forward speed, push outward from defender.
	var away := ball.global_position - global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = face_direction()
		away.y = 0.0
	away = away.normalized()
	# Saves kill more pace than outfield tips — leave rebounds playable.
	var deflect_speed := clampf(speed * (0.42 if is_save else 0.55), 4.0, 12.0)
	var up := 2.4 if is_save else 1.6
	ball.linear_velocity = away * deflect_speed + Vector3(0.0, up, 0.0)
	ball.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0), randf_range(-8.0, 8.0))
	block_attempted.emit(self, ball, success)
	# Short cooldown so one contact doesn't spam.
	if is_goalkeeper:
		_pickup_block = 0.12
	else:
		_block_timer = 0.08
		block_ready = false


func _ensure_craft_nodes() -> void:
	# Procedural arm boxes + contest areas — keeps player.tscn primitive-only.
	_arm_l = get_node_or_null("ArmL") as MeshInstance3D
	_arm_r = get_node_or_null("ArmR") as MeshInstance3D
	if _arm_l == null:
		_arm_l = _make_arm("ArmL", Vector3(-0.55, 1.15, 0.0))
	if _arm_r == null:
		_arm_r = _make_arm("ArmR", Vector3(0.55, 1.15, 0.0))

	_save_area = get_node_or_null("SaveArea") as Area3D
	if _save_area == null and is_goalkeeper:
		_save_area = Area3D.new()
		_save_area.name = "SaveArea"
		_save_area.collision_layer = 0
		_save_area.collision_mask = 4
		_save_area.monitoring = true
		_save_area.monitorable = false
		var save_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.6, 1.1)
		save_shape.shape = box
		save_shape.position = Vector3(0.0, 1.0, 0.15)
		_save_area.add_child(save_shape)
		add_child(_save_area)

	_block_area = get_node_or_null("BlockArea") as Area3D
	if _block_area == null and not is_goalkeeper:
		_block_area = Area3D.new()
		_block_area.name = "BlockArea"
		_block_area.collision_layer = 0
		_block_area.collision_mask = 4
		_block_area.monitoring = true
		_block_area.monitorable = false
		var block_shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.95
		block_shape.shape = sphere
		block_shape.position = Vector3(0.0, 1.25, 0.35)
		_block_area.add_child(block_shape)
		add_child(_block_area)

	# GK reads wider / lower arms at rest; outfield arms hang until block.
	_set_dive_pose(false)


func _make_arm(arm_name: String, pos: Vector3) -> MeshInstance3D:
	var arm := MeshInstance3D.new()
	arm.name = arm_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.55, 0.16, 0.16) if is_goalkeeper else Vector3(0.42, 0.12, 0.12)
	arm.mesh = mesh
	arm.position = pos
	add_child(arm)
	return arm


func _set_dive_pose(active: bool) -> void:
	if _arm_l == null or _arm_r == null:
		return
	if active:
		_arm_l.position = Vector3(-0.85, 0.85, 0.1)
		_arm_r.position = Vector3(0.85, 0.85, 0.1)
		_arm_l.rotation_degrees = Vector3(0, 0, 25)
		_arm_r.rotation_degrees = Vector3(0, 0, -25)
		if _save_area and _save_area.get_child_count() > 0:
			var shape := _save_area.get_child(0) as CollisionShape3D
			if shape and shape.shape is BoxShape3D:
				(shape.shape as BoxShape3D).size = Vector3(2.6, 1.2, 1.4)
	else:
		if is_goalkeeper:
			_arm_l.position = Vector3(-0.7, 1.2, 0.05)
			_arm_r.position = Vector3(0.7, 1.2, 0.05)
		else:
			_arm_l.position = Vector3(-0.45, 1.05, 0.0)
			_arm_r.position = Vector3(0.45, 1.05, 0.0)
		_arm_l.rotation_degrees = Vector3.ZERO
		_arm_r.rotation_degrees = Vector3.ZERO
		if _save_area and _save_area.get_child_count() > 0:
			var shape2 := _save_area.get_child(0) as CollisionShape3D
			if shape2 and shape2.shape is BoxShape3D:
				(shape2.shape as BoxShape3D).size = Vector3(1.8, 1.6, 1.1)


func _update_arm_pose(_delta: float) -> void:
	if diving or _arm_l == null:
		return
	if not is_goalkeeper and block_ready:
		_arm_l.position = Vector3(-0.55, 1.45, 0.25)
		_arm_r.position = Vector3(0.55, 1.45, 0.25)
	elif not is_goalkeeper:
		_arm_l.position = Vector3(-0.45, 1.05, 0.0)
		_arm_r.position = Vector3(0.45, 1.05, 0.0)


func _ensure_kit_nodes() -> void:
	if _kit_nodes_ready:
		return
	_kit_nodes_ready = true
	# White chest stripe + dark socks/shoes so kits read without custom meshes.
	if get_node_or_null("ChestStripe") == null:
		var stripe := MeshInstance3D.new()
		stripe.name = "ChestStripe"
		var box := BoxMesh.new()
		box.size = Vector3(0.72, 0.14, 0.38)
		stripe.mesh = box
		stripe.position = Vector3(0.0, 1.15, 0.02)
		add_child(stripe)
	if get_node_or_null("SockL") == null:
		_make_kit_box("SockL", Vector3(0.16, 0.28, 0.16), Vector3(-0.14, 0.22, 0.0))
		_make_kit_box("SockR", Vector3(0.16, 0.28, 0.16), Vector3(0.14, 0.22, 0.0))
		_make_kit_box("ShoeL", Vector3(0.2, 0.08, 0.32), Vector3(-0.14, 0.04, 0.04))
		_make_kit_box("ShoeR", Vector3(0.2, 0.08, 0.32), Vector3(0.14, 0.04, 0.04))
	# Soft shoulder pads for a slightly more humanoid silhouette (still boxes).
	if get_node_or_null("ShoulderL") == null:
		_make_kit_box("ShoulderL", Vector3(0.22, 0.16, 0.22), Vector3(-0.38, 1.55, 0.0))
		_make_kit_box("ShoulderR", Vector3(0.22, 0.16, 0.22), Vector3(0.38, 1.55, 0.0))


func _make_kit_box(node_name: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	add_child(mi)
	return mi


## Rim highlight so the controlled athlete is obvious among eight capsules.
func set_selection_highlight(active: bool) -> void:
	if _body_mat == null:
		return
	if active:
		_body_mat.emission_enabled = true
		_body_mat.emission = body_color.lightened(0.35)
		_body_mat.emission_energy_multiplier = 0.85
	else:
		_body_mat.emission_enabled = true
		_body_mat.emission = body_color.darkened(0.2)
		_body_mat.emission_energy_multiplier = 0.12 if is_goalkeeper else 0.05


func _apply_team_material() -> void:
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh == null:
		return
	_mesh_base_y = _mesh.position.y
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = body_color
	_body_mat.roughness = 0.48
	_body_mat.metallic = 0.08
	_body_mat.emission_enabled = true
	_body_mat.emission = body_color.darkened(0.25)
	_body_mat.emission_energy_multiplier = 0.12 if is_goalkeeper else 0.05
	_mesh.material_override = _body_mat
	var head := get_node_or_null("Head") as MeshInstance3D
	if head:
		var head_mat := StandardMaterial3D.new()
		# Skin-ish head so the kit/body contrast reads (darker so it isn't washed to white).
		head_mat.albedo_color = Color(0.72, 0.52, 0.38)
		head_mat.roughness = 0.7
		head.material_override = head_mat
	# Arm materials — GK slightly brighter so the line reads.
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = body_color.lightened(0.12 if is_goalkeeper else 0.05)
	arm_mat.roughness = 0.5
	if _arm_l:
		_arm_l.material_override = arm_mat
	if _arm_r:
		_arm_r.material_override = arm_mat

	var stripe := get_node_or_null("ChestStripe") as MeshInstance3D
	if stripe:
		var stripe_mat := StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.95, 0.95, 0.97) if not is_goalkeeper else Color(0.15, 0.15, 0.18)
		stripe_mat.roughness = 0.55
		stripe.material_override = stripe_mat
	var sock_mat := StandardMaterial3D.new()
	sock_mat.albedo_color = body_color.darkened(0.35)
	sock_mat.roughness = 0.7
	for sock_name in ["SockL", "SockR", "ShoulderL", "ShoulderR"]:
		var sock := get_node_or_null(sock_name) as MeshInstance3D
		if sock:
			sock.material_override = sock_mat
	var shoe_mat := StandardMaterial3D.new()
	shoe_mat.albedo_color = Color(0.12, 0.12, 0.14)
	shoe_mat.roughness = 0.6
	for shoe_name in ["ShoeL", "ShoeR"]:
		var shoe := get_node_or_null(shoe_name) as MeshInstance3D
		if shoe:
			shoe.material_override = shoe_mat
	set_selection_highlight(controlled)


func _update_bob(delta: float, speed: float) -> void:
	if _mesh == null:
		return
	if diving:
		_mesh.position.y = lerpf(_mesh.position.y, _mesh_base_y - 0.25, 1.0 - exp(-10.0 * delta))
		return
	if is_on_floor() and speed > 0.5:
		_bob_phase += delta * BOB_SPEED * clampf(speed / SPEED, 0.4, 1.2)
		_mesh.position.y = _mesh_base_y + sin(_bob_phase) * BOB_AMOUNT
	else:
		_mesh.position.y = lerpf(_mesh.position.y, _mesh_base_y, 1.0 - exp(-10.0 * delta))
