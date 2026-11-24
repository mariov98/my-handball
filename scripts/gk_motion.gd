extends RefCounted
class_name GkMotion

## Wave 3 GK movement / save vocabulary poses (set, shuffle, dive variants, catch vs deflect, outlet).
## Save volume sizing still lives on Player; this drives readable modular-body poses.

enum Stance {
	IDLE = 0,
	SET = 1,
	SHUFFLE = 2,
	DIVE = 3,
	CATCH = 4,
	DEFLECT = 5,
	OUTLET = 6,
}

enum DiveSide {
	NONE = 0,
	LEFT = 1,
	RIGHT = 2,
}

enum DiveHeight {
	LOW = 0,
	HIGH = 1,
}

const CATCH_POSE_S := 0.42
const DEFLECT_POSE_S := 0.36
const OUTLET_POSE_S := 0.55
const SET_BLEND := 0.85


static func stance_name(stance: int) -> String:
	match stance:
		Stance.SET:
			return "SET"
		Stance.SHUFFLE:
			return "SHUFFLE"
		Stance.DIVE:
			return "DIVE"
		Stance.CATCH:
			return "CATCH"
		Stance.DEFLECT:
			return "DEFLECT"
		Stance.OUTLET:
			return "OUTLET"
		_:
			return "IDLE"


static func dive_side_name(side: int) -> String:
	match side:
		DiveSide.LEFT:
			return "L"
		DiveSide.RIGHT:
			return "R"
		_:
			return "-"


static func dive_height_name(height: int) -> String:
	return "HIGH" if height == DiveHeight.HIGH else "LOW"


## Classify dive from planar wish / ball height.
static func classify_dive(dir: Vector3, ball_y: float, face: Vector3) -> Dictionary:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.01:
		flat = Vector3(face.x, 0.0, face.z)
	if flat.length_squared() < 0.01:
		flat = Vector3.RIGHT
	flat = flat.normalized()
	# Side relative to facing: cross Y gives left/right in local.
	var face_flat := Vector3(face.x, 0.0, face.z)
	if face_flat.length_squared() < 0.01:
		face_flat = Vector3(0, 0, 1)
	face_flat = face_flat.normalized()
	var cross_y := face_flat.x * flat.z - face_flat.z * flat.x
	# Also fall back to world X when facing along Z (typical GK).
	var side := DiveSide.RIGHT
	if absf(cross_y) > 0.08:
		side = DiveSide.LEFT if cross_y > 0.0 else DiveSide.RIGHT
	elif flat.x < -0.08:
		side = DiveSide.LEFT
	elif flat.x > 0.08:
		side = DiveSide.RIGHT
	var height := DiveHeight.HIGH if ball_y >= 1.15 else DiveHeight.LOW
	return {"side": side, "height": height, "dir": flat}


static func pose_rest_gk() -> Dictionary:
	return {
		"arm_l_pos": Vector3(-0.48, 1.28, 0.02),
		"arm_r_pos": Vector3(0.48, 1.28, 0.02),
		"arm_l_rot": Vector3(0, 0, 0),
		"arm_r_rot": Vector3(0, 0, 0),
		"hand_l_pos": Vector3(-0.70, 1.18, 0.06),
		"hand_r_pos": Vector3(0.70, 1.18, 0.06),
		"torso_yaw": 0.0,
		"torso_pitch": 0.0,
		"leg_l_x": 0.0,
		"leg_r_x": 0.0,
		"upper_y_off": 0.0,
		"save_box": Vector3(1.8, 1.6, 1.1),
	}


## Ready set / angle-cut stance — knees soft, arms wide.
static func pose_set() -> Dictionary:
	var p := pose_rest_gk()
	p["torso_pitch"] = 0.10
	p["upper_y_off"] = -0.06
	p["leg_l_x"] = 0.28
	p["leg_r_x"] = 0.28
	p["arm_l_pos"] = Vector3(-0.62, 1.38, 0.10)
	p["arm_r_pos"] = Vector3(0.62, 1.38, 0.10)
	p["arm_l_rot"] = Vector3(-18, 0, 18)
	p["arm_r_rot"] = Vector3(-18, 0, -18)
	p["hand_l_pos"] = Vector3(-0.88, 1.32, 0.18)
	p["hand_r_pos"] = Vector3(0.88, 1.32, 0.18)
	p["save_box"] = Vector3(2.0, 1.55, 1.15)
	return p


## Lateral shuffle — lead leg opens, arms stay ready.
static func pose_shuffle(side: float) -> Dictionary:
	var s := signf(side) if absf(side) > 0.01 else 1.0
	var p := pose_set()
	p["torso_yaw"] = s * 0.12
	p["upper_y_off"] = -0.05
	if s >= 0.0:
		p["leg_r_x"] = 0.42
		p["leg_l_x"] = 0.12
	else:
		p["leg_l_x"] = 0.42
		p["leg_r_x"] = 0.12
	p["arm_l_pos"] = Vector3(-0.70, 1.34, 0.08)
	p["arm_r_pos"] = Vector3(0.70, 1.34, 0.08)
	return p


