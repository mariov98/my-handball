extends RefCounted
class_name ShotCraft

## Phase 3 / F shot feel: charge power, lob loft, jump-shot craft (plant → air → window).

const CHARGE_TIME_S := 0.58
const IMPULSE_MIN := 10.5
const IMPULSE_MAX := 22.0
const FLAT_UP_BIAS := 0.05
const LOB_UP_BIAS := 0.58
const LOB_IMPULSE_SCALE := 0.84
## Jump-shot sweet spot: fraction of apex height (0–1) that counts as "good".
const JUMP_SWEET_MIN := 0.55
const JUMP_SWEET_MAX := 0.98
const JUMP_BONUS_IMPULSE := 1.18
const JUMP_EARLY_SCALE := 0.88
const JUMP_LATE_SCALE := 0.92
const JUMP_SCATTER_BAD := 0.12
const JUMP_SCATTER_GOOD := 0.02
## Approximate jump apex from JUMP_VELOCITY / gravity (Player.JUMP_VELOCITY≈7.8, g=18).
const JUMP_APEX_Y := 1.56

## Phase F jump-shot state machine (approach plant → jump → release window).
enum JumpPhase { NONE = 0, APPROACH = 1, PLANTED = 2, AIRBORNE = 3, WINDOW = 4 }

## Brief grounded plant before takeoff — readable approach into the jump.
const PLANT_HOLD_S := 0.10
## Air time window where release is "live" (early → sweet → late).
const WINDOW_OPEN_S := 0.16
const WINDOW_CLOSE_S := 0.58
const WINDOW_SWEET_OPEN_S := 0.28
const WINDOW_SWEET_CLOSE_S := 0.46
## Planar approach speed that qualifies a jump-with-ball as jump-shot craft.
const APPROACH_MIN_SPEED := 2.0
## Extra impulse when releasing inside the timed sweet window (on top of height sweet).
const WINDOW_SWEET_BONUS := 1.06


static func charge_01(held_s: float) -> float:
	return clampf(held_s / CHARGE_TIME_S, 0.0, 1.0)


static func impulse_for_charge(charge: float, lob: bool) -> float:
	var t := clampf(charge, 0.0, 1.0)
	# Ease-out so mid-hold already feels useful.
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var impulse := lerpf(IMPULSE_MIN, IMPULSE_MAX, eased)
	if lob:
		impulse *= LOB_IMPULSE_SCALE
	return impulse


static func up_bias(lob: bool) -> float:
	return LOB_UP_BIAS if lob else FLAT_UP_BIAS


## Height quality while airborne: -1 grounded, 0 early, 1 sweet, 2 late/falling.
## Takes CharacterBody3D to avoid a Player↔ShotCraft class_name load cycle.
## When the body exposes jump-shot craft fields, blends timed release window.
static func jump_shot_quality(body: CharacterBody3D) -> int:
	if body == null or body.is_on_floor():
		return -1
	var craft: Variant = body.get("jump_shot_active")
	if craft == true:
		var air_raw: Variant = body.get("jump_shot_air_s")
		var air_s := float(air_raw) if air_raw != null else 0.0
		return jump_shot_window_quality(body, air_s)
	return _height_quality(body)


## Timed release window for an active jump-shot craft (Phase F).
## Still uses height as a tie-break so floaty apex reads as sweet.
static func jump_shot_window_quality(body: CharacterBody3D, air_s: float) -> int:
	if body == null or body.is_on_floor():
		return -1
	var height_q := _height_quality(body)
	return window_quality_from_air_s(air_s, height_q)


## Pure time-band read (smoke / helpers). height_q tie-breaks open-but-not-sweet.
static func window_quality_from_air_s(air_s: float, height_q: int = 0) -> int:
	if air_s < WINDOW_OPEN_S:
		return 0  # early — still rising into the window
	if air_s > WINDOW_CLOSE_S:
		return 2  # late — falling out of the craft window
	if air_s >= WINDOW_SWEET_OPEN_S and air_s <= WINDOW_SWEET_CLOSE_S:
		# Sweet time: keep sweet even if height is slightly early/late.
		return 1
	# In the open window but outside the sweet band — prefer height read.
	if height_q == 1:
		return 1
	if air_s < WINDOW_SWEET_OPEN_S:
		return 0
	return 2


static func _height_quality(body: CharacterBody3D) -> int:
	var height := body.global_position.y
	var frac := clampf(height / JUMP_APEX_Y, 0.0, 1.2)
	if frac < JUMP_SWEET_MIN:
		return 0
	if frac <= JUMP_SWEET_MAX and body.velocity.y >= -1.5:
		return 1
	return 2


static func apply_jump_timing(aim: Vector3, impulse: float, quality: int) -> Dictionary:
	var out_aim := aim.normalized()
	var out_impulse := impulse
	var scatter := 0.0
	match quality:
		1:
			out_impulse *= JUMP_BONUS_IMPULSE
			scatter = JUMP_SCATTER_GOOD
		0:
			out_impulse *= JUMP_EARLY_SCALE
			scatter = JUMP_SCATTER_BAD
		2:
			out_impulse *= JUMP_LATE_SCALE
			scatter = JUMP_SCATTER_BAD * 0.85
		_:
			scatter = 0.03
	if scatter > 0.0:
		out_aim += Vector3(
			randf_range(-scatter, scatter),
			randf_range(-scatter * 0.35, scatter * 0.35),
			randf_range(-scatter, scatter)
		)
		if out_aim.length_squared() > 0.0001:
			out_aim = out_aim.normalized()
	return {"aim": out_aim, "impulse": out_impulse, "quality": quality}


## Extra punch when the timed window and height sweet agree.
static func apply_window_bonus(impulse: float, quality: int, air_s: float) -> float:
	if quality != 1:
		return impulse
	if air_s >= WINDOW_SWEET_OPEN_S and air_s <= WINDOW_SWEET_CLOSE_S:
		return impulse * WINDOW_SWEET_BONUS
	return impulse


static func jump_label(quality: int) -> String:
	match quality:
		1:
			return "JUMP · sweet"
		0:
			return "JUMP · early"
		2:
			return "JUMP · late"
		_:
			return ""


static func jump_phase_label(phase: int) -> String:
	match phase:
		JumpPhase.APPROACH:
			return "JUMP · approach"
		JumpPhase.PLANTED:
			return "JUMP · plant"
		JumpPhase.AIRBORNE:
			return "JUMP · rise"
		JumpPhase.WINDOW:
			return "JUMP · window"
		_:
			return ""
