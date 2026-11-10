extends RefCounted
class_name PassCraft

## Phase A pass feel: light lead in an aim cone (not heavy magnet, not pure ballistic).
## Shares the same throw release path as shots via Ball.release_and_shoot + pass meta.

const IMPULSE_MIN := 8.5
const IMPULSE_MAX := 13.0
## Cosine of half-cone — ~55° each side so face/mouse aim still matters.
const CONE_DOT_MIN := 0.35
const MIN_DIST_M := 2.0
const MAX_DIST_M := 16.0
## Light lead: fraction of estimated flight time × receiver planar speed.
const LEAD_TIME_SCALE := 0.55
const MAX_LEAD_M := 1.6
const LOFT_MIN := 0.05
const LOFT_MAX := 0.16
## How much cone-target blends into the aim hint (face / mouse). 0 = pure aim, 1 = lock.
const ASSIST_BLEND := 0.38
## Soft in-flight steer toward intended receiver (keeps feel catchable, not magnetized).
const FLIGHT_STEER := 0.7
const FLIGHT_STEER_DIST := 4.2
## Sticky catch planar radius while a pass is incoming (chest-anchored).
const CATCH_STICKY_RADIUS := 1.55
const CATCH_APPROACH_DOT := -0.15


static func impulse_for_distance(dist: float) -> float:
	return clampf(lerpf(IMPULSE_MIN, IMPULSE_MAX, dist / 12.0), IMPULSE_MIN, IMPULSE_MAX)


static func loft_for_distance(dist: float) -> float:
	return clampf(LOFT_MIN + dist * 0.007, LOFT_MIN, LOFT_MAX)


## Planar lead so a moving teammate can catch without a heavy magnet.
static func lead_offset(receiver: CharacterBody3D, from: Vector3, to: Vector3, impulse: float) -> Vector3:
	if receiver == null:
		return Vector3.ZERO
	var dist := from.distance_to(to)
	var speed := maxf(impulse * 0.55, 6.0)
	var flight_t := clampf(dist / speed, 0.08, 0.55) * LEAD_TIME_SCALE
	var planar := Vector3(receiver.velocity.x, 0.0, receiver.velocity.z)
	var lead := planar * flight_t
	if lead.length() > MAX_LEAD_M:
		lead = lead.normalized() * MAX_LEAD_M
	return lead


## Score a teammate inside the aim cone. Higher = better pass target.
static func score_in_cone(
	passer: CharacterBody3D,
	mate: CharacterBody3D,
	aim_dir: Vector3,
	passer_team_id: int
) -> float:
	if passer == null or mate == null:
		return -INF
	var to_m := mate.global_position - passer.global_position
	to_m.y = 0.0
	var d := to_m.length()
	if d < MIN_DIST_M or d > MAX_DIST_M:
		return -INF
	var dir := to_m / d
	var aim := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if aim.length_squared() < 0.01:
		aim = Vector3(0.0, 0.0, 1.0 if passer_team_id == 0 else -1.0)
	else:
		aim = aim.normalized()
	var forward := dir.dot(aim)
	if forward < CONE_DOT_MIN:
		return -INF
	var toward_goal := dir.z * (1.0 if passer_team_id == 0 else -1.0)
	# Prefer open forward lanes; mild distance preference for readable circulation.
	return forward * 2.6 + toward_goal * 1.2 + d * 0.04


static func best_in_cone(
	passer: CharacterBody3D,
	roster: Array,
	aim_dir: Vector3,
	passer_team_id: int
) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_score := -INF
	for mate in roster:
		if mate == null or mate == passer:
			continue
		if not (mate is CharacterBody3D):
			continue
		# Skip GK / frozen via duck typing used by Player.
		if mate.get("is_goalkeeper") == true:
			continue
		if mate.get("match_frozen") == true:
			continue
		var score := score_in_cone(passer, mate, aim_dir, passer_team_id)
		# Prefer uncontrolled receivers so the human can switch onto the catch.
		if mate.get("controlled") == false:
			score += 0.3
		if score > best_score:
			best_score = score
			best = mate
	return best


## Build aim + loft + impulse for a soft pass with light cone lead assist.
static func build_pass(
	passer: CharacterBody3D,
	target: CharacterBody3D,
	aim_hint: Vector3,
	impulse_override: float = -1.0
) -> Dictionary:
	var from := passer.global_position + Vector3(0, 1.2, 0)
	var to := target.global_position + Vector3(0, 1.15, 0)
	var dist := from.distance_to(to)
	var impulse := impulse_override if impulse_override > 0.0 else impulse_for_distance(dist)
	var lead := lead_offset(target, from, to, impulse)
	var assisted_to := to + lead
	var to_target := (assisted_to - from)
	if to_target.length_squared() < 0.01:
		return {}
	to_target = to_target.normalized()
	var hint := aim_hint
	if hint.length_squared() < 0.01:
		hint = to_target
	else:
		hint = hint.normalized()
	# Light blend: aim still reads as face/mouse, with a nudge into the cone target.
	var aim := hint.lerp(to_target, ASSIST_BLEND).normalized()
	var loft := loft_for_distance(dist)
	return {
		"aim": aim,
		"loft": loft,
		"impulse": impulse,
		"target": target,
		"dist": dist,
	}
