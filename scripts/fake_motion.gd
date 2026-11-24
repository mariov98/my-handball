extends RefCounted
class_name FakeMotion

## Wave 3 procedural fakes — threaten without releasing the ball.
## Gameplay sell/recover lives on Player; this module owns pose + timing.

enum Kind {
	NONE = 0,
	SHOT = 1,
	PASS = 2,
	JAB = 3,
}

enum Phase {
	IDLE = 0,
	THREATEN = 1,
	RECOVER = 2,
}

const SHOT_THREATEN_S := 0.22
const SHOT_RECOVER_S := 0.28
const PASS_THREATEN_S := 0.20
const PASS_RECOVER_S := 0.26
const JAB_THREATEN_S := 0.18
const JAB_RECOVER_S := 0.30

## Lite sell window for nearby markers (seconds).
const SELL_RADIUS := 3.1
const SELL_DURATION := 0.48
const SELL_RECOVER_S := 0.35
## AI: only attempt a fake occasionally under pressure.
const AI_FAKE_CHANCE := 0.22
const AI_FAKE_COOLDOWN_S := 2.4


static func kind_name(kind: int) -> String:
	match kind:
		Kind.SHOT:
			return "SHOT"
		Kind.PASS:
			return "PASS"
		Kind.JAB:
			return "JAB"
		_:
			return "NONE"


static func phase_name(phase: int) -> String:
	match phase:
		Phase.THREATEN:
			return "THREATEN"
		Phase.RECOVER:
			return "RECOVER"
		_:
			return "IDLE"


static func threaten_duration(kind: int) -> float:
	match kind:
		Kind.SHOT:
			return SHOT_THREATEN_S
		Kind.PASS:
			return PASS_THREATEN_S
		Kind.JAB:
			return JAB_THREATEN_S
		_:
			return 0.2


static func recover_duration(kind: int) -> float:
	match kind:
		Kind.SHOT:
			return SHOT_RECOVER_S
		Kind.PASS:
			return PASS_RECOVER_S
		Kind.JAB:
			return JAB_RECOVER_S
		_:
			return 0.25


## Rest pose matching ThrowMotion / outfield arms.
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
		"leg_l_z": 0.0,
		"leg_r_z": 0.0,
	}


## Shot fake: cock like a charge, then abort — ball stays.
static func pose_shot_threaten(torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw
	p["torso_pitch"] = -0.08
	p["arm_r_pos"] = Vector3(0.52, 1.52, -0.24)
	p["arm_r_rot"] = Vector3(-82, 22, -30)
	p["hand_r_pos"] = Vector3(0.64, 1.72, -0.40)
	p["arm_l_pos"] = Vector3(-0.38, 1.36, 0.18)
	p["arm_l_rot"] = Vector3(-40, -8, 12)
	p["hand_l_pos"] = Vector3(-0.44, 1.46, 0.32)
	p["leg_r_x"] = -0.18
	p["leg_l_x"] = 0.10
	return p


static func pose_shot_recover(torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.25
	p["arm_r_pos"] = Vector3(0.44, 1.30, -0.06)
	p["arm_r_rot"] = Vector3(-28, 10, -12)
	p["hand_r_pos"] = Vector3(0.56, 1.28, 0.02)
	return p


## Pass fake: look-off / pump toward a side, then pull back.
static func pose_pass_threaten(torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	# Exaggerate look-off away from pure forward.
	p["torso_yaw"] = clampf(torso_yaw + signf(torso_yaw + 0.15) * 0.55, -1.2, 1.2)
	p["torso_pitch"] = -0.04
	p["arm_r_pos"] = Vector3(0.48, 1.40, -0.16)
	p["arm_r_rot"] = Vector3(-70, 28, -22)
	p["hand_r_pos"] = Vector3(0.58, 1.52, -0.28)
	p["arm_l_pos"] = Vector3(-0.42, 1.28, 0.14)
	p["arm_l_rot"] = Vector3(-30, -12, 10)
	p["hand_l_pos"] = Vector3(-0.48, 1.32, 0.26)
	return p


static func pose_pass_recover(torso_yaw: float) -> Dictionary:
	var p := pose_rest()
	p["torso_yaw"] = torso_yaw * 0.2
	p["arm_r_pos"] = Vector3(0.42, 1.24, 0.02)
	p["hand_r_pos"] = Vector3(0.55, 1.14, 0.10)
	return p


## Jab / body fake: lead foot + hip slide, arms stay protective on the ball.
static func pose_jab_threaten(side: float) -> Dictionary:
	var s := signf(side) if absf(side) > 0.01 else 1.0
	var p := pose_rest()
	p["torso_yaw"] = s * 0.35
	p["torso_pitch"] = 0.06
	p["upper_y_off"] = -0.04
	# Lead jab foot forward; plant trail.
	if s >= 0.0:
		p["leg_r_x"] = -0.55
		p["leg_l_x"] = 0.22
		p["leg_r_z"] = s * 0.12
	else:
		p["leg_l_x"] = -0.55
		p["leg_r_x"] = 0.22
		p["leg_l_z"] = s * 0.12
	# Guard the ball — no throw cock.
	p["arm_r_pos"] = Vector3(0.36, 1.18, 0.12)
	p["arm_r_rot"] = Vector3(-25, -15, -8)
	p["hand_r_pos"] = Vector3(0.42, 1.08, 0.22)
	p["arm_l_pos"] = Vector3(-0.34, 1.20, 0.10)
	p["arm_l_rot"] = Vector3(-20, 10, 8)
	p["hand_l_pos"] = Vector3(-0.40, 1.10, 0.18)
	return p


static func pose_jab_recover(side: float) -> Dictionary:
	var s := signf(side) if absf(side) > 0.01 else 1.0
	var p := pose_rest()
	p["torso_yaw"] = s * 0.08
	p["leg_l_x"] = 0.05 * s
	p["leg_r_x"] = -0.05 * s
	return p


static func pose_for(kind: int, phase: int, torso_yaw: float, jab_side: float) -> Dictionary:
	match kind:
		Kind.SHOT:
			if phase == Phase.THREATEN:
				return pose_shot_threaten(torso_yaw)
			return pose_shot_recover(torso_yaw)
		Kind.PASS:
			if phase == Phase.THREATEN:
				return pose_pass_threaten(torso_yaw)
			return pose_pass_recover(torso_yaw)
		Kind.JAB:
			if phase == Phase.THREATEN:
				return pose_jab_threaten(jab_side)
			return pose_jab_recover(jab_side)
		_:
			return pose_rest()


## Advance fake sequence. Returns {phase, t, pose, done}.
static func tick_fake(
	kind: int,
	phase: int,
	t: float,
	delta: float,
	torso_yaw: float,
	jab_side: float
) -> Dictionary:
	if kind == Kind.NONE or phase == Phase.IDLE:
		return {"phase": Phase.IDLE, "t": 0.0, "pose": pose_rest(), "done": true}
	var cur_phase := phase
	var cur_t := t + delta
	var threaten_s := threaten_duration(kind)
	var recover_s := recover_duration(kind)
	if cur_phase == Phase.THREATEN:
		if cur_t >= threaten_s:
			cur_phase = Phase.RECOVER
			cur_t = 0.0
	elif cur_phase == Phase.RECOVER:
		if cur_t >= recover_s:
			return {
				"phase": Phase.IDLE,
				"t": 0.0,
				"pose": pose_rest(),
				"done": true,
			}
	var pose := pose_for(kind, cur_phase, torso_yaw, jab_side)
	return {"phase": cur_phase, "t": cur_t, "pose": pose, "done": false}
