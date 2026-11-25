extends CharacterBody3D
class_name Player

## Modular primitive outfield / GK (Wave 1 body anchors). Controlled player receives
## match input; AI teammates chase/block. Collision stays a capsule; visuals are
## named parts (hair→feet) so anims and foul regions have real anchors.
## Phase 3: GK dive/track, outfield block volume for contested shots.
## Phase 4: formation-aware off-ball slots (wing / backcourt / pivot-ish).
## Wave 5: role-distinct drive/mark/support (show, cut, seal, clear-out).

signal possession_changed(has_ball: bool)
signal dive_started
signal fake_started(kind: int)
signal save_resolved(caught: bool)
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
# Core-loop feel: open 9 m / crease shots; pass under pressure; avoid stall back-passes.
# AI credibility: pressure outlets, readable contest windows, GK shot-line cover.
const AI_CHASE_SPEED_SCALE := 0.88
const AI_BLOCK_SPEED_SCALE := 0.92
const AI_ATTACK_SPEED_SCALE := 0.84
const AI_GK_SPEED_SCALE := 0.76
const AI_GK_TRACK_SPEED_SCALE := 1.0
const AI_SHOOT_RANGE := 10.5
## Near crease: take the shot unless a clean forward escape exists.
const AI_CREASE_SHOT_RANGE := 8.2
const AI_SHOOT_COOLDOWN := 1.15
const AI_PASS_COOLDOWN := 0.55
const AI_BLOCK_DEPTH := 4.5
## Defender inside this range → prefer pass over forcing a shot.
const AI_PRESSURE_RANGE := 2.9
## Carry distance that reads as "last step" before traveling (~3 plants).
const AI_STEP_WARN_DIST := 2.5
## Wall-clock possession without a release → force pass/shot (dead-attack guard).
const AI_POSSESSION_FORCE_S := 3.6
## Only circulate when this far from the attacked goal (was 8.5 — stalled 9 m looks).
const AI_CIRCULATE_DIST := 12.0
## Readable contest window while marking / closing out (not a teleport steal).
const AI_CONTEST_WINDOW_S := 0.62
const AI_CONTEST_CLOSE_M := 4.2
## Contested free-ball age windows (shot vs pass) — tips only while block_ready.
const CONTEST_SHOT_AGE_MS := 1300
const CONTEST_PASS_AGE_MS := 900
## Lane openness below this under pressure → treat as contested hold (prefer other outlet).
const AI_PRESSURE_LANE_MIN := 0.40

# Phase 3 GK dive
const DIVE_DURATION := 0.55
const DIVE_COOLDOWN := 0.95
const DIVE_SPEED := 13.0
const DIVE_UP := 3.0
const GK_LATERAL_BOOST := 1.18
const AI_DIVE_REACT_DIST := 11.5
const AI_DIVE_MIN_BALL_SPEED := 7.0
## Mild near-post shade — keep body on the shot line (credibility).
const GK_NEAR_POST_BIAS := 0.22
## Phase F: catch settle (brief move penalty) + GK outlet delay.
const CATCH_SETTLE_S := 0.38
const CATCH_SETTLE_SPEED := 0.52
const GK_OUTLET_DELAY_S := 0.42
const GK_OUTLET_COOLDOWN_S := 1.1
## Wave 3: fake cooldown so spam doesn't soft-lock shoot/pass.
const FAKE_COOLDOWN_S := 0.55
## Brief move soft while jabbing.
const FAKE_JAB_SPEED := 0.72
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
## Wave 4: red card / DQ sandbox — removed for the match (roster hole).
var disqualified: bool = false
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
## Wave 6: opponent DefenseShape this player is attacking against (synced).
var facing_defense_shape: int = 0
## Wave 6 Kempa: brief lockout after redirect so we don't double-fire.
var _kempa_lock_t: float = 0.0
## Phase F jump-shot craft — exposed for ShotCraft.jump_shot_quality duck-typing.
var jump_shot_active: bool = false
var jump_shot_air_s: float = 0.0
var jump_shot_phase: int = 0  # ShotCraft.JumpPhase
## Wave 2 throw / jump motion (procedural poses on modular body parts).
var throw_action: int = 0  # ThrowMotion.Action
var throw_phase: int = 0  # ThrowMotion.Phase
var throw_t: float = 0.0
var throw_pass_type: int = 0
var throw_charge: float = 0.0
var throw_lob: bool = false
var throw_wing: bool = false
var throw_aim_dir: Vector3 = Vector3.FORWARD
## True while a one-shot throw sequence owns arms/torso (not charge-only).
var throw_motion_active: bool = false
var _throw_pose_cache: Dictionary = {}

## Wave 3 fakes — keep ball; threaten then recover.
var fake_kind: int = 0  # FakeMotion.Kind
var fake_phase: int = 0  # FakeMotion.Phase
var fake_t: float = 0.0
var fake_active: bool = false
var fake_jab_side: float = 1.0
var _fake_pose_cache: Dictionary = {}
var _fake_cd: float = 0.0
var _ai_fake_cd: float = 0.0
## Lite sell: briefly frozen / slowed after being faked.
var fake_sold_t: float = 0.0
var fake_recover_t: float = 0.0

## Wave 3 GK vocabulary.
var gk_stance: int = 0  # GkMotion.Stance
var dive_side: int = 0  # GkMotion.DiveSide
var dive_height: int = 0  # GkMotion.DiveHeight
var last_save_caught: bool = false
var _gk_pose_timer: float = 0.0
var _gk_pose_cache: Dictionary = {}
var _seven_m_lock: bool = false

