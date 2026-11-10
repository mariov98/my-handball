extends RefCounted
class_name HandballRules

## Phase 2 sport-logic approximations. MatchController owns restarts; this tracks
## steps, passive play, OOB, and goal-area violations and reports when they fire.

signal rule_warning(code: String, message: String)
signal rule_violation(code: String, message: String, awarding_team_id: int, spot: Vector3)

const MAX_STEPS := 3
const STEP_LENGTH_M := 1.15
## Soft passive: warn then turnover if offense stalls without progress to goal.
const PASSIVE_WARN_S := 6.0
const PASSIVE_TURNOVER_S := 10.0
const PASSIVE_PROGRESS_M := 1.75
## Brief grace so jump-shot landings / brush of the arc don't spam fouls.
const GOAL_AREA_GRACE_S := 0.18
const OOB_COOLDOWN_S := 0.35

var enabled: bool = true
var last_touch_team_id: int = 0

var _steps: int = 0
var _step_accum: float = 0.0
var _carrier_last_xz: Vector3 = Vector3.ZERO
var _have_carrier_sample: bool = false

var _passive_timer: float = 0.0
var _passive_warned: bool = false
var _passive_best_dist: float = INF
var _possession_team_id: int = -1

var _area_timers: Dictionary = {} ## player instance_id -> float
var _oob_cooldown: float = 0.0
var _lockout: bool = false ## true while MatchController runs a restart


func reset_possession_tracking() -> void:
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_passive_timer = 0.0
	_passive_warned = false
	_passive_best_dist = INF
	_possession_team_id = -1
	_area_timers.clear()


func begin_lockout() -> void:
	_lockout = true
	reset_possession_tracking()


func end_lockout() -> void:
	_lockout = false
	_oob_cooldown = OOB_COOLDOWN_S


func on_pickup(player: Player) -> void:
	if player == null:
		return
	last_touch_team_id = player.team_id
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_passive_timer = 0.0
	_passive_warned = false
	_passive_best_dist = INF
	_possession_team_id = player.team_id


func on_release(player: Player) -> void:
	if player == null:
		return
	last_touch_team_id = player.team_id
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	# Passive keeps ticking lightly on free ball only while same team last touched —
	# Phase 2: pause passive until someone possesses again.
	_passive_timer = 0.0
	_passive_warned = false
	_passive_best_dist = INF
	_possession_team_id = -1


func get_steps() -> int:
	return _steps


func get_passive_timer() -> float:
	return _passive_timer


func is_passive_warned() -> bool:
	return _passive_warned


## Returns true if a violation was emitted (caller should stop further checks).
func tick(delta: float, ball: Ball, players: Array[Player]) -> bool:
	if not enabled or _lockout or ball == null:
		return false
	if _oob_cooldown > 0.0:
		_oob_cooldown = maxf(0.0, _oob_cooldown - delta)

	var carrier: Player = ball.carrier
	if carrier:
		if _tick_steps(delta, carrier):
			return true
		if _tick_passive(delta, carrier):
			return true
	else:
		_have_carrier_sample = false
		_steps = 0
		_step_accum = 0.0

	if _tick_oob(ball, carrier):
		return true
	if _tick_goal_areas(delta, players, carrier):
		return true
	return false


func _is_airborne(player: Player) -> bool:
	# Prefer physics floor contact; fall back to height so teleports / early frames
	# still count as grounded for steps / crease rules.
	if player.is_on_floor():
		return false
	return player.global_position.y > 0.35 or player.velocity.y > 1.0


func _tick_steps(_delta: float, carrier: Player) -> bool:
	var xz := Vector3(carrier.global_position.x, 0.0, carrier.global_position.z)
	if not _have_carrier_sample:
		_carrier_last_xz = xz
		_have_carrier_sample = true
		return false
	var moved := xz.distance_to(_carrier_last_xz)
	_carrier_last_xz = xz
	# Approximate steps on the floor only — airborne jump-shot is allowed.
	if _is_airborne(carrier) or moved < 0.0001:
		return false
	_step_accum += moved
	while _step_accum >= STEP_LENGTH_M:
		_step_accum -= STEP_LENGTH_M
		_steps += 1
		if _steps > MAX_STEPS:
			var spot := Court.clamp_to_court_xz(carrier.global_position, 1.0)
			# Free-throw style: keep restart outside the 6 m if near goal.
			spot = _free_throw_spot(spot, 1 - carrier.team_id)
			rule_violation.emit(
				"traveling",
				"Traveling — steps",
				1 - carrier.team_id,
				spot
			)
			return true
	return false


