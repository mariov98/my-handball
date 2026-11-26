extends RefCounted
class_name Formations

## Phase 4 tactics lite + Phase E shape presets + Phase G full outfield.
## On-court roster: LW / LB / CB / RB / RW / Pivot + GK (7).
## Attack Wide (3-3) vs Crash (2-4). Defense: 6-0 / 5-1 / 3-2-1 / Man (Wave 6).
## Wave 5: role-distinct slots, ball-side marking + help, off-ball show/cut/clear-out.
## Wave 6: attack vs man/zone, Kempa eligibility helpers.

enum Role { GK, LEFT_WING, LEFT_BACK, CENTER_BACK, RIGHT_BACK, RIGHT_WING, PIVOT }
## Attack shape presets (full-roster reading of 3-3 / 2-4).
enum AttackShape { WIDE, CRASH }
## Defense systems (R4.7): Flat=6-0, OneUp=5-1, layered 3-2-1, Individual=man.
enum DefenseShape { FLAT, ONE_UP, THREE_TWO_ONE, INDIVIDUAL }

const FREE_THROW_LINE_M := 9.0 ## Distance from goal end for 9 m-style wall / free throws.
const ATTACK_ARC_M := 9.2 ## Wings sit near the free-throw arc.
const BACKCOURT_DEPTH_M := 12.5 ## Backcourt depth from opponent goal.
const HALFBACK_DEPTH_M := 11.0 ## LB/RB depth (slightly ahead of CB).
const PIVOT_DEPTH_M := 7.2 ## Line player just outside 6 m.
const DEFENSE_LINE_M := 7.6 ## Flat defenders stand outside own 6 m.
const ONE_UP_DEPTH_M := 9.4 ## OneUp CB steps toward ~9 m on the ball.
const THREE_FRONT_DEPTH_M := 11.2 ## 3-2-1 front (CB) depth from own goal.
const THREE_MID_DEPTH_M := 9.2 ## 3-2-1 mid (LB/RB) depth.
const THREE_BACK_DEPTH_M := 7.5 ## 3-2-1 back wall (wings + pivot).
const WALL_GAP_M := 3.2 ## Min distance defenders keep from free-throw taker (~3 m / R3.1).
const RESTART_GAP_M := 3.0 ## Opponents held back on throw-in / goal-throw (Wave 4).
## Wave 5 occupation: keep attack width / defense lanes from collapsing into piles.
const MIN_TEAMMATE_SEP_M := 2.35
const CLEAR_OUT_SEP_M := 2.8
const MARK_PRESSURE_M := 1.45 ## Stand this far ball-side of the mark toward own goal.
const HELP_COVER_BLEND := 0.42 ## How hard weak-side help shades to cutter/pivot.
const BALL_SIDE_SLIDE_NEAR := 0.32 ## Ball-side lane slide (nearby roles).
const BALL_SIDE_SLIDE_FAR := 0.08 ## Weak-side holds width — no stack on ball.
## Wave 6: Kempa / 9 m shoot heuristics.
const KEMPA_GOAL_DEPTH_M := 9.0 ## Max distance from opponent goal for Kempa redirect.
const NINE_METER_SHOT_MIN_M := 8.2
const NINE_METER_SHOT_MAX_M := 12.5
const ZONE_GAP_BLEND := 0.55
const MAN_OPEN_SPACE_BLEND := 0.62
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
			return "5-1"
		DefenseShape.THREE_TWO_ONE:
			return "3-2-1"
		DefenseShape.INDIVIDUAL:
			return "Man"
		_:
			return "6-0"


## Cycle Home defense: 6-0 → 5-1 → 3-2-1 → Man → 6-0.
static func next_defense_shape(shape: int) -> int:
	match shape:
		DefenseShape.FLAT:
			return DefenseShape.ONE_UP
		DefenseShape.ONE_UP:
			return DefenseShape.THREE_TWO_ONE
		DefenseShape.THREE_TWO_ONE:
			return DefenseShape.INDIVIDUAL
		_:
			return DefenseShape.FLAT


static func is_zone_defense(shape: int) -> bool:
	return shape != DefenseShape.INDIVIDUAL


static func attack_shape_of(player: Player) -> AttackShape:
	if player == null:
		return AttackShape.WIDE
	return player.attack_shape as AttackShape


static func defense_shape_of(player: Player) -> DefenseShape:
	if player == null:
		return DefenseShape.FLAT
	return player.defense_shape as DefenseShape