var _bob_phase: float = 0.0
var _idle_phase: float = 0.0
var _pickup_block: float = 0.0
var _ai_shoot_cd: float = 0.0
var _ai_pass_cd: float = 0.0
## AI carry distance — pass/shoot before Phase 2 traveling fires.
var _ai_carry_dist: float = 0.0
var _ai_carry_last_xz: Vector3 = Vector3.ZERO
var _ai_carry_sampling: bool = false
## Seconds holding the ball this possession (AI release / stall guard).
var _ai_possess_t: float = 0.0
## MatchController sets when attack stalls without progress — honor next tick.
var _ai_force_release: bool = false
## Wave 5: cut cadence so off-ball motion isn't a permanent dash.
var _ai_cut_cd: float = 0.0
var _ai_cut_active: float = 0.0
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
## Pivot / free foot teaching (R1.6 / R1.7) — synced from HandballRules while holding.
const PIVOT_NONE := -1
const PIVOT_LEFT := 0
const PIVOT_RIGHT := 1
var pivot_foot: int = PIVOT_NONE
var _shoe_mat_l: StandardMaterial3D
var _shoe_mat_r: StandardMaterial3D
var _pivot_ring: MeshInstance3D
var _pivot_ring_mat: StandardMaterial3D
const PIVOT_SHOE := Color(0.95, 0.72, 0.22)
const FREE_SHOE := Color(0.12, 0.12, 0.14)
const PIVOT_RING_COLOR := Color(0.98, 0.78, 0.28, 0.55)

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
	if _fake_cd > 0.0:
		_fake_cd = maxf(0.0, _fake_cd - delta)
	if _ai_fake_cd > 0.0:
		_ai_fake_cd = maxf(0.0, _ai_fake_cd - delta)
	if _ai_cut_cd > 0.0:
		_ai_cut_cd = maxf(0.0, _ai_cut_cd - delta)
	if _ai_cut_active > 0.0:
		_ai_cut_active = maxf(0.0, _ai_cut_active - delta)
	if fake_sold_t > 0.0:
		fake_sold_t = maxf(0.0, fake_sold_t - delta)
		if fake_sold_t <= 0.0 and fake_recover_t <= 0.0:
			fake_recover_t = FakeMotion.SELL_RECOVER_S
	if fake_recover_t > 0.0:
		fake_recover_t = maxf(0.0, fake_recover_t - delta)
	if _gk_pose_timer > 0.0:
		_gk_pose_timer = maxf(0.0, _gk_pose_timer - delta)
		if _gk_pose_timer <= 0.0 and not diving and gk_stance in [
			GkMotion.Stance.CATCH, GkMotion.Stance.DEFLECT, GkMotion.Stance.OUTLET
		]:
			gk_stance = GkMotion.Stance.SET if is_goalkeeper else GkMotion.Stance.IDLE
			_gk_pose_cache = {}
	if _catch_settle_t > 0.0:
		_catch_settle_t = maxf(0.0, _catch_settle_t - delta)
	if _kempa_lock_t > 0.0:
		_kempa_lock_t = maxf(0.0, _kempa_lock_t - delta)
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
	elif fake_sold_t > 0.0:
		# Sold by a fake — freeze briefly, then soft recover.
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

	# 7 m: defending GK stays on / behind the 4 m restraining line (lite).
	if is_goalkeeper and _seven_m_lock and not diving:
		wish = _clamp_gk_seven_m_wish(wish)

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
	if fake_recover_t > 0.0:
		target_speed *= 0.55
	# Snappy ground response; softer air control for jump-shot steering.
	if not diving and _js_plant_t <= 0.0 and not on_bench and not excluded and fake_sold_t <= 0.0:
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
		_tick_fake_motion(delta)
		_update_gk_stance(wish, planar_speed_hint(wish, target_speed))

	# Soft velocity push clears nested capsules without freezing wish/slide motion.
	_apply_soft_player_separation()
	move_and_slide()
	if is_goalkeeper and _seven_m_lock:
		_enforce_gk_four_meter()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if planar.length() > FACE_THRESHOLD and not diving and _js_plant_t <= 0.0 and not fake_active:
		var target_yaw := atan2(planar.x, planar.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))
	elif (
		is_goalkeeper
		and not diving
		and not on_bench
		and not excluded
		and match_ball != null
		and planar.length() <= FACE_THRESHOLD
	):
		# Set GK faces the threat so the body covers the shot line.
		var threat_look: Vector3 = match_ball.global_position
		if match_ball.carrier != null and match_ball.carrier.team_id != team_id:
			threat_look = match_ball.carrier.global_position
		var look: Vector3 = threat_look - global_position
		look.y = 0.0
		if look.length_squared() > 0.25:
			var face_yaw := atan2(look.x, look.z)
			rotation.y = lerp_angle(rotation.y, face_yaw, 1.0 - exp(-8.0 * delta))

	if on_bench or excluded:
		rotation.y = Court.bench_yaw(team_id)
		if global_position.y < -0.15:
			global_position.y = 0.0
			velocity.y = 0.0
	_tick_throw_motion(delta)
	_update_locomotion_anim(delta, planar.length())
	_apply_pivot_plant_visual(delta, planar.length())
	_update_arm_pose(delta)
	_apply_throw_pose(delta)
	_apply_fake_pose(delta)
	_apply_gk_pose(delta)
	_apply_torso_yaw(delta)
	_apply_bench_visual()
	_try_sticky_pass_catch()


func planar_speed_hint(wish: Vector3, target_speed: float) -> float:
	if wish.length_squared() < 0.01:
		return 0.0
	return wish.length() * target_speed


func try_shoot(
	aim_dir: Vector3,
	impulse_strength: float,
	ball: Ball,
	up_bias: float = -1.0,
	shot_meta: Dictionary = {}
) -> bool:
	if not has_ball or ball == null or ball.carrier != self:
		return false
	# Fakes keep the ball — never allow a release mid-fake.
	if fake_active:
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
	var is_pass := bool(shot_meta.get("pass", false))
	var wing := bool(shot_meta.get("wing_shot", false)) or ThrowMotion.is_wing_finish_context(self)
	if wing and not is_pass:
		shot_meta["wing_shot"] = true
	_begin_throw_from_release(aim_dir, shot_meta, is_pass, wing)
	possession_changed.emit(false)
	ball.release_and_shoot(aim_dir, impulse_strength, up_bias, shot_meta)
	return true


func begin_catch_settle() -> void:
	_catch_settle_t = CATCH_SETTLE_S
	# Catch land plant: establish a readable pivot if rules haven't synced yet.
	if pivot_foot == PIVOT_NONE and not is_goalkeeper:
		pivot_foot = preferred_catch_pivot_foot()
	_flash_catch_plant_pose()


func is_catch_settling() -> bool:
	return _catch_settle_t > 0.0


## Prefer the more-forward shoe for catch/gather plant (R1.7 / R2.8).
func preferred_catch_pivot_foot() -> int:
	var foot_l := find_child("ShoeL", true, false) as Node3D
	var foot_r := find_child("ShoeR", true, false) as Node3D
	if foot_l == null or foot_r == null:
		return PIVOT_RIGHT
	var forward := face_direction()
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()
	var origin := Vector3(global_position.x, 0.0, global_position.z)
	var l_fwd := (Vector3(foot_l.global_position.x, 0.0, foot_l.global_position.z) - origin).dot(forward)
	var r_fwd := (Vector3(foot_r.global_position.x, 0.0, foot_r.global_position.z) - origin).dot(forward)
	if l_fwd > r_fwd + 0.02:
		return PIVOT_LEFT
	return PIVOT_RIGHT


func set_pivot_foot(foot: int) -> void:
	pivot_foot = foot


func get_pivot_foot() -> int:
	return pivot_foot


func clear_pivot_foot() -> void:
	pivot_foot = PIVOT_NONE


## Wave 6 R4.8: after an airborne catch near goal, redirect toward goal (readable motion).
func _try_kempa_after_catch() -> void:
	if _kempa_lock_t > 0.0 or match_ball == null or not has_ball:
		return
	var airborne := (not is_on_floor()) or jump_shot_active or global_position.y > 0.45
	if not Formations.kempa_eligible(self, airborne):
		return
	# Brief settle so the catch reads, then tip toward goal (not a teleport release).
	_kempa_lock_t = 0.85
	_catch_settle_t = minf(_catch_settle_t, 0.08)
	# Defer one physics frame so possession/HUD settle before the tip.
	call_deferred("_kempa_redirect_deferred")


func _kempa_redirect_deferred() -> void:
	if not has_ball or match_ball == null or match_ball.carrier != self:
		return
	try_kempa_redirect(match_ball)


## Airborne tip / volley into goal — uses throw windup so it isn't a teleport.
func try_kempa_redirect(ball: Ball) -> bool:
	if ball == null or not has_ball or ball.carrier != self:
		return false
	if is_goalkeeper or fake_active:
		return false
	var airborne := (not is_on_floor()) or jump_shot_active or global_position.y > 0.35
	if not Formations.kempa_eligible(self, airborne):
		return false
	var goal := opponent_goal_point()
	var from := global_position + Vector3(0.0, 1.35, 0.0)
	var aim := (goal + Vector3(randf_range(-0.45, 0.45), randf_range(0.85, 1.45), 0.0) - from)
	if aim.length_squared() < 0.01:
		return false
	aim = aim.normalized()
	# Mild wing assist if finishing from the corridor.
	if ThrowMotion.is_wing_finish_context(self):
		aim = ThrowMotion.wing_aim_assist(self, aim)
	var meta := {
		"kempa": true,
		"jump_shot": true,
		"charge": 0.7,
		"ai": ai_enabled and not controlled,
	}
	jump_shot_active = true
	var ok := try_shoot(aim, ShotCraft.impulse_for_charge(0.7, false), ball, 0.12, meta)
	if ok:
		_kempa_lock_t = 0.9
	return ok


