extends RefCounted
class_name Formations

## Phase 4 tactics lite — recognizable handball spacing for 3 outfield + GK.
## Roles: left wing / center back (backcourt) / right wing, with a soft pivot fill
## when the attack is near the 6 m. Defense is a simple 3-across wall outside the crease.

enum Role { GK, LEFT_WING, CENTER_BACK, RIGHT_WING }

const FREE_THROW_LINE_M := 9.0 ## Distance from goal end for 9 m-style wall / free throws.
const ATTACK_ARC_M := 9.2 ## Wings sit near the free-throw arc.
const BACKCOURT_DEPTH_M := 12.5 ## Center back depth from opponent goal.
const PIVOT_DEPTH_M := 7.2 ## Soft pivot fill just outside 6 m.
const DEFENSE_LINE_M := 7.6 ## Defenders stand outside own 6 m.
const WALL_GAP_M := 3.2 ## Min distance defenders keep from free-throw taker.


## Map roster index → role. Outfield: 1=LW, 2=CB, 3=RW.
static func role_for(player: Player) -> Role:
	if player == null or player.is_goalkeeper:
		return Role.GK
	match player.player_index:
		1:
			return Role.LEFT_WING
		3:
			return Role.RIGHT_WING
		_:
			return Role.CENTER_BACK


static func role_label(role: Role) -> String:
	match role:
		Role.GK:
			return "GK"
		Role.LEFT_WING:
			return "LW"
		Role.RIGHT_WING:
			return "RW"
		_:
			return "CB"