static func pose_dive(side: int, height: int) -> Dictionary:
	var p := pose_rest_gk()
	var left := side == DiveSide.LEFT
	var high := height == DiveHeight.HIGH
	p["torso_pitch"] = 0.35 if not high else 0.12
	p["upper_y_off"] = -0.28 if not high else -0.12
	p["torso_yaw"] = -0.25 if left else 0.25
	if high:
		# High dive — arms stretch up toward the corner.
		if left:
			p["arm_l_pos"] = Vector3(-1.05, 1.55, 0.15)
			p["arm_r_pos"] = Vector3(0.35, 1.45, 0.08)
			p["arm_l_rot"] = Vector3(-55, 10, 35)
			p["arm_r_rot"] = Vector3(-30, 0, -10)
			p["hand_l_pos"] = Vector3(-1.25, 1.78, 0.28)
			p["hand_r_pos"] = Vector3(0.50, 1.55, 0.18)
			p["leg_l_x"] = 0.15
			p["leg_r_x"] = 0.55
		else:
			p["arm_r_pos"] = Vector3(1.05, 1.55, 0.15)
			p["arm_l_pos"] = Vector3(-0.35, 1.45, 0.08)
			p["arm_r_rot"] = Vector3(-55, -10, -35)
			p["arm_l_rot"] = Vector3(-30, 0, 10)
			p["hand_r_pos"] = Vector3(1.25, 1.78, 0.28)
			p["hand_l_pos"] = Vector3(-0.50, 1.55, 0.18)
			p["leg_r_x"] = 0.15
			p["leg_l_x"] = 0.55
		p["save_box"] = Vector3(2.8, 1.6, 1.5)
	else:
		# Low dive — stretch toward the floor / near post.
		if left:
			p["arm_l_pos"] = Vector3(-1.15, 0.72, 0.18)
			p["arm_r_pos"] = Vector3(0.25, 0.95, 0.10)
			p["arm_l_rot"] = Vector3(15, 5, 40)
			p["arm_r_rot"] = Vector3(5, 0, -8)
			p["hand_l_pos"] = Vector3(-1.35, 0.55, 0.28)
			p["hand_r_pos"] = Vector3(0.40, 0.85, 0.18)
			p["leg_l_x"] = 0.65
			p["leg_r_x"] = 0.25
		else:
			p["arm_r_pos"] = Vector3(1.15, 0.72, 0.18)
			p["arm_l_pos"] = Vector3(-0.25, 0.95, 0.10)
			p["arm_r_rot"] = Vector3(15, -5, -40)
			p["arm_l_rot"] = Vector3(5, 0, 8)
			p["hand_r_pos"] = Vector3(1.35, 0.55, 0.28)
			p["hand_l_pos"] = Vector3(-0.40, 0.85, 0.18)
			p["leg_r_x"] = 0.65
			p["leg_l_x"] = 0.25
		p["save_box"] = Vector3(2.7, 1.15, 1.55)
	return p


## Smother / catch — gather into the body.
static func pose_catch() -> Dictionary:
	var p := pose_rest_gk()
	p["torso_pitch"] = 0.18
	p["upper_y_off"] = -0.08
	p["arm_l_pos"] = Vector3(-0.28, 1.15, 0.28)
	p["arm_r_pos"] = Vector3(0.28, 1.15, 0.28)
	p["arm_l_rot"] = Vector3(-45, 15, 20)
	p["arm_r_rot"] = Vector3(-45, -15, -20)
	p["hand_l_pos"] = Vector3(-0.18, 1.05, 0.42)
	p["hand_r_pos"] = Vector3(0.18, 1.05, 0.42)
	p["leg_l_x"] = 0.35
	p["leg_r_x"] = 0.35
	p["save_box"] = Vector3(1.6, 1.4, 1.2)
	return p


## Tip / deflect — arms punch the ball away.
static func pose_deflect(side: int) -> Dictionary:
	var p := pose_rest_gk()
	var left := side == DiveSide.LEFT
	p["torso_pitch"] = -0.05
	if left:
		p["arm_l_pos"] = Vector3(-0.95, 1.48, 0.35)
		p["arm_l_rot"] = Vector3(-70, 20, 25)
		p["hand_l_pos"] = Vector3(-1.15, 1.62, 0.55)
		p["arm_r_pos"] = Vector3(0.40, 1.30, 0.10)
		p["hand_r_pos"] = Vector3(0.55, 1.25, 0.18)
	else:
		p["arm_r_pos"] = Vector3(0.95, 1.48, 0.35)
		p["arm_r_rot"] = Vector3(-70, -20, -25)
		p["hand_r_pos"] = Vector3(1.15, 1.62, 0.55)
		p["arm_l_pos"] = Vector3(-0.40, 1.30, 0.10)
		p["hand_l_pos"] = Vector3(-0.55, 1.25, 0.18)
	p["save_box"] = Vector3(2.4, 1.7, 1.3)
	return p


## Outlet / distribution throw windup after a save gather.
static func pose_outlet(torso_yaw: float) -> Dictionary:
	var p := pose_rest_gk()
	p["torso_yaw"] = torso_yaw
	p["torso_pitch"] = -0.10
	p["arm_r_pos"] = Vector3(0.55, 1.62, -0.28)
	p["arm_r_rot"] = Vector3(-100, 25, -35)
	p["hand_r_pos"] = Vector3(0.65, 1.88, -0.42)
	p["arm_l_pos"] = Vector3(-0.42, 1.35, 0.16)
	p["arm_l_rot"] = Vector3(-35, -8, 12)
	p["hand_l_pos"] = Vector3(-0.48, 1.45, 0.30)
	p["leg_r_x"] = -0.20
	p["leg_l_x"] = 0.15
	return p