func _move_speed_mul() -> float:
	var mul := 1.0
	if _catch_settle_t > 0.0:
		mul *= CATCH_SETTLE_SPEED
	if _js_plant_t > 0.0:
		mul *= JUMP_PLANT_SPEED
	if fake_active and fake_kind == FakeMotion.Kind.JAB and fake_phase == FakeMotion.Phase.THREATEN:
		mul *= FAKE_JAB_SPEED
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
		# Approach steps feed the plant so takeoff reads (R2.4).
		jump_shot_phase = ShotCraft.JumpPhase.APPROACH
		jump_shot_air_s = 0.0
		_js_plant_t = ShotCraft.PLANT_HOLD_S
		_js_was_airborne = false
		throw_wing = ThrowMotion.is_wing_finish_context(self)
		throw_aim_dir = opponent_goal_point() - global_position
		_torso_yaw_offset = ThrowMotion.torso_yaw_toward(face_direction(), throw_aim_dir)
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
		# First half of plant hold = approach gather; second half = plant load.
		if _js_plant_t > ShotCraft.PLANT_HOLD_S * 0.45:
			jump_shot_phase = ShotCraft.JumpPhase.APPROACH
		else:
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
			# Landed — craft complete; optional land pose if no throw sequence owns it.
			jump_shot_active = false
			jump_shot_phase = ShotCraft.JumpPhase.NONE
			jump_shot_air_s = 0.0
			_js_was_airborne = false
			if not throw_motion_active or throw_phase == ThrowMotion.Phase.CHARGE:
				_begin_land_pose()
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
	gk_stance = GkMotion.Stance.OUTLET
	_gk_pose_timer = GkMotion.OUTLET_POSE_S
	var yaw := 0.0
	var wing := _ai_outlet_wing()
	if wing:
		yaw = ThrowMotion.torso_yaw_toward(face_direction(), wing.global_position - global_position)
	_gk_pose_cache = GkMotion.pose_outlet(yaw)
	_apply_save_box_from_pose(_gk_pose_cache)


func _tick_gk_outlet(delta: float) -> void:
	if not is_goalkeeper or not _outlet_pending:
		return
	if not has_ball or match_ball == null or match_ball.carrier != self:
		_outlet_pending = false
		_outlet_timer = 0.0
		return
	if controlled and not ai_enabled:
		# Human GK keeps the ball — outlet is an AI assist after saves.
		# Still show outlet-ready pose so distribution reads.
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


## Wave 3: usable fake — keeps ball, never fires a shot/pass.
func try_fake(kind: int, aim_hint: Vector3 = Vector3.ZERO) -> bool:
	if kind == FakeMotion.Kind.NONE:
		return false
	if not has_ball or match_frozen or on_bench or excluded or diving or is_goalkeeper:
		return false
	if fake_active or _fake_cd > 0.0:
		return false
	if throw_motion_active and throw_phase == ThrowMotion.Phase.CHARGE:
		# Abort charge so fake can't be mistaken for a release.
		clear_shot_charge_motion()
	if throw_motion_active and throw_phase != ThrowMotion.Phase.IDLE:
		return false
	if jump_shot_active and not is_on_floor():
		return false
	dribbling = false
	fake_kind = kind
	fake_phase = FakeMotion.Phase.THREATEN
	fake_t = 0.0
	fake_active = true
	_fake_cd = FAKE_COOLDOWN_S + FakeMotion.threaten_duration(kind) + FakeMotion.recover_duration(kind)
	var aim := aim_hint
	if aim.length_squared() < 0.01:
		aim = opponent_goal_point() - global_position
	_torso_yaw_offset = ThrowMotion.torso_yaw_toward(face_direction(), aim)
	if kind == FakeMotion.Kind.JAB:
		var side := aim.x
		if absf(side) < 0.05:
			side = face_direction().x
		if absf(side) < 0.05:
			side = 1.0 if (player_index % 2) == 0 else -1.0
		fake_jab_side = signf(side)
		# Small planar nudge so the jab reads as a step, not a root slide only.
		velocity.x += fake_jab_side * 2.8
	_fake_pose_cache = FakeMotion.pose_for(kind, fake_phase, _torso_yaw_offset, fake_jab_side)
	_sell_fake_to_markers()
	fake_started.emit(kind)
	return true


func clear_fake_motion() -> void:
	fake_kind = FakeMotion.Kind.NONE
	fake_phase = FakeMotion.Phase.IDLE
	fake_t = 0.0
	fake_active = false
	_fake_pose_cache = {}


func is_faking() -> bool:
	return fake_active


func _tick_fake_motion(delta: float) -> void:
	if not fake_active:
		return
	if not has_ball or match_frozen or on_bench or excluded:
		clear_fake_motion()
		return
	var stepped := FakeMotion.tick_fake(
		fake_kind, fake_phase, fake_t, delta, _torso_yaw_offset, fake_jab_side
	)
	fake_phase = int(stepped["phase"])
	fake_t = float(stepped["t"])
	_fake_pose_cache = stepped["pose"]
	if bool(stepped["done"]):
		_apply_pose_dict(stepped["pose"] as Dictionary, 1.0)
		clear_fake_motion()


func _apply_fake_pose(delta: float) -> void:
	if not fake_active or _fake_pose_cache.is_empty() or _arm_r == null:
		return
	if throw_motion_active:
		return
	var blend := 1.0 - exp(-18.0 * delta)
	_apply_pose_dict(_fake_pose_cache, blend)


func _sell_fake_to_markers() -> void:
	var match_root := get_parent()
	if match_root:
		match_root = match_root.get_parent()
	if match_root == null:
		return
	for team_root in match_root.get_children():
		if not (team_root is Node):
			continue
		for child in team_root.get_children():
			if child == self or not (child is Player):
				continue
			var opp := child as Player
			if opp.team_id == team_id or opp.is_goalkeeper or opp.on_bench or opp.excluded:
				continue
			if global_position.distance_to(opp.global_position) > FakeMotion.SELL_RADIUS:
				continue
			# Lite sell: freeze then soft recover. Shot/pass fakes sell harder than jab.
			var sell := FakeMotion.SELL_DURATION
			if fake_kind == FakeMotion.Kind.JAB:
				sell *= 0.75
			opp.fake_sold_t = maxf(opp.fake_sold_t, sell)
			opp.raise_block(0.15)


func set_seven_meter_lock(active: bool) -> void:
	_seven_m_lock = active and is_goalkeeper


func _clamp_gk_seven_m_wish(wish: Vector3) -> Vector3:
	if wish.length_squared() < 0.0001:
		return wish
	var four := Court.four_meter_spot(team_id)
	var toward_court := 1.0 if team_id == 0 else -1.0
	# Don't advance past the 4 m mark toward midfield.
	var next_z := global_position.z + wish.z * 0.35
	if team_id == 0 and next_z > four.z:
		wish.z = minf(wish.z, 0.0)
	elif team_id == 1 and next_z < four.z:
		wish.z = maxf(wish.z, 0.0)
	# Tiny bias back onto the line when past it.
	if team_id == 0 and global_position.z > four.z + 0.05:
		wish.z = minf(wish.z, -0.6)
		wish += Vector3(0.0, 0.0, -toward_court) * 0.15
	elif team_id == 1 and global_position.z < four.z - 0.05:
		wish.z = maxf(wish.z, 0.6)
	return wish


