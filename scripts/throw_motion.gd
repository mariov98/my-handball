extends RefCounted
class_name ThrowMotion

## Wave 2 procedural throw / jump poses for the modular body (arms, hands, torso, feet).
## Gameplay release stays on existing pass/shoot paths — this drives readable motion.

enum Action {
	NONE = 0,
	PASS = 1,
	SHOOT = 2,
	JUMP_PASS = 3,
	JUMP_SHOT = 4,
	WING_SHOT = 5,
}

enum Phase {
	IDLE = 0,
	WINDUP = 1,
	CHARGE = 2,
	RELEASE = 3,
	FOLLOW = 4,
	LAND = 5,
	APPROACH = 6,
	PLANT = 7,
	AIR = 8,
}

## Standing / moving pass — windup → release → follow (weightier gather / follow-through).
const PASS_WINDUP_S := 0.14
const PASS_RELEASE_S := 0.08
const PASS_FOLLOW_S := 0.32

## Grounded shot release after charge.
const SHOT_RELEASE_S := 0.11
const SHOT_FOLLOW_S := 0.38

## Jump pass / jump shot land settle.
const LAND_S := 0.28

## Wing corridor: wide X near the attacking goal-area.
const WING_X_MIN := 5.4
const WING_GOAL_DEPTH := 11.5
const WING_AIM_BLEND := 0.42
## Local copies of court meters — avoid class_name cycles with Court/Player.
const _HALF_LENGTH := 20.0
const _GOAL_WIDTH := 3.0
## Pass type ints mirror PassCraft.PassType (FLAT/BOUNCE/LOB) without a hard dep at parse.
const _PASS_FLAT := 0
const _PASS_BOUNCE := 1
const _PASS_LOB := 2
## Jump phase ints mirror ShotCraft.JumpPhase.
const _JP_APPROACH := 1
const _JP_PLANTED := 2
const _JP_AIRBORNE := 3
const _JP_WINDOW := 4


static func action_name(action: int) -> String:
	match action:
		Action.PASS:
			return "PASS"
		Action.SHOOT:
			return "SHOOT"
		Action.JUMP_PASS:
			return "JUMP_PASS"
		Action.JUMP_SHOT:
			return "JUMP_SHOT"
		Action.WING_SHOT:
			return "WING_SHOT"
		_:
			return "NONE"


static func phase_name(phase: int) -> String:
	match phase:
		Phase.WINDUP:
			return "WINDUP"
		Phase.CHARGE:
			return "CHARGE"
		Phase.RELEASE:
			return "RELEASE"
		Phase.FOLLOW:
			return "FOLLOW"
		Phase.LAND:
			return "LAND"
		Phase.APPROACH:
			return "APPROACH"
		Phase.PLANT:
			return "PLANT"
		Phase.AIR:
			return "AIR"
		_:
			return "IDLE"


## World planar yaw offset (radians) so UpperBody faces `aim` relative to root facing.
static func torso_yaw_toward(root_forward: Vector3, aim: Vector3) -> float:
	var face := Vector3(root_forward.x, 0.0, root_forward.z)
	var to := Vector3(aim.x, 0.0, aim.z)
	if face.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return 0.0
	var from_yaw := atan2(face.x, face.z)
	var to_yaw := atan2(to.x, to.z)
	return clampf(angle_difference(from_yaw, to_yaw), -1.15, 1.15)


## True when the shooter is finishing from a wide wing corridor toward goal.
## Duck-types team_id / is_goalkeeper / player_index — no Player class_name dep (avoids cycles).
static func is_wing_finish_context(body: CharacterBody3D) -> bool:
	if body == null:
		return false
	if body.get("is_goalkeeper") == true:
		return false
	var team_raw: Variant = body.get("team_id")
	var team_id := int(team_raw) if team_raw != null else 0
	var pos: Vector3 = body.global_position
	var attack_sign := 1.0 if team_id == 0 else -1.0
	var goal_z := _HALF_LENGTH * attack_sign
	var depth_to_goal := (goal_z - pos.z) * attack_sign
	if depth_to_goal < 0.5 or depth_to_goal > WING_GOAL_DEPTH:
		return false
	if absf(pos.x) < WING_X_MIN:
		return false
	# Roster wings are indices 1 (LW) / 5 (RW); others need to be clearly wide.
	var idx_raw: Variant = body.get("player_index")
	var idx := int(idx_raw) if idx_raw != null else -1
	var role_wing := idx == 1 or idx == 5
	return role_wing or absf(pos.x) >= 6.6


