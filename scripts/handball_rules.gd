extends RefCounted
class_name HandballRules

## Phase 2 sport-logic approximations. MatchController owns restarts; this tracks
## steps, passive play, OOB, and goal-area violations and reports when they fire.
## Phase B: 3 s hold + dribble stream (step/hold reset on catch) + double-dribble lite.
## Phase C: IHF-inspired passive hybrid — progress/tempo warns, then pass-count.

signal rule_warning(code: String, message: String)
signal rule_violation(code: String, message: String, awarding_team_id: int, spot: Vector3)
## Fired when a counted floor step is taken (HUD pulse / glanceable counter).
signal step_taken(steps: int)

const MAX_STEPS := 3
## Planar distance per counted foot-plant while carrying. Slightly longer gait so
## a full drive (~3 plants) feels fair before the pass/shoot decision.
const STEP_LENGTH_M := 1.8
## Below this planar speed the carrier is pivoting / stopped — no new steps.
const MOVE_SPEED_MPS := 0.75
## Must stay slow this long before pivot locks (filters stick noise).
const STOP_SETTLE_S := 0.1
## Passive v2 (IHF-inspired hybrid): stall without progress → warn; after warn,
## whistle on Nth same-team receive without a shot attempt. N=5 mirrors IHF
## (max 4 passes, whistle on 5th receive). Progress only delays/resets the warn.
const PASSIVE_WARN_S := 7.0
## Deprecated wall-clock turnover — kept for smoke/docs that still reference it.
## Post-warn enforcement is receive-count (PASSIVE_MAX_RECEIVES), not this timer.
const PASSIVE_TURNOVER_S := 11.0
const PASSIVE_PROGRESS_M := 1.5
## IHF-like: whistle on the 5th team receive after the forewarning signal.
const PASSIVE_MAX_RECEIVES := 5
## Brief grace so jump-shot landings / brush of the arc don't spam fouls.
const GOAL_AREA_GRACE_S := 0.22
const OOB_COOLDOWN_S := 0.4
## IHF-ish: hold ≤ 3 s without dribble / pass / shot.
const HOLD_MAX_S := 3.0
const HOLD_WARN_S := 2.4

var enabled: bool = true
var last_touch_team_id: int = 0

var _steps: int = 0
var _step_accum: float = 0.0
var _carrier_last_xz: Vector3 = Vector3.ZERO
var _have_carrier_sample: bool = false
## IHF-ish reception zero: first plant after catch does not count.
var _reception_zero_pending: bool = false
var _pivoting: bool = false
var _stop_timer: float = 0.0
var _steps_warned: bool = false

var _passive_timer: float = 0.0
var _passive_warned: bool = false
var _passive_best_dist: float = INF
## Same-team receives after the passive warning (0 until first post-warn catch).
var _passive_receives: int = 0
## Attack team currently under passive scrutiny (−1 = none).
var _passive_attack_team_id: int = -1
var _possession_team_id: int = -1

## Phase B dribble / hold.
var _hold_timer: float = 0.0
var _hold_warned: bool = false
var _is_dribbling: bool = false
## After gathering a dribble stream, a second stream is double-dribble.
var _dribble_caught: bool = false

var _area_timers: Dictionary = {} ## player instance_id -> float
var _oob_cooldown: float = 0.0
var _lockout: bool = false ## true while MatchController runs a restart


func reset_possession_tracking() -> void:
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_reception_zero_pending = false
	_pivoting = false
	_stop_timer = 0.0
	_steps_warned = false
	_clear_passive()
	_possession_team_id = -1
	_reset_hold_and_dribble()
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
	_reception_zero_pending = true
	_pivoting = false
	_stop_timer = 0.0
	_steps_warned = false
	_possession_team_id = player.team_id
	# Fresh catch: new 3 s + may start one dribble stream.
	_hold_timer = 0.0
	_hold_warned = false
	_is_dribbling = false
	_dribble_caught = false

	# GK possession is exempt — clears any pending passive on the attack.
	if player.is_goalkeeper:
		_clear_passive()
		return

	# Opponent steals / new attack → fresh passive window.
	if _passive_attack_team_id >= 0 and player.team_id != _passive_attack_team_id:
		_clear_passive()

	_passive_attack_team_id = player.team_id

	# After warn: each same-team receive counts; whistle on Nth (IHF-like).
	if _passive_warned:
		_passive_receives += 1
		if _passive_receives >= PASSIVE_MAX_RECEIVES:
			var spot := Court.clamp_to_court_xz(player.global_position, 1.0)
			spot = _free_throw_spot(spot, 1 - player.team_id)
			rule_violation.emit(
				"passive",
				"Passive play — pass limit",
				1 - player.team_id,
				spot
			)