func _enforce_gk_four_meter() -> void:
	var four := Court.four_meter_spot(team_id)
	if team_id == 0 and global_position.z > four.z:
		global_position.z = four.z
		velocity.z = minf(velocity.z, 0.0)
	elif team_id == 1 and global_position.z < four.z:
		global_position.z = four.z
		velocity.z = maxf(velocity.z, 0.0)


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
	var ball_y := 1.0
	if match_ball:
		ball_y = match_ball.global_position.y
	var classified := GkMotion.classify_dive(_dive_dir, ball_y, face_direction())
	dive_side = int(classified["side"])
	dive_height = int(classified["height"])
	diving = true
	gk_stance = GkMotion.Stance.DIVE
	_dive_timer = DIVE_DURATION
	_dive_cd = DIVE_COOLDOWN + DIVE_DURATION
	_block_timer = DIVE_DURATION + 0.15
	block_ready = true
	var up := DIVE_UP * (1.15 if dive_height == GkMotion.DiveHeight.HIGH else 0.72)
	velocity = _dive_dir * DIVE_SPEED + Vector3(0.0, up, 0.0)
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
	_ai_reset_possession_tracking()
	_bob_phase = 0.0
	diving = false
	_dive_timer = 0.0
	_dive_cd = 0.0
	_block_timer = 0.0
	block_ready = false
	# Wave 4: red-carded players stay off for the match; 2-min exclusions clear on full reset.
	if disqualified:
		excluded = true
		exclusion_remaining = maxf(exclusion_remaining, 1.0)
		global_position = Court.bench_marker(team_id, 2 + maxi(0, player_index % 4))
	else:
		excluded = false
		exclusion_remaining = 0.0
	# on_bench / bench_slot preserved — MatchController owns sub state across resets.
	if on_bench and not disqualified:
		global_position = Court.bench_marker(team_id, maxi(0, bench_slot))
	stamina = STAMINA_MAX
	sprinting = false
	visible = true
	_catch_settle_t = 0.0
	_js_plant_t = 0.0
	clear_pivot_foot()
	_js_was_airborne = false
	jump_shot_active = false
	jump_shot_air_s = 0.0
	jump_shot_phase = ShotCraft.JumpPhase.NONE
	_outlet_pending = false
	_outlet_timer = 0.0
	_outlet_cd = 0.0
	clear_throw_motion()
	clear_fake_motion()
	_fake_cd = 0.0
	_ai_fake_cd = 0.0
	_ai_cut_cd = 0.0
	_ai_cut_active = 0.0
	fake_sold_t = 0.0
	fake_recover_t = 0.0
	gk_stance = GkMotion.Stance.IDLE
	dive_side = GkMotion.DiveSide.NONE
	dive_height = GkMotion.DiveHeight.LOW
	last_save_caught = false
	_gk_pose_timer = 0.0
	_gk_pose_cache = {}
	_seven_m_lock = false
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


## Cut the angle: sit on shooter→goal line with mild near-post shade.
func _gk_angle_cut_target(threat_pos: Vector3, home: Vector3, toward_court: float) -> Vector3:
	var goal_z := home.z
	var goal_center := Vector3(0.0, 0.0, goal_z)
	var gap := absf(threat_pos.z - goal_z)
	var depth_frac := clampf(1.0 - gap / 16.0, 0.0, 1.0)
	# Near post = post on the shooter's side; center threats keep middle.
	var near_post_x := 0.0
	if absf(threat_pos.x) > 0.65:
		near_post_x = signf(threat_pos.x) * (Court.GOAL_WIDTH * 0.5)
	# Sit harder on the shot line (higher lerp → closer to goal, body covers).
	var cut := threat_pos.lerp(goal_center, lerpf(0.78, 0.92, depth_frac))
	# Mild near-post shade — do not walk off the shot line.
	cut.x = lerpf(cut.x, near_post_x, GK_NEAR_POST_BIAS)
	cut.x = clampf(cut.x, -3.4, 3.4)
	# Step off the goal line as the threat closes (angle cut).
	var step := lerpf(0.65, 2.55, depth_frac)
	cut.z = goal_z + toward_court * step
	if team_id == 0:
		cut.z = clampf(cut.z, -18.5, -14.0)
	else:
		cut.z = clampf(cut.z, 14.0, 18.5)
	cut.y = 0.0
	return cut


## Ideal planar X of shooter→goal-mouth at the GK cut depth (smoke / cover check).
func gk_shot_line_x_at_cut(threat_pos: Vector3) -> float:
	var home := start_position
	var toward_court := 1.0 if team_id == 0 else -1.0
	var cut := _gk_angle_cut_target(threat_pos, home, toward_court)
	var goal_z := home.z
	var gap_z := goal_z - threat_pos.z
	if absf(gap_z) < 0.05:
		return clampf(threat_pos.x, -3.4, 3.4)
	var t := clampf((cut.z - threat_pos.z) / gap_z, 0.0, 1.0)
	return clampf(lerpf(threat_pos.x, 0.0, t), -3.4, 3.4)


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
	# Hold role shape toward last ball side — not a second chaser (R4.3).
	var slot := Formations.attack_slot(self, match_ball.global_position)
	# Bias slightly toward ball without full chase.
	slot = slot.lerp(Vector3(match_ball.global_position.x, 0.0, match_ball.global_position.z), 0.15)
	slot = Formations.apply_teammate_spacing(slot, self, _ai_teammate_roster())
	slot = _keep_outfield_legal(slot)
	return _steer_toward(slot) * AI_ATTACK_SPEED_SCALE


func _ai_defend_block(carrier: Player) -> Vector3:
	# Wave 5 R4.4: mark threats (ball-side pressure) + help/cover on cutters/pivot.
	var ball_pos := match_ball.global_position if match_ball else carrier.global_position
	var opponents := _ai_opponent_roster()
	var mark := Formations.find_mark_target(self, opponents)
	var help := Formations.find_help_threat(self, opponents, mark, ball_pos)
	var slot := Formations.defense_mark_slot(self, ball_pos, carrier, mark, help)
	slot = Formations.apply_teammate_spacing(slot, self, _ai_teammate_roster())
	var carrier_pos := carrier.global_position
	carrier_pos.y = 0.0
	slot = _keep_outfield_legal(slot)
	var close := carrier_pos.distance_to(global_position) < AI_CONTEST_CLOSE_M
	var marking_carrier := mark != null and mark == carrier
	# Readable contest window while pressuring the carrier (arms up — not a steal).
	if carrier.has_ball and (close or marking_carrier):
		raise_block(AI_CONTEST_WINDOW_S)
	elif match_ball != null and match_ball.carrier == null:
		# Tip window on free shots/passes flying through our lane.
		_ai_contest_free_ball_window()
	return _steer_toward(slot) * AI_BLOCK_SPEED_SCALE


## Raise a short contest window when a free ball is approaching through our corridor.
func _ai_contest_free_ball_window() -> void:
	if match_ball == null or diving or match_frozen:
		return
	var vel := match_ball.linear_velocity
	var speed := vel.length()
	if speed < 5.0:
		return
	var to_me := global_position - match_ball.global_position
	to_me.y = 0.0
	if to_me.length_squared() < 0.01:
		return
	# Approaching and within a readable tip range.
	if vel.dot(to_me) <= 0.0:
		return
	var lateral := absf(
		Vector3(vel.x, 0.0, vel.z).normalized().cross(to_me.normalized()).y
	) * to_me.length()
	if to_me.length() > 5.5 or lateral > 1.55:
		return
	raise_block(AI_CONTEST_WINDOW_S * 0.85)


func _ai_support_attack(carrier: Player) -> Vector3:
	# Wave 5 R4.5: show-for-pass, timed cuts, pivot seal, clear-out when crowded.
	var ball_pos := carrier.global_position
	var teammates := _ai_teammate_roster()
	var screen_def := _ai_nearest_opponent()
	var role := Formations.role_for(self)
	# Cut cadence: wings/backs flash cut; pivot seals continuously via support_attack_slot.
	var want_cut := _ai_cut_active > 0.0
	if (
		not want_cut
		and _ai_cut_cd <= 0.0
		and role != Formations.Role.PIVOT
		and role != Formations.Role.GK
	):
		# Stagger by roster index so the whole attack doesn't cut together.
		var beat := (int(Time.get_ticks_msec() / 900) + player_index) % 5
		if beat == 0 or beat == player_index % 5:
			_ai_cut_active = 1.15
			_ai_cut_cd = 2.8 + float(player_index % 3) * 0.35
			want_cut = true
	var opponents := _ai_opponent_roster()
	var slot := Formations.support_attack_slot(
		self, ball_pos, carrier, teammates, screen_def, want_cut, opponents
	)
	slot = _keep_outfield_legal(slot)
	var speed := AI_ATTACK_SPEED_SCALE * (1.14 if want_cut else 1.08)
	# Wave 6 Kempa setup: jump near crease when a pass is inbound.
	if (
		Formations.kempa_near_crease(self)
		and is_on_floor()
		and match_ball != null
		and match_ball.is_pass_in_flight()
		and match_ball.pass_intended_receiver() == self
	):
		velocity.y = maxf(velocity.y, JUMP_VELOCITY * 0.92)
	return _steer_toward(slot) * minf(speed, 1.0)


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
	for opp in _ai_opponent_roster():
		var d := global_position.distance_squared_to(opp.global_position)
		if d < best_d:
			best_d = d
			best = opp
	return best