## Mild aim assist: open the body toward the goal mouth (near/far post from the wing).
static func wing_aim_assist(body: CharacterBody3D, aim: Vector3) -> Vector3:
	if body == null:
		return aim
	var team_raw: Variant = body.get("team_id")
	var team_id := int(team_raw) if team_raw != null else 0
	var attack_sign := 1.0 if team_id == 0 else -1.0
	var goal_z := _HALF_LENGTH * attack_sign
	var pos: Vector3 = body.global_position
	# Near post = post on the wing's side; far post opposite — bias slightly far for spectacle.
	var side := signf(pos.x)
	if absf(side) < 0.01:
		side = 1.0
	var near_post_x := side * (_GOAL_WIDTH * 0.42)
	var far_post_x := -side * (_GOAL_WIDTH * 0.38)
	var target_x := lerpf(near_post_x, far_post_x, 0.55)
	var to_goal := Vector3(target_x - pos.x, 0.55, goal_z - pos.z)
	if to_goal.length_squared() < 0.01:
		return aim
	to_goal = to_goal.normalized()
	var base := aim
	if base.length_squared() < 0.01:
		base = to_goal
	else:
		base = base.normalized()
	return base.lerp(to_goal, WING_AIM_BLEND).normalized()


## Rest arms (matches Player._pose_arms_rest outfield).
static func pose_rest() -> Dictionary:
	return {
		"arm_l_pos": Vector3(-0.40, 1.22, 0.02),
		"arm_r_pos": Vector3(0.40, 1.22, 0.02),
		"arm_l_rot": Vector3(0, 0, 0),
		"arm_r_rot": Vector3(0, 0, 0),
		"hand_l_pos": Vector3(-0.58, 1.12, 0.08),
		"hand_r_pos": Vector3(0.58, 1.12, 0.08),
		"torso_yaw": 0.0,
		"torso_pitch": 0.0,
		"leg_l_x": 0.0,
		"leg_r_x": 0.0,
		"upper_y_off": 0.0,
	}