func _tick_passive(delta: float, carrier: Player) -> bool:
	if carrier.is_goalkeeper:
		# GK holding after a save shouldn't burn passive the same way.
		_passive_timer = 0.0
		_passive_warned = false
		return false
	var goal := carrier.opponent_goal_point()
	var dist := Vector2(carrier.global_position.x - goal.x, carrier.global_position.z - goal.z).length()
	if dist < _passive_best_dist - PASSIVE_PROGRESS_M:
		_passive_best_dist = dist
		_passive_timer = 0.0
		_passive_warned = false
		return false
	if _passive_best_dist == INF:
		_passive_best_dist = dist
	_passive_timer += delta
	if _passive_timer >= PASSIVE_WARN_S and not _passive_warned:
		_passive_warned = true
		rule_warning.emit("passive", "Passive play — keep attacking")
	if _passive_timer >= PASSIVE_TURNOVER_S:
		var spot := Court.clamp_to_court_xz(carrier.global_position, 1.0)
		spot = _free_throw_spot(spot, 1 - carrier.team_id)
		rule_violation.emit(
			"passive",
			"Passive play — turnover",
			1 - carrier.team_id,
			spot
		)
		return true
	return false


func _tick_oob(ball: Ball, carrier: Player) -> bool:
	if _oob_cooldown > 0.0:
		return false
	var pos: Vector3
	var from_team: int = last_touch_team_id
	if carrier:
		pos = carrier.global_position
		from_team = carrier.team_id
	else:
		pos = ball.global_position

	if Court.is_sideline_oob(pos):
		var award := 1 - from_team
		var side := signf(pos.x)
		if side == 0.0:
			side = 1.0
		# Inset from the soft OOB line so the taker doesn't instantly re-trigger.
		var spot := Vector3(side * (Court.OOB_HALF_WIDTH - 0.85), 0.0, clampf(pos.z, -18.0, 18.0))
		rule_violation.emit("throw_in", "Out of bounds — throw-in", award, spot)
		return true

	# End-line OOB only for free ball (carrier is blocked by end walls anyway).
	if carrier == null and Court.is_endline_oob(pos):
		var end_team := 0 if pos.z < 0.0 else 1  # team defending that end
		var award: int
		var code: String
		var message: String
		var spot: Vector3
		if from_team == end_team:
			# Defense last touched over own end → corner-style throw-in for attack.
			award = 1 - end_team
			code = "throw_in"
			message = "End line — corner throw-in"
			var side := 1.0 if pos.x >= 0.0 else -1.0
			spot = Vector3(side * 8.0, 0.0, signf(pos.z) * 17.8)
		else:
			# Attack put it out → goal throw.
			award = end_team
			code = "goal_throw"
			message = "End line — goal throw"
			spot = Vector3(0.0, 0.0, signf(pos.z) * 16.8)
		rule_violation.emit(code, message, award, spot)
		return true
	return false


func _tick_goal_areas(delta: float, players: Array[Player], carrier: Player) -> bool:
	for p in players:
		if p == null or p.is_goalkeeper:
			_area_timers.erase(p.get_instance_id())
			continue
		var violated_team := -1
		# Attackers in opponent crease, or defenders in own crease.
		if Court.in_goal_area(p.global_position, 1 - p.team_id):
			violated_team = 1 - p.team_id  # opponent's area
		elif Court.in_goal_area(p.global_position, p.team_id):
			violated_team = p.team_id  # own area
		else:
			_area_timers.erase(p.get_instance_id())
			continue

		# Jump shots: airborne in the opponent crease is allowed.
		if violated_team == 1 - p.team_id and _is_airborne(p):
			_area_timers.erase(p.get_instance_id())
			continue

		var id := p.get_instance_id()
		var t: float = float(_area_timers.get(id, 0.0)) + delta
		_area_timers[id] = t
		if t < GOAL_AREA_GRACE_S:
			continue

		var award := 1 - p.team_id
		var spot := Court.eject_from_goal_area(p.global_position, violated_team, 0.8)
		spot = _free_throw_spot(spot, award)
		var msg := "Goal area — attacker" if violated_team == 1 - p.team_id else "Goal area — defender"
		if carrier == p:
			msg = "Goal area — with ball"
		rule_violation.emit("goal_area", msg, award, spot)
		return true
	return false


func _free_throw_spot(near: Vector3, awarding_team_id: int) -> Vector3:
	# Keep free throws outside both goal areas and roughly near the foul.
	var spot := Court.clamp_to_court_xz(near, 1.2)
	if Court.in_goal_area(spot, 0):
		spot = Court.eject_from_goal_area(spot, 0, 1.0)
	if Court.in_goal_area(spot, 1):
		spot = Court.eject_from_goal_area(spot, 1, 1.0)
	# Nudge slightly toward midfield so the award team faces a playable angle.
	var mid_sign := 1.0 if awarding_team_id == 0 else -1.0
	# Prefer facing attack: home wants +Z space.
	if absf(spot.z) > 14.0:
		spot.z = clampf(spot.z - mid_sign * 0.5, -16.5, 16.5)
	return spot