func _ai_teammate_roster() -> Array:
	var out: Array = []
	var parent_n := get_parent()
	if parent_n == null:
		return out
	for sibling in parent_n.get_children():
		if sibling == self or not (sibling is Player):
			continue
		var mate := sibling as Player
		if mate.is_goalkeeper or mate.excluded or mate.on_bench:
			continue
		out.append(mate)
	return out


func _ai_opponent_roster() -> Array:
	var out: Array = []
	var my_parent := get_parent()
	if my_parent == null or my_parent.get_parent() == null:
		return out
	for team_root in my_parent.get_parent().get_children():
		if team_root == my_parent:
			continue
		for child in team_root.get_children():
			if not (child is Player):
				continue
			var opp := child as Player
			if opp.team_id == team_id or opp.is_goalkeeper or opp.excluded or opp.on_bench:
				continue
			out.append(opp)
	return out


func _ai_reset_possession_tracking() -> void:
	_ai_carry_dist = 0.0
	_ai_carry_sampling = false
	_ai_possess_t = 0.0
	_ai_force_release = false


func _ai_pass_is_forward(target: Player) -> bool:
	if target == null:
		return false
	var attack_sign := 1.0 if team_id == 0 else -1.0
	var dz := (target.global_position.z - global_position.z) * attack_sign
	return dz >= -0.35


## Safe side outlet: enough lateral escape without dumping backward.
func _ai_pass_is_side_outlet(target: Player) -> bool:
	if target == null:
		return false
	var attack_sign := 1.0 if team_id == 0 else -1.0
	var dz := (target.global_position.z - global_position.z) * attack_sign
	var dx := absf(target.global_position.x - global_position.x)
	return dz >= -0.85 and dx >= 2.0


func _ai_try_shoot_at_goal(dist: float, nine_m: bool) -> bool:
	if match_ball == null or _ai_shoot_cd > 0.0 or fake_active:
		return false
	var goal := opponent_goal_point()
	var me := global_position
	var aim := (goal - (me + Vector3(0, 1.2, 0))).normalized()
	# Slight aim noise so Away isn't laser-perfect.
	aim += Vector3(randf_range(-0.06, 0.06), randf_range(-0.02, 0.03), randf_range(-0.04, 0.04))
	aim = aim.normalized()
	var lob := dist < 7.0 and (player_index % 2) == 0 and not nine_m
	var charge := 0.72 if nine_m else 0.55
	var impulse := ShotCraft.impulse_for_charge(charge, lob)
	var up := ShotCraft.up_bias(lob)
	var meta := {"lob": lob, "ai": true, "charge": charge}
	if nine_m:
		meta["nine_meter"] = true
	if try_shoot(aim, impulse, match_ball, up, meta):
		_ai_shoot_cd = AI_SHOOT_COOLDOWN
		_ai_reset_possession_tracking()
		return true
	return false


func _ai_attack_with_ball(_delta: float) -> Vector3:
	var goal := opponent_goal_point()
	var me := global_position
	var xz := Vector3(me.x, 0.0, me.z)
	if not _ai_carry_sampling:
		_ai_carry_last_xz = xz
		_ai_carry_dist = 0.0
		_ai_possess_t = 0.0
		_ai_carry_sampling = true
	else:
		_ai_carry_dist += xz.distance_to(_ai_carry_last_xz)
		_ai_carry_last_xz = xz
		_ai_possess_t += _delta
	var flat := Vector3(goal.x - me.x, 0.0, goal.z - me.z)
	var dist := flat.length()
	# Pass or shoot before traveling (3 steps ≈ ~5.4 m with tuned gait).
	var must_release := _ai_carry_dist >= 3.2 or _ai_force_release
	var step_warn := _ai_carry_dist >= AI_STEP_WARN_DIST
	var under_pressure := _ai_under_pressure()
	var pass_target := _ai_pass_target()
	var forward_pass := _ai_pass_is_forward(pass_target)
	var shot_lane := Formations.shot_lane_openness(me, team_id, _ai_opponent_roster())
	var open_shot := (not under_pressure or shot_lane >= 0.52) and dist <= AI_SHOOT_RANGE
	var crease_look := dist <= AI_CREASE_SHOT_RANGE
	var force_release := must_release or _ai_possess_t >= AI_POSSESSION_FORCE_S
	var nine_m := Formations.should_take_nine_meter_shot(
		self, dist, under_pressure, pass_target != null and forward_pass
	)
	# Wave 3: sparingly fake under pressure before releasing.
	if (
		under_pressure
		and not force_release
		and not open_shot
		and _ai_fake_cd <= 0.0
		and not fake_active
		and randf() < FakeMotion.AI_FAKE_CHANCE
	):
		var fk := FakeMotion.Kind.JAB
		if dist <= AI_SHOOT_RANGE and (player_index % 2) == 0:
			fk = FakeMotion.Kind.SHOT
		elif pass_target != null:
			fk = FakeMotion.Kind.PASS
		var hint := flat if fk != FakeMotion.Kind.PASS else (pass_target.global_position - me)
		if try_fake(fk, hint):
			_ai_fake_cd = FakeMotion.AI_FAKE_COOLDOWN_S
			return _steer_toward(_keep_outfield_legal(
				Vector3(goal.x + fake_jab_side * 1.4, 0.0, goal.z)
			)) * AI_ATTACK_SPEED_SCALE
	# Take open 9 m / crease looks before recycling. Never stall on back-passes.
	var should_shoot := (
		open_shot
		or nine_m
		or (crease_look and (not under_pressure or shot_lane >= 0.4 or force_release))
		or (force_release and (pass_target == null or not forward_pass or open_shot or crease_look))
	)
	if match_ball != null and should_shoot and not fake_active:
		if _ai_try_shoot_at_goal(dist, nine_m):
			return Vector3.ZERO
	# Prefer pass under pressure / far from goal / force with a forward/side escape.
	# Credibility: under mark, clear outlets beat contested holds.
	var facing_man := Formations.facing_defense_of(self) == Formations.DefenseShape.INDIVIDUAL
	var side_outlet := _ai_pass_is_side_outlet(pass_target)
	var safe_outlet := forward_pass or side_outlet
	var prefer_pass := pass_target != null and not open_shot and (
		(under_pressure and safe_outlet and not (crease_look and shot_lane >= 0.55))
		or (force_release and safe_outlet)
		or (step_warn and under_pressure and safe_outlet)
		or (dist > AI_CIRCULATE_DIST and forward_pass)
		or (facing_man and under_pressure and safe_outlet)
	)
	# Endless back-passes kill the attack — shoot instead when in range.
	# Side outlets under pressure stay legal (escape the mark).
	if prefer_pass and not forward_pass and not side_outlet and dist <= AI_SHOOT_RANGE:
		prefer_pass = false
		if match_ball != null and not fake_active and _ai_try_shoot_at_goal(dist, nine_m):
			return Vector3.ZERO
	if match_ball != null and prefer_pass and _ai_pass_cd <= 0.0 and not fake_active:
		if _ai_try_pass(pass_target):
			return Vector3.ZERO
	# Last-chance release so possessions end in a shot or turnover, not a stall.
	if match_ball != null and force_release and not fake_active:
		if pass_target != null and _ai_pass_cd <= 0.0 and _ai_try_pass(pass_target):
			return Vector3.ZERO
		if _ai_try_shoot_at_goal(dist, nine_m or dist <= AI_SHOOT_RANGE):
			return Vector3.ZERO
	# Wave 5/6: role drive + man drive-and-kick / zone 9 m belt.
	var approach := Formations.attack_drive_for_style(self, me)
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
	var opponents := _ai_opponent_roster()
	var under_pressure := _ai_under_pressure()
	# Wave 6 + credibility: open lanes / pressure outlets / Kempa jumpers.
	var best: Player = null
	var best_score := -INF
	for mate in roster:
		if mate == null or mate == self or not (mate is Player):
			continue
		var recv := mate as Player
		if recv.is_goalkeeper or recv.match_frozen or recv.excluded or recv.on_bench:
			continue
		var score := PassCraft.score_in_cone(self, recv, face, team_id)
		if score <= -INF:
			continue
		var openness := Formations.pass_lane_openness(
			global_position, recv.global_position, opponents
		)
		score += openness * 2.4
		# Core-loop feel: punish back-passes so attacks advance or end.
		var attack_sign := 1.0 if team_id == 0 else -1.0
		var toward := (recv.global_position.z - global_position.z) * attack_sign
		if toward < -1.2:
			score -= 4.8
		elif toward > 1.0:
			score += 1.6
		# Under mark: prefer clear forward/side outlets over contested holds.
		if under_pressure:
			if openness < AI_PRESSURE_LANE_MIN:
				score -= 4.5
			else:
				score += openness * 2.2
			if _ai_pass_is_side_outlet(recv) and openness >= AI_PRESSURE_LANE_MIN:
				score += 2.4
			if toward > 0.5 and openness >= AI_PRESSURE_LANE_MIN:
				score += 1.8
		# R4.6a: vs man, strongly prefer clear lanes over contested ones.
		if Formations.facing_defense_of(self) == Formations.DefenseShape.INDIVIDUAL:
			if openness < 0.35:
				score -= 3.5
			else:
				score += openness * 1.6
		# R4.8: feed an airborne jumper near the crease.
		var jumper_air := not recv.is_on_floor() or recv.jump_shot_active
		if Formations.kempa_eligible(recv, jumper_air):
			score += 5.5
		elif Formations.kempa_near_crease(recv) and jumper_air:
			score += 3.0
		if not recv.controlled:
			score += 0.3
		if score > best_score:
			best_score = score
			best = recv
	return best