## Off-ball "show for pass": attack slot nudged into an open lane toward the ball.
## Keeps width/depth readable for wing↔CB↔wing circulation without stacking.
static func show_for_pass_slot(player: Player, ball_pos: Vector3) -> Vector3:
	var slot := attack_slot(player, ball_pos)
	if player == null or player.is_goalkeeper:
		return slot
	var role := role_for(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var ball_xz := Vector3(ball_pos.x, 0.0, ball_pos.z)
	# Step slightly toward the ball on depth so the passing lane is live.
	slot.z = lerpf(slot.z, ball_xz.z + attack_sign * 1.2, 0.28)
	match role:
		Role.LEFT_WING:
			# Hold width, cut a touch inside for a flat angle.
			slot.x = lerpf(slot.x, minf(slot.x + 1.1, -3.6), 0.35)
			slot.x = clampf(slot.x, -8.6, -3.2)
		Role.RIGHT_WING:
			slot.x = lerpf(slot.x, maxf(slot.x - 1.1, 3.6), 0.35)
			slot.x = clampf(slot.x, 3.2, 8.6)
		Role.CENTER_BACK:
			# Present between the wings, slightly ahead of the ball for a give-and-go feel.
			slot.x = lerpf(slot.x, ball_xz.x * 0.45, 0.4)
			slot.x = clampf(slot.x, -3.2, 3.2)
			slot.z = lerpf(slot.z, ball_xz.z + attack_sign * 2.4, 0.22)
		_:
			pass
	return _legalize_outfield(slot, player.team_id)


## Attack spacing relative to opponent goal. Ball bias shifts the shape slightly.
static func attack_slot(player: Player, ball_pos: Vector3) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return _gk_slot(player)

	var role := role_for(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var ball_x := clampf(ball_pos.x, -7.0, 7.0)
	var progress := clampf(absf(ball_pos.z) / 16.0, 0.0, 1.0)
	# Near the crease, CB tucks into a pivot-ish lane; wings stay wide.
	var use_pivot := progress > 0.55 and absf(ball_pos.z - goal_z) < 14.0

	var slot := Vector3.ZERO
	match role:
		Role.LEFT_WING:
			slot = Vector3(-7.2 + ball_x * 0.08, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			slot.x = clampf(slot.x, -8.6, -4.0)
		Role.RIGHT_WING:
			slot = Vector3(7.2 + ball_x * 0.08, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			slot.x = clampf(slot.x, 4.0, 8.6)
		Role.CENTER_BACK:
			if use_pivot:
				slot = Vector3(ball_x * 0.35, 0.0, goal_z - attack_sign * PIVOT_DEPTH_M)
				slot.x = clampf(slot.x, -2.8, 2.8)
			else:
				slot = Vector3(ball_x * 0.25, 0.0, goal_z - attack_sign * BACKCOURT_DEPTH_M)
				slot.x = clampf(slot.x, -3.5, 3.5)
		_:
			slot = player.start_position

	return _legalize_outfield(slot, player.team_id)


## Defense spacing: 3-across in front of own 6 m, ball-side bias.
static func defense_slot(player: Player, ball_pos: Vector3, carrier: Player = null) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return _gk_slot(player)

	var role := role_for(player)
	var defend_sign := -1.0 if player.team_id == 0 else 1.0 # toward own goal from midfield
	var own_goal_z := -20.0 if player.team_id == 0 else 20.0
	var threat := ball_pos
	if carrier:
		threat = carrier.global_position
	var threat_x := clampf(threat.x, -7.5, 7.5)

	var lane_x := 0.0
	match role:
		Role.LEFT_WING:
			lane_x = -4.6
		Role.RIGHT_WING:
			lane_x = 4.6
		_:
			lane_x = 0.0

	# Slide slightly toward the ball so the wall isn't static.
	lane_x = clampf(lane_x + threat_x * 0.22, -7.5, 7.5)
	var slot := Vector3(lane_x, 0.0, own_goal_z - defend_sign * DEFENSE_LINE_M)
	# When ball is mid-court, push the line up a bit.
	var mid_push := clampf((10.0 - absf(threat.z)) / 10.0, 0.0, 1.0)
	slot.z += (-defend_sign) * mid_push * 1.8
	slot.z = clampf(slot.z, -16.5, 16.5)
	return _legalize_outfield(slot, player.team_id)


## Kickoff / period restart shape (compact midfield).
static func kickoff_slot(player: Player, kickoff_team_id: int) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return player.start_position
	var role := role_for(player)
	var on_ball := player.team_id == kickoff_team_id
	var face := 1.0 if player.team_id == 0 else -1.0
	var z_base := -3.5 * face if on_ball else 4.5 * face
	var slot := Vector3.ZERO
	match role:
		Role.LEFT_WING:
			slot = Vector3(-4.5, 0.0, z_base)
		Role.RIGHT_WING:
			slot = Vector3(4.5, 0.0, z_base)
		_:
			slot = Vector3(0.0, 0.0, z_base + (1.2 * face if on_ball else 0.0))
	return _legalize_outfield(slot, player.team_id)


## Set-piece placement for Phase 2 restart codes.
## Returns { "taker": Vector3, "yaw": float } extras live on the caller's placement pass.
static func is_free_throw_code(code: String) -> bool:
	return code in ["traveling", "passive", "goal_area", "free_throw"]


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
	if player.is_goalkeeper:
		if code == "goal_throw" and player.team_id == awarding_team_id:
			return player.start_position
		# Non-taker GK stays home.
		return player.start_position

	var is_award := player.team_id == awarding_team_id
	var role := role_for(player)

	if code == "goal_throw":
		return _goal_throw_outfield(player, awarding_team_id, role, is_award)

	if code == "throw_in":
		return _throw_in_slot(player, spot, awarding_team_id, role, is_award, taker)

	# Free-throw family (traveling / passive / goal_area) — 9 m wall feel.
	if player == taker:
		var place := spot
		place.y = 0.0
		return _legalize_outfield(place, player.team_id)

	if is_award:
		return _free_throw_attack_slot(player, spot, awarding_team_id, role)
	return _free_throw_wall_slot(player, spot, awarding_team_id, role)


static func free_throw_taker_yaw(awarding_team_id: int, spot: Vector3) -> float:
	# Prefer facing the opponent goal; if near sideline, face inward a bit.
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
	var ball_pos := ball.global_position if ball else Vector3.ZERO
	var d_ball := candidate.global_position.distance_to(ball_pos)
	var carrier: Player = ball.carrier if ball else null

	# Free ball: prefer nearest teammate (especially outfield).
	if carrier == null:
		var score := 40.0 - d_ball
		if not candidate.is_goalkeeper:
			score += 6.0
		# Slight bonus if already near a sensible chase lane.
		return score

	# Own team has the ball: prefer open receiver (not the carrier).
	if carrier.team_id == candidate.team_id:
		if candidate == carrier:
			return 100.0 # Already on ball — only if somehow not controlled.
		if candidate.is_goalkeeper:
			return 5.0 - d_ball * 0.1
		# Open receiver: space from carrier + toward goal + not marked tightly.
		var to_carrier := candidate.global_position.distance_to(carrier.global_position)
		var goal := candidate.opponent_goal_point()
		var toward_goal := carrier.global_position.distance_to(goal) - candidate.global_position.distance_to(goal)
		var open := clampf(to_carrier, 2.0, 10.0) * 1.4
		var score := 28.0 + open + toward_goal * 1.8
		# Wings get a small spacing bonus when wide.
		var role := role_for(candidate)
		if role == Role.LEFT_WING or role == Role.RIGHT_WING:
			score += absf(candidate.global_position.x) * 0.35
		return score

	# Defending: best defender = nearest dangerous threat, outfield preferred.
	var threat_pos := carrier.global_position
	var d_threat := candidate.global_position.distance_to(threat_pos)
	var own_goal := candidate.own_goal_point()
	var goal_cover := 12.0 - candidate.global_position.distance_to(own_goal)
	var score_d := 35.0 - d_threat + goal_cover * 0.5
	if candidate.is_goalkeeper:
		# Only jump to GK when the ball is deep in our end.
		if absf(threat_pos.z - own_goal.z) < 10.0:
			score_d += 8.0
		else:
			score_d -= 12.0
	else:
		score_d += 4.0
	# Prefer ball-side lane match.
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
	# Keep home/away half preference soft — allow full court.
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
	var own_z := -16.0 * face if is_award else 6.0 * face
	# Award team spreads to receive the goal throw; opponents drop mid.
	var slot := Vector3.ZERO
	if is_award:
		match role:
			Role.LEFT_WING:
				slot = Vector3(-6.5, 0.0, -8.0 * face)
			Role.RIGHT_WING:
				slot = Vector3(6.5, 0.0, -8.0 * face)
			_:
				slot = Vector3(0.0, 0.0, -5.0 * face)
	else:
		match role:
			Role.LEFT_WING:
				slot = Vector3(-4.0, 0.0, 5.0 * face)
			Role.RIGHT_WING:
				slot = Vector3(4.0, 0.0, 5.0 * face)
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
			_:
				slot = Vector3(side * 2.0, 0.0, spot.z + face * 1.0)
	else:
		# Mark near throw-in lanes.
		match role:
			Role.LEFT_WING:
				slot = Vector3(side * 4.0, 0.0, spot.z - face * 1.5)
			Role.RIGHT_WING:
				slot = Vector3(side * 2.5, 0.0, spot.z + face * 2.0)
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
			# Prefer ball-side wing closer to the foul spot.
			if spot.x < -1.0:
				slot.z = lerpf(slot.z, spot.z, 0.25)
		Role.RIGHT_WING:
			slot = Vector3(7.0, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			if spot.x > 1.0:
				slot.z = lerpf(slot.z, spot.z, 0.25)
		_:
			# Second backcourt option behind the taker.
			slot = Vector3(clampf(spot.x * 0.3, -3.0, 3.0), 0.0, spot.z - attack_sign * 3.5)
	return _legalize_outfield(slot, player.team_id)


static func _free_throw_wall_slot(
	player: Player,
	spot: Vector3,
	awarding_team_id: int,
	role: Role
) -> Vector3:
	# Defending team forms a 9 m-style wall between taker and own goal.
	var defend_team := 1 - awarding_team_id
	var own_goal_z := -20.0 if defend_team == 0 else 20.0
	var to_goal := Vector3(0.0, 0.0, own_goal_z) - Vector3(spot.x, 0.0, spot.z)
	var dir := to_goal.normalized() if to_goal.length_squared() > 0.01 else Vector3(0, 0, signf(own_goal_z))
	var wall_anchor := Vector3(spot.x, 0.0, spot.z) + dir * WALL_GAP_M
	# Prefer sitting near the free-throw line if the foul is deep.
	var line_z := own_goal_z - signf(own_goal_z) * FREE_THROW_LINE_M
	if absf(spot.z - own_goal_z) < 12.0:
		wall_anchor.z = lerpf(wall_anchor.z, line_z, 0.55)

	var lateral := 0.0
	match role:
		Role.LEFT_WING:
			lateral = -2.4
		Role.RIGHT_WING:
			lateral = 2.4
		_:
			lateral = 0.0

	var side := Vector3(-dir.z, 0.0, dir.x)
	var slot := wall_anchor + side * lateral
	return _legalize_outfield(slot, player.team_id)
