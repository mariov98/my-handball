extends RefCounted
class_name Formations

## Phase 4 tactics lite + Phase E shape presets + Phase G full outfield.
## On-court roster: LW / LB / CB / RB / RW / Pivot + GK (7).
## Attack Wide (3-3) vs Crash (2-4). Defense Flat (6-0) vs OneUp (5-1).

enum Role { GK, LEFT_WING, LEFT_BACK, CENTER_BACK, RIGHT_BACK, RIGHT_WING, PIVOT }
## Attack shape presets (full-roster reading of 3-3 / 2-4).
enum AttackShape { WIDE, CRASH }
## Defense shape presets (full-roster reading of 6-0 / 5-1).
enum DefenseShape { FLAT, ONE_UP }

const FREE_THROW_LINE_M := 9.0 ## Distance from goal end for 9 m-style wall / free throws.
const ATTACK_ARC_M := 9.2 ## Wings sit near the free-throw arc.
const BACKCOURT_DEPTH_M := 12.5 ## Backcourt depth from opponent goal.
const HALFBACK_DEPTH_M := 11.0 ## LB/RB depth (slightly ahead of CB).
const PIVOT_DEPTH_M := 7.2 ## Line player just outside 6 m.
const DEFENSE_LINE_M := 7.6 ## Flat defenders stand outside own 6 m.
const ONE_UP_DEPTH_M := 9.4 ## OneUp CB steps toward ~9 m on the ball.
const WALL_GAP_M := 3.2 ## Min distance defenders keep from free-throw taker.
## Phase G: court roles use player_index 0–6 (GK + 6 outfield).
const COURT_OUTFIELD_COUNT := 6


## Map roster index → role. On court: 0=GK, 1=LW, 2=LB, 3=CB, 4=RB, 5=RW, 6=Pivot.
## Bench bodies keep their parked index (≥7) until a sub swaps a court role onto them.
static func role_for(player: Player) -> Role:
	if player == null or player.is_goalkeeper:
		return Role.GK
	# Bench reserves are not court roles — callers should skip on_bench players.
	if player.on_bench:
		return Role.CENTER_BACK
	match player.player_index:
		1:
			return Role.LEFT_WING
		2:
			return Role.LEFT_BACK
		3:
			return Role.CENTER_BACK
		4:
			return Role.RIGHT_BACK
		5:
			return Role.RIGHT_WING
		6:
			return Role.PIVOT
		_:
			return Role.CENTER_BACK


static func role_label(role: Role) -> String:
	match role:
		Role.GK:
			return "GK"
		Role.LEFT_WING:
			return "LW"
		Role.LEFT_BACK:
			return "LB"
		Role.CENTER_BACK:
			return "CB"
		Role.RIGHT_BACK:
			return "RB"
		Role.RIGHT_WING:
			return "RW"
		Role.PIVOT:
			return "P"
		_:
			return "CB"


## HUD label. Phase G has real LB/RB/P — no cosmetic CB remap.
static func role_label_hud(role: Role, _ball_x: float = 0.0, _remap_cb_by_ball: bool = true) -> String:
	return role_label(role)


static func attack_shape_label(shape: AttackShape) -> String:
	match shape:
		AttackShape.CRASH:
			return "Crash"
		_:
			return "Wide"


static func defense_shape_label(shape: DefenseShape) -> String:
	match shape:
		DefenseShape.ONE_UP:
			return "OneUp"
		_:
			return "Flat"


static func attack_shape_of(player: Player) -> AttackShape:
	if player == null:
		return AttackShape.WIDE
	return player.attack_shape as AttackShape


static func defense_shape_of(player: Player) -> DefenseShape:
	if player == null:
		return DefenseShape.FLAT
	return player.defense_shape as DefenseShape


static func is_wing(role: Role) -> bool:
	return role == Role.LEFT_WING or role == Role.RIGHT_WING


static func is_backcourt(role: Role) -> bool:
	return role == Role.LEFT_BACK or role == Role.CENTER_BACK or role == Role.RIGHT_BACK