func _ai_try_pass(target: Player) -> bool:
	if match_ball == null or target == null:
		return false
	var face := face_direction()
	if try_pass_to(target, match_ball, -1.0, face):
		_ai_pass_cd = AI_PASS_COOLDOWN
		_ai_shoot_cd = 0.35
		_ai_reset_possession_tracking()
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
		_ai_reset_possession_tracking()
		begin_catch_settle()
		possession_changed.emit(true)
		# Wave 6 R4.8: airborne catch near crease → Kempa redirect (readable, not teleport).
		_try_kempa_after_catch()


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
			_ai_reset_possession_tracking()
			begin_catch_settle()
			if is_goalkeeper and _should_arm_outlet_from_ball(ball):
				arm_outlet_pass()
			possession_changed.emit(true)
			_try_kempa_after_catch()


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
	# Never teleport-steal a held ball — contests are free-ball tip windows only.
	if ball.carrier != null:
		return
	if ball._last_carrier != null and ball._last_carrier.team_id == team_id:
		return
	# Readable contest window: fresh shot / pass age, or fast free ball.
	var age_ms := 0
	var age_ok := true
	if ball.last_shot_meta.has("time_msec"):
		age_ms = Time.get_ticks_msec() - int(ball.last_shot_meta["time_msec"])
		var age_limit := CONTEST_PASS_AGE_MS if ball.is_pass_in_flight() else CONTEST_SHOT_AGE_MS
		age_ok = age_ms < age_limit
	var speed := ball.linear_velocity.length()
	if not age_ok and speed < 7.0:
		return
	# Passes can be tipped a bit slower than shots while still in the window.
	if ball.is_pass_in_flight() and not age_ok and speed < 5.0:
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
			_ai_reset_possession_tracking()
			begin_catch_settle()
			if is_save:
				_begin_gk_catch_pose()
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
			_ai_reset_possession_tracking()
			begin_catch_settle()
			_begin_gk_catch_pose()
			arm_outlet_pass()
			possession_changed.emit(true)
			block_attempted.emit(self, ball, true)
			return
	if is_save:
		_begin_gk_deflect_pose()
	ball.linear_velocity = away * deflect_speed + Vector3(0.0, up, 0.0)
	ball.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0), randf_range(-8.0, 8.0))
	block_attempted.emit(self, ball, success)
	# Short cooldown so one contact doesn't spam.
	if is_goalkeeper:
		_pickup_block = 0.12
	else:
		_block_timer = 0.08
		block_ready = false


func _begin_gk_catch_pose() -> void:
	if not is_goalkeeper:
		return
	last_save_caught = true
	gk_stance = GkMotion.Stance.CATCH
	_gk_pose_timer = GkMotion.CATCH_POSE_S
	_gk_pose_cache = GkMotion.pose_catch()
	_apply_save_box_from_pose(_gk_pose_cache)
	save_resolved.emit(true)


func _begin_gk_deflect_pose() -> void:
	if not is_goalkeeper:
		return
	last_save_caught = false
	gk_stance = GkMotion.Stance.DEFLECT
	_gk_pose_timer = GkMotion.DEFLECT_POSE_S
	var side := dive_side if dive_side != GkMotion.DiveSide.NONE else GkMotion.DiveSide.RIGHT
	if match_ball:
		side = (
			GkMotion.DiveSide.LEFT
			if match_ball.global_position.x < global_position.x
			else GkMotion.DiveSide.RIGHT
		)
	_gk_pose_cache = GkMotion.pose_deflect(side)
	_apply_save_box_from_pose(_gk_pose_cache)
	save_resolved.emit(false)


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


## Live head center for shoot-cam close-up (falls back to rest height).
func head_world_position() -> Vector3:
	if _head != null and is_instance_valid(_head):
		return _head.global_position
	var region := get_head_region()
	if region != null and is_instance_valid(region):
		return region.global_position
	return global_position + Vector3(0.0, 1.78, 0.0)


## Independent upper-body yaw vs feet (Wave 2 pass/shoot windup).
func set_torso_yaw_offset(yaw: float) -> void:
	_torso_yaw_offset = yaw


func get_torso_yaw_offset() -> float:
	return _torso_yaw_offset


## MatchController drives charge pose while shoot is held.
func set_shot_charge_motion(charge: float, lob: bool, aim: Vector3 = Vector3.ZERO) -> void:
	if on_bench or excluded or diving:
		return
	throw_charge = clampf(charge, 0.0, 1.0)
	throw_lob = lob
	throw_wing = ThrowMotion.is_wing_finish_context(self)
	if aim.length_squared() > 0.01:
		throw_aim_dir = aim
	elif throw_aim_dir.length_squared() < 0.01:
		throw_aim_dir = opponent_goal_point() - global_position
	_torso_yaw_offset = ThrowMotion.torso_yaw_toward(face_direction(), throw_aim_dir)
	if throw_wing and not is_on_floor():
		throw_action = ThrowMotion.Action.WING_SHOT
	elif jump_shot_active or not is_on_floor():
		throw_action = ThrowMotion.Action.JUMP_SHOT if not throw_wing else ThrowMotion.Action.WING_SHOT
	elif throw_wing:
		throw_action = ThrowMotion.Action.WING_SHOT
	else:
		throw_action = ThrowMotion.Action.SHOOT
	throw_phase = ThrowMotion.Phase.CHARGE
	throw_t = 0.0
	throw_motion_active = true
	_throw_pose_cache = ThrowMotion.pose_shot_charge(
		throw_charge, throw_lob, _torso_yaw_offset, throw_wing
	)


func clear_shot_charge_motion() -> void:
	if throw_phase == ThrowMotion.Phase.CHARGE:
		clear_throw_motion()


func clear_throw_motion() -> void:
	throw_action = ThrowMotion.Action.NONE
	throw_phase = ThrowMotion.Phase.IDLE
	throw_t = 0.0
	throw_pass_type = PassCraft.PassType.FLAT
	throw_charge = 0.0
	throw_lob = false
	throw_wing = false
	throw_motion_active = false
	_throw_pose_cache = {}
	_torso_yaw_offset = 0.0