## Opponent defense the attack is facing (synced by MatchController).
static func facing_defense_of(player: Player) -> DefenseShape:
	if player == null:
		return DefenseShape.FLAT
	return player.facing_defense_shape as DefenseShape


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

	# Wave 5: stronger width — wings hug sideline; backs stay in shooting belt lanes.
	var wing_x := 8.0 if shape == AttackShape.CRASH else 7.6
	var slot := Vector3.ZERO
	match role:
		Role.LEFT_WING:
			slot = Vector3(-wing_x + ball_x * 0.05, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			slot.x = clampf(slot.x, -8.7, -5.0)
		Role.RIGHT_WING:
			slot = Vector3(wing_x + ball_x * 0.05, 0.0, goal_z - attack_sign * ATTACK_ARC_M)
			slot.x = clampf(slot.x, 5.0, 8.7)
		Role.LEFT_BACK:
			var lb_depth := PIVOT_DEPTH_M + 2.4 if (shape == AttackShape.CRASH and deep_ball) else HALFBACK_DEPTH_M
			slot = Vector3(-4.6 + ball_x * 0.1, 0.0, goal_z - attack_sign * lb_depth)
			slot.x = clampf(slot.x, -7.0, -2.4)
		Role.RIGHT_BACK:
			var rb_depth := PIVOT_DEPTH_M + 2.4 if (shape == AttackShape.CRASH and deep_ball) else HALFBACK_DEPTH_M
			slot = Vector3(4.6 + ball_x * 0.1, 0.0, goal_z - attack_sign * rb_depth)
			slot.x = clampf(slot.x, 2.4, 7.0)
		Role.CENTER_BACK:
			if shape == AttackShape.CRASH and deep_ball:
				# Crash: CB can float behind the line as a shooting option.
				slot = Vector3(ball_x * 0.18, 0.0, goal_z - attack_sign * (PIVOT_DEPTH_M + 3.5))
				slot.x = clampf(slot.x, -2.2, 2.2)
			else:
				slot = Vector3(ball_x * 0.2, 0.0, goal_z - attack_sign * BACKCOURT_DEPTH_M)
				slot.x = clampf(slot.x, -2.4, 2.4)
		Role.PIVOT:
			# True line player — Crash holds the crease earlier; ball-side seal bias.
			var piv_depth := PIVOT_DEPTH_M
			if shape == AttackShape.WIDE and not deep_ball:
				piv_depth = PIVOT_DEPTH_M + 1.6
			slot = Vector3(ball_x * 0.55, 0.0, goal_z - attack_sign * piv_depth)
			slot.x = clampf(slot.x, -2.8, 2.8)
		_:
			slot = player.start_position

	return _legalize_outfield(slot, player.team_id)


## Defense spacing: 6-0 flat wall; 5-1 OneUp; 3-2-1 layers; Man (home lanes + mark chase).
## Wave 5: ball-side slide is distance-weighted so far-side lanes keep width (no stack).
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

	var lane_x := _defense_home_lane_x(role)
	var slide := BALL_SIDE_SLIDE_FAR
	var line_depth := DEFENSE_LINE_M
	var pressing_front := false

	if shape == DefenseShape.ONE_UP and role == Role.CENTER_BACK:
		# 5-1: CB presses up to ~9 m on the ball; others stay flat.
		slide = 0.55
		line_depth = ONE_UP_DEPTH_M
		lane_x = threat_x * 0.15
		pressing_front = true
	elif shape == DefenseShape.THREE_TWO_ONE:
		# Readable 3-2-1 layers without collapsing occupation (R4.7).
		match role:
			Role.CENTER_BACK:
				line_depth = THREE_FRONT_DEPTH_M
				slide = 0.48
				lane_x = threat_x * 0.2
				pressing_front = true
			Role.LEFT_BACK, Role.RIGHT_BACK:
				line_depth = THREE_MID_DEPTH_M
				slide = 0.28
			Role.LEFT_WING, Role.RIGHT_WING, Role.PIVOT:
				line_depth = THREE_BACK_DEPTH_M
				slide = BALL_SIDE_SLIDE_NEAR * 0.7
				if role == Role.PIVOT:
					lane_x = clampf(threat_x * 0.35, -1.8, 1.8)
			_:
				pass
		var lane_gap_321 := absf(lane_x - threat_x)
		var near_321 := clampf(1.0 - lane_gap_321 / 9.0, 0.0, 1.0)
		if not pressing_front:
			slide = lerpf(BALL_SIDE_SLIDE_FAR, slide, near_321)
	elif shape == DefenseShape.INDIVIDUAL:
		# Man: keep role lanes as recovery anchors; mark chase lives in defense_mark_slot.
		var lane_gap_m := absf(lane_x - threat_x)
		var near_m := clampf(1.0 - lane_gap_m / 9.0, 0.0, 1.0)
		slide = lerpf(0.12, 0.4, near_m)
		line_depth = DEFENSE_LINE_M + 0.6
		if role == Role.PIVOT:
			lane_x = clampf(threat_x * 0.45, -2.2, 2.2)
	else:
		# 6-0 flat: near ball-side roles slide harder; weak-side holds home lane (R4.2).
		var lane_gap := absf(lane_x - threat_x)
		var nearness := clampf(1.0 - lane_gap / 9.0, 0.0, 1.0)
		slide = lerpf(BALL_SIDE_SLIDE_FAR, BALL_SIDE_SLIDE_NEAR, nearness)
		if role == Role.PIVOT:
			slide = maxf(slide, 0.28)
			lane_x = clampf(threat_x * 0.4, -2.0, 2.0)

	lane_x = clampf(lane_x + threat_x * slide, -7.8, 7.8)
	var slot := Vector3(lane_x, 0.0, own_goal_z - defend_sign * line_depth)
	if not pressing_front:
		var mid_push := clampf((10.0 - absf(threat.z)) / 10.0, 0.0, 1.0)
		slot.z += (-defend_sign) * mid_push * 1.6
	else:
		var ball_push := clampf((absf(threat.z) - 4.0) / 10.0, -0.4, 1.0)
		slot.z += (-defend_sign) * ball_push * 1.2
	slot.z = clampf(slot.z, -16.5, 16.5)
	return _legalize_outfield(slot, player.team_id)


static func _defense_home_lane_x(role: Role) -> float:
	match role:
		Role.LEFT_WING:
			return -6.2
		Role.LEFT_BACK:
			return -3.7
		Role.CENTER_BACK:
			return 0.0
		Role.PIVOT:
			return 0.0
		Role.RIGHT_BACK:
			return 3.7
		Role.RIGHT_WING:
			return 6.2
		_:
			return 0.0


## Wave 5 R4.4: same-role man-mark lite (switch/stay handled in defense_mark_slot).
static func paired_attack_role(def_role: Role) -> Role:
	match def_role:
		Role.LEFT_WING, Role.LEFT_BACK, Role.CENTER_BACK, Role.RIGHT_BACK, Role.RIGHT_WING, Role.PIVOT:
			return def_role
		_:
			return Role.CENTER_BACK


## Pick the opponent this defender should mark (same role preferred; nearest fallback).
static func find_mark_target(defender: Player, opponents: Array) -> Player:
	if defender == null or defender.is_goalkeeper:
		return null
	var want := paired_attack_role(role_for(defender))
	var same_role: Player = null
	var nearest: Player = null
	var nearest_d := INF
	for item in opponents:
		if not (item is Player):
			continue
		var opp := item as Player
		if opp == null or opp.is_goalkeeper or opp.excluded or opp.on_bench:
			continue
		if opp.team_id == defender.team_id:
			continue
		var d := defender.global_position.distance_squared_to(opp.global_position)
		if role_for(opp) == want:
			same_role = opp
		if d < nearest_d:
			nearest_d = d
			nearest = opp
	return same_role if same_role else nearest


## Most dangerous help threat: opponent pivot or deep cutter near own goal (not the primary mark).
static func find_help_threat(
	defender: Player,
	opponents: Array,
	mark: Player,
	ball_pos: Vector3
) -> Player:
	if defender == null:
		return null
	var own_goal_z := -20.0 if defender.team_id == 0 else 20.0
	var best: Player = null
	var best_score := -INF
	for item in opponents:
		if not (item is Player):
			continue
		var opp := item as Player
		if opp == null or opp == mark or opp.is_goalkeeper or opp.excluded or opp.on_bench:
			continue
		if opp.team_id == defender.team_id:
			continue
		var role := role_for(opp)
		var dist_goal := absf(opp.global_position.z - own_goal_z)
		var ball_side := (
			1.0
			if (signf(opp.global_position.x) == signf(ball_pos.x) or absf(ball_pos.x) < 1.2)
			else 0.35
		)
		var score := (18.0 - dist_goal) * ball_side
		if role == Role.PIVOT:
			score += 6.0
		elif is_wing(role) and dist_goal < 11.0:
			score += 3.5
		elif is_backcourt(role) and dist_goal < 10.0:
			score += 2.0
		if score > best_score:
			best_score = score
			best = opp
	# Only help if the threat is actually near the crease / ball-side.
	if best == null or best_score < 4.0:
		return null
	return best


## Wave 5 marking slot: ball-side pressure on mark + help/cover shade (lite switch/stay).
static func defense_mark_slot(
	player: Player,
	ball_pos: Vector3,
	carrier: Player,
	mark: Player,
	help: Player = null
) -> Vector3:
	var base := defense_slot(player, ball_pos, carrier)
	if player == null or player.is_goalkeeper:
		return base
	var own_goal := Vector3(0.0, 0.0, -20.0 if player.team_id == 0 else 20.0)
	var role := role_for(player)
	var shape := defense_shape_of(player)

	# Primary pressure: stand between mark and own goal (ball-side).
	if mark != null:
		var mark_pos := Vector3(mark.global_position.x, 0.0, mark.global_position.z)
		var to_goal := own_goal - mark_pos
		to_goal.y = 0.0
		var press := mark_pos
		if to_goal.length_squared() > 0.01:
			press = mark_pos + to_goal.normalized() * MARK_PRESSURE_M
		# Lite stay: weak-side mark keeps more of the home lane.
		var ball_x := ball_pos.x if carrier == null else carrier.global_position.x
		var same_side := signf(mark_pos.x) == signf(ball_x) or absf(ball_x) < 1.5
		var blend := 0.72 if same_side else 0.28
		# Individual: stay glued to the mark (R4.7 man).
		if shape == DefenseShape.INDIVIDUAL:
			blend = 0.92 if same_side else 0.78
		# Carrier mark → hard close-out.
		if carrier != null and mark == carrier:
			blend = 0.92 if shape == DefenseShape.INDIVIDUAL else 0.85
			# OneUp / 3-2-1 front already presses; keep a touch of base depth.
			if (
				(shape == DefenseShape.ONE_UP or shape == DefenseShape.THREE_TWO_ONE)
				and role == Role.CENTER_BACK
			):
				blend = 0.65
		# Lite switch: if assigned mark crossed far past our lane toward ball, chase harder.
		var home_lane := _defense_home_lane_x(role)
		if absf(mark_pos.x - home_lane) > 3.5 and same_side:
			blend = maxf(blend, 0.7 if shape != DefenseShape.INDIVIDUAL else 0.88)
		base.x = lerpf(base.x, press.x, blend)
		base.z = lerpf(base.z, press.z, blend * 0.85)
		# Man defense: help is lighter — stay with your man.
		if shape == DefenseShape.INDIVIDUAL:
			help = null

	# Help / cover: shade toward cutter or pivot without abandoning the wall.
	if help != null and (carrier == null or mark != carrier):
		var help_pos := Vector3(help.global_position.x, 0.0, help.global_position.z)
		var help_cover := help_pos.lerp(own_goal, 0.22)
		var help_blend := HELP_COVER_BLEND
		if role_for(help) == Role.PIVOT:
			help_blend = 0.55
		# Ball-side helpers shade more; weak-side gives soft cover only.
		var hx := help_pos.x
		var bx := ball_pos.x if carrier == null else carrier.global_position.x
		if signf(hx) != signf(bx) and absf(bx) > 2.0:
			help_blend *= 0.45
		base.x = lerpf(base.x, help_cover.x, help_blend)
		base.z = lerpf(base.z, help_cover.z, help_blend * 0.7)

	base.z = clampf(base.z, -16.5, 16.5)
	return _legalize_outfield(base, player.team_id)


## Carrier drive target — role-distinct (not one generic goal chase). R4.3
static func attack_drive_slot(player: Player, ball_pos: Vector3) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return _gk_slot(player)
	var role := role_for(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var ball_x := clampf(ball_pos.x, -7.0, 7.0)
	var slot := Vector3.ZERO
	match role:
		Role.LEFT_WING:
			# Wing corridor finish — stay wide then cut toward near post.
			slot = Vector3(-7.2 + ball_x * 0.08, 0.0, goal_z - attack_sign * 7.4)
			slot.x = clampf(slot.x, -8.5, -4.5)
		Role.RIGHT_WING:
			slot = Vector3(7.2 + ball_x * 0.08, 0.0, goal_z - attack_sign * 7.4)
			slot.x = clampf(slot.x, 4.5, 8.5)
		Role.LEFT_BACK:
			slot = Vector3(-3.8, 0.0, goal_z - attack_sign * 9.2)
			slot.x = clampf(slot.x + ball_x * 0.1, -6.5, -1.5)
		Role.RIGHT_BACK:
			slot = Vector3(3.8, 0.0, goal_z - attack_sign * 9.2)
			slot.x = clampf(slot.x + ball_x * 0.1, 1.5, 6.5)
		Role.CENTER_BACK:
			slot = Vector3(ball_x * 0.25, 0.0, goal_z - attack_sign * 10.0)
			slot.x = clampf(slot.x, -2.6, 2.6)
		Role.PIVOT:
			slot = Vector3(ball_x * 0.5, 0.0, goal_z - attack_sign * (PIVOT_DEPTH_M + 0.4))
			slot.x = clampf(slot.x, -2.4, 2.4)
		_:
			slot = Vector3(0.0, 0.0, goal_z - attack_sign * 10.0)
	return _legalize_outfield(slot, player.team_id)


## Wave 5 R4.5: cut toward space / goal from the show lane (role-timed).
static func cut_slot(player: Player, ball_pos: Vector3, carrier: Player = null) -> Vector3:
	var base := show_for_pass_slot(player, ball_pos)
	if player == null or player.is_goalkeeper:
		return base
	var role := role_for(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var car_x := ball_pos.x
	if carrier:
		car_x = carrier.global_position.x
	match role:
		Role.LEFT_WING:
			# Cut in from corner toward near-post seam.
			base.x = lerpf(base.x, -3.2, 0.55)
			base.z = lerpf(base.z, goal_z - attack_sign * 7.0, 0.45)
		Role.RIGHT_WING:
			base.x = lerpf(base.x, 3.2, 0.55)
			base.z = lerpf(base.z, goal_z - attack_sign * 7.0, 0.45)
		Role.LEFT_BACK:
			base.x = lerpf(base.x, -1.4, 0.4)
			base.z = lerpf(base.z, goal_z - attack_sign * 8.5, 0.5)
		Role.RIGHT_BACK:
			base.x = lerpf(base.x, 1.4, 0.4)
			base.z = lerpf(base.z, goal_z - attack_sign * 8.5, 0.5)
		Role.CENTER_BACK:
			# Playmaker flash cut into a gap opposite the ball.
			var cut_x := (-signf(car_x) * 2.0) if absf(car_x) > 1.0 else 1.6
			base.x = lerpf(base.x, cut_x, 0.5)
			base.z = lerpf(base.z, goal_z - attack_sign * 9.5, 0.35)
		Role.PIVOT:
			# Short seal/roll toward ball-side post.
			base.x = lerpf(base.x, clampf(car_x * 0.7, -2.4, 2.4), 0.6)
			base.z = lerpf(base.z, goal_z - attack_sign * PIVOT_DEPTH_M, 0.4)
		_:
			pass
	return _legalize_outfield(base, player.team_id)


## Pivot seal / screen lite: stand between nearest defender and the goal/ball lane.
static func pivot_seal_slot(
	player: Player,
	ball_pos: Vector3,
	defender: Player = null
) -> Vector3:
	var base := attack_slot(player, ball_pos)
	if player == null or role_for(player) != Role.PIVOT:
		return base
	if defender == null:
		return show_for_pass_slot(player, ball_pos)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal := Vector3(0.0, 0.0, 20.0 * attack_sign)
	var def_pos := Vector3(defender.global_position.x, 0.0, defender.global_position.z)
	# Seal: between defender and goal, slightly ball-side.
	var seal := def_pos.lerp(goal, 0.28)
	seal.x = lerpf(seal.x, ball_pos.x * 0.45, 0.35)
	seal.x = clampf(seal.x, -2.8, 2.8)
	# Keep the seal just outside 6 m toward the attack goal.
	var seal_z_near := goal.z - attack_sign * 6.5
	var seal_z_far := goal.z - attack_sign * 9.0
	seal.z = clampf(seal.z, minf(seal_z_near, seal_z_far), maxf(seal_z_near, seal_z_far))
	# Prefer seal over raw attack slot when Crash; Wide still seals lightly.
	var blend := 0.7 if attack_shape_of(player) == AttackShape.CRASH else 0.45
	base = base.lerp(seal, blend)
	return _legalize_outfield(base, player.team_id)


## Clear-out when a teammate (or carrier) crowds this slot. R4.5
static func clear_out_slot(
	player: Player,
	ball_pos: Vector3,
	crowded_from: Vector3,
	base_slot: Vector3 = Vector3.ZERO
) -> Vector3:
	var slot := base_slot
	if slot == Vector3.ZERO:
		slot = attack_slot(player, ball_pos)
	if player == null:
		return slot
	var role := role_for(player)
	var me := Vector3(slot.x, 0.0, slot.z)
	var other := Vector3(crowded_from.x, 0.0, crowded_from.z)
	var delta := me - other
	delta.y = 0.0
	if delta.length() < 0.15:
		# Degenerate — push toward role home width.
		var side := 1.0
		if role == Role.LEFT_WING or role == Role.LEFT_BACK:
			side = -1.0
		elif role == Role.RIGHT_WING or role == Role.RIGHT_BACK:
			side = 1.0
		elif role == Role.CENTER_BACK or role == Role.PIVOT:
			side = (-signf(other.x)) if absf(other.x) > 0.4 else 1.0
		delta = Vector3(side, 0.0, 0.0)
	var push := delta.normalized() * CLEAR_OUT_SEP_M
	slot = other + push
	# Prefer clearing to role-typical width rather than through the middle.
	match role:
		Role.LEFT_WING:
			slot.x = minf(slot.x, -4.5)
		Role.RIGHT_WING:
			slot.x = maxf(slot.x, 4.5)
		Role.LEFT_BACK:
			slot.x = minf(slot.x, -2.0)
		Role.RIGHT_BACK:
			slot.x = maxf(slot.x, 2.0)
		Role.CENTER_BACK:
			slot.z += (-1.0 if player.team_id == 0 else 1.0) * 1.2
		Role.PIVOT:
			slot.x = clampf(slot.x, -2.6, 2.6)
		_:
			pass
	return _legalize_outfield(slot, player.team_id)


## Soft anti-pileup: nudge slot away from nearby teammates. R4.2
static func apply_teammate_spacing(
	slot: Vector3,
	player: Player,
	teammates: Array,
	min_sep: float = MIN_TEAMMATE_SEP_M
) -> Vector3:
	if player == null:
		return slot
	var out := Vector3(slot.x, 0.0, slot.z)
	# Two passes so multi-body stacks still clear the minimum gap.
	for _pass in range(2):
		for item in teammates:
			if not (item is Player):
				continue
			var mate := item as Player
			if mate == null or mate == player or mate.is_goalkeeper or mate.excluded or mate.on_bench:
				continue
			var mate_xz := Vector3(mate.global_position.x, 0.0, mate.global_position.z)
			var delta := out - mate_xz
			var d := delta.length()
			if d >= min_sep:
				continue
			if d < 0.05:
				var side := (
					1.0
					if (
						role_for(player) == Role.RIGHT_WING
						or role_for(player) == Role.RIGHT_BACK
					)
					else -1.0
				)
				if role_for(player) == Role.CENTER_BACK or role_for(player) == Role.PIVOT:
					side = 0.0
					delta = Vector3(0.0, 0.0, -1.0 if player.team_id == 0 else 1.0)
				else:
					delta = Vector3(side, 0.0, 0.0)
				d = 0.05
			var need := min_sep - d
			out += delta.normalized() * need
	return _legalize_outfield(out, player.team_id)


## Unified off-ball support: show / cut / pivot seal / clear-out. R4.5
## Wave 6: optional opponents list biases man open-space / zone gap occupation.
static func support_attack_slot(
	player: Player,
	ball_pos: Vector3,
	carrier: Player,
	teammates: Array = [],
	screen_defender: Player = null,
	want_cut: bool = false,
	opponents: Array = []
) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.is_goalkeeper:
		return _gk_slot(player)
	var role := role_for(player)
	var pivot: Player = null
	for item in teammates:
		if item is Player and role_for(item as Player) == Role.PIVOT:
			pivot = item as Player
			break
	var slot: Vector3
	if role == Role.PIVOT:
		slot = pivot_seal_slot(player, ball_pos, screen_defender)
	elif want_cut and role != Role.GK:
		slot = cut_slot(player, ball_pos, carrier)
	else:
		slot = show_for_pass_slot(player, ball_pos, pivot, screen_defender)

	# Clear-out when stacked on the carrier or a teammate.
	if carrier != null:
		var cpos := carrier.global_position
		if Vector3(slot.x - cpos.x, 0.0, slot.z - cpos.z).length() < CLEAR_OUT_SEP_M * 0.85:
			slot = clear_out_slot(player, ball_pos, cpos, slot)
	for item in teammates:
		if not (item is Player):
			continue
		var mate := item as Player
		if mate == null or mate == player or mate == carrier:
			continue
		if mate.is_goalkeeper or mate.excluded or mate.on_bench:
			continue
		var mpos := mate.global_position
		if Vector3(slot.x - mpos.x, 0.0, slot.z - mpos.z).length() < MIN_TEAMMATE_SEP_M:
			slot = clear_out_slot(player, ball_pos, mpos, slot)
			break

	slot = apply_teammate_spacing(slot, player, teammates)
	# Wave 6: bias slot for man vs zone attack styles.
	slot = apply_attack_style_bias(slot, player, ball_pos, carrier, teammates, opponents)
	return _legalize_outfield(slot, player.team_id)


## Wave 6 R4.6: nudge occupation for man (open space) vs zone (gaps / 9 m belt).
static func apply_attack_style_bias(
	slot: Vector3,
	player: Player,
	ball_pos: Vector3,
	carrier: Player,
	teammates: Array = [],
	opponents: Array = []
) -> Vector3:
	if player == null or player.is_goalkeeper:
		return slot
	var facing := facing_defense_of(player)
	if facing == DefenseShape.INDIVIDUAL:
		return man_open_space_slot(player, ball_pos, slot, opponents)
	return zone_gap_slot(player, ball_pos, carrier, slot, opponents, teammates)


## Vs man: prefer open pockets away from nearest markers (R4.6a).
static func man_open_space_slot(
	player: Player,
	ball_pos: Vector3,
	base_slot: Vector3,
	opponents: Array = []
) -> Vector3:
	var slot := Vector3(base_slot.x, 0.0, base_slot.z)
	if player == null:
		return slot
	var nearest: Player = null
	var nearest_d := INF
	for item in opponents:
		if not (item is Player):
			continue
		var opp := item as Player
		if opp == null or opp.is_goalkeeper or opp.excluded or opp.on_bench:
			continue
		if opp.team_id == player.team_id:
			continue
		var d := slot.distance_squared_to(Vector3(opp.global_position.x, 0.0, opp.global_position.z))
		if d < nearest_d:
			nearest_d = d
			nearest = opp
	if nearest == null:
		# No roster passed — bias slightly away from ball X so lanes stay clear.
		var side := -signf(ball_pos.x) if absf(ball_pos.x) > 1.0 else 1.0
		slot.x += side * 0.9
		return _legalize_outfield(slot, player.team_id)
	var away := slot - Vector3(nearest.global_position.x, 0.0, nearest.global_position.z)
	away.y = 0.0
	if away.length_squared() < 0.04:
		away = Vector3(-signf(nearest.global_position.x + 0.01), 0.0, 0.0)
	slot = slot.lerp(slot + away.normalized() * 1.8, MAN_OPEN_SPACE_BLEND)
	return _legalize_outfield(slot, player.team_id)


## Vs zone: occupy gaps between defenders; reverse/overload bias (R4.6b).
static func zone_gap_slot(
	player: Player,
	ball_pos: Vector3,
	carrier: Player,
	base_slot: Vector3,
	opponents: Array = [],
	_teammates: Array = []
) -> Vector3:
	var slot := Vector3(base_slot.x, 0.0, base_slot.z)
	if player == null:
		return slot
	var role := role_for(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	# Collect opponent X sorted for gap finding.
	var xs: Array = []
	for item in opponents:
		if not (item is Player):
			continue
		var opp := item as Player
		if opp == null or opp.is_goalkeeper or opp.excluded or opp.on_bench:
			continue
		if opp.team_id == player.team_id:
			continue
		xs.append(opp.global_position.x)
	xs.sort()
	var gap_x := slot.x
	if xs.size() >= 2:
		var best_gap := -1.0
		for i in range(xs.size() - 1):
			var a: float = xs[i]
			var b: float = xs[i + 1]
			var mid := (a + b) * 0.5
			var gap := b - a
			# Prefer gaps near this role's home lane.
			var role_pref := absf(mid - slot.x)
			var score := gap - role_pref * 0.35
			if score > best_gap:
				best_gap = score
				gap_x = mid
	# Ball reversal: weak-side wings/backs hold width opposite the ball.
	var car_x := ball_pos.x
	if carrier:
		car_x = carrier.global_position.x
	if is_wing(role) or role == Role.LEFT_BACK or role == Role.RIGHT_BACK:
		if signf(slot.x) != signf(car_x) and absf(car_x) > 1.5:
			slot.x = lerpf(slot.x, signf(slot.x) * maxf(absf(slot.x), 5.5), 0.35)
	# Backs sit in the 9 m shooting belt vs zone.
	if is_backcourt(role):
		slot.z = lerpf(slot.z, goal_z - attack_sign * FREE_THROW_LINE_M, 0.28)
	slot.x = lerpf(slot.x, gap_x, ZONE_GAP_BLEND * 0.55)
	return _legalize_outfield(slot, player.team_id)


## Carrier drive biased by facing defense (drive-and-kick vs man; 9 m belt vs zone).
static func attack_drive_for_style(player: Player, ball_pos: Vector3) -> Vector3:
	var drive := attack_drive_slot(player, ball_pos)
	if player == null:
		return drive
	var facing := facing_defense_of(player)
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var role := role_for(player)
	if facing == DefenseShape.INDIVIDUAL:
		# Drive hard at the 1v1 — push deeper toward goal.
		drive.z = lerpf(drive.z, goal_z - attack_sign * 7.8, 0.4)
		return _legalize_outfield(drive, player.team_id)
	# Zone: backs hold the 9 m line for long-range looks.
	if is_backcourt(role):
		drive.z = lerpf(drive.z, goal_z - attack_sign * FREE_THROW_LINE_M, 0.55)
		drive.x = lerpf(drive.x, clampf(ball_pos.x * 0.3, -4.5, 4.5), 0.25)
	return _legalize_outfield(drive, player.team_id)


## True when a backcourt carrier should prefer a ~9 m shot vs a closed zone lane (R4.6b).
static func should_take_nine_meter_shot(
	player: Player,
	goal_dist: float,
	under_pressure: bool,
	pass_available: bool
) -> bool:
	if player == null or not is_backcourt(role_for(player)):
		return false
	if facing_defense_of(player) == DefenseShape.INDIVIDUAL:
		return false
	if goal_dist < NINE_METER_SHOT_MIN_M or goal_dist > NINE_METER_SHOT_MAX_M:
		return false
	# Closed lane: pressed with no clean pass, or zone and already in the belt.
	if under_pressure and not pass_available:
		return true
	if not under_pressure and goal_dist <= FREE_THROW_LINE_M + 1.5:
		return true
	return false


## Openness of a shot corridor toward the attacked goal mouth (1 = clear).
static func shot_lane_openness(
	from_pos: Vector3,
	team_id: int,
	opponents: Array,
	corridor_half: float = 1.25
) -> float:
	var goal_z := 19.5 if team_id == 0 else -19.5
	var goal := Vector3(0.0, 0.0, goal_z)
	return pass_lane_openness(from_pos, goal, opponents, corridor_half)


## Planar openness of a pass lane (1 = clear, 0 = contested). R4.6a.
static func pass_lane_openness(
	from_pos: Vector3,
	to_pos: Vector3,
	opponents: Array,
	corridor_half: float = 1.15
) -> float:
	var a := Vector3(from_pos.x, 0.0, from_pos.z)
	var b := Vector3(to_pos.x, 0.0, to_pos.z)
	var ab := b - a
	var len_ab := ab.length()
	if len_ab < 0.5:
		return 0.0
	var dir := ab / len_ab
	var worst := 1.0
	for item in opponents:
		if not (item is Player):
			continue
		var opp := item as Player
		if opp == null or opp.is_goalkeeper or opp.excluded or opp.on_bench:
			continue
		var p := Vector3(opp.global_position.x, 0.0, opp.global_position.z)
		var ap := p - a
		var t := clampf(ap.dot(dir), 0.15, len_ab - 0.15)
		var closest := a + dir * t
		var lateral := p.distance_to(closest)
		if lateral < corridor_half:
			worst = minf(worst, lateral / corridor_half)
	return clampf(worst, 0.0, 1.0)


## Near opponent crease for Kempa approach / finish (R4.8).
static func kempa_near_crease(player: Player) -> bool:
	if player == null or player.is_goalkeeper or player.on_bench or player.excluded:
		return false
	var attack_sign := 1.0 if player.team_id == 0 else -1.0
	var goal_z := 20.0 * attack_sign
	var dist := absf(player.global_position.z - goal_z)
	if dist > KEMPA_GOAL_DEPTH_M:
		return false
	# Must be on the attack half / approaching the crease.
	if (player.global_position.z * attack_sign) < 8.0:
		return false
	return true


## Kempa: airborne attacker near the opponent crease can redirect (R4.8).
static func kempa_eligible(player: Player, airborne: bool) -> bool:
	if not airborne:
		return false
	return kempa_near_crease(player)


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
	return code in [
		"traveling", "passive", "goal_area", "free_throw",
		"hold", "double_dribble", "foul"
	]


static func is_seven_meter_code(code: String) -> bool:
	return code == "seven_m"


## True when opponents must observe the ~3 m wall / hold-back (R3.1 cue).
## Free-throw family + throw-in / goal-throw. Not 7 m (different clear-out).
static func uses_three_meter_wall(code: String) -> bool:
	return three_meter_wall_gap(code) > 0.0


## Planar gap the wall cue should draw (0 = no 3 m wall for this restart).
static func three_meter_wall_gap(code: String) -> float:
	if is_free_throw_code(code):
		return WALL_GAP_M
	if code == "throw_in" or code == "goal_throw":
		return RESTART_GAP_M
	return 0.0


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
		# 7 m: defending GK stands on the 4 m restraining line (R2.7).
		if is_seven_meter_code(code) and player.team_id != awarding_team_id:
			var four := Court.four_meter_spot(player.team_id)
			four.y = 0.0
			return four
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
		# Defending outfield: stay ~3 m+ from the goal-throw taker / crease (R3.1).
		match role:
			Role.LEFT_WING:
				slot = Vector3(-6.5, 0.0, 6.5 * face)
			Role.RIGHT_WING:
				slot = Vector3(6.5, 0.0, 6.5 * face)
			Role.LEFT_BACK:
				slot = Vector3(-4.0, 0.0, 5.5 * face)
			Role.RIGHT_BACK:
				slot = Vector3(4.0, 0.0, 5.5 * face)
			Role.PIVOT:
				slot = Vector3(0.0, 0.0, 4.5 * face)
			_:
				slot = Vector3(0.0, 0.0, 5.0 * face)
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
		# Opponents held ~3 m off the throw-in spot (R3.1 wall consistency).
		match role:
			Role.LEFT_WING:
				slot = Vector3(side * 5.5, 0.0, spot.z - face * 2.5)
			Role.RIGHT_WING:
				slot = Vector3(side * 3.5, 0.0, spot.z + face * 3.0)
			Role.LEFT_BACK:
				slot = Vector3(side * 4.2, 0.0, spot.z - face * 0.5)
			Role.RIGHT_BACK:
				slot = Vector3(side * 3.2, 0.0, spot.z + face * 1.5)
			Role.PIVOT:
				slot = Vector3(side * 2.8, 0.0, spot.z - face * 1.5)
			_:
				slot = Vector3(side * 3.5, 0.0, spot.z + face * 0.5)
		slot = _hold_back_from_spot(slot, spot, RESTART_GAP_M)
	return _legalize_outfield(slot, player.team_id)


## Push `slot` away from `spot` until planar gap ≥ `min_gap` (3 m wall / restart).
static func _hold_back_from_spot(slot: Vector3, spot: Vector3, min_gap: float) -> Vector3:
	var delta := Vector3(slot.x - spot.x, 0.0, slot.z - spot.z)
	var d := delta.length()
	if d >= min_gap:
		return slot
	if d < 0.001:
		# Degenerate — push inward from sideline / toward midfield.
		var inward := -1.0 if spot.x > 0.0 else 1.0
		return Vector3(spot.x + inward * min_gap, slot.y, spot.z)
	var pushed := Vector3(spot.x, slot.y, spot.z) + delta.normalized() * min_gap
	return pushed


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
	# Enforce ≥ ~3 m from the taker even after 9 m line blend (R3.1).
	slot = _hold_back_from_spot(slot, spot, WALL_GAP_M)
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
