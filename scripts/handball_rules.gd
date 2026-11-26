extends RefCounted
class_name HandballRules

## Phase 2 sport-logic approximations. MatchController owns restarts; this tracks
## steps, passive play, OOB, and goal-area violations and reports when they fire.
## Phase B: 3 s hold + dribble stream (step/hold reset on catch) + double-dribble lite.
## Phase C: IHF-inspired passive hybrid — progress/tempo warns, then pass-count.
## Phase D: contact lite during shoot/pass windup → FT / heuristic 7 m (+ exclusion flag).
## Wave 4: soft auto-dribble helpers; foul ladder (head touch / head hit / behind push);
## 9 m snap for deep FTs; hardened clear-chance → 7 m.

signal rule_warning(code: String, message: String)
signal rule_violation(code: String, message: String, awarding_team_id: int, spot: Vector3)
## Fired when a counted floor step is taken (HUD pulse / glanceable counter).
signal step_taken(steps: int)
## Fired on every floor plant while holding (incl. reception-zero). For pivot teaching.
signal foot_planted(steps: int, reception_zero: bool)

const MAX_STEPS := 3
## Planar distance per counted foot-plant while carrying. Slightly longer gait so
## a full drive (~3 plants) feels fair before the pass/shoot decision.
const STEP_LENGTH_M := 1.8
## Below this planar speed the carrier is pivoting / stopped — no new steps.
const MOVE_SPEED_MPS := 0.75
## Must stay slow this long before pivot locks (filters stick noise).
const STOP_SETTLE_S := 0.1
## Pivot foot identity for 3-step teaching (−1 none, 0 left, 1 right).
const PIVOT_NONE := -1
const PIVOT_LEFT := 0
const PIVOT_RIGHT := 1
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
## Soft assist: auto-start a legal dribble before the 3 s whistle (Wave 4 / R3.2).
const HOLD_ASSIST_S := 2.55
## Soft assist: auto-dribble when on the last counted step (Wave 4 / R3.3).
const STEPS_ASSIST_AT := 3
## Master switch for hold/step auto-dribble helpers (never forces a double-dribble).
const AUTO_DRIBBLE_ASSIST := true

## Phase D / Wave 4 contact (tunable feel knobs — weightier body checks).
## Defender reach-in / body-check volume while attacker windups near 6–9 m.
const CONTACT_REACH_M := 1.12
## Arc band from defending goal end where contact during windup is a foul.
const FOUL_ARC_MIN_M := 6.0
const FOUL_ARC_MAX_M := 9.5
## Clear-chance heuristic: airborne shooter inside this distance → 7 m.
## Approx (not full IHF referee judgment) — documented in README.
const CLEAR_CHANCE_DIST_M := 8.0
## Grounded 1v1 clear-chance inside this distance with behind contact (Wave 4 harden).
const CLEAR_CHANCE_GROUND_DIST_M := 7.0
## Brief overlap before whistle — longer = heavier contact weight.
const CONTACT_HOLD_S := 0.07
## Dot of defender direction vs carrier facing; ≤ this = behind/side (not front).
const BEHIND_SIDE_DOT := 0.28
## Strict behind for push/pull exclusion (front defense must not false-positive).
const BEHIND_PUSH_DOT := -0.15
## Head/neck contact uses carrier HeadRegion (Wave 1 anchor) — approx radius.
const HEAD_CONTACT_M := 0.58
## Relative approach speed into the head that upgrades touch → hit (red).
const HEAD_HIT_APPROACH_MPS := 2.45
## When true, seven_m fouls set last_foul_warrants_exclusion for MatchController.
const EXCLUDE_ON_SEVEN_M := true
## Approx ready-window for a 7 m taker before sandbox turnover (Wave 4 / R3.11).
const SEVEN_M_READY_LIMIT_S := 5.0

var enabled: bool = true
var last_touch_team_id: int = 0
## Last defender who committed a contact foul (MatchController reads for exclusion).
var last_fouler: Player = null
## True when the latest contact foul should trigger a 2-min exclusion lite.
var last_foul_warrants_exclusion: bool = false
## True when the latest foul is a violent head strike → red / DQ (sandbox).
var last_foul_warrants_red: bool = false
## Last foul taxonomy for HUD / restart copy.
## "" | "ordinary" | "behind_push" | "head_touch" | "head_hit" | "clear_chance"
var last_foul_kind: String = ""
## Soft assist started the current dribble stream (HUD shows AUTO).
var last_dribble_was_assist: bool = false