## Approx screen: stand between pivot and a marking defender.
static func screen_slot(pivot_pos: Vector3, defender_pos: Vector3, team_id: int) -> Vector3:
	var pivot := Vector3(pivot_pos.x, 0.0, pivot_pos.z)
	var defender := Vector3(defender_pos.x, 0.0, defender_pos.z)
	# Bias slightly toward the defender so the seal reads as a screen, not a stack.
	var slot := pivot.lerp(defender, 0.55)
	# Nudge a touch toward own attack so the screen isn't behind the pivot.
	var attack_sign := 1.0 if team_id == 0 else -1.0
	slot.z += attack_sign * 0.35
	return _legalize_outfield(slot, team_id)


## Off-ball "show for pass": attack slot nudged into an open lane toward the ball.
## Crash shape: ball-side wing can set a light screen between pivot and nearest defender.
static func show_for_pass_slot(
	player: Player,
	ball_pos: Vector3,
	pivot: Player = null,
	screen_defender: Player = null
) -> Vector3:
	var slot := attack_slot(player, ball_pos)
	if player == null or player.is_goalkeeper:
		return slot
	if player.on_bench or player.excluded:
		return slot
	var role := role_for(player)
	var shape := attack_shape_of(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var ball_xz := Vector3(ball_pos.x, 0.0, ball_pos.z)

	# Crash soft-pivot screen: ball-side wing seals between pivot and a defender (approx).
	if (
		shape == AttackShape.CRASH
		and pivot != null
		and screen_defender != null
		and is_wing(role)
	):
		var ball_side_wing := (
			(role == Role.LEFT_WING and ball_xz.x <= 0.6)
			or (role == Role.RIGHT_WING and ball_xz.x >= -0.6)
		)
		if ball_side_wing:
			return screen_slot(pivot.global_position, screen_defender.global_position, player.team_id)

	# Step slightly toward the ball on depth so the passing lane is live.
	slot.z = lerpf(slot.z, ball_xz.z + attack_sign * 1.2, 0.28)
	match role:
		Role.LEFT_WING:
			slot.x = lerpf(slot.x, minf(slot.x + 1.1, -3.6), 0.35)
			slot.x = clampf(slot.x, -8.6, -3.2)
		Role.RIGHT_WING:
			slot.x = lerpf(slot.x, maxf(slot.x - 1.1, 3.6), 0.35)
			slot.x = clampf(slot.x, 3.2, 8.6)
		Role.LEFT_BACK:
			slot.x = lerpf(slot.x, minf(slot.x + 0.8, -2.0), 0.35)
			slot.x = clampf(slot.x, -6.5, -1.2)
		Role.RIGHT_BACK:
			slot.x = lerpf(slot.x, maxf(slot.x - 0.8, 2.0), 0.35)
			slot.x = clampf(slot.x, 1.2, 6.5)
		Role.CENTER_BACK:
			if shape == AttackShape.CRASH:
				slot.x = lerpf(slot.x, ball_xz.x * 0.35, 0.4)
				slot.x = clampf(slot.x, -2.4, 2.4)
			else:
				slot.x = lerpf(slot.x, ball_xz.x * 0.4, 0.4)
				slot.x = clampf(slot.x, -2.8, 2.8)
				slot.z = lerpf(slot.z, ball_xz.z + attack_sign * 2.2, 0.2)
		Role.PIVOT:
			slot.x = lerpf(slot.x, ball_xz.x * 0.55, 0.5)
			slot.x = clampf(slot.x, -2.6, 2.6)
		_:
			pass
	return _legalize_outfield(slot, player.team_id)


## Attack spacing relative to opponent goal. Shape presets drive backcourt / pivot depth.
static func attack_slot(player: Player, ball_pos: Vector3) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return _gk_slot(player)
	if player.on_bench or player.excluded:
		return Court.bench_marker(player.team_id, maxi(0, player.bench_slot))

	var role := role_for(player)
	var shape := attack_shape_of(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var ball_x := clampf(ball_pos.x, -7.0, 7.0)
	var progress := clampf(absf(ball_pos.z) / 16.0, 0.0, 1.0)
	# Wide (3-3): soft line bias only when deep. Crash (2-4): pivot + halfbacks push earlier.
	var deep_ball := false
	if shape == AttackShape.CRASH:
		deep_ball = (ball_pos.z * attack_sign) > -1.0
	else:
		deep_ball = progress > 0.55 and absf(ball_pos.z - goal_z) < 14.0

	var wing_x := 7.6 if shape == AttackShape.CRASH else 7.2
	var slot := Vector3.ZERO
	match role:
		Role.LEFT_WING:
			slot = Vector3(-wing_x + ball_x * 0.08, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			slot.x = clampf(slot.x, -8.6, -4.0)
		Role.RIGHT_WING:
			slot = Vector3(wing_x + ball_x * 0.08, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			slot.x = clampf(slot.x, 4.0, 8.6)
		Role.LEFT_BACK:
			var lb_depth := PIVOT_DEPTH_M + 2.4 if (shape == AttackShape.CRASH and deep_ball) else HALFBACK_DEPTH_M
			slot = Vector3(-4.2 + ball_x * 0.12, 0.0, goal_z - attack_sign * lb_depth)
			slot.x = clampf(slot.x, -6.8, -1.8)
		Role.RIGHT_BACK:
			var rb_depth := PIVOT_DEPTH_M + 2.4 if (shape == AttackShape.CRASH and deep_ball) else HALFBACK_DEPTH_M
			slot = Vector3(4.2 + ball_x * 0.12, 0.0, goal_z - attack_sign * rb_depth)
			slot.x = clampf(slot.x, 1.8, 6.8)
		Role.CENTER_BACK:
			if shape == AttackShape.CRASH and deep_ball:
				# Crash: CB can float behind the line as a shooting option.
				slot = Vector3(ball_x * 0.2, 0.0, goal_z - attack_sign * (PIVOT_DEPTH_M + 3.5))
				slot.x = clampf(slot.x, -2.6, 2.6)
			else:
				slot = Vector3(ball_x * 0.22, 0.0, goal_z - attack_sign * BACKCOURT_DEPTH_M)
				slot.x = clampf(slot.x, -2.8, 2.8)
		Role.PIVOT:
			# True line player — Crash holds the crease earlier.
			var piv_depth := PIVOT_DEPTH_M
			if shape == AttackShape.WIDE and not deep_ball:
				piv_depth = PIVOT_DEPTH_M + 1.6
			slot = Vector3(ball_x * 0.4, 0.0, goal_z - attack_sign * piv_depth)
			slot.x = clampf(slot.x, -2.6, 2.6)
		_:
			slot = player.start_position

	return _legalize_outfield(slot, player.team_id)


## Defense spacing: Flat = 6-across wall; OneUp = CB steps to ~9 m on the ball.
static func defense_slot(player: Player, ball_pos: Vector3, carrier: Player = null) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return _gk_slot(player)
	if player.on_bench or player.excluded:
		return Court.bench_marker(player.team_id, maxi(0, player.bench_slot))

	var role := role_for(player)
	var shape := defense_shape_of(player)
	var defend_sign := -1.0 if player.team_id == 0 else 1.0 # toward own goal from midfield
	var own_goal_z := -20.0 if player.team_id == 0 else 20.0
	var threat := ball_pos
	if carrier:
		threat = carrier.global_position
	var threat_x := clampf(threat.x, -7.5, 7.5)

	var lane_x := 0.0
	match role:
		Role.LEFT_WING:
			lane_x = -6.0
		Role.LEFT_BACK:
			lane_x = -3.6
		Role.CENTER_BACK:
			lane_x = 0.0
		Role.PIVOT:
			# Pivot marks the line / ball-side interior on the flat wall.
			lane_x = clampf(threat_x * 0.35, -1.8, 1.8)
		Role.RIGHT_BACK:
			lane_x = 3.6
		Role.RIGHT_WING:
			lane_x = 6.0
		_:
			lane_x = 0.0

	var slide := 0.18
	var line_depth := DEFENSE_LINE_M
	if shape == DefenseShape.ONE_UP and role == Role.CENTER_BACK:
		# 5-1-ish: CB presses up to ~9 m on the ball; others stay flat.
		slide = 0.55
		line_depth = ONE_UP_DEPTH_M
		lane_x = threat_x * 0.15
	lane_x = clampf(lane_x + threat_x * slide, -7.8, 7.8)
	var slot := Vector3(lane_x, 0.0, own_goal_z - defend_sign * line_depth)
	if not (shape == DefenseShape.ONE_UP and role == Role.CENTER_BACK):
		var mid_push := clampf((10.0 - absf(threat.z)) / 10.0, 0.0, 1.0)
		slot.z += (-defend_sign) * mid_push * 1.6
	else:
		var ball_push := clampf((absf(threat.z) - 4.0) / 10.0, -0.4, 1.0)
		slot.z += (-defend_sign) * ball_push * 1.2
	slot.z = clampf(slot.z, -16.5, 16.5)
	return _legalize_outfield(slot, player.team_id)


## Kickoff / period restart shape.
## Offense: own half, approaching center (before midfield), ≥3 m from ball.
## Defense: wall just outside own 6 m goal-area line (roles across).
static func kickoff_slot(player: Player, kickoff_team_id: int) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return player.start_position
	if player.on_bench or player.excluded:
		return Court.bench_marker(player.team_id, maxi(0, player.bench_slot))
	var role := role_for(player)
	var on_ball := player.team_id == kickoff_team_id
	var face := 1.0 if player.team_id == 0 else -1.0 # Home attacks +Z
	var slot := Vector3.ZERO
	if on_ball:
		# Attacking throw-off: stay in own half, stacked toward midfield.
		# Taker is placed near center separately; others hold ≥3 m clearance.
		match role:
			Role.LEFT_WING:
				slot = Vector3(-6.8, 0.0, -5.8 * face)
			Role.RIGHT_WING:
				slot = Vector3(6.8, 0.0, -5.8 * face)
			Role.LEFT_BACK:
				slot = Vector3(-3.6, 0.0, -4.2 * face)
			Role.RIGHT_BACK:
				slot = Vector3(3.6, 0.0, -4.2 * face)
			Role.CENTER_BACK:
				# Slightly deeper than the center taker so CB doesn't stack.
				slot = Vector3(0.0, 0.0, -3.4 * face)
			Role.PIVOT:
				slot = Vector3(0.0, 0.0, -6.6 * face)
			_:
				slot = Vector3(0.0, 0.0, -4.0 * face)
	else:
		# Defending throw-off: flat wall just outside own 6 m (DEFENSE_LINE_M).
		var own_goal_z := -Court.HALF_LENGTH if player.team_id == 0 else Court.HALF_LENGTH
		var defend_sign := -1.0 if player.team_id == 0 else 1.0
		var line_z := own_goal_z - defend_sign * DEFENSE_LINE_M
		var lane_x := 0.0
		match role:
			Role.LEFT_WING:
				lane_x = -6.2
			Role.LEFT_BACK:
				lane_x = -3.6
			Role.CENTER_BACK:
				lane_x = -1.1
			Role.PIVOT:
				lane_x = 1.1
			Role.RIGHT_BACK:
				lane_x = 3.6
			Role.RIGHT_WING:
				lane_x = 6.2
			_:
				lane_x = 0.0
		slot = Vector3(lane_x, 0.0, line_z)
	return _legalize_outfield(slot, player.team_id)


## Set-piece placement for Phase 2 restart codes.
static func is_free_throw_code(code: String) -> bool:
	return code in ["traveling", "passive", "goal_area", "free_throw", "hold", "double_dribble", "foul"]


static func is_seven_meter_code(code: String) -> bool:
	return code == "seven_m"


## Place one player for a restart. `taker` is the player who receives the ball.
static func set_piece_slot(
	player: Player,
	code: String,
	awarding_team_id: int,
	spot: Vector3,
	taker: Player
) -> Vector3:
	if player == null:
		return Vector3.ZERO
	# Bench / excluded stay on the sideline marker.
	if player.on_bench or player.excluded:
		return Court.bench_marker(player.team_id, maxi(0, player.bench_slot))

	if player.is_goalkeeper:
		if code == "goal_throw" and player.team_id == awarding_team_id:
			return player.start_position
		if is_seven_meter_code(code) and player.team_id != awarding_team_id:
			return player.start_position
		return player.start_position

	var is_award := player.team_id == awarding_team_id
	var role := role_for(player)

	if code == "goal_throw":
		return _goal_throw_outfield(player, awarding_team_id, role, is_award)

	if code == "throw_in":
		return _throw_in_slot(player, spot, awarding_team_id, role, is_award, taker)

	if is_seven_meter_code(code):
		return _seven_meter_slot(player, awarding_team_id, spot, taker, role, is_award)

	# Free-throw family — 9 m wall feel.
	if player == taker:
		var place := spot
		place.y = 0.0
		return _legalize_outfield(place, player.team_id)

	if is_award:
		return _free_throw_attack_slot(player, spot, awarding_team_id, role)
	return _free_throw_wall_slot(player, spot, awarding_team_id, role)


static func free_throw_taker_yaw(awarding_team_id: int, spot: Vector3) -> float:
	var face := 0.0 if awarding_team_id == 0 else PI
	if absf(spot.x) > 6.5:
		var inward := -PI * 0.5 if spot.x > 0.0 else PI * 0.5
		face = lerp_angle(face, inward, 0.35)
	return face


## Score teammates for switch-to-best. Higher = more useful.
static func switch_score(
	candidate: Player,
	controlled: Player,
	ball: Ball,
	attack_team_id: int
) -> float:
	if candidate == null or candidate == controlled:
		return -INF
	if candidate.excluded or candidate.on_bench:
		return -INF
	var ball_pos := ball.global_position if ball else Vector3.ZERO
	var d_ball := candidate.global_position.distance_to(ball_pos)
	var carrier: Player = ball.carrier if ball else null

	# Free ball: prefer nearest teammate (especially outfield).
	if carrier == null:
		var score := 40.0 - d_ball
		if not candidate.is_goalkeeper:
			score += 6.0
		return score

	# Own team has the ball: prefer open receiver (not the carrier).
	if carrier.team_id == candidate.team_id:
		if candidate == carrier:
			return 100.0
		if candidate.is_goalkeeper:
			return 5.0 - d_ball * 0.1
		var to_carrier := candidate.global_position.distance_to(carrier.global_position)
		var goal := candidate.opponent_goal_point()
		var toward_goal := carrier.global_position.distance_to(goal) - candidate.global_position.distance_to(goal)
		var open := clampf(to_carrier, 2.0, 10.0) * 1.4
		var score := 28.0 + open + toward_goal * 1.8
		var role := role_for(candidate)
		if is_wing(role):
			score += absf(candidate.global_position.x) * 0.35
		elif role == Role.PIVOT:
			score += 2.0
		return score

	# Defending: best defender = nearest dangerous threat, outfield preferred.
	var threat_pos := carrier.global_position
	var d_threat := candidate.global_position.distance_to(threat_pos)
	var own_goal := candidate.own_goal_point()
	var goal_cover := 12.0 - candidate.global_position.distance_to(own_goal)
	var score_d := 35.0 - d_threat + goal_cover * 0.5
	if candidate.is_goalkeeper:
		if absf(threat_pos.z - own_goal.z) < 10.0:
			score_d += 8.0
		else:
			score_d -= 12.0
	else:
		score_d += 4.0
	if signf(candidate.global_position.x) == signf(threat_pos.x) and absf(threat_pos.x) > 1.5:
		score_d += 3.0
	return score_d


static func _gk_slot(player: Player) -> Vector3:
	var home := player.start_position
	return Vector3(clampf(home.x, -3.0, 3.0), 0.0, home.z)


static func _legalize_outfield(slot: Vector3, team_id: int) -> Vector3:
	var out := Court.clamp_to_court_xz(slot, 0.9)
	out.y = 0.0
	if Court.in_goal_area(out, 0):
		out = Court.eject_from_goal_area(out, 0, 0.55)
	if Court.in_goal_area(out, 1):
		out = Court.eject_from_goal_area(out, 1, 0.55)
	out.x = clampf(out.x, -8.8, 8.8)
	out.z = clampf(out.z, -17.2, 17.2)
	return out


static func _goal_throw_outfield(
	player: Player,
	awarding_team_id: int,
	role: Role,
	is_award: bool
) -> Vector3:
	var face := 1.0 if awarding_team_id == 0 else -1.0
	var slot := Vector3.ZERO
	if is_award:
		match role:
			Role.LEFT_WING:
				slot = Vector3(-7.0, 0.0, -8.0 * face)
			Role.RIGHT_WING:
				slot = Vector3(7.0, 0.0, -8.0 * face)
			Role.LEFT_BACK:
				slot = Vector3(-4.0, 0.0, -5.5 * face)
			Role.RIGHT_BACK:
				slot = Vector3(4.0, 0.0, -5.5 * face)
			Role.PIVOT:
				slot = Vector3(0.0, 0.0, -3.0 * face)
			_:
				slot = Vector3(0.0, 0.0, -5.0 * face)
	else:
		match role:
			Role.LEFT_WING:
				slot = Vector3(-5.5, 0.0, 5.0 * face)
			Role.RIGHT_WING:
				slot = Vector3(5.5, 0.0, 5.0 * face)
			Role.LEFT_BACK:
				slot = Vector3(-3.0, 0.0, 4.0 * face)
			Role.RIGHT_BACK:
				slot = Vector3(3.0, 0.0, 4.0 * face)
			Role.PIVOT:
				slot = Vector3(0.0, 0.0, 2.5 * face)
			_:
				slot = Vector3(0.0, 0.0, 3.5 * face)
	return _legalize_outfield(slot, player.team_id)


static func _throw_in_slot(
	player: Player,
	spot: Vector3,
	awarding_team_id: int,
	role: Role,
	is_award: bool,
	taker: Player
) -> Vector3:
	if player == taker:
		var place := spot
		place.y = 0.0
		return place

	var side := signf(spot.x)
	if side == 0.0:
		side = 1.0
	var face := 1.0 if awarding_team_id == 0 else -1.0
	var slot := Vector3.ZERO
	if is_award:
		match role:
			Role.LEFT_WING:
				slot = Vector3(side * 5.5, 0.0, spot.z + face * 3.0)
			Role.RIGHT_WING:
				slot = Vector3(side * 3.0, 0.0, spot.z - face * 2.5)
			Role.LEFT_BACK:
				slot = Vector3(side * 3.5, 0.0, spot.z + face * 1.5)
			Role.RIGHT_BACK:
				slot = Vector3(side * 2.0, 0.0, spot.z - face * 1.0)
			Role.PIVOT:
				slot = Vector3(side * 1.2, 0.0, spot.z + face * 2.5)
			_:
				slot = Vector3(side * 2.0, 0.0, spot.z + face * 1.0)
	else:
		match role:
			Role.LEFT_WING:
				slot = Vector3(side * 4.5, 0.0, spot.z - face * 1.5)
			Role.RIGHT_WING:
				slot = Vector3(side * 2.5, 0.0, spot.z + face * 2.0)
			Role.LEFT_BACK:
				slot = Vector3(side * 3.0, 0.0, spot.z)
			Role.RIGHT_BACK:
				slot = Vector3(side * 1.8, 0.0, spot.z + face * 1.0)
			Role.PIVOT:
				slot = Vector3(side * 1.0, 0.0, spot.z - face * 0.5)
			_:
				slot = Vector3(side * 1.5, 0.0, spot.z)
	return _legalize_outfield(slot, player.team_id)


static func _free_throw_attack_slot(
	player: Player,
	spot: Vector3,
	awarding_team_id: int,
	role: Role
) -> Vector3:
	var attack_sign := 1.0 if awarding_team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var slot := Vector3.ZERO
	match role:
		Role.LEFT_WING:
			slot = Vector3(-7.0, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			if spot.x < -1.0:
				slot.z = lerpf(slot.z, spot.z, 0.25)
		Role.RIGHT_WING:
			slot = Vector3(7.0, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			if spot.x > 1.0:
				slot.z = lerpf(slot.z, spot.z, 0.25)
		Role.LEFT_BACK:
			slot = Vector3(-4.0, 0.0, spot.z - attack_sign * 2.5)
		Role.RIGHT_BACK:
			slot = Vector3(4.0, 0.0, spot.z - attack_sign * 2.5)
		Role.PIVOT:
			slot = Vector3(clampf(spot.x * 0.4, -2.2, 2.2), 0.0, goal_z - attack_sign * PIVOT_DEPTH_M)
		_:
			slot = Vector3(clampf(spot.x * 0.25, -2.5, 2.5), 0.0, spot.z - attack_sign * 3.5)
	return _legalize_outfield(slot, player.team_id)


static func _free_throw_wall_slot(
	player: Player,
	spot: Vector3,
	awarding_team_id: int,
	role: Role
) -> Vector3:
	var defend_team := 1 - awarding_team_id
	var own_goal_z := -20.0 if defend_team == 0 else 20.0
	var to_goal := Vector3(0.0, 0.0, own_goal_z) - Vector3(spot.x, 0.0, spot.z)
	var dir := to_goal.normalized() if to_goal.length_squared() > 0.01 else Vector3(0, 0, signf(own_goal_z))
	var wall_anchor := Vector3(spot.x, 0.0, spot.z) + dir * WALL_GAP_M
	var line_z := own_goal_z - signf(own_goal_z) * FREE_THROW_LINE_M
	if absf(spot.z - own_goal_z) < 12.0:
		wall_anchor.z = lerpf(wall_anchor.z, line_z, 0.55)

	var lateral := 0.0
	match role:
		Role.LEFT_WING:
			lateral = -3.6
		Role.LEFT_BACK:
			lateral = -2.2
		Role.CENTER_BACK:
			lateral = -0.6
		Role.PIVOT:
			lateral = 0.6
		Role.RIGHT_BACK:
			lateral = 2.2
		Role.RIGHT_WING:
			lateral = 3.6
		_:
			lateral = 0.0

	var side := Vector3(-dir.z, 0.0, dir.x)
	var slot := wall_anchor + side * lateral
	return _legalize_outfield(slot, player.team_id)


## 7 m: taker on the mark; only defending GK may stay near goal; outfield clear outside 9 m.
static func _seven_meter_slot(
	player: Player,
	awarding_team_id: int,
	spot: Vector3,
	taker: Player,
	role: Role,
	is_award: bool
) -> Vector3:
	if player == taker:
		var place := spot
		place.y = 0.0
		return place

	var defend_team := 1 - awarding_team_id
	var own_goal_z := -20.0 if defend_team == 0 else 20.0
	var attack_sign := 1.0 if awarding_team_id == 0 else -1.0
	var clear_z := own_goal_z - signf(own_goal_z) * (FREE_THROW_LINE_M + 1.8)
	var slot := Vector3.ZERO
	if is_award:
		match role:
			Role.LEFT_WING:
				slot = Vector3(-7.5, 0.0, clear_z - attack_sign * 1.5)
			Role.RIGHT_WING:
				slot = Vector3(7.5, 0.0, clear_z - attack_sign * 1.5)
			Role.LEFT_BACK:
				slot = Vector3(-4.5, 0.0, clear_z - attack_sign * 2.5)
			Role.RIGHT_BACK:
				slot = Vector3(4.5, 0.0, clear_z - attack_sign * 2.5)
			Role.PIVOT:
				slot = Vector3(0.0, 0.0, clear_z - attack_sign * 1.0)
			_:
				slot = Vector3(0.0, 0.0, clear_z - attack_sign * 3.5)
	else:
		match role:
			Role.LEFT_WING:
				slot = Vector3(-8.0, 0.0, clear_z)
			Role.RIGHT_WING:
				slot = Vector3(8.0, 0.0, clear_z)
			Role.LEFT_BACK:
				slot = Vector3(-5.0, 0.0, clear_z - signf(own_goal_z) * 1.0)
			Role.RIGHT_BACK:
				slot = Vector3(5.0, 0.0, clear_z - signf(own_goal_z) * 1.0)
			Role.PIVOT:
				slot = Vector3(-1.5, 0.0, clear_z - signf(own_goal_z) * 1.5)
			_:
				slot = Vector3(1.5, 0.0, clear_z - signf(own_goal_z) * 2.0)
	return _legalize_outfield(slot, player.team_id)