func on_release(player: Player) -> void:
	if player == null:
		return
	last_touch_team_id = player.team_id
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_reception_zero_pending = false
	_pivoting = false
	_stop_timer = 0.0
	_steps_warned = false
	_possession_team_id = -1
	# Pass / shot clear the 3 s clock and end any bounce stream.
	_reset_hold_and_dribble()
	# Passive v2: keep warn + receive count across a same-team pass flight.
	# Shot clears via on_shot_attempt(); opponent pickup clears via on_pickup.


## Shot attempt (non-pass) clears passive — clarification lite.
func on_shot_attempt(player: Player = null) -> void:
	_clear_passive()
	if player != null:
		last_touch_team_id = player.team_id


func get_steps() -> int:
	return _steps


func is_pivoting() -> bool:
	return _pivoting


func is_steps_warned() -> bool:
	return _steps_warned


func get_passive_timer() -> float:
	return _passive_timer


func is_passive_warned() -> bool:
	return _passive_warned


func get_passive_receives() -> int:
	return _passive_receives


func get_passive_max_receives() -> int:
	return PASSIVE_MAX_RECEIVES


func get_hold_timer() -> float:
	return _hold_timer


func get_hold_remaining() -> float:
	return maxf(0.0, HOLD_MAX_S - _hold_timer)


func is_hold_warned() -> bool:
	return _hold_warned


func is_dribbling() -> bool:
	return _is_dribbling


func has_caught_dribble() -> bool:
	return _dribble_caught


func _clear_passive() -> void:
	_passive_timer = 0.0
	_passive_warned = false
	_passive_best_dist = INF
	_passive_receives = 0
	_passive_attack_team_id = -1


## Begin a continuous bounce stream. Returns false if a double-dribble violation
## was emitted (caller should not enter dribble visuals).
func try_begin_dribble(player: Player) -> bool:
	if player == null or _lockout or not enabled:
		return false
	if _is_dribbling:
		return true
	if _dribble_caught:
		var spot := Court.clamp_to_court_xz(player.global_position, 1.0)
		spot = _free_throw_spot(spot, 1 - player.team_id)
		rule_violation.emit(
			"double_dribble",
			"Double dribble",
			1 - player.team_id,
			spot
		)
		return false
	_is_dribbling = true
	_hold_timer = 0.0
	_hold_warned = false
	return true


## Gather / catch the bounce stream → new 3 steps + fresh 3 s; further dribble = fault.
func end_dribble(player: Player) -> void:
	if player == null:
		return
	if not _is_dribbling:
		return
	_is_dribbling = false
	_dribble_caught = true
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_reception_zero_pending = true
	_pivoting = false
	_stop_timer = 0.0
	_steps_warned = false
	_hold_timer = 0.0
	_hold_warned = false


func _reset_hold_and_dribble() -> void:
	_hold_timer = 0.0
	_hold_warned = false
	_is_dribbling = false
	_dribble_caught = false


## Returns true if a violation was emitted (caller should stop further checks).
func tick(delta: float, ball: Ball, players: Array[Player]) -> bool:
	if not enabled or _lockout or ball == null:
		return false
	if _oob_cooldown > 0.0:
		_oob_cooldown = maxf(0.0, _oob_cooldown - delta)

	var carrier: Player = ball.carrier
	if carrier:
		# Keep rules dribble flag aligned with player state (AI / restarts).
		if carrier.dribbling and not _is_dribbling and not _dribble_caught:
			_is_dribbling = true
		elif not carrier.dribbling and _is_dribbling:
			end_dribble(carrier)
		if _tick_hold(delta, carrier):
			return true
		if _tick_steps(delta, carrier):
			return true
		if _tick_passive(delta, carrier):
			return true
	else:
		_have_carrier_sample = false
		_steps = 0
		_step_accum = 0.0
		_reception_zero_pending = false
		_pivoting = false
		_stop_timer = 0.0
		_steps_warned = false
		_reset_hold_and_dribble()

	if _tick_oob(ball, carrier):
		return true
	if _tick_goal_areas(delta, players, carrier):
		return true
	return false