var _steps: int = 0
var _step_accum: float = 0.0
var _carrier_last_xz: Vector3 = Vector3.ZERO
var _have_carrier_sample: bool = false
## IHF-ish reception zero: first plant after catch does not count.
var _reception_zero_pending: bool = false
var _pivoting: bool = false
var _stop_timer: float = 0.0
var _steps_warned: bool = false
## Which foot is the planted pivot while holding without dribbling (R1.6 teaching).
var _pivot_foot: int = PIVOT_NONE

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

## Phase D: MatchController sets while shoot charge / pass act is live.
var _windup_active: bool = false
var _windup_is_shot: bool = false
var _contact_timers: Dictionary = {} ## defender instance_id -> float


func reset_possession_tracking() -> void:
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_reception_zero_pending = false
	_pivoting = false
	_stop_timer = 0.0
	_steps_warned = false
	_pivot_foot = PIVOT_NONE
	_clear_passive()
	_possession_team_id = -1
	_reset_hold_and_dribble()
	_area_timers.clear()
	_contact_timers.clear()
	_windup_active = false
	_windup_is_shot = false
	last_fouler = null
	last_foul_warrants_exclusion = false
	last_foul_warrants_red = false
	last_foul_kind = ""
	last_dribble_was_assist = false


func begin_lockout() -> void:
	_lockout = true
	reset_possession_tracking()


func end_lockout() -> void:
	_lockout = false
	_oob_cooldown = OOB_COOLDOWN_S


## Call each frame from MatchController: shoot charge and/or pass act.
func set_windup(active: bool, is_shot: bool = true) -> void:
	_windup_active = active
	_windup_is_shot = is_shot if active else false
	if not active:
		_contact_timers.clear()


## Instant pass-act probe (pass has no charge window). Returns true if foul emitted.
func probe_pass_act_contact(ball: Ball, players: Array[Player]) -> bool:
	if not enabled or _lockout or ball == null or ball.carrier == null:
		return false
	if ball.carrier.is_goalkeeper:
		return false
	set_windup(true, false)
	var hit := _evaluate_contact(ball.carrier, players, true)
	set_windup(false, false)
	return hit


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
	# Catch / land plant: provisional pivot so the 3-step rule teaches itself (R1.6).
	_pivot_foot = _catch_pivot_foot(player)

	# GK possession is exempt — clears any pending passive on the attack.
	if player.is_goalkeeper:
		_pivot_foot = PIVOT_NONE
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
	_pivot_foot = PIVOT_NONE
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


## Pivot foot while holding without dribbling: PIVOT_NONE / LEFT / RIGHT.
func get_pivot_foot() -> int:
	return _pivot_foot


func pivot_foot_label() -> String:
	match _pivot_foot:
		PIVOT_LEFT:
			return "L"
		PIVOT_RIGHT:
			return "R"
		_:
			return ""


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


## True when a soft assist may legally start a dribble (not after gather).
func can_auto_dribble(player: Player) -> bool:
	if not AUTO_DRIBBLE_ASSIST or not enabled or _lockout:
		return false
	if player == null or player.is_goalkeeper:
		return false
	if _is_dribbling or player.dribbling or _dribble_caught:
		return false
	var near_hold := _hold_timer >= HOLD_ASSIST_S
	var near_steps := _steps >= STEPS_ASSIST_AT
	return near_hold or near_steps


## Soft auto-start dribble near 3 s / step limit when legal (never double-dribble).
## Returns true if a new bounce stream began via assist.
func try_auto_dribble_assist(player: Player) -> bool:
	if not can_auto_dribble(player):
		return false
	if not try_begin_dribble(player):
		return false
	# try_begin_dribble clears the flag — re-arm after a successful assist begin.
	last_dribble_was_assist = true
	return true


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
	_pivot_foot = PIVOT_NONE
	_hold_timer = 0.0
	_hold_warned = false
	last_dribble_was_assist = false
	return true


