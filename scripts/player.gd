extends CharacterBody3D
class_name Player

## Modular primitive outfield / GK (Wave 1 body anchors). Controlled player receives
## match input; AI teammates chase/block. Collision stays a capsule; visuals are
## named parts (hair→feet) so anims and foul regions have real anchors.
## Phase 3: GK dive/track, outfield block volume for contested shots.
## Phase 4: formation-aware off-ball slots (wing / backcourt / pivot-ish).

signal possession_changed(has_ball: bool)
signal dive_started
signal block_attempted(blocker: Player, ball: Ball, success: bool)

## Metres per second. 1 unit = 1 m (see Court.METERS_PER_UNIT).
## ~9.6 m/s is a fast handball sprint; sprint multiplier pushes a short burst.
const SPEED := 9.6
const AIR_CONTROL := 0.58
## Feet rise ~1.2 m (g = 18). Hand finishes near the 2 m crossbar on a jump shot.
const JUMP_VELOCITY := 6.6
const FACE_THRESHOLD := 0.12
const BOB_AMOUNT := 0.03
const BOB_SPEED := 13.0
const IDLE_BREATHE := 0.012
const JOG_LEG_SWING := 0.52
const JOG_ARM_SWING := 0.38
const PICKUP_COOLDOWN := 0.22
## Matches CapsuleShape3D radius in player.tscn — used for soft depenetration.
const BODY_RADIUS := 0.32
## Standing head-top height, metres. Court is 20 m wide, so a player is ~9.5% of the width.
const VISUAL_HEIGHT_M := 1.90
## Soft push when capsules nest (teleport residue / AI stack). Not a hard lock.
const SEPARATION_PUSH := 16.0
## Physics layers: 1=court, 2=player (see project.godot layer_names).
const COLLISION_LAYER_PLAYER := 2
const COLLISION_MASK_COURT_AND_PLAYERS := 1 | 2

## Hair archetype (R1.1) — cycles by player_index; material is never kit color.
enum HairStyle { SHORT = 0, MID = 1, LONG = 2, BALD = 3 }

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
## Phase F: catch settle (brief move penalty) + GK outlet delay.
const CATCH_SETTLE_S := 0.38
const CATCH_SETTLE_SPEED := 0.52
const GK_OUTLET_DELAY_S := 0.42
const GK_OUTLET_COOLDOWN_S := 1.1
## Phase F jump-shot plant slows approach so the takeoff reads.
const JUMP_PLANT_SPEED := 0.28
## Phase G stamina — drain on sprint / jump / shot; recover off-ball / on bench.
const STAMINA_MAX := 100.0
const SPRINT_SPEED_MUL := 1.26
const STAMINA_DRAIN_SPRINT := 16.0
const STAMINA_DRAIN_JUMP := 7.5
const STAMINA_DRAIN_SHOT := 5.5
const STAMINA_RECOVER_MOVE := 7.0
const STAMINA_RECOVER_IDLE := 11.0
const STAMINA_RECOVER_BENCH := 22.0
const STAMINA_LOW := 28.0
const STAMINA_SPEED_FLOOR := 0.78
const STAMINA_ACCURACY_FLOOR := 0.62

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
## Phase D: 2-min exclusion lite — parked at bench, AI off until MatchController restores.
var excluded: bool = false
var exclusion_remaining: float = 0.0
## Phase G: voluntary bench (substitution) — parked sideline, not an exclusion.
var on_bench: bool = false
## Sideline parking slot index (0+) for bench / exclusion spread.
var bench_slot: int = 0
## Phase G stamina 0–100.
var stamina: float = STAMINA_MAX
var sprinting: bool = false
## Phase E: team shape presets (MatchController syncs Home toggles / Away AI).
## Defaults are Formations.AttackShape.WIDE / DefenseShape.FLAT (0) — int avoids
## a Player↔Formations class-name cycle at parse time.
var attack_shape: int = 0
var defense_shape: int = 0
## Phase F jump-shot craft — exposed for ShotCraft.jump_shot_quality duck-typing.
var jump_shot_active: bool = false
var jump_shot_air_s: float = 0.0
var jump_shot_phase: int = 0  # ShotCraft.JumpPhase

var _bob_phase: float = 0.0
var _idle_phase: float = 0.0
var _pickup_block: float = 0.0
var _ai_shoot_cd: float = 0.0
var _ai_pass_cd: float = 0.0
## AI carry distance — pass/shoot before Phase 2 traveling fires.
var _ai_carry_dist: float = 0.0
var _ai_carry_last_xz: Vector3 = Vector3.ZERO
var _ai_carry_sampling: bool = false
## Torso mesh (kit). Kept as MeshInstance3D for older smoke paths.
var _mesh: MeshInstance3D
var _mesh_base_y: float = 1.30
var _dive_timer: float = 0.0
var _dive_cd: float = 0.0
var _block_timer: float = 0.0
var _dive_dir: Vector3 = Vector3.ZERO
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _hand_l: MeshInstance3D
var _hand_r: MeshInstance3D
var _leg_l: Node3D
var _leg_r: Node3D
var _upper_body: Node3D
var _upper_base_y: float = 0.0
var _head: MeshInstance3D
var _hair: MeshInstance3D
var _face_plate: MeshInstance3D
var _head_region: Area3D
var _save_area: Area3D
var _block_area: Area3D
var _body_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _hair_mat: StandardMaterial3D
var _body_parts_ready: bool = false
## Optional legacy sit mesh — hidden; seated pose uses modular legs/torso.
var _bench_visual: Node3D
var _was_seated: bool = false
## Upper-body yaw offset vs feet (pass/shoot windup hook for Wave 2).
var _torso_yaw_offset: float = 0.0
## Phase F catch settle + jump plant + GK outlet.
var _catch_settle_t: float = 0.0
var _js_plant_t: float = 0.0
var _js_was_airborne: bool = false
var _outlet_pending: bool = false
var _outlet_timer: float = 0.0
var _outlet_cd: float = 0.0

@onready var ball_attach: Marker3D = $BallAttach
@onready var pickup_area: Area3D = $PickupArea