func _tick_hold(delta: float, carrier: Player) -> bool:
	if carrier.is_goalkeeper:
		_hold_timer = 0.0
		_hold_warned = false
		return false
	# Continuous bounce stream pauses the 3 s clock.
	if _is_dribbling or carrier.dribbling:
		_hold_timer = 0.0
		_hold_warned = false
		return false
	_hold_timer += delta
	if _hold_timer >= HOLD_WARN_S and not _hold_warned:
		_hold_warned = true
		rule_warning.emit("hold", "3 seconds — pass, shoot, or dribble")
	if _hold_timer >= HOLD_MAX_S:
		var spot := Court.clamp_to_court_xz(carrier.global_position, 1.0)
		spot = _free_throw_spot(spot, 1 - carrier.team_id)
		rule_violation.emit(
			"hold",
			"Held ball — 3 seconds",
			1 - carrier.team_id,
			spot
		)
		return true
	return false


func _is_airborne(player: Player) -> bool:
	# Prefer physics floor contact; fall back to height so teleports / early frames
	# still count as grounded for steps / crease rules.
	if player.is_on_floor():
		return false
	return player.global_position.y > 0.35 or player.velocity.y > 1.0


func _tick_steps(delta: float, carrier: Player) -> bool:
	var xz := Vector3(carrier.global_position.x, 0.0, carrier.global_position.z)
	if not _have_carrier_sample:
		_carrier_last_xz = xz
		_have_carrier_sample = true
		return false

	var moved := xz.distance_to(_carrier_last_xz)
	_carrier_last_xz = xz

	# While dribbling, movement is free — steps resume after gather/catch.
	if _is_dribbling or carrier.dribbling:
		_stop_timer = 0.0
		_pivoting = false
		_step_accum = 0.0
		return false

	# Jump-shot: airborne carries do not plant steps (release before landing).
	if _is_airborne(carrier):
		_stop_timer = 0.0
		return false

	var planar_speed := Vector3(carrier.velocity.x, 0.0, carrier.velocity.z).length()
	# Teleports / smoke synthesize position without velocity — treat meaningful
	# planar displacement as movement so tests and edge frames still plant.
	if moved > 0.02:
		planar_speed = maxf(planar_speed, moved / maxf(delta, 0.001))

	if planar_speed < MOVE_SPEED_MPS:
		_stop_timer += delta
		if _stop_timer >= STOP_SETTLE_S:
			# Pivot / stand: fair reset of the gait accumulator only — taken
			# steps stay (IHF: you don't get fresh steps from stopping).
			_pivoting = true
			_step_accum = 0.0
		return false

	_stop_timer = 0.0
	_pivoting = false
	if moved < 0.0001:
		return false

	_step_accum += moved
	while _step_accum >= STEP_LENGTH_M:
		_step_accum -= STEP_LENGTH_M
		# Reception zero: first plant after catch is free (catch / land pattern).
		if _reception_zero_pending:
			_reception_zero_pending = false
			continue
		_steps += 1
		step_taken.emit(_steps)
		if _steps == MAX_STEPS and not _steps_warned:
			_steps_warned = true
			rule_warning.emit("steps", "Last step — pass or shoot")
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
		_clear_passive()
		return false

	_passive_attack_team_id = carrier.team_id
	var goal := carrier.opponent_goal_point()
	var dist := Vector2(carrier.global_position.x - goal.x, carrier.global_position.z - goal.z).length()

	# Progress toward goal only delays / resets the *warning* (pre-signal).
	# After warn, only a shot attempt (or new attack / GK) clears passive.
	if not _passive_warned:
		if dist < _passive_best_dist - PASSIVE_PROGRESS_M:
			_passive_best_dist = dist
			_passive_timer = 0.0
			return false
		if _passive_best_dist == INF:
			_passive_best_dist = dist
		_passive_timer += delta
		if _passive_timer >= PASSIVE_WARN_S:
			_passive_warned = true
			_passive_receives = 0
			rule_warning.emit("passive", "Passive (lite) — shoot within pass limit")
		return false

	# Post-warn: receive-count is enforced in on_pickup. Tick only tracks tempo
	# for HUD; no wall-clock turnover (PASSIVE_TURNOVER_S is legacy).
	_passive_best_dist = minf(_passive_best_dist, dist)
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