## Gather / catch the bounce stream → new 3 steps + fresh 3 s; further dribble = fault.
func end_dribble(player: Player) -> void:
	if player == null:
		return
	if not _is_dribbling:
		return
	_is_dribbling = false
	_dribble_caught = true
	last_dribble_was_assist = false
	_steps = 0
	_step_accum = 0.0
	_have_carrier_sample = false
	_reception_zero_pending = true
	_pivoting = false
	_stop_timer = 0.0
	_steps_warned = false
	_hold_timer = 0.0
	_hold_warned = false
	# Gather plant — same as catch: provisional pivot until the next free-foot step.
	_pivot_foot = _catch_pivot_foot(player)


func _reset_hold_and_dribble() -> void:
	_hold_timer = 0.0
	_hold_warned = false
	_is_dribbling = false
	_dribble_caught = false
	last_dribble_was_assist = false


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
			_pivot_foot = PIVOT_NONE
		elif not carrier.dribbling and _is_dribbling:
			end_dribble(carrier)
		# Contact during shoot/pass windup near the arc (Phase D) — before hold/steps.
		if _windup_active and not carrier.is_goalkeeper:
			if _tick_contact(delta, carrier, players):
				return true
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
		_pivot_foot = PIVOT_NONE
		_reset_hold_and_dribble()
		_contact_timers.clear()

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
		_pivot_foot = PIVOT_NONE
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
			# Keep the planted pivot foot while pivoting (free foot may lift visually).
			if _pivot_foot == PIVOT_NONE:
				_pivot_foot = _catch_pivot_foot(carrier)
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
			_register_plant(false)
			continue
		_steps += 1
		_register_plant(true)
		step_taken.emit(_steps)
		if _steps == MAX_STEPS and not _steps_warned:
			_steps_warned = true
			rule_warning.emit("steps", "Last step — pass, shoot, or dribble")
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


## Catch / gather provisional plant: prefer the more-forward shoe, else right.
func _catch_pivot_foot(player: Player) -> int:
	if player == null:
		return PIVOT_RIGHT
	if player.has_method("preferred_catch_pivot_foot"):
		var pref: int = int(player.preferred_catch_pivot_foot())
		if pref == PIVOT_LEFT or pref == PIVOT_RIGHT:
			return pref
	return PIVOT_RIGHT


## Legal plant: reception zero confirms catch plant; counted steps flip free→pivot.
func _register_plant(counted: bool) -> void:
	var reception_zero := not counted
	if counted:
		# Free foot plants and becomes the new pivot; old pivot frees.
		if _pivot_foot == PIVOT_LEFT:
			_pivot_foot = PIVOT_RIGHT
		elif _pivot_foot == PIVOT_RIGHT:
			_pivot_foot = PIVOT_LEFT
		else:
			_pivot_foot = PIVOT_RIGHT
	elif _pivot_foot == PIVOT_NONE:
		_pivot_foot = PIVOT_RIGHT
	foot_planted.emit(_steps, reception_zero)


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
		if p == null or p.is_goalkeeper or p.on_bench or p.excluded:
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
	# Wave 4 / R3.10: deep fouls snap to the 9 m line of the defending goal.
	var spot := Court.clamp_to_court_xz(near, 1.2)
	if Court.in_goal_area(spot, 0):
		spot = Court.eject_from_goal_area(spot, 0, 1.0)
	if Court.in_goal_area(spot, 1):
		spot = Court.eject_from_goal_area(spot, 1, 1.0)
	var defend_team := 1 - awarding_team_id
	if Court.in_nine_meter_area(spot, defend_team):
		spot = Court.eject_from_nine_meter(spot, defend_team, 0.2)
	# Nudge slightly toward midfield so the award team faces a playable angle.
	var mid_sign := 1.0 if awarding_team_id == 0 else -1.0
	# Prefer facing attack: home wants +Z space.
	if absf(spot.z) > 14.0:
		spot.z = clampf(spot.z - mid_sign * 0.5, -16.5, 16.5)
	return spot


func _tick_contact(delta: float, carrier: Player, players: Array[Player]) -> bool:
	# Accumulate overlap, then whistle (arcade bump → FT / 7 m).
	var fouler := _find_contact_fouler(carrier, players)
	if fouler == null:
		_contact_timers.clear()
		return false
	var id := fouler.get_instance_id()
	var t: float = float(_contact_timers.get(id, 0.0)) + delta
	_contact_timers[id] = t
	# Drop timers for other defenders so a brush doesn't linger.
	for key in _contact_timers.keys():
		if int(key) != id:
			_contact_timers.erase(key)
	if t < CONTACT_HOLD_S:
		return false
	return _emit_contact_foul(carrier, fouler)


