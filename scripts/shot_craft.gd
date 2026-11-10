extends RefCounted
class_name ShotCraft

## Phase 3 shot feel helpers: charge power, lob loft, jump-shot timing window.

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
## Approximate jump apex from JUMP_VELOCITY / gravity (Player.JUMP_VELOCITY=7.5, g=18).
const JUMP_APEX_Y := 1.56


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
static func jump_shot_quality(body: CharacterBody3D) -> int:
	if body == null or body.is_on_floor():
		return -1
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