func _begin_land_pose() -> void:
	throw_action = ThrowMotion.Action.JUMP_SHOT
	throw_phase = ThrowMotion.Phase.LAND
	throw_t = 0.0
	throw_motion_active = true
	# Land plant: bias weight onto the pivot / preferred catch foot (R1.7 / R2.8).
	if has_ball and not dribbling and not is_goalkeeper:
		if pivot_foot == PIVOT_NONE:
			pivot_foot = preferred_catch_pivot_foot()
	_throw_pose_cache = ThrowMotion.pose_land(_torso_yaw_offset, pivot_foot)


func _begin_throw_from_release(
	aim_dir: Vector3,
	shot_meta: Dictionary,
	is_pass: bool,
	wing: bool
) -> void:
	throw_aim_dir = aim_dir
	throw_lob = bool(shot_meta.get("lob", false))
	throw_charge = float(shot_meta.get("charge", throw_charge))
	throw_pass_type = int(shot_meta.get("pass_type", PassCraft.PassType.FLAT))
	throw_wing = wing
	_torso_yaw_offset = ThrowMotion.torso_yaw_toward(face_direction(), aim_dir)
	var airborne := (not is_on_floor()) or jump_shot_active
	if is_pass:
		throw_action = ThrowMotion.Action.JUMP_PASS if airborne else ThrowMotion.Action.PASS
		throw_phase = ThrowMotion.Phase.WINDUP
		# Jump pass leaves jump-shot craft; land is owned by the throw sequence.
		if airborne:
			jump_shot_active = false
			_js_plant_t = 0.0
	elif wing:
		throw_action = ThrowMotion.Action.WING_SHOT
		throw_phase = ThrowMotion.Phase.RELEASE
		if airborne:
			jump_shot_active = false
			_js_plant_t = 0.0
	elif airborne:
		throw_action = ThrowMotion.Action.JUMP_SHOT
		throw_phase = ThrowMotion.Phase.RELEASE
		jump_shot_active = false
		_js_plant_t = 0.0
	else:
		throw_action = ThrowMotion.Action.SHOOT
		throw_phase = ThrowMotion.Phase.RELEASE
	throw_t = 0.0
	throw_motion_active = true
	# Seed first pose so the same frame reads as windup / release.
	var seeded := ThrowMotion.tick_throw_sequence(
		throw_action, throw_phase, 0.0, 0.0,
		throw_pass_type, throw_charge, throw_lob, throw_wing, _torso_yaw_offset
	)
	_throw_pose_cache = seeded["pose"]


func _tick_throw_motion(delta: float) -> void:
	if not throw_motion_active or on_bench or excluded or diving:
		return
	if throw_phase == ThrowMotion.Phase.CHARGE:
		# Held charge — pose refreshed in apply from charge fields.
		_throw_pose_cache = ThrowMotion.pose_shot_charge(
			throw_charge, throw_lob,
			ThrowMotion.torso_yaw_toward(face_direction(), throw_aim_dir),
			throw_wing
		)
		return
	var yaw := ThrowMotion.torso_yaw_toward(face_direction(), throw_aim_dir)
	_torso_yaw_offset = yaw
	var stepped := ThrowMotion.tick_throw_sequence(
		throw_action,
		throw_phase,
		throw_t,
		delta,
		throw_pass_type,
		throw_charge,
		throw_lob,
		throw_wing,
		yaw
	)
	throw_phase = int(stepped["phase"])
	throw_t = float(stepped["t"])
	_throw_pose_cache = stepped["pose"]
	if bool(stepped["done"]):
		_apply_pose_dict(stepped["pose"] as Dictionary, 1.0)
		clear_throw_motion()


func _apply_throw_pose(delta: float) -> void:
	if on_bench or excluded or diving or _arm_r == null or fake_active:
		return
	var blend := 1.0 - exp(-16.0 * delta)
	if throw_motion_active and not _throw_pose_cache.is_empty():
		_apply_pose_dict(_throw_pose_cache, blend)
		return
	if jump_shot_active and has_ball:
		# Pre-release jump craft: approach / plant / air cock.
		throw_wing = throw_wing or ThrowMotion.is_wing_finish_context(self)
		var pose := ThrowMotion.pose_for_jump_craft(
			jump_shot_phase,
			ThrowMotion.torso_yaw_toward(face_direction(), opponent_goal_point() - global_position),
			throw_wing,
			false
		)
		_torso_yaw_offset = float(pose.get("torso_yaw", 0.0))
		_apply_pose_dict(pose, blend)


func _apply_pose_dict(pose: Dictionary, blend: float) -> void:
	if _arm_l == null or _arm_r == null:
		return
	_arm_l.position = _arm_l.position.lerp(pose["arm_l_pos"] as Vector3, blend)
	_arm_r.position = _arm_r.position.lerp(pose["arm_r_pos"] as Vector3, blend)
	var al_rot := pose["arm_l_rot"] as Vector3
	var ar_rot := pose["arm_r_rot"] as Vector3
	_arm_l.rotation_degrees = _arm_l.rotation_degrees.lerp(al_rot, blend)
	_arm_r.rotation_degrees = _arm_r.rotation_degrees.lerp(ar_rot, blend)
	if _hand_l and _hand_r:
		_hand_l.position = _hand_l.position.lerp(pose["hand_l_pos"] as Vector3, blend)
		_hand_r.position = _hand_r.position.lerp(pose["hand_r_pos"] as Vector3, blend)
	_torso_yaw_offset = float(pose.get("torso_yaw", _torso_yaw_offset))
	if _upper_body:
		var pitch := float(pose.get("torso_pitch", 0.0))
		_upper_body.rotation.x = lerpf(_upper_body.rotation.x, pitch, blend)
		var y_off := float(pose.get("upper_y_off", 0.0))
		_upper_body.position.y = lerpf(_upper_body.position.y, _upper_base_y + y_off, blend)
	if _leg_l and _leg_r and pose.has("leg_l_x"):
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, float(pose["leg_l_x"]), blend)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, float(pose["leg_r_x"]), blend)
	if _leg_l and pose.has("leg_l_z"):
		_leg_l.rotation.z = lerpf(_leg_l.rotation.z, float(pose["leg_l_z"]), blend)
	if _leg_r and pose.has("leg_r_z"):
		_leg_r.rotation.z = lerpf(_leg_r.rotation.z, float(pose["leg_r_z"]), blend)


func is_throw_motion_busy() -> bool:
	return throw_motion_active and throw_phase != ThrowMotion.Phase.IDLE


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
		var pose := GkMotion.pose_dive(dive_side, dive_height)
		_gk_pose_cache = pose
		gk_stance = GkMotion.Stance.DIVE
		_apply_pose_dict(pose, 1.0)
		_apply_save_box_from_pose(pose)
	else:
		_pose_arms_rest()
		if is_goalkeeper:
			gk_stance = GkMotion.Stance.SET
			_gk_pose_cache = GkMotion.pose_set()
			_apply_save_box_from_pose(_gk_pose_cache)
		else:
			_apply_save_box_size(Vector3(1.8, 1.6, 1.1))


func _apply_save_box_from_pose(pose: Dictionary) -> void:
	if pose.has("save_box"):
		_apply_save_box_size(pose["save_box"] as Vector3)


func _apply_save_box_size(size: Vector3) -> void:
	if _save_area == null or _save_area.get_child_count() == 0:
		return
	var shape := _save_area.get_child(0) as CollisionShape3D
	if shape and shape.shape is BoxShape3D:
		(shape.shape as BoxShape3D).size = size


func _update_gk_stance(wish: Vector3, speed_hint: float) -> void:
	if not is_goalkeeper or on_bench or excluded or diving:
		return
	if gk_stance in [GkMotion.Stance.CATCH, GkMotion.Stance.DEFLECT, GkMotion.Stance.OUTLET]:
		if _gk_pose_timer > 0.0:
			return
	# Holding after save / with ball → set or outlet already armed.
	if has_ball:
		if _outlet_pending:
			gk_stance = GkMotion.Stance.OUTLET
		else:
			gk_stance = GkMotion.Stance.SET
			_gk_pose_cache = GkMotion.pose_set()
		return
	var lateral := absf(wish.x) > 0.12 or absf(velocity.x) > 1.1
	if lateral and speed_hint > 0.8:
		gk_stance = GkMotion.Stance.SHUFFLE
		var side := wish.x
		if absf(side) < 0.05:
			side = velocity.x
		_gk_pose_cache = GkMotion.pose_shuffle(side)
	else:
		gk_stance = GkMotion.Stance.SET
		_gk_pose_cache = GkMotion.pose_set()
	_apply_save_box_from_pose(_gk_pose_cache)