func _ready() -> void:
	start_position = global_position
	start_yaw = rotation.y
	# Solid body vs court + other players (mask used to be court-only → free overlap).
	collision_layer = COLLISION_LAYER_PLAYER
	collision_mask = COLLISION_MASK_COURT_AND_PLAYERS
	add_to_group("players")
	_ensure_body_parts()
	_ensure_craft_nodes()
	_apply_team_material()
	_apply_bench_visual()
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
	if _outlet_cd > 0.0:
		_outlet_cd = maxf(0.0, _outlet_cd - delta)
	if _catch_settle_t > 0.0:
		_catch_settle_t = maxf(0.0, _catch_settle_t - delta)
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
	sprinting = false
	if excluded or on_bench:
		# Seated on the sideline bench — no movement / AI.
		wish = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		_tick_stamina(delta, false, false)
	elif match_frozen:
		wish = Vector3.ZERO
		_tick_stamina(delta, false, false)
	elif diving:
		wish = Vector3.ZERO
		_tick_stamina(delta, false, false)
	elif controlled:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# WASD / left stick are camera-relative: forward = into the screen along
		# the current camera facing projected onto the court plane.
		wish = camera_relative_wish(input_dir)
		if is_goalkeeper and Input.is_action_just_pressed("dive"):
			try_dive(_preferred_dive_dir(wish))
		# Phase G sprint (Shift / Back) — drains stamina while moving.
		sprinting = (
			Input.is_action_pressed("sprint")
			and wish.length_squared() > 0.04
			and stamina > 0.5
			and not is_goalkeeper
		)
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
	if sprinting:
		target_speed *= SPRINT_SPEED_MUL
	# Catch settle + jump plant + low stamina briefly softens speed.
	target_speed *= _move_speed_mul()
	# Snappy ground response; softer air control for jump-shot steering.
	if not diving and _js_plant_t <= 0.0 and not on_bench and not excluded:
		var desired := wish * target_speed
		var rate := 18.0 if is_on_floor() else (18.0 * AIR_CONTROL)
		var blend := 1.0 - exp(-rate * delta)
		velocity.x = lerpf(velocity.x, desired.x, blend)
		velocity.z = lerpf(velocity.z, desired.z, blend)
	elif _js_plant_t > 0.0 and not diving:
		# Plant: bleed planar speed while feet stay glued.
		velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-22.0 * delta))
		velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-22.0 * delta))

	if (
		controlled
		and not match_frozen
		and not diving
		and not on_bench
		and not excluded
		and Input.is_action_just_pressed("jump")
		and is_on_floor()
	):
		_begin_jump_from_input(wish)

	if not on_bench and not excluded:
		_tick_stamina(delta, sprinting, wish.length_squared() > 0.04)
		_tick_jump_shot_craft(delta)
		_tick_gk_outlet(delta)

	# Soft velocity push clears nested capsules without freezing wish/slide motion.
	_apply_soft_player_separation()
	move_and_slide()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length() > FACE_THRESHOLD and not diving and _js_plant_t <= 0.0:
		var target_yaw := atan2(planar.x, planar.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))

	if on_bench or excluded:
		rotation.y = Court.bench_yaw(team_id)
		if global_position.y < -0.15:
			global_position.y = 0.0
			velocity.y = 0.0
	_update_locomotion_anim(delta, planar.length())
	_update_arm_pose(delta)
	_apply_torso_yaw(delta)
	_apply_bench_visual()
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
	_outlet_pending = false
	_outlet_timer = 0.0
	drain_stamina(STAMINA_DRAIN_SHOT)
	# Preserve jump-shot craft meta for the release, then clear plant if still grounded.
	if jump_shot_active and not shot_meta.has("jump_shot"):
		shot_meta["jump_shot"] = true
		shot_meta["jump_air_s"] = jump_shot_air_s
		shot_meta["jump_phase"] = jump_shot_phase
	possession_changed.emit(false)
	ball.release_and_shoot(aim_dir, impulse_strength, up_bias, shot_meta)
	return true


func begin_catch_settle() -> void:
	_catch_settle_t = CATCH_SETTLE_S


func is_catch_settling() -> bool:
	return _catch_settle_t > 0.0


func _move_speed_mul() -> float:
	var mul := 1.0
	if _catch_settle_t > 0.0:
		mul *= CATCH_SETTLE_SPEED
	if _js_plant_t > 0.0:
		mul *= JUMP_PLANT_SPEED
	mul *= stamina_speed_mul()
	return mul


func stamina_01() -> float:
	return clampf(stamina / STAMINA_MAX, 0.0, 1.0)


## Soft speed floor when stamina is low (1.0 full → STAMINA_SPEED_FLOOR empty).
func stamina_speed_mul() -> float:
	var t := stamina_01()
	if t >= STAMINA_LOW / STAMINA_MAX:
		return 1.0
	var low_t := clampf(t / (STAMINA_LOW / STAMINA_MAX), 0.0, 1.0)
	return lerpf(STAMINA_SPEED_FLOOR, 1.0, low_t)


## Soft shot/pass accuracy (1.0 full → STAMINA_ACCURACY_FLOOR empty).
func stamina_accuracy_mul() -> float:
	var t := stamina_01()
	if t >= STAMINA_LOW / STAMINA_MAX:
		return 1.0
	var low_t := clampf(t / (STAMINA_LOW / STAMINA_MAX), 0.0, 1.0)
	return lerpf(STAMINA_ACCURACY_FLOOR, 1.0, low_t)


func drain_stamina(amount: float) -> void:
	stamina = clampf(stamina - maxf(0.0, amount), 0.0, STAMINA_MAX)


func _tick_stamina(delta: float, is_sprinting: bool, is_moving: bool) -> void:
	if on_bench or excluded:
		stamina = minf(STAMINA_MAX, stamina + STAMINA_RECOVER_BENCH * delta)
		return
	if is_sprinting:
		drain_stamina(STAMINA_DRAIN_SPRINT * delta)
		return
	# Off-ball / non-sprint recover — slower while carrying so sprint still matters.
	var rate := STAMINA_RECOVER_IDLE if not is_moving else STAMINA_RECOVER_MOVE
	if has_ball:
		rate *= 0.55
	stamina = minf(STAMINA_MAX, stamina + rate * delta)