static func pose_pass_windup(pass_type: int, torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw
	p["torso_pitch"] = -0.06
	# Cock throwing arm behind the ear; left hand guides.
	match pass_type:
		_PASS_LOB:
			p["arm_r_pos"] = Vector3(0.52, 1.55, -0.22)
			p["arm_r_rot"] = Vector3(-95, 25, -35)
			p["hand_r_pos"] = Vector3(0.62, 1.78, -0.38)
			p["arm_l_pos"] = Vector3(-0.42, 1.35, 0.18)
			p["arm_l_rot"] = Vector3(-40, -10, 15)
			p["hand_l_pos"] = Vector3(-0.48, 1.48, 0.32)
		_PASS_BOUNCE:
			p["arm_r_pos"] = Vector3(0.48, 1.28, -0.18)
			p["arm_r_rot"] = Vector3(-55, 20, -20)
			p["hand_r_pos"] = Vector3(0.58, 1.38, -0.28)
			p["arm_l_pos"] = Vector3(-0.38, 1.15, 0.12)
			p["arm_l_rot"] = Vector3(-25, 0, 10)
			p["hand_l_pos"] = Vector3(-0.45, 1.05, 0.22)
			p["torso_pitch"] = 0.08
		_:
			# Flat
			p["arm_r_pos"] = Vector3(0.50, 1.42, -0.20)
			p["arm_r_rot"] = Vector3(-75, 22, -28)
			p["hand_r_pos"] = Vector3(0.60, 1.58, -0.34)
			p["arm_l_pos"] = Vector3(-0.40, 1.28, 0.16)
			p["arm_l_rot"] = Vector3(-35, -8, 12)
			p["hand_l_pos"] = Vector3(-0.46, 1.35, 0.28)
	return p


static func pose_pass_release(pass_type: int, torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.85
	p["torso_pitch"] = -0.02
	match pass_type:
		_PASS_LOB:
			p["arm_r_pos"] = Vector3(0.38, 1.62, 0.28)
			p["arm_r_rot"] = Vector3(-110, -5, -10)
			p["hand_r_pos"] = Vector3(0.42, 1.88, 0.42)
		_PASS_BOUNCE:
			p["arm_r_pos"] = Vector3(0.36, 1.05, 0.32)
			p["arm_r_rot"] = Vector3(-20, -15, -8)
			p["hand_r_pos"] = Vector3(0.40, 0.88, 0.48)
			p["torso_pitch"] = 0.12
		_:
			p["arm_r_pos"] = Vector3(0.36, 1.38, 0.38)
			p["arm_r_rot"] = Vector3(-55, -18, -5)
			p["hand_r_pos"] = Vector3(0.40, 1.42, 0.55)
	p["arm_l_pos"] = Vector3(-0.36, 1.22, 0.10)
	p["arm_l_rot"] = Vector3(-20, 0, 8)
	p["hand_l_pos"] = Vector3(-0.42, 1.18, 0.22)
	return p


static func pose_pass_follow(pass_type: int, torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.35
	match pass_type:
		_PASS_LOB:
			p["arm_r_pos"] = Vector3(0.28, 1.48, 0.42)
			p["arm_r_rot"] = Vector3(-70, -30, 5)
			p["hand_r_pos"] = Vector3(0.30, 1.55, 0.62)
		_PASS_BOUNCE:
			p["arm_r_pos"] = Vector3(0.30, 0.95, 0.38)
			p["arm_r_rot"] = Vector3(15, -20, -5)
			p["hand_r_pos"] = Vector3(0.32, 0.78, 0.52)
		_:
			p["arm_r_pos"] = Vector3(0.28, 1.25, 0.48)
			p["arm_r_rot"] = Vector3(-25, -35, 8)
			p["hand_r_pos"] = Vector3(0.28, 1.22, 0.68)
	p["arm_l_pos"] = Vector3(-0.38, 1.18, 0.05)
	p["hand_l_pos"] = Vector3(-0.45, 1.10, 0.12)
	return p


## Charge pose scales with hold 0–1; lob lifts the arm path.
static func pose_shot_charge(charge: float, lob: bool, torso_yaw: float, wing: bool) -> Dictionary:
	var t := clampf(charge, 0.0, 1.0)
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw
	p["torso_pitch"] = lerpf(0.0, -0.10, t)
	var cock_y := lerpf(1.32, 1.58, t)
	var cock_z := lerpf(-0.08, -0.28, t)
	if lob:
		cock_y = lerpf(1.40, 1.72, t)
		cock_z = lerpf(-0.12, -0.34, t)
		p["arm_r_rot"] = Vector3(lerpf(-40, -105, t), lerpf(10, 28, t), lerpf(-12, -40, t))
	else:
		p["arm_r_rot"] = Vector3(lerpf(-30, -88, t), lerpf(8, 24, t), lerpf(-10, -32, t))
	p["arm_r_pos"] = Vector3(lerpf(0.42, 0.55, t), cock_y, cock_z)
	p["hand_r_pos"] = Vector3(
		lerpf(0.55, 0.68, t),
		lerpf(1.28, cock_y + 0.28, t),
		lerpf(-0.05, cock_z - 0.18, t)
	)
	p["arm_l_pos"] = Vector3(-0.38, lerpf(1.22, 1.40, t), lerpf(0.05, 0.22, t))
	p["arm_l_rot"] = Vector3(lerpf(0, -45, t), 0, 10)
	p["hand_l_pos"] = Vector3(-0.45, lerpf(1.15, 1.48, t), lerpf(0.10, 0.38, t))
	if wing:
		# Open the body toward goal; plant the outside foot.
		p["torso_yaw"] = torso_yaw + signf(torso_yaw + 0.001) * 0.25
		p["leg_l_x"] = -0.35 if torso_yaw >= 0.0 else 0.15
		p["leg_r_x"] = 0.15 if torso_yaw >= 0.0 else -0.35
		p["torso_pitch"] = lerpf(0.0, -0.06, t)
	return p


static func pose_shot_release(lob: bool, torso_yaw: float, wing: bool, jump: bool) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.9
	if lob:
		p["arm_r_pos"] = Vector3(0.32, 1.72, 0.35)
		p["arm_r_rot"] = Vector3(-125, -8, -5)
		p["hand_r_pos"] = Vector3(0.34, 2.02, 0.48)
		p["torso_pitch"] = -0.12
	elif wing:
		# Wing finish — arm sweeps across the body toward the far post.
		p["arm_r_pos"] = Vector3(0.15, 1.48, 0.45)
		p["arm_r_rot"] = Vector3(-70, -55, 15)
		p["hand_r_pos"] = Vector3(0.05, 1.55, 0.68)
		p["torso_yaw"] = torso_yaw
		p["torso_pitch"] = -0.04
		p["leg_l_x"] = -0.45
		p["leg_r_x"] = 0.25
	else:
		p["arm_r_pos"] = Vector3(0.30, 1.45, 0.42)
		p["arm_r_rot"] = Vector3(-70, -22, -5)
		p["hand_r_pos"] = Vector3(0.32, 1.52, 0.62)
	if jump:
		p["upper_y_off"] = 0.02
		p["leg_l_x"] = -0.55
		p["leg_r_x"] = 0.35
	p["arm_l_pos"] = Vector3(-0.42, 1.30, 0.18)
	p["arm_l_rot"] = Vector3(-30, 5, 12)
	p["hand_l_pos"] = Vector3(-0.48, 1.38, 0.32)
	return p


static func pose_shot_follow(lob: bool, torso_yaw: float, wing: bool) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.3
	if lob:
		p["arm_r_pos"] = Vector3(0.22, 1.55, 0.48)
		p["arm_r_rot"] = Vector3(-85, -40, 10)
		p["hand_r_pos"] = Vector3(0.18, 1.62, 0.70)
	elif wing:
		p["arm_r_pos"] = Vector3(-0.05, 1.32, 0.50)
		p["arm_r_rot"] = Vector3(-35, -70, 20)
		p["hand_r_pos"] = Vector3(-0.22, 1.28, 0.68)
		p["leg_l_x"] = -0.25
		p["leg_r_x"] = 0.15
	else:
		p["arm_r_pos"] = Vector3(0.20, 1.28, 0.52)
		p["arm_r_rot"] = Vector3(-30, -45, 12)
		p["hand_r_pos"] = Vector3(0.15, 1.22, 0.72)
	p["arm_l_pos"] = Vector3(-0.38, 1.18, 0.08)
	p["hand_l_pos"] = Vector3(-0.45, 1.10, 0.15)
	return p


static func pose_jump_approach(torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.4
	p["torso_pitch"] = 0.06
	p["arm_r_pos"] = Vector3(0.45, 1.35, -0.08)
	p["arm_r_rot"] = Vector3(-40, 12, -15)
	p["hand_r_pos"] = Vector3(0.55, 1.40, -0.15)
	p["leg_l_x"] = 0.45
	p["leg_r_x"] = -0.55
	p["upper_y_off"] = -0.04
	return p


static func pose_jump_plant(torso_yaw: float, wing: bool) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.55
	p["torso_pitch"] = 0.10
	p["arm_r_pos"] = Vector3(0.48, 1.40, -0.16)
	p["arm_r_rot"] = Vector3(-55, 18, -22)
	p["hand_r_pos"] = Vector3(0.58, 1.50, -0.26)
	p["arm_l_pos"] = Vector3(-0.42, 1.28, 0.12)
	p["hand_l_pos"] = Vector3(-0.48, 1.30, 0.22)
	# Plant: outside foot loads for takeoff / wing angle.
	if wing:
		p["leg_l_x"] = -0.15
		p["leg_r_x"] = -0.75
	else:
		p["leg_l_x"] = 0.2
		p["leg_r_x"] = -0.7
	p["upper_y_off"] = -0.06
	return p


static func pose_jump_air(torso_yaw: float, window: bool, for_pass: bool) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw
	p["torso_pitch"] = -0.08
	p["upper_y_off"] = 0.0
	p["leg_l_x"] = -0.65
	p["leg_r_x"] = 0.45
	if for_pass:
		p["arm_r_pos"] = Vector3(0.50, 1.50, -0.18)
		p["arm_r_rot"] = Vector3(-70, 20, -25)
		p["hand_r_pos"] = Vector3(0.60, 1.65, -0.30)
	elif window:
		# Sweet / live window — arm high and ready to snap.
		p["arm_r_pos"] = Vector3(0.48, 1.62, -0.12)
		p["arm_r_rot"] = Vector3(-95, 15, -30)
		p["hand_r_pos"] = Vector3(0.55, 1.85, -0.22)
	else:
		p["arm_r_pos"] = Vector3(0.52, 1.48, -0.22)
		p["arm_r_rot"] = Vector3(-80, 22, -28)
		p["hand_r_pos"] = Vector3(0.62, 1.68, -0.36)
	p["arm_l_pos"] = Vector3(-0.45, 1.35, 0.15)
	p["arm_l_rot"] = Vector3(-35, -5, 15)
	p["hand_l_pos"] = Vector3(-0.50, 1.45, 0.30)
	return p


## Land plant: weight on pivot foot (0=L, 1=R, else balanced crouch). Readable for R1.7 / R2.8.
static func pose_land(torso_yaw: float, pivot_foot: int = -1) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.15
	p["torso_pitch"] = 0.14
	p["upper_y_off"] = -0.08
	if pivot_foot == 0:
		# Left planted, right free / recovering.
		p["leg_l_x"] = 0.12
		p["leg_r_x"] = -0.72
	elif pivot_foot == 1:
		p["leg_r_x"] = 0.12
		p["leg_l_x"] = -0.72
	else:
		p["leg_l_x"] = -0.55
		p["leg_r_x"] = -0.40
	p["arm_r_pos"] = Vector3(0.35, 1.15, 0.15)
	p["arm_r_rot"] = Vector3(15, -10, -5)
	p["hand_r_pos"] = Vector3(0.40, 1.00, 0.25)
	p["arm_l_pos"] = Vector3(-0.35, 1.15, 0.12)
	p["hand_l_pos"] = Vector3(-0.40, 1.00, 0.22)
	return p


static func lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var u := clampf(t, 0.0, 1.0)
	var out := {}
	for key in a.keys():
		var av: Variant = a[key]
		var bv: Variant = b.get(key, av)
		if av is Vector3 and bv is Vector3:
			out[key] = (av as Vector3).lerp(bv as Vector3, u)
		elif typeof(av) == TYPE_FLOAT or typeof(av) == TYPE_INT:
			out[key] = lerpf(float(av), float(bv), u)
		else:
			out[key] = bv
	for key in b.keys():
		if not out.has(key):
			out[key] = b[key]
	return out


## Advance a one-shot throw sequence. Returns {phase, t, done, pose}.
static func tick_throw_sequence(
	action: int,
	phase: int,
	t: float,
	delta: float,
	pass_type: int,
	charge: float,
	lob: bool,
	wing: bool,
	torso_yaw: float
) -> Dictionary:
	var ph := phase
	var elapsed := t + delta
	var pose := pose_rest()
	var done := false

	match action:
		Action.PASS, Action.JUMP_PASS:
			if ph == Phase.WINDUP or ph == Phase.IDLE:
				ph = Phase.WINDUP
				pose = pose_pass_windup(pass_type, torso_yaw)
				if elapsed >= PASS_WINDUP_S:
					ph = Phase.RELEASE
					elapsed = 0.0
			elif ph == Phase.RELEASE:
				pose = pose_pass_release(pass_type, torso_yaw)
				if elapsed >= PASS_RELEASE_S:
					ph = Phase.FOLLOW
					elapsed = 0.0
			elif ph == Phase.FOLLOW:
				pose = pose_pass_follow(pass_type, torso_yaw)
				if elapsed >= PASS_FOLLOW_S:
					if action == Action.JUMP_PASS:
						ph = Phase.LAND
						elapsed = 0.0
					else:
						done = true
			elif ph == Phase.LAND:
				pose = pose_land(torso_yaw)
				if elapsed >= LAND_S:
					done = true
			else:
				done = true

		Action.SHOOT, Action.JUMP_SHOT, Action.WING_SHOT:
			if ph == Phase.CHARGE:
				pose = pose_shot_charge(charge, lob, torso_yaw, wing or action == Action.WING_SHOT)
				# Charge is held externally — do not auto-advance.
			elif ph == Phase.RELEASE or ph == Phase.IDLE or ph == Phase.WINDUP:
				ph = Phase.RELEASE
				pose = pose_shot_release(lob, torso_yaw, wing or action == Action.WING_SHOT, action != Action.SHOOT)
				if elapsed >= SHOT_RELEASE_S:
					ph = Phase.FOLLOW
					elapsed = 0.0
			elif ph == Phase.FOLLOW:
				pose = pose_shot_follow(lob, torso_yaw, wing or action == Action.WING_SHOT)
				if elapsed >= SHOT_FOLLOW_S:
					if action == Action.JUMP_SHOT or action == Action.WING_SHOT:
						# Wing may be grounded; still settle briefly.
						ph = Phase.LAND
						elapsed = 0.0
					else:
						done = true
			elif ph == Phase.LAND:
				pose = pose_land(torso_yaw)
				if elapsed >= LAND_S:
					done = true
			else:
				done = true

		_:
			done = true

	return {"phase": ph, "t": elapsed, "done": done, "pose": pose}


## Pose while jump-shot craft is active (before / without a release yet).
static func pose_for_jump_craft(
	jump_phase: int,
	torso_yaw: float,
	wing: bool,
	for_pass: bool = false
) -> Dictionary:
	match jump_phase:
		_JP_APPROACH:
			return pose_jump_approach(torso_yaw)
		_JP_PLANTED:
			return pose_jump_plant(torso_yaw, wing)
		_JP_AIRBORNE:
			return pose_jump_air(torso_yaw, false, for_pass)
		_JP_WINDOW:
			return pose_jump_air(torso_yaw, true, for_pass)
		_:
			return pose_rest()