func _apply_gk_pose(delta: float) -> void:
	if not is_goalkeeper or on_bench or excluded:
		return
	if throw_motion_active or fake_active:
		return
	if _gk_pose_cache.is_empty():
		return
	# Dive pose already applied hard; still refresh while diving.
	if diving or gk_stance != GkMotion.Stance.IDLE:
		var blend := 1.0 - exp(-14.0 * delta)
		_apply_pose_dict(_gk_pose_cache, blend)


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
	# Wave 2/3 throw / fake / GK craft owns the arms while active.
	if throw_motion_active or fake_active or (jump_shot_active and has_ball):
		return
	if is_goalkeeper and gk_stance != GkMotion.Stance.IDLE:
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

	_shoe_mat_l = StandardMaterial3D.new()
	_shoe_mat_l.albedo_color = FREE_SHOE
	_shoe_mat_l.roughness = 0.6
	_shoe_mat_r = StandardMaterial3D.new()
	_shoe_mat_r.albedo_color = FREE_SHOE
	_shoe_mat_r.roughness = 0.6
	var shoe_l := find_child("ShoeL", true, false) as MeshInstance3D
	var shoe_r := find_child("ShoeR", true, false) as MeshInstance3D
	if shoe_l:
		shoe_l.material_override = _shoe_mat_l
	if shoe_r:
		shoe_r.material_override = _shoe_mat_r
	_ensure_pivot_ring()
	_refresh_pivot_shoe_mats()
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
	# Throw / fake / jump / GK craft owns arms, torso settle, and plant legs.
	# Catch settle still lets pivot plant pose own the legs below.
	if throw_motion_active or fake_active or (jump_shot_active and has_ball):
		return
	if is_goalkeeper and gk_stance != GkMotion.Stance.IDLE:
		return
	# Holding without dribble: pivot plant pose owns legs (R1.6 teaching).
	if has_ball and not dribbling and pivot_foot != PIVOT_NONE and not is_goalkeeper:
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


## Pivot foot planted vs free foot lifted / swinging while holding (R1.6 / R1.7).
func _apply_pivot_plant_visual(delta: float, speed: float) -> void:
	_refresh_pivot_shoe_mats()
	_update_pivot_ring(delta)
	if on_bench or excluded or diving or is_goalkeeper:
		return
	if not has_ball or dribbling or pivot_foot == PIVOT_NONE:
		return
	if throw_motion_active or fake_active or (jump_shot_active and has_ball and _js_plant_t <= 0.0):
		# Jump plant still reads pivot; other throw/fake owns legs.
		if not (jump_shot_active and _js_plant_t > 0.0):
			return
	if _leg_l == null or _leg_r == null:
		return

	var blend := 1.0 - exp(-14.0 * delta)
	var settling := _catch_settle_t > 0.0
	var planting := _js_plant_t > 0.0
	var pivoting := speed < 0.85 or settling or planting
	var plant_x := 0.08 if settling or planting else 0.02
	var free_lift := 0.55 if settling else (0.42 if pivoting else 0.0)
	var free_swing := 0.0
	if not pivoting and speed > 0.8:
		_bob_phase += delta * BOB_SPEED * clampf(speed / SPEED, 0.45, 1.25)
		free_swing = sin(_bob_phase) * JOG_LEG_SWING * 0.85
		free_lift = maxf(0.18, absf(free_swing) * 0.35)

	var pivot_is_left := pivot_foot == PIVOT_LEFT
	if pivot_is_left:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, plant_x, blend)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -free_lift + free_swing, blend)
	else:
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, plant_x, blend)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -free_lift - free_swing, blend)

	if _upper_body and (settling or planting):
		var crouch := -0.06 if settling else -0.04
		_upper_body.position.y = lerpf(_upper_body.position.y, _upper_base_y + crouch, blend)


func _flash_catch_plant_pose() -> void:
	if _leg_l == null or _leg_r == null or is_goalkeeper:
		return
	var pivot_is_left := pivot_foot == PIVOT_LEFT
	if pivot_is_left:
		_leg_l.rotation.x = 0.12
		_leg_r.rotation.x = -0.62
	else:
		_leg_r.rotation.x = 0.12
		_leg_l.rotation.x = -0.62
	if _upper_body:
		_upper_body.position.y = _upper_base_y - 0.07
	_refresh_pivot_shoe_mats()


func _refresh_pivot_shoe_mats() -> void:
	if _shoe_mat_l == null or _shoe_mat_r == null:
		return
	var show_pivot := (
		has_ball
		and not dribbling
		and not is_goalkeeper
		and not on_bench
		and not excluded
		and pivot_foot != PIVOT_NONE
	)
	if not show_pivot:
		_shoe_mat_l.albedo_color = FREE_SHOE
		_shoe_mat_r.albedo_color = FREE_SHOE
		_shoe_mat_l.emission_enabled = false
		_shoe_mat_r.emission_enabled = false
		return
	var pivot_is_left := pivot_foot == PIVOT_LEFT
	_shoe_mat_l.albedo_color = PIVOT_SHOE if pivot_is_left else FREE_SHOE
	_shoe_mat_r.albedo_color = PIVOT_SHOE if not pivot_is_left else FREE_SHOE
	_shoe_mat_l.emission_enabled = pivot_is_left
	_shoe_mat_r.emission_enabled = not pivot_is_left
	if pivot_is_left:
		_shoe_mat_l.emission = PIVOT_SHOE
		_shoe_mat_l.emission_energy_multiplier = 0.55
	else:
		_shoe_mat_r.emission = PIVOT_SHOE
		_shoe_mat_r.emission_energy_multiplier = 0.55


func _ensure_pivot_ring() -> void:
	if _pivot_ring != null and is_instance_valid(_pivot_ring):
		return
	_pivot_ring = MeshInstance3D.new()
	_pivot_ring.name = "PivotRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.22
	cyl.height = 0.02
	cyl.radial_segments = 16
	_pivot_ring.mesh = cyl
	_pivot_ring_mat = StandardMaterial3D.new()
	_pivot_ring_mat.albedo_color = PIVOT_RING_COLOR
	_pivot_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pivot_ring_mat.emission_enabled = true
	_pivot_ring_mat.emission = Color(0.95, 0.7, 0.2)
	_pivot_ring_mat.emission_energy_multiplier = 0.4
	_pivot_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pivot_ring.material_override = _pivot_ring_mat
	_pivot_ring.visible = false
	add_child(_pivot_ring)


func _update_pivot_ring(_delta: float) -> void:
	_ensure_pivot_ring()
	var show_ring := (
		has_ball
		and not dribbling
		and not is_goalkeeper
		and not on_bench
		and not excluded
		and pivot_foot != PIVOT_NONE
		and (is_on_floor() or global_position.y < 0.25)
	)
	_pivot_ring.visible = show_ring
	if not show_ring:
		return
	var shoe_name := "ShoeL" if pivot_foot == PIVOT_LEFT else "ShoeR"
	var shoe := find_child(shoe_name, true, false) as Node3D
	if shoe == null:
		_pivot_ring.visible = false
		return
	var sole := shoe.global_position
	_pivot_ring.global_position = Vector3(sole.x, 0.012, sole.z)
	_pivot_ring.global_rotation = Vector3.ZERO


func _pose_hands_from_arms() -> void:
	if _hand_l == null or _hand_r == null or _arm_l == null or _arm_r == null:
		return
	# Hands track roughly past the forearm tips while jogging.
	_hand_l.position = _arm_l.position + Vector3(-0.18, -0.08, 0.06)
	_hand_r.position = _arm_r.position + Vector3(0.18, -0.08, 0.06)