## Jump with ball + approach → plant → jump-shot craft; otherwise a normal hop.
func _begin_jump_from_input(wish: Vector3) -> void:
	if _js_plant_t > 0.0:
		return
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var approach := planar.length()
	if wish.length_squared() > 0.01:
		approach = maxf(approach, wish.length() * SPEED * 0.55)
	drain_stamina(STAMINA_DRAIN_JUMP)
	var craft := has_ball and approach >= ShotCraft.APPROACH_MIN_SPEED
	if craft:
		jump_shot_active = true
		jump_shot_phase = ShotCraft.JumpPhase.PLANTED
		jump_shot_air_s = 0.0
		_js_plant_t = ShotCraft.PLANT_HOLD_S
		_js_was_airborne = false
	else:
		# Standing hop / no-ball jump — height heuristic only if somehow shooting mid-air.
		if has_ball:
			jump_shot_active = false
			jump_shot_phase = ShotCraft.JumpPhase.NONE
			jump_shot_air_s = 0.0
		velocity.y = JUMP_VELOCITY


func _tick_jump_shot_craft(delta: float) -> void:
	if _js_plant_t > 0.0:
		_js_plant_t = maxf(0.0, _js_plant_t - delta)
		jump_shot_phase = ShotCraft.JumpPhase.PLANTED
		if _js_plant_t <= 0.0 and is_on_floor():
			velocity.y = JUMP_VELOCITY
			_js_was_airborne = false
			jump_shot_air_s = 0.0
			jump_shot_phase = ShotCraft.JumpPhase.AIRBORNE
		return
	if not jump_shot_active:
		if is_on_floor():
			jump_shot_air_s = 0.0
			jump_shot_phase = ShotCraft.JumpPhase.NONE
		return
	if is_on_floor():
		if _js_was_airborne:
			# Landed — craft complete.
			jump_shot_active = false
			jump_shot_phase = ShotCraft.JumpPhase.NONE
			jump_shot_air_s = 0.0
			_js_was_airborne = false
		return
	_js_was_airborne = true
	jump_shot_air_s += delta
	var q := ShotCraft.jump_shot_window_quality(self, jump_shot_air_s)
	if q == 1:
		jump_shot_phase = ShotCraft.JumpPhase.WINDOW
	elif jump_shot_air_s < ShotCraft.WINDOW_OPEN_S:
		jump_shot_phase = ShotCraft.JumpPhase.AIRBORNE
	else:
		jump_shot_phase = ShotCraft.JumpPhase.WINDOW if q != 2 else ShotCraft.JumpPhase.AIRBORNE


## After a save gather, AI GK outlets to a wing (fast break lite).
func arm_outlet_pass() -> void:
	if not is_goalkeeper:
		return
	_outlet_pending = true
	_outlet_timer = GK_OUTLET_DELAY_S


func _tick_gk_outlet(delta: float) -> void:
	if not is_goalkeeper or not _outlet_pending:
		return
	if not has_ball or match_ball == null or match_ball.carrier != self:
		_outlet_pending = false
		_outlet_timer = 0.0
		return
	if controlled and not ai_enabled:
		# Human GK keeps the ball — outlet is an AI assist after saves.
		return
	_outlet_timer = maxf(0.0, _outlet_timer - delta)
	if _outlet_timer > 0.0 or _outlet_cd > 0.0 or _ai_pass_cd > 0.0:
		return
	var wing := _ai_outlet_wing()
	if wing == null:
		_outlet_pending = false
		return
	var hint := wing.global_position - global_position
	hint.y = 0.0
	if try_pass_to(wing, match_ball, -1.0, hint, PassCraft.PassType.LOB):
		_outlet_pending = false
		_outlet_cd = GK_OUTLET_COOLDOWN_S
		_ai_pass_cd = AI_PASS_COOLDOWN


func _ai_outlet_wing() -> Player:
	var parent_n := get_parent()
	if parent_n == null:
		return null
	var roster: Array = []
	for sibling in parent_n.get_children():
		if sibling is Player:
			roster.append(sibling)
	var best := PassCraft.best_outlet_wing(self, roster, team_id)
	return best as Player


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
	excluded = false
	exclusion_remaining = 0.0
	# on_bench / bench_slot preserved — MatchController owns sub state across resets.
	if on_bench:
		global_position = Court.bench_marker(team_id, maxi(0, bench_slot))
	stamina = STAMINA_MAX
	sprinting = false
	visible = true
	_catch_settle_t = 0.0
	_js_plant_t = 0.0
	_js_was_airborne = false
	jump_shot_active = false
	jump_shot_air_s = 0.0
	jump_shot_phase = ShotCraft.JumpPhase.NONE
	_outlet_pending = false
	_outlet_timer = 0.0
	_outlet_cd = 0.0
	_set_dive_pose(false)
	_torso_yaw_offset = 0.0
	if on_bench or excluded:
		_pose_seated()
		_was_seated = true
	else:
		_pose_standing_rest()
		_was_seated = false


## Light XZ velocity bias when another player capsule overlaps this one.
func _apply_soft_player_separation() -> void:
	if on_bench or excluded:
		return
	var min_sep := BODY_RADIUS * 2.0
	for node in get_tree().get_nodes_in_group("players"):
		if node == self or not (node is Player):
			continue
		var other := node as Player
		if other.on_bench or other.excluded:
			continue
		var offset := Vector3(
			global_position.x - other.global_position.x,
			0.0,
			global_position.z - other.global_position.z
		)
		var dist := offset.length()
		if dist >= min_sep:
			continue
		var dir := offset
		if dist < 0.001:
			# Identical spots — pick a stable horizontal axis from instance ids.
			dir = Vector3(1.0 if get_instance_id() > other.get_instance_id() else -1.0, 0.0, 0.0)
			dist = 0.001
		else:
			dir /= dist
		var penetration := min_sep - dist
		velocity.x += dir.x * penetration * SEPARATION_PUSH
		velocity.z += dir.z * penetration * SEPARATION_PUSH


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
	if on_bench or excluded:
		return Vector3.ZERO
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
	# Holding after a save: stay put while outlet arms / fires.
	if has_ball and match_ball != null and match_ball.carrier == self:
		return Vector3.ZERO

	var ball_pos := match_ball.global_position
	var home := start_position
	var toward_court := 1.0 if team_id == 0 else -1.0
	var threat_pos := ball_pos
	if match_ball.carrier != null and match_ball.carrier.team_id != team_id:
		threat_pos = match_ball.carrier.global_position
	# Phase F angle-cut: stand on shooter→goal line with near-post bias.
	var target := _gk_angle_cut_target(threat_pos, home, toward_court)
	var gap := absf(ball_pos.z - home.z)

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