## Immediate evaluate (pass act / smoke). Skips the short hold when `instant`.
func _evaluate_contact(carrier: Player, players: Array[Player], instant: bool) -> bool:
	var fouler := _find_contact_fouler(carrier, players)
	if fouler == null:
		return false
	if not instant:
		var id := fouler.get_instance_id()
		_contact_timers[id] = CONTACT_HOLD_S
	return _emit_contact_foul(carrier, fouler)


func _find_contact_fouler(carrier: Player, players: Array[Player]) -> Player:
	if carrier == null or not _in_attack_foul_zone(carrier.global_position, carrier.team_id):
		return null
	var best: Player = null
	var best_d := INF
	for p in players:
		if p == null or p == carrier or p.is_goalkeeper:
			continue
		if p.team_id == carrier.team_id:
			continue
		# Excluded defenders are off the court.
		if p.excluded or p.on_bench:
			continue
		var d := _planar_distance(carrier.global_position, p.global_position)
		if d > CONTACT_REACH_M:
			continue
		if d < best_d:
			best_d = d
			best = p
	return best


func _emit_contact_foul(carrier: Player, fouler: Player) -> bool:
	last_fouler = fouler
	last_foul_warrants_exclusion = false
	last_foul_warrants_red = false
	last_foul_kind = "ordinary"
	var award := carrier.team_id
	var dist_goal := _dist_to_defend_goal(carrier.global_position, 1 - carrier.team_id)
	var behind_side := _is_contact_from_behind_or_side(carrier, fouler)
	var behind_push := _is_contact_from_behind(carrier, fouler)
	var head_sev := _head_contact_severity(carrier, fouler)
	# Clear-chance heuristic (approx): airborne shooter inside ~8 m + behind/side,
	# or grounded 1v1 shot windup inside ~7 m with behind contact (Wave 4 harden).
	# Height/up-velocity count even if floor contact is sticky after a teleport frame.
	var airborne_shot := (
		_is_airborne(carrier)
		or carrier.global_position.y > 0.85
		or carrier.velocity.y > 1.0
	)
	var clear_air := (
		_windup_is_shot
		and airborne_shot
		and dist_goal <= CLEAR_CHANCE_DIST_M
		and behind_side
	)
	var clear_ground := (
		_windup_is_shot
		and not airborne_shot
		and dist_goal <= CLEAR_CHANCE_GROUND_DIST_M
		and behind_push
	)
	# Illegal defense in the crease during a shot windup near goal → 7 m (approx).
	var illegal_area_def := (
		_windup_is_shot
		and dist_goal <= CLEAR_CHANCE_DIST_M
		and Court.in_goal_area(fouler.global_position, 1 - carrier.team_id)
	)
	var clear_chance := clear_air or clear_ground or illegal_area_def

	# Wave 4 foul ladder (severity first):
	# head hit → red; head touch → 2'; clear chance → 7 m; behind push → 2'; else FT.
	if head_sev == "hit":
		last_foul_kind = "head_hit"
		last_foul_warrants_red = true
		last_foul_warrants_exclusion = false
		if clear_chance:
			var spot7 := Court.seven_meter_spot(1 - award)
			rule_violation.emit(
				"seven_m",
				"7 m — red — head contact",
				award,
				spot7
			)
			return true
		var ft_hit := _free_throw_spot(Court.clamp_to_court_xz(carrier.global_position, 1.0), award)
		rule_violation.emit("foul", "Red — head contact", award, ft_hit)
		return true

	if head_sev == "touch":
		last_foul_kind = "head_touch"
		last_foul_warrants_exclusion = true
		if clear_chance:
			var spot_ht := Court.seven_meter_spot(1 - award)
			rule_violation.emit(
				"seven_m",
				"7 m — head/neck contact",
				award,
				spot_ht
			)
			return true
		var ft_touch := _free_throw_spot(Court.clamp_to_court_xz(carrier.global_position, 1.0), award)
		rule_violation.emit("foul", "2 min — head/neck contact", award, ft_touch)
		return true

	if clear_chance:
		last_foul_kind = "clear_chance"
		last_foul_warrants_exclusion = EXCLUDE_ON_SEVEN_M
		var spot := Court.seven_meter_spot(1 - award)
		rule_violation.emit(
			"seven_m",
			"7 m — clear chance (heuristic)",
			award,
			spot
		)
		return true

	if behind_push:
		last_foul_kind = "behind_push"
		last_foul_warrants_exclusion = true
		var ft_behind := _free_throw_spot(Court.clamp_to_court_xz(carrier.global_position, 1.0), award)
		rule_violation.emit("foul", "2 min — push from behind", award, ft_behind)
		return true

	# Default arcade path: free throw at foul spot (front / ordinary contact).
	var ft := Court.clamp_to_court_xz(carrier.global_position, 1.0)
	ft = _free_throw_spot(ft, award)
	rule_violation.emit("foul", "Foul — free throw", award, ft)
	return true


func _in_attack_foul_zone(pos: Vector3, attack_team_id: int) -> bool:
	var defend_team := 1 - attack_team_id
	var dist := _dist_to_defend_goal(pos, defend_team)
	# Allow head-contact fouls slightly deeper / wider; zone still centers on 6–9 m.
	return dist >= FOUL_ARC_MIN_M - 0.4 and dist <= FOUL_ARC_MAX_M + 0.6


func _dist_to_defend_goal(pos: Vector3, defending_team_id: int) -> float:
	var end_z := -Court.HALF_LENGTH if defending_team_id == 0 else Court.HALF_LENGTH
	var nearest_x := clampf(pos.x, -Court.GOAL_WIDTH * 0.5, Court.GOAL_WIDTH * 0.5)
	var dx := pos.x - nearest_x
	var dz := pos.z - end_z
	return sqrt(dx * dx + dz * dz)


func _is_contact_from_behind_or_side(carrier: Player, defender: Player) -> bool:
	return _facing_dot_to_defender(carrier, defender) <= BEHIND_SIDE_DOT


## Stricter behind heuristic for push/pull exclusion (R3.7) — front defense stays clean.
func _is_contact_from_behind(carrier: Player, defender: Player) -> bool:
	return _facing_dot_to_defender(carrier, defender) <= BEHIND_PUSH_DOT


func _facing_dot_to_defender(carrier: Player, defender: Player) -> float:
	var face := carrier.face_direction()
	face.y = 0.0
	if face.length_squared() < 0.0001:
		face = Vector3(0.0, 0.0, 1.0 if carrier.team_id == 0 else -1.0)
	else:
		face = face.normalized()
	var to_def := Vector3(
		defender.global_position.x - carrier.global_position.x,
		0.0,
		defender.global_position.z - carrier.global_position.z
	)
	if to_def.length_squared() < 0.0001:
		return -1.0
	to_def = to_def.normalized()
	return face.dot(to_def)


## Uses carrier HeadRegion (Wave 1). Returns "" | "touch" | "hit".
func _head_contact_severity(carrier: Player, fouler: Player) -> String:
	if carrier == null or fouler == null:
		return ""
	var head := carrier.get_head_region() if carrier.has_method("get_head_region") else null
	var head_pos: Vector3
	if head != null:
		head_pos = head.global_position
	else:
		head_pos = carrier.global_position + Vector3(0.0, 1.72, 0.0)
	# Defender reach into head/neck height (hands / upper torso approx).
	var reach := fouler.global_position + Vector3(0.0, 1.55, 0.0)
	var d := reach.distance_to(head_pos)
	var planar := _planar_distance(carrier.global_position, fouler.global_position)
	if d > HEAD_CONTACT_M and not (planar <= 0.55 and absf(reach.y - head_pos.y) <= 0.4):
		return ""
	# Approach speed into the head upgrades touch → violent hit (red).
	# Positive = fouler closing on the head relative to the carrier.
	var rel := fouler.velocity - carrier.velocity
	var to_head := Vector3(head_pos.x - reach.x, 0.0, head_pos.z - reach.z)
	var approach := 0.0
	if to_head.length_squared() > 0.0001:
		approach = rel.dot(to_head.normalized())
	var airborne_fouler := (
		fouler.global_position.y > 0.55
		or fouler.velocity.y > 1.4
		or fouler.diving
	)
	if approach >= HEAD_HIT_APPROACH_MPS or airborne_fouler:
		return "hit"
	return "touch"


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)