## Cut the angle: advance off the line toward the threat, bias near post.
func _gk_angle_cut_target(threat_pos: Vector3, home: Vector3, toward_court: float) -> Vector3:
	var goal_z := home.z
	var goal_center := Vector3(0.0, 0.0, goal_z)
	var gap := absf(threat_pos.z - goal_z)
	var depth_frac := clampf(1.0 - gap / 16.0, 0.0, 1.0)
	# Near post = post on the shooter's side; center threats keep middle.
	var near_post_x := 0.0
	if absf(threat_pos.x) > 0.65:
		near_post_x = signf(threat_pos.x) * (Court.GOAL_WIDTH * 0.5)
	# Interpolate along shooter → goal, then bias X toward near post.
	var cut := threat_pos.lerp(goal_center, lerpf(0.72, 0.88, depth_frac))
	cut.x = lerpf(cut.x, near_post_x, 0.38)
	cut.x = clampf(cut.x, -3.4, 3.4)
	# Step off the goal line as the threat closes (angle cut).
	var step := lerpf(0.55, 2.35, depth_frac)
	cut.z = goal_z + toward_court * step
	if team_id == 0:
		cut.z = clampf(cut.z, -18.5, -14.0)
	else:
		cut.z = clampf(cut.z, 14.0, 18.5)
	cut.y = 0.0
	return cut


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
			if mate.is_goalkeeper or mate.match_frozen or mate.excluded or mate.on_bench:
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
	# Crash: ball-side wing may seal a light screen between pivot and nearest defender.
	var ball_pos := carrier.global_position
	var pivot := _ai_teammate_pivot()
	var screen_def := _ai_nearest_opponent() if attack_shape == Formations.AttackShape.CRASH else null
	var slot := Formations.show_for_pass_slot(self, ball_pos, pivot, screen_def)
	var to_carrier := slot.distance_to(Vector3(ball_pos.x, 0.0, ball_pos.z))
	if to_carrier < 2.4:
		# Don't stack on the ball carrier — slide wider.
		var role := Formations.role_for(self)
		var side := 1.0 if role == Formations.Role.RIGHT_WING or role == Formations.Role.RIGHT_BACK else -1.0
		if role == Formations.Role.CENTER_BACK or role == Formations.Role.PIVOT:
			side = 0.0
			slot.z += (-1.0 if team_id == 0 else 1.0) * 1.5
		slot.x += side * 2.2
	slot = _keep_outfield_legal(slot)
	# Slightly sharper close-out when showing so the lane arrives in time.
	return _steer_toward(slot) * minf(AI_ATTACK_SPEED_SCALE * 1.08, 1.0)


func _ai_teammate_pivot() -> Player:
	var parent_n := get_parent()
	if parent_n == null:
		return null
	var pivot: Player = null
	var cb: Player = null
	for sibling in parent_n.get_children():
		if sibling == self or not (sibling is Player):
			continue
		var mate := sibling as Player
		if mate.is_goalkeeper or mate.excluded or mate.on_bench:
			continue
		var role := Formations.role_for(mate)
		if role == Formations.Role.PIVOT:
			pivot = mate
		elif role == Formations.Role.CENTER_BACK:
			cb = mate
	return pivot if pivot else cb


func _ai_nearest_opponent() -> Player:
	var best: Player = null
	var best_d := INF
	var my_parent := get_parent()
	if my_parent == null or my_parent.get_parent() == null:
		return null
	# Home/Away roots are siblings under MatchController.
	for team_root in my_parent.get_parent().get_children():
		if team_root == my_parent:
			continue
		for child in team_root.get_children():
			if not (child is Player):
				continue
			var opp := child as Player
			if opp.team_id == team_id or opp.is_goalkeeper or opp.excluded or opp.on_bench:
				continue
			var d := global_position.distance_squared_to(opp.global_position)
			if d < best_d:
				best_d = d
				best = opp
	return best


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
## `pass_type`: PassCraft.PassType FLAT / BOUNCE / LOB.
func try_pass_to(
	target: Player,
	ball: Ball,
	impulse: float = -1.0,
	aim_hint: Vector3 = Vector3.ZERO,
	pass_type: int = PassCraft.PassType.FLAT
) -> bool:
	if target == null or not has_ball or ball == null or ball.carrier != self:
		return false
	var hint := aim_hint
	if hint.length_squared() < 0.01:
		hint = (target.global_position - global_position)
		hint.y = 0.0
		if hint.length_squared() < 0.01:
			hint = face_direction()
	var built := PassCraft.build_pass(self, target, hint, impulse, pass_type)
	if built.is_empty():
		return false
	var meta := {
		"pass": true,
		"charge": 0.3,
		"ai": ai_enabled and not controlled,
		"pass_target": target,
		"pass_type": int(built.get("pass_type", pass_type)),
	}
	if pass_type == PassCraft.PassType.BOUNCE and built.has("floor_point"):
		meta["floor_point"] = built["floor_point"]
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
	# Bounce passes aren't catchable until after the floor hop.
	if (
		match_ball.pass_type() == PassCraft.PassType.BOUNCE
		and not bool(match_ball.last_shot_meta.get("bounce_hopped", false))
	):
		return
	var intended := match_ball.pass_intended_receiver()
	# Intended receiver gets sticky catch; other teammates still get a slightly tighter window.
	var sticky := PassCraft.CATCH_STICKY_RADIUS
	if intended != null and intended != self:
		sticky *= 0.85
	elif intended == self:
		sticky *= 1.12
	var pass_type := match_ball.pass_type()
	var y_slack := 1.35
	if pass_type == PassCraft.PassType.LOB:
		y_slack = PassCraft.LOB_CATCH_Y
		sticky *= PassCraft.LOB_CATCH_STICKY_SCALE
	elif pass_type == PassCraft.PassType.BOUNCE:
		y_slack = PassCraft.BOUNCE_CATCH_Y
	# Measure from chest height — feet-origin distance alone is already ~1.1 m vertically.
	var catch_at := global_position + Vector3(0.0, 1.05, 0.0)
	var to_ball := match_ball.global_position - catch_at
	var planar := Vector3(to_ball.x, 0.0, to_ball.z)
	if planar.length() > sticky or absf(to_ball.y) > y_slack:
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
		begin_catch_settle()
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
		# Bounce pass: wait for floor hop before Area pickup.
		if (
			ball.is_pass_in_flight()
			and ball.pass_type() == PassCraft.PassType.BOUNCE
			and not bool(ball.last_shot_meta.get("bounce_hopped", false))
		):
			return
		if ball.try_pickup(self):
			has_ball = true
			_ai_carry_dist = 0.0
			_ai_carry_sampling = false
			begin_catch_settle()
			if is_goalkeeper and _should_arm_outlet_from_ball(ball):
				arm_outlet_pass()
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
			begin_catch_settle()
			if is_save:
				arm_outlet_pass()
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
	# Stronger saves (dive) can gather instead of tip when the ball is slow enough.
	if is_save and (diving or speed < 6.5):
		if ball.try_pickup(self):
			has_ball = true
			begin_catch_settle()
			arm_outlet_pass()
			possession_changed.emit(true)
			block_attempted.emit(self, ball, true)
			return
	ball.linear_velocity = away * deflect_speed + Vector3(0.0, up, 0.0)
	ball.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0), randf_range(-8.0, 8.0))
	block_attempted.emit(self, ball, success)
	# Short cooldown so one contact doesn't spam.
	if is_goalkeeper:
		_pickup_block = 0.12
	else:
		_block_timer = 0.08
		block_ready = false


func _should_arm_outlet_from_ball(ball: Ball) -> bool:
	if ball == null:
		return false
	# Arm outlet when the last touch was an opponent shot / free ball into the area.
	var shooter: Variant = ball.last_shot_meta.get("shooter", null)
	if shooter != null and is_instance_valid(shooter) and shooter is Player:
		return (shooter as Player).team_id != team_id
	# Free ball with no shooter meta — still a distribution chance.
	return ball._last_carrier == null or ball._last_carrier.team_id != team_id


## Hair archetype for this roster slot (short / mid / long / bald).
func hair_style() -> int:
	return abs(player_index) % 4


## Authored standing head-top height in metres (ignores sit/bob offsets).
func standing_head_top() -> float:
	# Rest pose: Head local y=1.78 under UpperBody at y=0, box height 0.24 → top 1.90.
	const HEAD_REST_Y := 1.78
	const HEAD_SIZE_Y := 0.24
	var head := _head if _head else find_child("Head", true, false) as MeshInstance3D
	if head != null and head.mesh is BoxMesh:
		var box := head.mesh as BoxMesh
		# Prefer live mesh size, but always evaluate at rest UpperBody (y=0).
		return HEAD_REST_Y + box.size.y * 0.5
	return HEAD_REST_Y + HEAD_SIZE_Y * 0.5


## Head/neck contact region for future foul ladder (R3.5 / R3.6).
func get_head_region() -> Area3D:
	return _head_region


## Independent upper-body yaw vs feet (Wave 2 pass/shoot windup).
func set_torso_yaw_offset(yaw: float) -> void:
	_torso_yaw_offset = yaw


func get_torso_yaw_offset() -> float:
	return _torso_yaw_offset


func _ensure_body_parts() -> void:
	if _body_parts_ready:
		_cache_body_refs()
		return
	_body_parts_ready = true

	# Upper body yaws independently of feet for pass/shoot windup (R1.3).
	_upper_body = get_node_or_null("UpperBody") as Node3D
	if _upper_body == null:
		_upper_body = Node3D.new()
		_upper_body.name = "UpperBody"
		add_child(_upper_body)
	_upper_base_y = 0.0
	_upper_body.position = Vector3.ZERO

	# Torso = kit color mass (was a full-body capsule).
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "MeshInstance3D"
		add_child(_mesh)
	if _mesh.get_parent() != _upper_body:
		_mesh.reparent(_upper_body)
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.42, 0.56, 0.26)
	_mesh.mesh = torso_mesh
	_mesh.position = Vector3(0.0, 1.30, 0.0)
	_mesh_base_y = _mesh.position.y

	_ensure_box_child(_upper_body, "ChestStripe", Vector3(0.44, 0.10, 0.28), Vector3(0.0, 1.28, 0.06))
	_ensure_box_child(_upper_body, "ShoulderL", Vector3(0.16, 0.14, 0.16), Vector3(-0.30, 1.54, 0.0))
	_ensure_box_child(_upper_body, "ShoulderR", Vector3(0.16, 0.14, 0.16), Vector3(0.30, 1.54, 0.0))

	# Head / face / hair — head top at VISUAL_HEIGHT_M (1.90).
	_head = _ensure_box_child(_upper_body, "Head", Vector3(0.24, 0.24, 0.24), Vector3(0.0, 1.78, 0.0))
	_face_plate = _ensure_box_child(_upper_body, "FacePlate", Vector3(0.18, 0.10, 0.04), Vector3(0.0, 1.78, 0.14))
	_hair = get_node_or_null("Hair") as MeshInstance3D
	if _hair == null:
		_hair = _upper_body.get_node_or_null("Hair") as MeshInstance3D
	if _hair == null:
		_hair = MeshInstance3D.new()
		_hair.name = "Hair"
		_upper_body.add_child(_hair)
	elif _hair.get_parent() != _upper_body:
		_hair.reparent(_upper_body)
	_apply_hair_style_mesh()

	_ensure_head_region()
	_ensure_arms_and_hands()
	_ensure_legs_and_feet()
	_wire_ball_attach_to_hand()

	# Legacy BenchSit kept hidden — seated pose uses the same modular parts.
	_bench_visual = get_node_or_null("BenchSit") as Node3D
	if _bench_visual == null:
		_bench_visual = Node3D.new()
		_bench_visual.name = "BenchSit"
		add_child(_bench_visual)
	_bench_visual.visible = false
	_cache_body_refs()


func _cache_body_refs() -> void:
	_upper_body = get_node_or_null("UpperBody") as Node3D
	_mesh = _upper_body.get_node_or_null("MeshInstance3D") as MeshInstance3D if _upper_body else get_node_or_null("MeshInstance3D") as MeshInstance3D
	_head = _upper_body.get_node_or_null("Head") as MeshInstance3D if _upper_body else get_node_or_null("Head") as MeshInstance3D
	_hair = _upper_body.get_node_or_null("Hair") as MeshInstance3D if _upper_body else null
	_face_plate = _upper_body.get_node_or_null("FacePlate") as MeshInstance3D if _upper_body else null
	_arm_l = _upper_body.get_node_or_null("ArmL") as MeshInstance3D if _upper_body else null
	_arm_r = _upper_body.get_node_or_null("ArmR") as MeshInstance3D if _upper_body else null
	_hand_l = _upper_body.get_node_or_null("HandL") as MeshInstance3D if _upper_body else null
	_hand_r = _upper_body.get_node_or_null("HandR") as MeshInstance3D if _upper_body else null
	_leg_l = get_node_or_null("LegL") as Node3D
	_leg_r = get_node_or_null("LegR") as Node3D
	_head_region = find_child("HeadRegion", true, false) as Area3D
	if _mesh:
		_mesh_base_y = _mesh.position.y
	if ball_attach == null:
		ball_attach = find_child("BallAttach", true, false) as Marker3D


func _ensure_box_child(parent: Node3D, node_name: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := parent.get_node_or_null(node_name) as MeshInstance3D
	if mi == null:
		mi = get_node_or_null(node_name) as MeshInstance3D
		if mi != null and mi.get_parent() != parent:
			mi.reparent(parent)
		elif mi == null:
			mi = MeshInstance3D.new()
			mi.name = node_name
			parent.add_child(mi)
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.rotation = Vector3.ZERO
	return mi


func _apply_hair_style_mesh() -> void:
	if _hair == null:
		return
	var style := hair_style()
	var box := BoxMesh.new()
	if style == HairStyle.BALD:
		# Keep a tiny mesh so the renderer never sees a null MeshInstance.
		box.size = Vector3(0.02, 0.02, 0.02)
		_hair.mesh = box
		_hair.position = Vector3(0.0, 1.90, 0.0)
		_hair.visible = false
		return
	_hair.visible = true
	match style:
		HairStyle.SHORT:
			box.size = Vector3(0.26, 0.08, 0.26)
			_hair.position = Vector3(0.0, 1.92, -0.01)
		HairStyle.MID:
			box.size = Vector3(0.28, 0.14, 0.28)
			_hair.position = Vector3(0.0, 1.94, -0.02)
		HairStyle.LONG:
			box.size = Vector3(0.26, 0.28, 0.22)
			_hair.position = Vector3(0.0, 1.88, -0.08)
		_:
			box.size = Vector3(0.26, 0.08, 0.26)
			_hair.position = Vector3(0.0, 1.92, -0.01)
	_hair.mesh = box


func _ensure_head_region() -> void:
	_head_region = find_child("HeadRegion", true, false) as Area3D
	if _head_region == null:
		_head_region = Area3D.new()
		_head_region.name = "HeadRegion"
		_upper_body.add_child(_head_region)
	elif _head_region.get_parent() != _upper_body:
		_head_region.reparent(_upper_body)
	_head_region.position = Vector3(0.0, 1.72, 0.0)
	_head_region.collision_layer = 0
	_head_region.collision_mask = 0
	_head_region.monitoring = false
	_head_region.monitorable = true
	_head_region.set_meta("body_region", "head")
	_head_region.set_meta("foul_region", "head_neck")
	var shape_node := _head_region.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		_head_region.add_child(shape_node)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	shape_node.shape = sphere


func _ensure_arms_and_hands() -> void:
	var arm_size := Vector3(0.55, 0.14, 0.14) if is_goalkeeper else Vector3(0.40, 0.11, 0.11)
	_arm_l = _ensure_box_child(
		_upper_body, "ArmL", arm_size,
		Vector3(-0.48, 1.28, 0.02) if is_goalkeeper else Vector3(-0.40, 1.22, 0.02)
	)
	_arm_r = _ensure_box_child(
		_upper_body, "ArmR", arm_size,
		Vector3(0.48, 1.28, 0.02) if is_goalkeeper else Vector3(0.40, 1.22, 0.02)
	)
	_hand_l = _ensure_box_child(
		_upper_body, "HandL", Vector3(0.10, 0.08, 0.12),
		Vector3(-0.70, 1.18, 0.06) if is_goalkeeper else Vector3(-0.58, 1.12, 0.08)
	)
	_hand_r = _ensure_box_child(
		_upper_body, "HandR", Vector3(0.10, 0.08, 0.12),
		Vector3(0.70, 1.18, 0.06) if is_goalkeeper else Vector3(0.58, 1.12, 0.08)
	)
	_hand_l.set_meta("body_region", "hand")
	_hand_r.set_meta("body_region", "hand")
	_hand_r.set_meta("ball_attach_hand", true)


func _wire_ball_attach_to_hand() -> void:
	# Ball sits on the right hand while possessed (R1.5) — not mid-capsule.
	if ball_attach == null:
		ball_attach = get_node_or_null("BallAttach") as Marker3D
	if ball_attach == null:
		ball_attach = Marker3D.new()
		ball_attach.name = "BallAttach"
		add_child(ball_attach)
	if _hand_r == null:
		return
	if ball_attach.get_parent() != _hand_r:
		ball_attach.reparent(_hand_r)
	# Slight forward/out offset from hand center so the ball reads in the palm.
	ball_attach.position = Vector3(0.02, 0.02, 0.10)


func _ensure_legs_and_feet() -> void:
	_leg_l = _ensure_leg("LegL", -0.13)
	_leg_r = _ensure_leg("LegR", 0.13)


func _ensure_leg(leg_name: String, x: float) -> Node3D:
	var leg := get_node_or_null(leg_name) as Node3D
	if leg == null:
		leg = Node3D.new()
		leg.name = leg_name
		add_child(leg)
	# Hip pivot — thighs hang down; feet end near y = 0.
	leg.position = Vector3(x, 0.95, 0.0)
	leg.rotation = Vector3.ZERO
	var side := "L" if x < 0.0 else "R"
	_ensure_box_child(leg, "Thigh%s" % side, Vector3(0.15, 0.40, 0.15), Vector3(0.0, -0.20, 0.0))
	var shin := leg.get_node_or_null("Shin%s" % side) as Node3D
	if shin == null:
		shin = Node3D.new()
		shin.name = "Shin%s" % side
		leg.add_child(shin)
	shin.position = Vector3(0.0, -0.42, 0.0)
	shin.rotation = Vector3.ZERO
	# Keep Sock*/Shoe* names for kit tinting.
	_ensure_box_child(shin, "Sock%s" % side, Vector3(0.13, 0.38, 0.13), Vector3(0.0, -0.16, 0.0))
	# Sole ≈ y=0: shin origin world y≈0.53 → shoe center 0.035 above floor.
	_ensure_box_child(shin, "Shoe%s" % side, Vector3(0.16, 0.07, 0.28), Vector3(0.0, -0.495, 0.05))
	# Alias Foot* for requirement naming / smoke (sole marker).
	if leg.get_node_or_null("Foot%s" % side) == null:
		var foot_alias := Node3D.new()
		foot_alias.name = "Foot%s" % side
		foot_alias.position = Vector3(0.0, -0.95, 0.05)
		leg.add_child(foot_alias)
	else:
		(leg.get_node("Foot%s" % side) as Node3D).position = Vector3(0.0, -0.95, 0.05)
	return leg


func _ensure_craft_nodes() -> void:
	# Contest areas — arms/hands come from _ensure_body_parts.
	_cache_body_refs()

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

	_set_dive_pose(false)


func _set_dive_pose(active: bool) -> void:
	if _arm_l == null or _arm_r == null:
		return
	if active:
		_arm_l.position = Vector3(-0.85, 0.85, 0.1)
		_arm_r.position = Vector3(0.85, 0.85, 0.1)
		_arm_l.rotation_degrees = Vector3(0, 0, 25)
		_arm_r.rotation_degrees = Vector3(0, 0, -25)
		if _hand_l and _hand_r:
			_hand_l.position = Vector3(-1.05, 0.78, 0.18)
			_hand_r.position = Vector3(1.05, 0.78, 0.18)
		if _save_area and _save_area.get_child_count() > 0:
			var shape := _save_area.get_child(0) as CollisionShape3D
			if shape and shape.shape is BoxShape3D:
				(shape.shape as BoxShape3D).size = Vector3(2.6, 1.2, 1.4)
	else:
		_pose_arms_rest()
		if _save_area and _save_area.get_child_count() > 0:
			var shape2 := _save_area.get_child(0) as CollisionShape3D
			if shape2 and shape2.shape is BoxShape3D:
				(shape2.shape as BoxShape3D).size = Vector3(1.8, 1.6, 1.1)


func _pose_arms_rest() -> void:
	if _arm_l == null or _arm_r == null:
		return
	if is_goalkeeper:
		_arm_l.position = Vector3(-0.48, 1.28, 0.02)
		_arm_r.position = Vector3(0.48, 1.28, 0.02)
		if _hand_l and _hand_r:
			_hand_l.position = Vector3(-0.70, 1.18, 0.06)
			_hand_r.position = Vector3(0.70, 1.18, 0.06)
	else:
		_arm_l.position = Vector3(-0.40, 1.22, 0.02)
		_arm_r.position = Vector3(0.40, 1.22, 0.02)
		if _hand_l and _hand_r:
			_hand_l.position = Vector3(-0.58, 1.12, 0.08)
			_hand_r.position = Vector3(0.58, 1.12, 0.08)
	_arm_l.rotation_degrees = Vector3.ZERO
	_arm_r.rotation_degrees = Vector3.ZERO


func _update_arm_pose(_delta: float) -> void:
	if diving or _arm_l == null or on_bench or excluded:
		return
	if not is_goalkeeper and block_ready:
		_arm_l.position = Vector3(-0.50, 1.48, 0.22)
		_arm_r.position = Vector3(0.50, 1.48, 0.22)
		_arm_l.rotation_degrees = Vector3(-35, 0, 0)
		_arm_r.rotation_degrees = Vector3(-35, 0, 0)
		if _hand_l and _hand_r:
			_hand_l.position = Vector3(-0.55, 1.62, 0.38)
			_hand_r.position = Vector3(0.55, 1.62, 0.38)
	elif not is_goalkeeper and not block_ready:
		# Jog swing may own rotation; keep rest positions when idle path resets.
		pass


## Rim highlight so the controlled athlete is obvious among teammates.
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
	_cache_body_refs()
	if _mesh == null:
		return
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = body_color
	_body_mat.roughness = 0.48
	_body_mat.metallic = 0.08
	_body_mat.emission_enabled = true
	_body_mat.emission = body_color.darkened(0.25)
	_body_mat.emission_energy_multiplier = 0.12 if is_goalkeeper else 0.05
	_mesh.material_override = _body_mat

	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = Color(0.72, 0.52, 0.38)
	_skin_mat.roughness = 0.7
	if _head:
		_head.material_override = _skin_mat
	if _face_plate:
		var face_mat := StandardMaterial3D.new()
		# Darker plate so face orientation reads from the 3/4 camera.
		face_mat.albedo_color = Color(0.45, 0.28, 0.20)
		face_mat.roughness = 0.65
		_face_plate.material_override = face_mat
	if _hand_l:
		_hand_l.material_override = _skin_mat
	if _hand_r:
		_hand_r.material_override = _skin_mat

	# Hair uses its own material — never kit color (R1.1).
	_hair_mat = StandardMaterial3D.new()
	var hair_colors := [
		Color(0.12, 0.09, 0.07),
		Color(0.35, 0.22, 0.10),
		Color(0.55, 0.42, 0.22),
		Color(0.18, 0.18, 0.20),
	]
	_hair_mat.albedo_color = hair_colors[abs(player_index) % hair_colors.size()]
	_hair_mat.roughness = 0.85
	if _hair and hair_style() != HairStyle.BALD:
		_hair.material_override = _hair_mat
		_hair.visible = true
	elif _hair:
		_hair.visible = false

	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = body_color.lightened(0.12 if is_goalkeeper else 0.05)
	arm_mat.roughness = 0.5
	if _arm_l:
		_arm_l.material_override = arm_mat
	if _arm_r:
		_arm_r.material_override = arm_mat

	var stripe := _upper_body.get_node_or_null("ChestStripe") as MeshInstance3D if _upper_body else null
	if stripe:
		var stripe_mat := StandardMaterial3D.new()
		stripe_mat.albedo_color = Color(0.95, 0.95, 0.97) if not is_goalkeeper else Color(0.15, 0.15, 0.18)
		stripe_mat.roughness = 0.55
		stripe.material_override = stripe_mat

	var sock_mat := StandardMaterial3D.new()
	sock_mat.albedo_color = body_color.darkened(0.35)
	sock_mat.roughness = 0.7
	for sock_name in ["SockL", "SockR", "ShoulderL", "ShoulderR", "ThighL", "ThighR"]:
		var sock := find_child(sock_name, true, false) as MeshInstance3D
		if sock:
			sock.material_override = sock_mat
	# Thighs use kit (shorts); socks darker — retint thighs to kit.
	for thigh_name in ["ThighL", "ThighR"]:
		var thigh := find_child(thigh_name, true, false) as MeshInstance3D
		if thigh and _body_mat:
			thigh.material_override = _body_mat
	for shoulder_name in ["ShoulderL", "ShoulderR"]:
		var sh := _upper_body.get_node_or_null(shoulder_name) as MeshInstance3D if _upper_body else null
		if sh:
			sh.material_override = sock_mat

	var shoe_mat := StandardMaterial3D.new()
	shoe_mat.albedo_color = Color(0.12, 0.12, 0.14)
	shoe_mat.roughness = 0.6
	for shoe_name in ["ShoeL", "ShoeR"]:
		var shoe := find_child(shoe_name, true, false) as MeshInstance3D
		if shoe:
			shoe.material_override = shoe_mat
	set_selection_highlight(controlled)


func _apply_torso_yaw(delta: float) -> void:
	if _upper_body == null or on_bench or excluded or diving:
		return
	# Soft return toward offset (Wave 2 will drive offset during windup).
	var target := _torso_yaw_offset
	_upper_body.rotation.y = lerp_angle(_upper_body.rotation.y, target, 1.0 - exp(-10.0 * delta))


func _apply_bench_visual() -> void:
	var seated := on_bench or excluded
	# Never show the old duplicate sit mesh — modular body sits itself.
	if _bench_visual:
		_bench_visual.visible = false
	if seated:
		_pose_seated()
		_was_seated = true
	elif _was_seated:
		_pose_standing_rest()
		_was_seated = false


func _pose_standing_rest() -> void:
	if _upper_body:
		_upper_body.position = Vector3(0.0, _upper_base_y, 0.0)
		_upper_body.rotation = Vector3(0.0, _torso_yaw_offset, 0.0)
	if _mesh:
		_mesh.position.y = _mesh_base_y
		_mesh.rotation = Vector3.ZERO
	if _leg_l:
		_leg_l.rotation = Vector3.ZERO
		_leg_l.position = Vector3(-0.13, 0.95, 0.0)
		var shin_l := _leg_l.get_node_or_null("ShinL") as Node3D
		if shin_l:
			shin_l.rotation = Vector3.ZERO
			shin_l.position = Vector3(0.0, -0.42, 0.0)
	if _leg_r:
		_leg_r.rotation = Vector3.ZERO
		_leg_r.position = Vector3(0.13, 0.95, 0.0)
		var shin_r := _leg_r.get_node_or_null("ShinR") as Node3D
		if shin_r:
			shin_r.rotation = Vector3.ZERO
			shin_r.position = Vector3(0.0, -0.42, 0.0)
	_pose_arms_rest()


func _pose_seated() -> void:
	# Seat top ≈ 0.44 m. Hips on the plank; thighs forward; shins down; feet ≈ y=0.
	if _upper_body:
		_upper_body.position = Vector3(0.0, -0.48, 0.06)
		_upper_body.rotation = Vector3(0.08, 0.0, 0.0)
	if _mesh:
		_mesh.rotation = Vector3.ZERO
	if _leg_l:
		_leg_l.position = Vector3(-0.12, 0.48, 0.04)
		_leg_l.rotation = Vector3(-1.15, 0.0, 0.0)  # thighs toward +Z
		var shin_l := _leg_l.get_node_or_null("ShinL") as Node3D
		if shin_l:
			shin_l.position = Vector3(0.0, -0.42, 0.0)
			shin_l.rotation = Vector3(1.35, 0.0, 0.0)  # shins hang down
	if _leg_r:
		_leg_r.position = Vector3(0.12, 0.48, 0.04)
		_leg_r.rotation = Vector3(-1.15, 0.0, 0.0)
		var shin_r := _leg_r.get_node_or_null("ShinR") as Node3D
		if shin_r:
			shin_r.position = Vector3(0.0, -0.42, 0.0)
			shin_r.rotation = Vector3(1.35, 0.0, 0.0)
	if _arm_l and _arm_r:
		_arm_l.position = Vector3(-0.36, 1.10, 0.10)
		_arm_r.position = Vector3(0.36, 1.10, 0.10)
		_arm_l.rotation_degrees = Vector3(-25, 0, 12)
		_arm_r.rotation_degrees = Vector3(-25, 0, -12)
	if _hand_l and _hand_r:
		_hand_l.position = Vector3(-0.40, 0.92, 0.28)
		_hand_r.position = Vector3(0.40, 0.92, 0.28)


func _update_locomotion_anim(delta: float, speed: float) -> void:
	if _mesh == null:
		return
	if on_bench or excluded:
		return
	if diving:
		if _upper_body:
			_upper_body.position.y = lerpf(_upper_body.position.y, _upper_base_y - 0.2, 1.0 - exp(-10.0 * delta))
		return

	var blend := 1.0 - exp(-12.0 * delta)
	# Near-floor counts as grounded so headless / teleport frames still jog.
	var grounded := is_on_floor() or (global_position.y < 0.2 and velocity.y <= 0.8)
	if grounded and speed > 0.8:
		# Slight jog — opposite arm/leg swing (R2.8 lite).
		_bob_phase += delta * BOB_SPEED * clampf(speed / SPEED, 0.45, 1.25)
		var swing := sin(_bob_phase)
		if _upper_body:
			_upper_body.position.y = lerpf(_upper_body.position.y, _upper_base_y + swing * BOB_AMOUNT, blend)
		if _leg_l and _leg_r and not block_ready:
			_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing * JOG_LEG_SWING, blend)
			_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing * JOG_LEG_SWING, blend)
		if _arm_l and _arm_r and not block_ready and not is_goalkeeper:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -swing * JOG_ARM_SWING, blend)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, swing * JOG_ARM_SWING, blend)
			_pose_hands_from_arms()
	elif grounded:
		# Idle breathe — tiny vertical settle.
		_idle_phase += delta * 2.4
		var breathe := sin(_idle_phase) * IDLE_BREATHE
		if _upper_body:
			_upper_body.position.y = lerpf(_upper_body.position.y, _upper_base_y + breathe, blend)
		if _leg_l and _leg_r:
			_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, blend)
			_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, blend)
		if _arm_l and _arm_r and not block_ready and not diving:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, 0.0, blend)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, blend)
			if not is_goalkeeper:
				_pose_arms_rest()


func _pose_hands_from_arms() -> void:
	if _hand_l == null or _hand_r == null or _arm_l == null or _arm_r == null:
		return
	# Hands track roughly past the forearm tips while jogging.
	_hand_l.position = _arm_l.position + Vector3(-0.18, -0.08, 0.06)
	_hand_r.position = _arm_r.position + Vector3(0.18, -0.08, 0.06)
